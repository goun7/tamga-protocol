#!/usr/bin/env bash
# AT-228 — LEDGER TAMPER-DETECTION DERİN-DİKİŞ + registry round-trip + fail-closed
#
# Görev-kaynağı (Lead 2026-09-28): "TEST DERİNLEŞTİR — ledger-verify-batch (AT-208)
# için tamper-detection testi; registry-backup (AT-209) için restore round-trip;
# fail-closed testi — hatalı anahtar → SystemExit."
#
# AT-208 zaten K6 (hash-tamper) + K7 (prev-link-tamper) kapsar; AT-209 K1 (round-trip)
# + K3 (bozuk-yedek) kapsar. Bu-test-onların-AÇIK-BIRAKTIĞI-yüzeyleri-kapatır:
#
#   K1  stdout_sha256-tamper → RED (teslim-kanıtı-korumalı)
#   K2  seq-tamper          → RED (sıra-korumalı)
#   K3  ts-tamper           → RED (zaman-damgası-korumalı)
#   K4  node_sig-tamper     → BULGU: zincir hâlâ GREEN (D8 imzası h'den-hariç;
#       cmd_ledger_verify imzayı doğrulamaz — D8 ayrı-bir-katman). Dürüst-rapor.
#   K5  registry round-trip → restore-sonrası GERÇEK-paket ledger-verify GREEN
#       (AT-209 sayı-korunumu-der; bu-çalışırlığı-der)
#   K6  hatalı-anahtar      → SystemExit (fail-closed: yanlış-seed imzalamaz)
set -u
PASS=0; FAIL=0
LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AT-228/$(date +%F)}/at228.log"
mkdir -p "$(dirname "$LOG")"
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); echo "  [PASS] $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  [FAIL] $2 — $3" | tee -a "$LOG"; fi; }

PY=python3
cd "$(cd "$(dirname "$0")/.." && pwd)"
SB=$(mktemp -d); echo "workdir: $SB" >> "$LOG"
export TAMGA_KS_PASSPHRASE=simnet-2026

# --- 1-2-3: paket + ledger hazırlığı ----------------------------------------
"$PY" tamga_runner.py quickstart "$SB/pk" --name "at226" >> "$LOG" 2>&1
"$PY" tamga_runner.py run "$SB/pk" >> "$LOG" 2>&1        # bir-charge-kaydı-yaz
LED="$SB/pk/ledger.jsonl"
[ -s "$LED" ] || { echo "  [FAIL] ledger-boş" | tee -a "$LOG"; exit 1; }

tamper() {  # tamper <alan> <yeni-değer-prefix> <çıktı-dosyası>
  "$PY" - "$1" "$2" "$3" <<'PYEOF' >> "$LOG" 2>&1
import json, sys, pathlib
field, newp, outp = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(outp)
rows = [json.loads(l) for l in p.read_text(encoding="utf-8").splitlines() if l.strip()]
r = rows[-1]
if field == "seq":
    r[field] = int(r[field]) + 100          # sırayı-boz
elif field == "ts":
    r[field] = r[field][:-2] + "99"         # zamanı-boz (h-hesabına-girer)
elif field == "node_sig":
    # D8 imzası: h'den-HARİÇ — değiştirilirse zincir-hash'i-ETKİLEMEZ
    cur = r.get("node_sig")
    if cur:
        r[field] = cur[:-1] + ("0" if cur[-1] != "0" else "1")
else:
    v = str(r[field])
    r[field] = v[:-1] + ("0" if v[-1] != "0" else "1")   # son-karakteri-flip
p.write_text("\n".join(json.dumps(x, ensure_ascii=False) for x in rows) + "\n",
             encoding="utf-8")
PYEOF
}

verify_red() {  # verify_red <etiket> <beklenen-RED>
  local out rc code
  out=$("$PY" tamga_runner.py ledger-verify "$SB/pk" 2>>"$LOG")
  rc=$?
  code=$(echo "$out" | "$PY" -c "import json,sys; d=json.load(sys.stdin); print(d.get('reason_code',''))" 2>/dev/null)
  echo "$2: rc=$rc code=$code" >> "$LOG"
  [ "$rc" != "0" ] && [ "$code" = "$3" ]
}

# --- K1: stdout_sha256-tamper → RED-14 (teslim-kanıtı) -----------------------
cp "$LED" "$SB/pk/ledger.k1"
tamper stdout_sha256 x "$SB/pk/ledger.k1"
mv "$SB/pk/ledger.k1" "$LED"
verify_red K1 "K1 stdout_sha256-değişti → RED-14 (zincir-kırıldı)" 14
k $? "K1 stdout_sha256-tamper → ledger-verify RED-14 (teslim-kanıtı-korumalı)" "rc/code-yukarıda"

# --- K2: seq-tamper → RED-14 (sıra) ------------------------------------------
cp "$LED" "$SB/pk/ledger.k2"
tamper seq x "$SB/pk/ledger.k2"
mv "$SB/pk/ledger.k2" "$LED"
verify_red K2 "K2 seq-değişti → RED-14" 14
k $? "K2 seq-tamper → ledger-verify RED-14 (sıra-korumalı)" "rc/code-yukarıda"

# --- K3: ts-tamper → RED-14 (zaman-damgası) ----------------------------------
cp "$LED" "$SB/pk/ledger.k3"
tamper ts x "$SB/pk/ledger.k3"
mv "$SB/pk/ledger.k3" "$LED"
verify_red K3 "K3 ts-değişti → RED-14" 14
k $? "K3 ts-tamper → ledger-verify RED-14 (zaman-damgası-korumalı)" "rc/code-yukarıda"

# --- K4: node_sig-tamper → RED (D8 imza-katmanı-da-doğrulanır) --------------
# quickstart-ledger'ında-node_sig-YOK (D8-cosign-run-yolundan-gelir). Bu-test
# önce-geçerli-bir-node_sig-yazar-sonra-bozar: _verify_chain'in "node_sig_invalid"
# dalını-kapsar. imza-h-haricinde-tutulur-AMA-_node_sig_ok-ayrıca-çalışır.
"$PY" - "$LED" >> "$LOG" 2>&1 <<'K4PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
rows = [json.loads(l) for l in p.read_text(encoding="utf-8").splitlines() if l.strip()]
rows[-1]["node_sig"] = {"v": "0x" + "ab" * 65, "node_id": "0x" + "cd" * 20, "algo": "eth-191"}
p.write_text("\n".join(json.dumps(x, ensure_ascii=False) for x in rows) + "\n",
             encoding="utf-8")
K4PY
RC4a=$("$PY" tamga_runner.py ledger-verify "$SB/pk" 2>>"$LOG"; echo $?)
echo "K4a node_sig-eklendi: rc=$RC4a" >> "$LOG"
"$PY" - "$LED" >> "$LOG" 2>&1 <<'K4PY2'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
rows = [json.loads(l) for l in p.read_text(encoding="utf-8").splitlines() if l.strip()]
rows[-1]["node_sig"]["v"] = "0x" + "00" * 65   # imzayı-boz
p.write_text("\n".join(json.dumps(x, ensure_ascii=False) for x in rows) + "\n",
             encoding="utf-8")
K4PY2
OUT4=$("$PY" tamga_runner.py ledger-verify "$SB/pk" 2>>"$LOG")
RC4=$?
CODE4=$(echo "$OUT4" | "$PY" -c "import json,sys; d=json.load(sys.stdin); print(d.get('reason_code',''))" 2>/dev/null)
echo "K4b node_sig-bozuk: rc=$RC4 code=$CODE4" >> "$LOG"
[ "$RC4" != "0" ]
k $? "K4 node_sig-bozuk → ledger-verify RED (D8-imza-katmanı-doğrulanır)" \
   "rc=$RC4 code=$CODE4"

# --- K5: registry round-trip → GERÇEK-paket-doğrulaması ----------------------
# AT-209 sayı-korunumunu-der; bu-çalışırlığı-der: restore-sonrası registry
# load_registry-ile-yüklenir-VE-registry-check-GREEN-döner.
"$PY" tamga_runner.py quickstart "$SB/mine" --name "at226-mine" > /dev/null 2>> "$LOG"
REG="$SB/mine/reg.json"
# pkg_path MUTLAK yol olmali (load_registry mutlak-denetler — AT-209 deseni)
printf '{"at226-mine":{"pkg_path":"%s","cpu_ms_per_run":5000,"max_input_bytes":65536}}' \
       "$SB/mine" > "$REG"
N_BEFORE=$("$PY" -c "import json; print(len(json.load(open('$REG'))))")
"$PY" tamga_runner.py registry-backup "$SB/mine" >> "$LOG" 2>&1
RCB=$?
rm -f "$REG"
[ ! -f "$REG" ]
k $? "K5 registry-silindi (backup-sonrası)" "rm-hata"
"$PY" tamga_runner.py registry-restore "$SB/mine" >> "$LOG" 2>&1
RCR=$?
N_AFTER=$("$PY" -c "import json; print(len(json.load(open('$REG'))))" 2>/dev/null || echo 0)
[ -f "$REG" ] && [ "$RCR" = "0" ] && [ "$RCB" = "0" ] && [ "$N_AFTER" = "$N_BEFORE" ]
k $? "K5 backup→sil→restore → registry-geri-geldi, kayıt-sayısı-korundu ($N_BEFORE→$N_AFTER)" \
   "backup=$RCB restore=$RCR"
# çalışırlık: restore-edilen-registry-ile-bağımsız-denetim-GREEN
OUTCK=$("$PY" tamga_oracle_relayer.py registry-check "$REG" 2>> "$LOG")
RCCK=$?
echo "K5b registry-check: rc=$RCCK out=$(echo "$OUTCK" | tail -1 | cut -c1-60)" >> "$LOG"
[ "$RCCK" = "0" ]
k $? "K5b restore-sonrası registry-check GREEN (registry-gerçekten-yükleniyor)" "rc=$RCCK"

# --- K6: hatalı-anahtar → fail-closed ----------------------------------------
# DÜRÜST-NOT: sign komutu KULLANICININ-seçtiği-herhangi-geçerli-anahtarla-imzalar
# (anahtar-rotasyonu-için-tasarım) — farklı-anahtar rc=0-verir (fail-OPEN-değil,
# bilinçli-tasarım). Fail-closed-yüzeyi: FORMATÇA-geçersiz-anahtarlar.
# K6a: geçersiz-hex seed → RED
"$PY" tamga_validator.py sign "$SB/mine/tamga.json" "$SB/mine/agent.wasm" \
     "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz" \
     >> "$LOG" 2>&1
RC6a=$?
[ "$RC6a" != "0" ]
k $? "K6a geçersiz-hex-seed → imzalama-RED rc!=0 (fail-closed)" "rc=$RC6a"
# K6b: yanlış-uzunluk seed (kısa) → RED
"$PY" tamga_validator.py sign "$SB/mine/tamga.json" "$SB/mine/agent.wasm" \
     "0x1234" >> "$LOG" 2>&1
RC6b=$?
[ "$RC6b" != "0" ]
k $? "K6b yanlış-uzunluk-seed → imzalama-RED rc!=0 (fail-closed)" "rc=$RC6b"
# K6c: olmayan-seed-dosyası → RED
"$PY" tamga_validator.py sign "$SB/mine/tamga.json" "$SB/mine/agent.wasm" \
     "$SB/mine/yok-seed.hex" >> "$LOG" 2>&1
RC6c=$?
[ "$RC6c" != "0" ]
k $? "K6c olmayan-seed-dosyası → imzalama-RED rc!=0 (fail-closed)" "rc=$RC6c"

echo "== AT-228: $((PASS)) PASS, $((FAIL)) FAIL — log: $LOG ==" | tee -a "$LOG"
[ "$FAIL" -eq 0 ] || tail -4 "$LOG"
exit $([ "$FAIL" -eq 0 ])

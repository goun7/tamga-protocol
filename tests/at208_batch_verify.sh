#!/bin/bash
# AT-208: BATCH-VERIFY — N paketi tek çağrıda denetle
#
# Müşteri değeri: "100 paketi tek seferde denetleyin" — ayrı komut yerine
# tek invocation + özet JSON. rc=0 yalnızca TÜM paketler geçerse.
#
#   K1  BOŞ args → kullanım hatası (rc != 0, traceback DEĞİL)
#   K2  3 paket (2 geçerli + 1 kırık) → 2 verified, 1 failed → rc=1
#   K3  2 geçerli paket → 2 verified, 0 failed → rc=0
#   K4  --summary-only → item satırları YOK, sadece özet
#   K5  yanlış dizin → failed olarak işaretlenir (green-giydirme yok)
#   K6  TAMPER: son-kaydın hash'i değişince → failed (zincir-tutarsız)
#   K7  TAMPER: prev-bağlantısı kopınca → failed (sıralı-bütünlük)
#       (K6/K7 issue #2332'ye-yanıt: "Logs can be rewritten. An external
#        anchor cannot." — anchor'ın-çalıştığının-kanıtı)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); export D; LOGDIR=".evidence/RELAYER/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at208.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

PY=python3
SB=$(mktemp -d)

# --- 2 gecerli paket hazirla (quickstart ile bos-ledger = gecerli) ----------
for i in 1 2; do
  "$PY" tamga_runner.py quickstart "$SB/pk$i" --name "at208-$i" > /dev/null 2>>"$LOG"
done
# --- 1 KIRIK paket: gecersiz JSON ledger -----------------------------------
mkdir -p "$SB/broken"
printf '{"op":"charge","this_is_not_valid_json_at_all\n' > "$SB/broken/ledger.jsonl"

note "AT-208: batch-verify (3 paket: 2 gecerli + 1 kirik)"

# K1 — bos args kullanım hatası vermeli (rc != 0)
"$PY" tamga_runner.py ledger-verify-batch >> "$LOG" 2>&1
RC1=$?
[ "$RC1" != "0" ]
k $? "K1 bos-args kullanım hatası (rc!=0, traceback yok)" "rc=$RC1"

# K2 — 3 paket: 2 gecerli + 1 kirik → rc=1, failed=1
OUT2=$("$PY" tamga_runner.py ledger-verify-batch "$SB/pk1" "$SB/pk2" "$SB/broken" 2>>"$LOG")
RC2=$?
echo "$OUT2" | tail -1 >> "$LOG"
VK2=$(echo "$OUT2" | tail -1 | "$PY" -c "import json,sys; d=json.load(sys.stdin); print(d['verified'])")
FK2=$(echo "$OUT2" | tail -1 | "$PY" -c "import json,sys; d=json.load(sys.stdin); print(d['failed'])")
[ "$RC2" != "0" ] && [ "$VK2" = "2" ] && [ "$FK2" = "1" ]
k $? "K2 2-gecerli + 1-kirik → verified=2 failed=1 rc!=0" "rc=$RC2 v=$VK2 f=$FK2"

# K3 — 2 gecerli → rc=0, verified=2
OUT3=$("$PY" tamga_runner.py ledger-verify-batch "$SB/pk1" "$SB/pk2" --summary-only 2>>"$LOG")
RC3=$?
VK3=$(echo "$OUT3" | "$PY" -c "import json,sys; d=json.load(sys.stdin); print(d['verified'])")
[ "$RC3" = "0" ] && [ "$VK3" = "2" ]
k $? "K3 2-gecerli → verified=2 rc=0" "rc=$RC3 v=$VK3"

# K4 — --summary-only → item satırı YOK (sadece 1 JSON satır)
NL=$(echo "$OUT3" | grep -c "ledger-verify-batch-item")
[ "$NL" = "0" ] && [ "$(echo "$OUT3" | wc -l)" = "1" ]
k $? "K4 --summary-only item satiri YOK, tek JSON" "lines=$(echo "$OUT3" | wc -l) items=$NL"

# K5 — yanlis dizin → failed (green-giydirme yok)
OUT5=$("$PY" tamga_runner.py ledger-verify-batch "$SB/yok-boyle-dizin" 2>>"$LOG")
RC5=$?
FK5=$(echo "$OUT5" | tail -1 | "$PY" -c "import json,sys; d=json.load(sys.stdin); print(d['failed'])")
[ "$RC5" != "0" ] && [ "$FK5" = "1" ]
k $? "K5 yanlis dizin → failed=1 rc!=0 (green-giydirme YOK)" "rc=$RC5 f=$FK5"

# --- TAMPER-DETECTION (AT-208-derinlestirme): geçerli-zincirde-tek-kayıt ---
# Issue #2332'nin-tespiti: "Logs can be rewritten. An external anchor cannot."
# Bu-K'lar-anchor'ın-çalıştığını-kanıtlar: zincirde-herhangi-bir-değişiklik
# verify tarafından-yakalanmalı (silent-accept-YOK).
"$PY" tamga_runner.py quickstart "$SB/tamper" --name "at208-tamper" > /dev/null 2>>"$LOG"
# önce-temiz-olduğunu-kanıtla (yeşil-giydirme-olmasın)
"$PY" tamga_runner.py ledger-verify "$SB/tamper" >> "$LOG" 2>&1
V0=$("$PY" -c "import json;print(json.load(open('$SB/tamper/ledger-verify.json'))['ok'])" 2>/dev/null || echo "false")
[ "$V0" = "True" ] || note "  (uyarı: tamper-paketi-temiz-değil: ok=$V0)"

# K6 — son-kaydın-hash'i-değiştirilince → batch-verify failed=1
"$PY" - "$SB/tamper/ledger.jsonl" <<'PYEOF' >> "$LOG" 2>&1
import json, sys, pathlib
p = pathlib.Path(sys.argv[1]); rows = [json.loads(l) for l in p.read_text().splitlines() if l.strip()]
rows[-1]["h"] = rows[-1]["h"][:-1] + ("0" if rows[-1]["h"][-1] != "0" else "1")
p.write_text("\n".join(json.dumps(r, ensure_ascii=False) for r in rows) + "\n")
PYEOF
OUT6=$("$PY" tamga_runner.py ledger-verify-batch "$SB/tamper" 2>>"$LOG")
RC6=$?
FK6=$(echo "$OUT6" | tail -1 | "$PY" -c "import json,sys; d=json.load(sys.stdin); print(d['failed'])")
[ "$RC6" != "0" ] && [ "$FK6" = "1" ]
k $? "K6 son-kayıt-hash'i-değişti → failed=1 rc!=0 (tamper-YAKALANDI)" "rc=$RC6 f=$FK6"

# K7 — prev-bağlantısı-koparılınca → failed (zincir-bütünlüğü-sıralı)
"$PY" tamga_runner.py quickstart "$SB/tamper2" --name "at208-t2" > /dev/null 2>>"$LOG"
"$PY" - "$SB/tamper2/ledger.jsonl" <<'PYEOF' >> "$LOG" 2>&1
import json, sys, pathlib
p = pathlib.Path(sys.argv[1]); rows = [json.loads(l) for l in p.read_text().splitlines() if l.strip()]
# son-kaydın-prev'ini-başka-bir-hash'e-bağla (zincir-kopar)
if len(rows) > 1:
    rows[-1]["prev"] = "0"*63 + "1"
    p.write_text("\n".join(json.dumps(r, ensure_ascii=False) for r in rows) + "\n")
PYEOF
OUT7=$("$PY" tamga_runner.py ledger-verify-batch "$SB/tamper2" 2>>"$LOG")
RC7=$?
FK7=$(echo "$OUT7" | tail -1 | "$PY" -c "import json,sys; d=json.load(sys.stdin); print(d['failed'])")
[ "$RC7" != "0" ] && [ "$FK7" = "1" ]
k $? "K7 prev-bağlantısı-koptu → failed=1 rc!=0 (sıralı-bütünlük)" "rc=$RC7 f=$FK7"

echo; echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" = "0" ]

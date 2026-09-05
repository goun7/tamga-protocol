#!/usr/bin/env bash
# Tamga Protocol — tek-komut regresyon takımı
# Semantik: kontrol <exit> — 0 = PASS, sıfırdan farklı = FAIL (bash PIPESTATUS konvansiyonu;
# 'POSIX' değil: PIPESTATUS bash'e özgüdür (Audit-9 B19). Takım her koşuda kendi
# tek-kullanımlık sandbox'ını kurar; kalıcı fixture'ları bozmaz.
set -u
cd "$(dirname "$0")/.."
export TAMGA_KS_PASSPHRASE="${TAMGA_KS_PASSPHRASE:-simnet-2026}"
LOG="kanit/REGRESYON/$(date +%F)/run_all-$(date +%H%M%S).log"
mkdir -p "$(dirname "$LOG")"
SB="tests/simnet/.sandbox"
PASS=0; FAIL=0
say() { echo "  [$1] $2"; }
kontrol() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); say PASS "$2"; else FAIL=$((FAIL+1)); say FAIL "$2"; fi; }
bekle_red() { kontrol "$@"; }  # RED-kanıt grepleri (grep -q'ya bağlı) için anlamsal ad; tek uygulama (Tur-2 temizliği)

{
  echo "# run_all — $(date -Iseconds)"

  echo "--- AT-001a: manifest doğrulama vektörleri (1 ACCEPT + 5 RED beklenir)"
  python3 tamga_validator.py validate tests/vectors/tc-a1 | grep -q '^ACCEPT'; kontrol $? "tc-a1 ACCEPT"
  for tc in tc-a2 tc-a3 tc-a4 tc-a5 tc-a6; do
    if python3 tamga_validator.py validate "tests/vectors/$tc" | grep -q '^RED'; then kontrol 0 "$tc RED"; else kontrol 1 "$tc RED"; fi
  done

  echo "--- AT-001f: import negatif vektörleri (reason 7/9/8) — ayrıntı: kanit/AT-001/$(date +%F)/AT-001f-vektorler.log"
  bash tests/negative_snapshots.sh > /dev/null 2>&1; kontrol $? "tc-s7/s9/s8 negatif vektörleri (3 RED beklentisi)"

  echo "--- AT-003: node-cosign negatif vektörleri (F25 çözümü) — ayrıntı: kanit/AT-003/$(date +%F)/AT-003-cosign.log"
  bash tests/negative_cosign.sh > /dev/null 2>&1; kontrol $? "tc-n1..n6 node-cosign vektörleri (L1/L0 politikası)"

  echo "--- sandbox kuruluyor (tek kullanımlık node)"
  rm -rf "$SB"; mkdir -p "$SB/pkg"
  cp tests/vectors/tc-a1/tamga.json tests/vectors/tc-a1/agent.wasm "$SB/pkg/"
  SEED=$(python3 tamga_runner.py keygen | python3 -c 'import sys,json;print(json.load(sys.stdin)["seed_hex"])')

  python3 tamga_runner.py grant "$SB/pkg" 0.01 "takim-hibe" | grep -q '"seq": 1'; kontrol $? "grant seq-1 zincire girdi"
  python3 tamga_runner.py run "$SB/pkg" --seed "$SEED" --note "takim-notu" | grep -q '"ok": true'; kontrol $? "koşum ok"

  echo "--- Dilim-11: girdi-bağlama (D11) — input_sha256 makbuzda + deterministik replay"
  printf '{"islem":"d11","v":1}' > "$SB/pkg/in.json"
  python3 tamga_runner.py run "$SB/pkg" --seed "$SEED" --input "$SB/pkg/in.json" --require-proof --note d11a > /dev/null
  python3 tamga_runner.py run "$SB/pkg" --seed "$SEED" --input "$SB/pkg/in.json" --require-proof --note d11b > /dev/null
  python3 - "$SB/pkg/ledger.jsonl" <<'PY'
import sys, json, hashlib
ch = [json.loads(l) for l in open(sys.argv[1]) if l.strip() and json.loads(l).get("op") == "charge"]
bek = hashlib.sha256(open(sys.argv[1].rsplit("/", 1)[0] + "/in.json", "rb").read()).hexdigest()
girdili = [r for r in ch if r.get("input_sha256")]
assert len(girdili) >= 2, "girdili makbuz yok"
assert all(r["input_sha256"] == bek for r in girdili), "input_sha256 uyuşmaz"
assert girdili[-1]["stdout_sha256"] == girdili[-2]["stdout_sha256"], "replay kırıldı"
PY
  kontrol $? "D11: girdi-hash makbuzda + aynı-girdi→aynı-çıktı"
  python3 tamga_runner.py ledger-verify "$SB/pkg" | grep -q '"ok": true'; kontrol $? "zincir ucuca doğru"

  echo "--- F21: truncate → import RED (reason 14)"
  python3 tamga_runner.py export "$SB/pkg" -o "$SB/snap.tsg" --seed "$SEED" > /dev/null
  python3 - "$SB/pkg/ledger.jsonl" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); lines = p.read_text().splitlines(); lines.pop()
p.write_text(chr(10).join(lines) + chr(10))
PY
  python3 tamga_runner.py import "$SB/snap.tsg" "$SB/pkg" | grep -q '"reason_code": 14'
  bekle_red $? "truncate sonrası import reason-14 RED"

  echo "--- merkle: state kurcala → taze pkg'ye import RED (reason 17)"
  python3 - "$SB" <<'PY'
import json, sys, pathlib
sb = pathlib.Path(sys.argv[1])
st = json.loads((sb / "pkg/state.json").read_text())
for n in st["memory"]["nodes"]:
    if n["kind"] == "note":
        n["text"] = "KURCALANDI"; break
(sb / "pkg/state.json").write_text(json.dumps(st, ensure_ascii=False))
PY
  python3 tamga_runner.py export "$SB/pkg" -o "$SB/snap2.tsg" --seed "$SEED" > /dev/null
  mkdir -p "$SB/pkg2"; cp tests/vectors/tc-a1/tamga.json tests/vectors/tc-a1/agent.wasm "$SB/pkg2/"
  python3 tamga_runner.py import "$SB/snap2.tsg" "$SB/pkg2" | grep -q '"reason_code": 17'
  bekle_red $? "merkle kurcalama reason-17 RED"

  echo "--- göç: taze node'a taşınma + gömülü zincir (F24 kapanışı)"
  python3 tamga_runner.py run "$SB/pkg" --seed "$SEED" > /dev/null   # zinciri onar (charge ekle)
  python3 tamga_runner.py export "$SB/pkg" -o "$SB/snap3.tsg" --seed "$SEED" > /dev/null
  mkdir -p "$SB/pkg3"; cp tests/vectors/tc-a1/tamga.json tests/vectors/tc-a1/agent.wasm "$SB/pkg3/"
  python3 tamga_runner.py import "$SB/snap3.tsg" "$SB/pkg3" | grep -q '"ok": true'; kontrol $? "göç ACCEPT"
  python3 tamga_runner.py ledger-verify "$SB/pkg3" | grep -q '"ok": true'; kontrol $? "gömülü zincir hedefte doğrulandı (F24)"

  echo "--- AT-001d özü: snapshot gövdesi şifreli (düz-metin taraması)"
  if grep -q "takim-notu" "$SB/snap3.tsg"; then kontrol 1 "snapshot gövdesinde düz-metin sızıntı"; else kontrol 0 "snapshot gövdesinde 0 düz-metin sızıntı"; fi

  if [ "${RUN_SLOW:-0}" = "1" ]; then
    # Audit-9 B16: yavaş tur gitignored fixture'lara bağlı (c30 + seedC) — taze klonde
    # çalışmaz; önkoşul kapısı net mesaj verir.
    if [ ! -f tests/simnet/node-C/pkg-c30/tamga.json ] || [ ! -f tests/simnet/seedC.hex ]; then
      echo "  [SKIP] RUN_SLOW atlandı: tests/simnet/node-C + seedC.hex fixture'ları bu klonde yok (gitignored)"
    else
    echo "--- AT-001c özü: 31s wall-ölçümü (yavaş)"
    W=$(python3 tamga_runner.py run tests/simnet/node-C/pkg-c30 --seed "$(cat tests/simnet/seedC.hex)" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("wall_ms",0))')
    if [ "$W" -ge 30000 ] 2>/dev/null; then kontrol 0 "c30 wall_ms=$W ≥ 30000"; else kontrol 1 "c30 wall_ms=$W < 30000"; fi
    fi
  fi

  rm -rf "$SB"
  echo ""
  echo "SONUÇ: $PASS PASS, $FAIL FAIL — log: $LOG"
  [ "$FAIL" = "0" ]
} 2>&1 | tee -a "$LOG"
exit ${PIPESTATUS[0]}

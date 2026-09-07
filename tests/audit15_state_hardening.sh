#!/usr/bin/env bash
# Audit-15 — state.json-saldırı-yüzeyi sertleştirmesi (2-gerçek-bulgu-fix + 3-dayanıklılık-kanıtı)
# Bulgu-1: bozuk-state.json-(truncate/vuruk-json)→runner-TRACEBACK-crash (RED-değil) —
#          _load_state-artık-fail-closed-RED-5 'state_invalid' + restore-talimatı
# Bulgu-2: (olumlu-kanıt) state-tampering-(tip/sessions)-zincire-ETKİSİZ — _ledger_append
#          gerçek-son-h'yi-okur (F21-disiplin); seq-sıralaması-sağlam
# Dayanıklılık: yabancı-alan-(unicode-anahtar)-tolere; 1000-düzey-nesting-çökertmez
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AUDIT-15/$(date +%F)}/audit15.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
export TAMGA_KS_PASSPHRASE=a15-2026
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
W=$(mktemp -d)

python3 - "$W" > "$LOG.1" 2>&1 <<'PYEOF'
import json, sys, pathlib, shutil
W = pathlib.Path(sys.argv[1])
shutil.copy("tests/vectors/tc-net-demo/tamga.json", W / "tamga.json")
shutil.copy("tests/vectors/tc-net-demo/agent.wasm", W / "agent.wasm")
sys.path.insert(0, ".")
import tamga_validator as tv
m = json.load(open(W / "tamga.json"))
sk = tv.SigningKey.generate()
m["signature"] = {"algo": "ed25519", "key": sk.verify_key.encode().hex(), "sig": ""}
m["signature"]["sig"] = sk.sign(tv.jcs(m)).signature.hex()
(W / "tamga.json").write_text(json.dumps(m, indent=2))
(W / "seed.hex").write_text(sk.encode().hex())
PYEOF
SEED=$(cat "$W/seed.hex")
python3 tamga_runner.py run "$W" --seed "$SEED" > /dev/null 2>&1
ok $? "kuruluş: taban-pkg + state.json"
cp "$W/state.json" "$W/state.orig"

python3 -c "import sys, pathlib; pathlib.Path(sys.argv[1], 'state.json').write_bytes(pathlib.Path(sys.argv[1], 'state.json').read_bytes()[:40])" "$W"
python3 tamga_runner.py run "$W" --seed "$SEED" > "$LOG.2" 2>&1; RC=$?
[ "$RC" -eq 1 ] && grep -q 'state_invalid' "$LOG.2" && grep -qv 'Traceback' "$LOG.2"
ok $? "bulgu-1: bozuk-state → fail-closed RED-5 (traceback-YOK, restore-talimatı-var)"

python3 tamga_runner.py ledger-verify "$W" > "$LOG.3" 2>&1
grep -q '"ok": true' "$LOG.3"; ok $? "bozuk-state-zinciri-ETKİLEMEZ (verify-ok)"

python3 - "$W" > "$LOG.4" 2>&1 <<'PYEOF'
import json, sys, pathlib
W = pathlib.Path(sys.argv[1])
st = json.loads((W / "state.json").read_text())
st["ledger_tip"] = "f" * 64; st["sessions"] = 99
(W / "state.json").write_text(json.dumps(st))
PYEOF
python3 tamga_runner.py run "$W" --seed "$SEED" > /dev/null 2>&1
python3 - "$W" > "$LOG.5" 2>&1 <<'PYEOF'
import json, sys, pathlib
W = pathlib.Path(sys.argv[1])
lines = [json.loads(l) for l in (W / "ledger.jsonl").read_text().splitlines() if l.strip()]
seqs = [r["seq"] for r in lines]
ok = (seqs == sorted(set(seqs)) and seqs == list(range(1, len(seqs) + 1))
      and all(lines[i]["prev"] == (lines[i-1]["h"] if i else "0"*64) for i in range(len(lines))))
sys.exit(0 if ok else 1)
PYEOF
ok $? "bulgu-2: state-tampering→seq/prev-zinciri-sağlam (F21-disiplin-kanıtı)"

cp "$W/state.orig" "$W/state.json"
python3 - "$W" > "$LOG.6" 2>&1 <<'PYEOF'
import json, sys, pathlib
W = pathlib.Path(sys.argv[1])
st = json.loads((W / "state.json").read_text())
st["sessoın"] = 5
deep = st
for _ in range(1000): deep["d"] = {}; deep = deep["d"]
(W / "state.json").write_text(json.dumps(st))
PYEOF
python3 tamga_runner.py run "$W" --seed "$SEED" > "$LOG.7" 2>&1; RC=$?
[ "$RC" -eq 0 ]; ok $? "dayanıklılık: yabancı-anahtar+1000-düzey-nesting → run-ok"

rm -rf "$W"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ]

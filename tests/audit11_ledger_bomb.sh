#!/usr/bin/env bash
# Audit-11 (D1) — ledger bombası ailesi: devasa-satır / grant-bombası / append-belleği
# Üç-oluş: (1) 50MB-el-ekleme-satırı → verify-FAIL-closed 1s-altı (düşük-RSS);
#          (2) 100KB-grant-note → RED-8 (memory_limit — F12-grant'a-genişletildi);
#          (3) 1KB-normal-grant hâlâ-OK + zincir-tam.
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AUDIT-11/$(date +%F)}/audit11.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
export TAMGA_KS_PASSPHRASE=simnet-2026
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
W=$(mktemp -d)
python3 - "$W" > "$LOG.1" 2>&1 <<'PYEOF'
import json, sys, pathlib, shutil
W = pathlib.Path(sys.argv[1])
shutil.copy("tests/vectors/tc-net-demo/tamga.json", W / "tamga.json")
shutil.copy("tests/vectors/tc-net-demo/agent.wasm", W / "agent.wasm")
sys.path.insert(0, ".")
import tamga_validator as tv
m = json.load(open("tests/vectors/tc-net-demo/tamga.json"))
sk = tv.SigningKey.generate()
m["signature"] = {"algo": "ed25519", "key": sk.verify_key.encode().hex(), "sig": ""}
m["signature"]["sig"] = sk.sign(tv.jcs(m)).signature.hex()
(W / "tamga.json").write_text(json.dumps(m, indent=2))
(W / "seed.hex").write_text(sk.encode().hex())
PYEOF
SEED=$(cat "$W/seed.hex")
python3 tamga_runner.py run "$W" --seed "$SEED" > /dev/null 2>&1
ok $? "kuruluş: pkg + run (taban-zincir)"

python3 - "$W" > "$LOG.2" 2>&1 <<'PYEOF'
import json, sys, pathlib
W = pathlib.Path(sys.argv[1])
(W / "ledger.jsonl").open("a").write(json.dumps({"op": "x", "note": "A" * (50 * 1024 * 1024)}) + "\n")
PYEOF
S=$(date +%s%N)
python3 tamga_runner.py ledger-verify "$W" > "$LOG.3" 2>&1
RC=$?; S1=$(date +%s%N); MS=$(( (S1-S)/1000000 ))
grep -q '"ok": false' "$LOG.3" && [ "$MS" -lt 5000 ]; ok $? "50MB-satır → fail-closed RED (${MS}ms — bellek-bombası-yutulmadı)"

python3 tamga_runner.py grant "$W" 0.001 "$(printf 'A%.0s' $(seq 1 100000))" > "$LOG.4" 2>&1
grep -q '"reason_code": 8' "$LOG.4" && grep -q 'memory_limit' "$LOG.4"; ok $? "100KB-grant-note → RED-8 memory_limit (F12 grant'a-genişletildi)"

python3 tamga_runner.py grant "$W" 0.001 "normal-note" > "$LOG.5" 2>&1
grep -q '"ok": true' "$LOG.5"; ok $? "1KB-normal-grant → OK (meşru-akış-kırılmadı)"

python3 tamga_runner.py ledger-verify "$W" > "$LOG.6" 2>&1
grep -q '"ok": false' "$LOG.6"; ok $? "bomba-satırından-sonra-zincir-hâlâ-RED (fail-closed-kalıcılığı)"

rm -rf "$W"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ]

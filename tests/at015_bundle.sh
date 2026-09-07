#!/usr/bin/env bash
# Audit-14 (AT-015) — B4 doğrulama-bundle: tek-komut-kanıt-paketi.
# Kontroller: (1) bundle-JSON+MD-üretir-(chain-ok); (2) bundle-REKORD-kopyaları-zincirle-BİREBİR;
# (3) mini-verifier-bundle-kayıtlarını-BAĞIMSIZ-doğrular; (4) tamper'lı-pkg-bundle-vardict-RED.
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AUDIT-14/$(date +%F)}/at015.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
export TAMGA_KS_PASSPHRASE=bundle-2026
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
python3 tamga_runner.py run "$W" --seed "$SEED" --delivery-alg keccak256 > /dev/null 2>&1
ok $? "kuruluş: charge-kaydı-(delivery-hash'li)"

python3 tamga_bundle.py "$W" -o "$W/out" > "$LOG.2" 2>&1
grep -q '"ok": true' "$LOG.2" && grep -q '"chain_verdict": "ok"' "$LOG.2"; ok $? "bundle-üretimi (JSON+MD, verdict ok)"

python3 - "$W" > "$LOG.3" 2>&1 <<'PYEOF'
import json, sys, pathlib
W = pathlib.Path(sys.argv[1])
ledger = [json.loads(l) for l in (W / "ledger.jsonl").read_text().splitlines() if l.strip()]
b = json.load(open(W / "out" / f"{W.name}-bundle.json"))
# (a) bundle-records-zincirle-birebir:
ok_copy = b["chain"]["records"] == ledger
# (b) jobs-bölümü-delivery-hash'i-taşıyor:
j = b["jobs"][0]
ok_job = j["delivery_hash"]["alg"] == "keccak256" and j["stdout_sha256"] == ledger[0]["stdout_sha256"]
print("copy-equal:", ok_copy, "| job-fields:", ok_job)
sys.exit(0 if (ok_copy and ok_job) else 1)
PYEOF
ok $? "bundle-zincirle-birebir + delivery-hash-taşınıyor"

# (3) mini-verifier-bundle-kayıtlarını-bağımsız-doğrular:
python3 - "$W" > "$LOG.4" 2>&1 <<'PYEOF'
import json, sys, pathlib, subprocess, tempfile
W = pathlib.Path(sys.argv[1])
b = json.load(open(W / "out" / f"{W.name}-bundle.json"))
tf = tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False)
for r in b["chain"]["records"]:
    tf.write(json.dumps(r) + "\n")
tf.close()
r = subprocess.run([sys.executable, "tamga_verify_mini.py", tf.name], capture_output=True, text=True)
print(r.stdout)
sys.exit(r.returncode)
PYEOF
ok $? "mini-verifier-bundle-kayıtlarını-bağımsız-doğrular (reproducibility)"

# (4) tamper'lı-pkg → bundle-verdict-RED:
python3 - "$W" <<'PYEOF'
import json, sys, pathlib
W = pathlib.Path(sys.argv[1])
lines = (W / "ledger.jsonl").read_text().splitlines()
rec = json.loads(lines[0]); rec["fee_sim"] = 0.0
(W / "ledger.jsonl").write_text("\n".join([json.dumps(rec)] + lines[1:]) + "\n")
PYEOF
python3 tamga_bundle.py "$W" -o "$W/out2" > "$LOG.5" 2>&1; RC=$?
grep -q '"chain_verdict": "broken' "$LOG.5" && [ "$RC" -eq 1 ]; ok $? "tamper → bundle-verdict-RED + rc-1 (kırık-zincir-de-kanıttır)"

rm -rf "$W"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ]

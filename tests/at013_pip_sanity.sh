#!/usr/bin/env bash
# Audit-12 (AT-013) — pip-kurulum sağlığı: izole-venv'de `pip install .` →
# keygen (motor-istemez) → ledger-verify (motor-istemez) → temizlik.
# Kanıt-hedefi: doğrulama-yolçapı pip-kurulumunda wasmtime OLMADAN çalışır (E-5: motor
# yalnız ilk `run`'da digest-kapılı indirilir; burada İNTERNET-indirimi tetiklenmez).
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AUDIT-12/$(date +%F)}/at013.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
V=$(mktemp -d)

python3 -m venv "$V/env" 2>>"$LOG.1"
"$V/env/bin/pip" install -q . > "$LOG.1" 2>&1
ok $? "pip install . (izole-venv, tek-bağımlılık-pynacl)"

"$V/env/bin/tamga" keygen > "$LOG.2" 2>&1
grep -q '"ok": true' "$LOG.2" && grep -q '"seed_hex": "' "$LOG.2"
ok $? "tamga keygen (wasmtime-yok; seed-bir-kez-yazar)"

python3 - "$V" > "$LOG.3" 2>&1 <<'PYEOF'
import json, sys, pathlib, shutil
V = pathlib.Path(sys.argv[1])
pkg = V / "pkg-verify"
pkg.mkdir(parents=True)
shutil.copy("tests/vectors/tc-net-demo/tamga.json", pkg / "tamga.json")
shutil.copy("tests/vectors/tc-net-demo/agent.wasm", pkg / "agent.wasm")
sys.path.insert(0, ".")
import tamga_validator as tv
m = json.load(open(pkg / "tamga.json"))
sk = tv.SigningKey.generate()
m["signature"] = {"algo": "ed25519", "key": sk.verify_key.encode().hex(), "sig": ""}
m["signature"]["sig"] = sk.sign(tv.jcs(m)).signature.hex()
(pkg / "tamga.json").write_text(json.dumps(m, indent=2))
import subprocess
r = subprocess.run([str(V / "env" / "bin" / "tamga"), "ledger-verify", str(pkg)], capture_output=True, text=True)
print(r.stdout)
sys.exit(r.returncode)
PYEOF
ok $? "tamga ledger-verify (pip-kurulumundan, motor-İSTEMEZ — doğrulama-yolçapı-saf)"

"$V/env/bin/pip" uninstall -y -q tamga-protocol > /dev/null 2>&1
[ ! -x "$V/env/bin/tamga" ]; ok $? "uninstall sonrası tamga-binary YOK (konsol-betiği-gerçekten-paketten-geliyor)"

rm -rf "$V"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ]

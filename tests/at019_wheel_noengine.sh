#!/usr/bin/env bash
# AT-019 (RUN_SLOW) - published-wheel: nacl-KASITLI-ortamda-gercek-verification
# Sem: pip-install-eden-karsi-taraf, pynacl'u-kirik/engelli-bir-host'ta bile
# tamga_verify_mini ile zincir-dogrulayabilir (engine + pynacl-free dogrulama yolu).
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AT-019/$(date +%F)}/at019.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
cd "$(cd "$(dirname "$0")/.." && pwd)"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# 1) wheel-kurulum (no-deps: pynacl-olmadan — sinirli-host-senaryosu):
python3 -m venv "$WORK/venv" > /dev/null 2>&1
"$WORK/venv/bin/pip" install --quiet --no-deps dist/tamga_protocol-*.whl > /dev/null 2>&1
ok $? "wheel: --no-deps-kurulum (pynacl-siz)"

# 2) tamga-run ile-canli-ledger-uretimi (bu-adim-pynacl-ister — ana-venv'de):
PASS=0
python3 -m venv "$WORK/full" > /dev/null 2>&1
"$WORK/full/bin/pip" install --quiet dist/tamga_protocol-*.whl pynacl > /dev/null 2>&1
cp -r tests/vectors/tc-net-demo "$WORK/pkg"
export TAMGA_KS_PASSPHRASE=at019-test
"$WORK/full/bin/tamga" keygen > "$WORK/kg.json" 2>&1 && \
"$WORK/full/bin/tamga" run "$WORK/pkg" --seed "$(python3 -c "import json;print(json.load(open('$WORK/kg.json'))['seed_hex'])")" > "$WORK/run.json" 2>&1
ok $? "tamga-run: canli-ledger-uretildi (tam-yigin)"

# 3) nacl-BLOKLU-ortamda-gercek-verification (wheel'in verify_mini'si):
python3 - "$WORK" > "$LOG.3" 2>&1 <<'PYEOF'
import json, pathlib, site, subprocess, sys, sysconfig
work = pathlib.Path(sys.argv[1])
site_dir = sorted(pathlib.Path(work / "venv" / "lib").glob("python3*/site-packages"))[0]
script = """
import sys
class NaclBlocker:
    def find_spec(self, name, path=None, target=None):
        if name == "nacl" or name.startswith("nacl."):
            raise ImportError("nacl blocked")
        return None
sys.meta_path.insert(0, NaclBlocker())
sys.path.insert(0, r""" + repr(str(site_dir)) + """)
sys.argv = ["tamga_verify_mini", r""" + repr(str(work / "pkg" / "ledger.jsonl")) + """]
import tamga_verify_mini
sys.exit(tamga_verify_mini.main(sys.argv[1:]))
"""
r = subprocess.run([sys.executable, "-c", script], capture_output=True, text=True)
assert r.returncode == 0, "nacl-blocked-verification-RED: " + r.stdout[:200]
out = json.loads(r.stdout)
assert out.get("ok") is True and out.get("lines", 0) >= 1, out
print("nacl-blocked-ortamda-GERCEK-verification-PASS:", json.dumps(out)[:120])
PYEOF
ok $? "AT-019: nacl-KASITLI-ortamda-gercek-verification (yayinlanan-wheel)"

echo "RESULT: $PASS PASS, $FAIL FAIL - log: $LOG"
[ "$FAIL" -eq 0 ]

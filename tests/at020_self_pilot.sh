#!/usr/bin/env bash
# AT-020 (RUN_SLOW) - SELF-PILOT: uc-bacakli-uctan-uca-teslimat-kaniti (dis-taraf-YOK)
# kurucu-steeri: "github-sessiz → kendimize-son-noktaya-kadar-gelistir"
# Kanit-kulturu: green-akis + iki-tamper-negatifi (bacak-cokerse-RED).
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AT-020/$(date +%F)}/at020.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
cd "$(cd "$(dirname "$0")/.." && pwd)"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# 1) GREEN-akis: uc-bacak-hepsi-green + donuk-kanit-yazilir:
python3 tools/self_pilot.py tests/vectors/tc-net-demo "$WORK/ev" > "$LOG.1" 2>&1
ok $? "self-pilot: uc-bacak-GREEN-akis (rc=0)"

python3 - "$WORK/ev" > "$LOG.2" 2>&1 <<'PYEOF'
import json, pathlib, sys
ev = pathlib.Path(sys.argv[1])
d = json.loads((ev / "self-pilot-evidence.json").read_text(encoding="utf-8"))
assert d["verdict"] == "ALL-THREE-LEGS-GREEN", d["verdict"]
assert all(l["ok"] for l in d["legs"]), d["legs"]
assert len(d["legs"]) == 3, d["legs"]
assert (ev / "acceptance.json").exists() and (ev / "delivered.out").exists()
print("self-pilot: evidence-donuk + 3-bacak-hepsi-ok")
PYEOF
ok $? "self-pilot: evidence-verdict + 3-bacak-yapisi"

# 2) NEGATIF-1 [delivered-tamper]: teslim-baytina-byte-copert → keccak-artik-esit-DEGIL:
python3 - "$WORK/ev" > "$LOG.3" 2>&1 <<'PYEOF'
import json, pathlib, sys
sys.path.insert(0, "tools")
from keccak256 import keccak256 as keccak
ev = pathlib.Path(sys.argv[1])
d = json.loads((ev / "self-pilot-evidence.json").read_text(encoding="utf-8"))
dh = d["delivery_hash"]["hex"]
out = bytearray((ev / "delivered.out").read_bytes())
out[0] ^= 0xFF                      # tek-byte-ters
assert keccak(bytes(out)).hex() != dh, "tampered-delivery-hala-esit-cikti"
print("delivered-tamper: keccak-artik-eslesmiyor (RED-dogru)")
PYEOF
ok $? "self-pilot-negatif: teslim-bayti-tamper → hash-ayrisir"

# 3) NEGATIF-2 [satisfied-tamper]: onay-dokumanina-byte-copert → imza-RED:
python3 - "$WORK/ev" > "$LOG.4" 2>&1 <<'PYEOF'
import json, pathlib, sys
sys.path.insert(0, ".")
from tamga_validator import jcs
from nacl.signing import VerifyKey
ev = pathlib.Path(sys.argv[1])
a = json.loads((ev / "acceptance.json").read_text(encoding="utf-8"))
doc = json.loads(json.dumps(a["doc"]))       # kopya
doc["receipt_head"] = "0" * 64               # recin-basini-degistir
vk = VerifyKey(bytes.fromhex(a["key"]))
try:
    vk.verify(jcs(doc), bytes.fromhex(a["sig"]))
    raise SystemExit("tampered-acceptance-imali-DOGrULANDI (olmamali)")   # FAIL
except SystemExit:
    raise
except Exception:
    print("acceptance-tamper: imza-RED (dogru-red)")
PYEOF
ok $? "self-pilot-negatif: onay-tamper → imza-RED"

echo "RESULT: $PASS PASS, $FAIL FAIL - log: $LOG"
[ "$FAIL" -eq 0 ]

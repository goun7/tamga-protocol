#!/usr/bin/env bash
# AT-007 — pairing fixture (x402 <-> Tamga, #3379)
# positive: regenerate a fixture in a temp dir and verify it (5 checks)
# negative x6: tamper delivery bytes / receiptHash / label / input / stale charge.h /
#   re-signed commitment with stale charge.input_sha256 -> verifier RED
# the committed docs/pairing fixture is ALSO verified against its own bytes
set -u
cd "$(dirname "$0")/.." || exit 1
export TAMGA_KS_PASSPHRASE=simnet-2026
PASS=0; FAIL=0
ok() { if [ "$1" = 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2"; else FAIL=$((FAIL+1)); echo "  FAIL: $2"; fi }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

# ---------- positive: fresh fixture + verifier accepts ----------
python3 tools/make_pairing_fixture.py "$W/work" "$W/fx" > "$W/gen.json" 2> "$W/gen.err" || {
  echo "  FAIL: fixture generation crashed"; cat "$W/gen.err"; exit 1; }
python3 tools/verify_pairing_fixture.py "$W/fx" > "$W/v.json" 2>&1
ok $? "AT-007a: fresh fixture verifies (5 checks: labeling+membership+sha256+keccak256+input)"

# the committed fixture verifies too (bytes in the tree are self-consistent)
python3 tools/verify_pairing_fixture.py docs/pairing > "$W/vc.json" 2>&1
ok $? "AT-007b: committed docs/pairing fixture verifies"

# ---------- negative 1: one flipped delivery byte -> RED ----------
cp -r "$W/fx" "$W/t1"
python3 - "$W/t1/delivery.stdout" <<'PY'
import sys
p = sys.argv[1]; b = bytearray(open(p, "rb").read())
b[0] ^= 0x01
open(p, "wb").write(bytes(b))
PY
python3 tools/verify_pairing_fixture.py "$W/t1" 2>/dev/null | grep -q '"ok": false'
ok $? "AT-007c: flipped delivery byte -> verifier RED (observed sha256 mismatch)"

# ---------- negative 2: receiptHash swap -> membership RED ----------
cp -r "$W/fx" "$W/t2"
python3 - "$W/t2/pairing-fixture.json" <<'PY'
import json, sys
p = sys.argv[1]
fx = json.load(open(p))
fx["tamga_observed"]["receiptHash"]["value"] = "0" * 64
json.dump(fx, open(p, "w"))
PY
python3 tools/verify_pairing_fixture.py "$W/t2" 2>/dev/null | grep -q '"ok": false'
ok $? "AT-007d: swapped receiptHash -> membership RED (recomputed h != receiptHash)"

# ---------- negative 3: missing/invalid label -> labeling RED ----------
cp -r "$W/fx" "$W/t3"
python3 - "$W/t3/pairing-fixture.json" <<'PY'
import json, sys
p = sys.argv[1]
fx = json.load(open(p))
del fx["tamga_observed"]["engine"]["source"]        # labeling discipline violated
json.dump(fx, open(p, "w"))
PY
python3 tools/verify_pairing_fixture.py "$W/t3" 2>/dev/null | grep -q '"ok": false'
ok $? "AT-007e: field without source label -> labeling RED (safal207 discipline)"

# ---------- negative 4: input swap -> input-commitment RED ----------
cp -r "$W/fx" "$W/t4"
python3 - "$W/t4/input.json" <<'PY'
import sys
open(sys.argv[1], "w").write('{"demo": "tampered", "v": 2}\n')
PY
python3 tools/verify_pairing_fixture.py "$W/t4" 2>/dev/null | grep -q '"ok": false'
ok $? "AT-007f: swapped input -> input_sha256 commitment RED"

# ---------- negative 5: doctored record with consistent receiptHash but stale
# charge.h -> membership RED (safal207 gap-2: h must bind to charge.h too) ----------
cp -r "$W/fx" "$W/t5"
python3 - "$W/t5/pairing-fixture.json" <<'PY'
import hashlib, json, sys
sys.path.insert(0, ".")
from tools.verify_pairing_fixture import jcs
p = sys.argv[1]
fx = json.load(open(p))
ch = fx["tamga_observed"]["charge_record"]["value"]
ch["fee_sim"] = 9.9e-9                      # doctor the record
rec = {k: v for k, v in ch.items() if k != "h"}
h = hashlib.sha256((ch["prev"] + jcs(rec)).encode("utf-8")).hexdigest()
fx["tamga_observed"]["receiptHash"]["value"] = h   # receiptHash made consistent...
json.dump(fx, open(p, "w"))                        # ...but charge.h is now stale
PY
python3 tools/verify_pairing_fixture.py "$W/t5" 2>/dev/null | grep -q '"ok": false'
ok $? "AT-007g: consistent receiptHash but stale charge.h -> membership RED"

# ---------- negative 6: input tampered + commitment re-signed, stale
# charge.input_sha256 -> input_commitment RED (safal207 gap-1) ----------
cp -r "$W/fx" "$W/t6"
python3 - "$W/t6" <<'PY'
import hashlib, json, sys
d = sys.argv[1]
new_inp = b'{"demo": "tampered", "v": 2}\n'
open(d + "/input.json", "wb").write(new_inp)
p = d + "/pairing-fixture.json"
fx = json.load(open(p))
fx["input_commitment"]["input_sha256"]["value"] = hashlib.sha256(new_inp).hexdigest()
json.dump(fx, open(p, "w"))                 # commitment made consistent...
# ...but charge.input_sha256 stays stale
PY
python3 tools/verify_pairing_fixture.py "$W/t6" 2>/dev/null | grep -q '"ok": false'
ok $? "AT-007h: re-signed input commitment but stale charge.input_sha256 -> RED"

echo "RESULT: $PASS PASS, $FAIL FAIL"
[ "$FAIL" = 0 ]
exit $((FAIL > 0))

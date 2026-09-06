#!/usr/bin/env bash
# AT-007 — pairing fixture (x402 <-> Tamga, #3379)
# positive: regenerate a fixture in a temp dir and verify it (5 checks)
# negative: tamper delivery bytes / receiptHash / a label / input -> verifier RED
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

echo "RESULT: $PASS PASS, $FAIL FAIL"
[ "$FAIL" = 0 ]
exit $((FAIL > 0))

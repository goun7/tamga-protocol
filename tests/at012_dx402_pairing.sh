#!/usr/bin/env bash
# AT-012 — dx402 pairing verification family (RFC-007 track, x402 #3379)
# Offline-first: the live receipt/blob captured 2026-09-07 (canonical spelling,
# post-normalization-fix) is a committed PRIVATE fixture — CI verifies the math
# without touching the network; the live-endpoint smoke is local-only (evidence).
#
# Controls:
#   a) paymentId derivation (keccak256 chain||tx)          — derived
#   b) CIDv1/raw/sha2-256 roundtrip over 4510 served bytes — derived, byte-equal to pointer
#   c) EIP-712 ecrecover == declared signer                — derived (needs eth_account; SKIP-if-absent)
#   d) contentHash vs served bytes = SKIP (plaintext sealed) — honest labeling, NOT a FAIL
#   e) --pair-charge cross-bridge: equal-hash PASS + differing-hash RED
#   f) tamper: one flipped byte in the blob → CID mismatch (RED)
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AT-012/$(date +%F)}/at012.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
EV="private/external-evidence/2026-09-07-dx402-canonical"
PY="${PYTHON:-python3}"

# fixture-önkoşulu (özel-kanıt-klonlarda-yok olabilir):
if [ ! -f "$EV/recv-canonical.json" ]; then
  echo "  [SKIP] AT-012: canonical evidence fixture absent (private/) — math still covered by selftest"
  echo "RESULT: $PASS PASS, $FAIL FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# a) paymentId + c/d) tam-zincir-araç-turu (envelope + delivery-file):
"$PY" tools/verify_dx402_vector.py "$EV/recv-canonical.json" --delivery-file "$EV/blob-canonical.bin" > "$LOG.a" 2>&1
grep -q "\[PASS\] paymentId" "$LOG.a"; ok $? "a: paymentId derivation (keccak chain||tx)"
# c-check: PASS (eth_account'lı) VEYA SKIP (bağımlılık-yok) kabul — FAIL asla; güçlü-tur-local'de:
grep -qE "\[(PASS|SKIP)\] EIP-712 ecrecover" "$LOG.a"; ok $? "c: EIP-712 ecrecover PASS/SKIP (SKIP=eth_account-yok, açık-bildirilir)"
grep -q "\[SKIP\] contentHash vs served" "$LOG.a"; ok $? "d: contentHash-vs-served SKIP etiketi (assumed-equality-yok)"

# b) CID-yuvarlama:
"$PY" - "$EV/blob-canonical.bin" > "$LOG.b" 2>&1 <<'PYEOF'
import base64, hashlib, sys
blob = open(sys.argv[1], "rb").read()
cid = "b" + base64.b32encode(bytes([0x01, 0x55, 0x12, 0x20]) + hashlib.sha256(blob).digest()).decode().lower().rstrip("=")
print("bafkreifcy4wykdscbdxnc3ynbbmtf6jsif72hssxclfp6l3xkbssxh3j5i")
print(cid)
PYEOF
[ "$(sed -n 1p "$LOG.b")" = "$(sed -n 2p "$LOG.b")" ]; ok $? "b: CIDv1/raw/sha2-256 roundtrip == pointer fragment (4510B)"

# f) tamper: blob'da-tek-bayt-flip → CID-eşleşmez:
TMPD=$(mktemp -d)
cp "$EV/blob-canonical.bin" "$TMPD/blob-tampered.bin"
printf '\x00' | dd of="$TMPD/blob-tampered.bin" bs=1 seek=100 conv=notrunc 2>/dev/null
"$PY" - "$TMPD/blob-tampered.bin" > "$LOG.f" 2>&1 <<'PYEOF'
import base64, hashlib, sys
blob = open(sys.argv[1], "rb").read()
cid = "b" + base64.b32encode(bytes([0x01, 0x55, 0x12, 0x20]) + hashlib.sha256(blob).digest()).decode().lower().rstrip("=")
print("bafkreifcy4wykdscbdxnc3ynbbmtf6jsif72hssxclfp6l3xkbssxh3j5i")
print(cid)
PYEOF
[ "$(sed -n 1p "$LOG.f")" != "$(sed -n 2p "$LOG.f")" ]; ok $? "f: flipped byte → CID mismatch RED"
rm -rf "$TMPD"

# e) --pair-charge iki-yolu (sentetik-eş + gerçek-fark):
"$PY" - > "$LOG.e" 2>&1 <<'PYEOF'
import json, subprocess, sys, pathlib, tempfile
fx = json.load(open("docs/pairing/pairing-fixture.json"))
charge = fx["tamga_observed"]["charge_record"]["value"]
our = charge["delivery_hash"]["hex"]
W = pathlib.Path(tempfile.mkdtemp())
(W / "ledger.jsonl").write_text(json.dumps(charge) + "\n")
# eş-durum:
(W / "eq.json").write_text(json.dumps({"receipt": {"contentHash": "0x" + our}}))
r_eq = subprocess.run([sys.executable, "tools/verify_dx402_vector.py", "--pair-charge", str(W / "eq.json"), str(W / "ledger.jsonl")], capture_output=True, text=True)
# farklı-durum:
(W / "diff.json").write_text(json.dumps({"receipt": {"contentHash": "0x5d6293910d4b4c4f63d45800d3b8cb5f176a6bdd96b0eae1b0a2706b295c2b26"}}))
r_diff = subprocess.run([sys.executable, "tools/verify_dx402_vector.py", "--pair-charge", str(W / "diff.json"), str(W / "ledger.jsonl")], capture_output=True, text=True)
print("rc_eq=", r_eq.returncode, "rc_diff=", r_diff.returncode)
sys.exit(0 if (r_eq.returncode == 0 and r_diff.returncode == 1) else 1)
PYEOF
ok $? "e: pair-charge cross-bridge (equal→PASS, differing→RED)"

echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ]

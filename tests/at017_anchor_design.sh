#!/usr/bin/env bash
# AT-017 - F1-anchor-design-vector (const-YOK; sekl-in-D5-matematigi-dondurulur)
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AT-017/$(date +%F)}/at017.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
cd "$(cd "$(dirname "$0")/.." && pwd)"

python3 - > "$LOG.1" 2>&1 <<'PYEOF'
import json, hashlib, sys, pathlib
sys.path.insert(0, ".")
from tamga_validator import jcs
rec = json.loads(pathlib.Path("tests/vectors/anchor-v0-design/anchor-design-vector.json").read_text(encoding="utf-8"))
body = {k: v for k, v in rec.items() if k not in ("h", "node_sig")}
h = hashlib.sha256((rec["prev"].encode() + jcs(body))).hexdigest()
assert h == rec["h"], (h, rec["h"])
print("anchor-kaydi-D5-uyumlu (yeniden-hesap=vector-h)")
PYEOF
ok $? "anchor-sekli: D5-matematigi-uyumlu (yeniden-hesap=vector)"

python3 - > "$LOG.2" 2>&1 <<'PYEOF'
import json, pathlib
rec = json.loads(pathlib.Path("tests/vectors/anchor-v0-design/anchor-design-vector.json").read_text(encoding="utf-8"))
assert rec["anchor_version"] == "TAMGA_EXTERNAL_ANCHOR_V1"
assert rec["foreign_registry"] == "apodix/epoch"
assert rec["foreign_fact"].startswith("0x") and len(rec["foreign_fact"]) == 66
assert rec["verified_at"].endswith("Z")
print("tasarim-sozlesmesi-alanlari-tam (4.4-parite-beyanli)")
PYEOF
ok $? "anchor-sekli: tasarim-sozlesmesi-alanlari (4.4-parite)"

python3 - > "$LOG.3" 2>&1 <<'PYEOF'
import sys
sys.path.insert(0, ".")
import tamga_verify_mini as mv
assert "APODIX_EPOCH_ROOT_V1" in mv.KNOWN_FOREIGN_TAGS
print("mini-verifier KNOWN_FOREIGN_TAGS: epoch-root-etiketi-halen-bilinir")
PYEOF
ok $? "mini-verifier: KNOWN_FOREIGN_TAGS-paritesi-korunuyor"

echo "RESULT: $PASS PASS, $FAIL FAIL - log: $LOG"
[ "$FAIL" -eq 0 ]

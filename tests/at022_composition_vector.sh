#!/usr/bin/env bash
# AT-022 - kompozisyon-vektörü (E1; RFC-009-DRAFT batch-leaf matematiği; op/const YOK)
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AT-022/$(date +%F)}/at022.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
cd "$(cd "$(dirname "$0")/.." && pwd)"

VEC=tests/vectors/anchor-v0-design/composition-fixture.json

# 1) Üretici-temiz-koşum (deterministik: her-koşumda-aynı-fixture)
python3 tests/vectors/anchor-v0-design/composition_vector.py > "$LOG.1" 2>&1
ok $? "üretici: üç-iddia-yeşil (izdüşüm/sunum/çapraz-teyit)"

# 2) Donuk-vektör-sözleşmesi: alan-tamlığı + dönmüş-sabitler
python3 - > "$LOG.2" 2>&1 <<'PYEOF'
import json, pathlib
d = json.loads(pathlib.Path("tests/vectors/anchor-v0-design/composition-fixture.json").read_text())
assert d["composition_version"] == "TAMGA_COMPOSITION_VECTOR_V1"
assert len(d["tamga_chain_head"]) == 64 and int(d["tamga_chain_head"], 16) > 0
assert d["cross_check"]["epoch_10_root_match"] is True
assert d["claims"]["claim_1_projection"] == "pass"
assert d["claims"]["claim_2_presentation_only"] == "pass"
assert d["claims"]["claim_3_cross_check"] == "pass"
assert "presentation-only" in d["composition"]["note"] or "sunum-paritesi" in d["composition"]["note"]
print("vektör-sözleşmesi-tam (sabitler+alanlar+dürüstlük-notu)")
PYEOF
ok $? "vektör-sözleşmesi: alanlar + presentation-only-notu"

# 3) ÇAPRAZ-TEYİT-REJenerasyonu: epoch-10 kökü yeniden katlanır ve EŞİŞİR
python3 - > "$LOG.3" 2>&1 <<'PYEOF'
import json, pathlib, sys
sys.path.insert(0, ".")
from tamga_keccak import keccak256
K = lambda b: bytes.fromhex(keccak256(b).hex())
FELT32 = lambda s: int(s.removeprefix("0x"), 16).to_bytes(32, "big")
feuille = lambda s: K(K(FELT32(s)))
def oz_root(leaves):
    fl = sorted(leaves); n = len(fl); buf = [None]*(2*n-1)
    for i, f in enumerate(fl): buf[2*n-2-i] = f
    for i in range(n-2, -1, -1):
        a, b = buf[2*i+1], buf[2*i+2]
        buf[i] = K(a+b) if a < b else K(b+a)
    return buf[0]
ep = json.loads(pathlib.Path(".evidence/APODIX-EPOCH-10/2026-09-10/epoch-manifest-10.json").read_text())
r = "0x" + oz_root([feuille(f) for f in ep["leaves"]]).hex()
assert r == ep["root"], (r, ep["root"])
print("epoch-10-kökü-bağımsız-yeniden-katıldı-ve-EŞİŞTİ (", len(ep["leaves"]), "yaprak )")
PYEOF
ok $? "çapraz-teyit: epoch-10-kökü-yeniden-üretim (tamga_keccak, 57-yaprak)"

# 4) DETERMİNİZM: ikinci-koşum-üreticisi-birebir-aynı-fixture'ı-verir
cp "$VEC" /tmp/at022-first.json
python3 tests/vectors/anchor-v0-design/composition_vector.py > "$LOG.4" 2>&1
python3 - >> "$LOG.4" 2>&1 <<'PYEOF'
import json, pathlib
a = json.loads(pathlib.Path("/tmp/at022-first.json").read_text())
b = json.loads(pathlib.Path("tests/vectors/anchor-v0-design/composition-fixture.json").read_text())
assert a == b, "üretici-deterministik-DEĞİL (iki-koşum-farklı-fixture)"
print("determinizm: iki-koşum-birebir-aynı-vektör")
PYEOF
ok $? "determinizm: çift-koşum-bayt-birebir"

echo "RESULT: $PASS PASS, $FAIL FAIL - log: $LOG"
[ "$FAIL" -eq 0 ]

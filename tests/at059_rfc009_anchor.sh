#!/usr/bin/env bash
# AT-059: RFC-009 EXTERNAL-CHAIN-ANCHOR — 'anchor'-op'u-üretim-koduna-girdi.
#
# RFC-009-§2'nin-beş-kuralı (R9-1..R9-5) cmd_anchor'da-uygulanır. Bu-test
# hem-GREEN-yolunu-hem-dört-negatif-sınıfı-kilitler:
#   R9-2: bilinmeyen-foreign_registry → RED (reason 7)
#   R9-3: kanonik-olmayan-0x+64-lowercase → RED (reason 8)
#   R9-4: RFC3339-UTC-Z-değil → RED (reason 8)
#   argüman: eksik → RED (reason 1)
#
# KRİTİK-İLKEL: anchor-yalnızca-KAYIT-yapar, dış-fact'i-DOĞRULAMAZ (R9-5:
# presentation-only). Bu-test'in-green-giydirme-yapan-bir-sürümüne-izın-yok.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-059/$(date +%F)/at059.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

FACT="0x02362521254a8ca4f75097267655f6aeb8524217a25c261f60538edc367136e2"
DIGEST="0x997c497ef5fe81b98290e990cd8f62e674bd55db8ab3c3ea85d3931b1e6ff71d"

note "AT-059: RFC-009 external-chain-anchor (pilot-şimdi-açık)"

PKG="$(mktemp -d)"
python3 tamga_runner.py quickstart "$PKG" >> "$LOG" 2>&1 || { FAIL=$((FAIL+1)); note "  FAIL quickstart"; }

# 1) GREEN: geçerli-anchor-zincire-girer-ve-D5-hash'ini-taşır
note "1) geçerli-anchor-zincire-girer"
python3 tamga_runner.py anchor "$PKG" \
  --foreign-registry apodix/epoch \
  --foreign-fact "$FACT" --foreign-digest "$DIGEST" \
  --verified-at 2026-09-10T07:32:08Z \
  --tool "verifier_epoque + tamga_keccak (dual-impl)" >> "$LOG" 2>&1
RC=$?
if [ $RC -eq 0 ]; then PASS=$((PASS+1)); note "  PASS 1) anchor-GREEN"; else FAIL=$((FAIL+1)); note "  FAIL 1)"; cat "$LOG"; fi

# 2) R9-2: bilinmeyen-registry → RED
note "2) R9-2 bilinmeyen-foreign_registry"
python3 tamga_runner.py anchor "$PKG" \
  --foreign-registry evil/registry \
  --foreign-fact "$FACT" --foreign-digest "$DIGEST" \
  --verified-at 2026-09-10T07:32:08Z >> "$LOG" 2>&1
RC=$?
if [ $RC -ne 0 ]; then PASS=$((PASS+1)); note "  PASS 2) R9-2-RED"; else FAIL=$((FAIL+1)); note "  FAIL 2) green-giydirdi"; fi

# 3) R9-3: kanonik-olmayan-digest (büyük-harf + kısa) → RED
note "3) R9-3 kanonik-olmayan-0x+64-lowercase"
python3 tamga_runner.py anchor "$PKG" \
  --foreign-registry apodix/epoch \
  --foreign-fact "0X02362521254A8CA4" --foreign-digest "$DIGEST" \
  --verified-at 2026-09-10T07:32:08Z >> "$LOG" 2>&1
RC=$?
if [ $RC -ne 0 ]; then PASS=$((PASS+1)); note "  PASS 3) R9-3-RED"; else FAIL=$((FAIL+1)); note "  FAIL 3) green-giydirdi"; fi

# 4) R9-4: RFC3339-UTC-Z-değil → RED
note "4) R9-4 verified_at-RFC3339-Z-değil"
python3 tamga_runner.py anchor "$PKG" \
  --foreign-registry apodix/epoch \
  --foreign-fact "$FACT" --foreign-digest "$DIGEST" \
  --verified-at "2026-09-10" >> "$LOG" 2>&1
RC=$?
if [ $RC -ne 0 ]; then PASS=$((PASS+1)); note "  PASS 4) R9-4-RED"; else FAIL=$((FAIL+1)); note "  FAIL 4) green-giydirdi"; fi

# 5) R9-1 + R9-5: yazılan-kayıt-sabit-sürüm-ve-presentation-only-etiketi-taşır
note "5) R9-1/R9-5 kayıt-sürüm-ve-presentation-only"
python3 - <<PYEOF >> "$LOG" 2>&1
import json, pathlib
rows = [json.loads(l) for l in pathlib.Path("$PKG/ledger.jsonl").read_text(
    encoding="utf-8").splitlines() if l.strip()]
anc = [r for r in rows if r.get("op") == "anchor"]
assert anc, "anchor-kaydı-yok"
a = anc[0]
assert a["anchor_version"] == "TAMGA_EXTERNAL_ANCHOR_V1", f"sürüm-yanlış: {a.get('anchor_version')}"
assert a.get("presentation_only") is True, "R9-5-presentation-only-etiketi-yok"
assert a["foreign_fact"] == "$FACT"
assert a["foreign_registry"] == "apodix/epoch"
# D5: hash-zincire-gerçek-girmiş (seq+prev+h-üçlüsü-tam)
assert all(k in a for k in ("seq", "prev", "h")), "D5-üçlü-eksik"
print("  R9-1-sürüm-sabit + R9-5-presentation-only + D5-üçlü-tam")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then PASS=$((PASS+1)); note "  PASS 5) R9-1/R9-5-aynen"; else FAIL=$((FAIL+1)); note "  FAIL 5)"; cat "$LOG"; fi

rm -rf "$PKG"
echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-059: RFC-009 external-chain-anchor"
[[ $FAIL -eq 0 ]]

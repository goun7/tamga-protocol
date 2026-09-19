#!/usr/bin/env bash
# AT-046: tri-product spec↔code-divergence-tarayıcısı.
#
# Sester'ın-önerisi: "üç ürünü birden tarayan tek checklist oluşturabiliriz."
# Bu-test-Tamga-sütununun-doldurulduğunu-ve-HİÇBİR-divergence-kalmadığını-
# kanıtlar. Üç-erratum-dersi-bu-tarayıcıda-birleşti:
#   Veridict-D12 → spec-only-sınıfı   (spec'te-yazıyor-kodda-yok)
#   Sester-K0.1  → code-only-sınıfı   (kodda-var-spec'te-yok — ERRATUM-A1)
#   Tamga-E1     → iki-yön-de-erratum
#
# Tarayıcı-her-kuralı-ÜRETİM-üzerinde-ölçer (sadece-iddia-etmez):
#   YÖN-A: kırım-vektörü-üret → RED-gelmeli (kod-uyguluyor)
#   YÖN-B: spec-needle-ara    → belgeli-mi
#   Ek:    bağımsız-verifier-aynı-karara-varıyor-mu (parite-ayrışması)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

PASS=0; FAIL=0
note() { echo "  $*"; }
D="$(date +%F)"
mkdir -p ".evidence/AT-046/$D"
LOG=".evidence/AT-046/$D/at046.log"
: > "$LOG"

note "AT-046 tri-product spec↔code-divergence-tarayıcısı"

# 1) tarayıcı-çalışır-ve-EXIT-0 (divergence-yok)
note "1) tarayıcı — sıfır-divergence"
python3 tools/spec_code_scan.py --format json > /tmp/at046.json 2>> "$LOG"
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS tarayıcı-rc=0"
else FAIL=$((FAIL+1)); note "  FAIL divergence-kaldı rc=$RC"; cat "$LOG"; fi

# 2) özet-alanları-doğru
note "2) özet — 18-aligned, 0-divergence"
python3 - <<'PYEOF' >> "$LOG" 2>&1
import json
d = json.load(open("/tmp/at046.json"))
s = d["summary"]
assert s["aligned"] == 18, f"aligned={s['aligned']} beklenen-18"
assert s["spec_only"] == 0, f"spec-only-divergence: {s['spec_only']}"
assert s["code_only"] == 0, f"code-only-divergence: {s['code_only']}"
assert s["untested"] == 0
# her-kural-için-iki-yön-de-kanıtlanmış-olmalı
for r in d["rules"]:
    assert r["spec_documented"], f"{r['id']} spec'te-belgeli-değil"
    assert r["code_enforced"] is not False, f"{r['id']} kod-tarafı-ölçülemedi"
print("18-kural-hepsi-çift-yönlü-kanıtlandı (9-ledger+9-anchor)")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 9-kural-çift-yönlü"
else FAIL=$((FAIL+1)); note "  FAIL kural-kanıtı-eksik"; cat "$LOG"; fi

# 3) bağımsız-verifier-paritesi — ayrışma-yok
note "3) parite — bağımsız-verifier-aynı-kararlar"
python3 - <<'PYEOF' >> "$LOG" 2>&1
import json
d = json.load(open("/tmp/at046.json"))
bad = [r["id"] for r in d["rules"] if r["independent_parity"] is False]
assert not bad, f"bağımsız-verifier-ayrışması: {bad}"
n = sum(1 for r in d["rules"] if r["independent_parity"] is True)
assert n >= 18, f"parite-ölçülen-kural-sayısı={n}"
print(f"bağımsız-verifier {n}-kuralda-üretim-ile-aynı")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS bağımsız-verifier-paritesi"
else FAIL=$((FAIL+1)); note "  FAIL parite-bozuk"; cat "$LOG"; fi

# 4) erratum'lar-spec'te-belgeli (E1-a/E1-b/A1)
note "4) erratum-belgeleri — üç-ders-de-yazılı"
python3 - <<'PYEOF' >> "$LOG" 2>&1
import pathlib
for f, needle in [("tests/conformance/spec/LEDGER-SPEC.md", "Erratum E1"),
                  ("tests/conformance/spec/ANCHOR-SPEC.md", "Erratum A1")]:
    t = pathlib.Path(f).read_text(encoding="utf-8")
    assert needle in t, f"{needle} {f}-dosyasında-yok"
print("E1(ledger) + A1(anchor) erratum'ları-belgeli")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS erratum'lar-belgeli"
else FAIL=$((FAIL+1)); note "  FAIL erratum-eksik"; cat "$LOG"; fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-046-kapısı: tri-product-checklist-Tamga-sütunu-sıfır-divergence"
[[ $FAIL -eq 0 ]]

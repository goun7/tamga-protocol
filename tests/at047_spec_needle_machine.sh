#!/usr/bin/env bash
# AT-047: spec-needle-machine — "spec'te-yazıyor" gözle-değil-makine-ile.
#
# DERS (Sester-2026-09-20): "benim-YÖN-B-negatif-kontrolüm-elle-grep'ti, yani
# spec'te-yazıyor-derken-göz-ile-bakmıştım." Aynısı-bizde-de-vardı — AT-046'nın
# spec-coverage'si-bir-needle-listesi-ile-ölçülüyor-ama-o-liste-ELLE-yazıldı.
# Bu-test-listenin-kendisini-makineye-taşır.
#
# İkinci-ders (E1(c)): op-kümesi-tükenmezliği-gözle-kanıtlanamaz. Deneyi-yaptım
# — kısıt-ekleyip-tam-suite-koştum: DALGA-1-2-FAIL (verify-lite'da-op:"note",
# AT-045'de-BILINMEYEN). SONRA-jsonl'ları-taradım: `replace`-CANLI-oturum-
# ledger'ında (__pycache__/session.v3.jsonl) — spec'te-yoktu. **Sester-K0.2'nin
# birebir-bizdeki-örneği.**
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

PASS=0; FAIL=0
note() { echo "  $*"; }
D="$(date +%F)"
mkdir -p ".evidence/AT-047/$D"
LOG=".evidence/AT-047/$D/at047.log"
: > "$LOG"

note "AT-047 spec-needle-machine (YÖN-B-artık-makinede)"

# 1) tüm-needle'lar-spec'te-var
note "1) 18-needle — makine-ile-aranır"
python3 tools/spec_needle_machine.py >> "$LOG" 2>&1
if [ $? -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 18/18-needle-belgeli"
else FAIL=$((FAIL+1)); note "  FAIL needle-düştü"; cat "$LOG"; fi

# 2) op-kümesi-uyumu (E1(c)-otomatik-yakalama)
note "2) op-kümesi — spec'te-yazmayan-ledger-op'u-yakalar"
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys
sys.path.insert(0, "tools")
from spec_needle_machine import check_op_coverage
undoc, found = check_op_coverage()
assert not undoc, f"spec-dışı-ledger-op'ları-keşfedildi: {undoc}"
assert "charge" in found and "grant" in found, "çekirdek-op'lar-yok"
# LEDGER-FİLTRESİ-kanıtı: session.v3.jsonl-'replace'-gürültüsü-artık-yakalanmaz
assert "replace" not in found, \
    "replace-tool/result-gürültüsü-hâlâ-ledger-op-sayılıyor (filtre-bozuk)"
# E1(c)-düzeltme: yanlış-bulguyu-spec'te-teslim-eden-itàiraf-yazılı-olmalı
import pathlib
spec = pathlib.Path("tests/conformance/spec/LEDGER-SPEC.md").read_text(encoding="utf-8")
assert "E1(c)-düzeltme" in spec, "yanlış-bulgu-itàrafı-spec'te-yok"
print(f"op-kümesi-uyumlu: {sorted(found)}")
PYEOF
if [ $? -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS op-kümesi-spec-ile-uyumlu"
else FAIL=$((FAIL+1)); note "  FAIL op-kümesi-uyumsuz"; cat "$LOG"; fi

# 3) fail-closed-dalga-YÖNTEMİ-kanıtlandı (deney-sonucu-dokümante)
note "3) dalga-yöntemi — deney-kanıtı-dokümante"
python3 - <<'PYEOF' >> "$LOG" 2>&1
import pathlib
spec = pathlib.Path("tests/conformance/spec/LEDGER-SPEC.md").read_text(encoding="utf-8")
# E1(c)-erratum'u-dalga-yöntemini-anlatıyor-olmalı
assert "fail-closed-dalga-deneyi" in spec or "fail-closed" in spec, \
    "E1(c)-dalga-yöntemini-anlatmıyor"
assert "Gözle" in spec and "tükenmezlik" in spec, "gözle-uyarı-yazılı-değil"
print("dalga-yöntemi-ve-gözle-uyarı-spec'te-dokümante")
PYEOF
if [ $? -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS dalga-yöntemi-dokümante"
else FAIL=$((FAIL+1)); note "  FAIL dokümantasyon-eksik"; cat "$LOG"; fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-047-kapısı: YÖN-B-makinede + op-kümesi-otomatik"
[[ $FAIL -eq 0 ]]

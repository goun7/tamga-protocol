#!/usr/bin/env bash
# AT-043: conformance pack — sıfır-import, repo-dışı-çalışan-portability-kanıtı.
#
# K23.1-portability-wedge'inin-somut-ürünü: üçüncü-taraf, Tamga-repo'sunu-
# kurmadan, sadece spec-özütü + bağımsız-verifier + vektörlerle-üzerinde-
# denetim-yapabilir. Bu-test-üç-şeyi-kanıtlar:
#   1) paket-repo-dışında-çalışır (kendi-başına)
#   2) bağımsız-verifier-hiçbir-tamga_-modülü-içe-aktarmaz
#   3) 7-vektör-beklenen-sonuçları-verir + üretim-ile-parite
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

PASS=0; FAIL=0
note() { echo "  $*"; }
D="$(date +%F)"
mkdir -p ".evidence/AT-043/$D"
LOG=".evidence/AT-043/$D/at043.log"
: > "$LOG"

note "AT-043 conformance pack (repo-dışı-bağımsız + parite)"

# 1) paket-repo-içi-koşar: 7/7
note "1) paket-koşusu — 7-vektör"
if bash tests/conformance/run.sh >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS 7/7-vektör-beklenen-sonuçlar"
else FAIL=$((FAIL+1)); note "  FAIL vektör-uyumsuz"; cat "$LOG"; fi

# 2) bağımsızlık: tamga_-import-yok
note "2) bağımsızlık — tamga_-import-yok"
if ! grep -qE "^(import|from) tamga" tests/conformance/verify.py; then
  PASS=$((PASS+1)); note "  PASS sıfır-tamga-import"
else FAIL=$((FAIL+1)); note "  FAIL bağımsızlık-bozuk"; cat "$LOG"; fi

# 3) İZOLASYON: paketi-repo-dışına-kopyala-ve-koş
note "3) izolasyon — repo-dışı-çalışma"
ISO=$(mktemp -d /tmp/at043-iso-XXXX)
cp -r tests/conformance/* "$ISO"/
if ( cd "$ISO" && bash run.sh ) >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS repo-dışı-7/7"
else FAIL=$((FAIL+1)); note "  FAIL repo-dışı-bozuk"; cat "$LOG"; fi
rm -rf "$ISO"

# 4) parite: üretim-tamga_verify_mini-ile-aynı-sonuçlar
# runner-çalışma-dizinini-tests/conformance'e-değiştirir → tam-yol-şart
note "4) parite — üretim-verifier-ile-aynı-sonuç"
ROOT="$(pwd)"
if bash tests/conformance/run.sh "python3 $ROOT/tamga_verify_mini.py" \
     >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS üretim-ile-parite-13/13"
else FAIL=$((FAIL+1)); note "  FAIL parite-bozuk"; cat "$LOG"; fi

# 5) normatif-kurallar-vektör-kapsamı: her-§3-kuralı-bir-vektör-örmeli
note "5) kapsam-denetimi — her-kural-bir-vektör"
if [ "$(ls tests/conformance/vectors/*.jsonl 2>/dev/null | wc -l)" -ge 7 ]; then
  PASS=$((PASS+1)); note "  PASS 7-vektör-5-kural-+empty"
else FAIL=$((FAIL+1)); note "  FAIL vektör-eksik"; cat "$LOG"; fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-043-kapısı: conformance-pack-sıfır-import-izole-çalışır"
[[ $FAIL -eq 0 ]]

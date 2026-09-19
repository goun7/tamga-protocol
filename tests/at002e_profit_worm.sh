#!/usr/bin/env bash
# AT-002e: kâr-solucanğı — λ-eşiğinin-geçerliliğini-sorgular (P9'suz-ön-iş)
# AT-002-TASLAK'taki λ≥2000-iddiası ÖLÇÜLDÜ ve YANLIŞ-çıktı:
# node-kâr-eşiği-maliyet-bandına-bağlıdır (300/1000/1500), tek-sayı-değildir.
# Bu-test-bulgunun-doğruluğunu-kilitler: eşik-altı-kâr- <%50, eşik-üstü-≥%50.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

PASS=0; FAIL=0
note() { echo "  $*"; }
D="$(date +%F)"
mkdir -p ".evidence/AT-002e/$D"
LOG=".evidence/AT-002e/$D/at002e.log"
: > "$LOG"

note "AT-002e kâr-solucanğı (λ-eşik-geçerliliği)"

# 1) araç-çalışır-ve-solucan-geçerli
note "1) solucan-denetimi — bant-eşikleri-geçerli"
if python3 tools/at002e_profit_worm.py --check >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS solucan-geçerli (rc=0)"
else FAIL=$((FAIL+1)); note "  FAIL solucan-geçersiz"; cat "$LOG"; fi

# 2) eşik-altı-gerçekten-kâr-edemez: λ=50-de-tüm-bantlar- <%50
note "2) eşik-altı — λ=50 tüm-bantlarda-kâr-edemez"
if python3 -c "
import sys; sys.path.insert(0,'tools')
from at002e_profit_worm import node_income, COST_BANDS
for c in COST_BANDS:
    p = node_income(50, c, 800)['kâr-olasılığı']
    assert p < 0.5, f'λ=50@\${c} kâr={p} — eşik-altı-kâr-ediyor'
    print(f'  λ=50@\${c:.0f}: kâr-olasılığı={p}')
" >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS eşik-altı-zararda"
else FAIL=$((FAIL+1)); note "  FAIL eşik-altı-kâr-ediyor"; cat "$LOG"; fi

# 3) eski-tek-eşik-2000-in-yanlışlığını-kanıtla: λ=500@$30-kâr-eder
note "3) eski-eşik-yanlış — λ=500@\$30 kâr-eder (2000-tek-eşik-RED)"
if python3 -c "
import sys; sys.path.insert(0,'tools')
from at002e_profit_worm import node_income
p = node_income(500, 30.0, 800)['kâr-olasılığı']
assert p > 0.5, f'λ=500@\$30 kâr={p} — bu-keşfe-zemin-olmaz'
print(f'  λ=500@\$30: kâr={p} — eski-eşik-2000-in-altında-ama-kâr-ediyor')
" >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS keşif-kanıtlı (eski-eşik-yanlış)"
else FAIL=$((FAIL+1)); note "  FAIL keşif-çöktü"; cat "$LOG"; fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-002e-kapısı: λ-eşik-geçerliliği (P9'suz-ön-iş; bulgu: eşik-bant-bağlı)"
[[ $FAIL -eq 0 ]]

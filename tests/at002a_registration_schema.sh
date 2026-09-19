#!/usr/bin/env bash
# AT-002a: manifest-keşif — registration-v1 şema-doğrulayıcı (Faz-3-ön-iş, P9'suz)
# ERC-8004 'registration-v1' şemasını Tamga manifest'inden üretir ve her olumsuz
# yolu belirli reason ile RED'ler. Kaynak: docs/ERC-8004-MAPPING.md §2.
#
# Önemli: bu test AĞDA koşmaz — P9 dolmadan Faz-3 başlamaz (ROADMAP K20-seçenek-3).
# Sadece şema-uyumluluğunu ve negatif yolları prova eder: AT-002a'nın taslak
# ısmarlama değil gerçek olduğunu kanıtlar.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

PASS=0; FAIL=0
note() { echo "  $*"; }
D="$(date +%F)"
mkdir -p ".evidence/AT-002a/$D"
LOG=".evidence/AT-002a/$D/at002a.log"
: > "$LOG"

note "AT-002a manifest-keşif (registration-v1 şema-doğrulama)"

# 1) produce + verify: geçerli-üretim-yeşil-olmalı
note "1) produce+verify — geçerli manifest GREEN"
MAN="/tmp/at002a-manifest.json"
python3 -c "
import json
print(json.dumps({'package':{'name':'tamga-ornek-ajani','version':'0.1'},
 'summary':'örnek-ajan','runtime':{'min_proof_level':1}}))" > "$MAN" 2>>"$LOG"
REG="/tmp/at002a-reg.json"
if python3 tools/registration_v1.py produce "$MAN" > "$REG" 2>>"$LOG" && \
   python3 tools/registration_v1.py verify  "$REG" 2>>"$LOG"; then
  PASS=$((PASS+1)); note "  PASS üretim+doğrulama GREEN"
else
  FAIL=$((FAIL+1)); note "  FAIL üretim/doğrulama RED"; cat "$LOG"
fi

# 2) JCS-paritesi: kanonik-form-belirlenebilir (ERC-8004-dosyaları-için-şart)
note "2) JCS-paritesi — kanonik-form-belirli"
if python3 -c "
import sys, json, hashlib; sys.path.insert(0,'.')
from tamga_canon import jcs
reg = json.load(open('$REG'))
c = jcs(reg)
assert len(c) > 0 and hashlib.sha256(c).hexdigest()
print('  JCS:', len(c), 'byte, sha256', hashlib.sha256(c).hexdigest()[:24])
" >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS JCS-paritesi (belirli-kanonik-form)"
else
  FAIL=$((FAIL+1)); note "  FAIL JCS-paritesi"; cat "$LOG"
fi

# 3) altı-negatif-yol: her-biri-belirli-reason-ile-RED
note "3) negatif-yollar — 6-kırılım-belirli-reason"
python3 - <<'PY' >> "$LOG" 2>&1
import json, sys
sys.path.insert(0, "tools")
from registration_v1 import verify
base = json.load(open("/tmp/at002a-reg.json"))
cases = {
  "eksik-alan":  {k:v for k,v in base.items() if k!="active"},
  "yanlis-type": {**base, "type":"human"},
  "trust-iddia": {**base, "supportedTrust":["crypto-economic"]},
  "onchain-v0":  {**base, "agentRegistry":"eip155:8453:0xabc"},
  "kotu-name":   {**base, "name":"!!@#"},
  "x402-string": {**base, "x402Support":"true"},
}
red = 0
for ad, c in cases.items():
    ok, reason = verify(c)
    assert not ok, f"{ad} RED-üretmedi"
    assert len(reason) > 3, f"{ad} reason-boş"
    red += 1
    print(f"  {ad:14} RED: {reason[:56]}")
assert red == 6, f"beklenen 6 RED, üretilen {red}"
print(f"  toplam: {red}/6 RED")
PY
rc=$?
if [[ $rc -eq 0 ]]; then
  PASS=$((PASS+1)); note "  PASS 6/6-negatif-yol-RED"
else
  FAIL=$((FAIL+1)); note "  FAIL negatif-yol-eksik"; cat "$LOG"
fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-002a-kapısı: registration-v1 şema-uyumluluğu (P9'suz-ön-iş)"
[[ $FAIL -eq 0 ]]

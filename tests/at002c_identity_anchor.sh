#!/usr/bin/env bash
# AT-002c: kimlik-çapası — node-kimliği ile makbuzun signer'ı bağlanır (Faz-3-ön-iş)
# ERC-8004 Identity-Registry henüz v0'da yok (P9); bu yüzden bağ ŞEMA-seviyesinde
# doğrulanır: bildirilen kimlik çapası geçerli eip155 bağı + signer-uyumu olmalı.
# Üretimde bunu tools/attest_verify_bagimsiz.py:258'deki signer==buyer karşılaştırması
# tamamlar — bu-test-onun-node-tarafıdır.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

PASS=0; FAIL=0
note() { echo "  $*"; }
D="$(date +%F)"
mkdir -p ".evidence/AT-002c/$D"
LOG=".evidence/AT-002c/$D/at002c.log"
: > "$LOG"

note "AT-002c kimlik-çapası (identity-anchor şema-doğrulama)"

GOOD="0x$(printf 'a%.0s' {1..40})"
OTHER="0x$(printf 'b%.0s' {1..40})"
REGADDR="0x$(printf 'c%.0s' {1..40})"

# 1) çapa-yok: v0'da-açık (geriye-uyumlu)
note "1) çapa-yok — v0'da-izinli (aç)"
if python3 -c "
import sys, json; sys.path.insert(0,'tools')
from registration_v1 import verify
base = json.load(open('/tmp/at002a-reg.json'))
ok, why = verify(base)
assert ok, why
print('  v0-çapa-yok: GREEN (aç)')
" >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS çapa-yok GREEN"
else FAIL=$((FAIL+1)); note "  FAIL çapa-yok RED"; cat "$LOG"; fi

# 2) çapa-iyi-ve-signer-uyumlu
note "2) çapa-iyi — signer-uyumlu GREEN"
if python3 -c "
import sys, json; sys.path.insert(0,'tools')
from registration_v1 import verify
base = json.load(open('/tmp/at002a-reg.json'))
c = {**base, 'tamgaIdentityAnchor': {'registry': f'eip155:8453:$REGADDR',
                                    'signerAddress': '$GOOD'},
     '_signer_address': '$GOOD'}
ok, why = verify(c)
assert ok, why
print('  çapa-uyumlu: GREEN')
" >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS çapa-uyumlu GREEN"
else FAIL=$((FAIL+1)); note "  FAIL çapa-uyumlu"; cat "$LOG"; fi

# 3) üç-negatif-yol: kötü-biçim / identity-mismatch / kötü-adres
note "3) negatif-yollar — 3-kırılım-belirli-reason"
python3 - <<'PY' >> "$LOG" 2>&1
import sys, json
sys.path.insert(0, "tools")
from registration_v1 import verify
base = json.load(open("/tmp/at002a-reg.json"))
GOOD = "0x" + "a"*40
OTHER = "0x" + "b"*40
REGADDR = "0x" + "c"*40
cases = {
  "kotu-bicim": {**base, "tamgaIdentityAnchor": {"registry": "sözcük"}},
  "identity-mismatch": {**base, "tamgaIdentityAnchor": {
      "registry": f"eip155:8453:{REGADDR}", "signerAddress": OTHER},
      "_signer_address": GOOD},
  "kotu-adres": {**base, "tamgaIdentityAnchor": {
      "registry": f"eip155:8453:{REGADDR}", "signerAddress": "0xqwe"}},
}
red = 0
for ad, c in cases.items():
    ok, why = verify(c)
    assert not ok, f"{ad} RED-üretmedi"
    assert len(why) > 3, f"{ad} reason-boş"
    red += 1
    print(f"  {ad:18} RED: {why[:56]}")
assert red == 3, f"beklenen 3 RED, üretilen {red}"
print(f"  toplam: {red}/3 RED")
PY
rc=$?
if [[ $rc -eq 0 ]]; then
  PASS=$((PASS+1)); note "  PASS 3/3-negatif-yol-RED"
else FAIL=$((FAIL+1)); note "  FAIL negatif-yol-eksik"; cat "$LOG"; fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-002c-kapısı: kimlik-çapası şema-doğrulama (P9'suz-ön-iş)"
[[ $FAIL -eq 0 ]]

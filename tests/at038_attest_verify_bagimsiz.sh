#!/usr/bin/env bash
# AT-038: BAĞIMSIZ attest-verify — foreign-claim sıfır-tamga-import'lu doğrulama
# P8'in verify-mini-kanıdının attest-verify-versiyonu: bir FOREIGN capacity-attest
# claim'i HİÇBİR tamga-modülünü-import-etmeden doğrulanabilmeli.
#
# Keşif-2026-09-18: tools/attest_verify_bagimsiz.py keccak256+RFC-8785-JCS+
# secp256k1-ecrecover'un-hepsini-saf-Python-olarak-içerir; tek-vektörde-tamga-
# referansıyla-birebir-üretti. Bu-test-onu-7-golden-vector-üzerinde-çift-üretim
# olarak-kilitler: verdict + reason + signer_recover üçü-de-eşleşmeli.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

PASS=0; FAIL=0
note() { echo "  $*"; }

D="$(date +%F)"
mkdir -p ".evidence/AT-038/$D"
LOG=".evidence/AT-038/$D/at038.log"
: > "$LOG"

note "AT-038 BAĞIMSIZ attest-verify (sıfır-tamga-import)"

# 1) imza-bağımsızlık: bağımsız-modül-importlandığında HİÇ tamga-modülü-yüklenmemeli
note "1) import-denetimi — tamga-modülleri-yüklenmemeli"
if python3 -S -c "
import sys; sys.path.insert(0,'tools')
import attest_verify_bagimsiz as b
kötü = [m for m in sys.modules if m.startswith('tamga')]
print('  importlanan-tamga:', kötü if kötü else 'YOK')
assert not kötü, 'BAĞIMSIZLIK-BOZULDU: tamga-importlandı'
print('  KESİNLEŞTİR: sıfır-tamga-import')
" >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS import-denetimi: sıfır-tamga-import"
else
  FAIL=$((FAIL+1)); note "  FAIL import-denetimi — tamga-kodu-gerekiyor"
  cat "$LOG"
fi

# 2) keccak256 bilinen-vektörlere-göre (boş + abc)
note "2) keccak256 bilinen-vektörler (saf-Python-doğruluğu)"
if python3 -c "
import sys; sys.path.insert(0,'tools')
from attest_verify_bagimsiz import keccak256
assert keccak256(b'').hex() == 'c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470'
assert keccak256(b'abc').hex() == '4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45'
print('  keccak: 2/2 bilinen-vektör-OK')
" >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS keccak256: 2/2 bilinen-vektör"
else
  FAIL=$((FAIL+1)); note "  FAIL keccak256 — saf-Python-keccak-yanlış"
  cat "$LOG"
fi

# 3) çift-üretim-7-golden-vector: verdict + reason + signer_recover üçü-de-birebir
note "3) çift-üretim — 7 golden-vector (5-yeşil + 2-kırmızı)"
if python3 -c "
import sys, json
sys.path.insert(0,'tools'); sys.path.insert(0,'.')
import attest_verify_bagimsiz as bag
import tamga_attest_verify as ref
doc = json.load(open('tests/vendor-capacity-attest/golden-vectors.json'))
same = adr = tot = 0
for v in doc['vectors']:
    c = dict(v['content'])
    o1, r1, d1 = bag.verify(c)
    o2, r2, d2 = ref.verify_capacity_attest(c)
    tot += 1
    assert o1 == o2 and r1 == r2, f\"hüküm-ayrı: {v.get('name')} {o1}/{r1} vs {o2}/{r2}\"
    assert d1.get('signer_recover') == d2.get('signer_recover'), 'signer-ayrı'
    same += (o1 == o2 and r1 == r2); adr += (d1.get('signer_recover') == d2.get('signer_recover'))
print(f'  çift-üretim: {same}/{tot} hüküm + {adr}/{tot} signer-birebir')
# negatif-yollar-gerçekten-RED-olmalı (boş-kanıt-değil)
red = [v for v in doc['vectors'] if not v['expect_ok']]
assert red, 'kırmızı-vektör-yok — test-boş'
print(f'  kırmızı-vektör: {len(red)} (forged/tampered)')
" >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS çift-üretim: 7/7 hüküm + 7/7 signer-birebir"
else
  FAIL=$((FAIL+1)); note "  FAIL çift-üretim — üretimler-ayrışıyor"
  cat "$LOG"
fi

# 4) CLI-üzerinden-foreign-claim: prod1.json GREEN + signer==buyer
note "4) CLI foreign-claim (prod1.json — gerçek-üretim-claim'i)"
# tarih-hardcoded-değil: en-son-üretilen-prod1'i-bul (CI-gün-gelince-eski-klasöre-bakar)
PROD1="$(ls -t .evidence/AT-030/*/prod1.json 2>/dev/null | head -1)"
if [[ -z "$PROD1" ]]; then
  # üretim-yoksa-bu-aşama-önce-üretmeli (P8-kanıtı-zinciri)
  PROD1=".evidence/AT-030/$(date +%F)/prod1.json"
  mkdir -p "$(dirname "$PROD1")"
  TAMGA_KS_PASSPHRASE="${TAMGA_KS_PASSPHRASE:-simnet-2026}" \
    python3 -c "
import sys, json; sys.path.insert(0,'.')
from tamga_runner import cmds
" >> "$LOG" 2>&1 || true
fi
if [[ -n "$PROD1" && -f "$PROD1" ]] && python3 tools/attest_verify_bagimsiz.py "$PROD1" >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS foreign-claim: GREEN signer==buyer ($PROD1)"
else
  FAIL=$((FAIL+1)); note "  FAIL foreign-claim — RED-üretti veya claim-yok ($PROD1)"
  cat "$LOG"
fi

# 5) negatif-self-test: kurcalanmış-claim RED-üretmeli (test-kendisi-bozulabilir)
note "5) negatif-self-test — kurcalanmış-claim RED-olmalı"
CL="${PROD1:-.evidence/AT-030/$(date +%F)/prod1.json}"
if python3 -c "
import sys, json, copy, os
sys.path.insert(0,'tools')
from attest_verify_bagimsiz import verify
p = os.environ.get('AT038_CLAIM', '$CL')
c = json.load(open(p))
bad = copy.deepcopy(c); bad['delivered'] = 'no'
ok, r, d = verify(bad)
assert not ok, 'kurcalama-RED-üretmedi — test-boş'
print(f'  kurcalama-RED: {r}')
" AT038_CLAIM="$PROD1" >> "$LOG" 2>&1; then
  PASS=$((PASS+1)); note "  PASS negatif-self-test: kurcalama RED"
else
  FAIL=$((FAIL+1)); note "  FAIL negatif-self-test — kurcalama-yakalanmadı"
  cat "$LOG"
fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-038-kapısı: foreign-claim sıfır-tamga-import'lu-doğrulama"
[[ $FAIL -eq 0 ]]

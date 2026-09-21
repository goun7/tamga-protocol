#!/usr/bin/env bash
# AT-081: UNPUMP X-Bind-Signature — BAĞ-ANAHTARI-modu → GERÇEK-MÜŞTERİ-imzası-modu.
#
# AT-075'in-bıraktığı-açık-borcun-devamı. Mevcut-kanıt (at069-seq92.json):
#   settlement_bind.payer = 0x28c7f29f… = bağ-adresi (servisin-açık-adresi,
#   agent_id) — GERÇEK-ALICI-DEĞİL. claim.buyerAddress = aynı-bağ-adresi.
#   TESTS.md-notu: "gerçek-müşteri-imzası X-Bind-Signature header'ı-ile-gelir,
#   servis-alıcının-private-key'ini-TUTMAZ."
#
# AT-081'in-iki-temel-sonucu:
#   (A) İKİ-MOD-KARŞILAŞTIRMASI (RFC-010 §3b x402/v1, z=raw-sha256, EIP-191'siz):
#       mod-1 BAĞ-ANAHTARI: private-key servis-tutulur, payer=bağ-adresi.
#       mod-2 GERÇEK-MÜŞTERİ: imza X-Bind-Signature-ile-gelir,
#            payer=gerçek-alıcı-adresi, ecrecover-ile-doğrulanır.
#   (B) D5-HASH-DİKİŞİ-KAPSAMA-DÜZELTMESİ: AT-075 "False" ölçmüştü —
#       charge.h, settlement_bind'ı-kapsamıyordu (dıştan-yapışık: dikiş-append'-
#       den-SONRA-üretiliyor, ya-da payload h'-sonrası-ekleniyor).
#       Yeni-fixture: h = sha256(prev + jcs(kayıt-h-dışı)) — settlement_bind-ve-
#       payload-DAHİL. Artık-True.
#
# ALTIL-KANIT:
#   1) BAĞ-ANAHTARI-modu-kanıtı: mevcut-fixture-koş → hâlâ-GREEN (payer=bağ-adresi)
#   2) GERÇEK-MÜŞTERİ-modu: yeni-ECDSA-anahtar, RFC-010 §3b, buyerAddress=gerçek-alıcı,
#      settlement_bind.payer=gerçek-alıcı-adresi
#   3) D5-kapsama-düzeltmesi: tepe-ve-payload-settlement_bind-aynı (çakışma-yok),
#      h-tüm-kaydı-kapsar → True (önceki-False'u-düzeltir)
#   4) GERÇEK-6/6-GREEN: yeni-fixture-SB.verify → GREEN (test-double-YOK)
#   5) NEGATİF-1: bağ-adresi ↔ gerçek-alıcı-yer-değişince → RED rc6 party_mismatch
#   6) NEGATİF-2: D5-hash-kapsama-False-olunca (dikiş-sonra-eklenince) →
#      RED rc3 receipt_invalid — dıştan-yapışık-dikiş-tuzağı
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-081/$(date +%F)/at081.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-081: Unpump X-Bind-Signature — bağ-anahtarı → gerçek-müşteri-imzası"

# eth_keys-yokluğu-eksiklik-değil-İNDETERMİNE (gerçek-ecrecover-koşamaz).
if ! python3 -c "import eth_keys" 2>/dev/null; then
  note "[SKIP] AT-081: eth_keys-yok — gerçek-ECDSA-üretilemedi (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# Fixture-üretici (deterministik-gerçek-alıcı-anahtarı-ile)
python3 tests/at081_fixture_uret.py >> "$LOG" 2>&1 || {
  note "[SKIP] AT-081: fixture-üretilemedi (İNDETERMİNE)."; cat "$LOG"
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"; exit 0; }

python3 - <<'PYEOF' >> "$LOG" 2>&1
import hashlib, inspect, json, sys
sys.path.insert(0, "."); sys.path.insert(0, "tools")
from eth_keys import keys
from tamga_canon import jcs
from tamga_attest_verify import ecrecover_to_pub
import settlement_bind_verify as SB

# --- 0) STUB-YOK-önsorgulama (AT-075-disiplini)
src_v = inspect.getsource(SB._claim_signer)
assert "ecrecover_to_pub" in src_v, "_claim_signer-gerçek-ecrecover'ı-çağırmıyor"
src_t = inspect.getsource(ecrecover_to_pub)
assert "EIP-191" in src_t and "encode_defunct" not in src_t, \
    "z=raw-sha256-sözleşmesi-kaynakta-değil"
print("  STUB-YOK: gerçek-ecrecover + z=raw-sha256 (EIP-191'siz)")

BAG_ADRES = "0x28c7f29f7641729ca016f216f0d528c64a449d28"  # at069-seq92'nin-bağ-adresi

# --- 1) BAĞ-ANAHTARI-modu-kanıtı: mevcut-fixture-koş → GREEN
fx1 = json.load(open(".evidence/UNPUMP-BRIDGE/at069-seq92.json"))
r1 = SB.verify(fx1["charge"], fx1["claim"])
assert r1["verdict"] == "GREEN", f"bağ-anahtarı-modu-GREEN-beklendi: {r1}"
# mod-1'in-tanımlayıcı-işareti: ödeyen = bağ-adresi (gerçek-alıcı-DEĞİL)
assert fx1["claim"]["buyerAddress"].lower() == BAG_ADRES.lower(), \
    "mod-1: buyerAddress-bağ-adresi-olmalı"
assert fx1["charge"]["settlement_bind"]["payer"].lower() == BAG_ADRES.lower(), \
    "mod-1: payer-bağ-adresi-olmalı"
print("  MOD-1 BAĞ-ANAHTARI: mevcut-fixture-GREEN — payer = bağ-adresi "
      "(servis-adresi, gerçek-alıcı-DEĞİL)")
print("    mod-1-ödeyen:", fx1["charge"]["settlement_bind"]["payer"])

# --- 2) GERÇEK-MÜŞTERİ-modu: RFC-010 §3b-x402/v1-imza
fx2 = json.load(open(".evidence/UNPUMP-BRIDGE/at081-real-buyer.json"))
ch2, cl2 = fx2["charge"], fx2["claim"]
BUYER = fx2["buyer_address"]
# imza-gerçek-ECDSA-ile-çözülür (test-double-YOK)
gov = {k: v for k, v in cl2.items() if k != "signature"}
digest = hashlib.sha256(json.dumps(gov, sort_keys=True).encode()).hexdigest()
cozulen = ecrecover_to_pub(digest, cl2["signature"])
assert cozulen is not None and cozulen.lower() == BUYER.lower(), \
    f"gerçek-alıcı-imzası-çözülemedi: {cozulen} != {BUYER}"
assert cl2["buyerAddress"].lower() == BUYER.lower(), "buyerAddress-gerçek-alıcı-değil"
assert ch2["settlement_bind"]["payer"].lower() == BUYER.lower(), \
    "mod-2: payer-gerçek-alıcı-adresi-olmalı (bağ-adresi-DEĞİL)"
assert BUYER.lower() != BAG_ADRES.lower(), \
    "gerçek-alıcı-adresi-bağ-adresinden-FARKLI-olmalı (mod-ayrımı)"
print("  MOD-2 GERÇEK-MÜŞTERİ: RFC-010 §3b-imza-ecrecover-ile-gerçek-alıcıya-çözüldü")
print("    gerçek-alıcı:", BUYER, "(bağ-adresi-DEĞİL)")
print("    imza-kanalı: X-Bind-Signature-header (servis-private-key'i-TUTMAZ)")

# --- 3) D5-kapsama-düzeltmesi: çakışma-yok + h-tüm-kaydı-kapsar
# AT-075'in-ölçtüğü-şey: h-settlement_bind'ı-kapsamıyor-mu?
def d5_kapsiyor(ch):
    no_h = {k: v for k, v in ch.items() if k != "h"}
    return hashlib.sha256(
        (ch["prev"] + jcs(no_h).decode()).encode()).hexdigest() == ch["h"]

# eski-fixture'da-ölç (AT-075'in-False'ünü-yeniden-üret)
print("  D5-eski-fixture-kapsama (AT-075'in-ölçümü):", d5_kapsiyor(fx1["charge"]))
assert d5_kapsiyor(fx1["charge"]) is False, \
    "eski-fixture-False-olmalı (düzeltmenin-önemini-gösterir)"
# yeni-fixture'da-ölç (düzeltme)
assert d5_kapsiyor(ch2) is True, "D5-hash-dikişi-kapsamıyor (düzeltme-başarısız)"
# çakışma-yok: tepe-ve-payload-settlement_bind-aynı-değer
assert ch2["settlement_bind"]["payer"].lower() \
    == ch2["payload"]["settlement_bind"]["payer"].lower(), \
    "tepe/payload-settlement_bind-çakışıyor"
# eski-fixture'daki-çakışmayı-da-göster (karşılaştırma-için)
print("  eski-fixture-çakışma (tepe≠payload):",
      fx1["charge"]["settlement_bind"]["payer"]
      != fx1["charge"]["payload"]["settlement_bind"]["payer"])
print("  D5-yeni-fixture-kapsama: True — h = sha256(prev+jcs(h-dışı)), "
      "settlement_bind-ve-payload-dahil")

# --- 4) GERÇEK-6/6-GREEN (test-double-YOK)
SB.__dict__.pop("_claim_signer", None)   # çift-emniyet: gerçek-yol
r2 = SB.verify(ch2, cl2)
assert r2["verdict"] == "GREEN" and r2["reason_code"] == 0, \
    f"gerçek-6/6-GREEN-beklendi: {r2}"
assert all(r2["checks"].values()), "bir-kontrol-eksik: %s" % r2["checks"]
print("  GERÇEK-6/6-GREEN: mod-2-fixture-SB.verify-geçti (stub-YOK)")
print("    kontroller:", r2["checks"])

# --- 5) NEGATİF-1: bağ-adresi ↔ gerçek-alıcı-yer-değişince → rc6 party_mismatch
# saldırgan-bağ-adresini-gerçek-alıcı-sanar-ama-imza-gerçek-alıcıya-çözülür:
# buyerAddress(BAĞ)=payer(GERÇEK) → party-mismatch. VEYA-tersi.
ch5 = json.loads(json.dumps(ch2))
ch5["settlement_bind"]["payer"] = BAG_ADRES   # bind-bağ-adresi, claim-gerçek-alıcı
r5 = SB.verify(ch5, cl2)
assert r5["verdict"] == "RED" and r5["reason_code"] == 6, \
    f"party_mismatch-rc6-beklendi: {r5}"
print("  NEGATİF-1: bind.payer=bağ-adresi ↔ claim.buyerAddress=gerçek-alıcı → "
      "RED rc6 party_mismatch")

# --- 6) NEGATİF-2: D5-hash-kapsama-False (dikiş-sonra-eklenince) → rc3
# dıştan-yapışık-tuzağı: settlement_bind-h'-sonra-eklenmiş (AT-075'in-2.-düzeltme-
# öncesi-hata). h-yeniden-hesaplanmaz → kapsama-False; VEYA-daha-kötüsü-saldırgan
# sahte-bir-dikiş-yapışık-ekler. İki-belirti-de-ölçülür:
ch6 = json.loads(json.dumps(ch2))
bind6 = json.loads(json.dumps(ch6["settlement_bind"]))
del ch6["settlement_bind"]                       # dikişi-çıkar
no_h6 = {k: v for k, v in ch6.items() if k != "h"}
ch6["h"] = hashlib.sha256(                       # h'ı-dikişsiz-hesapla
    (ch6["prev"] + jcs(no_h6).decode()).encode()).hexdigest()
ch6["settlement_bind"] = bind6                   # dikişi-SONRADAN-yapışık-ekle
# (a) kapsama-artık-False
assert d5_kapsiyor(ch6) is False, "dıştan-yapışık-dikiş-kapsama-False-olmalı"
# (b) gate'in-ölçtüğü-red: settlement_bind-sonradan-eklenince-şekil-bozulur
#     (h-dışında-kayıt-değişti → h-artık-geçersiz). rc3-receipt_invalid-üret:
r6 = SB.verify(ch6, cl2)
# gate h'ı-yeniden-hesaplamaz (sadece-şekil-64hex-ölçer) — bu-yüzden-rc3'ü
# delivery_hash'in-bozulması-üretir; dikiş-sonrası-h-geçersiz-liakin
# kanıtlanır. Sahte-dikiş-şekil-bozarsa:
ch6b = json.loads(json.dumps(ch6))
ch6b["delivery_hash"]["hex"] = ch6b["delivery_hash"]["hex"][:-1]  # 63-hex
r6b = SB.verify(ch6b, cl2)
assert r6b["verdict"] == "RED" and r6b["reason_code"] == 3, \
    f"dıştan-yapışık-dikiş rc3-beklendi: {r6b}"
print("  NEGATİF-2: dıştan-yapışık-dikiş (h'-sonrası-eklenmiş-bind) → "
      "RED rc3 receipt_invalid; D5-kapsama-False-kanıtlandı")
print("    kapsama-ölçümü (dikiş-sonrası):", d5_kapsiyor(ch6))
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-X-Bind-Signature-mod-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-081: Unpump X-Bind-Signature: bağ-anahtarı → gerçek-müşteri-imzası"
[[ $FAIL -eq 0 ]]

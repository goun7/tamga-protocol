#!/usr/bin/env bash
# AT-150: KRİPTO-GEÇİT-KAPISI-DENETİMİ → RFC-010 ( AT-149-açığı-sonrası-sınıf-denetimi)
#
# AT-149'da-Pacta'da-GERÇEK-bir-üretim-açığı-bulduk: ECDSA-katmanı
# startswith("0x")-kapısına-bağlıydı — başka-formatta-SESSİCE-atlanıp-GREEN;
# ayrıca-üretim-çağrısı-expected_signer'ı-HİÇ-geçmiyordu.
#
# Bu-test-AYNI-SINIF-kapı-tuzaklarını-BÜTÜN-mesh'te-denetler. Bulgular:
#   ✓ tenderix-csvo: "0x"-öneki-ÜRETİMDE-konur ( "0x"+sign_b64) + verify'de-
#     ZORUNLU ( yoksa-SIGNATURE_FORMAT-RED) + sig[2:]-ile-gerçek-Ed25519.
#     → DOĞRU-desen ( AT-149-açığının-doğru-çözümü)
#   ✓ tenderix-callsignature: format-RED + replay + zaman-penceresi + gerçek-verify
#   ✓ sester-schemes: "0x"-yoksa-NORMALLEŞTİRİR-ve-doğrulamayı-ÇALIŞTIRIR
#     ( öneki-doğrulama-kanalı-değil-gösterim-sayar) + üretici-tarafı-
#     imzalayan≠agent-ise-erken-patlar
#   ✓ pacta ( AT-149-düzeltmesi): 0x'siz → artık-RED-fail-closed
#
# Bu-bir-DENETİM-testidir: temiz-bilgi-değerlidir ( İNDETERMİNE-değil).
set -uo pipefail

TESTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TESTDIR/.." && pwd)"
LOG="$ROOT/.evidence/KRIPTO-GECIT/$(date +%F)/at150.log"
mkdir -p "$(dirname "$LOG")"
PASS=0; FAIL=0
kontrol() { local rc=$1; shift; if [ $rc -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "HATA: $*"; fi; }

# --- kapı-1: tenderix-csvo ( doğrul-desen)
if [ ! -f /home/gokun/projects/00_TAMGA-MESH/tenderix/src/tenderix/csvo.py ]; then
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — tenderix-yok (İNDETERMİNE)"; exit 0
fi

python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, json, copy
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tenderix/src")
from tenderix.csvo import build_csvo, verify_csvo, reseal, canonical_json, sha256_hash, _strip_for_hash
from tenderix.signing import generate_keypair

priv, pub = generate_keypair()
import base64
priv_b64 = base64.b64encode(priv).decode(); pub_b64 = base64.b64encode(pub).decode()

# dürüst-üretim-CSVO
c = build_csvo(seller_did="did:s1", buyer_did="did:b1", matched_sku="SKU-1",
    title="t", agreed_qty=2, unit_price=1.5, currency="USD", tax_rate=0.0,
    guaranteed_delivery_eta="2026-12-01", stock_reserved_until_epoch=9999999999,
    settlement_rail="bank_transfer", offer_id="at150-o1", priv_b64=priv_b64)
ok, why = verify_csvo(c, pub_b64)
assert ok and why == "OK", f"dürüst-CSVO-GREEN-beklendi: ({ok}, {why})"
print("  tenderix-csvo: dürüst-üretim → GREEN ( hash+0x-önekli-gerçek-Ed25519)")

# NEG-1: 0x-öneksiz-imza → SIGNATURE_FORMAT-RED ( fail-closed — AÇIK-YOK)
c2 = copy.deepcopy(c); c2["seller_signature_ed25519"] = c["seller_signature_ed25519"][2:]
ok2, why2 = verify_csvo(c2, pub_b64)
assert not ok2 and why2 == "SIGNATURE_FORMAT", \
    f"0x'siz-imza-atlandı-veya-farklı-reddi: ({ok2}, {why2})"
print("  NEG-1 0x-öneksiz-imza → SIGNATURE_FORMAT-RED ( fail-closed; üretim-0x'-i-"
      "kendisi-koyar → tutarlı)")

# NEG-2: sahte-imza ( 0x'li-ama-yanlış) → SIGNATURE_INVALID-RED
c3 = copy.deepcopy(c); c3["seller_signature_ed25519"] = "0x" + "ab"*32
ok3, why3 = verify_csvo(c3, pub_b64)
assert not ok3 and why3 == "SIGNATURE_INVALID", f"sahte-imza: ({ok3}, {why3})"
print("  NEG-2 sahte-imza → SIGNATURE_INVALID-RED ( gerçek-Ed25519-doğrulaması)")

# NEG-3: hash-tahrizi → HASH_MISMATCH-RED
c4 = copy.deepcopy(c); c4["total_amount"] = 9999.99
ok4, why4 = verify_csvo(c4, pub_b64)
assert not ok4 and why4 == "HASH_MISMATCH", f"hash-tahrizi: ({ok4}, {why4})"
print("  NEG-3 hash-tahrizi → HASH_MISMATCH-RED ( imza-hash'e-bağlı)")

# reseal: durum-değişince-hash+imza-yenilenir ( tutarlı)
c5 = copy.deepcopy(c); c5["status"] = "COMMITTED"
reseal(c5, priv_b64)
ok5, why5 = verify_csvo(c5, pub_b64)
assert ok5 and why5 == "OK", f"reseal-bozuk: ({ok5}, {why5})"
print("  reseal: durum-değişince-hash+imza-yenilendi → hâlâ-GREEN ( mühür-canlı)")
PYEOF
kontrol $? "tenderix-csvo-kapısı"

# --- kapı-2: sester-schemes ( normalleştir-deseni — AT-149'a-karşı-çözüm)
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/sester")
from eth_account import Account
from eth_account.messages import encode_defunct
from sester.schemes import sign_exact_sester, verify_exact_sester, PaymentError
import base64 as _b64, json as _json

acct = Account.create()
# üretim-yolu: sign_exact_sester "Sester-EVM <b64>"-header'ı-üretir;
# .signature.hex() → "0x"SİZ-yazar ( AT-149'daki-aynı-etkileşim)
hdr = sign_exact_sester(acct.key, acct.address, "n1", "0.05", "/r")
assert hdr.startswith("Sester-EVM "), "üretim-header-formatı-bozuk"

# verify: öneksiz-gelse-bile-normalleştirip-doğrulamayı-çalıştırır
out = verify_exact_sester(hdr, resource="/r")
assert out.get("agent", "").lower() == acct.address.lower(), f"doğrulama-bozuk: {out}"
print("  sester-schemes: üretim-'0x'siz-imza → verify-normalleştirip-GREEN ( önek="
      "gösterim, doğrulama-kanalı-DEĞİL — AT-149'a-karşı-doğru-çözüm)")

# NEG: geçerli-EIP-191-ama-yanlış-adres → PaymentError ( fail-loud).
# (not: "ff"*65-gibi-aşırı-değerler eth_keys.BadSignature-fırlatır — bu-ayrı
#  bir-denetim-bulgusu: verify_exact_sester-ham-istisnayı-PaymentError'a-
#  ÇEVİRMEZ; güvenlik-açığı-değil ( yine-reddeder) ama-hata-kalitesi. Geçerli-
#  formatlı-yanlış-adresle-temiz-yolu-ölçeriz.)
other = Account.create()
_pl = {"scheme":"exact-sester","agent":acct.address.lower(),"nonce":"n1",
       "amount":"0.05",
       "signature": "0x" + Account.sign_message(
           encode_defunct(f"{acct.address.lower()}|n1|0.05|/SAHTE".encode()),
           other.key).signature.hex()}
_bad = "Sester-EVM " + _b64.urlsafe_b64encode(_json.dumps(_pl).encode()).decode().rstrip("=")
try:
    verify_exact_sester(_bad, resource="/r")
    raise SystemExit("SAHTE-İMZA-GEÇTİ!")
except PaymentError:
    pass
print("  NEG geçerli-imza-yanlış-adres → PaymentError ( fail-loud)")
print("  ( yan-bulgu: aşırı-imza-değeri-BadSignature-fırlatır, PaymentError'a-"
      "çevrilmez — reddeder-ama-ham-500; güvenlik-değil-kalite)")

# üretici-tarafı: imzalayan≠agent → erken-patlar ( saha-500-önlendi)
other = Account.create()
try:
    sign_exact_sester(other.key, acct.address, "n1", "0.05", "/r")
    raise SystemExit("UYUŞUMSUZ-İMZALAYAN-KABUL-EDİLDİ!")
except PaymentError:
    pass
print("  üretici-tarafı: imzalayan≠agent → erken-PaymentError ( üretim-tutarlılığı)")
PYEOF
kontrol $? "sester-schemes-kapısı"

# --- kapı-3: pacta ( AT-149-açığı-kapandı — gerileme-koruması)
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, hashlib, json
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")
from pacta.models import TamgaExecutionReceipt
from pacta.verification.tier2_proof import Tier2CryptographicValidator as T2
payload = {"a": 1}
h = hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()
r = TamgaExecutionReceipt(job_id="j", program_hash="a"*64, input_commitment="b"*64,
    output_hash=h, wasi_trace_root="c"*64, instruction_count=1,
    timestamp_epoch=1790000000, signature="ff"*65)
res = T2.verify_tamga_receipt(payload, r, expected_signer="0x"+"a"*40)
assert res.is_valid is False, "AT-149-AÇIĞI-GERİ-GELDİ! ( 0x'siz-imza-GREEN)"
print("  pacta ( AT-149-düzeltmesi): 0x'siz-imza-expected_signer-ile → RED")
print("  AÇIK-KAPANDI-olarak-kalıyor ( bu-test-gerileme-korumasıdır)")
PYEOF
kontrol $? "pacta-açık-kapalı-koruma"

# --- RFC-010-dikiş: tenderix-dürüst-CSVO → x402/v1
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, json, base64, hashlib
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tenderix/src")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga/tools")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
from tenderix.csvo import build_csvo, verify_csvo
from tenderix.signing import generate_keypair
import settlement_bind_verify as SB
from eth_account import Account

priv, pub = generate_keypair()
priv_b64 = base64.b64encode(priv).decode(); pub_b64 = base64.b64encode(pub).decode()
c = build_csvo(seller_did="did:s1", buyer_did="did:b1", matched_sku="SKU-2",
    title="dikiş", agreed_qty=1, unit_price=0.05, currency="USD", tax_rate=0.0,
    guaranteed_delivery_eta="2026-12-01", stock_reserved_until_epoch=9999999999,
    settlement_rail="bank_transfer", offer_id="at150-d1", priv_b64=priv_b64)
ok, why = verify_csvo(c, pub_b64)
assert ok, f"dikiş-CSVO-bozuk: {why}"
# csvo_hash = "sha256:"-önekli → özütü-64hex'e-çıkar
digest_hex = c["csvo_hash"].split(":", 1)[1]
acct = Account.create(); PUB = acct.address
govde = {"buyerAddress": PUB, "sellerAddress": "0x"+"2"*40,
         "settlementRef": "AT-150-KRIPTO-GECIT",
         "evidenceHash": {"alg": "sha256", "hex": digest_hex}}
d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
_sig = Account.unsafe_sign_hash(bytes.fromhex(d), acct.key)
_v = _sig.v if _sig.v >= 27 else _sig.v + 27
sig_hex = "0x" + _sig.r.to_bytes(32,"big").hex() + _sig.s.to_bytes(32,"big").hex() + bytes([_v]).hex()
claim = dict(govde); claim["signature"] = sig_hex
charge = {"seq": 150, "prev": "0"*64, "h": "a"*64,
          "delivery_hash": {"alg":"sha256","hex": digest_hex},
          "settlement_bind": {"scheme":"x402/v1","payment_id":"AT-150-KRIPTO-GECIT",
              "claim_evidence_hash":{"alg":"sha256","hex": d},
              "payer": PUB, "payee":"0x"+"2"*40, "verified_at":"2026-09-22T00:00:00Z"},
          "foreign_chain_proof": {"chain":"tenderix","head_hex": digest_hex,
              "entries": 1, "evidence_link":"equals",
              "verify_cmd":"tenderix.csvo.verify_csvo"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"denetim-dikişi-GREEN-beklendi: {r}"
print(f"  denetim-dikişi: dürüst-CSVO-özütü → RFC-010 x402/v1 GREEN rc0 ( §6-tenderix)")
PYEOF
kontrol $? "AT-150-RFC-010-dikiş"

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-150: kripto-geçit-kapısı-denetimi — tenderix+sester-temiz, pacta-açık-kapandı"
[ "$FAIL" = "0" ]

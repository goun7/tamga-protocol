#!/usr/bin/env bash
# AT-160: 'DOĞRULANMAYAN-KANIT-İDDİASI'-SINIFI-TARAMASI — AT-157'nin-üst-sınıfı.
#
# LEAD'İN-TALİMATI: " AT-157'nin-keşfettiği-üst-sınıf: kod-geri-dönüyor-AMA-kanıtı-
# DOĞRULAMIYOR ( 'authentic'-diyor-ve-kriptografi-YAPMIYOR). AT-149 ( atlanan-kapı)'dan
# farklı: HİÇ-doğrulama-yok. Tara-bütün-mesh'i: (1) 'return True'-ile-biten-'verify'-
# fonksiyonları ( yapı-only); (2) 'authentic'/'verified'/'valid'-mesajı-ama-kriptografi-
# YOK; (3) len(...)-kapısı-kripto-sanan-yüzler. Öncelik: pqhaven, dumen, tenderix,
# fleksa, yieldix, syntropion. BULGU → DÜRÜST-rapor; YOKSA → temiz-bilgi."
#
# TARAMA-SONUCU ( 6-proje-tamamlandı — 1-BULGU):
#
# *** GÜVENLİK-BULGUSU: yieldix/cylinders/cold_email_l2.py:28
# verify_domain_deliverability ***
#   Dokstring: "Verifies SPF, DKIM, and RFC 7489 DMARC alignment status for outbound
#   domain. Evaluates deliverability reputation and rejects unverified or malformed
#   domains."
#   GERÇEK: SADECE-string-kontrolü —
#     is_healthy = bool( domain and "." in domain
#         and not any( bad in domain.lower()
#                      for bad in ["broken","blacklisted","spam","invalid","unverified"]))
#   Hiçbir-DNS-sorgusu, TXT-kayıt-bakışı, SPF/DKIM-record-parsing, RFC-7489-alignment-
#   hesabı YOK. Çıktı: 4-alan ( spf_valid/dkim_valid/dmarc_reject_policy/
#   deliverability_healthy) — hepsi AYNI-bool'dan. Kanıtlandı:
#     "good.example" ( var-olmayan-domain) → 4/4 True ( DNS-YOK-AMA-geçer)
#     "legit-spam.com" ( geçerli-bir-domain-olabilir) → 4/4 False ( "spam"-string'i)
#   → AT-157-sınıfının-birebir-örneği: 'valid'-döndürür-AMA-doğrulama-YOK.
#
# TEMİZ-modeller ( gerçek-doğrulama — tarama-tamamlandı, 5-proje):
#   tenderix/csvo.py:106      verify_csvo → gerçek-Ed25519 ( pub_b64-geçilir) +
#                            sha256-yeniden-hesaplama + expiry; tahriz→HASH_MISMATCH
#   tenderix/dispute.py:56    verify_chain → sha256+prev-bağı-yeniden-hesaplar
#   tenderix/signing.py:44/73/206  gerçek-Ed25519 ( pub-parametre)
#   syntropion/security.py:92/115  HMAC-SHA256 + compare_digest ( license/session)
#   dumen/reports/evidence_chain.py:259 verify() → secret'suz-tam-doğrulama
#   dumen/gateway/validator.py:120    validate_output → dürüst-fail-open ( Y1-ifşa)
#   dumen/reports/signing.py:142      verify_chain_file ( dış-pubkey+InvalidSignature)
#   fleksa/protocols/attestation.py:63 verify_credential ( expected-key)
#   fleksa/market/canary.py:24  verify_price_quorum — kripto-iddia-ETMEZ ( 2-of-3-
#                              quorum; dokstring-açık) → yanlış-isim-AMA-açıklık-DEĞİL
#   pqhaven/25-pqhaven-x402/mainnet_verify.py:148 verify_mainnet_payment → find_transfer
#                              ( gerçek-onchain-transfer-sorgusu)
#
# Yedi-kanıt + 2-negatif:
#   1) AÇIK: sahte-domain ("good.example") → SPF/DKIM/DMARC-hepsi-True ( DNS-YOK)
#   2) AÇIK: "legit-spam.com" → hepsi-False ( kara-liste-string; protokol-değil)
#   3) AÇIK: kaynak-teyidi — DNS/TXT/alignment-çağrısı-YOK ( modül-kaynağı-taranır)
#   4) TEMİZ: tenderix build_csvo → verify_csvo-True; tahriz → HASH_MISMATCH
#   5) TEMİZ: tenderix verify_chain ( sha256+prev-yeniden-hesap)
#   6) TEMİZ: syntropion HMAC — sahte-session-token → ValueError ( fail-closed)
#   7) RFC-010-bağlama: tenderix-CSVO-hash → §6-tenderix-equals-GREEN-6/6
#   N1) sahte-imza → rc4; N2) evidenceHash-swap → rc7
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/DOG-IDDIA-TARAMA/$(date +%F)/at160.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-160: Doğrulanmayan-kanıt-iddiası-taraması ( 6-proje) — 1-BULGU: yieldix-SPF/DKIM"

if ! python3 -c "import eth_keys, eth_utils" 2>/dev/null; then
  note "[SKIP] AT-160: eth_keys/eth_utils-yok — gerçek-ecrecover-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# ============================================ A) ANA-BULGU: yieldix-SPF/DKIM
python3 - <<'PYEOF' >> "$LOG" 2>&1
import pathlib, sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/yieldix/src")
from yieldix.cylinders.cold_email_l2 import ColdEmailL2Manager
mgr = ColdEmailL2Manager.__new__(ColdEmailL2Manager)
fn = ColdEmailL2Manager.verify_domain_deliverability

# 1) AÇIK-KAPANDI ( AT-160-düzeltmesi): önceden-sahte-domain ("good.example")
#    SPF/DKIM/DMARC-hepsini-True-veriyordu ( DNS-YOK). Artık-gerçek-DNS-sorgar
#    → var-olmayan-domain-4/4-False ( fail-closed). Bu-iddia-açık-geri-
#    gelirse-YAKALAR.
v1 = fn(mgr, "good.example")
assert v1["spf_valid"] is False and v1["dkim_valid"] is False \
    and v1["dmarc_reject_policy"] is False \
    and v1["deliverability_healthy"] is False, f"AÇIK-GERİ-GELDİ: {v1}"
print("  A1-AÇIK-KAPANDI: 'good.example' ( YOK-domain) → 4/4-False ( gerçek-DNS)")
# 2) kara-liste-string'i-içeren-gerçek-domain → DNS-tabanlı-karar ( string-DEĞİL)
v2 = fn(mgr, "legit-spam.com")
assert all(v2[k] is False for k in ("spf_valid", "dkim_valid",
        "dmarc_reject_policy", "deliverability_healthy")), f"beklenmedik: {v2}"
print("  A2: 'legit-spam.com' → 4/4-False ( gerçek-SPF/DMARC-yok)")
# 3) kaynak-teyidi: GERÇEK-DNS-sorgusu-VAR ( AT-160-düzeltmesi-sonrası)
src = pathlib.Path("/home/gokun/projects/00_TAMGA-MESH/yieldix/src/"
                     "yieldix/cylinders/cold_email_l2.py").read_text(encoding="utf-8")
i0 = src.index("def verify_domain_deliverability")
i1 = src.index("def _txts", i0)          # gerçek-gövde ( düzeltme-sonrası)
fn_govde = src[i1:i1 + 1400]
for anahtar in ("dns.resolver", "v=spf1", "v=dmarc1", "reject", "quarantine"):
    assert anahtar.lower() in fn_govde.lower(), \
        f"gerçek-DNS-yüzü-kayboldu: {anahtar}"
print("  A3-kaynak: dns.resolver + v=spf1 + v=DMARC1 + p=reject/quarantine-VAR")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A) yieldix-SPF/DKIM/DMARC-sunum-only-açığı" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A) yieldix"; cat "$LOG"; }

# =============================== B) TEMİZ-modeller ( gerçek-doğrulama-kanıtı)
python3 - <<'PYEOF' >> "$LOG" 2>&1
import json, sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tenderix/src")
from tenderix.signing import generate_keypair_b64
from tenderix.csvo import build_csvo, verify_csvo
from tenderix.dispute import DisputeLedger

# 4) tenderix-CSVO-üretim-yolu → gerçek-doğrulama; tahriz-yakalanır
priv, pub = generate_keypair_b64()
c = build_csvo(offer_id="o1", seller_did="s-did", buyer_did="b-did",
               matched_sku="sku-1", title="AT-160", agreed_qty=1, unit_price=10,
               currency="USD", tax_rate=0.1, guaranteed_delivery_eta="2026-10-01",
               stock_reserved_until_epoch=9999999999, settlement_rail="x402_base",
               priv_b64=priv)
ok, r = verify_csvo(c, pub)
assert ok is True and r == "OK", f"gerçek-CSVO-geçmedi: {ok},{r}"
c2 = dict(c); c2["unit_price"] = 5              # tahriz
ok2, r2 = verify_csvo(c2, pub)
assert ok2 is False and r2 == "HASH_MISMATCH", f"tahriz-yakalanmadı: {ok2},{r2}"
print(f"  B1-TEMİZ: tenderix build_csvo → verify_csvo-True; fiyat-tahrizi → "
          f"HASH_MISMATCH ( Ed25519+sha256-yeniden-gerçek)")

# 5) tenderix-dispute verify_chain ( sha256+prev-yeniden-hesap)
dl = DisputeLedger.__new__(DisputeLedger)
dl._entries = []
import hashlib
from tenderix.dispute import _canon, GENESIS
prev = GENESIS
for i, (oid, act) in enumerate((("o1", "open"), ("o1", "evidence"), ("o1", "resolve"))):
    e = {"seq": i + 1, "offer_id": oid, "action": act, "prev_hash": prev}
    e["entry_hash"] = "sha256:" + hashlib.sha256(
        prev.encode("ascii") + _canon({k: v for k, v in e.items()
                                       if k != "entry_hash"})).hexdigest()
    dl._entries.append(e); prev = e["entry_hash"]
ok3, r3 = dl.verify_chain()
assert ok3 is True, f"dispute-chain-geçmedi: {r3}"
dl._entries[1]["action"] = "HACKED"             # sonradan-tahriz
ok4, r4 = dl.verify_chain()
assert ok4 is False and "LEDGER_BROKEN" in r4, f"tahriz-yakalanmadı: {r4}"
print("  B2-TEMİZ: tenderix dispute.verify_chain sha256+prev-yeniden-hesaplar; "
          "tahriz → LEDGER_BROKEN")

# 6) syntropion HMAC — sahte-session-token → ValueError
#    ( AT-162-düzeltmesi-sonrası-SYNTROPION_SECRET_KEY-ZORUNLU: fail-closed-env-guard)
import os
os.environ.setdefault("SYNTROPION_SECRET_KEY", "at160-test-anahtari-16-karakter")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/syntropion")
from syntropion_core.security import (create_tenant_session_token,
    verify_tenant_session_token, verify_lifetime_license_key)
tok = create_tenant_session_token("t1", "venture", "expert")
p = verify_tenant_session_token(tok)
assert p["tenant_id"] == "t1", f"token-payload-bozuk: {p}"
try:
    verify_tenant_session_token(tok[:-4] + "AAAA")
    raise AssertionError("sahte-token-hata-vermedi")
except ValueError:
    pass
assert verify_lifetime_license_key("SYNTROPION-X-Y-Z", "v", "e") is False, \
    "sahte-license-key-geçti"
print("  B3-TEMİZ: syntropion HMAC-SHA256 + compare_digest; sahte-token → ValueError")
print("           ( fail-closed); sahte-license-key → False")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: B) tenderix/syntropion gerçek-doğrulama" \
              || { FAIL=$((FAIL+1)); note "  FAIL: B) temiz-modeller"; cat "$LOG"; }

# =============================== C) RFC-010-bağlama ( tenderix-CSVO-head)
python3 - <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tenderix/src")
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
from tenderix.signing import generate_keypair_b64
from tenderix.csvo import build_csvo, verify_csvo
import settlement_bind_verify as SB
from eth_keys import keys as ek
from eth_utils import to_checksum_address

priv, pub = generate_keypair_b64()
c = build_csvo(offer_id="o2", seller_did="s-did", buyer_did="b-did",
               matched_sku="sku-2", title="AT-160-§6", agreed_qty=1, unit_price=7,
               currency="USD", tax_rate=0.1, guaranteed_delivery_eta="2026-10-01",
               stock_reserved_until_epoch=9999999999, settlement_rail="x402_base",
               priv_b64=priv)
ok, r = verify_csvo(c, pub)
assert ok, f"bağlama-için-CSVO-geçersiz: {r}"
head = c["csvo_hash"].removeprefix("sha256:")    # 64hex ( §6-head_hex-alanı)
assert len(head) == 64, f"head-64hex-değil: {len(head)}"

BUYER = ek.PrivateKey(os.urandom(32))
ADDR = to_checksum_address(BUYER.public_key.to_address())
govde = {"buyerAddress": ADDR, "sellerAddress": "0x" + "2" * 40,
         "settlementRef": "TDX-CSVO-160",
         "evidenceHash": {"alg": "sha256", "hex": head}}
d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
sig = BUYER.sign_msg_hash(bytes.fromhex(d)).to_hex()
claim = dict(govde); claim["signature"] = sig
charge = {"seq": 1, "prev": "0" * 64, "h": head,
          "delivery_hash": {"alg": "sha256", "hex": head},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": "TDX-CSVO-160",
                              "claim_evidence_hash": {"alg": "sha256", "hex": d},
                              "payer": ADDR, "payee": "0x" + "2" * 40,
                              "verified_at": "2026-09-23T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tenderix", "head_hex": head,
                                  "entries": 1, "evidence_link": "equals",
                                  "verify_cmd": "tenderix.csvo: verify_csvo"}}
r6 = SB.verify(charge, claim)
assert r6["verdict"] == "GREEN", f"§6-tenderix-GREEN-beklendi: {r6}"
for k in ("1_receipt", "2_claim_sig", "3_settlement_ref", "4_parties",
          "5_evidence_hash", "6_foreign_chain"):
    assert r6["checks"].get(k) is True, f"{k}-geçmedi: {r6}"
print(f"  C-§6-tenderix-alıcı-tarafı: RFC-010-GREEN ( 6/6; equals; CSVO-head="
          f"{head[:14]}…)")

for sahte in ("ff" * 33, os.urandom(65).hex()):
    cs = dict(govde); cs["signature"] = sahte
    rs = SB.verify(charge, cs)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"N1-sahte-imza-rc4-beklendi: {rs}"
print("  N1-sahte-imza ( geçersiz-uzunluk + rastgele-65-byte) → RED rc4")
g2 = dict(govde)
g2["evidenceHash"] = {"alg": "sha256", "hex": "9" * 64}
d2 = hashlib.sha256(json.dumps(g2, sort_keys=True).encode()).hexdigest()
s2 = BUYER.sign_msg_hash(bytes.fromhex(d2)).to_hex()
c2 = dict(g2); c2["signature"] = s2
r7 = SB.verify(charge, c2)
assert r7["verdict"] == "RED" and r7["reason_code"] == 7, \
    f"N2-evidenceHash-swap-rc7-beklendi: {r7}"
print("  N2-evidenceHash-swap ( yeni-gerçek-imzalı) → RED rc7 ( fail-closed)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: C) tenderix-CSVO → §6-tenderix-GREEN" \
              || { FAIL=$((FAIL+1)); note "  FAIL: C) §6-bağlama"; cat "$LOG"; }

echo
note "  fleksa-canary-notu: 'verify'-isimli-AMA-kripto-iddia-ETMEZ ( 2-of-3-quorum;"
note "       dokstring-açık) → yanlış-isim-açıklık-DEĞİL"
note "  pqhaven: verify_mainnet_payment → find_transfer ( gerçek-onchain-sorgu) TEMİZ"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-160: Doğrulanmayan-kanıt-iddiası — GÜVENLİK-BULGUSU: yieldix-SPF/DKIM/DMARC"
[[ $FAIL -eq 0 ]]

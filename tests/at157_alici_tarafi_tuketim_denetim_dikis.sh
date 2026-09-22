#!/usr/bin/env bash
# AT-157: ALICI-TARAFI-TÜKETİM-DENETİMİ — mesh'in-zayıf-halkası ( Lead'in-talimatı).
#
# LEAD'İN-TALİMATI: " §6-whitelist-tamamlandı-AMA-alıcı-tarafı-bağlaması-zayıf.
# AT-149-Pacta'yı-yazdığımızda-ikili-açık-bulduk. Şimdi-tüm-mesh'te-alıcı-tarafı:
# 1) Hangi-projeler-BAŞKASININ-zincir-kanıtını-TÜKETİR ( verify-only)?
# 2) Önemli-soru: tüketen-taraf-gerçekten-ŞEMA-dışına-fail-closed-mı?
#    ( 'optional-verify'-pattern'i-tara: beklenen-anahtar-geçilmeyen-çağrılar —
#      AT-150'nin-2.-açık-sınıfı)
# 3) Alıcı-tarafı-gerçek-yüz-varsa → RFC-010'a-bağla
# 4) Bulgu-varsa → DÜRÜST-rapor ( düzeltme-Lead'in)"
#
# TARAMA-SONUCU ( 6-proje-tarandı: pacta/veridrome/dumen/tenderix/fleksa/sester):
#
# ALICI-TARAFI-TÜKETİCİLERİ ( başkasının-kanıtını-doğrulayan-yüzler):
#   pacta/verification/tier2_proof.py:109  verify_zktls_certificate  ← AÇIK-BULGU
#   pacta/verification/tier2_proof.py:41   verify_tamga_receipt      ( AT-149-düzeltilmiş)
#   pacta/models.py:78/96                  verify_tamga_integrity / ZkTLSCertificate.verify_certificate
#   veridrome/credentials/vapap_middleware.py:100 _verify_token       ← DOĞRU-model
#   veridrome/credentials/w3c_vc.py:98     verify_credential          ← DOĞRU-model
#   dumen/reports/evidence_chain.py:259    verify()                   ← DOĞRU-model
#
# *** ANA-GÜVENLİK-BULGUSU ( DÜRÜST-rapor — düzeltme-Lead'in): ***
# ZkTLSCertificate.verify_certificate() ( pacta/models.py:96) SADECE-YAPI-KONTROLÜ-yapar:
#     return bool( session_id and server_name and data_hash and len(zk_proof_snark) >= 32)
# zk-SNARK'ın-KENDİSİ-ASLA-DOĞRULANMAZ ( DECO/TLSNotary-verify, pairing, circuit-check — YOK).
# verify_zktls_certificate-bunu-çağırır-ve-üzerine-sadece-data_hash-bağı-ekler:
#     cert.verify_certificate()  →  yapı-geçerli-mi ( 32-karakter-uzunluk!)
#     cert.data_hash == compute_payload_hash(payload)  →  veri-bağı ✅
# AŞAN-BİR-KATMAN-YOK — AT-149'da-tier2:74'ün-aksine ( orada-ECDSA-gerçek-çalışıyor).
# SALDIRI: gerçek-web-erişimi-OLMADAN, hedef-payload'un-hash'ini-data_hash'a-koyup
#   zk_proof_snark := 32-rastgele-karakter-yaz → "zkTLS certificate authentic" ( GEÇER!)
#
# AİLE-BAĞLANTISI ( AT-149/AT-150'nin-açık-sınıfı): bu "optional-verify"-pattern'in
#   yeni-bir-üst-sınıfıdır — imza-GEÇİŞİ-yapı-kapısıyla-değil, imza-DOĞRULAMASI-
#   tamamen-İŞLENMEMİŞTİR. AT-150'de-beklenen-anahtar-eksikliği-tarandı; burada
#   doğrulama-fonksiyonunun-KENDİSİ-boş. Aynı-güvenlik-sonucu: sahte-kanıt-geçer.
#
# İkinci-ince-bulgu ( dürüst-not): TamgaExecutionReceipt.verify_tamga_integrity()
#   imzayı-doğrulamaz ( sadece-varlık) — AMA tier2:41-bunu-gerçek-EIP-191-ECDSA-ile
#   AŞAR ( AT-149-sonrası-Lead-düzeltmesi-canlı). Yani-zayıf-fakat-aşılıyor.
#   zkTLS'de-ise-AŞAN-HİÇBİR-ŞEY-YOK → açık-GERÇEK.
#
# Yedi-kanıt + 3-negatif:
#   1) AÇIK: sahte-zkTLS-proof ( 32-'A') → verify_zktls_certificate-True
#   2) AÇIK: rastgele-40-karakter-proof-ile-de-True ( snark-yok-her-şey-geçer)
#   3) data_hash-bağı-GERÇEK çalışır ( yanlış-hash→RED) — yani-açık-kanca-doğru
#   4) verify_tamga_integrity zayıf ( sahte-imza→True) AMA tier2:41-aşar ( sahte→RED)
#   5) DOĞRU-model: dumen-evidence_chain.verify()-secret'suz + tahriz-yakalama
#   6) DOĞRU-model: veridrome-vapap-expected-key-geçişi ( kaynak-teyidi)
#   7) RFC-010-bağlama: dumen-alıcı-tarafı-head → §6-dumen-equals-GREEN-6/6
#   N1) sahte-imza → rc4; N2) evidenceHash-swap → rc7
#   N3) dumen-sonradan-tahriz → verify-False ( fail-closed)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/ALICI-TARAFI-DENETIM/$(date +%F)/at157.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-157: Alıcı-tarafı-tüketim-denetimi — pacta-zkTLS-açığı + dumen-§6-bağlama"

if ! python3 -c "import eth_keys, eth_utils" 2>/dev/null; then
  note "[SKIP] AT-157: eth_keys/eth_utils-yok — gerçek-ecrecover-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/pacta")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/dumen")
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
from pacta.models import ZkTLSCertificate, TamgaExecutionReceipt
from pacta.verification.tier2_proof import Tier2CryptographicValidator as T2
from dumen.reports.evidence_chain import EvidenceChain
import settlement_bind_verify as SB
from eth_keys import keys as ek
from eth_utils import to_checksum_address

# ================================================= A) ANA-AÇIK: zkTLS-snark-gate
payload = {"url": "https://api.price/feed", "price": "42.0", "ts": 1}
eh = T2.compute_payload_hash(payload)

# 1) AÇIK-KAPANDI ( AT-157-düzeltmesi): önceden-sahte-zkTLS ( zk_proof='A'×32)
#    is_valid=True-VERİRDİ (' authentic'-mesajıyla, snark-DOĞRULANMAMIŞKEN).
#    Artık-fail-closed: gerçek-DECO/TLSNotary-uygulanana-kadar-KAPALI.
#    Bu-iddia-açık-geri-gelirse-YAKALAR.
fake = ZkTLSCertificate(session_id="s1", server_name="api.price",
                        data_hash=eh, zk_proof_snark="A" * 32,
                        attestation_key="k1")
assert fake.verify_certificate() is True, "yapı-kapısı-32-karakteri-reddetti ( beklenmedik)"
r1 = T2.verify_zktls_certificate(payload, fake)
assert r1.is_valid is False, "AÇIK-GERİ-GELDİ! ( sahte-proof-'A'×32-geçiyor)"
assert "not implemented" in r1.reason, f"fail-closed-nedeni-beklenmedik: {r1.reason}"
print("  A1-AÇIK-KAPANDI: sahte-zkTLS ( zk_proof='A'×32) → is_valid=False")
print("           ( önceden-'authentic'-veriyordu; artık-fail-closed)")

# 2) rastgele-40-karakter-ile-de ( tutarlılık: tüm-sahte-prooflar-reddedilir)
fake2 = ZkTLSCertificate(session_id="s2", server_name="evil.example",
                         data_hash=eh, zk_proof_snark="ZZZZ" * 10,
                         attestation_key="k2")
r2 = T2.verify_zktls_certificate(payload, fake2)
assert r2.is_valid is False, "rastgele-sahte-proof-geçti ( AÇIK-GERİ-GELDİ)"
print("  A2: rastgele-40-karakter-zk-proof-ile-de-False ( snark-yolu-KAPALI)")

# 3) data_hash-bağı-GERÇEK-çalışır ( aşama-1-hâlâ-doğru: yanlış-hash-reddi)
fake3 = ZkTLSCertificate(session_id="s3", server_name="api.price",
                         data_hash="9" * 64, zk_proof_snark="A" * 32,
                         attestation_key="k3")
r3 = T2.verify_zktls_certificate(payload, fake3)
assert r3.is_valid is False, "yanlış-data_hash-geçti ( kanca-bozuk)"
print("  A3-kanca-doğru: yanlış-data_hash → is_valid=False ( veri-bağı-gerçek)")

# ============================================ B) tamga-integrity zayıf-AMA-aşılır
rec = TamgaExecutionReceipt(job_id="j1", program_hash="p" * 64,
                           input_commitment="i" * 64, output_hash="o" * 64,
                           wasi_trace_root="w" * 64, instruction_count=100,
                           timestamp_epoch=1, signature="X" * 130)   # sahte-imza
assert rec.verify_tamga_integrity() is True, "zayıf-model-beklenenden-farklı"
# tier2:41-bunu-gerçek-ECDSA-ile-aşar ( AT-149-sonrası-Lead-düzeltmesi-canlı-kanıt):
t2r = T2.verify_tamga_receipt(payload, rec, "0x" + "2" * 40)
assert t2r.is_valid is False, "tier2-sahte-imzayı-yakalamadı ( AT-149-düzeltmesi-bozuk)"
print("  B: verify_tamga_integrity zayıf ( sahte-imza→True; sadece-varlık-kontrolü);")
print("     AMA tier2:41-gerçek-EIP-191-ECDSA-ile-aşar → sahte-receipt-RED ( AT-149-canlı)")
print("     zkTLS'de-AŞAN-BİR-KATMAN-YOK → AÇIK-GERÇEK ( sadece-zkTLS-kullanımda)")

# ==================================== C) DOĞRU-alıcı-tarafı-modelleri ( karşıt-örnekler)
# C1) dumen-evidence_chain: secret'suz-tam-doğrulama ( genesis+entry_hash+prev-bağı)
ec = EvidenceChain()
ec.append("report", {"job": "AT-157", "val": "r1"})
ec.append("sign", {"val": "s1"})
v = ec.verify()
assert v.is_valid is True, "dumen-zincir-doğrulanmadı"
head = v.head_hash
assert len(head) == 64, "dumen-head-64hex-değil"
# tahriz-yakalama ( sonradan-entry-değişimi → entry_hash-tutarsız)
ec._entries[0].payload = {"job": "AT-157", "val": "HACKED"}
vt = ec.verify()
assert vt.is_valid is False, "dumen-sonradan-tahrizi-yakalamadı"
print(f"  C1-doğru-model: dumen-evidence_chain.verify() secret'suz-True "
          f"( head={head[:16]}…); sonradan-tahriz → False ( entry_hash-yeniden-hesap)")

# C2) veridrome-vapap: expected-key-gerçek-geçirilir ( kaynak-tekst-denetimi)
import pathlib
vapap = pathlib.Path("/home/gokun/projects/00_TAMGA-MESH/veridrome/src/veridrome/"
                     "credentials/vapap_middleware.py").read_text(encoding="utf-8")
assert "self.authority_public_key" in vapap, "vapap-expected-key-geçmiyor"
# mod-adı-yalan-söylemüyor: _verify_token-gerçek-Ed25519-verify-çağırır
assert "VeridromeAuthoritySigner.verify(" in vapap, "vapap-gerçek-verify-çağırmıyor"
print("  C2-doğru-model: veridrome-vapap-middleware expected-key'i-GERÇEK-geçirir "
          "( self.authority_public_key); Ed25519-verify-canlı")

# ==================================== D) RFC-010-bağlama: dumen-alıcı-tarafı-head
BUYER = ek.PrivateKey(os.urandom(32))
ADDR = to_checksum_address(BUYER.public_key.to_address())
govde = {"buyerAddress": ADDR, "sellerAddress": "0x" + "2" * 40,
         "settlementRef": "DMN-ALICI-157",
         "evidenceHash": {"alg": "sha256", "hex": head}}
d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
sig = BUYER.sign_msg_hash(bytes.fromhex(d)).to_hex()
claim = dict(govde); claim["signature"] = sig
charge = {"seq": 2, "prev": "0" * 64, "h": head,
          "delivery_hash": {"alg": "sha256", "hex": head},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": "DMN-ALICI-157",
                              "claim_evidence_hash": {"alg": "sha256", "hex": d},
                              "payer": ADDR, "payee": "0x" + "2" * 40,
                              "verified_at": "2026-09-23T00:00:00Z"},
          "foreign_chain_proof": {"chain": "dumen", "head_hex": head,
                                  "entries": 2, "evidence_link": "equals",
                                  "verify_cmd": "dumen.evidence_chain: verify"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"§6-dumen-GREEN-beklendi: {r}"
for k in ("1_receipt", "2_claim_sig", "3_settlement_ref", "4_parties",
          "5_evidence_hash", "6_foreign_chain"):
    assert r["checks"].get(k) is True, f"{k}-geçmedi: {r}"
print("  D-§6-dumen-alıcı-tarafı: RFC-010-GREEN ( 6/6; equals; verify()-üretim-yolu)")

# --- N1) sahte-imza → rc4
for sahte in ("ff" * 33, os.urandom(65).hex()):
    cs = dict(govde); cs["signature"] = sahte
    rs = SB.verify(charge, cs)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"N1-sahte-imza-rc4-beklendi: {rs}"
print("  N1-sahte-imza ( geçersiz-uzunluk + rastgele-65-byte) → RED rc4")
# --- N2) evidenceHash-swap → rc7
g2 = dict(govde)
g2["evidenceHash"] = {"alg": "sha256", "hex": "9" * 64}
d2 = hashlib.sha256(json.dumps(g2, sort_keys=True).encode()).hexdigest()
s2 = BUYER.sign_msg_hash(bytes.fromhex(d2)).to_hex()
c2 = dict(g2); c2["signature"] = s2
r6 = SB.verify(charge, c2)
assert r6["verdict"] == "RED" and r6["reason_code"] == 7, \
    f"N2-evidenceHash-swap-rc7-beklendi: {r6}"
print("  N2-evidenceHash-swap ( yeni-gerçek-imzalı) → RED rc7 ( fail-closed)")
print("  SONUÇ: pacta-zkTLS-snark-açığı-GERÇEK ( sahte-proof-geçer; AT-149-aile-sınıfı); "
          "dumen/veridrome-alıcı-tarafı-DOĞRU-modeller-§6'ya-bağlandı")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: yedi-alıcı-tarafı-denetim-dikişi (zkTLS-açık-belgeli)" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-157: Alıcı-tarafı-tüketim-denetimi — GÜVENLİK-BULGUSU: pacta-zkTLS-snark-gate"
[[ $FAIL -eq 0 ]]

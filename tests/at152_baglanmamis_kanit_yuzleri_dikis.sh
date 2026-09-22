#!/usr/bin/env bash
# AT-152: BAĞLANMAMIŞ-PROJELERİN-KANIT-YÜZLERİ — §6-coverage-boşluğunu-kapat.
#
# LEAD'İN-TALİMATI: " Bağlananlar: tamga,sester,swarmax,dumen,pacta,pqhaven,
# tenderix,veridict. BOŞLUK: fleksa, yieldix, syntropion, pactiva, veridrome
# ( whitelist'te-olup-§6'ya-bağlanmamış). Tara: gerçek-kanıt-üretim-yüzü-ARANIYOR;
# VARSA → RFC-010'a-bağla ( §6-chain=ilgili); YOKSA → İNDETERMİNE."
#
# TARAMA-SONUCU ( 5-proje):
#   veridrome/ → MERKEZİ-aday: core/crypto.py MerkleTreeAuditLog ( RFC-6962:
#     0x00-yaprak/0x01-iç-düğüm) + get_root_hex + generate_proof + verify_proof
#     ( dışarıdan-SECRET'SIZ-bağımsız-denetim). runner.py:164-üretim-merkle-yolu.
#   fleksa/     → audit/ledger.py CryptographicSavingsLedger.compute_merkle_root
#     ( canonical-json SHA-256-Merkle; deterministik-head-anchor)
#   yieldix/    → crypto/signer.py Ed25519ReportSigner + telemetry/reporter
#     MonthlyReportGenerator.generate_signed_report ( Ed25519-imzalı-SLA-raporu)
#   syntropion/ → AT-131/132/133 ile-ZATEN-BAĞLI ( audit-ledger+shm-ipc+router);
#     §6-zaten-syntropion-adıyla-ölçüldü → TEKRAR-YOK
#   pactiva/    → attestation.compute_attestation_signature + webhook-HMAC:
#     HMAC-secret-tabanlı ( dışarıdan-secret'sız-değil); imza-anchor-üretir-AMA
#     §6-head-anchor DEĞİL → bu-test-kapsamı-dışı ( İNDETERMİNE-notu)
#
# ÖNEMLİ-BULGU: veridrome-AT-134-ve-fleksa-AT-107-zaten-§6'ya-bağlanmıştı-AMA
# **chain:"tamga"**-ile ( kendi-zincir-adları-DEĞİL) — Lead'in-boşluğu-tam-burada:
# üç-proje-de-whitelist'te-olup-KENDİ-ADINDA-§6'ya-bağlanmamış. Bu-test-üçünü-de
# kendi-adıyla-bağlar ( whitelist'te-hepsi-zaten-var).
#
# ÜÇ-BAĞLAMA + ortak-negatifler:
#   A) veridrome ( öncelik): RFC-6962-Merkle + verify_proof-bağımsız → §6-veridrome
#   B) fleksa: merkle-head-anchor → §6-fleksa
#   C) yieldix: Ed25519-imzalı-rapor-digest → §6-yieldix
#   Her-bağlama: gerçek-üretim-yolu + RFC-010-GREEN-6/6-§6-equals
#   Negatifler: rc4 ( sahte-imza) + rc7 ( evidenceHash-swap) + yanlış-kanıt-reddi
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/BAGLANMAMIS-KANIT-YUZ/$(date +%F)/at152.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-152: Bağlanmamış-projelerin-kanıt-yüzleri → §6-kendi-adıyla (veridrome/fleksa/yieldix)"

if ! python3 -c "import eth_keys, eth_utils" 2>/dev/null; then
  note "[SKIP] AT-152: eth_keys/eth_utils-yok — gerçek-ecrecover-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# ---------------------------------------------------------------- A) VERIDROME
python3 - <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, re, sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/veridrome/src")
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
from veridrome.core.crypto import MerkleTreeAuditLog, VeridromeAuthoritySigner
import settlement_bind_verify as SB
from eth_keys import keys as ek
from eth_utils import to_checksum_address

# A1) RFC-6962-gerçek-üretim-yolu ( runner.py:164'ün-yapığı-gibi: DOM/HTTP/LLM-yaprakları)
mt = MerkleTreeAuditLog()
for d in (b"dom:click#btn", b"http:GET/api/v1/jobs", b"llm:tokens=512",
          b"dom:input#email", b"http:POST/submit"):
    mt.add_leaf(d)
root_hex = mt.get_root_hex()               # "0x"+64hex
assert re.fullmatch(r"0x[0-9a-f]{64}", root_hex), f"root-formatı-bozuk: {root_hex}"
root_b = mt.get_root()
assert len(root_b) == 32, "RFC-6962-kök-32-bayt-değil"

# A2) bağımsız-denetim ( dışarıdan-secret'sız): audit-path-üret + doğrula
proof = mt.generate_proof(2)
assert MerkleTreeAuditLog.verify_proof(b"llm:tokens=512", proof, root_b) is True, \
    "gerçek-yaprak-denetim-geçmedi"
# yanlış-yaprak → False ( fail-closed-denetim)
assert MerkleTreeAuditLog.verify_proof(b"llm:tokens=999", proof, root_b) is False, \
    "yanlış-yaprak-denetim-geçti ( güvenlik-açığı)"
print(f"  A1-veridrome: RFC-6962-Merkle ( 5-yaprak: dom/http/llm) → root={root_hex[:18]}…; "
          "verify_proof-bağımsız-True; yanlış-yaprak-False")

# A3) RFC-010-GREEN — §6-chain="veridrome" ( KENDİ-ADINDA; AT-134-chain:tamga-değil)
root64 = root_hex[2:]                      # 64hex ( §6-head_hex-alanı)
BUYER = ek.PrivateKey(os.urandom(32))
ADDR = to_checksum_address(BUYER.public_key.to_address())
govde = {"buyerAddress": ADDR, "sellerAddress": "0x" + "2" * 40,
         "settlementRef": "VRD-MERKLE-152",
         "evidenceHash": {"alg": "sha256", "hex": root64}}
d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
sig = BUYER.sign_msg_hash(bytes.fromhex(d)).to_hex()
claim = dict(govde); claim["signature"] = sig
charge = {"seq": 5, "prev": "0" * 64, "h": root64,
          "delivery_hash": {"alg": "sha256", "hex": root64},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": "VRD-MERKLE-152",
                              "claim_evidence_hash": {"alg": "sha256", "hex": d},
                              "payer": ADDR, "payee": "0x" + "2" * 40,
                              "verified_at": "2026-09-22T00:00:00Z"},
          "foreign_chain_proof": {"chain": "veridrome", "head_hex": root64,
                                  "entries": 5, "evidence_link": "equals",
                                  "verify_cmd": "veridrome.crypto: verify_proof"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"§6-veridrome-GREEN-beklendi: {r}"
for k in ("1_receipt", "2_claim_sig", "3_settlement_ref", "4_parties",
          "5_evidence_hash", "6_foreign_chain"):
    assert r["checks"].get(k) is True, f"A-{k}-geçmedi: {r}"
print("  A2-§6-veridrome-KENDİ-ADINDA: RFC-010-GREEN ( 6/6; equals; AT-134'ten-"
          "farklı-olarak-chain:'veridrome')")
# A-negatif: sahte-imza + evidenceHash-swap ( rc4/rc7)
for sahte in ("ff" * 33, os.urandom(65).hex()):
    cs = dict(govde); cs["signature"] = sahte
    assert SB.verify(charge, cs)["reason_code"] == 4, "A-rc4-yakalanmadı"
g2 = dict(govde); g2["evidenceHash"] = {"alg": "sha256", "hex": "9" * 64}
d2 = hashlib.sha256(json.dumps(g2, sort_keys=True).encode()).hexdigest()
s2 = BUYER.sign_msg_hash(bytes.fromhex(d2)).to_hex()
c2 = dict(g2); c2["signature"] = s2
assert SB.verify(charge, c2)["reason_code"] == 7, "A-rc7-yakalanmadı"
print("  A3-negatifler: sahte-imza→rc4 + evidenceHash-swap→rc7 ( fail-closed)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A) veridrome RFC-6962-merkle → §6-veridrome" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A) veridrome"; }

# ---------------------------------------------------------------- B) FLEKSA
python3 - <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/fleksa/src")
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
from fleksa.audit.ledger import CryptographicSavingsLedger
import settlement_bind_verify as SB
from eth_keys import keys as ek
from eth_utils import to_checksum_address

# B1) gerçek-ledger-anchor ( server/app.py:386-nın-üretim-yolu)
led = CryptographicSavingsLedger()
for e in ({"event": "policy_applied", "rule": "R1", "amount": 12.5},
          {"event": "withdrawal", "amount": 3.2},
          {"event": "policy_applied", "rule": "R2", "amount": 8.0}):
    led.append_entry(e)
root = led.compute_merkle_root()
assert len(root) == 64, f"fleksa-kök-64hex-değil: {len(root)}"

# B2) deterministik + tahriz-dayanıklı ( yeni-girdi→değişir)
led2 = CryptographicSavingsLedger()
for e in ({"event": "policy_applied", "rule": "R1", "amount": 12.5},
          {"event": "withdrawal", "amount": 3.2},
          {"event": "policy_applied", "rule": "R2", "amount": 8.0}):
    led2.append_entry(e)
assert led2.compute_merkle_root() == root, "aynı-girdi-farklı-kök ( deterministik-değil)"
led2.append_entry({"event": "extra"})
assert led2.compute_merkle_root() != root, "yeni-girdi-kökü-değiştirmedi"
print(f"  B1-fleksa: CryptographicSavingsLedger ( 3-girdi) → merkle-root={root[:16]}…; "
          "deterministik + yeni-girdi→değişir")

# B3) RFC-010-GREEN — §6-chain="fleksa" ( KENDİ-ADINDA; AT-107-chain:tamga-değil)
BUYER = ek.PrivateKey(os.urandom(32))
ADDR = to_checksum_address(BUYER.public_key.to_address())
govde = {"buyerAddress": ADDR, "sellerAddress": "0x" + "2" * 40,
         "settlementRef": "FLX-LEDGER-152",
         "evidenceHash": {"alg": "sha256", "hex": root}}
d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
sig = BUYER.sign_msg_hash(bytes.fromhex(d)).to_hex()
claim = dict(govde); claim["signature"] = sig
charge = {"seq": 3, "prev": "0" * 64, "h": root,
          "delivery_hash": {"alg": "sha256", "hex": root},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": "FLX-LEDGER-152",
                              "claim_evidence_hash": {"alg": "sha256", "hex": d},
                              "payer": ADDR, "payee": "0x" + "2" * 40,
                              "verified_at": "2026-09-22T00:00:00Z"},
          "foreign_chain_proof": {"chain": "fleksa", "head_hex": root,
                                  "entries": 3, "evidence_link": "equals",
                                  "verify_cmd": "fleksa.audit: compute_merkle_root"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"§6-fleksa-GREEN-beklendi: {r}"
for k in ("1_receipt", "2_claim_sig", "3_settlement_ref", "4_parties",
          "5_evidence_hash", "6_foreign_chain"):
    assert r["checks"].get(k) is True, f"B-{k}-geçmedi: {r}"
print("  B2-§6-fleksa-KENDİ-ADINDA: RFC-010-GREEN ( 6/6; equals)")
# B-negatif
for sahte in ("ff" * 33, os.urandom(65).hex()):
    cs = dict(govde); cs["signature"] = sahte
    assert SB.verify(charge, cs)["reason_code"] == 4, "B-rc4-yakalanmadı"
g2 = dict(govde); g2["evidenceHash"] = {"alg": "sha256", "hex": "9" * 64}
d2 = hashlib.sha256(json.dumps(g2, sort_keys=True).encode()).hexdigest()
s2 = BUYER.sign_msg_hash(bytes.fromhex(d2)).to_hex()
c2 = dict(g2); c2["signature"] = s2
assert SB.verify(charge, c2)["reason_code"] == 7, "B-rc7-yakalanmadı"
print("  B3-negatifler: sahte-imza→rc4 + evidenceHash-swap→rc7")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: B) fleksa merkle-ledger → §6-fleksa" \
              || { FAIL=$((FAIL+1)); note "  FAIL: B) fleksa"; }

# ---------------------------------------------------------------- C) YIELDIX
python3 - <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/yieldix/src")
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
from yieldix.crypto.signer import Ed25519ReportSigner, sha256_digest_hex
import settlement_bind_verify as SB
from eth_keys import keys as ek
from eth_utils import to_checksum_address

# C1) gerçek-imzalı-SLA-raporu ( telemetry/reporter'ın-üretim-yolu)
ys = Ed25519ReportSigner()
rapor = {"report_id": "yrpt_202609_t1", "tenant_id": "t1",
         "total_leads": 128, "qualified_sql": 41,
         "p95_speed_to_lead_seconds": 17.5, "circuit_breaker_triggered": False}
digest, sig = ys.sign_dict(rapor)          # sha256-digest + Ed25519-sig-128hex
assert len(digest) == 64 and len(sig) == 128, "digest/sig-uzunluğu-bozuk"

# C2) dışarıdan-bağımsız-doğrulama + yanlış-anahtar-reddi
assert Ed25519ReportSigner.verify_signature(rapor, sig, ys.public_key_hex) is True, \
    "gerçek-imza-doğrulanmadı"
assert Ed25519ReportSigner.verify_signature(rapor, sig,
        Ed25519ReportSigner().public_key_hex) is False, "yanlış-anahtar-geçti"
assert sha256_digest_hex(rapor) == digest, "digest-bağımsız-tutmadı"
print(f"  C1-yieldix: Ed25519ReportSigner-imzalı-SLA-raporu → digest={digest[:16]}…; "
          "verify-True + yanlış-anahtar-False")

# C3) RFC-010-GREEN — §6-chain="yieldix" ( KENDİ-ADINDA; §6-İLK-KEZ)
BUYER = ek.PrivateKey(os.urandom(32))
ADDR = to_checksum_address(BUYER.public_key.to_address())
govde = {"buyerAddress": ADDR, "sellerAddress": "0x" + "2" * 40,
         "settlementRef": "YLX-REPORT-152",
         "evidenceHash": {"alg": "sha256", "hex": digest}}
d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
sigx = BUYER.sign_msg_hash(bytes.fromhex(d)).to_hex()
claim = dict(govde); claim["signature"] = sigx
charge = {"seq": 1, "prev": "0" * 64, "h": digest,
          "delivery_hash": {"alg": "sha256", "hex": digest},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": "YLX-REPORT-152",
                              "claim_evidence_hash": {"alg": "sha256", "hex": d},
                              "payer": ADDR, "payee": "0x" + "2" * 40,
                              "verified_at": "2026-09-22T00:00:00Z"},
          "foreign_chain_proof": {"chain": "yieldix", "head_hex": digest,
                                  "entries": 1, "evidence_link": "equals",
                                  "verify_cmd": "yieldix.crypto: verify_signature"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"§6-yieldix-GREEN-beklendi: {r}"
for k in ("1_receipt", "2_claim_sig", "3_settlement_ref", "4_parties",
          "5_evidence_hash", "6_foreign_chain"):
    assert r["checks"].get(k) is True, f"C-{k}-geçmedi: {r}"
print("  C2-§6-yieldix-İLK-KEZ-KENDİ-ADINDA: RFC-010-GREEN ( 6/6; equals)")
# C-negatif
for sahte in ("ff" * 33, os.urandom(65).hex()):
    cs = dict(govde); cs["signature"] = sahte
    assert SB.verify(charge, cs)["reason_code"] == 4, "C-rc4-yakalanmadı"
g2 = dict(govde); g2["evidenceHash"] = {"alg": "sha256", "hex": "9" * 64}
d2 = hashlib.sha256(json.dumps(g2, sort_keys=True).encode()).hexdigest()
s2 = BUYER.sign_msg_hash(bytes.fromhex(d2)).to_hex()
c2 = dict(g2); c2["signature"] = s2
assert SB.verify(charge, c2)["reason_code"] == 7, "C-rc7-yakalanmadı"
print("  C3-negatifler: sahte-imza→rc4 + evidenceHash-swap→rc7")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: C) yieldix Ed25519-report → §6-yieldix" \
              || { FAIL=$((FAIL+1)); note "  FAIL: C) yieldix"; }

echo
note "  syntropion-zaten-AT-131/132/133-ile-§6-syntropion-adında-bağlı (tekrar-yok)"
note "  pactiva-HMAC-secret-tabanlı-üretir ( §6-head-anchor-değil) → İNDETERMİNE-notu"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-152: Bağlanmamış-projelerin-kanıt-yüzleri → §6-kendi-adıyla (veridrome/fleksa/yieldix)"
[[ $FAIL -eq 0 ]]

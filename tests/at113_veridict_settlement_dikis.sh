#!/usr/bin/env bash
# AT-113: VERIDICT-SETTLEMENT (üçüncü-yüz) → RFC-010-DİKİŞİ (x402/v1 — gerçek-ecrecover).
#
# AT-091 ilk-dikişi yaptı (keys/ledger/certificate). Kalan-üçüncü-yüz:
# settlement.py — "certificate → settlement-claim bridge":
#   "the gap in the agent economy is between 'payment happened' and 'the work
#    was provably done'. Veridict's certificate is exactly the second half."
# Bu-modül-tam-RFC-010'ın-alanı: ödeme-layer'ının-değerlendireceği-bir-
# machine-checkable-yetki-üretir (para-hareket-etmez, bağlamayı-yapar).
#
# ENTEGRASYON-NOKTALARI (gerçek-kod, gerçek-satır):
#   veridict/settlement.py:62   SettlementPolicy.digest — policy-şekli-kilitli
#   veridict/settlement.py:115  build_settlement_claim — verdict/risk/diversity
#   veridict/settlement.py:162  verify_settlement_claim — 3-yol-reconciliation
#   veridict/settlement.py:78   _DIGEST_FIELDS — "binding-would-be-cosmetic"-notu
#   veridict/settlement.py:72   _RISK_ORDER (low<medium<high<critical)
#   tamga/tools/settlement_bind_verify.py:126  verify()-gate
#   tamga/tamga_attest_verify.py:64   ecrecover_to_pub (x402/v1-sözleşmesi)
#
# §3b-ŞEMA-SEÇİMİ: x402/v1 — settlement-bridge-BİR-ÖDEME-LAYER'INA-hitap-eder
# ("a payment layer can evaluate without trusting the agent"); AT-091'in-
# tamga/native-kararı-sertifika-mührü-içindi, bu-yüz-ödeme-yetki-yüzüdür-ve
# EVM-ekonomisinde-x402/v1-gerçek-para-kanalıdır (AT-080/084/085/090/109-ile-
# aynı-cluster). Test-double-YOK: gerçek-ecrecover.
#
# SETTLEMENT-GÜVENLİK-MODELİ (bu-testin-özü): claim'e-GÜVENİLMEZ —
# verify_settlement_claim-üç-yolu-da-ölçer:
#   (1) self_consistent: claim_digest-kendi-alanlarından-yeniden-hesaplanır
#       (valid-flip-saldırısı-bunu-kırar — "binding-would-be-cosmetic"-notu)
#   (2) matches_certificate: claim-BU-cert+BU-policy'den-gerçekten-çıkar-mı
#       (policy-swap-saldırısı-bunu-kırar)
#   (3) presented_valid: sunulan-valid-ile-beklenen-valid-aynı-mı
# Fail-closed: bilinmeyen-risk→high, tek-aile-jüri, eksik-coverage.
#
# Bu-test-altı-kanıt:
#   1) GERÇEK-settlement-claim: build → valid + claim_digest + policy_digest
#   2) ÜRETİCİ-TARAFI-SAĞLAMLIK: 3-yol-gate + policy-swap + 3-fail-closed-yol
#   3) DİKİŞ-GREEN: claim_digest=evidenceHash + x402/v1 → 6-kontrol (STOCK)
#   4) §6-foreign_chain: evidence_link='derived' → GREEN
#   5) NEGATİF-1: sahte-claim-digest (uydurma-64hex) → RED rc7
#   6) NEGATİF-2: party-swap (başka-satıcı, imza-geçerli) → RED rc6
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/VERIDICT-SETTLE/$(date +%F)/at113.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-113: Veridict-settlement (üçüncü-yüz) → RFC-010 x402/v1 dikişi"

VS="/home/gokun/projects/00_TAMGA-MESH/veridict/veridict/settlement.py"
if [ ! -f "$VS" ]; then
  note "[SKIP] AT-113: Veridict-kodu-bu-makinede-değil (CI) —"
  note "       settlement-bridge-dikişi-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import eth_keys" 2>/dev/null; then
  note "[SKIP] AT-113: eth-keys-yok —"
  note "       gerçek-imza-üretilemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$LOG" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, inspect, json, os, sys
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
# MUTLAK-YOL (§5b-dersi: kabuk-cwd'si-çağrılar-arası-sıfırlanır)
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/veridict")

LOG = sys.argv[1]                                  # kanıt-dizini (shell-değişkeni-değil)

from veridict.settlement import (SettlementPolicy, build_settlement_claim,
                                 verify_settlement_claim, _claim_digest)
import settlement_bind_verify as SB
import tamga_attest_verify as TAV
from eth_keys import keys

# STUB-YOK (AT-075-disiplini): gate'in-imza-yoluna-dokunmadık
assert "ecrecover_to_pub" in inspect.getsource(SB._claim_signer)

# --- 1) GERÇEK-settlement-claim: doğrulanmış-sertifika → ödeme-yetkisi
CERT = {
    "cert_id": "veridict-cert-0001",
    "subject": {"task_id": "task-42", "artifact_digest": "a" * 64},
    "claims": [{"verdict_value": "VERIFIED"}, {"verdict_value": "VERIFIED"}],
    "jury_composition": {"families": ["openai", "anthropic"]},
    "risk_level": "low",
}
pol = SettlementPolicy()                           # varsayılan: sadece-VERIFIED/low/2-aile/100%
sc = build_settlement_claim(CERT, pol)
assert sc.valid is True and sc.accepted_claims == 2 and sc.total_claims == 2
assert sc.jury_families == ["anthropic", "openai"]  # sorted-set
assert sc.risk_level == "low"
# claim_digest-gerçek-özüt: _DIGEST_FIELDS-üzerinden-bağımsız-yeniden-üretim
assert _claim_digest(sc.__dict__) == sc.claim_digest, "özüt-deterministik-değil"
assert len(sc.claim_digest) == 64 and len(sc.policy_digest) == 64
# policy_digest-alıcı-tarafında-bağımsız-yeniden-üretilebilir (policy-şekli-kilitli)
assert SettlementPolicy().digest() == pol.digest()
print(f"  GERÇEK-settlement-claim: valid=True (2/2-VERIFIED, 2-jüri-ailesi, low-risk)")
print(f"    claim_digest {sc.claim_digest[:20]}… | policy_digest "
      f"{sc.policy_digest[:16]}… (bağımsız-yeniden-üretim)")

# --- 2) ÜRETİCİ-TARAFI-SAĞLAMLIK: 3-yol-gate + policy-swap + fail-closed
# (a) GREEN-yol: reconcile-gerçek-claim → valid
vr = verify_settlement_claim(json.loads(sc.to_json()), CERT, pol)
assert vr["valid"] is True and vr["reasons"] == [], f"reconcile-GREEN: {vr}"
# (b) valid-flip-saldırısı → self_consistent-False (digest-kendi-alanlarından-
#     yeniden-hesaplanmaz — "binding-would-be-cosmetic"-notunun-canlı-kanıtı)
bad = json.loads(sc.to_json()); bad["valid"] = False
vr2 = verify_settlement_claim(bad, CERT, pol)
assert vr2["valid"] is False
assert any("does not recompute" in r for r in vr2["reasons"]), \
    "valid-flip-self-consistent-tespit-edilmeli"
# (c) policy-swap-saldırısı → matches_certificate-False (daha-gevşek-policy)
pol_loose = SettlementPolicy(accept_verdicts=("VERIFIED", "PARTIAL"))
vr3 = verify_settlement_claim(json.loads(sc.to_json()), CERT, pol_loose)
assert vr3["valid"] is False
assert any("does not follow from" in r for r in vr3["reasons"]), \
    "policy-swap-tespit-edilmeli"
# (d) fail-closed-yol-1: bilinmeyen-risk → high-varsayılır → reddedilir
c_risk = dict(CERT); c_risk["risk_level"] = "bilinmiyor"
assert build_settlement_claim(c_risk, pol).valid is False
# (e) fail-closed-yol-2: tek-aile-jüri (§5.2-self-preference)
c_fam = dict(CERT); c_fam["jury_composition"] = {"families": ["openai"]}
assert build_settlement_claim(c_fam, pol).valid is False
# (f) fail-closed-yol-3: eksik-coverage (1/2-VERIFIED)
c_cov = dict(CERT)
c_cov["claims"] = [{"verdict_value": "VERIFIED"}, {"verdict_value": "REFUTED"}]
sc_cov = build_settlement_claim(c_cov, pol)
assert sc_cov.valid is False and sc_cov.accepted_claims == 1
# (g) reddedilen-claim-de-bir-ARTIFACTTIR (sessiz-geçiş-yok — modülün-tasarımı)
assert sc_cov.claim_digest != "" and "coverage" in " ".join(sc_cov.reasons)
print("    3-yol-gate: GREEN-reconcile; valid-flip→self-consistent-False; "
      "policy-swap→mismatch; fail-closed (risk/aile/coverage)")

# --- 3) DİKİŞ-GREEN: claim_digest=evidenceHash + x402/v1 (AT-080-reçetesi)
BK = keys.PrivateKey(bytes.fromhex("7a" * 31 + "01"))  # test-only-anahtar
BUYER = BK.public_key.to_address()
SELLER = "0x" + "2" * 40
PID = "VERIDICT-SETTLE-0001"
govde = {"buyerAddress": BUYER, "sellerAddress": SELLER, "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": sc.claim_digest}}
digest_hex = hashlib.sha256(
    json.dumps(govde, sort_keys=True).encode()).hexdigest()
s = BK.sign_msg_hash(bytes.fromhex(digest_hex))      # z=raw-sha256, öneksiz
sig_hex = (s.r.to_bytes(32, "big") + s.s.to_bytes(32, "big")
           + bytes([27 + s.v])).hex()
assert TAV.ecrecover_to_pub(digest_hex, sig_hex).lower() == BUYER.lower(), \
    "gerçek-imza-gerçek-adrese-çözümlenmedi"
claim = dict(govde); claim["signature"] = sig_hex
charge = {"seq": 113, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": sc.claim_digest},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256",
                                                      "hex": sc.claim_digest},
                              "payer": BUYER, "payee": SELLER,
                              "verified_at": "2026-09-30T00:00:00Z"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"settlement-dikişi-GREEN-beklendi: {r}"
assert all(r["checks"].values()), f"bir-kontrol-eksik: {r['checks']}"
print("  DİKİŞ-GREEN: settlement-claim_digest=evidenceHash, x402/v1 6-kontrol "
      "(STOCK-ecrecover)")

# --- 4) §6-foreign_chain: derived-bağı (AT-085-deseni)
charge6 = json.loads(json.dumps(charge))
charge6["foreign_chain_proof"] = {
    "chain": "tamga",                             # whitelist-kısıtı (AT-079-dersi)
    "head_hex": hashlib.sha256(bytes.fromhex(sc.claim_digest)).hexdigest(),
    "entries": 1,
    "evidence_link": "derived",
    "verify_cmd": "veridict.settlement.verify_settlement_claim"}
r6 = SB.verify(charge6, claim)
assert r6["verdict"] == "GREEN" and r6["checks"].get("6_foreign_chain") is True, \
    f"§6-kanıtlı-GREEN-beklendi: {r6}"
print("  §6-foreign_chain: evidence_link='derived' (head=sha256(claim_digest)) → GREEN")

# --- kanıt-fixture'ı-kalıcı-la
FX = os.path.join(os.path.dirname(LOG), "at113-veridict-settle.json")
json.dump({"test": "AT-113", "scheme": "x402/v1",
           "project": "veridict/settlement",
           "cert_id": CERT["cert_id"], "claim_digest": sc.claim_digest,
           "policy_digest": sc.policy_digest,
           "accepted_claims": sc.accepted_claims, "total_claims": sc.total_claims,
           "jury_families": sc.jury_families, "payment_id": PID,
           "charge": charge6, "claim": claim, "verdict": r6["verdict"]},
          open(FX, "w"), ensure_ascii=False, indent=1)
print(f"  kanıt-fixture: {FX}")

# --- 5) NEGATİF-1: sahte-claim-digest (uydurma-64hex) → RED rc7
# saldırgan-gerçek-bir-sertifika-üretmeden-uydurma-claim_digest-yazar; alıcı
# verify_settlement_claim'ı-çağırınca-özüt-tutmayacak → evidenceHash-uyuşmazlığı.
chargeN1 = json.loads(json.dumps(charge))
chargeN1["delivery_hash"]["hex"] = "f" * 64
rN1 = SB.verify(chargeN1, claim)
assert rN1["verdict"] == "RED" and rN1["reason_code"] == 7, \
    f"sahte-claim-RED-rc7-beklendi: {rN1}"
print("  sahte-claim-digest (uydurma-64hex) → RED rc7 — kanıtsız-ödeme-alınamaz")

# --- 6) NEGATİF-2: party-swap (başka-satıcı, imza-geçerli) → RED rc6
govde2 = dict(govde)
govde2["sellerAddress"] = "0x" + "9" * 40           # başkası
s2 = BK.sign_msg_hash(bytes.fromhex(
    hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()))
claim2 = dict(govde2)
claim2["signature"] = (s2.r.to_bytes(32, "big") + s2.s.to_bytes(32, "big")
                       + bytes([27 + s2.v])).hex()
rN2 = SB.verify(charge, claim2)
assert rN2["verdict"] == "RED" and rN2["reason_code"] == 6, \
    f"party-swap-RED-rc6-beklendi: {rN2}"
assert rN2["checks"].get("2_claim_sig") is True, \
    "negatif-imza-GEÇERLİ-olmalı (saldırı-imzada-değil-party-bağında-yakalanmalı)"
print("  party-swap (imza-geçerli, satıcı-değişti) → RED rc6 (party_mismatch)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Veridict-settlement-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-113: Veridict-settlement (üçüncü-yüz) → RFC-010 x402/v1"
[[ $FAIL -eq 0 ]]

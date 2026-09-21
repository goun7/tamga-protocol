#!/usr/bin/env bash
# AT-108: VERIDROME-İKİNCİ-YÜZ → RFC-010-DİKİŞİ (B-sınıfı — gerçek-W3C-VC).
#
# AT-072 ilk-yüzü-bağladı (crypto.py: MerkleTreeAuditLog + VeridromeAuthoritySigner).
# İKİNCİ-YÜZ: credentials/w3c_vc.py — VeridromeCredentialManager:
#   issue_credential() — W3C-VC-v2.0 üretir, Ed25519 ile imzalar (sign_base64),
#                        RFC-6962-CT-defterine-yazar, VAPAP-token-döndürür
#   verify_credential() — imza-bütünlüğü + süre doğrular (gerçek-verify)
#   create_vapap_token() — kurumsal-API-gateway tasdik-token'ı
#
# AT-077-DİSİPLİNİ (test-double-YOK): RFC-010 §3b-imza-sözleşmesi imzayı
# sha256-digest'ın-HAM-BAYTLARI üzerine atar (gövde-metnine-değil). Veridrome
# kendi-VC'sini canonical-JSON-üzerine-imzalar — bu-yüzden-RFC-010-claim-için
# AYNI-gerçek-signer ile digest-baytları-üzerine-sözleşmeli-imza-üretiriz
# (AT-077'nin-nacl-gerçek-anahtar-dersiyle-aynı; double-YOK).
#
# Altı-kanıt + 2-negatif:
#   1) gerçek-W3C-VC-üretimi (gerçek-signer + gerçek-CT-log + VAPAP)
#   2) üretici-tarafı-sağlam: verify_credential doğru-True / yanlış-False
#   3) RFC-6962-kök R9-3-kanonik + gerçek-üyelik-kanıtı (AT-072'nin-üzerine)
#   4) RFC-010-sözleşmeli-imza (digest-baytları) → stock-GREEN, double-YOK
#   5) NEG-1: sahte-imza → RED rc4
#   6) NEG-2: evidenceHash-swap → RED rc7
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/VERIDROME-2/$(date +%F)/at108.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-108: Veridrome ikinci-yüz (W3C-VC) → RFC-010 dikişi"

VE="/home/gokun/projects/01_unicorn/73-Veridrome/src"
if [ ! -f "$VE/veridrome/credentials/w3c_vc.py" ] || [ ! -f "$VE/veridrome/core/crypto.py" ]; then
  note "[SKIP] AT-108: Veridrome-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import cryptography" 2>/dev/null; then
  note "[SKIP] AT-108: cryptography-kütüphanesi-yok —"
  note "       gerçek-Ed25519-üretilemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$VE" <<'PYEOF' >> "$LOG" 2>&1
import base64, hashlib, json, os, sys, tempfile
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from veridrome.core.crypto import VeridromeAuthoritySigner, MerkleTreeAuditLog
from veridrome.credentials.w3c_vc import VeridromeCredentialManager
import settlement_bind_verify as SB

# --- 1) GERÇEK-W3C-VC-üretimi (gerçek-Ed25519-otorite + gerçek-CT-defteri)
signer = VeridromeAuthoritySigner()                  # cryptography-ed25519, gerçek
PUB = signer.public_key_bytes.hex()                  # 32-byte-genel-anahtar
assert len(PUB) == 64 and all(c in "0123456789abcdef" for c in PUB)

CT = tempfile.mktemp(suffix=".jsonl")
mgr = VeridromeCredentialManager(signer, ct_log_path=CT)

# RFC-6962-yürütme-izi (AT-072'nin-crypto.py'si — şimdi-VC'nin-içine-bağlanır)
mt = MerkleTreeAuditLog()
mt.add_leaf(b"eval:agent-7:w1a:pass")
mt.add_leaf(b"exec:step-42:dom-mutate")
KOK = mt.get_root_hex()
assert KOK.startswith("0x") and len(KOK) == 66, "R9-3-kanonik-beklendi"

vc, vapap = mgr.issue_credential(
    job_id="JOB-108", agent_id="did:veridrome:agent-7",
    metrics={"w1a_score": 0.91, "task_success": True},
    tee_platform="sev-snp", pcr0_measurement="a"*64, merkle_root=KOK)
assert vc["proof"]["type"] == "Ed25519Signature2020"
assert vc["credentialSubject"]["executionMerkleRoot"] == KOK
ct_lines = open(CT, encoding="utf-8").read().strip().splitlines()
assert len(ct_lines) == 1 and json.loads(ct_lines[0])["cert_id"] == vc["id"]
assert base64.urlsafe_b64decode(vapap + "==")  # VAPAP-token-çözülebilir
print(f"  W3C-VC-üretildi: id={vc['id']} imza={vc['proof']['type']} "
      f"CT-defteri=1-girdi VAPAP=OK kök={KOK[:14]}…")

# --- 2) Üretici-tarafı-sağlam: gerçek-verify (double-YOK)
assert VeridromeCredentialManager.verify_credential(vc, signer.public_key_bytes) is True, \
    "gerçek-VC-gerçek-otorite-anahtarıyla-doğrulanmalı"
assert VeridromeCredentialManager.verify_credential(vc, bytes(32)) is False, \
    "yanlış-otorite-anahtarı-doğrulamamalı"
assert VeridromeCredentialManager.verify_credential(
    {**vc, "issuer": "did:sahte"}, signer.public_key_bytes) is False, \
    "değiştirilmiş-VC-doğrulamamalı (değişmezlik — imza-gövde-üzerine-atılır)"
print("  verify_credential: doğru-True; yanlış-anahtar-False; değiştirilmiş-VC-False")

# --- 3) RFC-6962-üyelik-kanıtı (AT-072'nin-üzerine: saf-kök-DEĞIL-üyelikle)
proof = mt.generate_proof(0)
assert MerkleTreeAuditLog.verify_proof(b"eval:agent-7:w1a:pass", proof, mt.get_root())
assert not MerkleTreeAuditLog.verify_proof(b"eval:agent-7:w1a:FAIL", proof, mt.get_root())
print(f"  RFC-6962-üyelik-kanıtı: {len(proof)}-seviye; doğru-yaprak-True, "
      f"yanlış-yaprak-False (saf-kökten-güçlü)")

# --- 4) RFC-010-SÖZLEŞMELİ-DİKİŞ (stock-yol, double-YOK)
# AT-077-dersi: Ed25519-imzası-digest'ın-ham-baytları-üzerine-atılır. Veridrome
# VC'sini-canonical-JSON-üzerine-imzalar (kendi-amacı-için); RFC-010-claim-için
# AYNI-gerçek-signer ile digest-baytları-üzerine-sözleşmeli-imza-üretiriz.
EV = hashlib.sha256(json.dumps(vc, sort_keys=True).encode()).hexdigest()
govde = {"buyerAddress": PUB, "sellerAddress": "0x2"*40,
         "settlementRef": "VRD-VC-108",
         "evidenceHash": {"alg": "sha256", "hex": EV}}
d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
sig = signer.sign(bytes.fromhex(d)).hex()            # gerçek-anahtar, digest-baytları
assert len(sig) == 128
assert sig[:64] != PUB, "imza-R-noktası-genel-anahtar-OLAMAZ (AT-077-eski-hata)"
claim = dict(govde); claim["signature"] = sig

charge = {"seq": 1, "prev": "0"*64, "h": "a"*64,
          "delivery_hash": {"alg": "sha256", "hex": EV},
          "settlement_bind": {"scheme": "tamga/native", "payment_id": "VRD-VC-108",
                              "claim_evidence_hash": {"alg": "sha256", "hex": d},
                              "payer": PUB, "payee": "0x2"*40,
                              "verified_at": "2026-09-21T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": KOK[2:],
                                  "entries": 2, "verify_cmd": "veridrome.w3c_vc"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"Veridrome-VC-dikişi-GREEN-beklendi: {r}"
assert all(r["checks"].get(k) is True for k in
           ("1_receipt", "2_claim_sig", "3_settlement_ref", "4_parties",
            "5_evidence_hash", "6_foreign_chain")), "altı-kontrol-tam-değil"
print(f"  RFC-010-sözleşmeli-claim → GREEN rc0 (STOCK-yol, double-YOK); "
      f"§6-foreign_chain: KOK[2:]={KOK[2:10]}…")

# --- 5) NEG-1: sahte-imza → RED rc4 (geçersiz-uzunluk + rastgele-64-byte)
for sahte in ("ff"*33, os.urandom(64).hex()):
    cs = dict(govde); cs["signature"] = sahte
    rs = SB.verify(charge, cs)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"sahte-imza-RED-rc4-beklendi ({sahte[:8]}…): {rs}"
print("  sahte-imza (geçersiz-uzunluk + rastgele-64-byte) → RED rc4")

# --- 6) NEG-2: evidenceHash-swap → RED rc7 (AT-077-negatif-kontrolü)
# saldırgan-aynı-otorite-anahtarıyla-geçerli-imza-AMA-kanıtı-başka-özüte-
# yönlendirir: imza-geçer, evidenceHash-delivery_hash'e-uymaz.
govde2 = dict(govde)
govde2["evidenceHash"] = {"alg": "sha256", "hex": "9"*64}
d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
s2 = signer.sign(bytes.fromhex(d2)).hex()            # aynı-gerçek-anahtarla
c2 = dict(govde2); c2["signature"] = s2
r2 = SB.verify(charge, c2)
assert r2["verdict"] == "RED" and r2["reason_code"] == 7, \
    f"evidenceHash-swap-RED-rc7-beklendi: {r2}"
print("  evidenceHash-swap (yeni-gerçek-imzalı) → RED rc7 (fail-closed)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Veridrome-W3C-VC-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-108: Veridrome ikinci-yüz (W3C-VC) → RFC-010"
[[ $FAIL -eq 0 ]]

#!/usr/bin/env bash
# AT-105: SESTER-POLICY-SIGNED (kalan-yüz) → RFC-010-DİKİŞİ (x402/v1 — gerçek-ecrecover).
#
# Sester'ın-3-AT'i-bağlandı (AT-090-ledger, AT-085-batch, +AT-095-K0). Kalan-yüz:
# policy_signed.py — imzalı-politika-zarfı (JWS-compact) + 24s-gevşetme-gate
# (execution-plan-§7/S3). Lead'in-tavsiye-ettiği tsa.py/coldstore.py SWARMAX'ta-
# dır (Sester'da-yok); Sester'ın-gerçek-kalan-yüzü-budur — kripto-anlamlı: JWS-
# ES256-asimetrik-imza + gövde-imza-bağı + fail-closed-vault.
#
# ENTEGRASYON-NOKTALARI (gerçek-kod, gerçek-satır):
#   sester/policy_signed.py:56    sign_policy — JWS-ES256-zarf-üretimi
#   sester/policy_signed.py:73    signed_policy_json — canonical-JSON (hash-stable)
#   sester/policy_signed.py:162   SignedPolicyVault — gevşetme-gate + evaluate
#   sester/policy_signed.py:30    RELAXATION_DELAY=86400 (24 saat)
#   sester/adapters.py:137/171    sign_mandate_jws / verify_mandate_jws (ES256)
#   sester/policy.py:70           Policy.from_dict (fail-closed PolicyCorruptError)
#   tamga/tools/settlement_bind_verify.py:126  verify()-gate
#   tamga/tamga_attest_verify.py:64   ecrecover_to_pub (x402/v1-sözleşmesi)
#
# §3b-ŞEMA-SEÇİMİ: x402/v1 — AT-090/AT-085-ile-aynı-Sester-cluster-kararı
# (Sester-üretim-ödeme-kanalı-x402; gerçek-EIP-191-secp256k1, test-double-YOK).
# JWS-ES256-(P-256)-imzası-ayrı-bir-üretici-tarafı-kanıtıdır: RFC-010-claim-
# imzasından-farklı-ön-görüntü (§4d-iki-kanal-notu) — policy-hash-(canonical-JSON-
# sha256)'i-evidenceHash'e-bağlarız, alıcı-verify_mandate_jws'ile-zarfı-doğrular.
#
# EKONOMİK-GÜVENLİK-HİKÂYESİ: satıcı-ödeme-sınırını-tek-tarafından-gevşetemez —
# SignedPolicyVault-gevşetmeyi-24s-gecikmeyle-uygular (pending-dönüşte-ESKİ-sıkı
# politika-geçerli-kalır). Bir-gevşetme-zarfı-bile-ısmarlanmışsa-kanıt-policy-hash
# olarak-RFC-010'a-bağlanır; alıcı-bağımsız-yeniden-üretip-doğrular.
#
# Bu-test-altı-kanıt:
#   1) GERÇEK-signed-policy: ES256-zarf + policy-hash + verify_mandate_jws True
#   2) ÜRETİCİ-TARAFI-SAĞLAMLIK: fail-closed + gevşetme-gate (pencere-içi-eski-sıkı)
#   3) DİKİŞ-GREEN: policy-hash=evidenceHash + x402/v1 → 6-kontrol (STOCK)
#   4) §6-foreign_chain: head=policy-hash, evidence_link='equals' → GREEN
#   5) NEGATİF-1: sahte-policy-hash (uydurma-64hex) → RED rc7
#   6) NEGATİF-2: party-swap (başka-satıcı, imza-geçerli) → RED rc6
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/SESTER-POLICY/$(date +%F)/at105.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-105: Sester-policy-signed (kalan-yüz) → RFC-010 x402/v1 dikişi"

SP="/home/gokun/projects/00_TAMGA-MESH/sester/sester/policy_signed.py"
if [ ! -f "$SP" ]; then
  note "[SKIP] AT-105: Sester-kodu-bu-makinede-değil (CI) —"
  note "       policy-signed-dikişi-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import eth_keys, cryptography" 2>/dev/null; then
  note "[SKIP] AT-105: eth-keys-veya-cryptography-yok —"
  note "       gerçek-imza-üretilemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$LOG" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, inspect, json, os, sys, tempfile
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
# MUTLAK-YOL (§5b-dersi: kabuk-cwd'si-çağrılar-arası-sıfırlanır)
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/sester")

LOG = sys.argv[1]                                  # kanıt-dizini (shell-değişkeni-değil)

from sester.adapters import AdapterError, verify_mandate_jws
from sester.policy_signed import (SignedPolicyVault, sign_policy, signed_policy_json)
from sester.policy import ALLOW, DENY, PolicyCorruptError
import settlement_bind_verify as SB
import tamga_attest_verify as TAV
from eth_keys import keys
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import serialization

# STUB-YOK (AT-075-disiplini): gate'in-imza-yoluna-dokunmadık
assert "ecrecover_to_pub" in inspect.getsource(SB._claim_signer)

# --- 1) GERÇEK-signed-policy: ES256-zarf + canonical-policy-hash
priv = ec.generate_private_key(ec.SECP256R1())     # asimetrik-üretim-anahtarı
PEM = priv.private_bytes(serialization.Encoding.PEM,
                         serialization.PrivateFormat.PKCS8,
                         serialization.NoEncryption())
PUB_PEM = priv.public_key().public_bytes(
    serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
KID = "sester-kid-01"
def resolve_key(kid, alg):                          # KeyResolver-Protokolü
    return PUB_PEM if kid == KID else None

# Policy-DSL (policy.py:70-şeması): per_request_max/daily_max + rules(id/then/when)
def policy_body(per_req, daily):
    return {"id": "sester-wp-0001",
            "defaults": {"per_request_max": per_req, "daily_max": daily},
            "rules": [{"id": "r-deny-over", "then": DENY, "when": {"amount_gt": per_req}},
                      {"id": "r-allow-host", "then": ALLOW,
                       "when": {"host_in": ["scrape"]}}]}

T0 = 1_700_000_000.0                                # sabit-zaman (gevşetme-penceresi)
env = sign_policy({"wallet_policy": policy_body(0.05, 5.0)},
                  alg="ES256", key=PEM, signer="did:key:zES256-simnet",
                  kid=KID, signed_at=T0)
assert set(env) == {"policy_envelope_version", "signed_at", "signer", "signature",
                    "policy"}, f"zarf-şekli-yanlış: {set(env)}"
assert env["policy_envelope_version"] == 1
# JWS-ES256-üretici-tarafı: gövde-imza-bağı-gerçek-doğrulama
body = verify_mandate_jws(env["signature"], resolve_key=resolve_key)
assert body == policy_body(0.05, 5.0), "JWS-payload-gövdeye-bağlı-değil"
# policy-hash: canonical-JSON-sha256 (alıcı-bağımsız-yeniden-üretilebilir)
canon = signed_policy_json(env)
ph = hashlib.sha256(canon.encode()).hexdigest()
assert len(ph) == 64 and hashlib.sha256(
    signed_policy_json(json.loads(canon)).encode()).hexdigest() == ph, \
    "canonical-JSON-deterministik-değil"
print(f"  GERÇEK-signed-policy: ES256-zarf → policy-hash {ph[:20]}…")
print(f"    verify_mandate_jws: gövde-bağı-True; canonical-JSON-deterministik")

# --- 2) ÜRETİCİ-TARAFI-SAĞLAMLIK: fail-closed + gevşetme-gate
# (a) sahte-JWS → AdapterError (imza-uyumsuz)
try:
    verify_mandate_jws(env["signature"].rsplit(".", 1)[0] + "." + "AAAA",
                       resolve_key=resolve_key)
    raise AssertionError("sahte-JWS-reddedilmeli")
except AdapterError:
    pass
# (b) bilinmeyen-kid → AdapterError (anahtar-çözülemez)
try:
    verify_mandate_jws(env["signature"], resolve_key=lambda k, a: None)
    raise AssertionError("bilinmeyen-kid-reddedilmeli")
except AdapterError:
    pass
# (c) SignedPolicyVault: fail-closed-yükleme + gevşetme-gate
vault = SignedPolicyVault(resolve_key=resolve_key, now=lambda: T0 + 100)
vault.load_envelope(env)
assert vault.is_pending_relaxation() is False, "tek-zarf-pending-değil"
assert vault.evaluate(0.03, "scrape").verdict == ALLOW
assert vault.evaluate(0.50, "scrape").verdict == DENY, \
    "limit-üstü-ödeme-reddedilmeli (sıkı-politika)"
# gevşetme: 0.05→5.00 (ikinci-zarf); 24s-penceresinde-ESKİ-sıkı-kalır
env_relax = sign_policy({"wallet_policy": policy_body(5.00, 50.0)},
                        alg="ES256", key=PEM, signer="did:key:zES256-simnet",
                        kid=KID, signed_at=T0 + 50)
vr = SignedPolicyVault(resolve_key=resolve_key, now=lambda: T0 + 1000)
vr.load_envelope(env); vr.load_envelope(env_relax)
assert vr.is_pending_relaxation() is True, "gevşetme-pending-olmalı"
assert vr.evaluate(0.50, "scrape").verdict == DENY, \
    "gevşetme-penceresinde-ESKİ-sıkı-politika-geçerli (24s-koruma)"
# 24s-sonrası: tick-yeni-politikayı-uygular
vr_late = SignedPolicyVault(resolve_key=resolve_key, now=lambda: T0 + 90000)
vr_late.load_envelope(env); vr_late.load_envelope(env_relax)
new_pol = vr_late.tick()
assert new_pol is not None and new_pol.per_request_max == 5.0
assert vr_late.is_pending_relaxation() is False
assert vr_late.evaluate(0.50, "scrape").verdict == ALLOW, \
    "pencere-sonrası-yeni-limit-uygulanmalı"
# (d) vault-fail-closed: resolve_key-None → SignedPolicyError
try:
    SignedPolicyVault(resolve_key=lambda k, a: None).load_envelope(env)
    raise AssertionError("imzasız-zarf-yüklenmemeli")
except Exception as e:
    assert "Error" in type(e).__name__, f"fail-closed-beklendi: {type(e)}"
print("    fail-closed: sahte-JWS/bilinmeyen-kid→AdapterError; "
      "gevşetme-penceresinde-ESKİ-sıkı-kalır (24s)")

# --- 3) DİKİŞ-GREEN: policy-hash=evidenceHash + x402/v1 (EIP-191, AT-080-reçetesi)
BK = keys.PrivateKey(bytes.fromhex("7a" * 31 + "01"))  # test-only-anahtar
BUYER = BK.public_key.to_address()
SELLER = "0x" + "2" * 40
PID = "SEST-POLICY-0001"
govde = {"buyerAddress": BUYER, "sellerAddress": SELLER, "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": ph}}
digest_hex = hashlib.sha256(
    json.dumps(govde, sort_keys=True).encode()).hexdigest()
s = BK.sign_msg_hash(bytes.fromhex(digest_hex))      # z=raw-sha256, öneksiz
sig_hex = (s.r.to_bytes(32, "big") + s.s.to_bytes(32, "big")
           + bytes([27 + s.v])).hex()
assert TAV.ecrecover_to_pub(digest_hex, sig_hex).lower() == BUYER.lower(), \
    "gerçek-imza-gerçek-adrese-çözümlenmedi"
claim = dict(govde); claim["signature"] = sig_hex
charge = {"seq": 105, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": ph},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256", "hex": ph},
                              "payer": BUYER, "payee": SELLER,
                              "verified_at": "2026-09-30T00:00:00Z"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"policy-signed-dikişi-GREEN-beklendi: {r}"
assert all(r["checks"].values()), f"bir-kontrol-eksik: {r['checks']}"
print("  DİKİŞ-GREEN: policy-hash=evidenceHash, x402/v1 6-kontrol (STOCK-ecrecover)")

# --- 4) §6-foreign_chain: policy-hash-ledger-head'i-olarak
charge6 = json.loads(json.dumps(charge))
charge6["foreign_chain_proof"] = {
    "chain": "tamga",                             # whitelist-kısıtı (AT-079-dersi)
    "head_hex": ph,
    "entries": 1,
    "evidence_link": "equals",                    # head == delivery_hash (içerik-bağı)
    "verify_cmd": "sester.policy_signed.signed_policy_json"}
r6 = SB.verify(charge6, claim)
assert r6["verdict"] == "GREEN" and r6["checks"].get("6_foreign_chain") is True, \
    f"§6-kanıtlı-GREEN-beklendi: {r6}"
print("  §6-foreign_chain: head=policy-hash, evidence_link='equals' → GREEN")

# --- kanıt-fixture'ı-kalıcı-la
FX = os.path.join(os.path.dirname(LOG), "at105-sester-policy.json")
json.dump({"test": "AT-105", "scheme": "x402/v1", "project": "sester/policy_signed",
           "jws_alg": "ES256", "policy_hash": ph, "kid": KID,
           "relaxation_delay": 86400.0, "buyer": BUYER, "seller": SELLER,
           "payment_id": PID, "charge": charge6, "claim": claim,
           "verdict": r6["verdict"]},
          open(FX, "w"), ensure_ascii=False, indent=1)
print(f"  kanıt-fixture: {FX}")

# --- 5) NEGATİF-1: sahte-policy-hash (uydurma-64hex) → RED rc7
# saldırgan-gerçek-bir-ES256-zarf-üretmeden-uydurma-hash-yazar; alıcı-
# verify_mandate_jws'ı-çağırınca-zarf-tutmayacak → evidenceHash-uyuşmazlığı.
chargeN1 = json.loads(json.dumps(charge))
chargeN1["delivery_hash"]["hex"] = "f" * 64
rN1 = SB.verify(chargeN1, claim)
assert rN1["verdict"] == "RED" and rN1["reason_code"] == 7, \
    f"sahte-policy-hash-RED-rc7-beklendi: {rN1}"
print("  sahte-policy-hash (uydurma-64hex) → RED rc7 — kanıtsız-ödeme-alınamaz")

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
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Sester-policy-signed-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-105: Sester-policy-signed (kalan-yüz) → RFC-010 x402/v1"
[[ $FAIL -eq 0 ]]

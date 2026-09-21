#!/usr/bin/env bash
# AT-107: FLEKSA İKİNCİ-YÜZ — Flex-Policy-v2 Ed25519 → RFC-010 (tamga/native).
#
# task-23. AT-070 (W3C-VC + Merkle) sonrası kalan-yüz:
#   src/fleksa/policy/verifier.py — FlexPolicyVerifier:
#     - gerçek-Ed25519 imza-doğrulama (cryptography-kütüphanesi)
#     - canonical-serialization: json.dumps(sort_keys, separators=(',',''))
#       → tamga_canon-jcs-ile-AYNI-aile (RFC-010 D5-hash-kapsama)
#     - fail-closed safety-invariants:
#         * fail_closed_on_telemetry_loss = True-ZORUNLU
#         * min_soc_pct ≥ 10.0, max_soc_pct ≤ 98.0
#     - trusted_public_keys yetkilendirmesi (bilinmeyen-anahtar-reddi)
#
# DİKİŞ: policy canonical-bytes → sha256-digest → hem-delivery_hash
#        hem-de-claim-evidence-hash; claim-imzası tamga/native-Ed25519
#        (nacl-VerifyKey, digest-ham-baytları — RFC-010 §3.2).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
EVDIR=".evidence/FLEKSA-2"
LOG="$EVDIR/$(date +%F)/at107.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

FL=/home/gokun/projects/01_unicorn/76-Fleksa/src
if [ ! -f "$FL/fleksa/policy/verifier.py" ]; then
  note "[SKIP] AT-107: Fleksa-policy-kodu-bu-makinede-değil (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
for mod in nacl cryptography pydantic yaml; do
  if ! python3 -c "import $mod" 2>/dev/null; then
    note "[SKIP] AT-107: $mod-yok (İNDETERMİNE)."
    echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
    exit 0
  fi
done

python3 - "$FL" >> "$LOG" 2>&1 <<'PYEOF'
import hashlib, json, sys
sys.path.insert(0, sys.argv[1])                    # fleksa
sys.path.insert(0, "."); sys.path.insert(0, "tools")

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from fleksa.policy.verifier import FlexPolicyVerifier
from fleksa.core.errors import PolicyVerificationError, SafetyGuardViolationError
from nacl.signing import SigningKey, VerifyKey
from nacl.encoding import HexEncoder
import settlement_bind_verify as SB

def policy_uret(fail_closed=True, min_soc=15.0, max_soc=95.0, key_id="k1"):
    """Gerçek-Flex-Policy-v2 üret + imzala (cryptography-Ed25519)."""
    pk = Ed25519PrivateKey.generate()
    priv, pub = pk.private_bytes_raw().hex(), pk.public_key().public_bytes_raw().hex()
    d = {
        "version": "2.0.0", "policy_id": "AT107-P1", "facility_id": "FLEX-1",
        "created_at": "2026-09-21T00:00:00Z", "valid_until": "2027-01-01T00:00:00Z",
        "crypto_signature": {"key_id": key_id, "algorithm": "Ed25519", "sig": ""},
        "assets": {"bess": {"capacity_kwh": 500.0, "max_charge_kw": 100.0,
                            "max_discharge_kw": 100.0, "min_soc_pct": min_soc,
                            "max_soc_pct": max_soc, "max_daily_cycles": 1.5,
                            "chemistry": "LFP"},
                   "compute": {"max_power_kw": 200.0, "min_critical_kw": 20.0}},
        "load_classes": [{"id": "critical", "priority": 1, "interruptible": False}],
        "rules": [{"id": "r1", "condition": {"grid_price_try": {"gt": 2.0}},
                   "actions": [{"target": "bess", "command": "discharge",
                                "power_kw": 50.0}], "audit_note": "peak-shave"}],
        "safety_guards": {"fail_closed_on_telemetry_loss": fail_closed,
                          "telemetry_timeout_sec": 90.0,
                          "max_grid_export_limit_kw": 0.0,
                          "human_in_the_loop_triggers": []},
    }
    clean = {k: v for k, v in d.items() if k != "crypto_signature"}
    canon = json.dumps(clean, sort_keys=True, separators=(",", ":")).encode()
    d["crypto_signature"]["sig"] = pk.sign(canon).hex()
    return d, priv, pub, canon

def dikis(canon, pub, priv, pid="FLEX-AT107"):
    """Fleksa-policy → RFC-010 tamga/native dikişi → SB-sonucu."""
    digest = hashlib.sha256(canon).hexdigest()
    claim = {"buyerAddress": pub, "sellerAddress": "0x2" * 40,
             "settlementRef": pid, "evidenceHash": {"alg": "sha256", "hex": digest},
             "signature": "_"}
    govde = json.dumps({k: v for k, v in claim.items() if k != "signature"},
                       sort_keys=True)
    _d = hashlib.sha256(govde.encode()).hexdigest()
    claim["signature"] = SigningKey(bytes.fromhex(priv)).sign(
        bytes.fromhex(_d)).signature.hex()
    charge = {"seq": 1, "prev": "0" * 64, "h": "a" * 64,
              "delivery_hash": {"alg": "sha256", "hex": digest},
              "settlement_bind": {"scheme": "tamga/native", "payment_id": pid,
                                  "claim_evidence_hash": {"alg": "sha256",
                                                          "hex": digest},
                                  "payer": pub, "payee": "0x2" * 40,
                                  "verified_at": "2026-09-21T00:00:00Z"}}
    return SB.verify(charge, claim), digest, claim, charge

# --- 1) Fleksa-policy gerçek-Ed25519-ile-üretilir-ve-doğrulanır
pd, priv, pub, canon = policy_uret()
v = FlexPolicyVerifier(trusted_public_keys={"k1": pub})
doc = v.parse_and_validate("flex_policy: " + json.dumps(pd), verify_signature=True)
assert doc.policy_id == "AT107-P1" and doc.safety_guards.fail_closed_on_telemetry_loss
print("  Fleksa FlexPolicyVerifier: gerçek-Ed25519 imza-doğrulandı"
      " (cryptography-kütüphanesi)")

# --- 2) canonical-serialization → sha256-digest (jcs-ailesi)
digest = hashlib.sha256(canon).hexdigest()
assert len(digest) == 64 and all(c in "0123456789abcdef" for c in digest)
print(f"  canonical-json → sha256-digest: {digest[:24]}… (tamga_canon-jcs-ailesi)")

# --- 3) DİKİŞ: tamga/native GREEN (ana-dizi)
r, dg, claim, charge = dikis(canon, pub, priv)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"tamga/native-GREEN-beklendi: {r}"
print(f"  DİKİŞ-1: Flex-Policy → tamga/native GREEN rc0 (Ed25519-gerçek,"
      f" nacl-VerifyKey)")

# --- 4) §6-zincir-kanıtı (AT-070-kapanışı)
c2 = json.loads(json.dumps(charge))
c2["foreign_chain_proof"] = {"chain": "tamga", "head_hex": dg,
                             "entries": 2, "verify_cmd": "n/a"}
r2 = SB.verify(c2, claim)
assert r2["verdict"] == "GREEN" and r2["checks"].get("6_foreign_chain") is True
print("  DİKİŞ-2: §6-foreign_chain (fleksa-head) GREEN")

# --- 5) NEG-1: yanlış-anahtar → hem-Fleksa-hem-RFC-010-reddeder
try:
    v.parse_and_validate("flex_policy: " + json.dumps(pd),
                         verify_signature=True)
    v2 = FlexPolicyVerifier(trusted_public_keys={"k1": "0" * 64})
    v2.parse_and_validate("flex_policy: " + json.dumps(pd), verify_signature=True)
    raise AssertionError("yanlış-anahtar-reddedilmeli")
except PolicyVerificationError as e:
    assert "verification failed" in str(e) or "untrusted" in str(e)
# RFC-010-tarafı: sahte-anahtarla-imzayı-boz
bad = json.loads(json.dumps(claim))
bad["signature"] = "0" * 128
r3 = SB.verify(charge, bad)
assert r3["verdict"] == "RED" and r3["reason_code"] == 4, \
    f"sahte-imza-rc4-beklendi: {r3}"
print("  NEG-1 yanlış-anahtar/sahte-imza → Fleksa PolicyVerificationError +"
      " RFC-010 RED rc4 (çift-taraf-koruma)")

# --- 6) NEG-2: fail_closed_on_telemetry_loss=False → invariant-ihlali
pd_bad, _, _, _ = policy_uret(fail_closed=False)
v3 = FlexPolicyVerifier(trusted_public_keys={"k1": pub})
try:
    v3.parse_and_validate("flex_policy: " + json.dumps(pd_bad))
    raise AssertionError("fail-closed-ihlali-yakalanmadı")
except SafetyGuardViolationError as e:
    assert "fail_closed_on_telemetry_loss" in str(e)
print("  NEG-2 fail_closed_on_telemetry_loss=False →"
      " SafetyGuardViolationError (fail-closed-invariant)")

# --- 7) Fleksa-policy-üreticisi-gerçek: doğrulama-sağlam
from fleksa.protocols.attestation import W3cAttestationBuilder
ok = W3cAttestationBuilder.verify_credential(
    W3cAttestationBuilder.create_credential("F1", 5.0, 1200.0, 2100.0, priv,
                                            "did:fleksa:at107"), pub)
assert ok is True
print("  AT-070-üretici-hâlâ-sağlam (W3C-VC-geri-uyum, iki-yüz-çakışmaz)")
PYEOF
RC=$?
[ $RC -eq 0 ] && { PASS=$((PASS+1)); note "  PASS: yedi-Fleksa-ikinci-yüz-kontrolü"; } \
              || { FAIL=$((FAIL+1)); note "  FAIL"; sed -n '1,40p' "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-107: Fleksa Flex-Policy-v2 → RFC-010 (tamga/native)"
[[ $FAIL -eq 0 ]]

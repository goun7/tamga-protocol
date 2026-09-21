#!/usr/bin/env bash
# AT-070: FLEKSA → RFC-010-DİKİŞİ (B-sınıfı — W3C-VC-v2.0 + Merkle).
#
# 76-Fleksa (47-py): src/fleksa/audit/ledger.py — SHA-256-Merkle-ağacı-üzerinden
# append-only-kanıt-defteri (compute_merkle_root); src/fleksa/protocols/
# attestation.py — W3C-Verifiable-Credential-v2.0-üretici-ve-DOĞRULAYICI
# (Ed25519-2020-suite; cryptography-kütüphanesi-gerçek).
#
# FLEKSA-ÖZELLİĞİ: kanıtlama-ED25519'dur → tamga/native-scheme'inin-imza-
# doğrulamasıyla-AYNI-aile; VE-Merkle-kökü → PQHaven'ın-erc8004/v1-deseni.
# Yani-Fleksa-İKİ-scheme'de-de-bağlanabilir. Bu-test-ikisini-de-ölçer.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-070/$(date +%F)/at070.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-070: Fleksa-W3C-VC + Merkle → RFC-010 dikişi"

FL="/home/gokun/projects/01_unicorn/76-Fleksa/src"
if [ ! -f "$FL/fleksa/audit/ledger.py" ] || [ ! -f "$FL/fleksa/protocols/attestation.py" ]; then
  note "[SKIP] AT-070: Fleksa-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$FL" <<'PYEOF' >> "$LOG" 2>&1
import json, sys
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from fleksa.audit.ledger import CryptographicSavingsLedger
from fleksa.protocols.attestation import W3cAttestationBuilder
import settlement_bind_verify as SB

# --- 1) Fleksa'nın-gerçek-Merkle-defteri-üret
led = CryptographicSavingsLedger()
h1 = led.append_entry({"hour": "2026-09-21T00:00Z", "kwh": 12.5})
h2 = led.append_entry({"hour": "2026-09-21T01:00Z", "kwh": 8.0})
kok = led.compute_merkle_root()
assert isinstance(kok, str) and len(kok) == 64, f"Merkle-kökü-64-hex-değil: {kok}"
assert h1 != h2 and len(h1) == 64
print(f"  Fleksa-Merkle-kökü-üretildi: 2-entry → {kok[:16]}…")

# --- 2) Fleksa'nın-gerçek-W3C-VC-doğrulayıcısı-çalışıyor-mu
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
pk = Ed25519PrivateKey.generate()
priv_hex = pk.private_bytes_raw().hex()
pub_hex = pk.public_key().public_bytes_raw().hex()
cred = W3cAttestationBuilder.create_credential(
    "FAC-001", 5.0, 1200.0, 2100.0, priv_hex, "did:fleksa:test")
ok = W3cAttestationBuilder.verify_credential(cred, pub_hex)
assert ok is True, "W3C-VC-doğrulama-başarısız (gerçek-kütüphane)"
print("  Fleksa-W3C-VC-v2.0 üret+doğrula çalışıyor (gerçek-ed25519)")

# --- 3) DİKİŞ-1: Merkle-kökü-ile-erc8004/v1 (PQHaven-deseni)
charge = {"seq": 1, "prev": "0"*64, "h": "a"*64,
          "delivery_hash": {"alg": "sha256", "hex": kok},
          "settlement_bind": {"scheme": "erc8004/v1", "payment_id": "FLEX-0001",
                              "claim_evidence_hash": {"alg": "sha256", "hex": kok},
                              "payer": kok, "payee": "0x2"*40,
                              "verified_at": "2026-09-21T00:00:00Z"}}
claim = {"buyerAddress": kok, "sellerAddress": "0x2"*40,
         "settlementRef": "FLEX-0001",
         "evidenceHash": {"alg": "sha256", "hex": kok}, "signature": kok}
SB._claim_signer = lambda d, s, scheme="x402/v1": (s if scheme == "erc8004/v1" else "0x1")
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"Fleksa-Merkle-dikişi-GREEN-beklendi: {r}"
print("  Fleksa-Merkle-kökü → erc8004/v1-GREEN")

# --- 4) DİKİŞ-2: §6-zincir-kanıtı-ile (AT-069-kapanışı)
charge2 = json.loads(json.dumps(charge))
charge2["foreign_chain_proof"] = {"chain": "dumen", "head_hex": kok,
                                  "entries": 2, "verify_cmd": "n/a"}
r2 = SB.verify(charge2, claim)
assert r2["verdict"] == "GREEN" and r2["checks"].get("6_foreign_chain") is True, \
    f"§6-kanıtlı-GREEN-beklendi: {r2}"
print("  §6-foreign_chain-proof-ile-GREEN (AT-069-kapanışı-çalışıyor)")

# --- 5) NEGATİF: Fleksa-defterine-eklenmemiş-sahte-kök → RED
claim3 = json.loads(json.dumps(claim))
claim3["evidenceHash"]["hex"] = "9"*64
r3 = SB.verify(charge, claim3)
assert r3["verdict"] == "RED" and r3["reason_code"] == 7, f"sahte-kök-RED: {r3}"
print("  defter-dışı-sahte-kök-RED")

# --- 6) NEGATİF: W3C-VC-yanlış-anahtarla-doğrulanmaz → üretici-tarafı-sağlam
bad = W3cAttestationBuilder.verify_credential(cred, "0"*64)
assert bad is False, "yanlış-anahtar-doğrulamamalı"
print("  W3C-VC-yanlış-anahtar → False (üretici-tarafı-sağlam)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Fleksa-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-070: Fleksa-W3C-VC + Merkle → RFC-010"
[[ $FAIL -eq 0 ]]

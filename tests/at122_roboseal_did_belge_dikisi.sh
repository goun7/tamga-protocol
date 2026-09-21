#!/usr/bin/env bash
# AT-122: ROBOSEAL-DÖRDÜNCÜ-YÜZ ( AgentID DID-belgesi + revocation) → RFC-010.
#
# 68-Kredent-roboseal: AT-074 ( çatışma), AT-083 ( çözüm-uzayı+verifier),
# AT-117 ( RFC-9421-çekirdek: crypto+canonical) yapıldı. KALAN-ÖLÇÜLMEMİŞ-YÜZ
# ( bu-test): models.py — DID-belge-modeli:
#   :11 AGENT_ID_REGEX ^did:agent:68:key:[a-zA-Z0-9_-]+$
#   :16 VerificationKey ( kid/type/public_key_multibase/purposes/expires_at/
#                         revoked) — Ed25519VerificationKey2020-credential
#   :47 AgentID ( DID-belge: agent_id/version/created_at/controller/keys/
#                capabilities/attestations)
#   :63 AgentID.get_key() — REVOKED-olmayan-ilk-anahtarı-döndürür (fail-closed)
# + schemas/agent-id.v1.json — JSON-Schema-Draft-2020-12 ( required-alanlar-
#   ile-model-birebir-uyumlu). DID-belgesi-multibase-pubkey'i-AT-117'in-crypto.py
#   -üretir — doğal-bütünleşme.
#
# LEAD'İN-ÖNERİSİ-GERÇEKLEŞTİ: stake/deposit-yoktu-AMA-credential/revocation-VAR —
# VerificationKey.revoked + get_key-fail-closed. Bu-credential- yüzü, DID-belgesinin
# imzalama-anahtarına-erişimini-denetler: revoked-bir-anahtarla-atılmış-imza-artık
# geçersiz-olur.
#
# Altı-kanıt + 2-negatif:
#   1) DID-belge-üretimi (gerçek-anahtar→multibase→VerificationKey→AgentID)
#   2) to_dict/from_dict/from_json-gidiş-dönüş-paritesi
#   3) revocation-yüzü: get_key() revoked → None (fail-closed); aktif → döner
#   4) AGENT_ID_REGEX + boş-keys-doğrulaması → ValueError
#   5) schemas/agent-id.v1.json-uyumu ( required-alanlar; jsonschema'dan-bağımsız)
#   6) RFC-010-tamga/native-GREEN ( DID-özütü=evidenceHash; §6-tamga-zinciri)
#   7) NEG-1: sahte-imza → RED rc4; NEG-2: evidenceHash-swap → RED rc7
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/ROBOSEAL-4/$(date +%F)/at122.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-122: ROBOSEAL AgentID DID-belgesi + revocation → RFC-010 tamga/native"

RK="/home/gokun/projects/01_unicorn/68-Kredent"
if [ ! -f "$RK/roboseal/models.py" ] || [ ! -f "$RK/roboseal/crypto.py" ]; then
  note "[SKIP] AT-122: ROBOSEAL-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import cryptography, nacl" 2>/dev/null; then
  note "[SKIP] AT-122: cryptography/PyNaCl-yok — gerçek-Ed25519-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$RK" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, sys
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from roboseal.crypto import generate_keypair, decode_multibase_pubkey
from roboseal.models import AgentID, VerificationKey, AGENT_ID_REGEX
from nacl.signing import SigningKey as NaClSigningKey
import settlement_bind_verify as SB

# --- 1) DID-BELGE-ÜRETİMİ (gerçek-anahtar → multibase → credential → DID)
priv, pub, MB = generate_keypair()
assert MB.startswith("z") and len(decode_multibase_pubkey(MB)) == 32
KID = "sig-122"
VK = VerificationKey(kid=KID, key_type="Ed25519VerificationKey2020",
                     public_key_multibase=MB,
                     purposes=["call-signing", "audit-verify"])
AID = AgentID(agent_id="did:agent:68:key:abc122", version="1.0.0",
              created_at="2026-09-22T00:00:00+00:00", controller="did:web:tamga.org",
              keys=[VK], capabilities=["mesh:settle"])
DID = AID.to_dict()
assert DID["agent_id"] == "did:agent:68:key:abc122"
assert DID["keys"][0]["public_key_multibase"] == MB
assert DID["keys"][0]["revoked"] is False
assert AGENT_ID_REGEX.match(DID["agent_id"]) is not None
print(f"  DID-belge-üretildi: {DID['agent_id']}, kid={KID}, "
      f"{len(DID['keys'])}-credential (Ed25519VerificationKey2020)")

# --- 2) GİDİŞ-DÖNÜŞ-PARİTESİ (DID-belge-serileştirme)
AID2 = AgentID.from_json(AID.to_json())
assert AID2.to_dict() == DID, "to_json→from_json→to_dict-bozuk"
AID3 = AgentID.from_dict(json.loads(json.dumps(DID)))
assert AID3.get_key() is not None and AID3.get_key().kid == KID
print("  serileştirme-paritesi: to_dict/from_dict/from_json-gidiş-dönüş-birebir")

# --- 3) REVOCATION-YÜZÜ (fail-closed)
assert AID.get_key() is not None and AID.get_key().kid == KID, "aktif-anahtar-dönmeli"
VK.revoked = True
assert AID.get_key() is None, "revoked-anahtar-döndürüldü (fail-closed-kırıldı)"
# kid-belirterek-de-revoked-atlanır
assert AID.get_key(kid=KID) is None, "revoked-anahtar-kid-ile-döndürüldü"
VK.revoked = False
assert AID.get_key(kid=KID) is not None, "aktif-dönünce-anahtar-dönmeli"
# ikinci-anahtar-revoked-iken-birincisi-aktif
VK2 = VerificationKey(kid="sig-122b", key_type="Ed25519VerificationKey2020",
                      public_key_multibase=MB, purposes=["audit-verify"])
VK2.revoked = True
AID4 = AgentID(agent_id="did:agent:68:key:abc122b", version="1.0.0",
               created_at="2026-09-22T00:00:00+00:00", controller="did:web:tamga.org",
               keys=[VK, VK2], capabilities=[])
assert AID4.get_key().kid == KID, "ilk-aktif-anahtar-dönmeli"
assert AID4.get_key(kid="sig-122b") is None, "revoked-ikinci-anahtar-dönmek"
print("  revocation-yüzü: revoked-credential → get_key=None (fail-closed); "
      "aktif-anahtar-seçilir")

# --- 4) AGENT_ID_REGEX + BOŞ-KEYS-DOĞRULAMASI
for kotu in ("did:agent:68:key:", "did:agent:99:key:abc", "did:agent:68:key:abc/bozuk",
             "agent:68:key:abc"):
    try:
        AgentID(agent_id=kotu, version="1.0.0", created_at="2026-09-22T00:00:00+00:00",
                controller="did:web:tamga.org", keys=[VK], capabilities=[])
        raise AssertionError(f"geçersiz-DID-kabul-edildi: {kotu!r}")
    except ValueError:
        pass
try:
    AgentID(agent_id="did:agent:68:key:gecerli", version="1.0.0",
            created_at="2026-09-22T00:00:00+00:00", controller="did:web:tamga.org",
            keys=[], capabilities=[])
    raise AssertionError("boş-keys-kabul-edildi")
except ValueError:
    pass
print("  doğrulama: geçersiz-DID-formatı (4-varyasyon) + boş-keys → ValueError")

# --- 5) SCHEMAS/AGENT-ID.V1.JSON-UYGUMLUĞU (jsonschema'dan-bağımsız, elle)
SCHEMA_PATH = sys.argv[1] + "/schemas/agent-id.v1.json"
SCHEMA = json.load(open(SCHEMA_PATH, encoding="utf-8"))
for req in SCHEMA["required"]:
    assert req in DID, f"schema-required-alan-eksik: {req}"
KEY_SCH = SCHEMA["properties"]["keys"]["items"]
for req in KEY_SCH["required"]:
    assert req in DID["keys"][0], f"credential-required-eksik: {req}"
assert KEY_SCH["properties"]["type"]["enum"] == ["Ed25519VerificationKey2020"]
assert set(DID["keys"][0]["purposes"]) <= {"call-signing", "commitment-assertion",
                                           "escrow-authorization", "audit-verify"}
assert SCHEMA["properties"]["agent_id"]["pattern"] == "^did:agent:68:key:[a-zA-Z0-9_-]+$"
print(f"  schema-uyumu: agent-id.v1.json-required-alanların-tamamı-mevar "
      f"({len(SCHEMA['required'])}-belge + {len(KEY_SCH['required'])}-credential)")

# --- 6) RFC-010-TAMGA/NATIVE-GREEN (DID-özütü=evidenceHash; AT-117-anahtarıyla)
DID_OZUT = hashlib.sha256(AID.to_json().encode()).hexdigest()
PUB_HEX = decode_multibase_pubkey(MB).hex()
nacl_sk = NaClSigningKey(priv.private_bytes_raw())
govde = {"buyerAddress": PUB_HEX, "sellerAddress": "0x2" * 40,
         "settlementRef": "ROB-DID-122",
         "evidenceHash": {"alg": "sha256", "hex": DID_OZUT}}
d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
sig_hex = nacl_sk.sign(bytes.fromhex(d)).signature.hex()
assert len(sig_hex) == 128
claim = dict(govde); claim["signature"] = sig_hex
charge = {"seq": 22, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": DID_OZUT},
          "settlement_bind": {"scheme": "tamga/native", "payment_id": "ROB-DID-122",
                              "claim_evidence_hash": {"alg": "sha256", "hex": d},
                              "payer": PUB_HEX, "payee": "0x2" * 40,
                              "verified_at": "2026-09-22T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": DID_OZUT, "entries": 1,
                                  "verify_cmd": "roboseal.models.AgentID.to_json"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"DID-dikişi-GREEN-beklendi: {r}"
assert r["checks"].get("2_claim_sig") is True, "stock-Ed25519-doğrulaması-geçmedi"
assert r["checks"].get("6_foreign_chain") is True, "§6-tamga-zinciri-geçmedi"
print(f"  DID-belge-özütü → RFC-010-tamga/native-GREEN (§6-tamga-zinciri, "
      f"DID={DID_OZUT[:20]}…)")

# --- 7) NEG-1: sahte-imza → RED rc4
for sahte in ("ff" * 64, "00" * 64):
    cs = dict(govde); cs["signature"] = sahte
    rs = SB.verify(charge, cs)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"sahte-imza-RED-rc4-beklendi: {rs}"
print("  sahte-imza (128-hex-sıfır/ff) → RED rc4 (fail-closed)")

# --- 8) NEG-2: evidenceHash-swap (aynı-gerçek-anahtarla-yeni-imzalı) → RED rc7
govde2 = dict(govde)
govde2["evidenceHash"] = {"alg": "sha256", "hex": "9" * 64}
d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
c2 = dict(govde2); c2["signature"] = nacl_sk.sign(bytes.fromhex(d2)).signature.hex()
r2 = SB.verify(charge, c2)
assert r2["verdict"] == "RED" and r2["reason_code"] == 7, \
    f"evidenceHash-swap-RED-rc7-beklendi: {r2}"
print("  evidenceHash-swap (yeni-gerçek-imzalı) → RED rc7 (fail-closed)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: sekiz-ROBOSEAL-DID-belge-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-122: ROBOSEAL AgentID DID-belgesi + revocation → RFC-010"
[[ $FAIL -eq 0 ]]

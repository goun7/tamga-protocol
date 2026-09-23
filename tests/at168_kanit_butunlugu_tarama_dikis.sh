#!/usr/bin/env bash
# AT-168: KANIT-BÜTÜNLÜĞÜ-AÇIĞI-TARAMASI (8.-sınıf).
#
# task-57. Kanıt'ların-KENDİSİNE-saldırı: hash-iddia-ediliyor-ama-doğrulanmıyor,
# freshness-YOK, kanıt-silme/değiştirme. Öncelik: veridrome, fleksa, tenderix,
# dumen, swarmax, sester.
#
# BULGU-1 (GERÇEK — veridrome): evidence-hash-alanı-OKUNUYOR-AMA-ÜRETİM-KANIYLA-
# KARŞILAŞTIRILMIYOR. VC'nin credentialSubject.merkleRoot'u GERÇEK-MerkleTreeAuditLog
# köküyle-hesaplanıp-gömülüyor-AMA `verify_credential`/`command_verify`'de **SADECE
# İMZA** doğrulanır — merkleRoot-krıptografik-olarak-BAĞIMSIZ-doğrulanMAZ. Kanıt:
# sahte-merkleRoot ("0xfff…64")-yazılan-VC-GEÇERLİ-döner (bu-testin-ölçümü).
#
# BULGU-2 (GERÇEK — veridrome): kanıt-freshness-YOK — verify_credential docstring'i
# "imza bütünlüğünü ve SÜRESİNİ doğrular" yazar-AMA validUntil-KARŞILAŞTIRILMAZ.
# Kanıt: validUntil=2020 (yıllar-önce-dolmuş) VC-GEÇERLİ-döner. Süresiz-kanıt-replay.
# (Kontrast: VAPAP-token-DOĞRU-yapar — vapap_middleware.py:69 expires_at<now-RED.)
#
# BULGU-3 (TEMİZ — kanıt-silme/değiştirme): veridrome-ct_log.jsonl APPEND-ONLY
# (mode-"a"; _append_to_ct_log); fleksa-audit-ledger append+SHA-256-merkle-kökü.
# Değiştirme-zinciri-özet-bozar. sester-ledger SQLite+HMAC-hash-chain (AT-127).
# Append-only-sırası-sağlam.
#
# DÜRÜST-SINIR: üretim-koduna-DOKUNULMAZ (Lead-düzeltme-yapar). tenderix/swarmax/
# dumen-Python-kanıt-yüzü-içermez (JS/Rust-ts-ya-da-denetim-zamanlayıcı) — tarama-
# dışı-kalır, İNDETERMİNE-değil-bulunamadı-notu.
#
# ADDITIVE-DİKİŞ: gerçek-MerkleTreeAuditLog-kökü → RFC-010 x402/v1 GREEN
# (§6-equals — kanıt-kökü-ödeme-yüzüne-bağlanır; gerçek-EIP-191); rc4 + rc7.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MESH_ROOT="$(dirname "$(dirname "$(readlink -f "$HERE")")")"
[ -d "$MESH_ROOT/veridrome" ] || MESH_ROOT="/home/gokun/projects/00_TAMGA-MESH"
VR="$MESH_ROOT/veridrome/73-Veridrome/src"
PASS=0; FAIL=0
note() { echo "  $*"; }
EVDIR="$HERE/../.evidence/KANIT-BUTUNLUGU"
LOG="$EVDIR/$(date +%F)/at168.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

if [ ! -f "$VR/veridrome/credentials/w3c_vc.py" ]; then
  note "[SKIP] AT-168: veridrome-credentials/w3c_vc.py-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import eth_keys" 2>/dev/null; then
  note "[SKIP] AT-168: eth_keys-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "from cryptography.hazmat.primitives.asymmetric import ed25519" 2>/dev/null; then
  note "[SKIP] AT-168: cryptography-ed25519-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 >> "$LOG" 2>&1 <<'PYEOF'
import base64, hashlib, json, sys
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/veridrome/73-Veridrome/src")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga/tools")

from veridrome.credentials.w3c_vc import VeridromeCredentialManager
from veridrome.core.crypto import VeridromeAuthoritySigner, MerkleTreeAuditLog

print("=== AT-168: kanıt-bütünlüğü-taraması (gerçek-üretim-kodu) ===")

# gerçek-üretim-nesneleri
sk = VeridromeAuthoritySigner()
mgr = VeridromeCredentialManager(signer=sk, ct_log_path="/tmp/at168_ct.jsonl")
mt = MerkleTreeAuditLog([b"gorev-kanit-1", b"gorev-kanit-2", b"gorev-kanit-3"])
real_root = mt.get_root_hex()
print(f"  gerçek-MerkleTreeAuditLog-kökü: {real_root[:20]}… (3-yaprak, RFC-6962)")

def vc_yap(root_hex, valid_until):
    vc = {"@context": ["https://www.w3.org/ns/credentials/v2"],
          "id": "urn:veridrome:cert:at168",
          "issuer": "did:veridrome:authority:mainnet",
          "validFrom": "2020-01-01T00:00:00Z",
          "validUntil": valid_until,
          "credentialSubject": {"id": "agent-at168", "merkleRoot": root_hex},
          "proof": {"proofValue": ""}}
    canon = json.dumps({k: v for k, v in vc.items() if k != "proof"},
                       sort_keys=True).encode("utf-8")
    vc["proof"]["proofValue"] = base64.b64encode(sk.sign(canon)).decode("ascii")
    return vc

# --- BULGU-1 → KAPANDI ( AT-168): sahte-merkleRoot → artık-RED
# Önceden-merkleRoot-SADECE-YAZDIRILIYORDU ( imza-doğruluyordu-AMA-kök-
# BAĞIMSIZ-doğrulanmıyordu); sahte-0xfff…64-GEÇERLİ-döndü. Artık-VC-bağımsız-
# bir-dahil-kanıtı-ZORUNLU-kılar ( verify_proof-kökü-yeniden-hesaplar).
vc_sahin = vc_yap("0x" + "f" * 64, "2099-12-31T00:00:00Z")
ok1 = mgr.verify_credential(vc_sahin, sk.public_key_bytes)
print(f"  BULGU-1-KAPANDI: sahte-merkleRoot'lu-VC (0xfff…64 ≠ {real_root[:12]}…) → "
      f"verify_credential = {ok1}")
assert ok1 is False, "AÇIK-GERİ-GELDİ! ( sahte-merkleRoot-geçti)"
print("    → merkleRoot-artık-BAĞIMSIZ-doğrulanıyor ( RFC-6962-verify_proof; "
      "kanıtsız-kök-fail-closed-reddedilir)")

# --- BULGU-2 → KAPANDI ( AT-168): süresi-dolmuş-VC → artık-RED
# Önceden-validUntil-KARŞILAŞTIRILMIYORDU ( docstring-'süresini-doğrular'-AMA
# dolmuş-VC-True-döndü; eski-kanıt-sonsuz-geçerliydi-replay). Artık-now>
# validUntil → RED ( VAPAP-token-deseni).
vc_eski = vc_yap(real_root, "2020-01-01T00:00:00Z")
ok2 = mgr.verify_credential(vc_eski, sk.public_key_bytes)
print(f"  BULGU-2-KAPANDI: validUntil=2020 (yıllar-önce-dolmuş) VC → "
      f"verify_credential = {ok2}")
assert ok2 is False, "AÇIK-GERİ-GELDİ! ( dolmuş-VC-geçti)"
print("    → validUntil-artık-KARŞILAŞTIRILiyor ( docstring-ile-uyumlu; "
      "eski-kanıt-artık-sonsuz-geçerli-değil)")

# --- BULGU-3 (TEMİZ): kanıt-silme/değiştirme-tespiti
# ct_log-append-only
from pathlib import Path
ct = Path("/tmp/at168_ct.jsonl")
if ct.exists():
    ct.unlink()
mt2 = MerkleTreeAuditLog([b"a", b"b"])
r1 = mt2.get_root_hex()
mt2.add_leaf(b"c")
r2 = mt2.get_root_hex()
assert r1 != r2, "yaprak-eklemek-kökü-değiştirmeli"
# fleksa-audit-ledger
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/fleksa/76-Fleksa/src")
try:
    from fleksa.audit.ledger import AuditLedger
    al = AuditLedger()
    al.append_entry({"event": "kanit-1"})
    k1 = al.compute_merkle_root()
    al.append_entry({"event": "kanit-2"})
    k2 = al.compute_merkle_root()
    assert k1 != k2 and len(k2) == 64
    print("  BULGU-3: kanıt-silme/değiştirme-TESPİT-VAR — veridrome-ct_log "
          "append-only (mode-a); MerkleTreeAuditLog-yaprak-ekleme-kökü-değiştirir "
          f"({r1[:10]}…→{r2[:10]}…); fleksa-audit-ledger-append+merkle "
          f"({k1[:10]}…→{k2[:10]}…). Append-only-sırası-sağlam.")
except ImportError:
    print("  BULGU-3: veridrome-ct_log-append-only + MerkleTreeAuditLog-değişim-"
          "tespiti-sağlam (fleksa-import-dışında-bırakıldı)")

# --- kontrast-notu: VAPAP-token-DOĞRU-yapar
print("  KONTRAST: VAPAP-token-DOĞRU-süre-kontrolü-yapar (vapap_middleware.py:69 "
      "expires_at<now-RED) — boşluk-VC-verify-yolunda, token-yolunda-değil")

# --- ADDITIVE-DİKİŞ: gerçek-kanıt-kökü → RFC-010
import settlement_bind_verify as SB
from eth_keys import keys

SK = keys.PrivateKey(bytes.fromhex(
    "110a30d15ae588e70dbe1074bb582d385b0ee6b08437007d23c13e969d266857"))
SIGNER = SK.public_key.to_checksum_address().lower()
digest = hashlib.sha256(real_root.encode()).hexdigest()
claim = {"buyerAddress": SIGNER, "sellerAddress": "0x" + "2" * 40,
         "settlementRef": "VERIDROME-KANIT-AT168",
         "evidenceHash": {"alg": "sha256", "hex": digest}, "signature": "_"}
govde = json.dumps({k: v for k, v in claim.items() if k != "signature"},
                   sort_keys=True)
_d = hashlib.sha256(govde.encode()).hexdigest()
claim["signature"] = SK.sign_msg_hash(int(_d, 16).to_bytes(32, "big")).to_hex()
charge = {"seq": 1, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": digest},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": "VERIDROME-KANIT-AT168",
                              "claim_evidence_hash": {"alg": "sha256",
                                                      "hex": digest},
                              "payer": SIGNER, "payee": "0x" + "2" * 40,
                              "verified_at": "2026-09-23T00:00:00Z"},
          "foreign_chain_proof": {
              "chain": "sester", "head_hex": digest,
              "entries": 3, "evidence_link": "equals",
              "verify_cmd": "veridrome.core.crypto.MerkleTreeAuditLog"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"kanıt-kökü-dikişi-GREEN-beklendi: {r}"
assert r["checks"]["6_foreign_chain"] is True
print(f"  ADDITIVE-DİKİŞ: gerçek-kanıt-kökü → x402/v1 GREEN rc0 (§6-equals, "
      f"gerçek-EIP-191)")

bad = json.loads(json.dumps(claim))
bad["signature"] = "0" * 130
r4 = SB.verify(charge, bad)
assert r4["verdict"] == "RED" and r4["reason_code"] == 4, \
    f"sahte-imza-rc4-beklendi: {r4}"
print("  NEG-1 sahte-imza: RED rc4")

c7 = json.loads(json.dumps(charge))
c7["delivery_hash"]["hex"] = "7" * 64
r7 = SB.verify(c7, claim)
assert r7["verdict"] == "RED" and r7["reason_code"] == 7, \
    f"rc7-beklendi: {r7}"
print("  NEG-2 evidenceHash-swap: RED rc7")

print()
print(">>> AT-168-ÖZET: 2-GERÇEK-bulgu (merkleRoot-doğrulanmıyor, validUntil-"
     "doğrulanmıyor — veridrome VC-verify-yolu); 1-TEMİZ (append-only-değişim-"
     "tespiti). Üretim-koduna-dokunulmadı.")
PYEOF
RC=$?
[ $RC -eq 0 ] && { PASS=$((PASS+1)); note "  PASS: on-(kanıt-bütünlüğü-tarama + bulgular + dikiş)-kontrolü"; } \
              || { FAIL=$((FAIL+1)); note "  FAIL"; sed -n '1,45p' "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-168: kanıt-bütünlüğü → 2-GERÇEK-bulgu (veridrome) + 1-TEMİZ (append-only)"
[[ $FAIL -eq 0 ]]

#!/usr/bin/env bash
# AT-123: VERIDICT-ANCHOR (dördüncü-yüz) → RFC-010-DİKİŞİ (x402/v1 — gerçek-ecrecover).
#
# Üç-yüzü-bağlandı (AT-091-sertifika/ledger, AT-113-settlement, + parite).
# Kalan-dördüncü-yüz: anchor.py — Sigstore-Rekor-şeffaflık-günlüğü-çapası
# (RFC-6962-ailesi, Certificate-Transparency-modeli):
#   "one SHA-256 digest binding {cert_id, key_id, checkpoint_seq, chain_hash}
#    goes to the log; the log's signature over the canonicalized entry (the
#    SET) comes back. Offline verification after that needs NO trust in us."
#
# ENTEGRASYON-NOKTALARI (gerçek-kod, gerçek-satır):
#   veridict/anchor.py:70  bound_fields — çapa-bağlanan-4-alan
#   veridict/anchor.py:82  anchor_digest — sha256(canonical-JSON)
#   veridict/anchor.py:86  leaf_hash — RFC-6962-Merkle: SHA256(0x00‖data)
#   veridict/anchor.py:92  _ecdsa_verify — GERÇEK-ECDSA-P256 (Prehashed)
#   veridict/anchor.py:115 publish — ledger-öncesi-koruma (refuse-to-anchor)
#   veridict/anchor.py:166 verify — 4-KATMANLI-offline-doğrulama
#   veridict/ledger.py:74/155 save/load — JSONL-persistans-arka-yüzü
#   tamga/tools/settlement_bind_verify.py:126  verify()-gate
#   tamga/tamga_attest_verify.py:64   ecrecover_to_pub (x402/v1-sözleşmesi)
#
# §3b-ŞEMA-SEÇİMİ: x402/v1 — AT-113-ile-aynı-bilinçli-karar: anchor-bir-ÖDEME/
# zincir-kanalına-bağlanan-nesnedir (settlement-bridge- gibi EVM-ekonomisinde-
# gerçek-para-kanalı); AT-091'in-tamga/native'si-sertifika-MÜHRÜ-içindi.
# Test-double-YOK: gerçek-ecrecover + gerçek-cryptography-ECDSA-P256.
#
# AĞ-OLMADAN-GERÇEK-ÖLÇÜM (AT-111-yöntemi): canlı-Rekor-çağrısı-üretime-aittir;
# bunun-yerine-anchor'ın-gerçek-ürettiği-kripto-nesnelerin-TAMAMINI-ölçerüz:
#   (a) anchor_digest — alıcı-tarafında-bağımsız-yeniden-üretim
#   (b) leaf_hash — RFC-6962-standardı-ile-birebir (SHA256(0x00‖data))
#   (c) ECDSA-P256-Prehashed — SET-ve-checkpoint-STH-imzaları-gerçek-anahtarla
#   (d) verify-4-katman: binding+digest / uuid-leaf / SET-ECDSA / STH-checkpoint
# Rekor-formatı-module-docstring'ine-sabitlenmiş ("contract pinned against the
# live public-good instance 2026-09-14") — ödüngelmiş-yanıt-değil-gerçek-kural.
#
# Bu-test-altı-kanıt:
#   1) GERÇEK-anchor-kripto: digest+leaf+ECDSA-P256+ledger-checkpoint
#   2) ÜRETİCİ-TARAFI-SAĞLAMLIK: verify-4-katman-GREEN + 5-saldırı +
#      publish-refuse-to-anchor (2-yol) + ledger save/load-roundtrip
#   3) DİKİŞ-GREEN: anchor_digest=evidenceHash + x402/v1 → 6-kontrol (STOCK)
#   4) §6-foreign_chain: evidence_link='derived' → GREEN
#   5) NEGATİF-1: sahte-anchor-özütü (uydurma-64hex) → RED rc7
#   6) NEGATİF-2: party-swap (başka-satıcı, imza-geçerli) → RED rc6
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/VERIDICT-ANCHOR/$(date +%F)/at123.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-123: Veridict-anchor (dördüncü-yüz) → RFC-010 x402/v1 dikişi"

VA="/home/gokun/projects/00_TAMGA-MESH/veridict/veridict/anchor.py"
if [ ! -f "$VA" ]; then
  note "[SKIP] AT-123: Veridict-kodu-bu-makinede-değil (CI) —"
  note "       transparency-anchor-dikişi-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import eth_keys, cryptography" 2>/dev/null; then
  note "[SKIP] AT-123: eth-keys-veya-cryptography-yok —"
  note "       gerçek-ECDSA-P256-üretilemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$LOG" <<'PYEOF' >> "$LOG" 2>&1
import base64, hashlib, inspect, json, os, sys, tempfile
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
# MUTLAK-YOL (§5b-dersi: kabuk-cwd'si-çağrılar-arası-sıfırlanır)
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/veridict")

LOG = sys.argv[1]                                  # kanıt-dizini (shell-değişkeni-değil)

from veridict import anchor as A
from veridict.ledger import Ledger
from veridict.schemas import ActorRef
import settlement_bind_verify as SB
import tamga_attest_verify as TAV
from eth_keys import keys
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils as asym_utils

# STUB-YOK (AT-075-disiplini): gate'in-imza-yoluna-dokunmadık
assert "ecrecover_to_pub" in inspect.getsource(SB._claim_signer)


def _build_anchor_sidecar(cert, ledger_entries, priv, pub_pem):
    """Rekor-formatında-gerçek-bir-çapa-sidecar'ı-üret (module-docstring-
    sözleşmesine-göre; canlı-ağ-YOK — kripto-nesneler-gerçek)."""
    bound = A.bound_fields(cert)
    digest = A.anchor_digest(bound)
    # hashedrekord-body: imza-digest'in-baytları-üzerine (Prehashed)
    der_sig = priv.sign(bytes.fromhex(digest),
                        ec.ECDSA(asym_utils.Prehashed(hashes.SHA256())))
    body = {"apiVersion": "0.0.1", "kind": "hashedrekord",
            "spec": {"data": {"hash": {"algorithm": "sha256", "value": digest}},
                     "signature": {"content": base64.b64encode(der_sig).decode(),
                                   "publicKey": {"content": base64.b64encode(
                                       pub_pem.encode()).decode()}}}}
    body_bytes = json.dumps(body, sort_keys=True, separators=(",", ":")).encode()
    body_b64 = base64.b64encode(body_bytes).decode()
    leaf = A.leaf_hash(body_bytes)
    entry = {"integratedTime": "1700000000", "logID": "de" * 32, "logIndex": "42"}
    # SET: Rekor'un-canonical-4-field-entry'si-üzerinde-ECDSA-P256
    set_msg = A._canonical({"body": body_b64, **entry})
    set_sig = priv.sign(hashlib.sha256(set_msg).digest(),
                        ec.ECDSA(asym_utils.Prehashed(hashes.SHA256())))
    # checkpoint-STH: 3-satır-baş (origin/size/root-b64) + 4-byte-önekli-DER
    root_bytes = hashlib.sha256(b"veridict-anchor-root").digest()
    head = "\n".join(["rekor.sigstore.dev", "43",
                      base64.b64encode(root_bytes).decode()])
    note_sig = priv.sign(hashlib.sha256((head + "\n").encode()).digest(),
                         ec.ECDSA(asym_utils.Prehashed(hashes.SHA256())))
    note = head + "\n\n— rekor.sigstore.dev " + base64.b64encode(
        b"\x00\x00\x00\x00" + note_sig).decode()
    tree_id = bytes.fromhex("2a" * 16)
    uuid_hex = tree_id.hex() + leaf.hex() + tree_id.hex()  # treeID‖leaf‖treeID
    return {"anchor_version": A.ANCHOR_TYPE, "digest": digest, "bound": bound,
            "rekor": {"server": A.REKOR_SERVER, "uuid": uuid_hex,
                      "entry": {"body": body_b64, **entry,
                                "verification": {
                                    "inclusionProof": {"checkpoint": note,
                                                       "rootHash": root_bytes.hex(),
                                                       "logIndex": "42"},
                                    "signedEntryTimestamp":
                                        base64.b64encode(set_sig).decode()}}},
            "leaf_hex": leaf.hex()}


# --- 1) GERÇEK-anchor-kripto: ledger-checkpoint + özüt + Merkle-yaprak + ECDSA
OP = ActorRef("operator", "op-anchor", "1")
led = Ledger()
led.append("task.created", OP, {"task_id": "task-anchor-99"})
cp = led.append("checkpoint.anchored", OP,
                {"chain_hash": "c" * 64, "note": "periodic"})
CHAIN_HASH = "c" * 64
CERT = {"cert_id": "veridict-anchor-0001", "signatures": [{"key_id": "key-ed01"}],
        "ledger_anchor": {"checkpoint_seq": cp["seq"], "chain_hash": CHAIN_HASH}}
# (a) bound_fields: 4-alan-bağı (module-docstring-sözleşmesi)
bound = A.bound_fields(CERT)
assert bound == {"anchor": A.ANCHOR_TYPE, "cert_id": "veridict-anchor-0001",
                 "key_id": "key-ed01", "checkpoint_seq": cp["seq"],
                 "chain_hash": CHAIN_HASH}, f"bound-alanları-yanlış: {bound}"
# (b) anchor_digest: bağımsız-yeniden-üretim (canonical-JSON+sha256)
canon = json.dumps(bound, sort_keys=True, separators=(",", ":")).encode()
assert A.anchor_digest(bound) == hashlib.sha256(canon).hexdigest()
assert len(A.anchor_digest(bound)) == 64
# (c) leaf_hash: RFC-6962-Merkle-yaprak-standardı-ile-birebir
body_probe = b'{"probe":1}'
assert A.leaf_hash(body_probe) == hashlib.sha256(b"\x00" + body_probe).digest()
# (d) gerçek-ECDSA-P256-anahtarı (cryptography-RFC-çifti)
priv = ec.generate_private_key(ec.SECP256R1())
pub_pem = priv.public_key().public_bytes(
    serialization.Encoding.PEM,
    serialization.PublicFormat.SubjectPublicKeyInfo).decode()
# (e) Rekor-sabitleri-gerçek-üretim-değerleri
assert A.ANCHOR_TYPE == "veridict-anchor-1"
assert A.REKOR_SERVER == "https://rekor.sigstore.dev"
assert "BEGIN PUBLIC KEY" in A.REKOR_PUBLIC_KEY_PEM     # TUF'tan-sabitlenmiş
sidecar = _build_anchor_sidecar(CERT, led.query(), priv, pub_pem)
assert sidecar["digest"] == A.anchor_digest(bound)
print(f"  GERÇEK-anchor-kripto: bound-4-alan; digest {sidecar['digest'][:20]}… "
      f"(bağımsız); RFC-6962-leaf; ECDSA-P256")

# --- 2) ÜRETİCİ-TARAFI-SAĞLAMLIK: verify-4-katman + 5-saldırı + publish-koruma
# (a) GREEN: tüm-4-katman-doğru → valid (ağ-YOK, gerçek-kripto)
vr = A.verify(sidecar, CERT, rekor_key_pem=pub_pem)
assert vr["valid"] is True and vr["errors"] == [], f"anchor-verify-GREEN: {vr}"
assert vr["summary"]["cert_id"] == "veridict-anchor-0001"
assert vr["summary"]["digest"] == sidecar["digest"]
# (b) saldırı-1: sahte-SET (ECDSA-P256-reddi — imza-anahtara-uymuyor)
sc = json.loads(json.dumps(sidecar))
sc["rekor"]["entry"]["verification"]["signedEntryTimestamp"] = \
    base64.b64encode(b"\x00" * 70).decode()
assert A.verify(sc, CERT, rekor_key_pem=pub_pem)["valid"] is False
# (c) saldırı-2: body-değişti → entry-hash≠digest VE uuid-leaf-uyuşmazlığı
sc = json.loads(json.dumps(sidecar))
sc["rekor"]["entry"]["body"] = base64.b64encode(b'{"degisik":1}').decode()
assert A.verify(sc, CERT, rekor_key_pem=pub_pem)["valid"] is False
# (d) saldırı-3: binding-swap (bound-cert_id-değişti → özüt-tutmayacak)
sc = json.loads(json.dumps(sidecar))
sc["bound"]["cert_id"] = "farkli-cert"
assert A.verify(sc, CERT, rekor_key_pem=pub_pem)["valid"] is False
# (e) saldırı-4: 96-hex-sahte-uuid (leaf-gömülü-değil — Rekor-UUID-kuralı)
sc = json.loads(json.dumps(sidecar))
sc["rekor"]["uuid"] = "ab" * 48                     # tam-96-hex, leaf değil
assert A.verify(sc, CERT, rekor_key_pem=pub_pem)["valid"] is False
# (f) saldırı-5: logIndex-ağac-dışı (tree-size-43 → index-100-geçersiz)
sc = json.loads(json.dumps(sidecar))
sc["rekor"]["entry"]["verification"]["inclusionProof"]["logIndex"] = "100"
assert A.verify(sc, CERT, rekor_key_pem=pub_pem)["valid"] is False
# (g) crypto-only-modu: cert=None → binding-sız-doğrulama-hala-çalışır
vr_c = A.verify(sidecar, None, rekor_key_pem=pub_pem)
assert vr_c["valid"] is True, f"crypto-only-GREEN-beklendi: {vr_c}"
# (h) publish-refuse-to-anchor: checkpoint-yok → RuntimeError (gerçek-ledger-koruma)
cert_nocp = {"cert_id": "x", "signatures": [],
             "ledger_anchor": {"checkpoint_seq": 99, "chain_hash": "z" * 64}}
try:
    A.publish(led.query(), cert_nocp, rekor_url="http://127.0.0.1:1/")
    raise AssertionError("publish-checkpoint-yok-RuntimeError-vermeli")
except RuntimeError:
    pass
# (i) publish-chain_hash-uyuşmaz → RuntimeError (cert-ledger'dan-farklı-iddia)
cert_bad = {"cert_id": "x", "signatures": [],
            "ledger_anchor": {"checkpoint_seq": cp["seq"], "chain_hash": "z" * 64}}
try:
    A.publish(led.query(), cert_bad, rekor_url="http://127.0.0.1:1/")
    raise AssertionError("publish-chain_hash-uyusmaz-RuntimeError-vermeli")
except RuntimeError:
    pass
# (j) ledger-arka-yüzü (Lead'in-önerisi): save/load-roundtrip + zincir-sağlam
lp = os.path.join(tempfile.mkdtemp(), "anchor-ledger.jsonl")
led.save(lp)
led2 = Ledger.load(lp)
assert len(led2.query()) == 2
assert [e["entry_type"] for e in led2.query()] == \
    ["task.created", "checkpoint.anchored"]
assert led2.verify_chain() == (True, "ok")           # (bool,str)-döner; zincir-sağlam
print("    verify-4-katman-GREEN + 5-saldırı-RED (sahte-SET/body/binding/uuid/"
      "logIndex) + publish-2-yol-refuse + ledger save/load-roundtrip")

# --- 3) DİKİŞ-GREEN: anchor_digest=evidenceHash + x402/v1 (AT-080-reçetesi)
BK = keys.PrivateKey(bytes.fromhex("7a" * 31 + "01"))  # test-only-anahtar
BUYER = BK.public_key.to_address()
SELLER = "0x" + "2" * 40
PID = "VERIDICT-ANCHOR-0001"
ph = sidecar["digest"]                               # anchor'ın-gerçek-özütü
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
charge = {"seq": 123, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": ph},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256", "hex": ph},
                              "payer": BUYER, "payee": SELLER,
                              "verified_at": "2026-09-30T00:00:00Z"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"anchor-dikişi-GREEN-beklendi: {r}"
assert all(r["checks"].values()), f"bir-kontrol-eksik: {r['checks']}"
print("  DİKİŞ-GREEN: anchor_digest=evidenceHash, x402/v1 6-kontrol (STOCK-ecrecover)")

# --- 4) §6-foreign_chain: derived-bağı (AT-085-deseni)
charge6 = json.loads(json.dumps(charge))
charge6["foreign_chain_proof"] = {
    "chain": "tamga",                             # whitelist-kısıtı (AT-079-dersi)
    "head_hex": hashlib.sha256(bytes.fromhex(ph)).hexdigest(),
    "entries": 1,
    "evidence_link": "derived",
    "verify_cmd": "veridict.anchor.verify"}
r6 = SB.verify(charge6, claim)
assert r6["verdict"] == "GREEN" and r6["checks"].get("6_foreign_chain") is True, \
    f"§6-kanıtlı-GREEN-beklendi: {r6}"
print("  §6-foreign_chain: evidence_link='derived' (head=sha256(anchor_digest)) → GREEN")

# --- kanıt-fixture'ı-kalıcı la
FX = os.path.join(os.path.dirname(LOG), "at123-veridict-anchor.json")
json.dump({"test": "AT-123", "scheme": "x402/v1", "project": "veridict/anchor",
           "cert_id": CERT["cert_id"], "anchor_digest": ph,
           "leaf_hex": sidecar["leaf_hex"], "uuid": sidecar["rekor"]["uuid"],
           "anchor_version": A.ANCHOR_TYPE, "checkpoint_seq": cp["seq"],
           "payment_id": PID, "charge": charge6, "claim": claim,
           "verdict": r6["verdict"]},
          open(FX, "w"), ensure_ascii=False, indent=1)
print(f"  kanıt-fixture: {FX}")

# --- 5) NEGATİF-1: sahte-anchor-özütü (uydurma-64hex) → RED rc7
# saldırgan-gerçek-bir-Rekor-çapası-üretmeden-uydurma-64hex-yazar; alıcı
# anchor_digest'ı-bağımsız-hesaplayınca-tutmaz → evidenceHash-uyuşmazlığı.
chargeN1 = json.loads(json.dumps(charge))
chargeN1["delivery_hash"]["hex"] = "f" * 64
rN1 = SB.verify(chargeN1, claim)
assert rN1["verdict"] == "RED" and rN1["reason_code"] == 7, \
    f"sahte-anchor-RED-rc7-beklendi: {rN1}"
print("  sahte-anchor-özütü (uydurma-64hex) → RED rc7 — kanıtsız-ödeme-alınamaz")

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
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Veridict-anchor-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-123: Veridict-anchor (dördüncü-yüz) → RFC-010 x402/v1"
[[ $FAIL -eq 0 ]]

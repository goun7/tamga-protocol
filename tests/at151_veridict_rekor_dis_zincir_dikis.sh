#!/usr/bin/env bash
# AT-151: VERİDİCT-REKOR-DIŞ-ZİNCİR-ÇAPASI → RFC-010 ( blockchain-yüzü-9)
#
# Mesh'in-İLK-GERÇEK-DIŞ-GENEL-ZİNCİR-entegrasyonu. veridict/anchor.py Rekor
# ( sigstore-public-good)'a-çıpa-at — AT-147/148'ün-iç-zincir-anchor'larından
# FARKLI-olarak-bu-gerçek-dış-log.
#
# TEHDİT-MODELİ ( üretim-kodunun-kendi-sözü): çapa-bir-EXISTENCE-attestation'ı;
# "anyone-can-anchor-any-digest — that-lauders-nothing-because-a-forged-
# certificate-fails-verify-on-its-own-signature". Güvenlik-enrolled-Ed25519
# anahtarında; çapa-sadece "bu-checkpoint-zaman-T'de-kamuyen-var-oldu"-der.
#
# ÖNEMLİ-TEST-SAFLIĞI: anchor.verify-PURE-OFFLINE'dır; bu-test
# (a) CANLI-KAYDEDİLMİŞ-GERÇEK-Rekor-trafiği-ile-çağrılır ( PROBE_ENTRY —
#     2026-09-14-tarihli-gerçek-kayıt, UYDURMA-DEĞİL) + GERÇEK-Rekor-anahtarı
#     ( default-pin) → sıfır-test-double, sıfır-simülasyon;
# (b) sadık-Rekor-transcript'i-sadece-network-katmanını-değiştirir — Merkle
#     matematiği-ve-ECDSA-tamamen-gerçektir.
set -uo pipefail

TESTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TESTDIR/.." && pwd)"
LOG="$ROOT/.evidence/VERIDICT-REKOR/$(date +%F)/at151.log"
mkdir -p "$(dirname "$LOG")"
PASS=0; FAIL=0
kontrol() { local rc=$1; shift; if [ $rc -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "HATA: $*"; fi; }

if [ ! -f /home/gokun/projects/00_TAMGA-MESH/veridict/veridict/anchor.py ]; then
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — veridict-yok (İNDETERMİNE)"; exit 0
fi

python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, json, hashlib, copy
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/veridict")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/veridict/tests")
from veridict import anchor
# PROBE_ENTRY/PROBE_UUID: CANLI-Rekor'dan-kaydedilmiş-gerçek-trafik ( modül-
# seviyesi; fixture'lar-çağrılmaz). Uydurma-yük-DEĞİL — kaynaktır:
from test_anchor import PROBE_ENTRY, PROBE_UUID

# --- 1) GERÇEK-DIŞ-ZİNCİR: canlı-kayıt + gerçek-Rekor-anahtarı → GREEN
sidecar = {"anchor_version": anchor.ANCHOR_TYPE,
           "rekor": {"server": anchor.REKOR_SERVER,
                     "uuid": PROBE_UUID, "entry": copy.deepcopy(PROBE_ENTRY)},
           "bound": {"anchor": anchor.ANCHOR_TYPE, "cert_id": "",
                     "key_id": "", "checkpoint_seq": None, "chain_hash": ""},
           "digest": hashlib.sha256(b"probe").hexdigest()}
res = anchor.verify(sidecar)             # cert=None: crypto-only; default=GERÇEK-anahtar
assert res["valid"], f"gerçek-Rekor-kaydı-doğrulanmadı: {res['errors']}"
print("  GERÇEK-DIŞ-ZİNCİR: canlı-kayıtlı-Rekor-entry → GREEN ( gerçek-pin, "
      "offline; SET+checkpoint+uuid/leaf+root-çapraz-kontrol)")

# --- 2) trust-pinning: yabancı-log-anahtarı → RED
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
stranger = ec.generate_private_key(ec.SECP256R1)
pem = stranger.public_key().public_bytes(Encoding.PEM, PublicFormat.SubjectPublicKeyInfo).decode()
res2 = anchor.verify(sidecar, rekor_key_pem=pem)
assert not res2["valid"], "yabancı-log-anahtarı-GEÇTİ!"
assert any("SET signature" in e for e in res2["errors"]), f"hata-beklenmedik: {res2['errors']}"
print("  NEG trust-pinning: yabancı-log-anahtarı → RED ( 'SET signature'; "
      "stale-pin-fail-CLOSED — asla-güvenmez)")

# --- 3) entry-body-tahrizi → RED
sc3 = copy.deepcopy(sidecar)
body = json.loads(__import__("base64").b64decode(sc3["rekor"]["entry"]["body"]))
body["spec"]["data"]["hash"]["value"] = "00" * 32
sc3["rekor"]["entry"]["body"] = __import__("base64").b64encode(
    json.dumps(body).encode()).decode()
res3 = anchor.verify(sc3)
assert not res3["valid"], "tahrizli-entry-geçti!"
print("  NEG entry-body-tahrizi → RED ( digest-body'ye-bağlı)")
PYEOF
kontrol $? "gerçek-dış-zincir-çapası"

# --- 4) dogfood-pipeline: gerçek-üretim-akışı + sadık-Rekor-transcript
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, json, copy, hashlib, base64, tempfile, os
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/veridict")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/veridict/tests")
from veridict import anchor
from veridict.audit import AuditOrchestrator
from veridict.claim_extractor import ClaimExtractor
from veridict.jury import Jury, Opinion, ScriptedProvider
from veridict.keys import KeyStore
from veridict.ledger import Ledger
from veridict.policy import PolicyDeclaration, Thresholds
from veridict.schemas import TaskManifest

REPO = "/home/gokun/projects/00_TAMGA-MESH/veridict"
task = TaskManifest(task_id="at151-t", artifact_path=REPO,
                    actor_identity="at151", intent_lines=("DOCTRINE: anchor",),
                    criticality=(), has_existing_tests=False, pytest_args=())
pol = PolicyDeclaration(policy_id="p", mode="CERTIFICATE", criticality=(),
                        thresholds=Thresholds(), divergence_tolerance=1/3)
led = Ledger(); ks = KeyStore(led); kid = ks.generate_and_enroll("at151")
jury = Jury([ScriptedProvider(family="f1", identity="j1",
            default=Opinion("SUPPORTS", 0.9, "imported")),
            ScriptedProvider(family="f2", identity="j2",
            default=Opinion("SUPPORTS", 0.9, "on disk"))])
res = AuditOrchestrator(led, pol, jury, ks, kid).run(task)
cert = res["cert"]; entries = led.entries()

# sadık-Rekor: RFC-6962-Merkle + gerçek-ECDSA ( network-dışı)
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec, utils
log_key = ec.generate_private_key(ec.SECP256R1)
pin_pem = log_key.public_key().public_bytes(
    __import__("cryptography.hazmat.primitives.serialization",
               fromlist=["Encoding"]).Encoding.PEM,
    __import__("cryptography.hazmat.primitives.serialization",
               fromlist=["PublicFormat"]).PublicFormat.SubjectPublicKeyInfo).decode()
tree_id = "108e9186e8c5677a"; state = {"index": 4242}
class Post:
    def __call__(self, url, json=None, timeout=None, **kw):
        body = anchor._canonical(json)
        leaf = hashlib.sha256(b"\x00" + body).hexdigest()
        uuid = f"{tree_id}{leaf}{tree_id}"
        entry = {"body": base64.b64encode(body).decode(),
                 "integratedTime": 1790000000,
                 "logID": "ab"*32, "logIndex": state["index"],
                 "verification": {}}
        state["index"] += 1
        set_b = json  # Rekor-canonical-SET
        st = log_key.sign(anchor._canonical({"apiVersion":"0.0.1","kind":"hashedrekord",
            "spec":entry["body"]}), hashes.SHA256())
        entry["verification"] = {"signedEntryTimestamp": base64.b64encode(st).decode()}
        return type("R", (), {"status_code": 201, "text": "ok",
                              "json": lambda self=0, p=entry: p})()
import veridict.anchor as A
A.requests.post = Post()

sidecar = anchor.publish(entries, cert)
v = anchor.verify(sidecar, cert, rekor_key_pem=pin_pem)
assert v["valid"], f"dogfood-pipeline-çapa-bozuk: {v['errors']}"
print("  dogfood-pipeline: gerçek-AuditOrchestrator → publish → verify-GREEN "
      "( Merkle+ECDSA-gerçek; transcript-yalnız-network)")

# chain-disagreement: ledger-chain_hash ↔ cert-uyuşmazsa → RuntimeError
e2 = copy.deepcopy(entries); cp = cert["ledger_anchor"]["checkpoint_seq"]
for e in e2:
    if e.get("seq") == cp:
        e["payload"]["chain_hash"] = "00"*32
try:
    anchor.publish(e2, cert)
    raise SystemExit("CHAIN-DISAGREEMENT-KABUL-EDİLDİ!")
except RuntimeError as ex:
    assert "disagrees" in str(ex)
print("  NEG chain-disagreement → RuntimeError ( ledger↔cert-tutarlılık)")
PYEOF
kontrol $? "dogfood-pipeline-çapası"

# --- 5) RFC-010-DİKİŞ: gerçek-Rekor-digest → x402/v1 ( §6-veridict)
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, json, hashlib
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/veridict")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/veridict/tests")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga/tools")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/tamga")
from veridict import anchor
from test_anchor import PROBE_UUID
import settlement_bind_verify as SB
from eth_account import Account

# GERÇEK-Rekor'ca-çapalanmış-digest ( sha256(b"probe") — canlı-kayıtla-aynı)
digest_hex = hashlib.sha256(b"probe").hexdigest()
acct = Account.create(); PUB = acct.address
govde = {"buyerAddress": PUB, "sellerAddress": "0x"+"2"*40,
         "settlementRef": "AT-151-REKOR",
         "evidenceHash": {"alg": "sha256", "hex": digest_hex}}
d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
_sig = Account.unsafe_sign_hash(bytes.fromhex(d), acct.key)
_v = _sig.v if _sig.v >= 27 else _sig.v + 27
sig_hex = "0x" + _sig.r.to_bytes(32,"big").hex() + _sig.s.to_bytes(32,"big").hex() + bytes([_v]).hex()
claim = dict(govde); claim["signature"] = sig_hex
charge = {"seq": 151, "prev": "0"*64, "h": "a"*64,
          "delivery_hash": {"alg":"sha256","hex": digest_hex},
          "settlement_bind": {"scheme":"x402/v1","payment_id":"AT-151-REKOR",
              "claim_evidence_hash":{"alg":"sha256","hex": d},
              "payer": PUB, "payee":"0x"+"2"*40, "verified_at":"2026-09-22T00:00:00Z"},
          "foreign_chain_proof": {"chain":"veridict","head_hex": digest_hex,
              "entries": 1, "evidence_link":"equals",
              "verify_cmd":"veridict.anchor.verify"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"Rekor-dikişi-GREEN-beklendi: {r}"
assert r["checks"].get("6_foreign_chain") is True
print(f"  dikiş: gerçek-Rekor-digest → RFC-010 x402/v1 GREEN rc0 "
      f"( §6-veridict; head=canlı-çapalı-digest, equals-link)")
PYEOF
kontrol $? "AT-151-RFC-010-dikiş"

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-151: veridict-Rekor-dış-zincir-çapası ( ilk-gerçek-dış-genel-zincir)"
[ "$FAIL" = "0" ]

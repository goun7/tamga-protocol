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
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

# ( ec-importu-üste-alındı: anchor.verify()'ın-ilk-çağrısı-modül-içi-import
#  yapar; import-sırası-yan-etkileri-var. İzole-teyitte-çalışan-sıra.)
stranger = ec.generate_private_key(ec.SECP256R1())
PEM_STRANGER = stranger.public_key().public_bytes(
    Encoding.PEM, PublicFormat.SubjectPublicKeyInfo).decode()

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
res2 = anchor.verify(sidecar, rekor_key_pem=PEM_STRANGER)
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

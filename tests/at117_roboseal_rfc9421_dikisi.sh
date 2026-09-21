#!/usr/bin/env bash
# AT-117: ROBOSEAL-ÜÇÜNCÜ-YÜZ ( RFC-9421-imza-çekirdeği) → RFC-010-tamga/native.
#
# 68-Kredent-roboseal: AT-074 ( çatışma-analizi, kaynak-tarama), AT-083 ( çözüm-
# uzayı: reputation.py+verifier.py), AT-092 ( K0-CT-log-Sybil) yapıldı.
# KALAN-ÖLÇÜLMEMİŞ-KRİPTO-YÜZ ( bu-test):
#   roboseal/crypto.py — Ed25519 + Multibase/Base58 çekirdeği
#     :84 generate_keypair, :95/:100 sign_detached/verify_detached (RFC-8032),
#     :58/:69 encode/decode_multibase_pubkey (z+base58btc+0xed01-multicodec)
#   roboseal/canonical.py — IETF RFC-9421 HTTP-Message-Signatures kanonizasyonu
#     :12 compute_content_digest (sha-256=:b64:), :22 build_signature_base,
#     :44 format_signature_headers, :75/:103 parse_signature_input/header
# AT-083'ün-çağırdığı verifier.py-bu-çekirdek-üzerine-inşa-edilir — AMA-çekirdek-
# kendisi-henüz-ölçülmedi. AT-117-onu-doldurur.
#
# DİKİŞ-ÖZELLİĞİ: RFC-9421-imza-tabanı-deterministik-kanonik-bir-bayt-dizisidir;
# onun-sha256'ı-RFC-010'a-evidenceHash-olarak-girer. Bu-iki-imza-standardını-
# BİRLEŞTİRMEZ (double-YOK): RFC-9421-HTTP-bağlamı-için, RFC-010-ödeme-kanıtı-
# için-ayrı-imzalanır — her-ikisi-de-aynı-GERÇEK-Ed25519-anahtarıyla.
#
# PyCa↔PyNaCl-paritesi ( AT-077-disiplini): crypto.py-cryptography-Ed25519-
# kullanır, SB._claim_signer-PyNaCl-doğrular — aynı-anahtar-aynı-imza-ortak-
# kanal olduğunu-gerçek-üretimle-ölçeriz ( stock-SB, test-double-YOK).
#
# Altı-kanıt + 2-negatif:
#   1) anahtar-çifti + multibase/base58-gidiş-dönüş-paritesi
#   2) RFC-9421-content-digest + 6-satır-imza-tabanı ( deterministik)
#   3) sign_detached/verify_detached: doğru-True / yanlış-payload-False /
#      yanlış-anahtar-False ( RFC-8032)
#   4) format/parse-header-gidiş-dönüş-paritesi ( keyid/alg/created + sig)
#   5) RFC-010-tamga/native-GREEN ( PyCa↔PyNaCl-paritesi, §6-tamga-zinciri)
#   6) NEG-1: sahte-imza → RED rc4; NEG-2: evidenceHash-swap → RED rc7
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/ROBOSEAL-3/$(date +%F)/at117.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-117: ROBOSEAL RFC-9421-imza-çekirdeği → RFC-010 tamga/native dikişi"

RK="/home/gokun/projects/01_unicorn/68-Kredent"
if [ ! -f "$RK/roboseal/crypto.py" ] || [ ! -f "$RK/roboseal/canonical.py" ]; then
  note "[SKIP] AT-117: ROBOSEAL-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import cryptography, nacl" 2>/dev/null; then
  note "[SKIP] AT-117: cryptography/PyNaCl-yok — gerçek-Ed25519-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$RK" <<'PYEOF' >> "$LOG" 2>&1
import base64, hashlib, json, os, sys
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from roboseal.crypto import (
    generate_keypair, sign_detached, verify_detached,
    b58encode, b58decode, encode_multibase_pubkey, decode_multibase_pubkey,
    load_private_key_from_bytes, load_public_key_from_bytes)
from roboseal.canonical import (
    compute_content_digest, build_signature_base,
    format_signature_headers, parse_signature_input, parse_signature_header)
from cryptography.hazmat.primitives.asymmetric import ed25519
from nacl.signing import SigningKey as NaClSigningKey
import settlement_bind_verify as SB

# --- 1) ANAHTAR-ÇİFTİ + multibase/base58-gidiş-dönüş-paritesi
priv, pub, MB = generate_keypair()
RAW = pub.public_bytes_raw()
assert len(RAW) == 32
assert MB.startswith("z"), f"multibase-'z'-önekli-olmalı: {MB!r}"
assert decode_multibase_pubkey(MB) == RAW, "multibase-gidiş-dönüş-bozuk"
assert decode_multibase_pubkey("z" + b58encode(b"\xed\x01" + RAW)) == RAW
for olcum in (b"", bytes(range(64)), b"\x00\x00\x00sifir-ic-baslangic", os.urandom(0)):
    assert b58decode(b58encode(olcum)) == olcum, f"b58-gidiş-dönüş-bozuk: {olcum!r}"
# anahtar-yükleme-paritesi
assert load_private_key_from_bytes(priv.private_bytes_raw()).private_bytes_raw() == priv.private_bytes_raw()
assert load_public_key_from_bytes(RAW).public_bytes_raw() == RAW
try:
    decode_multibase_pubkey("k" + MB[1:]); raise AssertionError("z-dışı-önek-kabul-edilmemeli")
except ValueError: pass
try:
    decode_multibase_pubkey("z" + b58encode(b"\xee\x02" + RAW)); raise AssertionError("yanlış-multicodec-kabul-edilmemeli")
except ValueError: pass
print(f"  anahtar-çifti: multibase-z+base58btc+0xed01, {len(MB)}-karakter; "
      f"gidiş-dönüş-paritesi-gerçek")

# --- 2) RFC-9421-content-digest + deterministik-6-satır-imza-tabanı
govde = {"agent_id": "did:agent:68:key:test117", "islem": "odeme", "tutar": "0.50"}
raw_body = json.dumps(govde, sort_keys=True).encode()
CD = compute_content_digest(raw_body)
assert CD.startswith("sha-256=:") and CD.endswith(":")
assert CD == "sha-256=:" + base64.b64encode(
    hashlib.sha256(raw_body).digest()).decode() + ":", "content-digest-standart-değil"
SIG_PARAMS = ('("@method" "@authority" "@target-uri" "content-digest" "date");'
              'created=1789262700;keyid="sig-117";alg="ed25519"')
B1 = build_signature_base("POST", "mesh.tamga", "/settle", CD,
                          "Mon, 21 Sep 2026 00:00:00 GMT", SIG_PARAMS)
B2 = build_signature_base("POST", "mesh.tamga", "/settle", CD,
                          "Mon, 21 Sep 2026 00:00:00 GMT", SIG_PARAMS)
assert B1 == B2, "imza-tabanı-deterministik-değil"
assert B1.count(b"\n") == 5, "6-satır-beklendi"
# büyük-küçük-harf-normalizasyonu
assert build_signature_base("post", "MESH.TAMGA", "/settle", CD,
                            "Mon, 21 Sep 2026 00:00:00 GMT", SIG_PARAMS) == B1
print(f"  RFC-9421: content-digest + {len(B1)}-bayt-6-satır-imza-tabanı, "
      f"deterministik (method/authority-normalizasyonuyla)")

# --- 3) sign_detached/verify_detached (RFC-8032, gerçek-doğrulama)
SIG = sign_detached(priv, B1)
assert len(SIG) == 64, f"Ed25519-imzası-64-bayt-beklendi: {len(SIG)}"
assert verify_detached(pub, B1, SIG) is True, "gerçek-imza-doğrulamalı"
assert verify_detached(pub, B1 + b"x", SIG) is False, "yanlış-payload-doğrulamamalı"
assert verify_detached(ed25519.Ed25519PublicKey.from_public_bytes(b"\x11" * 32),
                       B1, SIG) is False, "yanlış-anahtar-doğrulamamalı"
assert verify_detached(pub, B1, bytes(64)) is False, "sıfır-imza-doğrulamamalı"
print("  RFC-8032: sign_detached→verify_detached doğru-True; yanlış-payload/"
      "yanlış-anahtar/sıfır-imza-False")

# --- 4) format/parse-header-gidiş-dönüş-paritesi
DATE = "Mon, 21 Sep 2026 00:00:00 GMT"
HDR = format_signature_headers("did:agent:68:key:test117", "sig-117", "POST",
                              "mesh.tamga", "/settle", raw_body, SIG,
                              1789262700, DATE)
pi = parse_signature_input(HDR["Signature-Input"])
assert pi["keyid"] == "sig-117" and pi["alg"] == "ed25519"
assert pi["created"] == 1789262700
assert parse_signature_header(HDR["Signature"]) == SIG, "imza-gidiş-dönüş-bozuk"
assert HDR["Content-Digest"] == CD, "header-digest-gövdeyle-tutarlı-değil"
# bozuk-headerlar-rededilmeli
for bozuk in ("", "sig2=:abc:", "sig1=abc"):
    try:
        parse_signature_header(bozuk); raise AssertionError(f"bozuk-kabul: {bozuk!r}")
    except ValueError: pass
try:
    parse_signature_input("x=1"); raise AssertionError("sig1-dışı-kabul-edilmemeli")
except ValueError: pass
print("  RFC-9421-headerları: parse(format())-gidiş-dönüş + bozuk-girişler-ValueError")

# --- 5) RFC-010-tamga/native-GREEN (PyCa↔PyNaCl-paritesi, stock-SB)
# imza-tabanının-özütü-ödeme-kanıtının-evidenceHash'idir; buyerAddress-64-hex-
# raw-Ed25519-pubkey ( AT-077-deseni). İmza-PyNaCl-ile-atılır-çünkü-SB.stock.
EV = hashlib.sha256(B1).hexdigest()
PUB_HEX = RAW.hex()
nacl_sk = NaClSigningKey(priv.private_bytes_raw())
# PyCa↔PyNaCl-aynı-anahtar-aynı-imza-ortak-kanal-kanıtı
d_test = hashlib.sha256(b"parite-olcumu-117").digest()
assert nacl_sk.sign(d_test).signature == priv.sign(d_test), \
    "PyCa↔PyNaCl-imza-paritesi-bozuk"
govde_claim = {"buyerAddress": PUB_HEX, "sellerAddress": "0x2" * 40,
               "settlementRef": "ROB-9421-117",
               "evidenceHash": {"alg": "sha256", "hex": EV}}
d_stock = hashlib.sha256(json.dumps(govde_claim, sort_keys=True).encode()).hexdigest()
sig_hex = nacl_sk.sign(bytes.fromhex(d_stock)).signature.hex()
assert len(sig_hex) == 128
claim = dict(govde_claim); claim["signature"] = sig_hex
charge = {"seq": 17, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": EV},
          "settlement_bind": {"scheme": "tamga/native", "payment_id": "ROB-9421-117",
                              "claim_evidence_hash": {"alg": "sha256", "hex": d_stock},
                              "payer": PUB_HEX, "payee": "0x2" * 40,
                              "verified_at": "2026-09-21T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": EV, "entries": 1,
                                  "verify_cmd": "roboseal.canonical.compute_content_digest"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"RFC-9421-dikişi-GREEN-beklendi: {r}"
assert r["checks"].get("2_claim_sig") is True, "stock-Ed25519-doğrulaması-geçmedi"
assert r["checks"].get("6_foreign_chain") is True, "§6-tamga-zinciri-geçmedi"
print("  RFC-9421-özütü → RFC-010-tamga/native-GREEN (PyCa↔PyNaCl-paritesi, §6-tamga)")

# --- 6) NEG-1: sahte-imza → RED rc4
for sahte in ("ff" * 64, os.urandom(64).hex(), "11" * 64):
    cs = dict(govde_claim); cs["signature"] = sahte
    rs = SB.verify(charge, cs)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"sahte-imza-RED-rc4-beklendi: {rs}"
print("  sahte-imza (64-byte-rastgele/sıfır) → RED rc4 (fail-closed)")

# --- 7) NEG-2: evidenceHash-swap (aynı-gerçek-anahtarla-yeni-imzalı) → RED rc7
govde2 = dict(govde_claim)
govde2["evidenceHash"] = {"alg": "sha256", "hex": "9" * 64}
d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
c2 = dict(govde2); c2["signature"] = nacl_sk.sign(bytes.fromhex(d2)).signature.hex()
r2 = SB.verify(charge, c2)
assert r2["verdict"] == "RED" and r2["reason_code"] == 7, \
    f"evidenceHash-swap-RED-rc7-beklendi: {r2}"
print("  evidenceHash-swap (yeni-gerçek-imzalı) → RED rc7 (fail-closed)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: yedi-ROBOSEAL-RFC-9421-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-117: ROBOSEAL RFC-9421-imza-çekirdeği → RFC-010 tamga/native"
[[ $FAIL -eq 0 ]]

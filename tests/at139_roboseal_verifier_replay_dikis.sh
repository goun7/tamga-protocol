#!/usr/bin/env bash
# AT-139: ROBOSEAL-BEŞİNCİ-YÜZ ( RFC-9421-TAM-DOĞRULAMA-YOLU + REPLAY-KORUMASI)
# → RFC-010-TAMGA/NATIVE-DİKİŞİ.
#
# 68-Kredent-roboseal: AT-074 ( çatışma), AT-083 ( çözüm-uzayı-reputation),
# AT-092 ( K0-CT-log-Sybil), AT-117 ( RFC-9421-çekirdek: crypto+canonical),
# AT-122 ( DID-belgesi+revocation) bağlandı. KALAN-ÖLÇÜLMEMİŞ-YÜZ ( bu-test):
#   roboseal/verifier.py — RFC-9421-TAM-6-ADIM-DOĞRULAMA-YOLU:
#     :56 verify_http_request — header-kontrolü → content-digest → created/
#       drift → imza-parse → REPLAY → canonical-base → Ed25519 ( 6-adım,
#       her-adımda-fail-closed)
#     :22 ReplayCache — sha256(raw_sig) + TTL ( 360s) + thread-lock;
#       "kullan-at-sonra-öldü" — aynı-imza-ikinci-keze-RED
#   AT-117-çekirdeği-bağladı-AMA-tam-doğrulama-yolu-bütünleşik-ölçülmedi;
#   AT-083-reputation'ı-ayrı-bir-yüz. Bu-test-edge-verifier'ın-kendisini-ölçer.
#
# DİKİŞ-ÖZELLİĞİ ( bu-testin-asıl-kanıtı): edge-verifier'ın-GERÇEK-geçerli-
# sonucu-ödeme-kanıtıdır — 6-adımın-tamamı-gerçek-yoldan-koşar ( gerçek-keypair,
# gerçek-RFC-9421-imza-tabanı, gerçek-Ed25519). ReplayCache-penceresi-içinde
# TEK-SEFERLİK-işlem-semantiği-doğrulanır ( imza-bir-kez-kullanılır; tekrarı-RED).
#
# AT-117-PyCa↔PyNaCl-paritesi ( stock-SB, test-double-YOK): roboseal-cryptography-
# Ed25519-üretir, SB._claim_signer-tamga/native-PyNaCl-doğrular; aynı-anahtarın
# aynı-imzayı-ortak-kanal-yaptığını-gerçek-üretimle-ölçeriz.
#
# Yedi-kanıt + 3-negatif:
#   1) GERÇEK-RFC-9421-imzalı-istek-üretimi ( generate_keypair+format_headers)
#   2) 6-adım-fail-closed: MISSING_HEADERS-400 / DIGEST_MISMATCH-401 /
#      MALFORMED_SIG_INPUT-400 / MISSING_CREATED-400 / SIGNATURE_EXPIRED-401 /
#      MALFORMED_SIGNATURE-400 / INVALID_PUBLIC_KEY-401 / INVALID_SIGNATURE-401
#   3) ReplayCache: 1.-kullanım-200 → aynı-imza-2.-REPLAY-401; TTL-pruner
#      ( kullan-at-sonra-öldü); farklı-imza-aynı-pencerede-geçerli
#   4) PyCa↔PyNaCl-imza-paritesi ( aynı-anahtar-aynı-imza)
#   5) RFC-010-tamga/native-GREEN ( doğrulama-sonucu-özütü + gerçek-Ed25519, §6)
#   6) NEG-1: sahte-imza → RED rc4
#   7) NEG-2: evidenceHash-swap ( yeni-gerçek-imzalı) → RED rc7
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/ROBOSEAL-5/$(date +%F)/at139.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-139: Roboseal RFC-9421 tam-doğrulama-yolu + ReplayCache → RFC-010 dikişi"

RK="/home/gokun/projects/01_unicorn/68-Kredent"
if [ ! -f "$RK/roboseal/verifier.py" ] || [ ! -f "$RK/roboseal/canonical.py" ] \
   || [ ! -f "$RK/roboseal/crypto.py" ]; then
  note "[SKIP] AT-139: ROBOSEAL-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
# cryptography (PyCa-Ed25519) + nacl (tamga/native-verify) yokluğu-eksiklik-değil
if ! python3 -c "import cryptography, nacl" 2>/dev/null; then
  note "[SKIP] AT-139: cryptography/PyNaCl-yok — gerçek-Ed25519-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$RK" <<'PYEOF' >> "$LOG" 2>&1
import base64, hashlib, json, os, sys
sys.path.insert(0, sys.argv[1])              # .../68-Kredent
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from roboseal.crypto import generate_keypair, sign_detached, load_public_key_from_bytes
from roboseal.canonical import (compute_content_digest, build_signature_base,
                                format_signature_headers)
from roboseal.verifier import verify_http_request, ReplayCache
import settlement_bind_verify as SB

# --- 0) SABİT-zaman-üzerinde-deterministik-test ( clock-free)
T0 = 1789262700                              # sabit-epoch ( drift-kontrolleri-için)
DATE = "Mon, 22 Sep 2026 12:45:00 GMT"
AUTH, URI = "api.agentshelf.org", "https://api.agentshelf.org/v1/settle"
BODY = json.dumps({"agent": "mesh-139", "islem": "odeme",
                   "tutar": "0.50"}, sort_keys=True).encode()

# --- 1) GERÇEK-RFC-9421-imzalı-istek-üretimi ( gerçek-keypair-üretim-yolu)
priv, pub, MB = generate_keypair()
RAW = pub.public_bytes_raw()                 # 32-byte-raw-Ed25519-pubkey
AID = f"did:agent:68:key:{MB}"
assert len(RAW) == 32 and len(AID) > 20

def imzali_istek(created_epoch, body=BODY, priv_k=priv):
    """Üretim-yolu: content-digest → 6-satır-imza-tabanı → Ed25519 → headerlar."""
    cd = compute_content_digest(body)
    sp = (f'("@method" "@authority" "@target-uri" "content-digest" "date");'
          f'created={created_epoch};keyid="sig-139";alg="ed25519"')
    sb = build_signature_base("POST", AUTH, URI, cd, DATE, sp)
    sig = sign_detached(priv_k, sb)
    return format_signature_headers(agent_id=AID, kid="sig-139", method="POST",
                                    authority=AUTH, target_uri=URI, raw_body=body,
                                    signature_bytes=sig, created_epoch=created_epoch,
                                    date_str=DATE), sb, sig

H, SIG_BASE, SIG = imzali_istek(T0)
r = verify_http_request("POST", AUTH, URI, H, BODY, RAW, now=float(T0))
assert r.valid is True and r.status_code == 200, f"geçerli-beklendi: {r.status_code} {r.error_code}"
assert r.agent_id == AID and r.created_epoch == T0
assert r.message == "Signature verified successfully"
print(f"  RFC-9421-geçerli: 200, agent={AID[:34]}…, created={T0} (gerçek-keypair)")

# --- 2) 6-ADIM-FAIL-CLOSED ( her-adım-gerçek-reddi)
# (a) header-eksik → 400
ra = verify_http_request("POST", AUTH, URI, {"agent-id": AID}, BODY, RAW,
                         now=float(T0))
assert (ra.status_code, ra.error_code) == (400, "MISSING_SIGNATURE_HEADERS"), \
    f"missing-400-beklendi: {ra.error_code}"
# (b) body-tahrizi → digest-uyumsuz → 401
H2 = dict(H)
r_b = verify_http_request("POST", AUTH, URI, H2, BODY + b"x", RAW,
                          now=float(T0))
assert (r_b.status_code, r_b.error_code) == (401, "DIGEST_MISMATCH")
# (c) content-digest-swap → 401
H2["content-digest"] = compute_content_digest(b"diger-govde")
r_c = verify_http_request("POST", AUTH, URI, H2, BODY, RAW, now=float(T0))
assert (r_c.status_code, r_c.error_code) == (401, "DIGEST_MISMATCH")
# (d) bozuk-signature-input ( parse-hatası) → 400
H3 = dict(H); H3["signature-input"] = "invalid_no_sig1"
r_d = verify_http_request("POST", AUTH, URI, H3, BODY, RAW, now=float(T0))
assert (r_d.status_code, r_d.error_code) == (400, "MALFORMED_SIGNATURE_INPUT")
# (e) created-yok ( parse-edilir-ama-created-alanı-yok) → 400
H4 = dict(H); H4["signature-input"] = "sig1=();keyid=\"k\""
r_e = verify_http_request("POST", AUTH, URI, H4, BODY, RAW, now=float(T0))
assert (r_e.status_code, r_e.error_code) == (400, "MISSING_CREATED_TIMESTAMP")
# (f) drift > 180s → 401 SIGNATURE_EXPIRED
H5, _, _ = imzali_istek(T0 - 1000)
r_f = verify_http_request("POST", AUTH, URI, H5, BODY, RAW, now=float(T0))
assert (r_f.status_code, r_f.error_code) == (401, "SIGNATURE_EXPIRED")
# (g) bozuk-signature-header ( parse-hatası) → 400
H6 = dict(H); H6["signature"] = "malformed_sig_val"
r_g = verify_http_request("POST", AUTH, URI, H6, BODY, RAW, now=float(T0))
assert (r_g.status_code, r_g.error_code) == (400, "MALFORMED_SIGNATURE")
# (h) geçersiz-pubkey ( yanlış-uzunluk) → 401
r_h = verify_http_request("POST", AUTH, URI, H, BODY, bytes(31), now=float(T0))
assert (r_h.status_code, r_h.error_code) == (401, "INVALID_PUBLIC_KEY")
# (i) geçersiz-imza ( BAŞKA-gerçek-anahtarla-imzalı) → 401
priv2, pub2, _ = generate_keypair()
H7, _, _ = imzali_istek(T0, priv_k=priv2)
r_i = verify_http_request("POST", AUTH, URI, H7, BODY, RAW, now=float(T0))
assert (r_i.status_code, r_i.error_code) == (401, "INVALID_SIGNATURE")
print("  6-adım-fail-closed: MISSING-400 / DIGEST-401 / MALFORMED-INPUT-400 / "
      "NO-CREATED-400 / EXPIRED-401 / MALFORMED-SIG-400 / BAD-PUBKEY-401 / "
      "INVALID-SIG-401 (hepsi-gerçek-yoldan)")

# --- 3) ReplayCache: TEK-SEFERLİK-işlem-semantiği ( kullan-at-sonra-öldü)
RC = ReplayCache(ttl_seconds=360)
# 1.-kullanım-geçerli
r1 = verify_http_request("POST", AUTH, URI, H, BODY, RAW,
                         replay_cache=RC, now=float(T0))
assert r1.valid is True and r1.status_code == 200
# 2.-aynı-imza → REPLAY-401 ( imza-dijital-tekrar-oynatma)
r2 = verify_http_request("POST", AUTH, URI, H, BODY, RAW,
                         replay_cache=RC, now=float(T0))
assert (r2.status_code, r2.error_code) == (401, "REPLAY_ATTACK_DETECTED"), \
    f"replay-RED-beklendi: {r2.error_code}"
# farklı-imza-aynı-pencerede → geçerli ( her-imza-tek-seferlik)
H8, _, _ = imzali_istek(T0 + 1)
r3 = verify_http_request("POST", AUTH, URI, H8, BODY, RAW,
                         replay_cache=RC, now=float(T0) + 1.0)
assert r3.valid is True, "farklı-imza-replay-değil"
# check_and_add-TTL-pruner: aynı-digest-TTL-sonrası-tekrar-eklenebilir
assert RC.check_and_add("digest-x", now=100.0) is True
assert RC.check_and_add("digest-x", now=100.0) is False
assert RC.check_and_add("digest-x", now=500.0) is True, "TTL-sonrası-prune-edilmeli"
# thread-safe-lock-var ( eş-zamanlı-kullanım-güvenliği)
assert hasattr(RC, "_lock"), "replay-cache-thread-lock-yok"
print("  ReplayCache: 1.-kullanım-200 → aynı-imza-REPLAY-401; farklı-imza-"
      "geçerli; TTL-pruner ( 360s) cache'i-boşaltır; thread-lock-var")

# --- 4) PyCa↔PyNaCl-imza-paritesi ( AT-117-disiplini, stock-yol)
from nacl.signing import SigningKey as NaClSigningKey
nacl_sk = NaClSigningKey(priv.private_bytes_raw())
d_parite = hashlib.sha256(b"parite-olcumu-139").digest()
assert nacl_sk.sign(d_parite).signature == priv.sign(d_parite), \
    "PyCa↔PyNaCl-imza-paritesi-bozuk (aynı-anahtar-aynı-imza)"
print("  PyCa≡PyNaCl: aynı-anahtarın-imzası-ortak-kanal ( RFC-9421↔RFC-010)")

# --- 5) DİKİŞ: edge-verifier'ın-geçerli-sonucu → RFC-010-tamga/native-GREEN
# kanıt: 6-adımın-tamamını-geçmiş-gerçek-doğrulama-sonucunun-özütü
sonuc = {"valid": r1.valid, "status_code": r1.status_code,
         "agent_id": r1.agent_id, "created_epoch": r1.created_epoch,
         "replay_window": "single-use", "message": r1.message}
EV = hashlib.sha256(json.dumps(sonuc, sort_keys=True).encode()).hexdigest()
assert len(EV) == 64
PUB_HEX = RAW.hex()
govde = {"buyerAddress": PUB_HEX, "sellerAddress": "0x" + "2" * 40,
         "settlementRef": "ROB-VERIFY-139",
         "evidenceHash": {"alg": "sha256", "hex": EV}}
d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
sig_hex = nacl_sk.sign(bytes.fromhex(d)).signature.hex()
assert len(sig_hex) == 128
assert sig_hex[:64] != PUB_HEX, "imza-R-noktası-genel-anahtar-OLAMAZ (AT-077-dersi)"
claim = dict(govde); claim["signature"] = sig_hex
charge = {"seq": 139, "prev": "0" * 64, "h": "c" * 64,
          "delivery_hash": {"alg": "sha256", "hex": EV},
          "settlement_bind": {"scheme": "tamga/native", "payment_id": "ROB-VERIFY-139",
                              "claim_evidence_hash": {"alg": "sha256", "hex": d},
                              "payer": PUB_HEX, "payee": "0x" + "2" * 40,
                              "verified_at": "2026-09-22T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": EV,
                                  "entries": 1, "evidence_link": "equals",
                                  "verify_cmd": "roboseal.verifier."
                                                "verify_http_request"}}
r10 = SB.verify(charge, claim)
assert r10["verdict"] == "GREEN", f"verifier-dikişi-GREEN-beklendi: {r10}"
assert r10["checks"].get("2_claim_sig") is True, "stock-PyNaCl-imzası-geçmedi"
assert r10["checks"].get("6_foreign_chain") is True, "§6-zincir-geçmedi"
print(f"  geçerli-doğrulama-sonucu-özütü → RFC-010-tamga/native-GREEN "
      f"(gerçek-Ed25519; §6-tamga-zinciri)")

# --- 6) NEG-1: sahte-imza → RED rc4
for sahte in ("ff" * 64, os.urandom(64).hex()):
    cs = dict(govde); cs["signature"] = sahte
    rs = SB.verify(charge, cs)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"sahte-imza-RED-rc4-beklendi ({sahte[:8]}…): {rs}"
print("  sahte-imza (128-heks-sıfır/rastgele) → RED rc4 (fail-closed)")

# --- 7) NEG-2: evidenceHash-swap ( yeni-gerçek-imzalı) → RED rc7
govde2 = dict(govde)
govde2["evidenceHash"] = {"alg": "sha256", "hex": "9" * 64}
d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
c2 = dict(govde2); c2["signature"] = nacl_sk.sign(bytes.fromhex(d2)).signature.hex()
r2n = SB.verify(charge, c2)
assert r2n["verdict"] == "RED" and r2n["reason_code"] == 7, \
    f"evidenceHash-swap-RED-rc7-beklendi: {r2n}"
print("  evidenceHash-swap (yeni-gerçek-imzalı) → RED rc7 (fail-closed)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: yedi-Roboseal-RFC-9421-verifier-replay-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-139: Roboseal RFC-9421 tam-doğrulama-yolu + ReplayCache → RFC-010"
[[ $FAIL -eq 0 ]]

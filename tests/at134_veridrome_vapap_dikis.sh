#!/usr/bin/env bash
# AT-134: VERIDROME-BEŞİNCİ-YÜZ ( VAPAP agent-yetkilendirme-protokolü) →
# RFC-010-TAMGA/NATIVE-DİKİŞİ.
#
# 73-Veridrome: AT-072 ( RFC-6962-audit-log), AT-108 ( W3C-VC), AT-126 ( TEE),
# AT-128 ( contracts-ERC-8004-on-chain) bağlandı. KALAN-ÖLÇÜLMEMİŞ-KRİPTO-YÜZ
# ( bu-test): **credentials/vapap_middleware.py** — kurumsal-API-gateway'ler
# için-otonom-ajan-yetkilendirme-katmanı:
#   vapap_middleware.py:101 — VAPAPAuthMiddleware._verify_token
#     base64 → JSON → imza-ayrıştırma → canonical-JSON ( sort_keys) → GERÇEK
#     Ed25519-doğrulama ( VeridromeAuthoritySigner.verify)
#   vapap_middleware.py:36  — dispatch: 401-TOKEN_MISSING / 403-INVALID_SIGNATURE
#     / 403-EXPIRED / 403-INSUFFICIENT_SCORE / 400-MALFORMED
#
# ÜRETİM/TÜKETİM-BÜTÜNLÜĞÜ ( bu-testin-asıl-kanıtı): tokenı AT-108'in-üretim
# yolu-üretir — w3c_vc.py:116 create_vapap_token ( iss/cert_id/agent_id/score_
# median/tee_pcr0/issued_at/expires_at → canonical → Ed25519 → b64-kapsül).
# Bu-test-o-tokenı-middleware'in-GERÇEK-yolundan-geçirir. Token-bizim-tarafımızdan
# elle-İNŞA-EDİLMİYOR ( test-double-YOK): gerçek-üretici-gerçek-tüketiciyi-doğrular.
#
# AT-108-W3C-VC'si-tokenı-üretip-CT-defterine-yazdı-AMA-onu-TÜKETEN-yüz
# ( middleware) hiç-ölçülmedi — AT-134-o-boşluğu-kapatır.
#
# DİKİŞ-ŞEMASI: tamga/native ( RFC-010-§3.2) — gerçek-Ed25519-operatör;
# imza-digest'ın-HAM-BAYTLARI-üzerine-atılır ( gövde-metnine-değil;
# AT-077/108/126-disiplini); buyerAddress=64-hex-raw-pubkey.
#
# Altı-kanıt + 2-negatif:
#   1) GERÇEK-token-üretimi ( create_vapap_token — AT-108'in-yolu)
#   2) Üretici-tarafı-sağlamlık: roundtrip-True / yanlış-anahtar-False /
#      tahrif-False / imzasız-False / sahte-otorite-False
#   3) DÖRT-dispatch-gate + muaf-yol + çift-taşıyıcı ( gerçek-HTTP-isteği)
#   4) RFC-010-tamga/native-GREEN ( token-özütü + gerçek-Ed25519, §6)
#   5) NEG-1: sahte-imza → RED rc4
#   6) NEG-2: evidenceHash-swap ( yeni-gerçek-imzalı) → RED rc7
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/VERIDROME-5/$(date +%F)/at134.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-134: Veridrome beşinci-yüz (VAPAP agent-yetkilendirme) → RFC-010 tamga/native dikişi"

VE="/home/gokun/projects/01_unicorn/73-Veridrome/src"
if [ ! -f "$VE/veridrome/credentials/vapap_middleware.py" ] \
   || [ ! -f "$VE/veridrome/credentials/w3c_vc.py" ] \
   || [ ! -f "$VE/veridrome/core/crypto.py" ]; then
  note "[SKIP] AT-134: Veridrome-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
# cryptography (Ed25519) + nacl (tamga/native-verify) + fastapi/httpx (dispatch)
# yokluğu-eksiklik-değil-İNDETERMİNE ( RED-boyanmaz)
if ! python3 -c "import cryptography, nacl, fastapi, httpx, starlette" 2>/dev/null; then
  note "[SKIP] AT-134: cryptography/nacl/fastapi/httpx/starlette-yok —"
  note "       gerçek-Ed25519+middleware-dispatch-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$VE" <<'PYEOF' >> "$LOG" 2>&1
import base64, hashlib, json, os, sys, tempfile
sys.path.insert(0, sys.argv[1])              # .../73-Veridrome/src
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from fastapi import FastAPI, Request
from starlette.testclient import TestClient
from veridrome.core.crypto import VeridromeAuthoritySigner
from veridrome.credentials.w3c_vc import VeridromeCredentialManager
from veridrome.credentials.vapap_middleware import VAPAPAuthMiddleware
import settlement_bind_verify as SB

# --- 1) GERÇEK-token-üretimi ( AT-108'in-üretim-yolu — elle-inşa-YOK)
signer = VeridromeAuthoritySigner()                 # cryptography-Ed25519, gerçek
PUB = signer.public_key_bytes.hex()                 # 32-byte-raw-genel-anahtar
assert len(PUB) == 64 and all(c in "0123456789abcdef" for c in PUB)
CT = tempfile.mktemp(suffix=".jsonl")
mgr = VeridromeCredentialManager(signer, ct_log_path=CT)
VAPAP = mgr.create_vapap_token(
    agent_id="did:veridrome:agent-7", cert_id="urn:veridrome:cert:JOB-134",
    score_median=0.92, expires_in_sec=3600,
    tee_pcr0="98f12a" + "00" * 29)
raw_tok = json.loads(base64.b64decode(VAPAP))
assert set(raw_tok) >= {"iss", "cert_id", "agent_id", "score_median",
                        "tee_pcr0", "issued_at", "expires_at", "signature"}
assert raw_tok["iss"] == "veridrome:authority:root"
assert raw_tok["agent_id"] == "did:veridrome:agent-7"
assert raw_tok["score_median"] == 0.92
assert raw_tok["expires_at"] - raw_tok["issued_at"] == 3600, "1-saat-geçerlilik"
print(f"  VAPAP-token-üretildi ( create_vapap_token): iss={raw_tok['iss']} "
      f"agent={raw_tok['agent_id']} skor={raw_tok['score_median']}")

# --- 2) ÜRETİCİ-TARAFI-SAĞLAMLIK ( middleware'in-gerçek-doğrulama-yolu)
MW = VAPAPAuthMiddleware(app=None, authority_public_key=signer.public_key_bytes,
                         required_min_score=0.85)
claims, ok = MW._verify_token(VAPAP)
assert ok is True, "gerçek-token-gerçek-otorite-anahtarıyla-doğrulanmalı"
assert claims["agent_id"] == "did:veridrome:agent-7"
assert claims["score_median"] == 0.92
# (a) yanlış-otorite-anahtarı → False
MW_BAD = VAPAPAuthMiddleware(app=None, authority_public_key=bytes(32))
c_bad, ok_bad = MW_BAD._verify_token(VAPAP)
assert ok_bad is False, "yanlış-otorite-anahtarı-doğrulamamalı"
# (b) tahrif-edilmiş-payload → False ( imza-değişmezlik)
t = dict(raw_tok); t["score_median"] = 0.999
c_t, ok_t = MW._verify_token(base64.b64encode(json.dumps(t).encode()).decode())
assert ok_t is False, "tahrif-edilmiş-claim-doğrulamamalı (canonical-üzerine-imza)"
# (c) imzasız-token → False
t2 = {k: v for k, v in raw_tok.items() if k != "signature"}
c_n, ok_n = MW._verify_token(base64.b64encode(json.dumps(t2).encode()).decode())
assert ok_n is False, "imzasız-token-doğrulamamalı"
# (d) sahte-otorite-anahtarıyla-imzalanmış-token → False ( otorite-taklidi)
IMPOSTER = VeridromeAuthoritySigner()          # farklı-gerçek-Ed25519-anahtarı
t4 = {k: v for k, v in raw_tok.items() if k != "signature"}
canon4 = json.dumps(t4, sort_keys=True).encode()
t4["signature"] = base64.b64encode(IMPOSTER.sign(canon4)).decode()
c_i, ok_i = MW._verify_token(base64.b64encode(json.dumps(t4).encode()).decode())
assert ok_i is False, "sahte-otorite-anahtarıyla-imzalı-token-doğrulamamalı"
assert IMPOSTER.public_key_bytes != signer.public_key_bytes, "anahtarlar-farklı-olmalı"
print("  _verify_token: roundtrip-True; yanlış-anahtar/tahrif/imzasız/sahte-otorite-False")

# --- 3) DÖRT-DISPATCH-GATE + muaf-yol + çift-taşıyıcı ( GERÇEK-HTTP-isteği)
app = FastAPI()

@app.get("/api/v1/agent-islem")
def agent_islem(request: Request):
    return {"ok": True, "agent_id": request.state.agent_id,
            "score": request.state.vapap_claims["score_median"]}

@app.get("/healthz")
def healthz():
    return {"status": "ok"}

app.add_middleware(VAPAPAuthMiddleware,
                   authority_public_key=signer.public_key_bytes,
                   required_min_score=0.85)
C = TestClient(app)

# (a) token-yok → 401
r1 = C.get("/api/v1/agent-islem")
assert r1.status_code == 401 and r1.json()["error"] == "VAPAP_TOKEN_MISSING", \
    f"401-beklendi: {r1.status_code} {r1.json()}"
# (b) geçerli-token → 200 ( istek-app'e-ulaştı, state-enjekte-edildi)
r2 = C.get("/api/v1/agent-islem",
           headers={"X-Veridrome-VAPAP-Token": VAPAP})
assert r2.status_code == 200, f"200-beklendi: {r2.status_code} {r2.json()}"
assert r2.json()["agent_id"] == "did:veridrome:agent-7"
assert r2.json()["score"] == 0.92
# (c) alternatif-taşıyıcı: Authorization: VAPAP <token> → 200
r2b = C.get("/api/v1/agent-islem",
            headers={"Authorization": "VAPAP " + VAPAP})
assert r2b.status_code == 200 and r2b.json()["agent_id"] == "did:veridrome:agent-7"
# (d) düşük-skore → 403-INSUFFICIENT
TOK_LOW = mgr.create_vapap_token("agent-low", "urn:c:low", 0.50, 3600)
r3 = C.get("/api/v1/agent-islem",
           headers={"X-Veridrome-VAPAP-Token": TOK_LOW})
assert r3.status_code == 403 and r3.json()["error"] == "VAPAP_INSUFFICIENT_SCORE"
# (e) süresi-dolmuş → 403-EXPIRED
TOK_EXP = mgr.create_vapap_token("agent-exp", "urn:c:exp", 0.95, -10)
r4 = C.get("/api/v1/agent-islem",
           headers={"X-Veridrome-VAPAP-Token": TOK_EXP})
assert r4.status_code == 403 and r4.json()["error"] == "VAPAP_TOKEN_EXPIRED"
# (f) sahte-imzalı-token → 403-INVALID_SIGNATURE
t_s = dict(raw_tok); t_s["signature"] = base64.b64encode(bytes([0x99]) * 64).decode()
TOK_SIG = base64.b64encode(json.dumps(t_s).encode()).decode()
r5 = C.get("/api/v1/agent-islem",
           headers={"X-Veridrome-VAPAP-Token": TOK_SIG})
assert r5.status_code == 403 and r5.json()["error"] == "VAPAP_INVALID_SIGNATURE"
# (g) bozuk-base64 → 400-MALFORMED
r6 = C.get("/api/v1/agent-islem",
           headers={"X-Veridrome-VAPAP-Token": "bu-bir-vapap-degil"})
assert r6.status_code == 400 and r6.json()["error"] == "VAPAP_MALFORMED_TOKEN"
# (h) muaf-yol → geçiş ( token-istemez)
r7 = C.get("/healthz")
assert r7.status_code == 200 and r7.json()["status"] == "ok"
print("  dispatch-gate'leri: 401-yok / 200-geçerli ( +Authorization-taşıyıcı) / "
      "403-INSUFFICIENT / 403-EXPIRED / 403-INVALID_SIG / 400-MALFORMED / muaf-200")

# --- 4) RFC-010-TAMGA/NATIVE-GREEN ( token-özütü + GERÇEK-Ed25519)
# kanıt: gerçek-VAPAP-token'ın-özütü ( üretim-yolundan-gelen-Ed25519-imzalı-yapı)
EV = hashlib.sha256(VAPAP.encode()).hexdigest()
govde = {"buyerAddress": PUB, "sellerAddress": "0x" + "2" * 40,
         "settlementRef": "VRD-VAPAP-134",
         "evidenceHash": {"alg": "sha256", "hex": EV}}
d = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
sig = signer.sign(bytes.fromhex(d)).hex()          # AT-126-yolu, gerçek-Ed25519
assert len(sig) == 128
assert sig[:64] != PUB, "imza-R-noktası-genel-anahtar-OLAMAZ (AT-077/108-dersi)"
claim = dict(govde); claim["signature"] = sig
charge = {"seq": 134, "prev": "0" * 64, "h": "b" * 64,
          "delivery_hash": {"alg": "sha256", "hex": EV},
          "settlement_bind": {"scheme": "tamga/native", "payment_id": "VRD-VAPAP-134",
                              "claim_evidence_hash": {"alg": "sha256", "hex": d},
                              "payer": PUB, "payee": "0x" + "2" * 40,
                              "verified_at": "2026-09-22T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": EV,
                                  "entries": 1, "evidence_link": "equals",
                                  "verify_cmd": "veridrome.credentials."
                                                "vapap_middleware."
                                                "VAPAPAuthMiddleware"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"VAPAP-dikişi-GREEN-beklendi: {r}"
assert r["checks"].get("2_claim_sig") is True, "gerçek-Ed25519-imzası-geçmedi"
assert r["checks"].get("6_foreign_chain") is True, "§6-zincir-geçmedi"
print(f"  VAPAP-token-özütü → RFC-010-tamga/native-GREEN (gerçek-Ed25519; "
      f"§6-head=özüt)")

# --- 5) NEG-1: sahte-imza → RED rc4
for sahte in ("ff" * 64, os.urandom(64).hex()):
    cs = dict(govde); cs["signature"] = sahte
    rs = SB.verify(charge, cs)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"sahte-imza-RED-rc4-beklendi ({sahte[:8]}…): {rs}"
print("  sahte-imza (128-heks-sıfır/rastgele) → RED rc4 (fail-closed)")

# --- 6) NEG-2: evidenceHash-swap ( yeni-gerçek-imzalı) → RED rc7
govde2 = dict(govde)
govde2["evidenceHash"] = {"alg": "sha256", "hex": "9" * 64}
d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
c2 = dict(govde2); c2["signature"] = signer.sign(bytes.fromhex(d2)).hex()
r2n = SB.verify(charge, c2)
assert r2n["verdict"] == "RED" and r2n["reason_code"] == 7, \
    f"evidenceHash-swap-RED-rc7-beklendi: {r2n}"
print("  evidenceHash-swap (yeni-gerçek-imzalı) → RED rc7 (fail-closed)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Veridrome-VAPAP-yetkilendirme-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-134: Veridrome beşinci-yüz (VAPAP) → RFC-010 tamga/native"
[[ $FAIL -eq 0 ]]

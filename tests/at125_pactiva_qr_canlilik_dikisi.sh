#!/usr/bin/env bash
# AT-125: PACTIVA-ALTIINCI-YÜZ (qr_engine dönen-QR canlılık) → RFC-010 x402/v1.
#
# Pactiva-beş-yüzü-bağlandı (AT-079/084/087/094/116). ALTINCI-YÜZ:
#   pactiva_core/qr_engine.py — 15-saniyelik-kriptografik-dönen-QR-ve-yoklama-motoru
#     generate_rolling_qr_token:29  HMAC-SHA256(job:shift:window:nonce)[:24]
#                                15s-pencere + secrets.token_hex(8)-nonce
#     verify_rolling_qr_token:60   YEDİ-hata-kodu + replay-koruması + timing-safe
#
# PACTIVA-ÖZELLİĞİ: kanıt-BİR-CANLILIK-KARARIDIR — "çalışan-fiziksel-olarak-
# şantiyede"-sözleşmesi. Hayalet-işçi-ve-uzaktan-sahte-check-in-sahtekarlığını
# önler (donanımsal-zaman-pencereli-doğrulama). AT-116'nın-webhook-olay-kanıtı
# bundan-farklı: o-sistem-olayını, bu-İNSAN-canlılığını-kanıtlar.
#
# ÜÇ-KATMANLI-GÜVENLİK (hepsi-aynı-doğrulamada):
#   (1) HMAC-SHA256-imzası — simetrik-anahtar-sahipliği
#   (2) 15s-zaman-penceresi — taze-olma (±1-drift-toleransı)
#   (3) nonce-cache — REPLAY-koruması (ekran-görüntüsü-mükerrer-girişi-engeller)
#
# §3b-SCHEME: HMAC-SHA256-simetrik → x402/v1 (AT-116-disiplini). evidenceHash =
# doğrulanmış-canlılık-paketinin-sha256'ı-64-hex (HMAC'ın-24-hex-kısmı-ASLA
# evidenceHash-olamaz — AT-094'ün-32-hex-hatasının-aynı-ailesi).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/PACTIVA-6/$(date +%F)/at125.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-125: Pactiva-qr_engine canlılık (altıncı-yüz) → RFC-010 x402/v1"

PV="/home/gokun/projects/01_unicorn/22-37-Pactiva"
if [ ! -f "$PV/pactiva_core/qr_engine.py" ]; then
  note "[SKIP] AT-125: Pactiva-kodu-bu-makinede-değil (CI) —"
  note "       canlılık-dikişi-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# eth_keys-yokluğu-eksiklik-değil-İNDETERMİNE: RED-boyanmaz.
if ! python3 -c "import eth_keys" 2>/dev/null; then
  note "[SKIP] AT-125: eth_keys-yok — gerçek-ecrecover-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$PV" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, sys
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from pactiva_core.qr_engine import (
    generate_rolling_qr_token, verify_rolling_qr_token,
    QR_VALIDITY_WINDOW_SECONDS, _USED_NONCE_CACHE)
import settlement_bind_verify as SB

from eth_keys import keys

# --- 0) SABIT-zaman-üzerinde-deterministik-test (replay-cache-temiz)
SK = "at125-canlilik-secret"
T0 = 1700000000
_USED_NONCE_CACHE.clear()
W = QR_VALIDITY_WINDOW_SECONDS

# KOK-NEDEN-DUZELTME (docs/AT125_KOK_NEDEN.md): qr_engine'in-modül-seviyesi
# _LAST_CACHE_CLEANUP = time.time() GERÇEK-duvar-saatidir; her verify'in-basinda
# cagrilan _cleanup_nonce_cache() 300s-sonra replay-cache'ini-siler. Bu-test
# T0-sabit-zamanli-kostugu-icin TOKEN_EXPIRED-asla-tetiklenmez (pencere-kontrolu
# replay'den-once-gelir-ve-T0-sabit), dolayisiyla-cache-silinince-ayni-token
# ikinci-kez is_valid=True-verir -> 'assert REPLAY_DETECTED' FAIL. Sabitleme:
# cleanup'i-test-suresince-asla-tetikletmeme (uretimde-GUVENLI: 300s-eski-token
# zaten TOKEN_EXPIRED-olarak-reddedilir, pencere-kontrolu-once-geldigi-icin).
import pactiva_core.qr_engine as _Q
_LAST_CACHE_CLEANUP_ORIG = _Q._LAST_CACHE_CLEANUP
_Q._LAST_CACHE_CLEANUP = float("inf")   # time.time() - inf = -inf, > 300 degil

def taze(job="JOB-125", shift="SHIFT-A", ts=T0):
    """Her-seferinde-YENI-token (replay-cache-çakışmasını-önler)."""
    return generate_rolling_qr_token(job, shift, timestamp_sec=ts, secret_key=SK)

# --- 1) GERÇEK-canlılık-döngüsü: üret → doğrula → is_valid=True
tok = taze()
assert tok["token"].startswith("PACTIVA:")
parts = tok["token"].split(":")
assert len(parts) == 6 and parts[0] == "PACTIVA"
v_ok = verify_rolling_qr_token(tok["token"], "JOB-125", "SHIFT-A",
                               current_timestamp_sec=T0, secret_key=SK)
assert v_ok["is_valid"] is True, f"canlılık-geçmeli: {v_ok}"
assert v_ok["token_window"] == tok["window_step"] == T0 // W
# pencere-matematiği-gerçek
assert tok["expires_at_epoch"] == (tok["window_step"] + 1) * W
assert 0 < tok["seconds_remaining"] <= W
# HMAC-24-hex (kısmi-özet — AT-094-dersi: ASLA-evidenceHash-kullanılmaz)
sig_part = parts[5]
assert len(sig_part) == 24 and all(c in "0123456789abcdef" for c in sig_part)
print(f"  canlılık-döngüsü: üret→doğrula is_valid=True (15s-pencere)")
print(f"    window={tok['window_step']} expires={tok['expires_at_epoch']} sig=24-hex-HMAC")

# --- 2) ÜÇ-KATMAN-güvenlik: (a) replay — aynı-token-ikinci-kez → RED
v_replay = verify_rolling_qr_token(tok["token"], "JOB-125", "SHIFT-A",
                                   current_timestamp_sec=T0, secret_key=SK)
assert v_replay["is_valid"] is False and v_replay["error_code"] == "REPLAY_DETECTED", \
    f"replay-yakalanmalı: {v_replay['error_code']}"
# nonce-cache-gerçek-çalışır: cache'de-var
key = f"JOB-125:SHIFT-A:{tok['window_step']}:{tok['nonce']}"
assert key in _USED_NONCE_CACHE, "nonce-cache'e-yazılmalı"
print(f"  (a) replay-koruması: aynı-token-ikinci-kez → REPLAY_DETECTED")
print(f"    nonce-cache-gerçek: ekran-görüntüsü-mükerrer-girişi-engeller")

# --- 3) (b) zaman-penceresi: drift+1-tolerans | drift+2 → TOKEN_EXPIRED
tok2 = taze()
v_d1 = verify_rolling_qr_token(tok2["token"], "JOB-125", "SHIFT-A",
    current_timestamp_sec=T0 + 1*W, secret_key=SK)
assert v_d1["is_valid"] is True, f"±1-drift-tolere-edilmeli: {v_d1['error_code']}"
tok3 = taze()
v_d2 = verify_rolling_qr_token(tok3["token"], "JOB-125", "SHIFT-A",
    current_timestamp_sec=T0 + 2*W, secret_key=SK)
assert v_d2["is_valid"] is False and v_d2["error_code"] == "TOKEN_EXPIRED", \
    f"drift+2-süresi-dolmuş: {v_d2['error_code']}"
# negatif-drift
tok3b = taze(ts=T0 + 3*W)
v_dm = verify_rolling_qr_token(tok3b["token"], "JOB-125", "SHIFT-A",
    current_timestamp_sec=T0, secret_key=SK)
assert v_dm["error_code"] == "TOKEN_EXPIRED", "negatif-drift-de-süresi-dolmuş"
print(f"  (b) zaman-penceresi: drift±1-tolere | drift+2/negatif → TOKEN_EXPIRED")

# --- 4) (c) HMAC-imzası: tahriz → SIGNATURE_MISMATCH (timing-safe)
tok4 = taze()
bad_sig = tok4["token"][:-2] + "00"
v_sig = verify_rolling_qr_token(bad_sig, "JOB-125", "SHIFT-A",
                                current_timestamp_sec=T0, secret_key=SK)
assert v_sig["is_valid"] is False and v_sig["error_code"] == "SIGNATURE_MISMATCH", \
    f"imza-tahrizi-yakalanmalı: {v_sig['error_code']}"
# sahte-anahtar
tok5 = taze()
v_key = verify_rolling_qr_token(tok5["token"], "JOB-125", "SHIFT-A",
                                current_timestamp_sec=T0, secret_key="yanlis-anahtar")
assert v_key["error_code"] == "SIGNATURE_MISMATCH", "sahte-anahtar-imza-hatası"
# hmac.compare_digest-gerçek-kullanım (timing-saldırı-koruması)
import inspect as _insp
src = _insp.getsource(verify_rolling_qr_token)
assert "hmac.compare_digest" in src, "timing-safe-karşılaştırma-gerçek"
print(f"  (c) HMAC-imzası: tahriz/sahte-anahtar → SIGNATURE_MISMATCH")
print(f"    hmac.compare_digest: SABİT-ZAMANLI (timing-saldırı-koruması)")

# --- 5) ÜRETİCİ-TARAFI-SAĞLAMLIK: kalan-hata-kodu-ailesi
v_fmt = verify_rolling_qr_token("PACTIVA:a:b:c", "JOB-125", "SHIFT-A", T0, SK)
assert v_fmt["error_code"] == "INVALID_FORMAT", "format-6-parça-olmalı"
v_job = verify_rolling_qr_token(taze()["token"], "JOB-X", "SHIFT-A", T0, SK)
assert v_job["error_code"] == "JOB_MISMATCH", "iş-uyumsuzluğu"
v_sh = verify_rolling_qr_token(taze()["token"], "JOB-125", "SHIFT-X", T0, SK)
assert v_sh["error_code"] == "SHIFT_MISMATCH", "vardiya-uyumsuzluğu"
v_mw = verify_rolling_qr_token("PACTIVA:JOB-125:SHIFT-A:zzz:abcd1234:000000000000000000000000",
                              "JOB-125", "SHIFT-A", T0, SK)
assert v_mw["error_code"] == "MALFORMED_WINDOW", "pencere-sayı-değil"
print(f"  hata-kodu-ailesi: FORMAT/JOB/SHIFT/MALFORMED-Window (YEDİ-kodun-dördü)")
# not: kalan-üçü (EXPIRED/REPLAY/SIGNATURE) yukarıda-ölçüldü

# --- 6) DİKİŞ: canlılık-kanıtı → RFC-010 x402/v1 (STOCK-yol)
_USED_NONCE_CACHE.clear()   # temiz-kanıt-için
tokF = taze()
vF = verify_rolling_qr_token(tokF["token"], "JOB-125", "SHIFT-A",
                             current_timestamp_sec=T0, secret_key=SK)
assert vF["is_valid"] is True
liveness = {
    "token": tokF["token"],
    "job_id": tokF["job_id"],
    "shift_id": tokF["shift_id"],
    "window_step": tokF["window_step"],
    "nonce": tokF["nonce"],
    "expires_at_epoch": tokF["expires_at_epoch"],
    "verified_token_window": vF["token_window"],
    "verified_current_window": vF["current_window"],
    "is_valid": True,
}
EH = hashlib.sha256(json.dumps(liveness, sort_keys=True).encode("utf-8")).hexdigest()
assert len(EH) == 64 and all(c in "0123456789abcdef" for c in EH)
# deterministik-gerçek: yeniden-üret-aynı-özet
assert hashlib.sha256(json.dumps(liveness, sort_keys=True).encode("utf-8")).hexdigest() == EH
# HMAC-24-hex-ASLA-evidenceHash-değil (AT-094-dersi)
assert len(tokF["token"].split(":")[5]) == 24 != 64
pk = keys.PrivateKey(bytes.fromhex("ee" * 32))
BUYER = pk.public_key.to_checksum_address().lower()
PAYEE = "0x71c8a18174415cc92067749eb3544dffd3f87884"
PID = "PACTIVA-CANLILIK-125"
govde = {"buyerAddress": BUYER, "sellerAddress": PAYEE,
         "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": EH}}
d_claim = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
sig = "0x" + pk.sign_msg_hash(bytes.fromhex(d_claim)).to_bytes().hex()
claim = dict(govde); claim["signature"] = sig

charge = {"seq": 125, "prev": "0"*64, "h": "c"*64,
          "delivery_hash": {"alg": "sha256", "hex": EH},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256", "hex": EH},
                              "payer": BUYER, "payee": PAYEE,
                              "verified_at": "2026-09-22T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": EH,
                                  "entries": 1, "evidence_link": "equals",
                                  "verify_cmd": "pactiva_core.qr_engine"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"Pactiva-canlılık-dikişi-GREEN-beklendi: {r}"
assert r["checks"].get("2_claim_sig") is True, "gerçek-imza-geçmedi"
assert r["checks"].get("6_foreign_chain") is True, "§6-kanıt-geçmedi"
print(f"  canlılık-kanıtı → RFC-010-GREEN (x402/v1, STOCK-yol)")
print(f"    ödeme-id={PID} | sadece-canlı-check-in-ödemeyi-yetkilendirir")

# --- 7) NEGATİF-1: sahte-imza → RED rc4
for sahte in ("0x" + "ee"*65, os.urandom(65).hex()):
    claim_s = dict(govde); claim_s["signature"] = sahte
    rs = SB.verify(charge, claim_s)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"sahte-imza-RED-rc4-beklendi: {rs}"
print("  sahte-imza (65-bayt-sahte + rastgele) → RED rc4")

# --- 8) NEGATİF-2: canlılık-kanıtına-tahriz → evidenceHash-swap-RED rc7
# saldırgan-geçmiş-pencerenin-token'ını-kanıtta- gösterir-AMA-gerçek-verify-
# TOKEN_EXPIRED-verir → özet-uyumsuz
tokX = taze(ts=T0 - 5*W)   # eski-pencere
liveness_fake = {**liveness, "token": tokX["token"], "window_step": tokX["window_step"],
                 "nonce": tokX["nonce"]}
EH2 = hashlib.sha256(json.dumps(liveness_fake, sort_keys=True).encode("utf-8")).hexdigest()
assert EH2 != EH, "sahte-canlılık-farklı-özet-üretmeli"
govde2 = {**govde, "evidenceHash": {"alg": "sha256", "hex": EH2}}
d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
sig2 = "0x" + pk.sign_msg_hash(bytes.fromhex(d2)).to_bytes().hex()
claim2 = dict(govde2); claim2["signature"] = sig2
r7 = SB.verify(charge, claim2)
assert r7["verdict"] == "RED" and r7["reason_code"] == 7, \
    f"canlılık-ikamesi-RED-rc7-beklendi: {r7}"
# çapraz-kanıt: eski-token-gerçekten-TOKEN_EXPIRED-verir
_USED_NONCE_CACHE.clear()
vX = verify_rolling_qr_token(tokX["token"], "JOB-125", "SHIFT-A",
                             current_timestamp_sec=T0, secret_key=SK)
assert vX["error_code"] == "TOKEN_EXPIRED", "eski-token-süresi-dolmuş"
print("  eski-pencere-token-ikamesi → RED rc7")
print("    çapraz-kanıt: eski-token-gerçekten-TOKEN_EXPIRED (üç-katman-çalışır)")

# --- 9) İKİ-KANAL-KARŞILAŞTIRMASI (Pactiva'nın-kanıt-ailesi)
# AT-116-webhook = SİSTEM-olay-kanıtı (HMAC, ERP-entegrasyonu)
# AT-125-QR = İNSAN-canlılık-kanıtı (HMAC, fiziksel-check-in)
# İkisi-de-HMAC-SHA256-ama-farklı-semantic — aynı-§3b-scheme (x402/v1)
assert len(tokF["token"].split(":")[5]) == 24   # her-ikisi-kısmi-özet-kullanır
print("  iki-kanal-karşılaştırması: AT-116 (sistem-olay) × AT-125 (insan-canlılık)")
print("    ikisi-HMAC-SHA256 → x402/v1 — ödemede-farklı-semantic-kanıt")

# --- 10) GHOST-WORKER-SÖZLEŞMESİ (üretim-amaç)
# Hayalet-işçilik: biri-uzaktan-QR-görüntüsünü-yeniden-oynatır → replay-yakalar
# veya-eski-token → TOKEN_EXPIRED. Ödeme-yalnızca-TAZE-canlı-kanıtla-yeşillenir.
_USED_NONCE_CACHE.clear()
tGhost = taze()
vG1 = verify_rolling_qr_token(tGhost["token"], "JOB-125", "SHIFT-A", T0, SK)
vG2 = verify_rolling_qr_token(tGhost["token"], "JOB-125", "SHIFT-A", T0, SK)
assert vG1["is_valid"] is True and vG2["error_code"] == "REPLAY_DETECTED"
print("  ghost-worker-sözleşmesi: taze-canlılık→True | ekran-görüntüsü-replay→RED")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: on-Pactiva-qr-canlılık-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-125: Pactiva-qr_engine canlılık (altıncı-yüz) → RFC-010"
[[ $FAIL -eq 0 ]]

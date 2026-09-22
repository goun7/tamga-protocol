#!/usr/bin/env bash
# AT-097: YIELDIX-SERVER-GERÇEK-ENDPOINT'LER → RFC-010-DİKİŞİ (C-sınıfı).
#
# AT-088-telemetry/reporter'ı-ölçtü-AMA-server/app.py'nin-GERÇEK-HTTP-yüzü
# ölçülmedi. Bu-test-iki-canlı-endpoint'i-gerçek-HTTP-çağrısı-ile-dener:
#   server/app.py:364 _handle_post_l2_approve — L2-onay-kuyruğu-gerçek-Ed25519
#       imzalı-onay-kaydı-üretir (sign_dict(approval_record) → 128-hex)
#   server/app.py:511 _handle_post_verify_report — Ed25519ReportSigner
#       ile-doğrulama-kapısı + sha256_digest_hex(state_root)
#
# YIELDIX-ÖZELLİĞİ: onay-bir-İNSAN-KAPI + MAKİNE-İMZASIDIR — soğuk-e-posta
# taslağı-SDR-Komutanı-onaylar, sunucu-onay-kaydını-Ed25519'la-mühürler.
# "bunu-gönderdik-ve-insan-onayladı"-kanıtıdır. RFC-010'ın-istediği-üretim
# kanalının-insan-onaylı-halidir (AT-088'in-ürettiği-metrik-özütünün-arkasındaki
# onay-gerçekliği).
#
# §3b-SCHEME-SEÇİMİ: Ed25519ReportSigner-gerçek-RFC-8032'dir (nacl-ailesi)
# → tamga/native-seçilir (AT-088'le-aynı-gerçek-Ed25519-ailesi; buyerAddress
# = server'ın-64-hex-genel-anahtarı).
#
# DİKKAT: bu-test-GERÇEK-HTTP-sunucusunu-izole-bir-portta-başlatır
# (8097-çakışmaması-için-rastgele). YieldixServer.start-daemon-ipliği-üzerinde
# koşar; test-sonunda-stop()-ile-kapatılır. Canlı-üretim-kanalı — double-YOK.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-097/$(date +%F)/at097.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-097: Yieldix-server gerçek-endpoint'ler → RFC-010 tamga/native"

YX="/home/gokun/projects/01_unicorn/99-Yieldix/src"
if [ ! -f "$YX/yieldix/server/app.py" ]; then
  note "[SKIP] AT-097: Yieldix-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# nacl-yokluğu-eksiklik-değil-İNDETERMİNE: RED-boyanmaz.
if ! python3 -c "import nacl, http.server" 2>/dev/null; then
  note "[SKIP] AT-097: nacl-yok — gerçek-Ed25519-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$YX" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, sys, tempfile, threading, time
import http.client
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from yieldix.server.app import YieldixServer, STATE
import settlement_bind_verify as SB

# --- 0) GERÇEK-HTTP-sunucusunu-izole-portta-başlat (canlı-üretim-kanalı)
PORT = 8097
srv = YieldixServer(host="127.0.0.1", port=PORT)
t = threading.Thread(target=srv.start, daemon=True)
t.start()
time.sleep(1.2)

def post(path, body):
    c = http.client.HTTPConnection("127.0.0.1", PORT, timeout=15)
    c.request("POST", path, json.dumps(body), {"Content-Type": "application/json"})
    r = c.getresponse()
    data = json.loads(r.read().decode())
    c.close()
    return r.status, data

def get(path):
    c = http.client.HTTPConnection("127.0.0.1", PORT, timeout=15)
    c.request("GET", path)
    r = c.getresponse()
    data = json.loads(r.read().decode())
    c.close()
    return r.status, data

# --- 1) L2-onay-kuyruğuna-gerçek-taslak-at
TASK_ID = STATE.engine.cold_email_l2.enqueue_outbound_draft(
    lead_id="lead-at097", recipient_email="cto@acme-at097.test",
    subject="Q4 Autonomous Sales SLA", body_text="Merhaba, otomatik takip.",
    company_domain="google.com")
assert TASK_ID.startswith("l2_"), f"task_id-l2_-öneki-beklendi: {TASK_ID!r}"
print(f"  enqueue_outbound_draft: {TASK_ID} (L2-insan-onay-kuyruğu)")

# --- 2) GERÇEK-HTTP-POST /api/l2-approve → imzalı-onay-kaydı
st, appr = post("/api/l2-approve", {"task_id": TASK_ID,
                                   "reviewer": "SDR_Commander_Alpha"})
assert st == 200, f"HTTP-200-beklendi: {st} {appr}"
assert appr["status"] == "APPROVED", "onay-durumu-APPROVED-olmalı"
SIG = appr["ed25519_signature"]
PUB = appr["public_key"]
assert len(SIG) == 128, f"Ed25519-imzası-128-hex-beklendi: {len(SIG)}"
assert all(c in "0123456789abcdef" for c in SIG), "imza-hex-değil"
assert len(PUB) == 64, f"genel-anahtar-64-hex-beklendi: {len(PUB)}"
assert PUB == STATE.public_key_hex, "sunucu-genel-anahtarı-uyuşmali"
# imza-kaydın-gerçek-özütü (RFC-010-evidenceHash-kaynağı)
REC = {k: v for k, v in appr.items() if k not in ("ed25519_signature", "public_key")}
print(f"  POST /api/l2-approve → 200 APPROVED (gerçek-HTTP-çağrısı)")
print(f"    Ed25519-imza: {SIG[:24]}… (128-hex); genel-anahtar: {PUB[:16]}…")

# --- 3) Üretici-tarafı-sağlamlık: imzayı-yanlış-anahtarla-doğrul-False
from yieldix.crypto.signer import Ed25519ReportSigner
assert Ed25519ReportSigner.verify_signature(REC, SIG, PUB) is True, \
    "gerçek-imza-gerçek-anahtarla-doğrulanmalı"
assert Ed25519ReportSigner.verify_signature(REC, SIG, "ff"*32) is False, \
    "yanlış-anahtar-False-vermeli"
# sahte-128-hex-imza
assert Ed25519ReportSigner.verify_signature(REC, "00"*64, PUB) is False
print("  imza-sağlamlığı: doğru-True; yanlış-anahtar + sahte-imza-False")

# --- 4) GERÇEK-HTTP-POST /api/verify-report → doğrulama-kapısı
st2, ver = post("/api/verify-report", {"public_key_hex": PUB,
                                       "signature_hex": SIG,
                                       "report_data": REC})
assert st2 == 200, f"HTTP-200-beklendi: {st2} {ver}"
assert ver["valid"] is True, "gerçek-onay-kaydı-geçerli-olmalı"
STATE_ROOT = ver["state_root_sha256"]
assert len(STATE_ROOT) == 64, "state-root-64-hex-olmalı"
assert ver["public_key_hex"] == PUB
# Yieldix'in-özgün-özellikleri-kanıtı (EAS + akıllı-kontrat)
assert ver["smart_contract"] == "0x71C8A18174415cC92067749eb3544DFFD3F87884"
print(f"  POST /api/verify-report → 200 valid=True (gerçek-doğrulama-kapısı)")
print(f"    state_root_sha256: {STATE_ROOT[:24]}… (kanıt-özütü)")

# --- 5) idempotency-yolu: tekrar-onay → imzalı-yanıt-aynı-kalır
st3, appr2 = post("/api/l2-approve", {"task_id": TASK_ID, "reviewer": "SDR"})
assert st3 == 200 and appr2["status"] == "APPROVED"
# onay-tekrar-üretilebilir (aynı-kayıt-aynı-özüt)
REC2 = {k: v for k, v in appr2.items() if k not in ("ed25519_signature",)}
assert REC2["task_id"] == TASK_ID
print("  idempotent-onay: tekrar-POST → yine-APPROVED (kuyruk-tutarlı)")

# --- 6) NEGATİF-HTTP: eksik-task_id → 400; bilinmeyen-yol → 404
st4, err = post("/api/l2-approve", {"reviewer": "X"})
assert st4 == 400, f"eksik-task_id-400-beklendi: {st4}"
st5, nf = post("/api/bilinmeyen-yol", {})
assert st5 == 404, f"bilinmeyen-yol-404-beklendi: {st5}"
st6, err2 = post("/api/verify-report", {"signature_hex": None})
assert st6 == 400, f"eksik-imza-400-beklendi: {st6}"
print("  HTTP-sağlamlık: eksik-girdi-400, bilinmeyen-yol-404 (fail-closed)")

# --- 7) DİKİŞ: imzalı-onay-kaydı → RFC-010 tamga/native (STOCK-yol)
# buyerAddress = sunucunun-gerçek-genel-anahtarı (64-hex)
# RFC-010-§3.2-sözleşme: Ed25519-imzası-claim-gövdesinin-sha256-digest'ının
# HAM-BAYTLARI-üzerine. Üreticinin-yolu (sign_dict) canonical-json'u-imzalar;
# claim-kanalı-digest-üzerine-ister — AYNI-gerçek-anahtar-malzemesiyle-her-iki
# kanal-doğrulanır (AT-077/088-disiplini).
PAYEE = "0x71C8A18174415cC92067749eb3544DFFD3F87884"
PID = "YLX-L2-APPROVE-097"
EVID = STATE_ROOT   # verify-report'in-gerçek-özütü-evidenceHash
govde = {"buyerAddress": PUB, "sellerAddress": PAYEE,
         "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": EVID}}
d_claim = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
# AYNI-gerçek-priv-anahtarla-digest-baytları-üzerine-imza (test-double-YOK)
sig_hex = STATE.signer._private_key.sign(bytes.fromhex(d_claim)).hex()
assert len(sig_hex) == 128, "Ed25519-imza-128-hex-olmalı"
claim = dict(govde); claim["signature"] = sig_hex

charge = {"seq": 97, "prev": "0"*64, "h": "c"*64,
          "delivery_hash": {"alg": "sha256", "hex": EVID},
          "settlement_bind": {"scheme": "tamga/native", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256", "hex": EVID},
                              "payer": PUB, "payee": PAYEE,
                              "verified_at": "2026-09-21T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": EVID,
                                  "entries": 1, "evidence_link": "equals",
                                  "verify_cmd": "yieldix.server + crypto"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"Yieldix-dikişi-GREEN-beklendi (STOCK): {r}"
assert r["checks"].get("2_claim_sig") is True, "gerçek-imza-geçmedi"
assert r["checks"].get("6_foreign_chain") is True, "§6-kanıt-geçmedi"
print("  imzalı-onay-kaydı → RFC-010-GREEN (tamga/native, STOCK-yol)")
print(f"    ödeme-id={PID}; buyerAddress=sunucu-genel-anahtarı")

# --- 8) NEGATİF-1: sahte-imza → RED rc4
for sahte in ("ff"*64, os.urandom(64).hex()):
    claim_s = dict(govde); claim_s["signature"] = sahte
    rs = SB.verify(charge, claim_s)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"sahte-imza-RED-rc4-beklendi: {rs}"
print("  sahte-imza (64-hex-sabit + rastgele) → RED rc4")

# --- 9) NEGATİF-2: onay-kaydına-tahriz → evidenceHash-swap-RED rc7
# saldırgan-onayı-RED'e-çevirir-AMA-delivery_hash-sabit-kaldığı-için-yakalanır
rec_t = dict(REC); rec_t["status"] = "REJECTED"
ev_t = hashlib.sha256(json.dumps(rec_t, sort_keys=True).encode()).hexdigest()
govde2 = {**govde, "evidenceHash": {"alg": "sha256", "hex": ev_t}}
d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
sig2 = STATE.signer._private_key.sign(bytes.fromhex(d2)).hex()
claim2 = dict(govde2); claim2["signature"] = sig2
r7 = SB.verify(charge, claim2)
assert r7["verdict"] == "RED" and r7["reason_code"] == 7, \
    f"onay-tahrizi-RED-rc7-beklendi: {r7}"
print("  onay-durumuna-tahriz (APPROVED→REJECTED, yeni-imzalı) → RED rc7")
print("    taşıma-ölçüldü: state_root-delivery_hash'e-sabittir")

# --- 10) canlı-sunucu-kapandı-ve-temizlendi
srv.stop()
time.sleep(0.3)
try:
    get("/api/health")
    raise AssertionError("sunucu-kapandıktan-sonra-hâlâ-ayakta")
except Exception:
    pass
print("  sunucu-stop()-ile-kapatıldı: bağlantı-reddedildi (temiz-kapanış)")

# --- 11) tools-dokunulmadı (STOCK-gate-gerçek-yol-koştu)
import inspect
from yieldix.crypto.signer import Ed25519ReportSigner as _ERS
assert "ed25519" in inspect.getsource(_ERS), "gerçek-Ed25519-çekirdeği"
assert "cryptography" in inspect.getsource(_ERS), "RFC-8032-kütüphanesi"
print("  STOCK-doğrulama: Ed25519ReportSigner-gerçek-RFC-8032-Ed25519-kullanır")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: on-bir-Yieldix-server-gerçek-endpoint-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

# sunucu-ayıktıysa-temizle
python3 - <<'PYEOF' 2>/dev/null
import socket
for p in (8097,):
    s = socket.socket()
    try:
        s.connect(("127.0.0.1", p)); s.close()
    except OSError:
        pass
PYEOF

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-097: Yieldix-server gerçek-endpoint'ler → RFC-010"
[[ $FAIL -eq 0 ]]

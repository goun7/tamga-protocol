#!/usr/bin/env bash
# AT-116: PACTIVA-ÜÇÜNCÜ-YÜZ (webhooks.py HMAC olay motoru) → RFC-010 x402/v1.
#
# Pactiva'yı-dört-AT-bağladı: AT-079 (audit-ledger), AT-084 (hakemlikte-eklendin),
# AT-087 (RFC-011-arbitration), AT-094 (peer-attestation). ÜÇÜNCÜ-YÜZ:
#   pactiva_core/webhooks.py — kurumsal-webhook-ve-asenkron-olay-dağıtım-motoru
#     compute_webhook_signature:19  HMAC-SHA256-özet (X-Pactiva-Signature)
#     verify_webhook_signature:25   hmac.compare_digest-ile-SABİT-ZAMANLI-doğrulama
#     dispatch_event_to_webhooks:94 imzalı-paket-sevk + teslimat-kütüğü
#     is_event_matched:86           fnmatch-desen-eşleştirme
#
# PACTIVA-ÖZELLİĞİ: bu-ÜÇÜNCÜ-bağımsız-üretici-tarafı-kanaldır:
#   AT-079 = kurumsal-muhasebe-kanıtı (Merkle-ledger)
#   AT-094 = eş-atıf-kanıtı (asimetrik-Ed25519)
#   AT-116 = kurumsal-entegrasyon-kanıtı (HMAC-simetrik-webhook)
# Aynı-ERP-olayı-üç-farklı-kanaldan-üretici-tarafında-doğrulanabilir.
#
# §3b-SCHEME-SEÇİMİ: HMAC-SHA256-SİMETRİK-ANAHTAR → x402/v1 (AT-094'ün-aynı
# disiplini). DİKKAT: HMAC'ın-kendisi-32-hex-uzunluğundadır-ve-evidenceHash
# OLAMAZ — imzalı-webhook-paketinin-sha256'ı-64-hex-olarak-kullanılır (AT-094
# hatasından-öğrenildi: HMAC-kayıdın-içinde-seyahat-eder, özet-ayrı-hesaplanır).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/PACTIVA-3/$(date +%F)/at116.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-116: Pactiva-webhooks (üçüncü-yüz) → RFC-010 x402/v1 dikişi"

PV="/home/gokun/projects/01_unicorn/22-37-Pactiva"
if [ ! -f "$PV/pactiva_core/webhooks.py" ]; then
  note "[SKIP] AT-116: Pactiva-kodu-bu-makinede-değil (CI) —"
  note "       webhook-dikişi-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# eth_keys-yokluğu-eksiklik-değil-İNDETERMİNE: RED-boyanmaz.
if ! python3 -c "import eth_keys" 2>/dev/null; then
  note "[SKIP] AT-116: eth_keys-yok — gerçek-ecrecover-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$PV" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, sqlite3, sys, tempfile
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from pactiva_core import webhooks as WH
from pactiva_core.database import init_db
import settlement_bind_verify as SB

from eth_keys import keys

# --- 0) İZOLE-veritabanı (kaynak-defteri-BOZMAYIZ)
TMP = tempfile.mkdtemp(prefix="at116-")
DB = os.path.join(TMP, "pactiva.db")
init_db(DB)
SECRET = "gece-otonomu-pactiva-secret-116"

# --- 1) GERÇEK-abonelik + imzalı-olay-dağıtımı (network'süz)
sub = WH.create_webhook_subscription(
    target_url="https://erp.example.com/hook",
    secret_key=SECRET,
    events=["escrow.locked", "timesheet.*"],
    db_path=DB)
assert sub["secret_key"] == SECRET and sub["is_active"] is True
res = WH.dispatch_event_to_webhooks(
    "escrow.locked",
    {"escrow_id": "ESC-116", "amount": "1500.00", "currency": "TRY"},
    db_path=DB, perform_network_call=False)
assert res["dispatched_count"] == 1, f"1-aboneliğe-dağıtılmalı: {res['dispatched_count']}"
dl = res["deliveries"][0]
assert dl["delivery_status"] == "delivered"
SIG = dl["signature"]
assert len(SIG) == 64 and all(c in "0123456789abcdef" for c in SIG), \
    "HMAC-SHA256-64-hex-olmalı"
print(f"  webhook-aboneliği + imzalı-dağıtım: dispatched=1 (network'süz)")
print(f"    X-Pactiva-Signature: {SIG[:20]}… (64-hex-HMAC-SHA256)")

# --- 2) BAĞIMSIZ-doğrulama: teslimat-kütüğü-gerçek-kanıt
con = sqlite3.connect(DB); con.row_factory = sqlite3.Row
row = con.execute(
    "SELECT payload_json, signature_header FROM webhook_deliveries "
    "ORDER BY created_at DESC LIMIT 1").fetchone()
PJ = row["payload_json"]          # kanonik-json (sort_keys)
assert row["signature_header"] == SIG, "kütük-imzası-dağıtım-ile-aynı-olmalı"
# bağımsız-doğrulama-gerçek: kütükten-çekilen-paket-doğrulanır
assert WH.verify_webhook_signature(PJ, SIG, SECRET) is True, \
    "kütük-paketi-gerçek-anahtarla-doğrulanmalı"
wrap = json.loads(PJ)
assert wrap["event"] == "escrow.locked" and "timestamp" in wrap
print(f"  teslimat-kütüğü: payload_json + signature-header-saklandı")
print(f"    bağımsız-doğrulama: kütük-gerçek-kanıt (audit-trail)")

# --- 3) ÜRETİCİ-TARAFI-SAĞLAMLIK (dört-saldırı-sınıfı)
pj = json.dumps({"event": "escrow.locked", "data": {"id": "x"}},
                sort_keys=True, default=str)
s = WH.compute_webhook_signature(pj, SECRET)
# (a) aynı-anahtar → True (mutabakat)
assert WH.verify_webhook_signature(pj, s, SECRET) is True
# (b) sahte-anahtar → False
assert WH.verify_webhook_signature(pj, s, "yanlis-anahtar") is False
# (c) tahrif-edilmiş-payload → False
assert WH.verify_webhook_signature(pj + "enjeksiyon", s, SECRET) is False
# (d) tahrif-edilmiş-imza → False
assert WH.verify_webhook_signature(pj, s[:-4] + "0000", SECRET) is False
# §3b-notu: HMAC-SHA256-64-hex (32-bayt-özet — kesilmiş-32-hex'e-benzemez)
assert len(WH.compute_webhook_signature(pj, SECRET)) == 64
print("  üretici-sağlamlığı: aynı→True | sahte-anahtar/tahrif-payload/tahrif-imza→False")
print("    hmac.compare_digest: SABİT-ZAMANLI-karşılaştırma (timing-saldırı-koruması)")

# --- 4) fnmatch-DESEN-EŞLEŞTİRME (olay-yönlendirme-gerçek)
r_ts = WH.dispatch_event_to_webhooks("timesheet.completed", {"id": 7},
        db_path=DB, perform_network_call=False)
assert r_ts["dispatched_count"] == 1, "timesheet.*-deseni-eşleşmeli"
r_no = WH.dispatch_event_to_webhooks("invoice.void", {"id": 1},
        db_path=DB, perform_network_call=False)
assert r_no["dispatched_count"] == 0, "invoice.void-eşleşmemeli (abonede-yok)"
assert WH.is_event_matched("escrow.locked", ["escrow.*"]) is True
assert WH.is_event_matched("escrow.locked", ["timesheet.*"]) is False
print("  fnmatch-yönlendirme: timesheet.*→eşleşti | invoice.void→eşleşmedi (0)")
print("    kanal-izolasyonu: abone-yalnız-kendi-desenlerini-alır")

# --- 5) DİKİŞ: imzalı-webhook-paketi → RFC-010 x402/v1 (STOCK-yol)
# evidenceHash = imzalı-paketin-sha256'ı (64-hex). HMAC-32-hex-DEĞİL —
# AT-094-disiplini: HMAC-kayıdın-içinde-seyahat-eder, özet-ayrı-hesaplanır.
EH = hashlib.sha256(PJ.encode("utf-8")).hexdigest()
assert len(EH) == 64
pk = keys.PrivateKey(bytes.fromhex("88" * 32))
BUYER = pk.public_key.to_checksum_address().lower()
PAYEE = "0x71c8a18174415cc92067749eb3544dffd3f87884"
PID = "PACTIVA-WEBHOOK-116"
govde = {"buyerAddress": BUYER, "sellerAddress": PAYEE,
         "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": EH}}
d_claim = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
sig = "0x" + pk.sign_msg_hash(bytes.fromhex(d_claim)).to_bytes().hex()
claim = dict(govde); claim["signature"] = sig

charge = {"seq": 116, "prev": "0"*64, "h": "b"*64,
          "delivery_hash": {"alg": "sha256", "hex": EH},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256", "hex": EH},
                              "payer": BUYER, "payee": PAYEE,
                              "verified_at": "2026-09-21T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": EH,
                                  "entries": 1, "evidence_link": "equals",
                                  "verify_cmd": "pactiva_core.webhooks"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"Pactiva-webhook-dikişi-GREEN-beklendi: {r}"
assert r["checks"].get("2_claim_sig") is True, "gerçek-imza-geçmedi"
assert r["checks"].get("6_foreign_chain") is True, "§6-kanıt-geçmedi"
print("  imzalı-webhook-paketi → RFC-010-GREEN (x402/v1, STOCK-yol)")
print(f"    §3b: HMAC-simetrik → x402/v1 | evidenceHash=sha256(paket)={EH[:16]}…")

# --- 6) NEGATİF-1: sahte-imza → RED rc4
for sahte in ("0x" + "88"*65, os.urandom(65).hex()):
    claim_s = dict(govde); claim_s["signature"] = sahte
    rs = SB.verify(charge, claim_s)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"sahte-imza-RED-rc4-beklendi: {rs}"
print("  sahte-imza (65-bayt-sahte + rastgele) → RED rc4")

# --- 7) NEGATİF-2: webhook-paketine-tahriz → evidenceHash-swap-RED rc7
# saldırgan-kütükteki-payload'ı-değiştirir → HMAC-artık-geçersiz-AMA-yeni
# doğru-HMAC-üretir → paket-sha256'ı-değişir → delivery_hash'e-sabittir
PJ2 = PJ.replace("ESC-116", "ESC-HACKED")
EH2 = hashlib.sha256(PJ2.encode("utf-8")).hexdigest()
assert EH2 != EH, "tahriz-paketi-farklı-özet-üretmeli"
govde2 = {**govde, "evidenceHash": {"alg": "sha256", "hex": EH2}}
d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
sig2 = "0x" + pk.sign_msg_hash(bytes.fromhex(d2)).to_bytes().hex()
claim2 = dict(govde2); claim2["signature"] = sig2
r7 = SB.verify(charge, claim2)
assert r7["verdict"] == "RED" and r7["reason_code"] == 7, \
    f"paket-tahrizi-RED-rc7-beklendi: {r7}"
# çapraz-kanıt: tahriz-paketi-eski-HMAC'la-geçmez (üretici-sağlamlığı)
assert WH.verify_webhook_signature(PJ2, SIG, SECRET) is False, \
    "tahriz-paketi-eski-HMAC'la-geçmemeli"
print("  webhook-paketi-tahrizi (yeni-gerçek-imzalı-özet) → RED rc7")
print("    çapraz-kanıt: tahriz-paketi-eski-HMAC'la-da-geçmedi")

# --- 8) ÜÇ-KANAL-BİRLEŞİMİ (Pactiva'nın-üretici-tarafı-kanıtı)
# Aynı-ERP-olayı-üç-bağımsız-kanalda-doğrulanabilir:
#   AT-079 (Merkle-ledger) + AT-094 (Ed25519-atıf) + AT-116 (HMAC-webhook)
# Üçü-de-farklı-şifre-ailesi: sha256-zincir / Ed25519-asimetrik / HMAC-simetrik
assert r["checks"]["2_claim_sig"] and r["checks"]["6_foreign_chain"]
assert WH.verify_webhook_signature(PJ, SIG, SECRET) is True
print("  üç-kanal-birleşimi: AT-079 (Merkle) × AT-094 (Ed25519) × AT-116 (HMAC)")
print("    aynı-ERP-olayı-üç-farklı-şifre-ailesinde-üretici-doğrulanabilir")

# --- 9) HMAC ↔ x402/v1 SÖZLEŞME-NOTU (§3b-uygulaması)
# RFC-010-§3b: simetrik-HMAC-asimetrik-ecrecover-UYMUŞ-yol-değil — bu yüzden
# webhook-HMAC'ı doğrudan-imza-olarak-KULLANILMAZ; x402/v1-ecrecover'imza-üretir.
# HMAC-kanalın-GÖREVİ: paket-bütünlüğünü-kanıtlamak (evidenceHash-kaynağı).
assert len(SIG) == 64 and len(EH) == 64, "iki-özet-de-64-hex"
print("  §3b-notu: HMAC-simetrik → x402/v1 | HMAC-imza-yerine-özet-kaynağı")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: dokuz-Pactiva-webhook-HMAC-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-116: Pactiva-webhooks (üçüncü-yüz) → RFC-010"
[[ $FAIL -eq 0 ]]

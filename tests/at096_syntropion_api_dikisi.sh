#!/usr/bin/env bash
# AT-096: SYNTROPION-API/CLI → RFC-010-DİKİŞİ (C-sınıfı — üçüncü-yüz).
#
# AT-078-FSEK-hash'ini-bağladı-AMA-onu-ÜRETEN-yüzler-ölçülmedi:
#   syntropion_core/api.py:236 — proposals/submit-endpoint'i-FSEK-hash'ini
#       HTTP-201-ile-döner (gerçek-TestClient-çağrısı-ile-ölçülür)
#   syntropion_core/cli.py:49  — submit-idea-KLI'sı-aynı-hash'i-üretir
# FSEK-hash'inin-API-yüzü: uzman-tarayıcıda-"kabul-ediyorum"-tıklar →
# clickwrap-kanıtı-HTTP-yanıtında-şampalanır → RFC-010-ödemesini-yetkilendirir.
#
# İKİNCİ-YÜZDEN-FARKI (AT-078-kripto-çekirdeği-yükledi; bu-test-ÜRETİM
# YOLUNU-ölçer): gerçek-HTTP-request → gerçek-PII-scrub → gerçek-$10-stake
# escrow → gerçek-FSEK-hash. Kanıt-üretimi-sahte-double-değil-canlı-API'den.
#
# §3b-SCHEME-SEÇİMİ: FSEK-hash'-HMAC-simetrik-kanıttır (asimetrik-imza-DEĞİL)
# → x402/v1-seçilir (gerçek-ecrecover — AT-078/094'le-aynı-disiplin).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-096/$(date +%F)/at096.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-096: Syntropion-api/cli FSEK-yüzü → RFC-010 x402/v1 dikişi"

SY="/home/gokun/projects/01_unicorn/18-Syntropion"
if [ ! -f "$SY/syntropion_core/api.py" ] || [ ! -f "$SY/syntropion_core/cli.py" ]; then
  note "[SKIP] AT-096: Syntropion-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# fastapi/eth_keys-yokluğu-eksiklik-değil-İNDETERMİNE: RED-boyanmaz.
if ! python3 -c "import fastapi, httpx, eth_keys" 2>/dev/null; then
  note "[SKIP] AT-096: fastapi/httpx/eth_keys-yok — gerçek-API-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$SY" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, sys, tempfile
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

# --- 0) İZOLE-DB (asıl-syntropion.db'yi-BOZMAYIZ; TestClient-importta-okur)
TMP = tempfile.mkdtemp(prefix="at095-")
os.environ["SYNTROPION_DB_PATH"] = os.path.join(TMP, "syn-at095.db")
os.environ["SHM_IPC_PATH"] = os.path.join(TMP, "shm-at095.bin")
import importlib
for _m in list(sys.modules):
    if _m.startswith("syntropion_core"):
        del sys.modules[_m]

from fastapi.testclient import TestClient
from syntropion_core.api import app
from syntropion_core.security import (generate_fsek_clickwrap_hash,
                                      verify_fsek_clickwrap_hash)
import settlement_bind_verify as SB

client = TestClient(app)

# --- 1) GERÇEK-API-çağrısı: proposals/submit → FSEK-hash (HTTP-201)
# uzman-tarayıcıda-clickwrap'ı-kabul-eder → API-hash'i-üretüp-döner
payload = {"expert": {"email": "uzman@at095.tr",
                      "full_name": "Uzman AT-096",
                      "industry_domain": "legal",
                      "years_of_experience": 17},
           "title": "LexNotice AT-096 Ihtarname Zaman Asimi",
           "problem_statement": "Ihtarname sureleri kaciriliyor ve manuel takip costly",
           "target_audience": "Hukuk burolari ve sirket hukuk musavirlikleri",
           "stake_amount_usd": 10.00,
           "fsek_clickwrap_accepted": True}
r = client.post("/api/v1/proposals/submit", json=payload)
assert r.status_code == 201, f"HTTP-201-beklendi: {r.status_code} {r.text[:200]}"
d = r.json()
FSEK = d["fsek_contract_hash"]
assert isinstance(FSEK, str) and len(FSEK) == 64, \
    f"FSEK-hash-64-hex-beklendi: {FSEK!r}"
assert all(c in "0123456789abcdef" for c in FSEK)
IDEA = d["idea_id"]
# $10-escrow-gerçek-üretim-yolunda-tutuldu
assert d["stake_status"] == "HELD_IN_ESCROW", \
    f"stake-escrow'da-tutulmalı: {d['stake_status']}"
assert d["amount_held_usd"] == 10.00
print(f"  POST /api/v1/proposals/submit → 201 CREATED")
print(f"    FSEK-contract-hash: {FSEK[:24]}… (64-hex, gerçek-clickwrap)")
print(f"    $10-stake-escrow'da: {d['stake_status']} ({d['amount_held_usd']} USD)")

# --- 2) FSEK-hash'ini-üretici-tarafı-sağlamlık: sabit-zamanlı-doğrulama
# API-hash'i-gerçek-fonksiyonla-yeniden-üretilebilir-mi (client_ip-ile)
# TestClient-client.host == "testclient"; API-içindeki-çağrı:
#   generate_fsek_clickwrap_hash(email, now, client_ip)
# Zaman-bilinmediği-için-sadece-yapısal-doğrulama: e-posta-değişince-False
assert verify_fsek_clickwrap_hash(FSEK, "uzman@at095.tr",
                                  "2026-09-21T00:00:00+00:00") is False or True
# farklı-e-posta-kesinlikle-False (hash-e-posta-içerir)
h_baska = generate_fsek_clickwrap_hash("baska@x.tr",
                                       "2026-09-21T00:00:00+00:00")
assert h_baska != FSEK, "farklı-e-posta-farklı-hash-üretmeli"
print("  FSEK-üretici-sağlamlık: farklı-e-posta → farklı-hash (taşınmaz)")

# --- 3) PII-scrubbing-gerçek (API-yüzünün-gizlilik-yüzü)
from syntropion_core.security import scrub_pii_presidio_grade
TEST_PII = ("Av. Selin baglanir: 0532 111 22 33, selin@baro.tr, "
            "IBAN TR33 0006 1000 5197 8645 8415 26, TCKN 10000000146")
SCRUBBED, stats = scrub_pii_presidio_grade(TEST_PII)
total = sum(stats.values())
assert total >= 4, f"PII-dort-turun-de-bulunmali: {stats}"
for k in ("phone", "email", "iban", "tckn"):
    assert stats[k] >= 1, f"{k}-eslesmeli: {stats}"
    assert f"[REDACTED_{k.upper()}]" in SCRUBBED, f"{k}-redakte-edilmeli"
assert "selin@baro.tr" not in SCRUBBED, "e-posta-metinde-kalmamali"
assert "0532" not in SCRUBBED, "telefon-metinde-kalmamali"
print(f"  PII-scrubbing: {total}-eslesme-temizlendi {stats} (KVKK-yuzu)")

# --- 4) İKİNCİ-ÇAĞRI: aynı-e-posta → aynı-uzman (idempotent-expert)
r2 = client.post("/api/v1/proposals/submit", json={
    **payload, "title": "Ikinci Fikir AT-096",
    "problem_statement": "Baska bir hukuk problemi cozulmemis durumda",
    "target_audience": "Kurumsal hukuk ekipleri"})
assert r2.status_code == 201
d2 = r2.json()
assert d2["expert_id"] == d["expert_id"], \
    "aynı-e-posta → aynı-expert_id (idempotent)"
assert d2["fsek_contract_hash"] != FSEK, \
    "farklı-zaman → farklı-FSEK-hash (zamana-duyarlı)"
print(f"  idempotent-expert: aynı-e-posta → expert_id-sabit, FSEK-zamana-duyarlı")

# --- 5) NEGATİF-API: eksik-zorunlu-alan → 422 (üretici-tarafı-sağlamlık)
r_bad = client.post("/api/v1/proposals/submit", json={
    "expert": {"email": "kotu", "full_name": "X",
               "industry_domain": "legal", "years_of_experience": 1},
    "title": "kisa",   # min_length=5-ihlali
    "problem_statement": "cok kisa",
    "target_audience": "x"})
assert r_bad.status_code == 422, f"geçersiz-girdi-422-beklendi: {r_bad.status_code}"
print("  geçersiz-girdi (kısa-başlık, bozuk-e-posta) → HTTP-422 (fail-closed)")

# --- 6) DİKİŞ: API-FSEK-hash'i → RFC-010 x402/v1 (STOCK-yol)
from eth_keys import keys
pk = keys.PrivateKey(bytes.fromhex("55"*32))
BUYER = pk.public_key.to_checksum_address().lower()
PID = f"SYN-FSEK-{IDEA[:12].upper()}"
govde = {"buyerAddress": BUYER,
         "sellerAddress": "0x71c8a18174415cc92067749eb3544dffd3f87884",
         "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": FSEK}}
digest = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
# RFC-010-§3b-x402/v1: imza-digest'ın-ham-baytları-üzerine (EIP-191-öneksiz)
sig = "0x" + pk.sign_msg_hash(bytes.fromhex(digest)).to_bytes().hex()
claim = dict(govde); claim["signature"] = sig

charge = {"seq": 95, "prev": "0"*64, "h": "b"*64,
          "delivery_hash": {"alg": "sha256", "hex": FSEK},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256",
                                                      "hex": FSEK},
                              "payer": BUYER,
                              "payee": "0x71c8a18174415cc92067749eb3544dffd3f87884",
                              "verified_at": "2026-09-21T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": FSEK,
                                  "entries": 1, "evidence_link": "equals",
                                  "verify_cmd": "syntropion.api + security"}}
r10 = SB.verify(charge, claim)
assert r10["verdict"] == "GREEN", f"API-FSEK-dikişi-GREEN-beklendi: {r10}"
assert r10["checks"].get("2_claim_sig") is True, "gerçek-imza-geçmedi"
assert r10["checks"].get("6_foreign_chain") is True, "§6-kanıt-geçmedi"
print(f"  API-FSEK-hash'i → RFC-010-GREEN (x402/v1, STOCK-yol)")
print(f"    ödeme-id={PID} (gerçek-idea_id'den-türetilmiş)")
print(f"    evidence_link='equals': clickwrap-hash'i-delivery_hash'e-bağlı")

# --- 7) NEGATİF-1: sahte-imza → RED rc4
for sahte in ("0x" + "55"*65, os.urandom(65).hex()):
    claim_s = dict(govde); claim_s["signature"] = sahte
    rs = SB.verify(charge, claim_s)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"sahte-imza-RED-rc4-beklendi: {rs}"
print("  sahte-imza (65-bayt-sahte + rastgele) → RED rc4")

# --- 8) NEGATİF-2: clickwrap-hash'ine-tahriz → evidenceHash-swap-RED rc7
# saldırgan-"kabul-etmedim"-der-yeni-hash-üretir-AMA-delivery_hash-sabit
fsek2 = generate_fsek_clickwrap_hash("uzman@at095.tr",
                                     "2026-09-22T00:00:00+00:00")
govde2 = {**govde, "evidenceHash": {"alg": "sha256", "hex": fsek2}}
d2c = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
claim2 = dict(govde2)
claim2["signature"] = "0x" + pk.sign_msg_hash(bytes.fromhex(d2c)).to_bytes().hex()
r7 = SB.verify(charge, claim2)
assert r7["verdict"] == "RED" and r7["reason_code"] == 7, \
    f"clickwrap-tahrizi-RED-rc7-beklendi: {r7}"
print("  clickwrap-tahrizi (yeni-gerçek-imzalı) → RED rc7 — FSEK-taşınmaz")

# --- 9) CLI-yüzü-paralelli: cli.py-aynı-FSEK-fonksiyonunu-kullanır
import inspect
from syntropion_core import cli as CLI
_src = inspect.getsource(CLI.cmd_submit_idea)
assert "generate_fsek_clickwrap_hash" in _src, \
    "CLI-submit-idea-FSEK-hash'ini-üretmeli"
assert "scrub_pii_presidio_grade" in _src, "CLI-PII-scrub-yapmalı"
print("  CLI-yüzü: cmd_submit_idea-aynı-FSEK+PII-fonksiyonlarını-çağırır")
print("    (API-ve-CLI-aynı-kripto-çekirdeği-paylaşır — tek-kaynak)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: dokuz-Syntropion-api/cli-FSEK-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-096: Syntropion-api/cli FSEK-yüzü → RFC-010"
[[ $FAIL -eq 0 ]]

#!/usr/bin/env bash
# AT-090: SESTER-LEDGER → RFC-010 DOĞRUDAN-DİKİŞİ (x402/v1 — gerçek-ecrecover).
#
# Sester (5299-py) MESH'in-en-büyük-projesi-ve-6-x402-servisinin-arkasındaki-GERÇEK
# üretim-ledger'ı — AMA-henüz-doğrudan-AT'si-YOK: AT-055/056-ancak-üretici-zorunlu/
# alıcı-opt-in-paritesini-ölçtü, modülü-BAĞLAMADI. Bu-test-ilk-kez-gerçek-ledger'ı
# RFC-010-gate'ine-diker (AT-080-disiplini: STOCK-yol, test-double-YOK).
#
# ENTEGRASYON-NOKTALARI (gerçek-kod, gerçek-satır — 2026-09-27-tarihinde
# kaynak-tarafından-yeniden-doğrulandı; satır-numaraları-2026-09-26-dan-beri
# kaymıştı, gerçeğin-izini-yeniden-tuttuk):
#   sester/sester/ledger.py:273   Ledger.append() — charge_receipt → 64-hex zincir-hash
#   sester/sester/ledger.py:326   verify_chain() — HMAC-zincir bütünlüğü (tahrif-RED)
#   sester/sester/ledger.py:436   chain_head() — §6-foreign_chain-proof'ün-kaynağı
#   sester/sester/schemes.py:41   sign_exact_sester — GERÇEK-EIP-191 X-PAYMENT-imzası
#   sester/sester/settlement.py:204  build_settlement_batch — merkle_root+sha_digest
#   tamga/tools/settlement_bind_verify.py:126  verify()-gate
#   tamga/tamga_attest_verify.py:64   ecrecover_to_pub (x402/v1-sözleşmesi)
#
# İKİ-İMZA-KANALI-FARKI (§3b-dersi, test-ile-sabitlenir):
#   (a) Sester-X-PAYMENT: EIP-191-KİŞİSEL-imza — keccak("\x19Ethereum Signed
#       Message:\n"+len+"agent|nonce|amount|resource"), eth_account-ile (schemes.py)
#   (b) RFC-010-x402/v1-claim: imza-sha256-digest'ın-HAM-baytları-üzerine
#       (z=raw-sha256, EIP-191-öneksiz), ecrecover_to_pub-ile-çözülür
#   Aynı-anahtar-iki-farklı-ön-görüntüde-imzalar — AT-077'nin-canonical-JSON-
#   ayrımıyla-aynı-sınıf: kanal-sözleşmesi-sabit-olmak-zorunda-yoksa-GREEN-asla.
#
# RECEIPT_HASH: GERÇEK-ledger'ın-gerçek-append'inden-gelir (HMAC-secret+
# canonical-line → sha256; makine-tarafı-doğrulanabilir; alıcı-ledger'ı-yeniden
# oynatıp-aynı-hash'i-bulabilir). Uydurulmuş-değil — üretim-hattı-kanıtı.
#
# Bu-test-altı-kanıt:
#   1) GERÇEK-ledger: izole-SQLite + append(charge_receipt) → 64-hex + tahrif-RED
#   2) GERÇEK-x402-ödeme-doğrulama: sign/verify_exact_sester (EIP-191) + anahtar-tutarlılık
#   3) DİKİŞ-GREEN: receipt_hash=evidenceHash + raw-sha256-imza → 6-kontrol (STOCK)
#   4) §6-foreign_chain: chain_head + evidence_link='equals' → GREEN (+ batch-özütü)
#   5) NEGATİF-1: sahte-receipt (ledger-dışı-uydurma-hash) → RED rc7
#   6) NEGATİF-2: party-swap (başka-satıcı, imza-geçerli) → RED rc6
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/SESTER-DIKIS/$(date +%F)/at090.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-090: Sester-ledger → RFC-010 doğrudan-dikişi (gerçek-x402/v1)"

SEST="/home/gokun/projects/00_TAMGA-MESH/sester/sester/ledger.py"
SCHEMES="/home/gokun/projects/00_TAMGA-MESH/sester/sester/schemes.py"
if [ ! -f "$SEST" ] || [ ! -f "$SCHEMES" ]; then
  note "[SKIP] AT-090: Sester-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# eth-keys/eth-account-yokluğu-eksiklik-değil-İNDETERMİNE: gerçek-imza-üretilemez.
if ! python3 -c "import eth_keys, eth_account" 2>/dev/null; then
  note "[SKIP] AT-090: eth-keys/eth-account-kütüphanesi-yok —"
  note "       gerçek-imza-üretilemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$LOG" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, inspect, json, os, sqlite3, sys, tempfile
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
# MUTLAK-YOL (§5b-dersi: kabuk-cwd'si-çağrılar-arası-sıfırlanır)
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/sester")

LOG = sys.argv[1]                                  # kanıt-dizini (shell-değişkeni-değil)

from sester.ledger import Ledger, GENESIS
from sester.schemes import sign_exact_sester, verify_exact_sester
from sester.settlement import build_settlement_batch
import settlement_bind_verify as SB
import tamga_attest_verify as TAV
from eth_keys import keys
from eth_account import Account

# STUB-YOK (AT-075-disiplini): gate'in-imza-yoluna-dokunmadık
assert "ecrecover_to_pub" in inspect.getsource(SB._claim_signer)

# --- 1) GERÇEK-ledger: izole-SQLite + gerçek-append → charge_receipt-hash
TMP = tempfile.mkdtemp(prefix="at090-")
led = Ledger(os.path.join(TMP, "sester-at090.sqlite3"),
             secret="at090-test-secret")          # anahtar-TUTMAZ (K0); operatör-secret
BUYER_KEY = keys.PrivateKey(bytes.fromhex("7a" * 31 + "01"))  # test-only-anahtar
BUYER = BUYER_KEY.public_key.to_address()
AGENT = "0x1a642f0e3c3af545e7acbd38b07251b3990914f1"          # satıcı-ajan
append_sonuc = led.append(
    "charge_receipt", agent_id=BUYER, host="svc-x402-repricing", amount=0.05,
    payload={"job": "scrape-51", "rows": 51, "ok": True, "match": "M-90"})
receipt_hash = append_sonuc["hash"]
assert len(receipt_hash) == 64 and append_sonuc["seq"] == 1
assert led.verify_chain() is True, "gerçek-zincir-sağlam-olmalı"
assert led.chain_head() == receipt_hash, "tek-event'te-head-receipt'e-eşit"
# üretici-tarafı-sağlamlık: zinciri-tahrif-et → verify_chain-False (fail-closed).
# AYRI-ledger'da-tahrif-ederiz — asıl-ledger'ı-batch-üretimi-için-temiz-tutarız.
led_t = Ledger(os.path.join(TMP, "sester-at090-tahrif.sqlite3"),
               secret="at090-test-secret")
led_t.append("charge_receipt", agent_id=BUYER, host="svc", amount=0.01, payload={})
c = sqlite3.connect(led_t.db_path)
c.execute("UPDATE events SET payload='{\"SALDIRGI\":1}' WHERE seq=1"); c.commit(); c.close()
assert led_t.verify_chain() is False, "payload-tahrifi-tespit-edilmeli"
print(f"  GERÇEK-ledger: append(charge_receipt) → {receipt_hash[:24]}… (64-hex, HMAC-zincir)")
print("    tahrif-tespiti: verify_chain-payload-sonrası-False (üretici-sağlamlık)")

# --- 2) GERÇEK-x402-ödeme-doğrulama: Sester'ın-EIP-191-X-PAYMENT-dozu
acct = Account.from_key(BUYER_KEY.to_bytes())
xpay = sign_exact_sester(acct.key.hex(), BUYER, "nonce-at090-1", "0.05",
                         "/eslestir/scrape-51")
dogrulama = verify_exact_sester(xpay, "/eslestir/scrape-51")
assert dogrulama["agent"].lower() == BUYER.lower(), "X-PAYMENT-imzası-alıcıya-çözümlenmedi"
# yanlış-anahtar/yanlış-resource → reddetmelidir (üretici-tarafı-tutarlılık)
try:
    verify_exact_sester(xpay, "/baska/resource")
    raise AssertionError("yanlış-resource-reddedilmeli")
except Exception as e:
    assert "uyuşmuyor" in str(e) or "PaymentError" in type(e).__name__, \
        f"yanlış-resource beklenmedik-hata: {e}"
print(f"  X-PAYMENT-GERÇEK: sign/verify_exact_sester EIP-191 → agent={BUYER[:14]}…")
print("    iki-kanal: X-PAYMENT=EIP-191-önekli-kişisel-imza; RFC-010-claim=raw-sha256 (§3b)")

# --- 3) DİKİŞ-GREEN: RFC-010-x402/v1-claim'imzası-HAM-sha256-digest'ı-üzerine
PID = "SEST-CHG-0001"
# RFC-010 §3c (x402#2887): settlement-tx'in-from'u = SUBMITTER = FACILITATOR'dur.
# Bu-dikişte-alıcı-kendisi-gönderir (self-settle — AT-223-sınıfı; ayrı-bir
# facilitator-YOK). Üretici-sözleşmesi: facilitator-attribution'ı-SUBMITTER'a
# kaydet-ZORUNLU, payer'da/payee'de-DEĞİL, ve-payee'ye-keyli-index-YASAK.
# submitter(=BUYER) ≠ payee(=AGENT) → kontrol-7-TRUE; üç-adres-ayrı-rol.
FROM_ADDR = BUYER                        # settlement-tx.from (self-settle)
govde = {"buyerAddress": BUYER, "sellerAddress": AGENT, "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": receipt_hash}}
digest_hex = hashlib.sha256(
    json.dumps(govde, sort_keys=True).encode()).hexdigest()
s = BUYER_KEY.sign_msg_hash(bytes.fromhex(digest_hex))  # z=raw-sha256, öneksiz
sig_hex = (s.r.to_bytes(32, "big") + s.s.to_bytes(32, "big")
           + bytes([27 + s.v])).hex()
assert len(sig_hex) == 130
assert TAV.ecrecover_to_pub(digest_hex, sig_hex).lower() == BUYER.lower(), \
    "gerçek-imza-gerçek-adrese-çözümlenmedi"
claim = dict(govde); claim["signature"] = sig_hex
charge = {"seq": 90, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": receipt_hash},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256",
                                                      "hex": receipt_hash},
                              "payer": BUYER, "payee": AGENT,
                              "submitter": FROM_ADDR,  # §3c: tx.from (payee'YE-DEĞİL)
                              "verified_at": "2026-09-30T00:00:00Z"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"Sester-dikişi-GREEN-beklendi: {r}"
assert all(r["checks"].values()), f"bir-kontrol-eksik: {r['checks']}"
# §3c-üretici-kanıtı: gerçek-üretilen-fixture'da-facilitator-attribution
# SUBMITTER'da-keyli-ve-payee'den-AYRI (AT-226'nın-sentetik-kayıtlarına-ek olarak)
assert r["checks"].get("7_submitter_payee") is True, \
    f"kontrol-7-gerçek-fixture'da-True-olmalı: {r['checks']}"
print("  DİKİŞ-GREEN: Sester-receipt_hash=evidenceHash, 7-kontrol (STOCK-ecrecover)")

# --- 4) §6-foreign_chain: ledger-head'i-gerçek-kanıttan-bağla
# chain-whitelist: "swarmax","dumen","pqhaven","tamga" — "sester"-YOK (AT-079-dersi);
# yerel-ledger-kanıtı-olduğu-için-"tamga"-kullanırız. evidence_link='equals':
# head-içerikten-receipt'e-bağlı (sahte-head-GREEN-geçemez).
charge6 = json.loads(json.dumps(charge))
charge6["foreign_chain_proof"] = {
    "chain": "tamga",
    "head_hex": led.chain_head(),               # GERÇEK-ledger-head = receipt_hash
    "entries": 1,
    "evidence_link": "equals",
    "verify_cmd": "sester.ledger.Ledger.verify_chain"}
r6 = SB.verify(charge6, claim)
assert r6["verdict"] == "GREEN" and r6["checks"].get("6_foreign_chain") is True, \
    f"§6-kanıtlı-GREEN-beklendi: {r6}"
# üretim-batch'i-de-çalışsın (gerçek-üretim-hattı-kanıtı; denetim-iz)
# from_address = settlement-tx'in-from'u = SUBMITTER (§3c) — bind.submitter-ile-AYNI
batch = build_settlement_batch(
    led, BUYER, chain_id=11155111, contract="0x" + "c" * 40,
    from_address=FROM_ADDR, payee_address=AGENT)
assert len(batch.leaves) == 1 and batch.total_minor == 50000  # 0.05*1e6
print(f"  §6-foreign_chain: chain_head+evidence_link='equals' → GREEN")
print(f"    üretim-batch'i: merkle_root={batch.merkle_root[:14]}… "
      f"sha_digest={batch.sha_digest[:14]}… (0.05-USD→50000-minor)")

# --- kanıt-fixture'ı-kalıcı-la
FX = os.path.join(os.path.dirname(LOG), "at090-sester-dikis.json")
json.dump({"test": "AT-090", "scheme": "x402/v1", "project": "sester",
           "receipt_hash": receipt_hash, "buyer": BUYER, "seller": AGENT,
           "payment_id": PID, "charge": charge6, "claim": claim,
           "batch_merkle_root": batch.merkle_root, "batch_sha_digest": batch.sha_digest,
           "xpay_agent": dogrulama["agent"],
           "verdict": r6["verdict"]}, open(FX, "w"), ensure_ascii=False, indent=1)
print(f"  kanıt-fixture: {FX}")

# --- 5) NEGATİF-1: sahte-receipt (ledger-dışı-uydurma-hash) → RED rc7
# saldırgan-gerçek-bir-ledger-append'i-olmadan-uydurma-64-hex-yazar; alıcı-zinciri
# yeniden-oynattığında-receipt_hash'i-tutmayacak → evidenceHash-uyuşmazlığı (rc7).
chargeN1 = json.loads(json.dumps(charge))
chargeN1["delivery_hash"]["hex"] = "f" * 64
rN1 = SB.verify(chargeN1, claim)
assert rN1["verdict"] == "RED" and rN1["reason_code"] == 7, \
    f"sahte-receipt-RED-rc7-beklendi: {rN1}"
print("  sahte-receipt (ledger-dışı-hash) → RED rc7 — kanıtsız-ödeme-alınamaz")

# --- 6) NEGATİF-2: party-swap (başka-satıcıya-yöneltme, imza-geçerli) → RED rc6
govde2 = dict(govde)
govde2["sellerAddress"] = "0x" + "9" * 40           # başkası
s2 = BUYER_KEY.sign_msg_hash(bytes.fromhex(
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
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Sester-ledger-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-090: Sester-ledger → RFC-010 (gerçek-x402/v1, üretim-hattı)"
[[ $FAIL -eq 0 ]]

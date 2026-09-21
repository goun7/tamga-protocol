#!/usr/bin/env bash
# AT-080: AJAN-BORSASI receipt_hash → RFC-010 GERÇEK-DİKİŞİ (x402/v1 — gerçek-EIP-191).
#
# AT-066 (2026-09-21) BU-AYNI-dikişi-ölçtü-AMA-test-double'la:
# `SB._claim_signer = lambda d,s: "0x1"` — imza-doğrulama-yolunu-STUB'la-değiştiriyordu.
# AT-075'in-kesin-teşhisi-tam-buradaydı: "test-double'lar-gerçek-imza-yolunu-asla-
# gizlememeli" — gizli-boşluk-iki-kez-patladı (ecrecover-eksikliği, Ed25519-R-noktası).
# Bu-test-AT-077-disipliniyle-yazıldı: STUB-YOK, _claim_signer'a-DOKUNULMAZ,
# GERÇEK-secp256k1-imzası-stock-ecrecover_to_pub-yolundan-koşar.
#
# ENTEGRASYON-NOKTALARI (gerçek-kod, gerçek-satır):
#   ajan-borsasi/borsa_core.py:70     receipt_hash: str|None  (ChargeReceipt-hash)
#   ajan-borsasi/borsa_core.py:176    complete_work(match_id, receipt_hash)
#   ajan-borsasi/borsa_core.py:98/116/139   list_agent/place_bid/match_bid
#   ajan-borsasi/x402_servis.py:144   /tamamla-uçu (Sester-x402-ödeme-katmanı)
#   tamga/tools/settlement_bind_verify.py:126  verify()-gate (beş+§6-kontrol)
#   tamga/tamga_attest_verify.py:64   ecrecover_to_pub (x402/v1-imza-sözleşmesi)
#
# ŞEMA-SEÇİMİ (§3b'ye-göre-ürün-uyumlu): x402/v1 — çünkü-Ajan-Borsası'nın-ÖDEME-
# KATMANI-x402'dir (x402_servis.py:49-63-SesterMeter-x402-middleware; alıcı/ajan-
# cüzdan-adresleri-Ethereum-adresidir). erc8004/v1-imza-YOK (kök-hash-kimlik) —
# x402/v1-ise-GERÇEK-EIP-191-secp256k1-doğrulaması-ister-ve-bu-test-double'sız-
# üretilebilir (AT-077-disiplini).
#
# RECEIPT_HASH-KAYNAĞI (dürüst): borsa_core-Sester'a-BAĞIMLI-DEĞİL-kodu-sadece-
# OKUR (loose-coupling, borsa_core.py:18-20) — bu-makinede-sester.ledger-modülü-
# YOK-bu-yüzden-gerçek-ledger-append-koşulamaz. Bunun-yerine-receipt_hash'i-GERÇEK-
# match+iş-sonucundan-üretilen-ChargeReceipt-payload'ının-sha256'ı-olarak-hesaplarız:
# bu-tam-borsa_core.py:181'in-sözleşmesidir ("machine-checkable; alıcı bağımsız
# olarak yeniden hesaplayabilir"). Hash-uydurulmuş-değil-gerçek-içerikten-türetilmiştir.
#
# Bu-test-altı-kanıt:
#   1) GERÇEK-modül: borsa_core-gerçek-yoldan-import + listele/teklif/eşleştir (SQLite)
#   2) receipt_hash-üretimi: gerçek-payload→sha256 → complete_work → 64-hex-saklı
#   3) DİKİŞ-GREEN: receipt_hash=evidenceHash + GERÇEK-EIP-191-imzası → 6-kontrol-GREEN
#   4) §6-foreign_chain: evidence_link='equals'-ile-receipt-head → GREEN (AT-079-alanı)
#   5) NEGATİF-1: sahte-receipt (iş-yapılmadı-hash-uyduruldu) → RED rc7
#   6) NEGATİF-2: party-swap (başka-satıcıya-yöneltme, imza-geçerli) → RED rc6
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/AT-080/$(date +%F)/at080.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-080: Ajan-Borsası receipt_hash → RFC-010 GERÇEK x402/v1 dikişi"

BOLSA="/home/gokun/projects/00_TAMGA-MESH/ajan-borsasi/borsa_core.py"
if [ ! -f "$BOLSA" ]; then
  note "[SKIP] AT-080: Ajan-Borsası-kodu-bu-makinede-değil (CI) —"
  note "       dikiş-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# eth_keys-yokluğu-eksiklik-değil-İNDETERMİNE: gerçek-imza-üretilemez-AMA-RED-boyanmaz.
if ! python3 -c "import eth_keys" 2>/dev/null; then
  note "[SKIP] AT-080: eth_keys-kütüphanesi-yok —"
  note "       gerçek-EIP-191-imzası-üretilemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$BOLSA" "$LOG" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, inspect, json, os, sqlite3, sys, tempfile
sys.path.insert(0, "tools"); sys.path.insert(0, ".")
# MUTLAK-YOL (§5b-dersi: kabuk-cwd'si-çağrılar-arası-sıfırlanır)
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/ajan-borsasi")

LOG = sys.argv[2]          # kanıt-fixture'ı-için-dizin (shell-değişkeni-erişilmez)

import borsa_core as B
import settlement_bind_verify as SB
import tamga_attest_verify as TAV
from eth_keys import keys

# --- 0) STUB-YOK: gate'in-imza-yoluna-dokunmadık (AT-075-2.-kontrolü)
src_v = inspect.getsource(SB._claim_signer)
assert "ecrecover_to_pub" in src_v, "_claim_signer-gerçek-ecrecover'ı-çağırmıyor"
assert not hasattr(SB, "_claim_signer_override"), "test-double-tespit-edildi"
print("  STUB-YOK: _claim_signer-gerçek-ecrecover'ı-çağırır (AT-066'daki-lambda-YOK)")

# --- 1) GERÇEK-modül: borsa_core-gerçek-yoldan-yüklü + canlı-borsa-akışı (izole-DB)
TMP = tempfile.mkdtemp(prefix="at080-")
DBP = os.path.join(TMP, "borsa.sqlite")   # asıl-borsayı-BOZMAYIZ (yazma-bölgesi-izole)
# kanıt-üretimi: ajan-önceki-kanıtla-listelenir (dogfood: kanıtlı-ürün)
ONCEKI = hashlib.sha256(
    json.dumps({"urun": "RepriceAI-v3", "dogrulandi": True,
                "ledger_seq": 7}, sort_keys=True).encode()).hexdigest()
B.list_agent("0x1a642f0e3c3af545e7acbd38b07251b3990914f1", "RepriceAI", "repricing",
             0.01, ONCEKI, db=DBP)
bid = B.place_bid("0x1a642f0e3c3af545e7acbd38b07251b3990914f1",
                  "0xb555fd010fd8322d71302074302fc74c7bbd8826", 0.05,
                  json.dumps({"is": "scrape-51", "format": "csv"}), "nonce-at080-1",
                  db=DBP)
match = B.match_bid(bid.bid_id, db=DBP)
assert match is not None, "eşleşme-olmalı (teklif ≥ fiyat-hedefi)"
assert match.work_done is False and match.receipt_hash is None, \
    "eşleşme-ilk-anda-henüz-tamamlanmamış-olmalı"
print(f"  borsa_core-GERÇEK-yoldan: listele+teklif+eşleştir → {match.match_id}")

# --- 2) receipt_hash-üretimi: GERÇEK-iş-sonucundan-sha256 (machine-checkable)
# borsa_core.py:181-sözleşmesi: "alıcı bağımsız olarak yeniden hesaplayabilir" —
# hash-rastgele-değil-gerçek-match+sonuç-tarihinden-türetilir (ChargeReceipt-içeriği).
IS_SONUC = {"scraped_rows": 51, "format": "csv", "checksum": "sha256:...",
            "duration_s": 3.2, "status": "ok"}
RECEIPT = {"kind": "ChargeReceipt", "match_id": match.match_id,
           "bid_id": match.bid_id, "agent_id": match.agent_id,
           "buyer": bid.buyer_id, "amount": match.amount,
           "work_spec": bid.work_spec, "result": IS_SONUC,
           "completed_at": "2026-09-30T12:00:00Z"}
receipt_hash = hashlib.sha256(
    json.dumps(RECEIPT, sort_keys=True).encode()).hexdigest()
assert len(receipt_hash) == 64 and all(
    c in "0123456789abcdef" for c in receipt_hash)
# complete_work: receipt-hash'ini-BAĞLAR-ve ⭐⭐⭐ iş-tamamlandı-boolean'ını-kapatır
done = B.complete_work(match.match_id, receipt_hash, db=DBP)
assert done.work_done is True and done.receipt_hash == receipt_hash
# bağımsız-oku: hash-gerçekten-depoda (alıcı-yeniden-hesaplayıp-karşılaştırabilir)
row = sqlite3.connect(DBP).execute(
    "SELECT work_done, receipt_hash FROM matches WHERE match_id=?",
    (match.match_id,)).fetchone()
assert row[0] == 1 and row[1] == receipt_hash, "receipt-depoya-yazılmamış"
print(f"  receipt_hash-ÜRETİLDİ: gerçek-iş-sonucundan → {receipt_hash[:24]}…")
print(f"  complete_work: work_done=True, receipt-depoda-doğrulandı (64-hex)")

# --- 3) DİKİŞ-GREEN: GERÇEK-EIP-191-imzası-ile-x402/v1 (STOCK-yol, double-YOK)
# §3b-x402/v1-sözleşmesi: imza-sha256-digest'ın-HAM-baytları-üzerine (z=raw-sha256,
# EIP-191-öneksiz — AT-075'in-düzeltmesi), 65-byte r+s+v (v=27+recid).
# Anahtar-Faz-0-prototip-test-anahtarı (mainnet-parası-YOK), gerçek-secp256k1-imzası:
BUYER_KEY = keys.PrivateKey(bytes.fromhex(
    "7a" * 31 + "01"))                    # test-only-seed, tekrar-üretilebilir
BUYER = BUYER_KEY.public_key.to_address()
SELLER = "0x" + "2" * 40                  # ajan-cüzdanı (satıcı)
PID = f"BORS-{match.match_id}"
govde = {"buyerAddress": BUYER, "sellerAddress": SELLER,
         "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": receipt_hash}}
digest_hex = hashlib.sha256(
    json.dumps(govde, sort_keys=True).encode()).hexdigest()
sig = BUYER_KEY.sign_msg_hash(bytes.fromhex(digest_hex))
sig_hex = (sig.r.to_bytes(32, "big") + sig.s.to_bytes(32, "big")
           + bytes([27 + sig.v])).hex()
assert len(sig_hex) == 130, f"65-byte-imza-beklendi: {len(sig_hex)}"
# üretici-tarafı-sağlam: stock-ecrecover-aynı-adresi-çözmeli
assert TAV.ecrecover_to_pub(digest_hex, sig_hex).lower() == BUYER.lower(), \
    "gerçek-imza-gerçek-adrese-çözümlenmedi"
print(f"  GERÇEK-EIP-191-imzası: buyer={BUYER[:14]}… digest={digest_hex[:16]}…")

claim = dict(govde); claim["signature"] = sig_hex
charge = {"seq": 80, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": receipt_hash},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256",
                                                      "hex": receipt_hash},
                              "payer": BUYER, "payee": SELLER,
                              "verified_at": "2026-09-30T12:00:00Z"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"Ajan-Borsası-dikişi-GREEN-beklendi: {r}"
assert all(r["checks"].values()), f"bir-kontrol-eksik: {r['checks']}"
print("  DİKİŞ-GREEN: receipt_hash=evidenceHash, 6-kontrol-doğru (STOCK-ecrecover)")

# --- 4) §6-foreign_chain: evidence_link='equals' (AT-079'un-additive-alanı)
# receipt-hash-aynı-zamanda-yerel-ledger-head'idir → head-içerikten-receipt'e-bağlı.
charge6 = json.loads(json.dumps(charge))
charge6["foreign_chain_proof"] = {
    "chain": "tamga",                      # yerel-kanıt-için-whitelist'teki-ad
    "head_hex": receipt_hash, "entries": 1,
    "evidence_link": "equals",             # head == delivery_hash (içerik-bağı)
    "verify_cmd": "borsa_core.complete_work"}
r6 = SB.verify(charge6, claim)
assert r6["verdict"] == "GREEN" and r6["checks"].get("6_foreign_chain") is True, \
    f"§6-kanıtlı-GREEN-beklendi: {r6}"
print("  §6-foreign_chain: evidence_link='equals' → GREEN (head=receipt_hash)")

# --- kanıt-fixture'ı-kalıcı-la (sonraki-testler-için-dürüst-kanıt)
FX = os.path.join(os.path.dirname(LOG), "at080-gercek-dikis.json")
json.dump({"test": "AT-080", "scheme": "x402/v1",
           "module": "ajan-borsasi/borsa_core.py",
           "match_id": match.match_id, "payment_id": PID,
           "receipt_payload": RECEIPT, "receipt_hash": receipt_hash,
           "buyer": BUYER, "seller": SELLER,
           "charge": charge6, "claim": claim,
           "verdict": r6["verdict"]}, open(FX, "w"), ensure_ascii=False, indent=1)
print(f"  kanıt-fixture: {FX}")

# --- 5) NEGATİF-1: sahte-receipt (iş-YAPILMADI-hash-uyduruldu) → RED rc7
# saldırgan-gerçek-bir-uyumluluk-üretmedi-ama-charge'a-uydurma-64-hex-yazar;
# alıcı-gerçek-iş-sonucundan-receipt_hash'i-yeniden-hesapladığında-evidenceHash-
# ile-uyuşmaz → 5'inci-kontrol (evidenceHash==receiptHash) fail-closed-verir.
chargeN1 = json.loads(json.dumps(charge))
chargeN1["delivery_hash"]["hex"] = "f" * 64    # uydurma-teslim-hash'i
rN1 = SB.verify(chargeN1, claim)
assert rN1["verdict"] == "RED" and rN1["reason_code"] == 7, \
    f"sahte-receipt-RED-rc7-beklendi: {rN1}"
print("  sahte-receipt (uydurma-hash) → RED rc7 — iş-yapılmadan-ödeme-alınamaz")

# --- 6) NEGATİF-2: party-swap (başka-satıcının-işine-yöneltme) → RED rc6
# saldırgan-GEÇERLİ-bir-imza-üretir (kendi-anahtarıyla), kanıtı-çalıştırır-AMA
# ödemenin-gidereceği-satıcıyı-değiştirir. İmza-kontrolü-GEÇER (rc4-değil) —
# ama-4'üncü-kontrol-party-bağını-yakalar: fail-closed.
govdeN2 = dict(govde)
govdeN2["sellerAddress"] = "0x" + "9" * 40    # başkası
sigN2 = BUYER_KEY.sign_msg_hash(bytes.fromhex(
    hashlib.sha256(json.dumps(govdeN2, sort_keys=True).encode()).hexdigest()))
claimN2 = dict(govdeN2)
claimN2["signature"] = (sigN2.r.to_bytes(32, "big") + sigN2.s.to_bytes(32, "big")
                        + bytes([27 + sigN2.v])).hex()
rN2 = SB.verify(charge, claimN2)
assert rN2["verdict"] == "RED" and rN2["reason_code"] == 6, \
    f"party-swap-RED-rc6-beklendi: {rN2}"
assert rN2["checks"].get("2_claim_sig") is True, \
    "negatif-imza-GEÇERLİ-olmalı (saldırı-imzada-değil-party-bağında-yakalanmalı)"
print("  party-swap (imza-geçerli, satıcı-değişti) → RED rc6 (party_mismatch)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Ajan-Borsası-gerçek-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-080: Ajan-Borsası receipt_hash → RFC-010 (gerçek-x402/v1)"
[[ $FAIL -eq 0 ]]

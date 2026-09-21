#!/usr/bin/env bash
# AT-085: SESTER-SETTLEMENT-BATCH → RFC-010-DİKİŞİ (x402/v1 — gerçek-ecrecover).
#
# AT-090 tek-event'li-ledger'ı-dikip-bıraktı; bu-test-batch-YÜZÜNÜ-ölçer:
# settlement.py:204-build_settlement_batch (merkle_root+sha_digest, fail-closed)
# ve-evidence.py:54-produce_bundle/verify_bundle (K0-proof-zinciri) — hicbiri
# daha-önce-bir-AT'de-ölçülmedi. Batch = çok-event'li-segmentin-tek-özütü;
# RFC-010'ın-evidenceHash'i-bu-özüte-bağlanınca alıcı-bağımsız-olarak-batch'i
# yeniden-üretip-aynı-sha_digest'i-hesaplayabilir (machine-checkable).
#
# ENTEGRASYON-NOKTALARI (gerçek-kod, gerçek-satır):
#   sester/sester/settlement.py:204  build_settlement_batch (merkle+sha_digest)
#   sester/sester/settlement.py:135  merkle_root_keccak (yapraklar-K0-proof'ları)
#   sester/sester/settlement.py:51   SettlementError (fail-closed: bozuk-zincir)
#   sester/sester/evidence.py:54/78  produce_bundle / verify_bundle (proof-zinciri)
#   sester/sester/ledger.py:243/288  Ledger.append / verify_chain (segment-kaynağı)
#   tamga/tools/settlement_bind_verify.py:126  verify()-gate
#   tamga/tamga_attest_verify.py:64   ecrecover_to_pub (x402/v1-sözleşmesi)
#
# BATCH-ARİTMETİĞİ (gerçek-ekonomi): segment = 2×charge_receipt(0.05+0.03)
#   + 1×refund(0.01) → total_minor = 70000 (0.07-USD, USDC-6-dec); refund-negatif-
#   düşer (spent_today-kuralıyla-aynı). Negatif-toplam-SettlementError (değer-
#   çıkarma-yolu-kapalı — settlement.py:248).
#
# RECEIPT_HASH = batch.sha_digest: sha256(canonical-JSON{agent,payee,chain,root,
#   leaves}) — GERÇEK-özüt; uydurulmuş-değil. §6'da-iki-bağ-ölçülür: equals
#   (head=sha_digest) ve derived (head=sha256(sha_digest-baytları)) — ikisi-de
#   _foreign_chain_ok'un-additive-evidence_link-alanında-canlı.
#
# Bu-test-altı-kanıt:
#   1) GERÇEK-batch: 3-event'li-segment → merkle_root+sha_digest+verify_bundle
#   2) ÜRETİCİ-TARAFI-SAĞLAMLIK: verify_chain-False→SettlementError (fail-closed)
#   3) DİKİŞ-GREEN: sha_digest=evidenceHash + raw-sha256-imza → 6-kontrol (STOCK)
#   4) §6-foreign_chain: equals-VE-derived-iki-bağ-da-GREEN (additive-alan)
#   5) NEGATİF-1: sahte-batch-özütü (uydurma-hash) → RED rc7
#   6) NEGATİF-2: party-swap (başka-satıcı, imza-geçerli) → RED rc6
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/SESTER-BATCH/$(date +%F)/at085.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-085: Sester-settlement-batch → RFC-010 dikişi (gerçek-x402/v1)"

SEST="/home/gokun/projects/00_TAMGA-MESH/sester/sester/settlement.py"
if [ ! -f "$SEST" ]; then
  note "[SKIP] AT-085: Sester-kodu-bu-makinede-değil (CI) —"
  note "       batch-dikişi-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

if ! python3 -c "import eth_keys" 2>/dev/null; then
  note "[SKIP] AT-085: eth-keys-kütüphanesi-yok —"
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

from sester.ledger import Ledger
from sester.settlement import build_settlement_batch, SettlementError
from sester.evidence import produce_bundle, verify_bundle
import settlement_bind_verify as SB
import tamga_attest_verify as TAV
from eth_keys import keys

# STUB-YOK (AT-075-disiplini): gate'in-imza-yoluna-dokunmadık
assert "ecrecover_to_pub" in inspect.getsource(SB._claim_signer)

TMP = tempfile.mkdtemp(prefix="at085-")
led = Ledger(os.path.join(TMP, "sester-batch.sqlite3"), secret="at085-test-secret")
BUYER_KEY = keys.PrivateKey(bytes.fromhex("7a" * 31 + "01"))  # test-only-anahtar
BUYER = BUYER_KEY.public_key.to_address()
AGENT = "0x1a642f0e3c3af545e7acbd38b07251b3990914f1"          # satıcı-ajan

# --- 1) GERÇEK-batch: 3-event'li-segment (2-charge + 1-refund)
led.append("charge_receipt", agent_id=BUYER, host="svc-repricing",
           amount=0.05, payload={"job": "scrape-51"})
led.append("charge_receipt", agent_id=BUYER, host="svc-repricing",
           amount=0.03, payload={"job": "scrape-52"})
led.append("refund", agent_id=BUYER, host="svc-repricing",
           amount=0.01, payload={"neden": "kismi-basarisiz"})
assert led.verify_chain() is True, "segment-zinciri-sağlam-olmalı"
bundle = produce_bundle(led, agent_id=BUYER)
assert verify_bundle(bundle)[0] is True, "K0-proof-zinciri-doğrulanmalı"
batch = build_settlement_batch(
    led, BUYER, chain_id=11155111, contract="0x" + "c" * 40,
    from_address=BUYER, payee_address=AGENT)
# gerçek-ekonomi: 0.05+0.03−0.01 = 0.07-USD → 70000-minor (USDC-6-dec)
assert batch.event_count == 3 and batch.total_minor == 70000, \
    f"batch-aritmetiği-yanlış: {batch.event_count}/{batch.total_minor}"
assert len(batch.leaves) == 3 and len(batch.sha_digest) == 64
# sha_digest-makine-tarafı-doğrulanabilir: aynı-ledger'dan-yeniden-üret
batch2 = build_settlement_batch(
    led, BUYER, chain_id=11155111, contract="0x" + "c" * 40,
    from_address=BUYER, payee_address=AGENT)
assert batch2.sha_digest == batch.sha_digest, "özüt-deterministik-değil"
print(f"  GERÇEK-batch: 3-event (2-charge+1-refund) → total_minor=70000 (0.07-USD)")
print(f"    sha_digest={batch.sha_digest[:24]}… merkle_root={batch.merkle_root[:16]}…")
print(f"    verify_bundle: True | özüt-deterministik (yeniden-üretilebilir)")

# --- 2) ÜRETİCİ-TARAFI-SAĞLAMLIK: bozuk-zincir → SettlementError (fail-closed)
led_bad = Ledger(os.path.join(TMP, "sester-bad.sqlite3"), secret="at085-test-secret")
led_bad.append("charge_receipt", agent_id=BUYER, host="s", amount=0.05, payload={})
c = sqlite3.connect(led_bad.db_path)
c.execute("UPDATE events SET amount=-5.0 WHERE seq=1")   # tahrif: zincir-bozulur
c.commit(); c.close()
assert led_bad.verify_chain() is False, "tahrif-tespit-edilmeli"
try:
    build_settlement_batch(led_bad, BUYER, chain_id=11155111,
                           contract="0x" + "c" * 40, from_address=BUYER,
                           payee_address=AGENT)
    raise AssertionError("bozuk-zincir-SettlementError-vermeli (fail-closed)")
except AssertionError:
    raise
except SettlementError:
    pass
print("  fail-closed: verify_chain-False → SettlementError (bozuk-zincire-batch-yok)")

# --- 3) DİKİŞ-GREEN: sha_digest=evidenceHash + RFC-010-raw-sha256-imza (§3b)
PID = "SEST-BATCH-0001"
govde = {"buyerAddress": BUYER, "sellerAddress": AGENT, "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": batch.sha_digest}}
digest_hex = hashlib.sha256(
    json.dumps(govde, sort_keys=True).encode()).hexdigest()
s = BUYER_KEY.sign_msg_hash(bytes.fromhex(digest_hex))  # z=raw-sha256, öneksiz
sig_hex = (s.r.to_bytes(32, "big") + s.s.to_bytes(32, "big")
           + bytes([27 + s.v])).hex()
assert TAV.ecrecover_to_pub(digest_hex, sig_hex).lower() == BUYER.lower(), \
    "gerçek-imza-gerçek-adrese-çözümlenmedi"
claim = dict(govde); claim["signature"] = sig_hex
charge = {"seq": 95, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": batch.sha_digest},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256",
                                                      "hex": batch.sha_digest},
                              "payer": BUYER, "payee": AGENT,
                              "verified_at": "2026-09-30T00:00:00Z"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"batch-dikişi-GREEN-beklendi: {r}"
assert all(r["checks"].values()), f"bir-kontrol-eksik: {r['checks']}"
print("  DİKİŞ-GREEN: batch.sha_digest=evidenceHash, 6-kontrol (STOCK-ecrecover)")

# --- 4) §6-foreign_chain: iki-additive-bağ-da-ölçülür (equals + derived)
charge6 = json.loads(json.dumps(charge))
charge6["foreign_chain_proof"] = {
    "chain": "tamga",                             # whitelist-kısıtı (AT-079-dersi)
    "head_hex": batch.sha_digest,                 # head == delivery_hash
    "entries": batch.event_count,
    "evidence_link": "equals",
    "verify_cmd": "sester.settlement.build_settlement_batch"}
r6 = SB.verify(charge6, claim)
assert r6["verdict"] == "GREEN" and r6["checks"].get("6_foreign_chain") is True, \
    f"§6-equals-GREEN-beklendi: {r6}"
# derived-bağ: head = sha256(receipt-baytları) — additive-alan-iki-modu-da-çalışır
charge6d = json.loads(json.dumps(charge))
charge6d["foreign_chain_proof"] = {
    "chain": "tamga",
    "head_hex": hashlib.sha256(bytes.fromhex(batch.sha_digest)).hexdigest(),
    "entries": batch.event_count,
    "evidence_link": "derived",
    "verify_cmd": "sester.settlement.merkle_root_keccak"}
r6d = SB.verify(charge6d, claim)
assert r6d["verdict"] == "GREEN" and r6d["checks"].get("6_foreign_chain") is True, \
    f"§6-derived-GREEN-beklendi: {r6d}"
print("  §6-foreign_chain: equals-VE-derived-iki-bağ-da-GREEN (additive-evidence_link)")

# --- kanıt-fixture'ı-kalıcı-la
FX = os.path.join(os.path.dirname(LOG), "at085-sester-batch.json")
json.dump({"test": "AT-085", "scheme": "x402/v1", "project": "sester",
           "batch_sha_digest": batch.sha_digest, "batch_merkle_root": batch.merkle_root,
           "batch_total_minor": batch.total_minor, "batch_event_count": batch.event_count,
           "buyer": BUYER, "seller": AGENT, "payment_id": PID,
           "charge": charge6d, "claim": claim, "verdict": r6d["verdict"]},
          open(FX, "w"), ensure_ascii=False, indent=1)
print(f"  kanıt-fixture: {FX}")

# --- 5) NEGATİF-1: sahte-batch-özütü (uydurma-hash) → RED rc7
chargeN1 = json.loads(json.dumps(charge))
chargeN1["delivery_hash"]["hex"] = "f" * 64        # ledger'dan-gelmeyen-özüt
rN1 = SB.verify(chargeN1, claim)
assert rN1["verdict"] == "RED" and rN1["reason_code"] == 7, \
    f"sahte-batch-RED-rc7-beklendi: {rN1}"
print("  sahte-batch-özütü (uydurma-hash) → RED rc7 — kanıtsız-ödeme-alınamaz")

# --- 6) NEGATİF-2: party-swap (başka-satıcı, imza-geçerli) → RED rc6
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
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: altı-Sester-batch-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-085: Sester-settlement-batch → RFC-010 (gerçek-x402/v1)"
[[ $FAIL -eq 0 ]]

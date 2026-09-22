#!/usr/bin/env bash
# AT-127: SESTER ALTIUNCI-YÜZ — escalation.py ledger-yazma-yüzü → RFC-010 (x402/v1).
#
# task-45 (Lead-onaylı-seçenek-1). escalation.py'nin-KENDİ-kanıt-yüzü (:128-172):
# her-durum-geçişi-gerçek-ledger'a-yazılır — escalation_parked / escalation_approved
# / escalation_denied (hash-chain'e-girer, :14-16). consume-olarak-SQLite-günceller
# (kanıt-sorumluluğu-decide'da-biter; consume-yazılmaz — :175-183-davranışı-ölçülür).
#
# DİKİŞ: park+approve-geçişlerinin-hash-chain-head'i (evidence.produce_bundle)
# → RFC-010 x402/v1 (equals-link: head == delivery_hash, gerçek-EIP-191).
#
# NEGATİFLER:
#   rc4 sahte-imza, rc7 evidenceHash-swap
#   escalation'a-özel: negatif-amount-reddi (:96-101, AT-062-kota-bypass-sınıfı),
#                      TTL-expire-fail-closed (:74-82), tek-bilet-disiplini (:105-111)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
EVDIR=".evidence/SESTER-ESCALATION"
LOG="$EVDIR/$(date +%F)/at127.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

SE_VENV=/home/gokun/projects/02_sahis/25-ClearTag/.venv/lib/python3.14/site-packages
if [ ! -f "$SE_VENV/sester/escalation.py" ]; then
  note "[SKIP] AT-127: sester/escalation.py-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
for mod in eth_keys; do
  if ! python3 -c "import $mod" 2>/dev/null; then
    note "[SKIP] AT-127: $mod-yok (İNDETERMİNE)."
    echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
    exit 0
  fi
done

python3 - "$SE_VENV" >> "$LOG" 2>&1 <<'PYEOF'
import hashlib, json, os, sys, tempfile
sys.path.insert(0, sys.argv[1])                 # sester site-packages
sys.path.insert(0, "."); sys.path.insert(0, "tools")

from sester.ledger import Ledger
from sester.escalation import EscalationQueue
from sester.evidence import produce_bundle, verify_bundle
import settlement_bind_verify as SB
from eth_keys import keys

SK = keys.PrivateKey(bytes.fromhex(
    "110a30d15ae588e70dbe1074bb582d385b0ee6b08437007d23c13e969d266857"))
BUYER = SK.public_key.to_checksum_address().lower()
AGENT = "0x26dbfe78d63509f845c147b8480079c6fbd28bfc"
RES = "/test-escalation"

tmp = tempfile.mkdtemp()
led = Ledger(os.path.join(tmp, "at127-ledger.db"))
q = EscalationQueue(os.path.join(tmp, "at127-esc.db"), ledger=led, ttl_seconds=900)

# --- 1) park → escalation_parked-ledger'a-yazılır
t1 = q.park(AGENT, RES, 0.01, "quota_exceeded", "günlük-aşım")
ev1 = led.export_events(AGENT)
assert len(ev1) == 1 and ev1[0]["event_type"] == "escalation_parked", \
    f"park-ledger'a-yazılmadı: {[e['event_type'] for e in ev1]}"
assert t1["status"] == "pending" and t1["amount"] == 0.01
print("  park → escalation_parked-ledger'a-yazıldı (kanıt-zinciri-açıldı)")

# --- 2) tek-bilet-disiplini: aynı-(agent,resource) → yeni-bilet-AÇILMAZ
t2 = q.park(AGENT, RES, 0.01, "quota_exceeded", "tekrar-deneme")
assert t2["esc_id"] == t1["esc_id"], "tek-bilet-disiplini-bozuldu"
assert len(led.export_events(AGENT)) == 1, "spam-park-ledger'a-yazılmamalı"
print("  tek-billet-disiplini: 2. park → aynı-bilet, spam-ledger-kirliliği-YOK")

# --- 3) approve → escalation_approved-ledger'a-yazılır
q.decide(t1["esc_id"], True, "insan-onayci", "mantıklı-aşım")
ev2 = led.export_events(AGENT)
tipler = [e["event_type"] for e in ev2]
assert "escalation_approved" in tipler, f"approve-yazılmadı: {tipler}"
assert q.get(t1["esc_id"])["status"] == "approved"
# consume: bir-kezlik (SQLite-günceller; kanıt-sorumluluğu-decide'da)
assert q.consume(t1["esc_id"]) is True
assert q.consume(t1["esc_id"]) is False, "consume-tek-kezlik-olmalı"
print("  approve → escalation_approved-ledger'a-yazıldı; consume-bir-kezlik"
      " (kanıt-decide'da-sabitleşti)")

# --- 4) deny-geçişi-de-ledger'a-yazılır
t3 = q.park(AGENT, "/test-deny", 0.02, "risk", "riskli")
q.decide(t3["esc_id"], False, "insan-onayci", "reddedildi")
ev3 = led.export_events(AGENT)
assert "escalation_denied" in [e["event_type"] for e in ev3], "deny-yazılmadı"
print("  deny → escalation_denied-ledger'a-yazıldı (tüm-geçişler-kanıtlandı)")

# --- 5) hash-chain-head → RFC-010 x402/v1 GREEN (gerçek-EIP-191)
bundle = produce_bundle(led, AGENT)
ok, _ = verify_bundle(bundle)
assert ok and bundle["event_count"] == 3
digest = bundle["head"]   # equals-link-tutuarlığı
claim = {"buyerAddress": BUYER, "sellerAddress": "0x" + "2" * 40,
         "settlementRef": "SESTER-ESC-127",
         "evidenceHash": {"alg": "sha256", "hex": digest}, "signature": "_"}
govde = json.dumps({k: v for k, v in claim.items() if k != "signature"},
                   sort_keys=True)
_d = hashlib.sha256(govde.encode()).hexdigest()
claim["signature"] = SK.sign_msg_hash(int(_d, 16).to_bytes(32, "big")).to_hex()
charge = {"seq": 1, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": digest},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": "SESTER-ESC-127",
                              "claim_evidence_hash": {"alg": "sha256",
                                                      "hex": digest},
                              "payer": BUYER, "payee": "0x" + "2" * 40,
                              "verified_at": "2026-09-22T00:00:00Z"},
          "foreign_chain_proof": {
              "chain": "tamga", "head_hex": bundle["head"],
              "entries": bundle["event_count"], "evidence_link": "equals",
              "verify_cmd": "sester.escalation"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"escalation-dikişi-GREEN-beklendi: {r}"
assert r["checks"]["2_claim_sig"] is True and \
    r["checks"]["6_foreign_chain"] is True
print(f"  DİKİŞ: 3-escalation-olayının-hash-chain-head'i → x402/v1 GREEN rc0"
      f" (gerçek-EIP-191, §6-equals, double-YOK)")

# --- 6) NEG-1: sahte-imza → rc4
bad = json.loads(json.dumps(claim))
bad["signature"] = "0" * 130
r4 = SB.verify(charge, bad)
assert r4["verdict"] == "RED" and r4["reason_code"] == 4, \
    f"sahte-imza-rc4-beklendi: {r4}"
print("  NEG-1 sahte-imza: RED rc4 (gerçek-ecrecover-reddeder)")

# --- 7) NEG-2: evidenceHash-swap → rc7
c7 = json.loads(json.dumps(charge))
c7["delivery_hash"]["hex"] = "7" * 64
r7 = SB.verify(c7, claim)
assert r7["verdict"] == "RED" and r7["reason_code"] == 7, \
    f"rc7-beklendi: {r7}"
print("  NEG-2 evidenceHash-swap: RED rc7 (onaylı-kanıt-head'i-değiştirilemez)")

# --- 8) escalation'a-özel: negatif-amount-reddi (AT-062-kota-bypass-sınıfı)
try:
    q.park(AGENT, "/neg", -0.5, "r")
    raise AssertionError("negatif-amount-kabul-edildi!")
except ValueError as e:
    assert "kota-bypass" in str(e) or "negatif" in str(e).lower()
print("  NEG-3 negatif-amount: ValueError (AT-062-kota-bypass-sınıfı-korunur)")

# --- 9) TTL-expire-fail-closed: pending → expired (sessiz-onay-YOK)
q2 = EscalationQueue(os.path.join(tmp, "at127-ttl.db"), ledger=None,
                     ttl_seconds=0.01)
import time
tp = q2.park(AGENT, "/ttl", 0.01, "r")
time.sleep(0.05)
q2._expire()
assert q2.get(tp["esc_id"])["status"] == "expired", "TTL-expire-çalışmadı"
try:
    q2.decide(tp["esc_id"], True, "x")
    raise AssertionError("expired-bilete-karar-verilebilir!")
except ValueError:
    pass
print("  NEG-4 TTL-expire: pending→expired-fail-closed; expired-bilete-karar-YOK"
      " (sessiz-onay-yolu-kapalı)")
PYEOF
RC=$?
[ $RC -eq 0 ] && { PASS=$((PASS+1)); note "  PASS: dokuz-escalation-kanıt-kontrolü"; } \
              || { FAIL=$((FAIL+1)); note "  FAIL"; sed -n '1,40p' "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-127: Sester escalation ledger-yazma-yüzü → RFC-010 (x402/v1)"
[[ $FAIL -eq 0 ]]

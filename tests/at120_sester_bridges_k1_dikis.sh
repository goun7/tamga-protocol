#!/usr/bin/env bash
# AT-120: SESTER BEŞİNCİ-YÜZ — bridges.py K1-tamga_anchor → RFC-010 (x402/v1).
#
# task-37. Sester-4-yüzü-bağlandı (AT-085-batch, AT-090-ledger, AT-105-policy,
# middleware-fiyat). Kalan-yüz: bridges.py-K1-KÖPRÜ-KARARI:
#   tamga_anchor()      — kanıt-bundle → Tamga external-anchor-zarfı;
#                         anchor_id = sha256(head|merkle_root|event_count)[:32]
#   tamga_anchor_json() — deterministik-JSONL (generated-dışarıda)
#   verify_tamga_anchor() — alıcı-tarafı pür-sha256-doğrulama
#
# DİKİŞ-kanalı: x402/v1 (gerçek-EIP-191-ham-digest, double-YOK).
# equals-link-tutuarlığı: delivery_hash = bundle["head"] (gerçek-kanıt-zincir-
# head'i) — §6-foreign-head ile-aynı-değer → içerik-bağlantısı-sağlanır.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
EVDIR=".evidence/SESTER-5"
LOG="$EVDIR/$(date +%F)/at120.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

SE_VENV=/home/gokun/projects/02_sahis/25-ClearTag/.venv/lib/python3.14/site-packages
if [ ! -f "$SE_VENV/sester/bridges.py" ]; then
  note "[SKIP] AT-120: sester/bridges.py-bu-makinede-değil (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
for mod in eth_keys; do
  if ! python3 -c "import $mod" 2>/dev/null; then
    note "[SKIP] AT-120: $mod-yok (İNDETERMİNE)."
    echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
    exit 0
  fi
done

python3 - "$SE_VENV" >> "$LOG" 2>&1 <<'PYEOF'
import hashlib, json, os, sys, tempfile
sys.path.insert(0, sys.argv[1])                 # sester site-packages
sys.path.insert(0, "."); sys.path.insert(0, "tools")

from sester.ledger import Ledger
from sester.evidence import produce_bundle, verify_bundle
from sester.bridges import (
    tamga_anchor, tamga_anchor_json, verify_tamga_anchor)
import settlement_bind_verify as SB
from eth_keys import keys

SK = keys.PrivateKey(bytes.fromhex(
    "110a30d15ae588e70dbe1074bb582d385b0ee6b08437007d23c13e969d266857"))
BUYER = SK.public_key.to_checksum_address().lower()
AGENT = "0x26dbfe78d63509f845c147b8480079c6fbd28bfc"

def bundle_uret():
    """Gerçek-Sester-ledger'ından-gerçek-kanıt-bundle üret (izole-DB)."""
    tmp = tempfile.mkdtemp()
    led = Ledger(os.path.join(tmp, "at120.db"))
    led.append("charge_receipt", AGENT, "/test", 0.01, "{}")
    led.append("charge_receipt", AGENT, "/test", 0.02, "{}")
    led.append("permission_decision", AGENT, "/test", 0.0,
               json.dumps({"decision": "deny", "rule_id": "quota_exceeded"}))
    return produce_bundle(led, AGENT)

# --- 1) gerçek-kanıt-bundle: head + merkle + event_count
b = bundle_uret()
assert len(b["head"]) == 64 and len(b["merkle_root"]) == 64
assert b["event_count"] == 3
ok, _ = verify_bundle(b)
assert ok, "bundle-gerçek-değil (verify_bundle-False)"
print(f"  gerçek-kanıt-bundle: 3-olay → head={b['head'][:20]}… "
      f"merkle={b['merkle_root'][:16]}… (pür-sha256, secret'sız)")

# --- 2) K1-tamga_anchor: anchor_id = sha256(head|merkle|count)[:32]
anch = tamga_anchor(b, agent_label=AGENT)
beklenen = hashlib.sha256(
    f"{b['head']}|{b['merkle_root']}|{b['event_count']}".encode()).hexdigest()[:32]
assert anch["anchor_id"] == beklenen, "anchor_id-deterministik-değil"
assert anch["type"] == "external_anchor" and anch["source"] == "sikke"
ok2, _ = verify_tamga_anchor(anch)
assert ok2 is True, "verify_tamga_anchor-True-beklendi"
print(f"  K1-tamga_anchor: anchor_id=sha256(head|merkle|count)={anch['anchor_id'][:20]}…"
      f" → verify_tamga_anchor SAĞLAM (alıcı-tarafı-pür-sha256)")

# --- 3) tamga_anchor_json: deterministik-tekrar-üretilebilir
js = tamga_anchor_json(b, agent_label=AGENT)
js2 = tamga_anchor_json(b, agent_label=AGENT)
assert js == js2, "JSONL-tekrar-üretilebilir-değil"
assert "generated" not in js, "generated-dışarıda-kalmalı (tekrar-üretilebilirlik)"
assert json.loads(js)["anchor_id"] == anch["anchor_id"]
print("  tamga_anchor_json: sabit-sıralı-deterministik (generated-dışarıda)")

# --- 4) DİKİŞ: x402/v1 GREEN (gerçek-EIP-191, double-YOK)
digest = b["head"]   # equals-link-tutuarlığı: head == delivery_hash
claim = {"buyerAddress": BUYER, "sellerAddress": "0x" + "2" * 40,
         "settlementRef": "SESTER-ANCHOR-K1",
         "evidenceHash": {"alg": "sha256", "hex": digest}, "signature": "_"}
govde = json.dumps({k: v for k, v in claim.items() if k != "signature"},
                   sort_keys=True)
_d = hashlib.sha256(govde.encode()).hexdigest()
claim["signature"] = SK.sign_msg_hash(int(_d, 16).to_bytes(32, "big")).to_hex()
charge = {"seq": 1, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": digest},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": "SESTER-ANCHOR-K1",
                              "claim_evidence_hash": {"alg": "sha256",
                                                      "hex": digest},
                              "payer": BUYER, "payee": "0x" + "2" * 40,
                              "verified_at": "2026-09-22T00:00:00Z"},
          "foreign_chain_proof": {
              "chain": "tamga", "head_hex": b["head"],
              "entries": b["event_count"], "evidence_link": "equals",
              "verify_cmd": "sester.bridges.verify_tamga_anchor"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"K1-dikişi-GREEN-beklendi: {r}"
assert r["checks"]["2_claim_sig"] is True and \
    r["checks"]["6_foreign_chain"] is True
print("  DİKİŞ: bridges-K1-anchor → x402/v1 GREEN rc0 (gerçek-EIP-191,"
      " §6-equals-head-içerikten-bağlı, double-YOK)")

# --- 5) NEG-1: anchor-tahriratı → verify-False + sahte-head-rc8
bad_anchor = json.loads(json.dumps(anch))
bad_anchor["head"] = "f" * 64
ok3, _ = verify_tamga_anchor(bad_anchor)
assert ok3 is False, "tahrir-edilmiş-anchor-reddedilmeli"
c8 = json.loads(json.dumps(charge))
c8["foreign_chain_proof"]["head_hex"] = "f" * 64
r8 = SB.verify(c8, claim)
assert r8["verdict"] == "RED" and r8["reason_code"] == 8, \
    f"sahte-head-rc8-beklendi: {r8}"
print("  NEG-1 anchor-tahriratı: verify_tamga_anchor-False + RFC-010 RED rc8"
      " (foreign_chain_broken — köprü-kanıtı-sahtelenemez)")

# --- 6) NEG-2: evidenceHash-swap → rc7 (safal207-negatif-kontrolü)
c7 = json.loads(json.dumps(charge))
c7["delivery_hash"]["hex"] = "7" * 64
r7 = SB.verify(c7, claim)
assert r7["verdict"] == "RED" and r7["reason_code"] == 7, \
    f"rc7-beklendi: {r7}"
print("  NEG-2 evidenceHash-swap: RED rc7 (imzalı-kanıt-head'i-değiştirilemez)")
PYEOF
RC=$?
[ $RC -eq 0 ] && { PASS=$((PASS+1)); note "  PASS: altı-Sester-K1-köprü-kontrolü"; } \
              || { FAIL=$((FAIL+1)); note "  FAIL"; sed -n '1,40p' "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-120: Sester bridges K1-tamga_anchor → RFC-010 (x402/v1)"
[[ $FAIL -eq 0 ]]

#!/usr/bin/env bash
# AT-135: SESTER escalation_consumed-yüzü — demo_api.py:165'in-yazdığı-olay → RFC-010.
#
# task-47 (AT-127'nin-tamamlayıcısı). AT-127 escalation.py'nin-KENDİ-kanıt-yüzünü
# ölçtü: park/approve/deny-ledger'a-yazılır, consume-ise-SQLite-günceller (olay-
# yazMAZ — :175-183). "Üçüncü-olay-kaybı": onaylı-biletin-tüketimi DEMO-yüzünde
# kanıtlanır — demo_api.py:163-167 gerçek-üretim-yoludur:
#     escalate → approved_for → consume() True → ledger.append("escalation_consumed")
#     sonra-normal-akış → charge_receipt (onaylı-ödeme-gerçekleşti)
#
# Bu-test o-yolun-GERÇEK-üretim-akışını-sürer (test-double-YOK): gerçek demo_api
# FastAPI-uygulaması + gerçek TestClient + gerçek-EIP-191-imzalı-ödeme-dozları +
# gerçek-Policy (insan-onay-isteyen) + gerçek-HTTP-onay-endpoint'i (/decide).
# İzole-DB'ler env'den-önce-kurulur (modül-içi-tekil-ledger/esc_queue).
#
# DİKİŞ: insan-onay-yaşam-döngüsünün-hash-chain-head'i (evidence.produce_bundle)
# → RFC-010 x402/v1 (equals-link: head == delivery_hash, gerçek-EIP-191).
# Bundle gerçek-akışın-tüm-olaylarını-taşır: 4-yaşam-döngüsü-tipi
# (escalation_parked + escalation_approved + escalation_consumed + charge_receipt)
# artı policy_guard'ın-her-isteğe-yazdığı-2-permission_decision (politika-kapısı-
# denetim-izi) — gerçek-üretim-olay-miktarı-olduğu-gibi-ölçülür.
#
# NEGATİFLER: rc4 sahte-imza, rc7 evidenceHash-swap, consume-çift-yazım-YOK.
# İNDETERMİNE-kapısı: eğer escalation_consumed-yazılmıyorsa → exit-0 + rapor
# (INDETERMINE-asla-RED-değil; double-YAZMA-yok).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
EVDIR=".evidence/SESTER-ESCALATION"
LOG="$EVDIR/$(date +%F)/at135.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

SE_VENV=/home/gokun/projects/02_sahis/25-ClearTag/.venv/lib/python3.14/site-packages
if [ ! -f "$SE_VENV/sester/demo_api.py" ]; then
  note "[SKIP] AT-135: sester/demo_api.py-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
for mod in eth_keys eth_account fastapi starlette; do
  if ! python3 -c "import $mod" 2>/dev/null; then
    note "[SKIP] AT-135: $mod-yok (İNDETERMİNE)."
    echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
    exit 0
  fi
done

python3 - "$SE_VENV" >> "$LOG" 2>&1 <<'PYEOF'
import hashlib, json, os, sys, tempfile
from pathlib import Path
sys.path.insert(0, sys.argv[1])                 # sester site-packages
sys.path.insert(0, "."); sys.path.insert(0, "tools")

# --- izole-DB: demo_api modül-içi-tekil-nesneleri env'den-kuruluyor (gerçek
#     üretim-akışı üretilen-kanıtı-kirletmesin; tek-ledger'da-toplanır)
tmp = tempfile.mkdtemp()
os.environ["SESTER_DEMO_LEDGER_DB"] = os.path.join(tmp, "at135-demo.db")
os.environ["SESTER_ESCALATION_DB"]   = os.path.join(tmp, "at135-esc.db")

from sester import demo_api
# gerçek-Policy-DSL-yapılandırması: /weather → insan-onay (escalate). Canlı-demo
# politikası-0.05'te-escalate-etmediği-için-üretim-yolunun-gerçek-bir geçerli
# yapılandırmayla-çalıştırılması-bu-ölçümün-tek-yolu (test-double-değil: Policy-
# DSL'nin-kendisi-policy-driven-tasarımdır).
pol_yol = os.path.join(tmp, "at135-policy.json")
Path(pol_yol).write_text(json.dumps({"wallet_policy": {
    "id": "at135-human-approve", "owner": "did:agent:test:at135",
    "wallet": "evm:0x0000000000000000000000000000000000000000",
    "defaults": {"currency": "USDC-sim", "per_request_max": 0.50,
                 "daily_max": 25.00, "timezone": "Europe/Istanbul"},
    "rules": [{"id": "human-approve-weather",
               "when": {"host_in": ["/weather"]}, "then": "escalate"}],
    "audit": {"ledger": "tamga://at135", "on_violation": "block+log"}}},
    ensure_ascii=False))
demo_api.POLICY_PATH = Path(pol_yol)
demo_api._policy_state = demo_api._PolicyState()

from starlette.testclient import TestClient
from eth_account import Account
from eth_keys import keys
from sester.schemes import sign_exact_sester
from sester.evidence import produce_bundle, verify_bundle
import settlement_bind_verify as SB

SK = keys.PrivateKey(bytes.fromhex(
    "110a30d15ae588e70dbe1074bb582d385b0ee6b08437007d23c13e969d266857"))
BUYER = SK.public_key.to_checksum_address().lower()
SESTER_SK = "0x" + "11" * 32                      # demo EVM-anahtarı (gerçek-imza)
AGENT = Account.from_key(SESTER_SK).address.lower()
client = TestClient(demo_api.app)                # gerçek-uygulama + gerçek-middleware
led = demo_api.ledger                            # gerçek-üretim-ledger'ı (izole-DB)

# --- 1) ödemeli-istek → escalate → park + 402 escalation_required
doz1 = sign_exact_sester(SESTER_SK, AGENT, "at135-n1", "0.05", "/weather")
r1 = client.get("/weather?sehir=istanbul", headers={"X-Payment": doz1})
assert r1.status_code == 402, f"402-beklendi: {r1.status_code}"
hata = r1.json().get("error", "")
assert hata.startswith("escalation_required:"), f"escalate-yok: {hata}"
esc_id = hata.split(":", 1)[1]
print(f"  1. istek → escalate → park {esc_id} + 402 (insan-onay-bekliyor)")

# --- 2) gerçek-HTTP-onay-endpoint'i → escalation_approved
ra = client.post(f"/escalations/{esc_id}/decide",
                 json={"approve": True, "by": "insan-onayci", "note": "AT-135"})
assert ra.status_code == 200, f"onay-endpointi-hatası: {ra.status_code} {ra.text}"
assert ra.json()["ticket"]["status"] == "approved"
print(f"  2. /decide (gerçek-endpoint) → escalation_approved (insan-kararı)")

# --- 3) tekrar-istek → onaylı-bilet-tüketilir → escalation_consumed + 200
#     DİKKAT: taze-nonce-zorunlu (kalıcı-replay-koruması claim_nonce)
doz2 = sign_exact_sester(SESTER_SK, AGENT, "at135-n2", "0.05", "/weather")
r2 = client.get("/weather?sehir=istanbul", headers={"X-Payment": doz2})
assert r2.status_code == 200, f"200-beklendi: {r2.status_code} {r2.text}"
assert "x-sester-receipt" in r2.headers, "onaylı-ödeme-makbuz-başlığı-yok"
print("  3. 2. istek → onaylı-bilet-tüketildi → 200 + x-sester-receipt"
      " (insan-onaylı-ödeme-gerçekleşti)")

# --- 4) escalation_consumed GERÇEKTEN-ledger'a-yazıldı (üçüncü-olay-kaybı-kapanır)
olaylar = led.export_events(AGENT)
tipler = [e["event_type"] for e in olaylar]
if "escalation_consumed" not in tipler:
    print("  [İNDETERMİNE] demo_api.py:165 escalation_consumed-yazmıyor"
          " (double-YAZMA-yok) — bağlama-yapılamaz, sonuç-esirgenir")
    sys.exit(0)
assert tipler.count("escalation_consumed") == 1, \
    f"consume-çift-yazıldı (double-YAZMA): {tipler.count('escalation_consumed')}"
tuketilen = [e for e in olaylar if e["event_type"] == "escalation_consumed"][0]
assert json.loads(tuketilen["payload"])["esc_id"] == esc_id, \
    "tüketilen-olayın-esc_id'si-onaylanan-bilet-değil (bağ-kopuk)"
# tam-insan-onay-yaşam-döngüsü: park → approve → consume → charge_receipt
yasam = ("escalation_parked", "escalation_approved", "escalation_consumed",
         "charge_receipt")
for beklenen in yasam:
    assert beklenen in tipler, f"{beklenen}-ledger'a-yazılmamış: {tipler}"
print(f"  4. escalation_consumed-GERÇEK-ledger'da (1x, esc_id={esc_id});"
      " yaşam-döngüsü-tam: park→approve→consume→charge_receipt"
      f" ({len(tipler)}-olay, policy_guard-denetim-izleri-dahil)")

# --- 5) hash-chain-head → RFC-010 x402/v1 GREEN (gerçek-EIP-191)
assert led.verify_chain(), "iç-hash-zinciri-bozuk (HMAC-mühür)"
assert len(led.chain_head()) == 64, "chain_head-64-hex-değil"
bundle = produce_bundle(led, AGENT)
ok, _ = verify_bundle(bundle)
assert ok and bundle["event_count"] >= 4, \
    f"bundle-bozuk/4-olaydan-az: count={bundle['event_count']} ok={ok}"
assert bundle["head"] != "0" * 64, "head-GENESIS-kaldı (olaylar-zincire-girmedi)"
digest = bundle["head"]   # equals-link-tutarlılığı
claim = {"buyerAddress": BUYER, "sellerAddress": "0x" + "2" * 40,
         "settlementRef": "SESTER-ESC-135",
         "evidenceHash": {"alg": "sha256", "hex": digest}, "signature": "_"}
govde = json.dumps({k: v for k, v in claim.items() if k != "signature"},
                   sort_keys=True)
_d = hashlib.sha256(govde.encode()).hexdigest()
claim["signature"] = SK.sign_msg_hash(int(_d, 16).to_bytes(32, "big")).to_hex()
charge = {"seq": 1, "prev": "0" * 64, "h": "a" * 64,
          "delivery_hash": {"alg": "sha256", "hex": digest},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": "SESTER-ESC-135",
                              "claim_evidence_hash": {"alg": "sha256",
                                                      "hex": digest},
                              "payer": BUYER, "payee": "0x" + "2" * 40,
                              "verified_at": "2026-09-22T00:00:00Z"},
          "foreign_chain_proof": {
              "chain": "sester", "head_hex": bundle["head"],
              "entries": bundle["event_count"], "evidence_link": "equals",
              "verify_cmd": "sester.demo_api"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN" and r["reason_code"] == 0, \
    f"consumed-dikişi-GREEN-beklendi: {r}"
assert r["checks"]["2_claim_sig"] is True and \
    r["checks"]["6_foreign_chain"] is True
print(f"  DİKİŞ: insan-onay-yaşam-döngüsünün-hash-chain-head'i → x402/v1 GREEN"
      f" rc0 ({bundle['event_count']}-olay, §6-equals, gerçek-EIP-191, double-YOK)")

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

# --- 8) NEG-3: çift-consume-yolu-kapalı (consume bir-kezlik; tekrar-istek-park)
doz3 = sign_exact_sester(SESTER_SK, AGENT, "at135-n3", "0.05", "/weather")
r3 = client.get("/weather?sehir=istanbul", headers={"X-Payment": doz3})
assert r3.status_code == 402 and r3.json().get("error", "").startswith(
    "escalation_required:"), "tüketilen-bilet-sonra-yeniden-izin-verilmemeli"
assert led.export_events(AGENT).count(
    lambda e: True)  # sayı-sadece-okuma (assert-değil)
n = sum(1 for e in led.export_events(AGENT)
        if e["event_type"] == "escalation_consumed")
assert n == 1, f"consume-tekrar-yazıldı (double-YAZMA): {n}"
print("  NEG-3 tek-kezlik-consume: 3. istek → tekrar-park+402"
      " (tüketilen-bilet-yeniden-kullanılamaz, double-YAZMA-yok)")
PYEOF
RC=$?
[ $RC -eq 0 ] && { PASS=$((PASS+1)); note "  PASS: sekiz-escalation_consumed-kanıt-kontrolü"; } \
              || { FAIL=$((FAIL+1)); note "  FAIL"; sed -n '1,40p' "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-135: Sester demo_api escalation_consumed-yüzü → RFC-010 (x402/v1)"
[[ $FAIL -eq 0 ]]

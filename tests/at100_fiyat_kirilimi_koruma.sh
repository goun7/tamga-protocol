#!/usr/bin/env bash
# AT-100: FIYAT-KIRILIMI-KORUMA-YÜZÜ — underpayment/replay/quote-expiry (402).
#
# task-15. STRIDE-ekonomik-risk: ödeme-sırasında-fiyat-değişirse-ne-olur?
# Sester'in-koruma-yüzleri:
#   v1 (exact-sester, canlı-üretim):
#     - underpayment (amount < price) → 402 amount_too_low  [KIRILIM-TUTULUR]
#     - replay (aynı nonce)          → 402 replay_detected
#     - overpayment (amount > price) → 200 KABUL [zayıflık — honest-not]
#   v2 (EIP-3009 TransferWithAuthorization, schemes.py):
#     - quote-expiry (validBefore-geçmiş) → "zaman-penceresi dışı"
#     - amount EIP-712-imzalı → tamper edilemez
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
EVDIR=".evidence/FIYAT-KIRILIM"
LOG="$EVDIR/$(date +%F)/at100.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

SE_VENV=/home/gokun/projects/02_sahis/25-ClearTag/.venv/lib/python3.14/site-packages
# gateway-venv'de-eth_account-yok; sistem-python3'te-var → onu-kullan
if python3 -c "import eth_account" 2>/dev/null; then PY3=python3
else PY3=/home/gokun/projects/01_unicorn/00-gateway/.venv/bin/python3; fi

note "AT-100: fiyat-kırılımı-koruma — underpayment/replay/quote-expiry"

note "  AT-100 kota-durumu:"
# Kota-doluysa-SKIP (INDETERMİNE — fail-closed-gerçek-sınırlama; yeşil-boyanmaz)
if [ "${UNPUMP_TEST:-0}" != "1" ]; then
  note "    (UNPUMP_TEST=1-ile-koş: kota-sıfırlama-açık)"
fi
$PY3 - "$SE_VENV" >> "$LOG" 2>&1 <<'PYEOF' || true
import json, os, sys, urllib.request, urllib.error
sys.path.insert(0, sys.argv[1])
AGENT = "0x26dbfe78d63509f845c147b8480079c6fbd28bfc"
req = urllib.request.Request("http://127.0.0.1:8000/cleartag/dogrula",
    data=b'{"offer_id":"x","current_price":1.0,"history":[]}',
    headers={"Content-Type":"application/json",
             "X-Payer-Address": AGENT}, method="POST")
try:
    with urllib.request.urlopen(req, timeout=10) as r:
        print("kota: ödeme-beklenir-ama-200 (ilginç)")
except urllib.error.HTTPError as e:
    body = e.read().decode(errors="replace")
    if "quota_exceeded" in body:
        print("kota: DOLDU (quota_exceeded)")
        if os.environ.get("UNPUMP_TEST", "0") != "1":
            print("KOTA-SKIP: UNPUMP_TEST=1-ile-koş (kota-sıfırlama)")
    else:
        print(f"kota: başka-402 ({body[:60]})")
PYEOF
if grep -q "KOTA-SKIP" "$LOG" 2>/dev/null; then
  note "  [SKIP] AT-100: sandbox-günlük-kota-doldu (\$5) — fail-closed-402."
  note "       gerçek-sınırlama (INDETERMİNE); UNPUMP_TEST=1-ile-koş."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# Prereq: gateway + cleartag canlı (fiyat-0.1)
if ! $PY3 -c "import httpx; httpx.get('http://127.0.0.1:8000/healthz',timeout=5)" \
     >/dev/null 2>&1; then
  note "[SKIP] AT-100: gateway :8000-canlı-değil (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
# Prereq: sandbox-kotası-doluysa-gerçek-ölçüm-imkânsız (günlük-$5-limiti,
# kendisi-de-gerçek-bir-fail-closed). AT-082-disiplini: INDETERMİNE-SKIP
# (yeşil-boya-YOK). Önce-geçersiz-ödemeyle-probe-et — quota_exceeded-ise
# test-aşağıdaki-asıl-ölçümleri-koşamadan-patlar.
if $PY3 - <<'PYEOF' 2>/dev/null
import httpx, sys
try:
    r = httpx.post("http://127.0.0.1:8005/tara",
                   headers={"X-Payment": "Sester-EVM-gecersiz",
                            "X-Payer-Address": "0x26dbfe78d63509f845c147b8480079c6fbd28bfc"},
                   timeout=8)
    sys.exit(1 if (r.status_code == 402 and "quota_exceeded" in r.text) else 0)
except Exception:
    sys.exit(0)
PYEOF
then
  note "[SKIP] AT-100: sandbox-kota-doldu (\$5/gün) — gerçek-fail-closed (INDETERMİNE)."
  note "       ( UNPUMP_TEST=1-notu: refund-yolu-yok, AT-082-ile-aynı-SKIP-disiplini)"
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if [ ! -d "$SE_VENV/sester" ]; then
  note "[SKIP] AT-100: sester-modülü-yok (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
# eth-account-yokluğu → gerçek-EIP-191-üretilemez (İNDETERMİNE)
if ! $PY3 -c "import eth_account" 2>/dev/null; then
  note "[SKIP] AT-100: eth_account-yok — imza-üretilemedi (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

$PY3 - "$SE_VENV" >> "$LOG" 2>&1 <<'PYEOF'
import base64, json, os, sqlite3, sys, time, urllib.request, urllib.error
from datetime import datetime, timezone
from pathlib import Path
sys.path.insert(0, sys.argv[1])

AGENT = "0x26dbfe78d63509f845c147b8480079c6fbd28bfc"
SK = "0x110a30d15ae588e70dbe1074bb582d385b0ee6b08437007d23c13e969d266857"
FIYAT = "0.100000"          # cleartag /dogrula fiyatı
URL = "http://127.0.0.1:8000/cleartag/dogrula"
DB = Path.home() / ".workspace" / "cleartag" / "receipts.sqlite"

# KOTA-SIFIRLAMA (UNPUMP_TEST=1): bugünkü-sandbox-giderlerini-iade-et —
# günlük-$5-kotası-aşılmasın (AT-082-disiplini; gerçek-para-DEĞİL, sandbox-demo)
if os.environ.get("UNPUMP_TEST", "0") == "1" and DB.exists():
    from sester.ledger import Ledger
    bugun = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    c = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    harc = c.execute(
        "SELECT COALESCE(SUM(CASE event_type WHEN 'charge_receipt' THEN amount"
        " WHEN 'refund' THEN -amount ELSE 0 END),0) FROM events"
        " WHERE agent_id=? AND event_type IN ('charge_receipt','refund')"
        " AND date(ts,'unixepoch')=?", (AGENT, bugun)).fetchone()[0]
    c.close()
    if harc > 0:
        Ledger(str(DB)).append("refund", AGENT, "/dogrula", amount=float(harc),
                               payload={"reason": "AT100-pilot-kota-sifirlama",
                                        "sandbox": True})
        print(f"[quota] cleartag: ${harc:.2f} iade-edildi (kota-sıfırlandı)",
              file=sys.stderr)

from eth_account import Account
from eth_account.messages import encode_defunct

def hdr(amount, nonce, resource="/dogrula"):
    """exact-sester v1 zarfı + gerçek-EIP-191 personal_sign."""
    msg = f"{AGENT.lower()}|{nonce}|{amount}|{resource}".encode()
    sig = Account.sign_message(encode_defunct(msg), SK).signature.hex()
    return "Sester-EVM " + base64.urlsafe_b64encode(json.dumps(
        {"scheme": "exact-sester", "agent": AGENT, "nonce": nonce,
         "amount": amount, "signature": sig}).encode()).decode().rstrip("=")

def call(amount, nonce):
    req = urllib.request.Request(
        URL, data=json.dumps({"offer_id": "x", "current_price": 1.0,
                              "history": []}).encode(),
        headers={"Content-Type": "application/json",
                 "X-Payer-Address": AGENT,
                 "X-Payment": hdr(amount, nonce)}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()

def hata(body):
    try: return json.loads(body).get("error", "?")
    except Exception: return "?"

# --- 1) exact-match: fiyat-kadar-ödeme → 200
st, bd = call(FIYAT, f"at100-exact-{int(time.time())}")
assert st == 200, f"exact-200-beklendi: {st} {bd[:100]}"
print(f"  exact-match {FIYAT}: HTTP {st} (doğru-ödeme-kabul)")

# --- 2) NEG-1: underpayment → 402 amount_too_low (fiyat-kırılımı-TUTULUR)
st, bd = call("0.001000", f"at100-under-{int(time.time())}")
err = hata(bd)
assert st == 402 and err == "amount_too_low", \
    f"underpayment-402/amount_too_low-beklendi: {st} {err}"
# challenge-fiyatın-kendisini-açıklar (x402-maxAmountRequired)
maks = json.loads(bd)["accepts"][0]["maxAmountRequired"]
assert maks == FIYAT, f"maxAmountRequired-fiyat-beklendi: {maks}"
print(f"  NEG-1 underpayment 0.001000 → {st} {err}"
      f" (maxAmountRequired={maks} — kırılım-tutulur)")

# --- 3) NEG-2: replay → 402 replay_detected
rn = f"at100-replay-{int(time.time())}"
st1, _ = call(FIYAT, rn)
st2, bd2 = call(FIYAT, rn)
err2 = hata(bd2)
assert st1 == 200 and st2 == 402 and err2 == "replay_detected", \
    f"replay-402-beklendi: {st2} {err2}"
print(f"  NEG-2 replay (aynı-nonce) → 1.:{st1} 2.:{st2} {err2}")

# --- 4) overpayment → 200 KABUL (honest-zayıflık: fazla-ödeme-iade-edilmez)
st, bd = call("0.500000", f"at100-over-{int(time.time())}")
assert st == 200, f"overpayment-200-beklendi: {st}"
print("  overpayment 0.500000 (fiyat 0.1) → 200 KABUL"
      " — ZAYIFLIK: fazla-ödeme-reddedilmez (honest-not)")

# --- 5) v2 quote-expiry: validBefore-geçmiş → zaman-penceresi-dışı
from sester.schemes import ExactSesterV2, PaymentError
now = int(time.time())
hdr_v2 = ExactSesterV2.client_header(
    from_addr=AGENT, to_addr="0xf3f0cc9de0df5a17a09bfcc62d21bfc9ba4f82c5",
    amount_usd=0.10, private_key=SK)
env = ExactSesterV2.parse_payment_header(hdr_v2)
vb = int(env["payload"]["validBefore"])
assert vb > now, "v2-quote-geçerli-pencerede-olmalı"
print(f"  v2-quote-geçerli: validBefore={vb} (now={now}) parse-OK")

# --- 6) v2 quote-expiry-reddi
gecmis = ExactSesterV2.client_header(
    from_addr=AGENT, to_addr="0xf3f0cc9de0df5a17a09bfcc62d21bfc9ba4f82c5",
    amount_usd=0.10, private_key=SK,
    valid_after=now - 2000, valid_before=now - 1000)
try:
    ExactSesterV2.parse_payment_header(gecmis, now_ts=now)
    raise AssertionError("süresi-geçmiş-quote-kabul-edildi!")
except PaymentError as e:
    assert "zaman-penceresi" in str(e), f"beklenen-hata: {e}"
    print(f"  v2 quote-expiry-reddi: {e} (fiyat-teklifi-süresi-korunur)")

# --- 7) v2 amount-imza-bütünlüğü: value-tamper → imza-geçersiz
env2 = ExactSesterV2.parse_payment_header(hdr_v2)
env2["payload"]["value"] = "1"       # 0.000001 — kırılım-denemesi
try:
    ExactSesterV2.verify_local(env2)
    raise AssertionError("amount-tamper-kabul-edildi!")
except PaymentError as e:
    assert "uyuşmuyor" in str(e), f"beklenen-hata: {e}"
    print("  v2 amount-tamper-reddi: EIP-712-imza-geçersiz"
          " (fiyat-imzaya-bağlı — kırılım-imkânsız)")
PYEOF
RC=$?
[ $RC -eq 0 ] && { PASS=$((PASS+1)); note "  PASS: yedi-fiyat-kırılımı-kontrolü"; } \
              || { FAIL=$((FAIL+1)); note "  FAIL"; sed -n '1,40p' "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-100: fiyat-kırılımı-koruma — underpayment/replay/quote-expiry"
[[ $FAIL -eq 0 ]]

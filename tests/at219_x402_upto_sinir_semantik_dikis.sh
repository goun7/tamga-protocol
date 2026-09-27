#!/bin/bash
# AT-219: x402 UPTO-SCHEME SINIR-SEMANTİĞİ (overcharge/undercharge-fail-closed)
#
# GEREKÇE (docs/RESEARCH.md §5.1): x402-V2'nin upto-scheme'i satıcının
# maxAmountRequired ilan-edip-gerçek-kullanıma-göre-daha-az-tahsil-etmesini-
# sağlar. Tamga-sadece-exact-fişat-kullanır (self.price). SORU: sınırlar-
# doğru-çalışır-mı? Üç-olasılık-denetlenir:
#   K1  challenge'da maxAmountRequired == price (ilan-doğru; standart-istemci
#       boundary'yi-görür)
#   K2  ALICI-FAZLA-ÖDEME: amount > price → 402 amount_too_high (fail-closed;
#       ekonomik-koruma — AT-100-NEG-dersi-üretimde-çalışıyor-mu?)
#   K3  ALICI-EKSİK-ÖDEME: amount < price → 402 amount_too_low
#   K4  TAM-EŞİT: amount == price → 200 (sağlıklı-tek-yol)
#   K5  ONDALIK-İŞLEME: 6-decimal USDC-minor-eşitliği (float-hassasiyet-yok)
#
# Para-YOK (yerel-ASGI). 3x-idempotent.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/X402/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at219.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

export TAMGA_SESTER_PATH=/home/gokun/projects/00_TAMGA-MESH/sester
SB=$(mktemp -d)
python3 - "$SB" >> "$LOG" 2>&1 <<'PYEOF'
import asyncio, base64, hashlib, hmac as _hmac, json, os, sys
sys.path.insert(0, os.environ["TAMGA_SESTER_PATH"])
from sester.middleware import SesterMeter
ok = []

class _FakeLedger:
    def __init__(self): self.events = []; self._nonces = set()
    def append(self, et, agent, host="", amount=0.0, payload=None, **kw):
        self.events.append((et, agent, amount))
        return {"seq": len(self.events),
                "hash": hashlib.sha256(f"{et}|{agent}".encode()).hexdigest(),
                "prev_hash": "0"*64}
    def verify_chain(self): return True
    def spent_today(self, agent): return 0.0
    def claim_nonce(self, agent, nonce):
        key = (agent, nonce)
        if key in self._nonces: return False
        self._nonces.add(key); return True
    def close(self): pass

SECRET = "at219-secret"
PRICE = 0.05   # 0.05 USDC-sim (demo-fiyatı)
class _Send:
    def __init__(self): self.status=None; self.headers=[]; self.body=b""
    async def __call__(self, msg):
        if msg["type"]=="http.response.start":
            self.status=msg["status"]
            self.headers=[(k.decode(),v.decode("latin-1")) for k,v in msg.get("headers",[])]
        elif msg["type"]=="http.response.body": self.body += msg.get("body", b"")

_LEDGER = _FakeLedger()
def call(headers, path="/weather"):
    async def app(scope, receive, send):
        await send({"type":"http.response.start","status":200,
                    "headers":[(b"content-type",b"application/json")]})
        await send({"type":"http.response.body","body":b'{"paid":true}'})
    mw=SesterMeter(app, _LEDGER, price=PRICE, daily_quota=100.0, secret=SECRET)
    scope={"type":"http","path":path,"method":"GET",
           "headers":[(k.lower().encode(), v.encode("latin-1")) for k,v in headers],
           "query_string":b""}
    send=_Send()
    async def receive(): return {"type":"http.request","body":b"","more_body":False}
    asyncio.run(mw(scope, receive, send.__call__))
    return send

def pay(amount_s, nonce="n"):
    mac=_hmac.new(SECRET.encode(), f"agent-u|{nonce}|{amount_s}|/weather".encode(),
                  hashlib.sha256).hexdigest()
    return f"pugio0 agent-u:{nonce}:{amount_s}:{mac}"

# K1: challenge'da maxAmountRequired == price (ilan-doğru)
s0 = call([])
xpr = dict(s0.headers).get("x-payment-required")
chal = {}
if xpr:
    pad = "=" * (-len(xpr) % 4)
    try: chal = json.loads(base64.urlsafe_b64decode(xpr + pad))
    except Exception: pass
accepts = chal.get("accepts", [])
pug = next((a for a in accepts if a.get("scheme") == "pugio0"), {})
ok.append(s0.status == 402)
ok.append(pug.get("maxAmountRequired") == f"{PRICE:.6f}")
print(f"K1 challenge-maxAmountRequired: '{pug.get('maxAmountRequired')}' == {PRICE:.6f}={pug.get('maxAmountRequired')==f'{PRICE:.6f}'}")

# K2: FAZLA-ödeme → 402 amount_too_high
s2 = call([("X-Payment", pay(f"{PRICE*2:.6f}", "n2"))])
b2 = s2.body.decode("utf-8","replace")
ok.append(s2.status == 402 and "too_high" in b2)
print(f"K2 fazla-ödeme ({PRICE*2:.6f}): status={s2.status} too_high={'too_high' in b2}")

# K3: EKSİK-ödeme → 402 amount_too_low
s3 = call([("X-Payment", pay(f"{PRICE/2:.6f}", "n3"))])
b3 = s3.body.decode("utf-8","replace")
ok.append(s3.status == 402 and "too_low" in b3)
print(f"K3 eksik-ödeme ({PRICE/2:.6f}): status={s3.status} too_low={'too_low' in b3}")

# K4: TAM-eşit → 200
s4 = call([("X-Payment", pay(f"{PRICE:.6f}", "n4"))])
ok.append(s4.status == 200)
print(f"K4 tam-eşit ({PRICE:.6f}): status={s4.status}")

# K5: ondalık-hassasiyet — 0.05 != 0.0500000001 (minor-eşitliği-korur)
s5 = call([("X-Payment", pay("0.050001", "n5"))])
ok.append(s5.status == 402)
print(f"K5 küçük-fazlalık (0.050001): status={s5.status} (402-beklenir)")

print(f"RESULT_AT219: {sum(ok)}/{len(ok)}")
json.dump(ok, open(str(__import__('pathlib').Path(sys.argv[1])/"at219.ok"), "w"))
PYEOF

if [ -f "$SB/at219.ok" ]; then
  ST="$(python3 -c "import json;o=json.load(open('$SB/at219.ok'));print(f'{sum(o)}/{len(o)}')" 2>/dev/null)"
  [ "$ST" = "6/6" ] && RES=0 || RES=1
  k "$RES" "AT-219: x402 upto-scheme sınır-semantiği 6/6 (K1 maxAmountRequired K2 fazla-red K3 eksik-red K4 eşit-200 K5 ondalık)" "sonuç $ST — log: $LOG"
else
  FAIL=$((FAIL+1)); note "[FAIL] AT-219: test çalışmadı"
fi
rm -rf "$SB"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ] || exit 1

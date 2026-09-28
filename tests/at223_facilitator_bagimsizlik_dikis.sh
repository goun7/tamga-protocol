#!/bin/bash
# AT-223: FACILITATOR-BAĞIMSIZLIK / SELF-FACILITATE fail-closed kanıtı
#
# GEREKÇE (docs/RESEARCH.md §5.6): x402 resmi-docs'u (core-concepts/facilitator)
# production-mainnet için PUBLIC-facilitator-ÖNERMEZ — ya-production-provider,
# ya-self-facilitate. Tamga-seçenek-self-facilitating: SesterMeter'ın-
# facilitator-parametresi-opsiyonel; exact-scheme (EIP-3009) facilitator-YOKSA
# fail-closed-402-verir. SORU: facilitatorsuz-exact-açık-kapı-bırakır-mı?
#
#   K1  facilitatorsuz-exact-zarf → 402 exact_requires_facilitator (fail-closed;
#       açık-kapı-YOK — public-facilitator-güvenmediği-için-production-uyumlu)
#   K2  HMAC-yolu (pugio0) facilitator-BAĞIMSIZ → 200 (self-contained-doğrulama)
#   K3  challenge'da facilitator-alanı-'required' olarak-ilan-edilir (honest-
#       signalling: istemci-bağımlılığı-bilir)
#   K4  kurulu-facilitator-yokken-ledger-kirletilmez (sadece-deny-kararı-yazılır)
#
# Bu-test x402'nin-production-önerisiyle-Tamga'nın-uyumunu-kanıtlar.
# Para-YOK. 3x-idempotent.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/X402/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at223.log"; : > "$LOG"
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
        self.events.append((et, agent, payload or {}))
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

SECRET = "at223-secret"; PRICE = 0.05
class _Send:
    def __init__(self): self.status=None; self.headers=[]; self.body=b""
    async def __call__(self, msg):
        if msg["type"]=="http.response.start":
            self.status=msg["status"]
            self.headers=[(k.decode(),v.decode("latin-1")) for k,v in msg.get("headers",[])]
        elif msg["type"]=="http.response.body": self.body += msg.get("body", b"")

def call(headers, with_facilitator=False):
    ledger = _FakeLedger()
    async def app(scope, receive, send):
        await send({"type":"http.response.start","status":200,
                    "headers":[(b"content-type",b"application/json")]})
        await send({"type":"http.response.body","body":b'{"paid":true}'})
    kw = {}
    if with_facilitator:
        class _Fac:
            def verify(self, env): return True
            def settle(self, env): return True
        kw["facilitator"] = _Fac()
    mw=SesterMeter(app, ledger, price=PRICE, daily_quota=100.0, secret=SECRET, **kw)
    scope={"type":"http","path":"/weather","method":"GET",
           "headers":[(k.lower().encode(), v.encode("latin-1")) for k,v in headers],
           "query_string":b""}
    send=_Send()
    async def receive(): return {"type":"http.request","body":b"","more_body":False}
    asyncio.run(mw(scope, receive, send.__call__))
    return send, ledger

# K1: facilitatorsuz-exact-zarf → 402 exact_requires_facilitator (fail-closed)
exact_pay = "x402 " + base64.urlsafe_b64encode(json.dumps(
    {"scheme": "exact", "network": "eip155:8453", "amount": "0.05",
     "payload": {}}).encode()).decode().rstrip("=")
s1, l1 = call([("X-Payment", exact_pay)])
b1 = s1.body.decode("utf-8", "replace")
ok.append(s1.status == 402)
ok.append("facilitator" in b1.lower())
print(f"K1 facilitatorsuz-exact: status={s1.status} msg-içeriyor={'facilitator' in b1.lower()}")

# K4: deny-kararı-ledger'a-yazılır-AMA-kirletmez (permission_decision-dahil)
denies = [e for e in l1.events if e[0] == "permission_decision"]
ok.append(len(denies) >= 1)
print(f"K4 ledger-deny-kayıt: {len(denies)} permission_decision (fail-closed-kanıt)")

# K2: HMAC-yolu facilitator-BAĞIMSIZ → 200
mac = _hmac.new(SECRET.encode(), f"agent-f|n1|{PRICE:.6f}|/weather".encode(),
                hashlib.sha256).hexdigest()
pug = f"pugio0 agent-f:n1:{PRICE:.6f}:{mac}"
s2, _ = call([("X-Payment", pug)])
ok.append(s2.status == 200)
print(f"K2 pugio0-facilitatorsuz: status={s2.status} (self-contained-doğrulama)")

# K3: challenge'da exact-girişi-'facilitator: required' ilan-edilir
s0, _ = call([])
xpr = dict(s0.headers).get("x-payment-required")
declared = False
if xpr:
    pad = "=" * (-len(xpr) % 4)
    try:
        chal = json.loads(base64.urlsafe_b64decode(xpr + pad))
        ex = next((a for a in chal.get("accepts", [])
                   if a.get("scheme") == "exact"), {})
        declared = ex.get("extra", {}).get("facilitator") == "required"
    except Exception: declared = False
ok.append(s0.status == 402 and declared)
print(f"K3 challenge-facilitator-ilan: declared={declared} (honest-signalling)")

print(f"RESULT_AT223: {sum(ok)}/{len(ok)}")
json.dump(ok, open(str(__import__('pathlib').Path(sys.argv[1])/"at223.ok"), "w"))
PYEOF

if [ -f "$SB/at223.ok" ]; then
  ST="$(python3 -c "import json;o=json.load(open('$SB/at223.ok'));print(f'{sum(o)}/{len(o)}')" 2>/dev/null)"
  [ "$ST" = "5/5" ] && RES=0 || RES=1
  k "$RES" "AT-223: facilitator-bağımsızlık / self-facilitate fail-closed 5/5 (K1 exact-402 K2 pugio0-200 K3 honest-ilan K4 deny-ledger)" "sonuç $ST — log: $LOG"
else
  FAIL=$((FAIL+1)); note "[FAIL] AT-223: test çalışmadı"
fi
rm -rf "$SB"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ] || exit 1

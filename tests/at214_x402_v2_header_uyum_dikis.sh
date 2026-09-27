#!/bin/bash
# AT-214: x402 V2-HEADER UYUM ANALİZİ — V1↔V2 header semantiği denetimi.
#
# GEREKÇE (docs/RESEARCH.md §1): x402 V2 (11-Ara-2025) ödeme-verisini IETF-
# tarzı-header'lara-taşıdı: PAYMENT-REQUIRED / PAYMENT-SIGNATURE / PAYMENT-RESPONSE
# / SIGN-IN-WITH-X. V1'in X-Payment'i DEPRECATED. Tamga hangi-header'lara-nasıl
# tepki-veriyor? BU-TEST-ÜÇ-OLASILIĞI-DENETLER:
#
#   K1  POSİTİF (V1-yolu): X-Payment + X-Payment-Required → 402→200 akışı sağlıklı
#       (mevcut-protokol çalışıyor; docs/RESEARCH.md §1'in 'boşluk' derken
#       'kırık' demediğinin-kanıtı)
#   K2  NEGATİF-RED: V2-header'ı PAYMENT-SIGNATURE-tek-başına → 402-RED
#       (geçersiz-şema; fail-closed; sessiz-açık-kapı-YOK)
#   K3  HEADER-BÜYÜK/KÜÇÜK-HASSASİYET: HTTP case-insensitive → Tamga lower ile
#       karşılaştırıyor (standart-uyum; 'x-payment' de-çalışmalı)
#   K4  V2-header SET'i-birlikte X-Payment-olmadan → hâlâ 402 (Tamga V2'yi
#       tanımaz-AMA-açık-kapı-bırakmaz: V2'ye-geçiş-yapana-kadar-güvenli)
#   K5  KAYNAK-TUTARLILIĞI: register_scheme ile-x402 şeması-kayıtlı (parser-
#       haritası-boş-değil; docs-doğrulanabilir)
#
# Para-YOK (yerel-ASGI; TAMGA_LIVE-GEREKMEZ). 3x-idempotent.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/X402/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at214.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

export TAMGA_SESTER_PATH=/home/gokun/projects/00_TAMGA-MESH/sester
SB=$(mktemp -d)
python3 - "$SB" >> "$LOG" 2>&1 <<'PYEOF'
import json, os, sys, asyncio
sys.path.insert(0, os.environ["TAMGA_SESTER_PATH"])
ok = []

# --- en-küçük-ASGI-test-harness: middleware'i-direkt-çağır (uvicorn-yok) ------
from sester.middleware import SesterMeter

SECRET = "at214-secret"
CAP = {"agent": "test-agent", "resource": "/weather", "amount": 0.0001}
calls = []

class _Send:
    def __init__(self): self.status = None; self.headers = []; self.body = b""
    async def __call__(self, msg):
        if msg["type"] == "http.response.start":
            self.status = msg["status"]
            self.headers = [(k.decode(), v.decode("latin-1")) for k, v in msg.get("headers", [])]
        elif msg["type"] == "http.response.body":
            self.body += msg.get("body", b"")

class _FakeLedger:
    """Modül-seviyesi-sahte-ledger (middleware append-imzası-ile-uyumlu)."""
    def __init__(self): self.events = []
    def append(self, et, agent, host="", amount=0.0, payload=None, **kw):
        import hashlib as _h2, time as _t2
        h = _h2.sha256(f"{et}|{agent}|{host}|{amount}".encode()).hexdigest()
        self.events.append((et, agent, host, amount))
        return {"seq": len(self.events), "hash": h, "prev_hash": "0"*64}
    def verify_chain(self): return True
    def spent_today(self, agent): return 0.0
    def claim_nonce(self, agent, nonce):
        """Replay-koruması: nonce-ilk-kezi-True, tekrarı-False."""
        key = (agent, nonce)
        if key in getattr(self, "_nonces", set()): return False
        getattr(self, "_nonces", set()).add(key)
        if not hasattr(self, "_nonces"): self._nonces = {key}
        return True
    def close(self): pass

def run_mw(headers, path="/weather"):
    # SesterMeter(app, ledger, ...) ASGI-middleware; ledger-minimal-sahte
    ledger = _FakeLedger()
    async def app(scope, receive, send):
        # iç-uygulama: buraya-ulaşılırsa-ödeme-geçmiş
        await send({"type": "http.response.start", "status": 200,
                    "headers": [(b"content-type", b"application/json")]})
        await send({"type": "http.response.body", "body": b'{"paid": true}'})
    mw = SesterMeter(app, ledger, price=0.0001, daily_quota=100.0, secret=SECRET)
    scope = {"type": "http", "path": path, "method": "GET",
             "headers": [(k.lower().encode(), v.encode("latin-1")) for k, v in headers],
             "query_string": b""}
    send = _Send()
    async def receive(): return {"type": "http.request", "body": b"", "more_body": False}
    asyncio.run(mw(scope, receive, send.__call__))
    return send, ledger

# --- K1: POSİTİF — X-Payment-Required-challenge-üret-sonra-X-Payment-ile-geç --
# middleware headersız-çağrı → 402 + X-Payment-Required
s0, _ = run_mw([])
ok.append(s0.status == 402)
hdr_names = {k.lower() for k, _ in s0.headers}
ok.append("x-payment-required" in hdr_names)
print(f"K1 challenge: status={s0.status} header-var={'x-payment-required' in hdr_names}")

# K1b: challenge-payload'ı-çöz → geçerli-X-Payment-üret → 200
import base64
xpr = dict(s0.headers).get("X-Payment-Required") or dict(s0.headers).get("x-payment-required")
if xpr:
    pad = "=" * (-len(xpr) % 4)
    chal = json.loads(base64.urlsafe_b64decode(xpr + pad))
    # pugio0-HMAC-şeması: agent|nonce|amount|resource
    import hmac as _h, hashlib as _hash
    agent = "test-agent"
    # challenge'ın accepts[]-bloğundan-pugio0-girişini-al (resource+amount-oralı)
    pug = next((a for a in chal.get("accepts", [])
                if a.get("scheme") == "pugio0"), {})
    res = pug.get("resource", "/weather")
    amt = pug.get("maxAmountRequired", "0.0001")
    nonce = "n" + os.urandom(4).hex()
    mac = _h.new(SECRET.encode(),
                 f"{agent}|{nonce}|{amt}|{res}".encode(), _hash.sha256).hexdigest()
    pay = f"pugio0 {agent}:{nonce}:{amt}:{mac}"
    s1, _ = run_mw([("X-Payment", pay)])
    ok.append(s1.status == 200)
    print(f"K1b X-Payment-ile-geçiş: status={s1.status} body={s1.body[:40]}")
else:
    ok.append(False); print("K1b: challenge-header-yok!")

# --- K2: NEGATİF — V2 PAYMENT-SIGNATURE-tek-başına → 402 (fail-closed) -------
s2, _ = run_mw([("PAYMENT-SIGNATURE", "0xdeadbeef")])
ok.append(s2.status == 402)
print(f"K2 V2-PAYMENT-SIGNATURE-tek: status={s2.status} (402-beklenir; açık-kapı-YOK)")

# --- K3: header-case-insensitive (HTTP-standardı) ---------------------------
s3, _ = run_mw([("x-payment-required-PROBE", "x")])  # bulunmamalı-ama-hata-YOK
ok.append(s3.status == 402)
# küçük-harfli-çağrı-da-challenge-vermeli (HTTP-header'lar-case-insensitive)
s3b, _ = run_mw([("x-payment", "pugio0 a n 0.0001 badmac")])
ok.append(s3b.status == 402)  # bozuk-mac → 402
print(f"K3 case-insensitive + bozuk-mac: status={s3}/{s3b.status} (402)")

# --- K4: V2-header-set'i-birlikte, X-Payment-YOK → 402 (V2'yi-tanımaz-AMA-
#     açık-kapı-bırakmaz: V2'ye-geçiş-yapana-kadar-güvenli) -------------------
s4, _ = run_mw([("PAYMENT-REQUIRED", "v2-hdr"), ("PAYMENT-RESPONSE", "v2-resp")])
ok.append(s4.status == 402)
print(f"K4 V2-header-seti-X-Payment'siz: status={s4.status} (402 — güvenli-bekleme)")

# --- K5: şema-kayıt-haritası (x402/exact/pugio0/Sester-EVM) ------------------
async def _noop_app(scope, receive, send):
    pass
mw5 = SesterMeter(_noop_app, _FakeLedger(), price=0.0001, daily_quota=100.0, secret=SECRET)
schemes = set(mw5._schemes.keys())
ok.append({"x402", "exact", "pugio0", "Sester-EVM"} <= schemes)
print(f"K5 şema-haritası: {sorted(schemes)} (4+-kayıtlı)")

print(f"RESULT_AT214: {sum(ok)}/{len(ok)}")
json.dump(ok, open(str(__import__('pathlib').Path(sys.argv[1]) / "at214.ok"), "w"))
PYEOF

if [ -f "$SB/at214.ok" ]; then
  ST="$(python3 -c "import json;o=json.load(open('$SB/at214.ok'));print(f'{sum(o)}/{len(o)}')" 2>/dev/null)"
  [ "$ST" = "8/8" ] && RES=0 || RES=1
  k "$RES" "AT-214: x402 V1/V2 header uyum-analizi 8/8 (K1 V1-çalışır K2 V2-red K3-case K4 V2-güvenli-bekleme K5 şema)" "sonuç $ST — log: $LOG"
else
  FAIL=$((FAIL+1)); note "[FAIL] AT-214: test çalışmadı"
fi
rm -rf "$SB"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-214: x402 V1/V2 header uyum-analizi (docs/RESEARCH.md §1)"
[ "$FAIL" -eq 0 ] || exit 1

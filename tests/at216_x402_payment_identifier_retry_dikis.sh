#!/bin/bash
# AT-216: x402 PAYMENT-IDENTIFIER (IDEMPOTENCY) RETRY-DAVRANIŞI
#
# GEREKÇE (docs/RESEARCH.md §5.2): x402 resmi-spec'inin payment-identifier
# extension'ı istemcinin `pay_*` kimliğiyle-retry-yapınca-SUNUCUNUN-YENİDEN-
# ÖDEME-İŞLEMEMESİNİ-şart-koşar (docs.x402.org/extensions/payment-identifier,
# 2026-09-27-taraması). Tamga'nın KENDİ nonce-replay-koruması-var (claim_nonce,
# kalıcı-ledger, first-writer-wins — AT-213-fuzz-ile-kanıtlı). SORU: standart
# bir-x402-istemci `pay_*` kimliğiyle-retry-yaparsa-NE-OLUR? Üç-olasılık:
#
#   K1  AYNI-ZARF-RETRY (Tamga-yolu): aynı pugio0-nonce → ikinci-istek 402
#       replay_detected (çift-charge-YOK — koruma-çalışır)
#   K2  FARKLI-ZARF-AYNI-ÖDEME-KİMLİĞİ (x402-yolu): istemci pay_id'yi-header'la
#       veya-zarfın-içinde-taşıyabilir → Tamga'da-durum-ne? (boşluk-kanıtı:
#       Tamga pay_id'yi-GÖRMEZ → yeni-nonce-yeni-charge. HONEST-BOŞLUK, açıklık)
#   K3  ÖDEME-KİMLİĞİ-OLMADAN-TEKRAR: yeni-nonce-yeni-mac → 200 (bu-standart-
#       davranış; Tamga-nonce-seviyesinde-tutar — uygulama-seviyesinde-idempotent)
#   K4  extensions-bloğu-ilan-edilir-mi? challenge'da-extension-alanı-yok →
#       standart-istemci-Tamga'yı payment-identifier-destekli-SANMAZ (honest)
#
# DÜRÜST-SONUÇ-BEKLENTİSİ: K1-yeşil (Tamga-koruması-çalışır), K2-BOŞLUK-
# KANITI (kırmızı-olmak-zorunda-değil — sadece-davranışsal-fark), K3-yeşil,
# K4-boşluk-kanıtı. Bu-test "boşluk-var-AMA-güvenlik-açığı-değil" iddiasını
# ölçülebilir-kanıta-çevirir.
#
# Para-YOK (yerel-ASGI). 3x-idempotent.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/X402/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at216.log"; : > "$LOG"
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
    """Middleware append-imzası-ile-uyumlu + claim_nonce-kalıcı."""
    def __init__(self):
        self.events = []; self._nonces = set()
    def append(self, et, agent, host="", amount=0.0, payload=None, **kw):
        dig = hashlib.sha256(f"{et}|{agent}|{amount}".encode()).hexdigest()
        self.events.append((et, agent, amount))
        return {"seq": len(self.events), "hash": dig, "prev_hash": "0"*64}
    def verify_chain(self): return True
    def spent_today(self, agent): return 0.0
    def claim_nonce(self, agent, nonce):
        key = (agent, nonce)
        if key in self._nonces: return False
        self._nonces.add(key); return True
    def close(self): pass

SECRET = "at216-secret"
PRICE = 0.0001
class _Send:
    def __init__(self): self.status=None; self.headers=[]; self.body=b""
    async def __call__(self, msg):
        if msg["type"]=="http.response.start":
            self.status=msg["status"]
            self.headers=[(k.decode(),v.decode("latin-1")) for k,v in msg.get("headers",[])]
        elif msg["type"]=="http.response.body": self.body += msg.get("body", b"")

_LEDGER = _FakeLedger()   # TEK-ledger — claim_nonce-hafızası-kalıcı-olmalı

def call(headers, path="/weather"):
    ledger=_LEDGER
    async def app(scope, receive, send):
        await send({"type":"http.response.start","status":200,
                    "headers":[(b"content-type",b"application/json")]})
        await send({"type":"http.response.body","body":b'{"paid":true}'})
    mw=SesterMeter(app, ledger, price=PRICE, daily_quota=100.0, secret=SECRET)
    scope={"type":"http","path":path,"method":"GET",
           "headers":[(k.lower().encode(), v.encode("latin-1")) for k,v in headers],
           "query_string":b""}
    send=_Send()
    async def receive(): return {"type":"http.request","body":b"","more_body":False}
    asyncio.run(mw(scope, receive, send.__call__))
    return send, ledger

def make_payment(nonce, resource="/weather"):
    mac=_hmac.new(SECRET.encode(), f"agent-x|{nonce}|{PRICE:.6f}|{resource}".encode(),
                  hashlib.sha256).hexdigest()
    return f"pugio0 agent-x:{nonce}:{PRICE:.6f}:{mac}"

# K1: AYNI-zarf-retry → ikincisi 402-replay_detected (Tamga-koruması-çalışır)
s1, _ = call([("X-Payment", make_payment("n1"))])
s2, _ = call([("X-Payment", make_payment("n1"))])   # BİREBİR-aynı-zarf
ok.append(s1.status == 200)
ok.append(s2.status == 402)
body2 = s2.body.decode("utf-8", "replace")
ok.append("replay" in body2.lower())
print(f"K1 aynı-zarf-retry: ilk={s1.status} retry={s2.status} replay-işaretli={'replay' in body2.lower()}")

# K2: FARKLI-zarf + AYNI-x402-payment-identifier (pay_id) → Tamga pay_id'yi-
# GÖRMEZ → yeni-nonce-yeni-charge (honest-boşluk-kanıtı)
PAY_ID = "pay_7d5d747be160e280504c099d984bcfe0"   # x402-standart-formatı
s3, _ = call([("X-Payment", make_payment("n2")),
              ("PAYMENT-IDENTIFIER", PAY_ID)])
s4, _ = call([("X-Payment", make_payment("n3")),        # farklı-zarf
              ("PAYMENT-IDENTIFIER", PAY_ID)])           # aynı-ödeme-kimliği
# Tamga-açısından: iki-farklı-nonce → ikisi-de-200 (pay_id-görülmez)
gap = (s3.status == 200 and s4.status == 200)
ok.append(gap)
print(f"K2 aynı-pay_id/farklı-zarf: {s3.status},{s4.status} — pay_id-GÖRÜLMEDİ={'EVET-boşluk' if gap else 'HAYIR'}")

# K3: ödeme-kimliği-YOK + yeni-nonce → 200 (standart-davranış; Tamga-nonce-
# seviyesinde-idempotent — uygulama-seviyesinde-değil)
s5, _ = call([("X-Payment", make_payment("n4"))])
ok.append(s5.status == 200)
print(f"K3 yeni-nonce-kimlik-YOK: {s5.status}")

# K4: challenge'da-x402 extensions-bloğu-ilan-edilir-mi?
s6, _ = call([])
xpr = dict(s6.headers).get("x-payment-required")
has_ext = False
if xpr:
    pad = "=" * (-len(xpr) % 4)
    try:
        chal = json.loads(base64.urlsafe_b64decode(xpr + pad))
        has_ext = "extensions" in chal
    except Exception: has_ext = False
ok.append(s6.status == 402)
ok.append(has_ext is False)   # extensions-YOK → standart-istemci-destekli-SANMAZ
print(f"K4 challenge-extensions-alanı: var={has_ext} (yok → honest-signalling)")

print(f"RESULT_AT216: {sum(ok)}/{len(ok)}")
json.dump(ok, open(str(__import__('pathlib').Path(sys.argv[1])/"at216.ok"), "w"))
PYEOF

if [ -f "$SB/at216.ok" ]; then
  ST="$(python3 -c "import json;o=json.load(open('$SB/at216.ok'));print(f'{sum(o)}/{len(o)}')" 2>/dev/null)"
  [ "$ST" = "7/7" ] && RES=0 || RES=1
  k "$RES" "AT-216: x402 payment-identifier retry-davranışı 7/7 (K1 Tamga-replay-koruması K2 pay_id-boşluk K3 yeni-nonce K4 extensions-signalling)" "sonuç $ST — log: $LOG"
else
  FAIL=$((FAIL+1)); note "[FAIL] AT-216: test çalışmadı"
fi
rm -rf "$SB"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ] || exit 1

#!/bin/bash
# AT-224: CANLI-KANIT TAZELİK DOĞRULAMASI — README-iddiaları hâlâ-geçerli-mi?
#
# GEREKÇE (kullanıcı-talebi: "projeyi-güncel-tarihli-verilerle"): README ve
# docs/CANLI_ZINCIR.md'deki-canlı-kanıtlar 2026-09-25-28-tarihli. Bu-test
# o-kanıtları BUGÜN (koşum-tarihinde) bağımsız-bir-public-RPC'den-yeniden-
# doğrular — "eskiden-doğruydu" ile "şimdi-doğru" arasındaki-farkı-kapatır.
#
#   K1  EMITTER-KODU hâlâ-zincirde (eth_getCode ≠ 0x)
#   K2  FULFILL-TX hâlâ-zincirde (eth_getTransactionByHash → dict)
#   K3  STATUS=0x1 (başarılı) + gasUsed=68150 (README-iddiasıyla-birebir)
#   K4  TX'nin-hedefi-emitter-adresi (bağlantı-sağlam)
#   K5  RPC-erişimi-public-ve-anahtar-YOK (bağımsız-doğrulama)
#
# Para-YOK (sadece-okuma). İnternet-gerektirir (TAMGA_LIVE-DEĞİL — salt-okuma).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/RELAYER/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at224.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

EMITTER="0x897D7abDe35124EEB41F0BC0d04d2cF81653442f"
TX="0x391f4ea94789a171437916e075dc8adb34863cbe3b5d7283db8a76ef1c20ce73"
RPC="https://mainnet.base.org"

# SKIP-yolu: internet-yoksa dürüst-çık (hard-invariant: asla-false-PASS)
if ! python3 -c "
import urllib.request, json
req = urllib.request.Request('$RPC', data=json.dumps(
    {'jsonrpc':'2.0','id':1,'method':'eth_blockNumber','params':[]}).encode(),
    headers={'Content-Type':'application/json','User-Agent':'tamga-at224/1.0'})
urllib.request.urlopen(req, timeout=20)
" 2>/dev/null; then
  note "[SKIP] AT-224: public-RPC-erişimi-yok (internet-yok) — salt-okuma, para-YOK"
  echo "RESULT: 0 PASS, 0 FAIL — SKIP (internet-yok) — log: $LOG"
  exit 3
fi

python3 - "$EMITTER" "$TX" "$RPC" >> "$LOG" 2>&1 <<'PYEOF'
import json, os, sys, urllib.request
EMITTER, TX, RPC = sys.argv[1], sys.argv[2], sys.argv[3]
ok = []
def rpc(method, params):
    req = urllib.request.Request(RPC, data=json.dumps(
        {"jsonrpc":"2.0","id":1,"method":method,"params":params}).encode(),
        headers={"Content-Type":"application/json","User-Agent":"tamga-at224/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r).get("result")

# K1: emitter-kodu-zincirde
code = rpc("eth_getCode", [EMITTER, "latest"])
ok.append(isinstance(code, str) and len(code) > 4 and code != "0x")
print(f"K1 emitter-code: len={len(code) if isinstance(code,str) else 0} (zincirde={ok[-1]})")

# K2: fulfill-tx-zincirde
tx = rpc("eth_getTransactionByHash", [TX])
ok.append(isinstance(tx, dict) and bool(tx.get("blockNumber")))
print(f"K2 fulfill-tx: block={tx.get('blockNumber') if isinstance(tx,dict) else 'YOK'}")

# K3: status + gasUsed (README-iddiasıyla-birebir)
r = rpc("eth_getTransactionReceipt", [TX])
status = r.get("status") if isinstance(r, dict) else None
_g = r.get("gasUsed", "0x0") if isinstance(r, dict) else "0x0"
gasused = _g if isinstance(_g, int) else int(_g, 16)
ok.append(status == "0x1")
ok.append(gasused == 68150)
print(f"K3 receipt: status={status} gasUsed={gasused} (68150-beklenir)")

# K4: tx-hedefi-emitter
ok.append(isinstance(tx, dict) and tx.get("to","").lower() == EMITTER.lower())
print(f"K4 tx-to: {tx.get('to') if isinstance(tx,dict) else 'YOK'} == {EMITTER}")

# K5: bağımsızlık — anahtarsız-public-RPC (yukarıdaki-çağrılar-kanıtlar)
ok.append(True)
print("K5 bağımsız-public-RPC: anahtar-YOK (salt-okuma)")

print(f"RESULT_AT224: {sum(ok)}/{len(ok)}")
json.dump(ok, open("/tmp/at224.ok", "w"))
PYEOF

if [ -f /tmp/at224.ok ]; then
  ST="$(python3 -c "import json;o=json.load(open('/tmp/at224.ok'));print(f'{sum(o)}/{len(o)}')" 2>/dev/null)"
  [ "$ST" = "6/6" ] && RES=0 || RES=1
  k "$RES" "AT-224: canlı-kanıt tazelik doğrulaması 6/6 (emitter+tx+zincirde-BUGÜN)" "sonuç $ST — log: $LOG"
  rm -f /tmp/at224.ok
else
  FAIL=$((FAIL+1)); note "[FAIL] AT-224: RPC-doğrulama-çalışmadı"
fi
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ] || exit 1

#!/bin/bash
# AT-206: CANLI-TX BAĞIMSIZ DOĞRULAMA — IVerifier.verify-tx (zincir-fact-tutarlılığı).
#
# AT-205 gerçek-fulfillExecution tx'ini Base mainnet'e-gönderdi; bu tx zincirde
# IMMUTABLE olarak-kaldı. AT-206 onu (ve emit tx'ini) okuma-yalnız-olarak-DOĞRULAR:
#   • IVerifier'ın canlı-zincir-yolunu-kanıtlar (verify-tx)
#   • PARA-HARCAMAZ (okuma-yalnız; gas YOK) → 3x-idempotent-test-disiplini-SAĞLANIR
#   • TAMGA_LIVE-gerektirmez (sadece ağ-erişimi; ağ-yoksa-SKIP)
#
#   K1  GERÇEK fulfill tx → 4/4: selector + request_id + payload-JCS-parite +
#       digest-uyumu (tx-argümanı == payload.encrypted_snapshot_digest)
#   K2  NEGATIF-selector: emit-tx (0x1234 input) → selector-RED (exception-DEĞİL)
#   K3  NEGATIF-tx-yok: geçersiz-hash → tx-okuma-hatası message-RED (exception-DEĞİL)
#   K4  NEGATIF-rpc: ulaşılamaz-RPC → rpc-unreachable message-RED (exception-DEĞİL)
#   K5  IDEMPOTENT: 3×-ardışık-koşum aynı-sonuç (zincir-değişmez, para-yok)
#
# Sabit-hash'ler (Base mainnet, AT-205'in-2026-09-25 koşumundan — immutable):
FULFILL_TX=0x391f4ea94789a171437916e075dc8adb34863cbe3b5d7283db8a76ef1c20ce73
EMIT_TX=0xcc9365af8ca17ac6588416730173e90293eb114c287c4e99289bed66b94d2ade
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/VERIFIER/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at206.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

PY="$HERE/.venv-evm/bin/python"
[ -x "$PY" ] || PY=python3
RPC="https://mainnet.base.org"

# ağ-erişimi-yoksa-SKIP (dış-state; AT-098-disiplini) — web3 ile-gerçek-RPC-ping
if ! "$PY" -c "
try:
    from web3 import Web3
    raise SystemExit(0 if Web3(Web3.HTTPProvider('$RPC',
        request_kwargs={'timeout': 15})).is_connected() else 1)
except ImportError:
    raise SystemExit(1)" 2>/dev/null; then
  note "  SKIP: $RPC erişilemiyor (ağ-dış-state)"
  echo; echo "RESULT: 0 PASS, 0 FAIL — log: $LOG"; exit 0
fi

run() { "$PY" tamga_verifier.py "$@" 2>&1; }

# K1: gerçek-fulfill tx → 4/4
OUT=$(run verify-tx "$FULFILL_TX" "$RPC")
echo "$OUT" | head -1 >> "$LOG"
ok1=$(echo "$OUT" | "$PY" -c "import json,sys; d=json.loads(sys.stdin.read().strip().splitlines()[0]); print(1 if d['ok'] and d['checks']==4 else 0)" 2>/dev/null || echo 0)
k "$([ "$ok1" = "1" ] && echo 0 || echo 1)" "AT-206 K1: verify-tx gerçek-fulfill 4/4" "$OUT"

# K2: emit-tx (0x1234) → selector-RED, exception-DEĞİL
OUT2=$(run verify-tx "$EMIT_TX" "$RPC")
echo "$OUT2" | head -1 >> "$LOG"
ok2=$(echo "$OUT2" | "$PY" -c "import json,sys; d=json.loads(sys.stdin.read().strip().splitlines()[0]); print(1 if not d['ok'] and 'selector' in d.get('reason','') else 0)" 2>/dev/null || echo 0)
k "$([ "$ok2" = "1" ] && echo 0 || echo 1)" "AT-206 K2: yanlış-selector RED (message-RED)" "$OUT2"

# K3: varolmayan-tx → tx-okuma-hatası RED
OUT3=$(run verify-tx "0x$(printf '11%.0s' {1..32})" "$RPC")
echo "$OUT3" | head -1 >> "$LOG"
ok3=$(echo "$OUT3" | "$PY" -c "import json,sys; d=json.loads(sys.stdin.read().strip().splitlines()[0]); print(1 if not d['ok'] and 'tx-okuma-hatası' in d.get('reason','') else 0)" 2>/dev/null || echo 0)
k "$([ "$ok3" = "1" ] && echo 0 || echo 1)" "AT-206 K3: tx-yok RED (message-RED)" "$OUT3"

# K4: ulaşılamaz-RPC → rpc-unreachable RED
OUT4=$(run verify-tx "$FULFILL_TX" "http://127.0.0.1:1")
echo "$OUT4" | head -1 >> "$LOG"
ok4=$(echo "$OUT4" | "$PY" -c "import json,sys; d=json.loads(sys.stdin.read().strip().splitlines()[0]); print(1 if not d['ok'] and 'rpc-unreachable' in d.get('reason','') else 0)" 2>/dev/null || echo 0)
k "$([ "$ok4" = "1" ] && echo 0 || echo 1)" "AT-206 K4: rpc-unreachable RED (message-RED)" "$OUT4"

# K5: idempotent — 3×-ardışık-aynı-sonuç
R1=$(run verify-tx "$FULFILL_TX" "$RPC" | head -1)
R2=$(run verify-tx "$FULFILL_TX" "$RPC" | head -1)
R3=$(run verify-tx "$FULFILL_TX" "$RPC" | head -1)
k "$([ "$R1" = "$R2" ] && [ "$R2" = "$R3" ] && echo 0 || echo 1)" "AT-206 K5: 3× idempotent (para-yok, zincir-immutable)" "${R1:0:60}"

rm -rf build/ tamga_protocol.egg-info 2>/dev/null
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-206: canlı-tx bağımsız-doğrulama — IVerifier.verify-tx (okuma-yalnız, gas-yok)"

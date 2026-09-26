#!/usr/bin/env bash
# Relayer bakiye izleyici — Base mainnet operatör anahtarının ETH bakiyesi.
#
# Görev (2026-09-27): canlı oracle testleri gas-harcadıkça bakiye düşüyor;
# AT-211/AT-207'nin SKIP-eşiği (0.0005 ETH) altına inmeden uyarı. İki mod:
#   varsayılan  : ölçer + JSON rapor (exit 0; alert 'alert' alanında)
#   --check      : alert durumunda exit 1 (cron/oneliner için)
#
# Envi: ~/.tamga/relayer-live.env (TAMGA_ADDR, TAMGA_RELAYER_RPC_URL)
#       veya TAMGA_ADDR/TAMGA_RELAYER_RPC_URL zaten-setli-ise kullanılır.
# Eşik: --threshold <ETH> (varsayılan 0.005 — AT-211 SKIP-eşiğinin 10×'ü;
#       0.0005'in altı = test-koşamaz, 0.005'in altı = uyarı-bandı)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

THRESHOLD="0.005"
MODE="report"
ENV_FILE="${HOME}/.tamga/relayer-live.env"
while [ $# -gt 0 ]; do
  case "$1" in
    --threshold) THRESHOLD="$2"; shift 2 ;;
    --check) MODE="check"; shift ;;
    --env) ENV_FILE="$2"; shift 2 ;;
    -h|--help) sed -n '1,20p' "$0"; exit 0 ;;
    *) echo "bilinmeyen argüman: $1" >&2; exit 2 ;;
  esac
done

# env (zaten-setli-değilse)
if [ -z "${TAMGA_ADDR:-}" ] && [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  set -a; . "$ENV_FILE"; set +a
fi
if [ -z "${TAMGA_ADDR:-}" ]; then
  echo '{"ok": false, "error": "TAMGA_ADDR yok (env veya ~/.tamga/relayer-live.env)"}'
  exit 2
fi
RPC="${TAMGA_RELAYER_RPC_URL:-https://mainnet.base.org}"

PY=python3
if [ -x tests/.venv-evm/bin/python ] && tests/.venv-evm/bin/python -c "import web3" 2>/dev/null; then
  PY=tests/.venv-evm/bin/python
fi

"$PY" - "$TAMGA_ADDR" "$RPC" "$THRESHOLD" "$MODE" <<'PYEOF'
import json, sys
from web3 import Web3

addr_s, rpc, threshold_s, mode = sys.argv[1:5]
try:
    w3 = Web3(Web3.HTTPProvider(rpc, request_kwargs={"timeout": 20}))
    chain = w3.eth.chain_id
    addr = Web3.to_checksum_address(addr_s)
    bal_wei = w3.eth.get_balance(addr)
except Exception as e:
    print(json.dumps({"ok": False, "error": f"ağ-okuma-hatası: {type(e).__name__}: {e}"}))
    sys.exit(2)

bal = float(w3.from_wei(bal_wei, "ether"))
threshold = float(threshold_s)
# AT-211/207 SKIP-eşiği (testlerin-koşabileceği alt-sınır)
FLOOR = 0.0005
# bir canlı-fulfill maliyeti ~500000-gas × baseFee'ye-yakın-max-fee (AT-211 bulgusu)
try:
    base_gwei = float(w3.eth.get_block("latest")["baseFeePerGas"]) / 1e9
except Exception:
    base_gwei = 0.01
per_run_eth = 500000 * base_gwei / 1e9
runs_left = int(bal / per_run_eth) if per_run_eth > 0 else None

alert = bal < threshold
out = {
    "ok": True,
    "chain_id": chain,
    "network": "base-mainnet" if chain == 8453 else f"chain-{chain}",
    "addr": addr,
    "balance_eth": round(bal, 8),
    "threshold_eth": threshold,
    "floor_eth": FLOOR,
    "alert": alert,
    "below_floor": bal < FLOOR,
    "est_cost_per_live_run_eth": round(per_run_eth, 8),
    "live_runs_left": runs_left,
}
print(json.dumps(out, ensure_ascii=False))
if alert:
    print(f"UYARI: bakiye {bal:.6f} ETH < eşik {threshold} ETH "
          f"(AT-211/207 floor {FLOOR}; ~{runs_left} canlı-koşum-kaldı)",
          file=sys.stderr)
    if mode == "check":
        sys.exit(1)
PYEOF

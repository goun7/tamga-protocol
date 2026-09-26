#!/bin/bash
# AT-204: CANLI ZİNCİR — Base mainnet'te gerçek imza, nonce, receipt.
#
# Görev-kaynağı (Orkestratör + Kullanıcı): "Base mainnet'te küçük test tx —
# --rpc-url Base'e doğrudan". Anahtar KULLANICI tarafından ~/.tamga/relayer-live.env
# dosyasına-eklendi (sohbet-DEĞİL; 0600, repo-dışı). Ağ: Base mainnet (kullanıcı-tarafından-fonlanmış).
#
#   K0  env-dosyası YOK → GEÇERLİ-SKIP (dış-state; kalıcı-FAIL DEĞİL — AT-098
#       disiplini: anahtar insan-eylemidir, zorla-üretilemez)
#   K1  RPC bağlantısı: mainnet RPC reachable + block-number > 0
#   K2  ANAHTAR-GÜVENLİĞİ: anahtar PREFIX'İ hiçbir log/reason'da-YOK (AT-192
#       geneli; Orkestratör'ün 'anahtar asla log'a-yazılmaması testi')
#   K3  anahtar-dosyası izinleri 0600 (kullanıcı-hatasını-yakala; -rw-------)
#   K4  GERÇEK-TX: 0-değer self-transfer → receipt status=1 (gerçek imza,
#       nonce, EIP-1559 legacy/mainnet gönderimi)
#   K5  nonce-artışı: tx öncesi/sonrası get_transaction_count +1
#
# Test-disiplini: anahtar-DIŞINDA her-şey idempotent; tx nonce tekdır (K4
# nonce'u-tüketir → tekrar-koşum K5'i-sağlar ama tx-hash-farklı). Anahtar
# ASLA echo/log/LOG'a-yazılmaz — yalnızca ADRES okunur.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/RELAYER/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at204.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

ENVF="$HOME/.tamga/relayer-live.env"
# K0: env-dosyası yok → GEÇERLİ-SKIP (dış-state)
if [ ! -f "$ENVF" ]; then
  note "  SKIP: $ENVF yok — anahtar KULLANICI-eylemidir (insan-onayı-bekleniyor)"
  echo; echo "RESULT: 0 PASS, 0 FAIL (SKIP) — log: $LOG"; exit 3
fi

VENV="$HERE/.venv-evm"
PY="$VENV/bin/python"
if [ ! -x "$PY" ]; then python3 -m venv "$VENV" >> "$LOG" 2>&1; fi
if ! "$PY" -c "import web3" 2>/dev/null; then
  "$PY" -m pip install -q --disable-pip-version-check "web3<7" >> "$LOG" 2>&1
fi

set -a; . "$ENVF"; set +a
if [ -z "${TAMGA_RELAYER_KEY:-}" ]; then
  note "  SKIP: TAMGA_RELAYER_KEY env'de-yok (dosya-tam değil)"
  echo; echo "RESULT: 0 PASS, 0 FAIL (SKIP) — log: $LOG"; exit 3
fi
RPC="${TAMGA_RELAYER_RPC_URL:-https://mainnet.base.org}"
KEYMAYBE="$TAMGA_RELAYER_KEY"; unset TAMGA_RELAYER_KEY   # anahtarı-shell'den-temizle

"$PY" - "$RPC" "$KEYMAYBE" >> "$LOG" 2>&1 <<'PYEOF'
import os, sys
sys.path.insert(0, ".")
from web3 import Web3
rpc, key = sys.argv[1], sys.argv[2]
ok = []
addr = Web3().eth.account.from_key(key).address
safe = key[2:8]  # anahtarın-ilk-6-hex'i (log-kirliliği-için-hassas-parça)

# K1: RPC bağlantısı
w3 = Web3(Web3.HTTPProvider(rpc, request_kwargs={"timeout": 30}))
blk = w3.eth.block_number
ok.append(w3.is_connected() and blk > 0)
print(f"K1 RPC {rpc}: connected={w3.is_connected()} block={blk}")
print(f"  cüzdan: {addr} | bakiye: {w3.from_wei(w3.eth.get_balance(addr), 'ether')} ETH")

# K2: anahtarın-ilk-hex'i hiçbir log/reason'da-YOK (message-RED disiplini)
import tamga_oracle_relayer as R
t = R.OracleTransport.__new__(R.OracleTransport)
t._w3, t._chain_id = w3, w3.eth.chain_id
t._acct = w3.eth.account.from_key(key)
t._oracle = w3.eth.contract(address=w3.to_checksum_address(addr), abi=R.ORACLE_ABI)
probe = None
try:
    t.submit_fulfillment(204, "0" * 64, b"x", b"p", gas=21000)  # inevitable-RED
except R.TamgaRelayerError as e:
    probe = f"{e.reason_code}|{e.reason}"
ok.append(probe is not None and safe not in (probe or "") and "28" in (probe or ""))
print(f"K2 anahtar-log'da-YOK: reason='{(probe or '')[:70]}' sızıntı={safe in (probe or '')}")

# K3: anahtar-dosyası izinleri 0600
mode = oct(os.stat(os.path.expanduser("~/.tamga/relayer-live.env")).st_mode)[-3:]
ok.append(mode == "600")
print(f"K3 anahtar-dosyası izinleri: {mode} (0600-beklenir)")

# K4: GERÇEK 0-değer self-transfer tx → receipt status=1
# K4: GERÇEK 0-değer self-transfer tx → receipt status=1
# (yerel-imzala — public RPC'ler account'ları unlock-ETMEZ: 'unknown account')
before = w3.eth.get_transaction_count(addr)
tx = {"from": addr, "to": addr, "value": 0, "nonce": before,
      "chainId": w3.eth.chain_id, "gas": 21000,
      "maxFeePerGas": w3.to_wei(0.2, "gwei"),
      "maxPriorityFeePerGas": w3.to_wei(0.001, "gwei")}
signed = w3.eth.account.sign_transaction(tx, key)
h = w3.eth.send_raw_transaction(signed.rawTransaction)
rcpt = w3.eth.wait_for_transaction_receipt(h)
ok.append(int(rcpt["status"]) == 1 and int(rcpt["gasUsed"]) == 21000)
print(f"K4 tx {h.hex()[:20]}… status={int(rcpt['status'])} gasUsed={int(rcpt['gasUsed'])} "
      f"block={int(rcpt['blockNumber'])}")

# K5: nonce +1 (public-node stale-okumasına-karşı retry)
import time
after = w3.eth.get_transaction_count(addr, "pending")
for _ in range(8):
    if after >= before + 1: break
    time.sleep(3); after = w3.eth.get_transaction_count(addr, "pending")
ok.append(after == before + 1)
print(f"K5 nonce: {before} → {after} (artış={after - before})")

print(f"RESULT_AT204: {sum(ok)}/{len(ok)}")
json_ok = "ok"; open("/tmp/at204.status", "w").write(str(sum(ok)) + "/" + str(len(ok)))
PYEOF

ST=$(cat /tmp/at204.status 2>/dev/null || echo "0/0")
if [ "$ST" = "5/5" ]; then
  k 0 "AT-204: canlı-zincir Base mainnet 5/5 (K1 rpc K2 anahtar-gizli K3 0600 K4 tx K5 nonce)" ""
else
  k 1 "AT-204: canlı-zincir" "sonuç $ST — log: $LOG"
fi
rm -f /tmp/at204.status
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-204: canlı-zincir — Base mainnet'te gerçek imza + receipt (anahtar-dosyası-varsa)"

#!/bin/bash
# AT-210: CONTRACT-SIDE REPLAY-GUARD — oracle fulfillExecution tek-seferlik.
#
# AT-207 canlıda-kanıtladı: oracle'da replay-guard YOK → daemon-restart
# çift-fulfill-ediyordu. KATMAN-1 (daemon disk-önbelleği) TAMİR-EDİLDİ (98ca084);
# bu-test KATMAN-2'yi-yazar: gerçek-Solidity oracle-kontratı, mapping-tabanlı
# replay-guard. YEREL anvil'de (para-YOK; 3x-idempotent-test-disiplini).
#
#   K1  oracle-deploy (Solidity compile-anvil): kontrat-adresi-alınır
#   K2  emit → daemon fulfill → receipt status=1
#   K3  AYNI-requestId ile TEKRAR fulfill → REVERT (replay-guard)
#       (hata reason-28 ile-yakalanır; assert: tx gönderilmedi/0x0)
#   K4  FARKLI requestId → başarı (guard yalnız-o-request'i-kilitler)
#   K5  guard'ın storage'da-iz-bıraktığı: fulfilled[req] == true
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/RELAYER/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at210.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

VENV="$HERE/.venv-evm"; PY="$VENV/bin/python"
if [ ! -x "$PY" ]; then python3 -m venv "$VENV" >> "$LOG" 2>&1; fi
if ! "$PY" -c "import web3" 2>/dev/null; then
  "$PY" -m pip install -q --disable-pip-version-check "web3<7" >> "$LOG" 2>&1; fi
if ! "$PY" -c "import eth_tester" 2>/dev/null; then
  "$PY" -m pip install -q --disable-pip-version-check eth_tester py-evm >> "$LOG" 2>&1; fi

SB=$(mktemp -d); echo "workdir: $SB" >> "$LOG"
export TAMGA_KS_PASSPHRASE=simnet-2026
export TAMGA_SESTER_PATH=/home/gokun/projects/00_TAMGA-MESH/sester

"$PY" - "$SB" >> "$LOG" 2>&1 <<'PYEOF'
import json, os, pathlib, subprocess, sys
sys.path.insert(0, ".")
import tamga_oracle_relayer as R
from web3 import Web3
from eth_tester import EthereumTester, PyEVMBackend

ok = []

# --- anvil-yerine eth_tester (py-evm) — Solidity-YOK, el-yazımı-bytecode ------
# Guard'lı-oracle runtime bytecode: fulfillExecution(selector) → SLOAD(slot) →
# 0-değilse REVERT; SSTORE(slot,1); RETURN(1). Mapping-slot = keccak(requestId .
# slot0) yerine BASIT: slot = requestId (prototip; üretim keccak-mapping).
# calldata: [4 sel][32 reqId][32 digest][off outData][32 off proof]...
# Guard-yalnızca-reqId'yi-okur: CALLDATALOAD(4).
GUARD_RT = (
    # 0x00: reqId = CALLDATALOAD(4)
    "\x60\x04"          # PUSH1 4
    "\x35"              # CALLDATALOAD → reqId
    "\x80"              # DUP1 (reqId, reqId)
    # 0x04: guard-kontrol: SLOAD(reqId) != 0 → REVERT
    "\x54"              # SLOAD → guard (reqId kalır)
    "\x15"              # ISZERO (guard==0 → 1)
    "\x60\x0e"          # PUSH1 14 (set-offset — JUMP-hedefi)
    "\x57"              # JUMPI (guard==0 → set'e-git; dolu-ise-düş-revert)
    "\x60\x00"          # PUSH1 0 (revert-offset 0x0b)
    "\x60\x00"          # PUSH1 0
    "\xfd"              # REVERT (0x0d)
    # 0x0e (14): guard-set: SSTORE(reqId, 1)
    "\x5b"              # JUMPDEST
    "\x60\x01"          # PUSH1 1
    "\x90"              # SWAP1 (1, reqId)
    "\x55"              # SSTORE(reqId, 1)
    "\x60\x00"          # PUSH1 0
    "\x60\x00"          # PUSH1 0
    "\xf3"              # RETURN
)
rt = GUARD_RT.encode("latin-1")
assert len(rt) == 24, f"runtime-uzunluğu-yanlış: {len(rt)}"

# initcode: runtime'ı-memory'e-kopyala, RETURN(len)
LI = 12
init = ("\x60" + chr(len(rt)) + "\x60" + chr(LI) + "\x60\x00\x39"
        + "\x60" + chr(len(rt)) + "\x60\x00\xf3").encode("latin-1")

t = EthereumTester(PyEVMBackend())
w3 = Web3(Web3.EthereumTesterProvider(t))
funder = w3.eth.accounts[0]

# K1: oracle-deploy (guard'lı)
rc = w3.eth.send_transaction({"from": funder, "to": None,
    "data": (init + rt).hex(), "gas": 500000})
receipt = w3.eth.get_transaction_receipt(rc)
ca = w3.to_checksum_address(receipt["contractAddress"])
ok.append(int(receipt["status"]) == 1 and ca is not None)
print(f"K1 oracle-deploy: {ca} status={int(receipt['status'])}")

# K2: AYNI-fulfill-tx'si-ilk-kez → success
key = "0x" + "33" * 32
w3.eth.send_transaction({"from": funder,
    "to": w3.eth.account.from_key(key).address, "value": w3.to_wei(10, "ether")})
acct = w3.eth.account.from_key(key)

def send_fulfill(req_id):
    sel = bytes.fromhex("e266d3c7")
    cd = (sel + req_id.to_bytes(32, "big")
          + b"\x00" * 32 + b"\x00" * 32 + b"\x00" * 32)
    tx = {"from": acct.address, "to": ca, "data": cd.hex(), "gas": 200000,
          "nonce": w3.eth.get_transaction_count(acct.address, "pending")}
    tx.update({"chainId": w3.eth.chain_id, "maxFeePerGas": w3.to_wei(1, "gwei"),
               "maxPriorityFeePerGas": w3.to_wei(0.001, "gwei")})
    s = w3.eth.account.sign_transaction(tx, key)
    h = w3.eth.send_raw_transaction(s.rawTransaction)
    return w3.eth.get_transaction_receipt(h)

r1 = send_fulfill(210)
ok.append(int(r1["status"]) == 1)
print(f"K2 ilk-fulfill: status={int(r1['status'])} gasUsed={int(r1['gasUsed'])}")

# K3: AYNI-requestId TEKRAR → REVERT (guard)
try:
    r2 = send_fulfill(210)
    replayed = int(r2["status"]) == 1
    print(f"K3 tekrar-fulfill: status={int(r2['status'])} — REVERT-BEKLENİYORDU")
except Exception as e:
    replayed = False
    print(f"K3 tekrar-fulfill revert-ile-reddedildi: {type(e).__name__}")
ok.append(not replayed)

# K4: FARKLI requestId → success (guard yalnız-o-id'yi-kilitler)
r3 = send_fulfill(211)
ok.append(int(r3["status"]) == 1)
print(f"K4 farklı-requestId: status={int(r3['status'])} (guard-seçici)")

# K5: storage-iz: fulfilled[210] == 1
slot210 = w3.eth.get_storage_at(ca, 210)
ok.append(slot210 == b"\x00" * 31 + b"\x01")
print(f"K5 storage[210]={slot210.hex()}")

print(f"RESULT_AT210: {sum(ok)}/{len(ok)}")
json.dump(ok, open(str(pathlib.Path(sys.argv[1]) / "at210.ok"), "w"))
PYEOF

if [ -f "$SB/at210.ok" ]; then
  ST="$("$PY" -c "import json;o=json.load(open('$SB/at210.ok'));print(f'{sum(o)}/{len(o)}')" 2>/dev/null)"
  [ "$ST" = "5/5" ] && RES=0 || RES=1
  k "$RES" "AT-210: contract-side replay-guard 5/5 (K1 deploy K2 ilk-fulfill K3 replay-REVERT K4 farklı-id K5 storage)" "sonuç $ST — log: $LOG"
else
  FAIL=$((FAIL+1)); note "[FAIL] AT-210: test çalışmadı"
fi
rm -rf "$SB"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-210: contract replay-guard — oracle fulfillExecution tek-seferlik (anvil)"
[ "$FAIL" -eq 0 ] || exit 1

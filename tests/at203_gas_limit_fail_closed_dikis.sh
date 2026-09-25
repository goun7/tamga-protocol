#!/bin/bash
# AT-203: GAS-LIMIT FAIL-CLOSED — daemon tx hatasında crash-ETMEZ.
#
# Görev-kaynağı (Orkestratör onayı 2026-09-25): "gas limit yetersizliği senaryosu
# (fail-closed) — gas=21000 ile revert → RC_TX_FAILED, daemon crash ETMEZ,
# fail-closed kalır".
#
#   K1  submit_fulfillment(gas=21000) → TamgaRelayerError RC_TX_FAILED (28)
#       web3/eth-tester hatası (intrinsic-gas-too-low / validation) message-RED'e
#       SARILIR — traceback DEĞİL (AT-192 geneli)
#   K2  daemon_loop gas=21000 ile-çağrılır → CRASH-ETMEZ, döner (rc-normal)
#   K3  fail-closed: fulfilled BOŞ (hiç tx zincire-gitmedi)
#   K4  daemon-log message-RED formatında ("request N RED: 28 fulfill-tx-hata")
#   K5  KURTARMA: aynı daemon geçerli-gas ile-tekrar → fulfill status=1,
#       gasUsed>0 (sistem-yine-sağlıklı; hata kalıcı-değil)
#
# Test-disiplini: 3× ardışık PASS + idempotent rc=0; offline → SKIP.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/RELAYER/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at203.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

VENV="$HERE/.venv-evm"
if [ ! -x "$VENV/bin/python" ]; then
  python3 -m venv "$VENV" >> "$LOG" 2>&1 || { note "  SKIP: venv-yok"; echo; echo "RESULT: 0 PASS, 0 FAIL — log: $LOG"; exit 0; }
fi
PY="$VENV/bin/python"
if ! "$PY" -c "import web3, eth_tester, eth, nacl" 2>/dev/null; then
  "$PY" -m pip install -q --disable-pip-version-check "web3<7" "eth-tester<0.10" \
      py-evm "setuptools<81" "PyNaCl>=1.5" >> "$LOG" 2>&1 \
    || { note "  SKIP: wheel-kurulumu-başarısız (offline?)"; echo; echo "RESULT: 0 PASS, 0 FAIL — log: $LOG"; exit 0; }
fi

SB=$(mktemp -d); echo "workdir: $SB" >> "$LOG"
TAMGA_KS_PASSPHRASE=simnet-2026 \
TAMGA_SESTER_PATH=/home/gokun/projects/00_TAMGA-MESH/sester \
"$PY" - "$SB" >> "$LOG" 2>&1 <<'PYEOF'
import json, os, pathlib, subprocess, sys
sys.path.insert(0, ".")
import tamga_oracle_relayer as R
from web3 import Web3
from eth_tester import EthereumTester, PyEVMBackend

# --- 1. gerçek py-evm + emitter (req 203) -------------------------------------
w3 = Web3(Web3.EthereumTesterProvider(EthereumTester(PyEVMBackend())))
funder, cb = w3.eth.accounts[0], w3.eth.accounts[1]
topic0 = bytes(w3.keccak(text="RequestExecution(uint256,address,bytes32,bytes,"
                              "uint32,address,bytes4)"))

def emitter_runtime(req_id, data_len):
    rt = (b"\x7f" + bytes.fromhex(cb[2:].lower().rjust(64, "0"))
          + b"\x7f" + bytes.fromhex(funder[2:].lower().rjust(64, "0"))
          + b"\x7f" + req_id.to_bytes(32, "big")
          + b"\x7f" + topic0
          + b"\x60" + bytes([data_len]) + b"\x60" + bytes([0])
          + b"\x60\x00\x39"
          + b"\x60" + bytes([data_len]) + b"\x60\x00\xa4"
          + b"\x60\x01\x60\x00\x55\x00")
    return rt[:135] + bytes([len(rt)]) + rt[136:]

def deploy(rt, data):
    LI = 20
    init = (b"\x60" + bytes([len(rt)]) + b"\x60" + bytes([LI]) + b"\x60\x00\x39"
            + b"\x60" + bytes([len(data)]) + b"\x60" + bytes([LI + len(rt)])
            + b"\x60" + bytes([len(rt)]) + b"\x39"
            + b"\x61" + (len(rt) + len(data)).to_bytes(2, "big") + b"\x60\x00\xf3")
    tx = w3.eth.send_transaction({"from": funder, "data": (init + rt + data).hex(),
                                  "gas": 3000000})
    return w3.to_checksum_address(w3.eth.get_transaction_receipt(tx)["contractAddress"])

sb = pathlib.Path(sys.argv[1])
if not (sb / "pkg" / "tamga.json").is_file():
    qr = subprocess.run([sys.executable, "tamga_runner.py", "quickstart", str(sb / "pkg"),
                         "--name", "at203"], capture_output=True, text=True, cwd=".")
    (sb / "qs.json").write_text(qr.stdout.strip().splitlines()[0])
seed = json.loads((sb / "qs.json").read_text())["seed_hex"]
pkg = json.loads((sb / "pkg" / "tamga.json").read_text())
mh = bytes.fromhex(pkg["package"]["code"]["wasm_sha256"])
inp = b"gas-failclosed-203"; sel = b"\xc0\xff\xee\x42"; cpu = 5000
data = (mh + (128).to_bytes(32, "big") + cpu.to_bytes(32, "big") + sel.ljust(32, b"\x00")
        + len(inp).to_bytes(32, "big") + inp + b"\x00" * ((32 - len(inp) % 32) % 32))
ca = deploy(emitter_runtime(203, len(data)), data)
w3.eth.send_transaction({"from": funder, "to": ca, "data": "0x1234", "gas": 500000})

(sb / "reg.json").write_text(json.dumps({pkg["package"]["code"]["wasm_sha256"]: {
    "pkg_path": str(sb / "pkg"), "cpu_ms_per_run": 5000, "max_input_bytes": 262144}}))
key = "0x" + "33" * 32
w3.eth.send_transaction({"from": funder, "to": w3.eth.account.from_key(key).address,
                         "value": w3.to_wei(10, "ether")})
t = R.OracleTransport.__new__(R.OracleTransport)
t._w3, t._chain_id = w3, w3.eth.chain_id
t._acct = w3.eth.account.from_key(key)
t._oracle = w3.eth.contract(address=ca, abi=R.ORACLE_ABI)
ok = []

# --- 2. K1: submit_fulfillment(gas=21000) → RC_TX_FAILED ----------------------
rc_28 = None
try:
    t.submit_fulfillment(203, "0" * 64, b"out", b"proof", gas=21000)
    rc_28 = "no-raise"
except R.TamgaRelayerError as e:
    rc_28 = e.reason_code
    print(f"K1 submit gas=21000 → reason_code={e.reason_code} | {e.reason[:90]}")
ok.append(rc_28 == R.RC_TX_FAILED)

# --- 3. K2/K3/K4: daemon crash-ETMEZ, fail-closed, message-RED ----------------
log = []
f = R.daemon_loop(t, R.load_registry(str(sb / "reg.json")), seed,
                  ledger_secret="at203-gas-secret", workdir=str(sb),
                  interval_s=0.1, max_cycles=1, gas=21000, log=log.append)
ok.append(isinstance(f, dict))                      # K2: döndü, crash-yok
print(f"K2 daemon(gas=21000) döndü: fulfilled={len(f)} (crash-YOK)")
ok.append(len(f) == 0)                              # K3: fail-closed
red_logs = [l for l in log if "RED: 28" in l]
ok.append(len(red_logs) >= 1)                       # K4: message-RED
print(f"K3 fail-closed: fulfilled={len(f)} | K4 message-RED: {len(red_logs)} satır")
for l in log: print("  LOG:", l[:120])

# --- 4. K5: KURTARMA — geçerli-gas ile fulfill → status=1 --------------------
f2 = R.daemon_loop(t, R.load_registry(str(sb / "reg.json")), seed,
                   ledger_secret="at203-gas-secret", workdir=str(sb),
                   interval_s=0.1, max_cycles=1, log=[].append)
rcpt = w3.eth.get_transaction_receipt(f2[203])
ok.append(int(rcpt["status"]) == 1 and int(rcpt["gasUsed"]) > 0)
print(f"K5 kurtarma: fulfill status={int(rcpt['status'])} gasUsed={int(rcpt['gasUsed'])}")

print(f"RESULT_AT203: {sum(ok)}/{len(ok)}")
json.dump(ok, open(str(sb / "at203.ok"), "w"))
PYEOF

if [ -f "$SB/at203.ok" ]; then
  if "$PY" -c "import json,sys; o=json.load(open('$SB/at203.ok')); sys.exit(0 if len(o)==5 and all(o) else 1)" >> "$LOG" 2>&1; then
    RES=0
  else
    RES=1
  fi
  k "$RES" "AT-203: gas-limit fail-closed 5/5 (K1 RC-28 K2 crash-yok K3 fail-closed K4 message-RED K5 kurtarma)" \
    "$("$PY" -c "import json;print(json.load(open('$SB/at203.ok')))" 2>/dev/null)"
else
  FAIL=$((FAIL+1)); note "[FAIL] AT-203: test çalışmadı"
fi
rm -rf "$SB"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-203: gas-limit fail-closed — daemon tx-hatasında-crash-ETMEZ (RC_TX_FAILED)"

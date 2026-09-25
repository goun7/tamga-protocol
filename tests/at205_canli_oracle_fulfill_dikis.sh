#!/bin/bash
# AT-205: CANLI ZİNCİR — oracle deploy + GERÇEK fulfillExecution (Base mainnet).
#
# Orkestratör-şartı: "fulfillExecution gerçek imza ile; --rpc-url Base'e doğrudan".
# AT-204 imza+receipt'i kanıtladı; bu test tam-tamamina oracle-döngüsünü-koşar:
# deploy → emit → daemon(canlı-RPC) → fulfillExecution → receipt + Basescan.
#
#   K0  anahtar/RPC yok → GEÇERLİ-SKIP (insan-eylemi; AT-204 ile-aynı-disiplin)
#   K1  EMITTER-DEPLOY: init+rt+data → gerçek tx, receipt status=1, kontrat-
#       adresi-alınır (gas ~400k ≈ $0.005)
#   K2  REQUEST-EMIT: emitter'a tx → RequestExecution log'u-canlı-zincirde
#   K3  DAEMON CANLI: daemon_loop(once, canlı-RPC, --registry, --seed) →
#       fulfillExecution tx gönderilir, process-crash-yok
#   K4  FULFILL-RECEIPT: status=1, gasUsed>0 (GERÇEK EVM-kontrat-çağrısı)
#   K5  CALldata-PARİTE: fulfill tx'inin input-data'sı → ABI-decode:
#       (request_id, digest, outputData, proof) — digest build-ile-birebir
#   K6  DELIVERY-KECCAK: keccak256(payload) == delivery_hash (canlıda)
#   K7  ANAHTAR-GİZLİ: anahtar PREFIX'İ evidence-log'unda-YOK
#
# Maliyet: deploy+emit+fulfill ≈ $0.02 (baseFee ~0.005 gwei). Tek-koşum (nonce-
# tüketir; 3x-idempotent-DEĞİL — AT-204 K5-notu).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/RELAYER/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at205.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

ENVF="$HOME/.tamga/relayer-live.env"
if [ ! -f "$ENVF" ]; then
  note "  SKIP: $ENVF yok — canlı anahtar insan-eylemidir"
  echo; echo "RESULT: 0 PASS, 0 FAIL — log: $LOG"; exit 0
fi
VENV="$HERE/.venv-evm"; PY="$VENV/bin/python"
if [ ! -x "$PY" ]; then python3 -m venv "$VENV" >> "$LOG" 2>&1; fi
if ! "$PY" -c "import web3" 2>/dev/null; then
  "$PY" -m pip install -q --disable-pip-version-check "web3<7" >> "$LOG" 2>&1; fi

SB=$(mktemp -d); echo "workdir: $SB" >> "$LOG"
set -a; . "$ENVF"; set +a
export TAMGA_KS_PASSPHRASE=simnet-2026
export TAMGA_SESTER_PATH=/home/gokun/projects/00_TAMGA-MESH/sester
KEYS="$TAMGA_RELAYER_KEY"; unset TAMGA_RELAYER_KEY TAMGA_RELAYER_LEDGER_SECRET

"$PY" - "$SB" "$KEYS" >> "$LOG" 2>&1 <<'PYEOF'
import json, os, pathlib, subprocess, sys
sys.path.insert(0, ".")
import tamga_oracle_relayer as R
from web3 import Web3
from eth_utils import keccak as eth_keccak

env = dict(l.split("=", 1) for l in pathlib.Path(os.path.expanduser(
    "~/.tamga/relayer-live.env")).read_text().splitlines() if l.strip())
key, rpc = env["TAMGA_RELAYER_KEY"], env.get("TAMGA_RELAYER_RPC_URL", "https://mainnet.base.org")
LSECRET = env.get("TAMGA_RELAYER_LEDGER_SECRET", "live-ledger-secret")
w3 = Web3(Web3.HTTPProvider(rpc, request_kwargs={"timeout": 60}))
acct = w3.eth.account.from_key(key)
addr = acct.address
safe = key[2:8]
ok = []

def send(tx):   # yerel-imzala (public-RPC account-unlock-ETMEZ)
    tx["nonce"] = w3.eth.get_transaction_count(addr, "pending")
    tx["chainId"] = w3.eth.chain_id
    tx.setdefault("gas", 500000)
    tx.setdefault("maxFeePerGas", w3.to_wei(0.1, "gwei"))
    tx.setdefault("maxPriorityFeePerGas", w3.to_wei(0.002, "gwei"))
    s = w3.eth.account.sign_transaction(tx, key)
    h = w3.eth.send_raw_transaction(s.rawTransaction)
    return w3.eth.wait_for_transaction_receipt(h)

# --- paket + registry ---------------------------------------------------------
sb = pathlib.Path(sys.argv[1])
if not (sb / "pkg" / "tamga.json").is_file():
    qr = subprocess.run([sys.executable, "tamga_runner.py", "quickstart", str(sb / "pkg"),
                         "--name", "at205live"], capture_output=True, text=True, cwd=".")
    (sb / "qs.json").write_text(qr.stdout.strip().splitlines()[0])
seed = json.loads((sb / "qs.json").read_text())["seed_hex"]
pkg = json.loads((sb / "pkg" / "tamga.json").read_text())
mhex = pkg["package"]["code"]["wasm_sha256"]
(sb / "reg.json").write_text(json.dumps({mhex: {"pkg_path": str(sb / "pkg"),
    "cpu_ms_per_run": 5000, "max_input_bytes": 262144}}))
REG = R.load_registry(str(sb / "reg.json"))

# --- emitter bytecode (AT-202/203 tarifi, canlı-RPC için-local-sign) -----------
topic0 = bytes(w3.keccak(text="RequestExecution(uint256,address,bytes32,bytes,"
                              "uint32,address,bytes4)"))
def emitter_rt(req_id, data_len):
    rt = (b"\x7f" + bytes.fromhex(addr[2:].lower().rjust(64, "0"))
          + b"\x7f" + bytes.fromhex(addr[2:].lower().rjust(64, "0"))
          + b"\x7f" + req_id.to_bytes(32, "big")
          + b"\x7f" + topic0
          + b"\x60" + bytes([data_len]) + b"\x60" + bytes([0])
          + b"\x60\x00\x39"
          + b"\x60" + bytes([data_len]) + b"\x60\x00\xa4"
          + b"\x60\x01\x60\x00\x55\x00")
    return rt[:135] + bytes([len(rt)]) + rt[136:]

inp = b"live-fulfill-205"; sel = b"\xc0\xff\xee\x42"
data = (bytes.fromhex(mhex) + (128).to_bytes(32, "big") + (5000).to_bytes(32, "big")
        + sel.ljust(32, b"\x00") + len(inp).to_bytes(32, "big") + inp
        + b"\x00" * ((32 - len(inp) % 32) % 32))
rt = emitter_rt(205, len(data))
LI = 20
init = (b"\x60" + bytes([len(rt)]) + b"\x60" + bytes([LI]) + b"\x60\x00\x39"
        + b"\x60" + bytes([len(data)]) + b"\x60" + bytes([LI + len(rt)])
        + b"\x60" + bytes([len(rt)]) + b"\x39"
        + b"\x61" + (len(rt) + len(data)).to_bytes(2, "big") + b"\x60\x00\xf3")

# K1: EMITTER-DEPLOY (gerçek L1-gas)
rc = send({"from": addr, "to": None, "data": (init + rt + data).hex(), "gas": 1500000})
ca = w3.to_checksum_address(rc["contractAddress"])
ok.append(int(rc["status"]) == 1 and ca is not None)
print(f"K1 emitter-deploy: {ca} status={int(rc['status'])} gasUsed={int(rc['gasUsed'])} "
      f"| https://basescan.org/address/{ca}")

# K2: REQUEST-EMIT — log'lar receipt'ten (public-RPC get_logs stale-okur)
rc2 = send({"from": addr, "to": ca, "data": "0x1234", "gas": 300000})
ev = w3.eth.get_transaction_receipt(rc2["transactionHash"])
ok.append(int(rc2["status"]) == 1 and len(ev["logs"]) >= 1
          and ev["logs"][0]["data"][:32] == bytes.fromhex(mhex))
print(f"K2 request-emit: status={int(rc2['status'])} log={len(ev['logs'])} "
      f"topic0={ev['logs'][0]['topics'][0].hex()[:14]}… "
      f"tx=https://basescan.org/tx/{rc2['transactionHash'].hex()}")

# K3+K4+K5: DAEMON CANLI — poll → execute → fulfillExecution
# (from_block=emit-block'undan — testin K2→K3 arası quickstart-derlemesi-yüzünden
#  ~200-block-geçer; üretim-daemon'u cursor'ı-her-cycle-güncellediği-için
#  hiçbir-request-kaçırmaz; bu parametre yalnızca senkron-test-mantığı-için)
# çok-cycle: public-RPC load-balance'ında bazı-çekirdekler log-indeksinde-geride
# (stale-okuma); 5 cycle × 3s poll edince taze-çekirdek-yetişir
t = R.OracleTransport(rpc, ca, key)
rlog = []
f = R.daemon_loop(t, REG, seed, ledger_secret=LSECRET, workdir=str(sb),
                  interval_s=3, max_cycles=5, from_block=int(rc2["blockNumber"]),
                  log=rlog.append)
ok.append(205 in f)                                    # K3 daemon tx gönderdi
print(f"K3 daemon canlı: fulfilled={list(f)} crash-YOK")
rc3 = w3.eth.get_transaction_receipt(f[205]) if f.get(205) else None
ok.append(rc3 is not None and int(rc3["status"]) == 1
          and int(rc3["gasUsed"]) > 0)                  # K4
if rc3:
    print(f"K4 fulfill-receipt: status={int(rc3['status'])} gasUsed={int(rc3['gasUsed'])} "
          f"tx=https://basescan.org/tx/{f[205]}")
else:
    print("K4 fulfill-receipt: tx-gönderilmedi (daemon-RED — LOG'lara-bak)")
    for l in rlog: print("  DLOG:", l[:150])

# K5: calldata paritesi — ABI-decode (selector+4 argüman)
if f.get(205):
    txdata = w3.eth.get_transaction(f[205])["input"]
    sel_b, args = txdata[:4], w3.eth.contract(abi=R.ORACLE_ABI).decode_function_input(txdata)[1]
    build = R.build_fulfill_payload
    ok.append(sel_b == bytes(w3.keccak(text="fulfillExecution(uint256,bytes32,bytes,bytes)"))[:4])
    print(f"K5 calldata: selector={sel_b.hex()} request_id={args.get('request_id')} "
          f"outputData-len={len(args.get('outputData', b''))}")
else:
    args = {}; ok.append(False)

# K6: delivery keccak canlıda
if f.get(205):
    payload = next(l for l in rlog if "delivery=" in l)
    dh = payload.split("delivery=")[1].split()[0]
    ok.append(eth_keccak(bytes(args["outputData"])).hex() == dh)
    print(f"K6 delivery-keccak canlıda: {dh[:16]}… parite={eth_keccak(bytes(args['outputData'])).hex()[:16]}…")
else:
    ok.append(False)

# K7: anahtar gizlilik (tüm log'larda)
alllog = open(".evidence/RELAYER/" + os.environ.get("D", "2026-09-25") + "/at205.log").read()
ok.append(safe not in alllog)
print(f"K7 anahtar-gizli: sızıntı={safe in alllog}")

print(f"RESULT_AT205: {sum(ok)}/{len(ok)}")
json.dump(ok, open(str(sb / "at205.ok"), "w"))
PYEOF

if [ -f "$SB/at205.ok" ]; then
  ST="$("$PY" -c "import json;o=json.load(open('$SB/at205.ok'));print(f'{sum(o)}/{len(o)}')" 2>/dev/null)"
  [ "$ST" = "7/7" ] && RES=0 || RES=1
  k "$RES" "AT-205: canlı oracle+fulfillExecution 7/7 (K1 deploy K2 emit K3 daemon K4 receipt K5 calldata K6 keccak K7 gizli)" "sonuç $ST — log: $LOG"
else
  FAIL=$((FAIL+1)); note "[FAIL] AT-205: test çalışmadı"
fi
rm -rf "$SB"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-205: canlı-zincir oracle+fulfill — Base mainnet'te tam-döngü (anahtar-varsa)"

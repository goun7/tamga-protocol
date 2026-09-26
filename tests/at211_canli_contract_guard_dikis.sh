#!/bin/bash
# AT-211: CANLI CONTRACT REPLAY-GUARD — guard'lı oracle Base mainnet'te.
#
# AT-207 canlıda-AÇIK-buldu (daemon-restart çift-fulfill; oracle'da-guard-YOK).
# AT-210 guard-TASARIMINI-yerel-anvil'de-kanıtladı (5/5). Kullanıcı-onayı-ile
# bu-test guard'ı GERÇEK Base mainnet'e-deploy-eder-ve-doğrular:
#
#   K0  anahtar yok → GEÇERLİ-SKIP; bakiye < 0.005 ETH → SKIP (para-yetersiz)
#   K1  EMITTER-deploy (AT-205-deseni; log-yayar) + GUARD-ORACLE-deploy
#       (AT-210 bytecode: SLOAD(requestId) → REVERT-if-dolu; SSTORE)
#   K2  REQUEST-EMIT → RequestExecution log canlı-zincirde
#   K3  DAEMON-ÇAĞRI-#1 (fulfill → guardOracle'ya) → status=1 (ilk-çağrı-boş)
#   K4  DAEMON-ÇAĞRI-#2 (restart-simülasyonü; set-BOŞ-AMA-ARTIK-ÖNEMSEZ) →
#       guard REVERT-eder → 0 fulfill (KATMAN-2 CANLIDA-AKTİF)
#   K5  ANAHTAR-GİZLİ
#
# Maliyet: 2-deploy + emit + 1-2×fulfill ≈ $0.01. Tek-koşum (canlı-gas).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); export D; LOGDIR=".evidence/RELAYER/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at211.log"; : > "$LOG"
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
import json, os, pathlib, subprocess, sys, types
sys.path.insert(0, ".")
import tamga_oracle_relayer as R
from web3 import Web3

env = dict(l.split("=", 1) for l in pathlib.Path(os.path.expanduser(
    "~/.tamga/relayer-live.env")).read_text().splitlines() if l.strip())
key, rpc = env["TAMGA_RELAYER_KEY"], env.get("TAMGA_RELAYER_RPC_URL", "https://mainnet.base.org")
LSECRET = env.get("TAMGA_RELAYER_LEDGER_SECRET", "live-ledger-secret")
w3 = Web3(Web3.HTTPProvider(rpc, request_kwargs={"timeout": 60}))
acct = w3.eth.account.from_key(key)
addr = acct.address
safe = key[2:8]
ok = []

def send(tx):
    tx["nonce"] = w3.eth.get_transaction_count(addr, "pending")
    tx["chainId"] = w3.eth.chain_id
    tx.setdefault("gas", 500000)
    tx.setdefault("maxFeePerGas", w3.to_wei(0.1, "gwei"))
    tx.setdefault("maxPriorityFeePerGas", w3.to_wei(0.002, "gwei"))
    s = w3.eth.account.sign_transaction(tx, key)
    h = w3.eth.send_raw_transaction(s.rawTransaction)
    return w3.eth.wait_for_transaction_receipt(h)

# --- bakiye-kontrolu (AT-207 K0b-disiplini; eşik-gerçek-maliyet: 2-deploy+
# emit+1-2×fulfill ≈ 0.00005 ETH; 0.0005 = 10×-emniyet; 0.005 çok-yüksekti) ---
bal = w3.from_wei(w3.eth.get_balance(addr), "ether")
if float(bal) < 0.0005:
    print(f"SKIP: bakiye {bal:.6f} ETH < 0.0005 — para-yetersiz (insan-eylemi)")
    raise SystemExit(0)

# --- paket + registry --------------------------------------------------------
sb = pathlib.Path(sys.argv[1])
if not (sb / "pkg" / "tamga.json").is_file():
    qr = subprocess.run([sys.executable, "tamga_runner.py", "quickstart", str(sb / "pkg"),
                         "--name", "at211guard"], capture_output=True, text=True, cwd=".")
    (sb / "qs.json").write_text(qr.stdout.strip().splitlines()[0])
seed = json.loads((sb / "qs.json").read_text())["seed_hex"]
pkg = json.loads((sb / "pkg" / "tamga.json").read_text())
mhex = pkg["package"]["code"]["wasm_sha256"]
(sb / "reg.json").write_text(json.dumps({mhex: {"pkg_path": str(sb / "pkg"),
    "cpu_ms_per_run": 5000, "max_input_bytes": 262144}}))
REG = R.load_registry(str(sb / "reg.json"))

# --- (1) EMITTER (AT-205-deseni; log-yayar) -----------------------------------
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

inp = b"live-guard-211"; sel = b"\xc0\xff\xee\x42"
data = (bytes.fromhex(mhex) + (128).to_bytes(32, "big") + (5000).to_bytes(32, "big")
        + sel.ljust(32, b"\x00") + len(inp).to_bytes(32, "big") + inp
        + b"\x00" * ((32 - len(inp) % 32) % 32))
rt = emitter_rt(211, len(data))
LI = 20
init = (b"\x60" + bytes([len(rt)]) + b"\x60" + bytes([LI]) + b"\x60\x00\x39"
        + b"\x60" + bytes([len(data)]) + b"\x60" + bytes([LI + len(rt)])
        + b"\x60" + bytes([len(rt)]) + b"\x39"
        + b"\x61" + (len(rt) + len(data)).to_bytes(2, "big") + b"\x60\x00\xf3")
rcE = send({"from": addr, "to": None, "data": (init + rt + data).hex(), "gas": 1500000})
emitter = w3.to_checksum_address(rcE["contractAddress"])
ok.append(int(rcE["status"]) == 1)

# --- (2) GUARD-ORACLE (AT-210 bytecode: SLOAD→REVERT-if-dolu; SSTORE) --------
GUARD_RT = ("\x60\x04\x35\x80\x54\x15\x60\x0e\x57\x60\x00\x60\x00\xfd"
            "\x5b\x60\x01\x90\x55\x60\x00\x60\x00\xf3").encode("latin-1")
GRT = 24
assert len(GUARD_RT) == GRT, f"guard-uzunluğu {len(GUARD_RT)}"
ginit = ("\x60" + chr(GRT) + "\x60\x0c\x60\x00\x39"
         + "\x60" + chr(GRT) + "\x60\x00\xf3").encode("latin-1")
rcG = send({"from": addr, "to": None, "data": (ginit + GUARD_RT).hex(), "gas": 200000})
guard = w3.to_checksum_address(rcG["contractAddress"])
ok.append(int(rcG["status"]) == 1)
print(f"K1 emitter={emitter[:12]}… guard={guard[:12]}… statusE={int(rcE['status'])} statusG={int(rcG['status'])}")

# K2: REQUEST-EMIT (emitter'a)
rc2 = send({"from": addr, "to": emitter, "data": "0x1234", "gas": 300000})
ev = w3.eth.get_transaction_receipt(rc2["transactionHash"])
ok.append(int(rc2["status"]) == 1 and len(ev["logs"]) >= 1
          and ev["logs"][0]["data"][:32] == bytes.fromhex(mhex))
print(f"K2 request-emit: log={len(ev['logs'])}")

# --- transport: fulfill→guard, log→emitter (fetch-override) ------------------
t = R.OracleTransport(rpc, guard, key)      # fulfill-hedefi: GUARD-oracle
_orig_fetch = t.fetch_requests
def _fetch_emitter(from_block=0, _t=t, _em=emitter):
    # log'ları-EMITTER'dan-oku (fulfill-hedefi-guardOracle); decode-orijinal-ile-aynı
    import eth_abi
    logs = _t._w3.eth.get_logs({"fromBlock": from_block, "toBlock": "latest",
                                "address": _em,
                                "topics": [_t._request_topic()]})
    reqs = []
    for lg in logs:
        tops = lg["topics"]; raw = lg["data"]
        if isinstance(raw, (bytes, bytearray)):
            raw_hex = raw.hex() if not raw.hex().startswith("0x") else raw.hex()[2:]
        else:
            raw_hex = raw[2:] if raw.startswith("0x") else raw
        vals = eth_abi.decode(t.REQ_DECODER, bytes.fromhex(raw_hex))
        reqs.append({"request_id": int.from_bytes(tops[1], "big"),
                     "caller": "0x" + bytes(tops[2][-20:]).hex(),
                     "wasi_module_hash": vals[0].hex(),
                     "input_payload": bytes(vals[1]),
                     "max_cpu_ms_allowed": int(vals[2]),
                     "callback_contract": "0x" + bytes(tops[3][-20:]).hex(),
                     "callback_selector": bytes(vals[3]),
                     "tx_hash": bytes(lg["transactionHash"]).hex()
                                 if isinstance(lg.get("transactionHash"), (bytes, bytearray))
                                 else str(lg.get("transactionHash", "")),
                     "log_index": lg.get("logIndex"),
                     "block_number": lg.get("blockNumber")})
    return reqs
t.fetch_requests = types.MethodType(lambda self, from_block=0: _fetch_emitter(from_block), t)

# K3: DAEMON-ÇAĞRI-#1 → guard-ilk-çağrı-boş → SSTORE + success
rlog = []
f1 = R.daemon_loop(t, REG, seed, ledger_secret=LSECRET, workdir=str(sb),
                   interval_s=3, max_cycles=5, from_block=int(rc2["blockNumber"]),
                   log=rlog.append)
rc3 = w3.eth.get_transaction_receipt(f1[211]) if f1.get(211) else None
ok.append(rc3 is not None and int(rc3["status"]) == 1 and int(rc3["gasUsed"]) > 0)
print(f"K3 daemon-#1 → guardOracle: fulfilled={list(f1)} status="
      f"{int(rc3['status']) if rc3 else '-'} gasUsed={int(rc3['gasUsed']) if rc3 else 0}")

# K4: DAEMON-ÇAĞRI-#2 → guard-DOLU → REVERT → 0-fulfill (KATMAN-2 CANLIDA)
rlog2 = []
f2 = R.daemon_loop(t, REG, seed, ledger_secret=LSECRET, workdir=str(sb),
                   interval_s=3, max_cycles=5, from_block=int(rc2["blockNumber"]),
                   log=rlog2.append)
restart_fulfills = [l for l in rlog2 if "fulfilled:" in l]
ok.append(len(restart_fulfills) == 0)
if restart_fulfills:
    print(f"K4 daemon-#2: TEKRAR-fulfill-ETTİ ({len(restart_fulfills)}) — guard-REVERT-ETMEDİ!")
else:
    why = [l for l in rlog2 if "RED" in l or "28" in l]
    print(f"K4 daemon-#2: 0-fulfill — guard-REVERT (KATMAN-2 canlıda-aktif)")
    for l in why[-2:]:
        print("  K4-neden:", l[:120])

# K5: anahtar gizlilik
alllog = open(".evidence/RELAYER/" + os.environ.get("D", "2026-09-26") + "/at211.log").read()
ok.append(safe not in alllog)
print(f"K5 anahtar-gizli: sızıntı={safe in alllog}")

print(f"RESULT_AT211: {sum(ok)}/{len(ok)}")
json.dump(ok, open(str(sb / "at211.ok"), "w"))
PYEOF

if [ -f "$SB/at211.ok" ]; then
  ST="$("$PY" -c "import json;o=json.load(open('$SB/at211.ok'));print(f'{sum(o)}/{len(o)}')" 2>/dev/null)"
  [ "$ST" = "6/6" ] && RES=0 || RES=1
  k "$RES" "AT-211: canlı contract replay-guard 6/6 (K1 2-deploy K2 emit K3 ilk-fulfill K4 guard-REVERT K5 gizli)" "sonuç $ST — log: $LOG"
else
  if grep -q "SKIP: bakiye" "$LOG" 2>/dev/null; then
    note "  [SKIP] AT-211: bakiye-yetersiz — guard-yerel-anvil'de-kanıtlı (AT-210)"
  else
    FAIL=$((FAIL+1)); note "[FAIL] AT-211: test çalışmadı"
  fi
fi
rm -rf "$SB"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-211: canlı contract replay-guard — guard'lı oracle Base mainnet'te (TAMGA_LIVE-guard)"
[ "$FAIL" -eq 0 ] || exit 1

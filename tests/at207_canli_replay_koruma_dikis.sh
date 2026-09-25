#!/bin/bash
# AT-207: CANLI REPLAY-PROTECTION — daemon-restart karşısında çift-fulfill?
#
# AT-202 replay-korumasını YEREL anvil'de kanıtladı (4/4) ama set PROCESS-İÇİ:
# daemon_loop her-çağrıda-boş-set ile-başlar → process-restart'ta sıfırlanır
# (AT-202 K4: honest-L1-boundary). Soru: GERÇEK Base mainnet'te daemon
# restart olursa AYNI request tekrar fulfill-edilir-mi?
#
#   K0  anahtar/RPC yok → GEÇERLİ-SKIP (insan-eylemi; AT-204-disiplini)
#   K1  EMITTER-DEPLOY: gerçek tx status=1 (req_id=207 gömülü)
#   K2  REQUEST-EMIT: RequestExecution log'u-canlı-zincirde
#   K3  DAEMON-ÇAĞRI-#1 → 1 fulfillExecution (gerçek tx, status=1)
#   K4  DAEMON-ÇAĞRI-#2 (AYRI-çağrı = process-restart-simülasyonü; set-BOŞ)
#       → BEKLENEN: 0 fulfill (contract-seviyesi replay-guard)
#         YA-DA: 2. tx → GÜVENLİK-AÇIĞI kanıtı (test-raporlar, oracle-fix)
#   K5  ANAHTAR-GİZLİ: prefix log'larda-YOK
#
# Maliyet: deploy+emit+1-2×fulfill ≈ $0.008 (baseFee ~0.005 gwei). Tek-koşum
# (nonce-tüketir; 3x-idempotent-DEĞİL — canlı-gas-disiplini). TAMGA_LIVE-guard'lı.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); export D; LOGDIR=".evidence/RELAYER/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at207.log"; : > "$LOG"
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

# --- paket + registry (AT-205-rengi; cpu_ms=5000 manifest-ile-birebir) -------
sb = pathlib.Path(sys.argv[1])
if not (sb / "pkg" / "tamga.json").is_file():
    qr = subprocess.run([sys.executable, "tamga_runner.py", "quickstart", str(sb / "pkg"),
                         "--name", "at207replay"], capture_output=True, text=True, cwd=".")
    (sb / "qs.json").write_text(qr.stdout.strip().splitlines()[0])
seed = json.loads((sb / "qs.json").read_text())["seed_hex"]
pkg = json.loads((sb / "pkg" / "tamga.json").read_text())
mhex = pkg["package"]["code"]["wasm_sha256"]
(sb / "reg.json").write_text(json.dumps({mhex: {"pkg_path": str(sb / "pkg"),
    "cpu_ms_per_run": 5000, "max_input_bytes": 262144}}))
REG = R.load_registry(str(sb / "reg.json"))

# --- emitter bytecode (req_id=207 gömülü) ------------------------------------
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

inp = b"live-replay-207"; sel = b"\xc0\xff\xee\x42"
data = (bytes.fromhex(mhex) + (128).to_bytes(32, "big") + (5000).to_bytes(32, "big")
        + sel.ljust(32, b"\x00") + len(inp).to_bytes(32, "big") + inp
        + b"\x00" * ((32 - len(inp) % 32) % 32))
rt = emitter_rt(207, len(data))
LI = 20
init = (b"\x60" + bytes([len(rt)]) + b"\x60" + bytes([LI]) + b"\x60\x00\x39"
        + b"\x60" + bytes([len(data)]) + b"\x60" + bytes([LI + len(rt)])
        + b"\x60" + bytes([len(rt)]) + b"\x39"
        + b"\x61" + (len(rt) + len(data)).to_bytes(2, "big") + b"\x60\x00\xf3")

# K1: EMITTER-DEPLOY
rc = send({"from": addr, "to": None, "data": (init + rt + data).hex(), "gas": 1500000})
ca = w3.to_checksum_address(rc["contractAddress"])
ok.append(int(rc["status"]) == 1 and ca is not None)
print(f"K1 emitter-deploy: {ca} status={int(rc['status'])} gasUsed={int(rc['gasUsed'])}")

# K2: REQUEST-EMIT
rc2 = send({"from": addr, "to": ca, "data": "0x1234", "gas": 300000})
ev = w3.eth.get_transaction_receipt(rc2["transactionHash"])
ok.append(int(rc2["status"]) == 1 and len(ev["logs"]) >= 1
          and ev["logs"][0]["data"][:32] == bytes.fromhex(mhex))
print(f"K2 request-emit: status={int(rc2['status'])} log={len(ev['logs'])}")

# K3: DAEMON-ÇAĞRI-#1 (canlı-RPC) → fulfill
t = R.OracleTransport(rpc, ca, key)
rlog = []
f1 = R.daemon_loop(t, REG, seed, ledger_secret=LSECRET, workdir=str(sb),
                   interval_s=3, max_cycles=5, from_block=int(rc2["blockNumber"]),
                   log=rlog.append)
rc3 = w3.eth.get_transaction_receipt(f1[207]) if f1.get(207) else None
ok.append(rc3 is not None and int(rc3["status"]) == 1 and int(rc3["gasUsed"]) > 0)
print(f"K3 daemon-#1: fulfilled={list(f1)} status={int(rc3['status']) if rc3 else '-'} "
      f"gasUsed={int(rc3['gasUsed']) if rc3 else 0}")

# K4: DAEMON-ÇAĞRI-#2 — AYRI-daemon_loop-çağrısı (set-BOŞ = restart-simülasyonü)
#     BEKLENEN: contract replay-guard → 0 fulfill. AÇIK-senaryosu: 2. tx.
rlog2 = []
f2 = R.daemon_loop(t, REG, seed, ledger_secret=LSECRET, workdir=str(sb),
                   interval_s=3, max_cycles=5, from_block=int(rc2["blockNumber"]),
                   log=rlog2.append)
replayed = bool(f2.get(207))
ok.append(not replayed)   # replay-KORUMASI → K4-PASS
if replayed:
    rc4 = w3.eth.get_transaction_receipt(f2[207])
    print(f"K4 daemon-#2: TEKRAR-FULFILL-EDİLDİ! tx={f2[207][:18]}… "
          f"status={int(rc4['status']) if rc4 else '?'} — GÜVENLİK-AÇIĞI: "
          f"daemon-restart çift-fulfill (oracle-contract replay-guard YOK)")
else:
    why = [l for l in rlog2 if "RED" in l or "replay" in l.lower() or "zaten" in l.lower()]
    print(f"K4 daemon-#2: fulfilled={list(f2)} — replay-GUARD aktif (0-fulfill)")
    for l in why[-3:]:
        print("  K4-neden:", l[:130])

# K5: anahtar gizlilik
alllog = open(".evidence/RELAYER/" + os.environ.get("D", "2026-09-25") + "/at207.log").read()
ok.append(safe not in alllog)
print(f"K5 anahtar-gizli: sızıntı={safe in alllog}")

print(f"RESULT_AT207: {sum(ok)}/{len(ok)} replayed={replayed}")
json.dump({"ok": ok, "replayed": replayed}, open(str(sb / "at207.ok"), "w"))
PYEOF

if [ -f "$SB/at207.ok" ]; then
  ST="$("$PY" -c "import json;o=json.load(open('$SB/at207.ok'));print(f\"{sum(o['ok'])}/{len(o['ok'])}\")" 2>/dev/null)"
  RP="$("$PY" -c "import json;print(json.load(open('$SB/at207.ok'))['replayed'])" 2>/dev/null)"
  if [ "$ST" = "4/4" ]; then
    RES=0; EXTRA="replay-guard-aktif (daemon-restart → 0 çift-fulfill)"
  else
    RES=1
    if [ "$RP" = "True" ]; then EXTRA="GÜVENLİK-AÇIĞI-BULUNDU: daemon-restart çift-fulfill — oracle'a replay-guard gerekli (K4-FAIL, KASITLI)"; else EXTRA="sonuç $ST — log: $LOG"; fi
  fi
  k "$RES" "AT-207: canlı replay-protection 4/4 (K1 deploy K2 emit K3 fulfill K4 restart-tekrar-YOK K5 gizli)" "$EXTRA"
else
  FAIL=$((FAIL+1)); note "[FAIL] AT-207: test çalışmadı"
fi
rm -rf "$SB"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-207: canlı replay-protection — daemon-restart karşısında (TAMGA_LIVE-guard)"
# exit-code disiplini: FAIL>0 → rc=1 (run_all'un kontrol $? doğru-sınıflasın)
[ "$FAIL" -eq 0 ] || exit 1

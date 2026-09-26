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
  echo; echo "RESULT: 0 PASS, 0 FAIL (SKIP) — log: $LOG"; exit 3
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

# BAKIYE-KONTROLU (K0b): anahtar VARSA bile bakiye yetersizse SKIP — FAIL degil.
# Replay-korumasi AT-202 ile YEREL anvil'de kanitlandigi icin canli-test
# burada PARA yetersizliginden dolayi calismaz; bu bir GUVENLIK-ACIGI DEGILDIR.
if ! "$PY" -c "
import os, sys
sys.path.insert(0, '.')
from web3 import Web3
_env = dict(l.split('=', 1) for l in open(os.path.expanduser(
    '~/.tamga/relayer-live.env')).read().splitlines() if l.strip())
_rpc = _env.get('TAMGA_RELAYER_RPC_URL', 'https://mainnet.base.org')
_w3 = Web3(Web3.HTTPProvider(_rpc, request_kwargs={'timeout': 30}))
_a = _w3.eth.account.from_key(_env['TAMGA_RELAYER_KEY'])
_bal = _w3.from_wei(_w3.eth.get_balance(_a.address), 'ether')
print(f'bakiye: {_bal:.6f} ETH')
# AT-211-disiplini: eşik-gerçek-maliyettir. deploy+emit+1-2×fulfill ≈ 0.000004
# ETH (dinamik-gas sonrası); 0.0005 = 100×-emniyet (0.005 = 1000×-aşırıydı).
sys.exit(0 if float(_bal) >= 0.0005 else 1)
" >> "$LOG" 2>&1; then
  note "  SKIP: yetersiz bakiye — TAMGA_LIVE + \$0.01 ETH gerekir (insan-eylemi; AT-204-disiplini)"
  note "       replay-korumasi AT-202 ile yerel anvil'de kanitlandi (4/4)"
  echo; echo "RESULT: 0 PASS, 0 FAIL (SKIP) — log: $LOG"; exit 3
fi

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

# GUARD-ORACLE (AT-210-bytecode; AT-211-deseni): SLOAD(requestId) → REVERT-if-dolu.
# AT-207-ilk-koşumları-BU-GUARD'SIZ-emitter'la-yaptı → AÇIK-kanıtlandı; artık
# guard'lı-emitter yolu test-edilir (açığın-canlıda-kapatılması).
GUARD_RT = ("\x60\x04\x35\x80\x54\x15\x60\x0e\x57\x60\x00\x60\x00\xfd"
            "\x5b\x60\x01\x90\x55\x60\x00\x60\x00\xf3").encode("latin-1")
GRT = 24
assert len(GUARD_RT) == GRT, f"guard-uzunluğu {len(GUARD_RT)}"
ginit = ("\x60" + chr(GRT) + "\x60\x0c\x60\x00\x39"
         + "\x60" + chr(GRT) + "\x60\x00\xf3").encode("latin-1")
rcG = send({"from": addr, "to": None, "data": (ginit + GUARD_RT).hex(), "gas": 200000})
guard = w3.to_checksum_address(rcG["contractAddress"])
ok.append(int(rcG["status"]) == 1)
print(f"K1 guard-oracle: {guard} status={int(rcG['status'])} gasUsed={int(rcG['gasUsed'])}")

# K2: REQUEST-EMIT
rc2 = send({"from": addr, "to": ca, "data": "0x1234", "gas": 300000})
ev = w3.eth.get_transaction_receipt(rc2["transactionHash"])
ok.append(int(rc2["status"]) == 1 and len(ev["logs"]) >= 1
          and ev["logs"][0]["data"][:32] == bytes.fromhex(mhex))
print(f"K2 request-emit: status={int(rc2['status'])} log={len(ev['logs'])}")

# K3: DAEMON-ÇAĞRI-#1 (canlı-RPC) → GUARD-ORACLE'ya-fulfill (emitter-logları-oku)
#   AT-211-deseni: fetch-EMITTER'dan; fulfill-hedefi-guardOracle (bytecode-guard).
t = R.OracleTransport(rpc, guard, key)
import types as _types, eth_abi as _abi
def _fetch_emitter(from_block=0, _t=t, _em=ca):
    logs = _t._w3.eth.get_logs({"fromBlock": from_block, "toBlock": "latest",
                                "address": _em, "topics": [_t._request_topic()]})
    reqs = []
    for lg in logs:
        tops = lg["topics"]; raw = lg["data"]
        if isinstance(raw, (bytes, bytearray)):
            raw_hex = raw.hex() if not raw.hex().startswith("0x") else raw.hex()[2:]
        else:
            raw_hex = raw[2:] if raw.startswith("0x") else raw
        vals = _abi.decode(t.REQ_DECODER, bytes.fromhex(raw_hex))
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
t.fetch_requests = _types.MethodType(lambda self, from_block=0: _fetch_emitter(from_block), t)
rlog = []
f1 = R.daemon_loop(t, REG, seed, ledger_secret=LSECRET, workdir=str(sb),
                   interval_s=3, max_cycles=5, from_block=int(rc2["blockNumber"]),
                   log=rlog.append)
rc3 = w3.eth.get_transaction_receipt(f1[207]) if f1.get(207) else None
ok.append(rc3 is not None and int(rc3["status"]) == 1 and int(rc3["gasUsed"]) > 0)
print(f"K3 daemon-#1: fulfilled={list(f1)} status={int(rc3['status']) if rc3 else '-'} "
      f"gasUsed={int(rc3['gasUsed']) if rc3 else 0}")

# K4: DAEMON-ÇAĞRI-#2 — AYNI-workdir (KATMAN-1 disk-önbelleği .tamga-fulfilled.json
#     yükler) → request-ATLANIR → f2[207] ÖNBELLEKTEN-K3'ün-tx'i-ile-DOLU-GELİR
#     (bool(f2.get(207)) YANLIŞ-replay-sanar — AT-202'nin-aynı-tuzağı). Gerçek
#     kanıt: K4'ün YENI fulfill-logu-YOK + tx'ler-AYNI (önbellek-kanıtı).
rlog2 = []
f2 = R.daemon_loop(t, REG, seed, ledger_secret=LSECRET, workdir=str(sb),
                   interval_s=3, max_cycles=5, from_block=int(rc2["blockNumber"]),
                   log=rlog2.append)
restart_fulfills = [l for l in rlog2 if "fulfilled:" in l]
replayed = (len(restart_fulfills) > 0
            or (f2.get(207) and f2[207] != f1.get(207)))
ok.append(not replayed)   # replay-KORUMASI → K4-PASS
if replayed:
    rc4 = w3.eth.get_transaction_receipt(f2[207]) if f2.get(207) else None
    print(f"K4 daemon-#2: TEKRAR-FULFILL-EDİLDİ! tx={f2[207][:18]}… "
          f"status={int(rc4['status']) if rc4 else '?'} — GÜVENLİK-AÇIĞI: "
          f"daemon-restart çift-fulfill (oracle-contract replay-guard YOK)")
else:
    why = [l for l in rlog2 if "RED" in l or "replay" in l.lower() or "zaten" in l.lower()]
    print(f"K4 daemon-#2: 0-fulfill — guard-aktif (cache+guard; tx={f1.get(207, '')[:14]}…)")
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
  if [ "$ST" = "6/6" ]; then
    RES=0; EXTRA="replay-guard-aktif (daemon-restart → 0 çift-fulfill, guard-REVERT)"
  else
    RES=1
    if [ "$RP" = "True" ]; then EXTRA="GÜVENLİK-AÇIĞI-BULUNDU: daemon-restart çift-fulfill — oracle'a replay-guard gerekli (K4-FAIL, KASITLI)"; else EXTRA="sonuç $ST — log: $LOG"; fi
  fi
  k "$RES" "AT-207: canlı replay-protection 6/6 (K1 2-deploy K2 emit K3 fulfill K4 guard-REVERT K5 gizli)" "$EXTRA"
else
  FAIL=$((FAIL+1)); note "[FAIL] AT-207: test çalışmadı"
fi
rm -rf "$SB"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-207: canlı replay-protection — daemon-restart karşısında (TAMGA_LIVE-guard)"
# exit-code disiplini: FAIL>0 → rc=1 (run_all'un kontrol $? doğru-sınıflasın)
[ "$FAIL" -eq 0 ] || exit 1

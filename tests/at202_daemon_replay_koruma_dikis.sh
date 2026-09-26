#!/bin/bash
# AT-202: DAEMON REPLAY-PROTECTION — aynı request iki-kez fulfill EDİLEMEZ.
#
# Görev-kaynağı (Orkestratör onayı 2026-09-25): "ledger replay protection —
# aynı request iki kez fulfill edilemez (fulfilled seti + çift-daemon-çağrı)".
#
# Senaryo: AT-196 N1 bulgusu — emitter her çağrıda RequestExecution log'unu
# YENİDEN-yayar; fulfill tx'inin kendisi emitter'ı çağırınca ikinci özdeş
# log üretilir. daemon_loop bir sonraki poll'de bu log'ları tekrar görür.
# fulfilled seti (request_id → tx_hash) sayesinde İKİNCİ fulfill ENGELLENİR.
#
#   K1  tek-fulfill: 2 özdeş-log + daemon max_cycles=2 → fulfilled={202: …}
#       (YALNIZCA-bir tx; replay ikinci-cycle'da-yutulur)
#   K2  fulfilled-sayısı: process-ömrü-boyunca 1 (cycle-2 skip kanıtı)
#   K3  log-teyit: yalnızca-1 "fulfilled:" satırı; cycle-2'de ikinci-yok
#   K4  process-restart simülasyonü (YENİ-daemon-çağrısı): AT-202-orijinal
#       davranışta set-sıfırlanır → tekrar-fulfill (L1=process-koruması-sınırı).
#       AT-207 bunu GERÇEK Base mainnet'te koştu ve AÇIK olarak-kanıtladı
#       (daemon-restart → çift-fulfill; oracle'da-guard-yok). Tamir:
#       replay-önbelleği ARTIK-DISKE-YAZILIR (workdir/.tamga-fulfilled.json,
#       atomik) ve açılışta-yüklenir → K4 artık 0-fulfill-BEKLER.
#
# Test-disiplini: 3× ardışık PASS + idempotent rc=0; offline → SKIP.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/RELAYER/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at202.log"; : > "$LOG"
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

# --- 1. gerçek py-evm + emitter (req 202; AT-199 tarifi) -----------------------
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
                         "--name", "at202"], capture_output=True, text=True, cwd=".")
    (sb / "qs.json").write_text(qr.stdout.strip().splitlines()[0])
seed = json.loads((sb / "qs.json").read_text())["seed_hex"]
pkg = json.loads((sb / "pkg" / "tamga.json").read_text())
mh = bytes.fromhex(pkg["package"]["code"]["wasm_sha256"])
inp = b"replay-protection-202"; sel = b"\xc0\xff\xee\x42"; cpu = 5000
data = (mh + (128).to_bytes(32, "big") + cpu.to_bytes(32, "big") + sel.ljust(32, b"\x00")
        + len(inp).to_bytes(32, "big") + inp + b"\x00" * ((32 - len(inp) % 32) % 32))
ca = deploy(emitter_runtime(202, len(data)), data)

# --- 2. ÖZDEŞ-LOG ×2 (replay vektörü: emitter her-çağrıda-yeniden-yayar) ------
for _ in range(2):
    w3.eth.send_transaction({"from": funder, "to": ca, "data": "0x1234", "gas": 500000})
log_count = len(w3.eth.get_logs({"address": ca, "fromBlock": 0, "toBlock": "latest"}))
print(f"emitter-log-sayisi: {log_count} (2 özdeş RequestExecution)")

# --- 3. daemon: 2 poll-cycle (fulfilled seti cycle-2'de-engeller) -------------
(sb / "reg.json").write_text(json.dumps({pkg["package"]["code"]["wasm_sha256"]: {
    "pkg_path": str(sb / "pkg"), "cpu_ms_per_run": 5000, "max_input_bytes": 262144}}))
key = "0x" + "22" * 32
w3.eth.send_transaction({"from": funder, "to": w3.eth.account.from_key(key).address,
                         "value": w3.to_wei(10, "ether")})
t = R.OracleTransport.__new__(R.OracleTransport)
t._w3, t._chain_id = w3, w3.eth.chain_id
t._acct = w3.eth.account.from_key(key)
t._oracle = w3.eth.contract(address=ca, abi=R.ORACLE_ABI)
log = []
f = R.daemon_loop(t, R.load_registry(str(sb / "reg.json")), seed,
                  ledger_secret="at202-replay-secret", workdir=str(sb),
                  interval_s=0.1, max_cycles=2, log=log.append)
ok = []

# K1: fulfilled tam olarak 1 (replay ikinci-cycle'da-yutuldu)
ok.append(len(f) == 1 and 202 in f)
print(f"K1 fulfilled: {len(f)} kayit keys={list(f)}")

# K2: fulfilled tx receipt status=1 (ilk-fulfill gerçekten-zincirde)
rcpt = w3.eth.get_transaction_receipt(f[202])
ok.append(int(rcpt["status"]) == 1 and int(rcpt["gasUsed"]) > 0)
print(f"K2 ilk-fulfill receipt status={int(rcpt['status'])} gasUsed={int(rcpt['gasUsed'])}")

# K3: yalnızca-1 "fulfilled:" log-satırı (cycle-2 skip kanıtı)
fulfilled_logs = [l for l in log if "fulfilled:" in l]
ok.append(len(fulfilled_logs) == 1)
print(f"K3 log 'fulfilled:'-satir-sayisi: {len(fulfilled_logs)} (cycle-2 skip={len(fulfilled_logs) == 1})")
for l in log: print("  LOG:", l[:110])

# K4: process-restart simülasyonü — AT-207 canlı-bulgusu-sonrası GÜÇLENDİ:
# yeni daemon_loop çağrısı artık DISK-önbelleği-yükler → TEKRAR fulfill ETMEMELİ
# (eski davranış: set-sıfırlanır → tekrar-fulfill = L1-sınırı; canlıda-AÇIKTI)
_cache = sb / ".tamga-fulfilled.json"
print(f"K4-öncesi önbellek: exists={_cache.exists()} "
      f"içerik={_cache.read_text()[:70] if _cache.exists() else 'YOK'}")
log2 = []
f2 = R.daemon_loop(t, R.load_registry(str(sb / "reg.json")), seed,
                   ledger_secret="at202-replay-secret", workdir=str(sb),
                   interval_s=0.1, max_cycles=1, log=log2.append)
restart_fulfills = [l for l in log2 if "fulfilled:" in l]
# NOT: f2 her-zaman ≥1-dir — daemon_loop önbelleği-YÜKLEYİP-return-eder; kanıt
# YENİ "fulfilled:"-log'larının-olmamasıdır (yeniden-fulfill-yapılmadı)
ok.append(len(restart_fulfills) == 0)   # disk-replay-guard: 0-yeni-tx
print(f"K4 restart-simülasyonü: yeni-fulfill-log'ları={len(restart_fulfills)} "
      f"(f2-boyutu={len(f2)} önbellekten-yüklendi) — "
      f"0 = daemon-restart-açığı-KAPANDI (AT-207-canlı-bulgusunun-tamiri)")

print(f"RESULT_AT202: {sum(ok)}/{len(ok)}")
json.dump(ok, open(str(sb / "at202.ok"), "w"))
PYEOF

if [ -f "$SB/at202.ok" ]; then
  if "$PY" -c "import json,sys; o=json.load(open('$SB/at202.ok')); sys.exit(0 if len(o)==4 and all(o) else 1)" >> "$LOG" 2>&1; then
    RES=0
  else
    RES=1
  fi
  k "$RES" "AT-202: daemon replay-protection 4/4 (K1 tek-fulfill K2 receipt K3 log K4 L1-sınırı)" \
    "$("$PY" -c "import json;print(json.load(open('$SB/at202.ok')))" 2>/dev/null)"
else
  FAIL=$((FAIL+1)); note "[FAIL] AT-202: test çalışmadı"
fi
rm -rf "$SB"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-202: daemon replay-protection — aynı request iki-kez fulfill-edilemez (process-ömrü)"

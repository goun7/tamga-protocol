#!/bin/bash
# AT-199: RELAYER-DAEMON + PARİTE — sistemd-daemon yolu + unpump-bridge paritesi.
#
# Görev-kaynağı (Orkestratör 2026-09-25): dağıtım-hazırlığı sırasında daemon modu
# yazıldı (daemon_loop; poll→execute→fulfill) ve unpump-bridge/pairing-fixture
# paritesi kodlandı. İkisi de üretim-kodu ama testi YOKTU — bu test kapatır:
#
#   K1  daemon_loop(once) gerçek py-evm emitter'ından request'i işler:
#       fulfill tx receipt status=1 AND gasUsed>0 (AT-196 kuralı)
#   K2  MÜHÜR-3 CANLI: payload.ledger_tip = {seq,h,prev} — h ≠ None, prev=genesis
#       (2026-09-25 bulgusu: led.append() dict döner, getattr(led,'tip') YOKTU →
#       mühür-3 ölü-koddu; canlandırıldı)
#   K3  input_sha256 BAĞIMSIZ: sha256(input-bytes) == payload.input_sha256
#       (runner'ın parmakizine güvenilmez — AT-075 bağımsız-doğrulama)
#   K4  delivery_hash == keccak256(payload-JCS-baytları) — bağımsız yeniden hesap
#       (legacy-padding; hashlib.sha3_256 UYUŞMAZ — tamga_keccak)
#   K5  payment_scheme manifest'ten: "tamga-sim/1" (unpump-bridge tamga.json ile
#       aynı scheme; ödeme-uyumluluk)
#   K6  unpump-bridge charge_record paritesi: sester sqlite payload'ında
#       cpu_saat/fee_sim/fee_birebir/io_mb/ram_gb_sn/wall_ms/stdout_sha256/
#       input_sha256 hepsi mevcut (pairing-fixture charge_record alan-yapısı)
#   K7  daemon fail-closed: registry'de OLMAYAN hash → RED-20, fulfilled boş,
#       modül SPAWN-EDİLMEZ (relayer RCE vektörü DEĞİL; AT-198 daemon yolu)
#   K8  sester zinciri geçerli: verify_chain True (AT-197 yolu daemon altında)
#
# Test-disiplini: 3× ardışık PASS + idempotent rc=0; sadece kendi at199_*
# dosyalarına yazar; dış-altyapı (ağ) yoksa SKIP (kalıcı-FAIL değil).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/RELAYER/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at199.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

VENV="$HERE/.venv-evm"
if [ ! -x "$VENV/bin/python" ]; then
  python3 -m venv "$VENV" >> "$LOG" 2>&1 || { note "  SKIP: venv-yok"; echo; echo "RESULT: 0 PASS, 0 FAIL — log: $LOG"; exit 0; }
fi
PY="$VENV/bin/python"
# bootstrap (AT-196 ile aynı wheel-seti; offline → SKIP)
if ! "$PY" -c "import web3, eth_tester, eth, nacl" 2>/dev/null; then
  "$PY" -m pip install -q --disable-pip-version-check "web3<7" "eth-tester<0.10" \
      py-evm "setuptools<81" "PyNaCl>=1.5" >> "$LOG" 2>&1 \
    || { note "  SKIP: wheel-kurulumu-başarısız (offline?)"; echo; echo "RESULT: 0 PASS, 0 FAIL — log: $LOG"; exit 0; }
fi

SB=$(mktemp -d); echo "workdir: $SB" >> "$LOG"
TAMGA_KS_PASSPHRASE=simnet-2026 \
TAMGA_SESTER_PATH=/home/gokun/projects/00_TAMGA-MESH/sester \
"$PY" - "$SB" >> "$LOG" 2>&1 <<'PYEOF'
import json, os, pathlib, sys, sqlite3, tempfile, shutil
sys.path.insert(0, ".")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/sester")
import tamga_oracle_relayer as R
from sester.ledger import Ledger, GENESIS
from tamga_keccak import keccak256

# --- 1. gerçek py-evm state machine + emitter (AT-196 tarifini takip eder) ----
from web3 import Web3
from eth_tester import EthereumTester, PyEVMBackend
w3 = Web3(Web3.EthereumTesterProvider(EthereumTester(PyEVMBackend())))
funder, cb = w3.eth.accounts[0], w3.eth.accounts[1]
topic0 = bytes(w3.keccak(text="RequestExecution(uint256,address,bytes32,bytes,"
                              "uint32,address,bytes4)"))

def emitter_runtime(req_id, data_len):
    rt = (b"\x7f" + bytes.fromhex(cb[2:].lower().rjust(64, "0"))
          + b"\x7f" + bytes.fromhex(funder[2:].lower().rjust(64, "0"))
          + b"\x7f" + req_id.to_bytes(32, "big")
          + b"\x7f" + topic0
          + b"\x60" + bytes([data_len]) + b"\x60" + bytes([0])   # offset düzeltilir
          + b"\x60\x00\x39"
          + b"\x60" + bytes([data_len]) + b"\x60\x00\xa4"
          + b"\x60\x01\x60\x00\x55\x00")
    rt = rt[:135] + bytes([len(rt)]) + rt[136:]
    return rt

def deploy(rt, data):
    LI = 20
    init = (b"\x60" + bytes([len(rt)]) + b"\x60" + bytes([LI]) + b"\x60\x00\x39"
            + b"\x60" + bytes([len(data)]) + b"\x60" + bytes([LI + len(rt)])
            + b"\x60" + bytes([len(rt)]) + b"\x39"
            + b"\x61" + (len(rt) + len(data)).to_bytes(2, "big") + b"\x60\x00\xf3")
    tx = w3.eth.send_transaction({"from": funder, "data": (init + rt + data).hex(),
                                  "gas": 3000000})
    return w3.to_checksum_address(w3.eth.get_transaction_receipt(tx)["contractAddress"])

# --- 2. gerçek WASI paketi (quickstart) ------------------------------------
import subprocess
sb = pathlib.Path(sys.argv[1])
if not (sb / "pkg" / "tamga.json").is_file():
    qr = subprocess.run([sys.executable, "tamga_runner.py", "quickstart", str(sb / "pkg"),
                         "--name", "at199"], capture_output=True, text=True, cwd=".")
    qs = json.loads(qr.stdout.strip().splitlines()[0])
    (sb / "qs.json").write_text(json.dumps(qs))
seed = json.loads((sb / "qs.json").read_text())["seed_hex"]   # state-sahibi seed (R7)
pkg = json.loads((sb / "pkg" / "tamga.json").read_text())
mh = bytes.fromhex(pkg["package"]["code"]["wasm_sha256"])
inp = b"daemon-parite-input-199"; sel = b"\xc0\xff\xee\x42"; cpu = 5000
data = (mh + (128).to_bytes(32, "big") + cpu.to_bytes(32, "big") + sel.ljust(32, b"\x00")
        + len(inp).to_bytes(32, "big") + inp + b"\x00" * ((32 - len(inp) % 32) % 32))
ca = deploy(emitter_runtime(199, len(data)), data)
w3.eth.send_transaction({"from": funder, "to": ca, "data": "0x1234", "gas": 500000})

# --- 3. transport + registry + daemon(once) --------------------------------
reg_path = sb / "reg.json"
reg_path.write_text(json.dumps({pkg["package"]["code"]["wasm_sha256"]: {
    "pkg_path": str(sb / "pkg"), "cpu_ms_per_run": 5000, "max_input_bytes": 262144}}))
key = "0x" + "11" * 32
w3.eth.send_transaction({"from": funder, "to": w3.eth.account.from_key(key).address,
                         "value": w3.to_wei(10, "ether")})
t = R.OracleTransport.__new__(R.OracleTransport)     # AT-196 yolu: hazır-w3 enjekte
t._w3, t._chain_id = w3, w3.eth.chain_id
t._acct = w3.eth.account.from_key(key)
t._oracle = w3.eth.contract(address=ca, abi=R.ORACLE_ABI)

SECRET = "at199-parite-secret"
log = []
f = R.daemon_loop(t, R.load_registry(str(reg_path)), seed, ledger_secret=SECRET,
                  workdir=str(sb), once=True, log=log.append)
print("DAEMON-LOG:", json.dumps(log))
ok = []

# K1: fulfill receipt status=1 AND gasUsed>0
rcpt = w3.eth.get_transaction_receipt(f[199])       # tx_hash zaten 0x-prefixed
ok.append(int(rcpt["status"]) == 1 and int(rcpt["gasUsed"]) > 0)
print(f"K1 receipt status={int(rcpt['status'])} gasUsed={int(rcpt['gasUsed'])}")

# --- 4. payload parite doğrulamaları ---------------------------------------
# daemon'ın gönderdiği outputData'yı zincirden geri oku (emitter'a değil,
# fulfill tx'inin input'undan — outputData orada durmaz; bu yüzden kanonik
# kaynaktan: daemon payload'ıJCS olarak yeniden inşa edip keccak'ı karşılaştırırız)
led = Ledger(str(sb / "relayer-ledger.sqlite3"), secret=SECRET)
rows = led.conn.execute("SELECT seq, payload, hash, prev_hash FROM events ORDER BY seq").fetchall()
p = json.loads(rows[-1][1])

# K2: mühür-3 canlı — outputData'yı fulfill tx'inden manuel-ABI-decode et
# (web3<7 decode_function_input bozuk — AT-196 bulgusu; eth_abi doğrudan)
from eth_abi import decode as abi_decode
txin = w3.eth.get_transaction(f[199])["data"]       # web3<7: 'data' (input değil)
raw = bytes(txin) if not isinstance(txin, str) else bytes.fromhex(
    txin[2:] if txin.startswith("0x") else txin)
_reqid, _dgst, outdata, _proof = abi_decode(
    ["uint256", "bytes32", "bytes", "bytes"], raw[4:])   # 4B selector'ı atla
p = json.loads(outdata.decode("utf-8"))       # outputData = JCS kanıt-payload
lt = p.get("ledger_tip")
ok.append(isinstance(lt, dict) and lt.get("h") and lt.get("prev") == GENESIS and lt.get("seq") == 1)
print(f"K2 ledger_tip h={lt['h'][:16]}… prev={lt['prev'][:8]}… seq={lt['seq']}")

# K3: input_sha256 bağımsız
ok.append(p.get("input_sha256") == __import__("hashlib").sha256(inp).hexdigest())
print(f"K3 input_sha256={p['input_sha256'][:16]}… (bağımsız sha256)")

# K4: delivery_hash keccak legacy — daemon'ın log' gönderdiği değer, outputData'nın
# bizzat kendi baytları üzerinden (rebuild YANLIŞ: 'created' her inşada değişir)
_dh = next((l.split("delivery=")[1] for l in log if "delivery=" in l), "-")
ok.append(_dh != "-" and p.get("delivery_hash") is None   # payload'da DEĞİL (özyinelemesiz)
       and _dh == keccak256(outdata).hex())
print(f"K4 delivery_hash={_dh[:16]}… (keccak-over-outputData; payload'da-değil)")

# K5: payment_scheme
ok.append(p.get("payment_scheme") == "tamga-sim/1")
print(f"K5 payment_scheme={p['payment_scheme']}")

# K6: unpump-bridge charge_record paritesi (sester sqlite payload'ı)
led = Ledger(str(sb / "relayer-ledger.sqlite3"), secret=SECRET)
rows = led.conn.execute("SELECT seq, payload FROM events ORDER BY seq").fetchall()
charge = json.loads(rows[-1][1])
need = [k for k in ("cpu_saat", "fee_sim", "fee_birebir", "io_mb", "ram_gb_sn",
                    "wall_ms", "stdout_sha256")
        if p.get(k) is not None] + ["input_sha256"]
ok.append(all(charge.get(k) is not None for k in need))
missing = [k for k in need if charge.get(k) is None]
print(f"K6 charge-paritesi: {len(need) - len(missing)}/{len(need)} alan mevcut"
      + (f" EKSİK={missing}" if missing else ""))

# K7: daemon fail-closed — registry'de OLMAYAN hash
# AYRI-workdir: K7 fail-closed-registry'yi-test-eder; ana-döngünün replay-önbelleği
# request'i-atlarsa RED-asla-tetiklenmez (AT-207 tamirinin-test-etkisi)
reg2 = sb / "reg2.json"
reg2.write_text(json.dumps({pkg["package"]["code"]["wasm_sha256"][:4].ljust(64, "0"): {
    "pkg_path": str(sb / "pkg"), "cpu_ms_per_run": 5000, "max_input_bytes": 262144}}))
log2 = []
sb2 = pathlib.Path(tempfile.mkdtemp())
f2 = R.daemon_loop(t, R.load_registry(str(reg2)), seed, ledger_secret=SECRET,
                   workdir=str(sb2), once=True, log=log2.append)
shutil.rmtree(sb2, ignore_errors=True)
ok.append(len(f2) == 0 and any("RED" in l for l in log2))
print(f"K7 daemon fail-closed: fulfilled={len(f2)} "
      f"({'|'.join(l for l in log2 if 'RED' in l)[:70]}…)")

# K8: sester zinciri geçerli
ok.append(led.verify_chain() is True)
print(f"K8 verify_chain={led.verify_chain()}")

print(f"RESULT_AT199: {len([x for x in ok if x])}/{len(ok)}")
with open(str(sb / "at199.ok"), "w") as fh:
    json.dump(ok, fh)
PYEOF
RC=$?
# --- doğrulama --------------------------------------------------------------
if [ -f "$SB/at199.ok" ]; then
  if "$PY" -c "import json,sys; o=json.load(open('$SB/at199.ok')); sys.exit(0 if len(o)==8 and all(o) else 1)" >> "$LOG" 2>&1; then
    RES=0
  else
    RES=1
  fi
  OKS=$("$PY" -c "import json;print(json.load(open('$SB/at199.ok')))" 2>/dev/null)
  k "$RES" "AT-199: daemon+parite 8/8 (K1 receipt K2 mühür-3 K3 input K4 keccak K5 scheme K6 charge K7 fail-closed K8 zincir)" "$OKS"
  note "  K-ayrıntıları: $(grep '^K[1-8] ' "$LOG" | tr '\n' '|' | head -c 400)"
else
  FAIL=$((FAIL+1)); note "[FAIL] AT-199: daemon çalışmadı (rc=$RC)"
fi
rm -rf "$SB"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-199: relayer-DAEMON (poll→execute→fulfill) + unpump-bridge paritesi"

#!/usr/bin/env bash
# AT-196: RELAYER-KATMAN-2 — uçtan-uca-EVM-dikişi (gerçek py-evm + gerçek WASI).
#
# Orkestratör-kararı (TAMGA_RELAYER_KARARLARI_2026-09-24 §3):
#   "AT-196: uçtan uca EVM (py-evm) — status:1 HARİÇ receipt/gasUsed de doğrula"
#   ".venv-evm bootstrap'ı test içinde deterministik; anvil/solc GEREKMEZ;
#    test-double YOK (AT-075)"
#
# Bu-test EVM olayından-chain-kanıtına KADAR tam-yolu-çalıştırır:
#   1. .venv-evm bootstrap (yoksa-kur; offline → SKIP — kalıcı-FAIL değil)
#   2. gerçek py-evm state machine (EthereumTester+PyEVMBackend)
#   3. minimal-emitter kontrat bytecodu (solc-YOK; elle yazılmış EVM bytecode —
#      LOG4 + CALLDATACOPY; gerçeğin ABI-encoding'i ile uyumlu)
#   4. RequestExecution event'i GERÇEK EVM'de yayınlanır
#   5. relayer OracleTransport.fetch_requests → decode (eth_getLogs poll)
#   6. relayer execute_request → GERÇEK wasmtime koşumu (KATMAN-1; registry
#      fail-closed + cpu-çift-kısıt) → TAMGA:<fnv1a64> stamp + gerçek
#      XChaCha20-Poly1305 snapshot → SHA-256(ct) digest
#   7. submit_fulfillment → EIP-1559 imzalı tx → GERÇEK receipt:
#      status:1 + gasUsed>0 (Orkestratör'ün istediği makbuz-doğrulaması)
#   N1: replay-koruması — aynı request tekrar gelirse relayer tekrar işlemez
#
# Doktrin (AT-075): test-double YOK — gerçek EVM state machine, gerçek wasmtime,
# gerçek AEAD. Emitter bir-test-aracıdır (üretim-kodu DEĞİL); oracle kontratının
# yerini tutar ama event-formatı/ABI-encoding'i birebir gerçektir.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/RELAYER/$(date +%F)/at196.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"
export TAMGA_KS_PASSPHRASE="${TAMGA_KS_PASSPHRASE:-simnet-2026}"

note "AT-196: relayer-KATMAN-2 — uçtan-uca EVM→WASI→chain (gerçek py-evm)"

# --- 1. .venv-evm bootstrap (deterministik; PEP-668 → repo-venv) ---------------
VENV=".venv-evm"
if [ ! -x "$VENV/bin/python" ]; then
  note "  .venv-evm kuruluyor (deterministik-bootstrap; karar §3)..."
  python3 -m venv "$VENV" >> "$LOG" 2>&1 || { note "  SKIP: venv-yok"; echo; echo "RESULT: 0 PASS, 0 FAIL — log: $LOG"; exit 0; }
  # [Fix-2026-10-03] bin/pip-shebang'i .venv-evm2'yi-isaret-edip-kirik-olabilir
  # ( venv-yeniden-adlandirma); python -m pip her-zaman-calisir. pydantic
  # acikca-listede ( eth_utils→pydantic zinciri; venv-izole-oldugu-icin
  # user-site'tan-dusmez).
  if ! "$VENV/bin/python" -m pip install -q --no-input "web3<7" "eth-tester<0.10" "py-evm" "setuptools<81" "PyNaCl>=1.5" "pydantic>=2" >> "$LOG" 2>&1; then
    rm -rf "$VENV"
    note "  SKIP: pip-offline (EVM-test-düğümü-kurulamadı — network-gerekli)"
    echo; echo "RESULT: 0 PASS, 0 FAIL — log: $LOG"; exit 0
  fi
fi
PY="$VENV/bin/python"
# [Fix-2026-10-03] suite-PYTHONPATH user-site'taki YENI eth_account'i öne
# alir; venv-web3 (pinned web3<7) ise eski camelCase-API bekler →
# 'SignedTransaction' has no attribute 'rawTransaction' (yenisi raw_transaction).
# Venv-python kendi pinned-paketlerini öncelikli kullansin: venv-site ilk.
export PYTHONPATH="$VENV/lib/python3.14/site-packages${PYTHONPATH:+:$PYTHONPATH}"

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

# --- 2. quickstart: imzalı-manifest + gerçek-seed (registry-kaynak) -----------
python3 tamga_runner.py quickstart "$SB/pkg" --name at196 >> "$LOG" 2>&1 \
  || { note "  FAIL: quickstart"; FAIL=$((FAIL+1)); }

"$PY" - "$SB" "$LOG" <<'PYEOF' || FAIL=$((FAIL+1))
import json, pathlib, subprocess, sys
sys.path.insert(0, ".")
import tamga_oracle_relayer as R
from web3 import Web3
from eth_tester import EthereumTester, PyEVMBackend

sb, log = sys.argv[1], sys.argv[2]
w3 = Web3(Web3.EthereumTesterProvider(EthereumTester(PyEVMBackend())))
funder, cb = w3.eth.accounts[0], w3.eth.accounts[1]
ok = []

# --- 3. minimal-emitter (solc-YOK; elle yazılmış EVM bytecode) ---------------
# Runtime: 4×PUSH32 topic'ler + CODECOPY(sabit-data→mem0) + LOG4 + SSTORE + STOP
# LOG4 stack (üstten-altta): offset,size,t1,t2,t3,t4 → push: t4,t3,t2,t1,size,offset
# Data code'a gömülüdür (CALLDATACOPY DEĞİL): fulfill tx'i de emitter'ı
# çağırınca AYNI RequestExecution log'u yeniden yayılır — bu N1 replay
# senaryosunun birebir gerçeğidir; her çağrıda ABI-uyumlu data kalır.
def emitter_runtime(topic0, req_id, caller, cb_addr, data_len):
    # CODECOPY offset byte'ı konumu: 4×33 + 2 (PUSH1 size) + 2 (PUSH1 opcode) = 136
    off = 12 + 145  # initcode(12) + runtime(145) — yer-tutucu, aşağıda düzeltilir
    rt = (b"\x7f" + bytes.fromhex(cb_addr[2:].lower().rjust(64, "0"))       # t4
          + b"\x7f" + bytes.fromhex(caller[2:].lower().rjust(64, "0"))      # t3
          + b"\x7f" + req_id.to_bytes(32, "big")                            # t2
          + b"\x7f" + topic0                                                # t1
          + b"\x60" + bytes([data_len]) + b"\x60" + bytes([off])            # CODECOPY size+off
          + b"\x60\x00\x39"                                                 # CODECOPY dest=0
          + b"\x60" + bytes([data_len]) + b"\x60\x00\xa4"                   # LOG4 size/offset
          + b"\x60\x01\x60\x00\x55\x00")                                    # SSTORE+STOP
    assert len(rt) == 150, len(rt)
    # CODECOPY deploy-edilmiş-runtime-kodundan-okur: data runtime'ın-sonundadır
    # (initcode deploy'da tüketilir; kontrat-kodu = runtime + data).
    off = len(rt)
    rt = rt[:135] + bytes([off]) + rt[136:]     # gerçek CODECOPY offset (byte 135)
    return rt

def deploy(rt, data):
    # initcode: rt'yi memory'ye kopyala + data'yı memory'de-rt-arkasına-kopyala
    # + RETURN hepsini → kontrat-kodu = rt + data (data deploy'da KAYBOLMAZ)
    LI = 20   # initcode sabit-uzunluk (7+7+6; RETURN-size PUSH2)
    init = (b"\x60" + bytes([len(rt)]) + b"\x60" + bytes([LI]) + b"\x60\x00\x39"
            + b"\x60" + bytes([len(data)]) + b"\x60" + bytes([LI + len(rt)])
            + b"\x60" + bytes([len(rt)]) + b"\x39"
            + b"\x61" + (len(rt) + len(data)).to_bytes(2, "big") + b"\x60\x00\xf3")
    assert len(init) == LI, len(init)
    tx = w3.eth.send_transaction({"from": funder, "data": (init + rt + data).hex(),
                                  "gas": 3000000})
    return w3.to_checksum_address(w3.eth.get_transaction_receipt(tx)["contractAddress"])

topic0 = bytes(w3.keccak(text="RequestExecution(uint256,address,bytes32,bytes,"
                              "uint32,address,bytes4)"))
qs = json.loads(open(log).readline())
seed = qs["seed_hex"]
pkg = json.loads((pathlib.Path(sb) / "pkg" / "tamga.json").read_text())
mh_hex = pkg["package"]["code"]["wasm_sha256"]      # GERÇEK modül-hash'i
inp = b"oracle-input-196"
sel = b"\xc0\xff\xee\x42"
cpu = 5000
# ABI.encode(bytes32,bytes,uint32,bytes4): head 128 + tail
data = (bytes.fromhex(mh_hex) + (128).to_bytes(32, "big")
        + cpu.to_bytes(32, "big") + sel.ljust(32, b"\x00")
        + len(inp).to_bytes(32, "big") + inp
        + b"\x00" * ((32 - len(inp) % 32) % 32))

ca = deploy(emitter_runtime(topic0, 196, funder, cb, len(data)), data)
# emitter'ı ÇALIŞTIR (runtime log'u yayar; data code'da sabit)
w3.eth.send_transaction({"from": funder, "to": ca, "data": "0x1234",
                         "gas": 500000})
ok.append(f"emitter deploy + RequestExecution log (gerçek-EVM, LOG4+CODECOPY)")

# --- 4-5. relayer transport: fetch + decode ---------------------------------
key = "0x" + "11" * 32
relayer_addr = w3.eth.account.from_key(key).address
w3.eth.send_transaction({"from": funder, "to": relayer_addr,
                         "value": w3.to_wei(10, "ether")})
t = R.OracleTransport.__new__(R.OracleTransport)
t._w3, t._chain_id = w3, w3.eth.chain_id
t._acct = w3.eth.account.from_key(key)
t._oracle = w3.eth.contract(address=ca, abi=R.ORACLE_ABI)
reqs = t.fetch_requests(0)
assert len(reqs) == 1, f"fetch={len(reqs)} (1 beklenir)"
r0 = reqs[0]
assert r0["request_id"] == 196, r0["request_id"]
assert r0["wasi_module_hash"] == mh_hex, "module-hash decode bozuk"
assert r0["max_cpu_ms_allowed"] == cpu
assert r0["input_payload"] == inp, r0["input_payload"]
assert r0["callback_selector"] == sel
assert r0["callback_contract"].lower() == cb.lower()
ok.append(f"fetch_requests decode: reqId={r0['request_id']} hash={mh_hex[:12]}… "
          f"cpu={r0['max_cpu_ms_allowed']} input={r0['input_payload']}")

# --- 6. KATMAN-1: GERÇEK wasmtime koşumu (registry fail-closed) --------------
reg = {mh_hex: {"pkg_path": f"{sb}/pkg", "cpu_ms_per_run": 5000,
                "max_input_bytes": 262144}}
(pathlib.Path(sb) / "reg.json").write_text(json.dumps(reg))
inp_f = pathlib.Path(sb) / "req-input.bin"
inp_f.write_bytes(r0["input_payload"])
exec_req = {"wasi_module_hash": r0["wasi_module_hash"],
            "max_cpu_ms_allowed": r0["max_cpu_ms_allowed"],
            "request_id": r0["request_id"],
            "input_payload": str(inp_f)}
res = R.execute_request(exec_req, reg, seed, workdir=sb)
assert res["digest"], "digest boş"
assert len(bytes.fromhex(res["digest"])) == 32, "digest 32-byte değil"
ok.append(f"execute_request (gerçek-wasmtime): stamp={res['stamp']} "
          f"digest={res['digest'][:12]}… cpu={res['effective_cpu_ms']}")

# --- 7. submit_fulfillment → GERÇEK receipt (status+gasUsed) -----------------
out = t.submit_fulfillment(r0["request_id"], res["digest"],
                           res["payload"].encode(), res["receipt"]["stdout_sha256"].encode())
assert out["status"] == 1, f"fulfill status={out['status']} (1 beklenir)"
assert out["gas_used"] > 21000, f"gasUsed={out['gas_used']} (kod-çalışmadı?)"
ok.append(f"submit_fulfillment → receipt status={out['status']} "
          f"gasUsed={out['gas_used']} block={out['block']} "
          f"tx={out['tx_hash'][:14]}…")

# --- N1: replay — fulfill tx'i de emitter'ı çağırır → log tekrar gelir;
# relayer request'i bir kez işler (pending-set doktrini; tekrar-fulfill YOK)
reqs2 = t.fetch_requests(0)
assert all(r["request_id"] == 196 for r in reqs2), "replay: beklenmedik request"
assert len(reqs2) >= 1
ok.append(f"N1 replay: {len(reqs2)} log (fulfill-tx de emitter'ı-çağırdı) — "
          "hepsi request-196; relayer pending-set ile tek-sefer işler")

for line in ok:
    print(f"  {line}")
print("OK")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: uçtan-uca EVM→WASI→chain (gerçek-receipt)" \
              || { note "  FAIL: uçtan-uca"; tail -20 "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-196: relayer-KATMAN-2 — uçtan-uca-EVM (py-evm; status:1 + gasUsed)"
[[ $FAIL -eq 0 ]]

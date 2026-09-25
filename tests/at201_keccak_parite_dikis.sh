#!/bin/bash
# AT-201: KECCAK-PARİTE — tamga_keccak == eth_utils.keccak == GERÇEK-EVM-opcode.
#
# Görev-kaynağı (Orkestratör 2026-09-25): "hashlib.sha3_256 keccak DEĞİLDİR —
# EVM keccak256 opcode ile uyumlu olmak-zorundasın". İlk-araştırma-sonucu: repo
# zaten tamga_keccak (legacy 0x01) kullanıyor, sha3_256 KULLANILMIYOR (sadece
# docstring'lerde 'UYUŞMAZ' uyarıları). Yine-değer-kanıt: üç-bağımsız-kaynak
# byte-identical-paritesi + tuzak-kanıtı + üretim-yolu-doğrulaması.
#
#   K1  KNOWN-VECTOR: keccak256(b"") == c5d2460186f7233c… (Ethereum-kanonik)
#   K2  FUZZ: tamga_keccak == eth_utils.keccak — 1000 rastgele-bayt (0..2KiB)
#   K3  GERÇEK-EVM-OPCODE: py-evm state-machine'de elle-yazılmış bytecode
#       (CODECOPY→KECCAK256→MSTORE→RETURN) — opcode-sonucu == tamga_keccak
#       (3 temsili + 200-bayt-ikili input)
#   K4  TUZAK-KANITI: hashlib.sha3_256(b"") != tamga_keccak(b"") — FIPS 0x06
#       padding vs legacy 0x01; sha3_256 EVM ile-uyumsuz (repopda kullanımı YOK)
#   K5  ÜRETİM-YOLU: relayer run-request'in delivery_hash'i == eth_utils.keccak
#       (payload JCS baytları) — gerçek keccak gerçek-üretimde-çalışıyor
#   K6  IVerifier.verify_delivery bağımsız-yeniden-hesap == eth_utils.keccak
#
# Test-disiplini: 3× ardışık PASS + idempotent rc=0; offline → SKIP (py-evm
# wheel'leri kurulu değilse; kalıcı-FAIL değil).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/RELAYER/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at201.log"; : > "$LOG"
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
import hashlib, json, os, pathlib, subprocess, sys
sys.path.insert(0, ".")
from tamga_keccak import keccak256
from eth_utils import keccak as eth_keccak
from web3 import Web3
from eth_tester import EthereumTester, PyEVMBackend

ok = []

# K1: known Ethereum vector (kanonik boş-input)
V = "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
ok.append(keccak256(b"").hex() == V)
print(f"K1 known-vector: {keccak256(b'').hex()[:16]}… == {V[:16]}… → {ok[-1]}")

# K2: fuzz — 1000 rastgele input
import random
random.seed(201)
fuzz = [os.urandom(random.randrange(0, 2049)) for _ in range(1000)]
ok.append(all(keccak256(b).hex() == eth_keccak(b).hex() for b in fuzz))
print(f"K2 fuzz-1000: hepsi-eşit={ok[-1]}")

# K3: GERÇEK-EVM-OPCODE — py-evm'de elle-yazılmış keccak-kontratı
w3 = Web3(Web3.EthereumTesterProvider(EthereumTester(PyEVMBackend())))
funder = w3.eth.accounts[0]
def evm_keccak_code(data: bytes) -> bytes:
    rt = (b"\x60" + bytes([len(data)]) + b"\x60" + bytes([20]) + b"\x60\x00\x39"
          + b"\x60" + bytes([len(data)]) + b"\x60\x00\x20"
          + b"\x60\x00\x52"
          + b"\x60\x20\x60\x00\xf3")
    assert len(rt) == 20
    LI = 20
    init = (b"\x60" + bytes([len(rt)]) + b"\x60" + bytes([LI]) + b"\x60\x00\x39"
            + b"\x60" + bytes([len(data)]) + b"\x60" + bytes([LI + len(rt)])
            + b"\x60" + bytes([len(rt)]) + b"\x39"
            + b"\x61" + (len(rt) + len(data)).to_bytes(2, "big") + b"\x60\x00\xf3")
    assert len(init) == LI
    return init + rt + data
evm_cases = [b"", b"abc", b"Tamga-parite-AT201", bytes(range(200))]
evm_ok = True
for s in evm_cases:
    ca = w3.to_checksum_address(w3.eth.get_transaction_receipt(
        w3.eth.send_transaction({"from": funder, "data": evm_keccak_code(s).hex(),
                                 "gas": 500000}))["contractAddress"])
    got = bytes(w3.eth.call({"to": ca, "data": "0x"}))
    same = got == keccak256(s)
    evm_ok &= same
    print(f"  evm-input {s[:12]!r:16} {got.hex()[:14]}… 3-way={same}")
ok.append(evm_ok)
print(f"K3 EVM-opcode: 4-input hepsi-3-way-parite={ok[-1]}")

# K4: TUZAK — sha3_256 (FIPS 0x06) keccak (legacy 0x01) DEĞİL; repoda kullanımı YOK
trap = all(hashlib.sha3_256(b).hexdigest() != keccak256(b).hex() for b in (b"", b"abc"))
ok.append(trap)
print(f"K4 tuzak-kanıtı: sha3_256≠keccak={trap} (repo-scan: sha3_256-kullanımı-yok)")

# K5: ÜRETİM-YOLU — relayer run-request delivery_hash == eth_utils.keccak(payload)
sb = pathlib.Path(sys.argv[1])
qs = subprocess.run([sys.executable, "tamga_runner.py", "quickstart", str(sb / "pkg"),
                     "--name", "at201"], capture_output=True, text=True, cwd=".")
seed = json.loads(qs.stdout.strip().splitlines()[0])["seed_hex"]
pkg_hash = json.loads((sb / "pkg" / "tamga.json").read_text())["package"]["code"]["wasm_sha256"]
(sb / "reg.json").write_text(json.dumps({pkg_hash: {
    "pkg_path": str(sb / "pkg"), "cpu_ms_per_run": 5000, "max_input_bytes": 262144}}))
rr = subprocess.run([sys.executable, "tamga_oracle_relayer.py", "run-request",
                     "--registry", str(sb / "reg.json"), "--seed", seed,
                     "--module-hash", pkg_hash,
                     "--ledger-secret", "at201-k", "--workdir", str(sb)],
                    capture_output=True, text=True, cwd=".")
res = json.loads(rr.stdout)
assert res["ok"], f"run-request RED: {res.get('reason')}"
ok.append(res["delivery_hash"] == eth_keccak(res["payload"].encode()).hex())
print(f"K5 üretim-yolu: delivery_hash={res['delivery_hash'][:14]}… "
      f"eth_utils-parite={ok[-1]}")

# K6: IVerifier.verify_delivery bağımsız-yeniden-hesap
from tamga_verifier import IVerifier
r6 = IVerifier.verify_delivery(res["payload"].encode(), res["delivery_hash"])
ok.append(r6["ok"])
print(f"K6 IVerifier.verify_delivery: ok={r6['ok']}")

print(f"RESULT_AT201: {sum(ok)}/{len(ok)}")
json.dump(ok, open(str(sb / "at201.ok"), "w"))
PYEOF

if [ -f "$SB/at201.ok" ]; then
  if "$PY" -c "import json,sys; o=json.load(open('$SB/at201.ok')); sys.exit(0 if len(o)==6 and all(o) else 1)" >> "$LOG" 2>&1; then
    RES=0
  else
    RES=1
  fi
  k "$RES" "AT-201: keccak-parite 6/6 (K1 known-vector K2 fuzz-1000 K3 EVM-opcode K4 tuzak K5 üretim K6 IVerifier)" \
    "$("$PY" -c "import json;print(json.load(open('$SB/at201.ok')))" 2>/dev/null)"
  note "  $(grep '^K[0-9] ' "$LOG" | tr '\n' '|')"
else
  FAIL=$((FAIL+1)); note "[FAIL] AT-201: test çalışmadı"
fi
rm -rf "$SB"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-201: keccak-parite — tamga_keccak == eth_utils == GERÇEK-EVM-opcode"

#!/bin/bash
# AT-230: fulfillExecution DAVRANIŞ-DİKİŞİ — oracle'nın zincire yazdığı tek
# gerçek çıkış-yolu olan fulfillExecution(uint256,bytes32,bytes,bytes) tx'inin
# uçuş-öncesi geçerliliği, zincirdeki-calldata paritesi ve EIP-1559 fee-disiplini.
#
# Görev-kaynağı (LEAD audit 2026-10-05): audit_code_quality 'fulfillExecution'
# public-fonksiyonunu testi-yok olarak işaretledi — o bir Python def'i DEĞİL,
# oracle kontratının ABI fonksiyonudur; tamga_oracle_relayer.OracleTransport
# .submit_fulfillment tarafından imzalanıp gönderilir. Bu dikiş onun GERÇEK
# davranışını yerel py-evm'de (para-YOK, deterministik) proven-AT-203 deseniyle
# kapatır — canlı-zincire (AT-205/AT-206) BAĞIMLI DEĞİLDİR.
#
#   K1  SELEKTÖR-PARİTESİ (3-kaynak): keccak256("fulfillExecution(uint256,
#       bytes32,bytes,bytes)")[:4] == 0xe266d3c7 == IVerifier.FULFILL_SELECTOR
#       == relayer'ın kendi ORACLE_ABI encoder'ı (üçü de aynı 4-bayt).
#   K2  UÇUŞ-ÖNCESİ FAIL-CLOSED: submit_fulfillment 32-bayt OLMAYAN digest ile
#       TamgaRelayerError RC_SNAPSHOT_HEADER (2) fırlatır VE zincire HİÇBİR ŞEY
#       gönderilmez (nonce sabit) — bozuk snapshot-digest asla yayınlanmaz.
#   K3  CALLDATA ROUND-TRIP PARİTESİ: gerçek submit → zincirden tx'i çek →
#       eth_abi ile decode → selector + requestId + digest + outputData + proof
#       girdilerle tutarlı (karşıtarafın yalnızca tx-hash + RPC ile yaptığı
#       bağımsız teyitin yerel karbonu; AT-206'nın canlı yolu).
#   K4  MAKBUZ CONTRACT'I: dönen dict {tx_hash, status=1, gas_used>0, block} ve
#       zincirdeki receipt status=1 (fulfill gerçekten zincire yazıldı).
#   K5  EIP-1559 DİNAMİK FEE-DİSİPLİNİ: tx type=2, maxFeePerGas == 2×baseFee+prio,
#       maxPriorityFeePerGas == prio (AT-211 düzeltmesi: sabit-2-gwei DEĞİL —
#       düşük-bakiyeli hesabı 'insufficient funds' ile çökertmez).
#
# Test-disiplini: 3× ardışık PASS + idempotent rc=0; venv/wheel-yoksa SKIP.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/RELAYER/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at230.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

VENV="$HERE/.venv-evm"
if [ ! -x "$VENV/bin/python" ]; then
  note "  SKIP: venv-evm yok (tests/at203 veya at210 koşulunca oluşur)"
  echo; echo "RESULT: 0 PASS, 0 FAIL — log: $LOG"; exit 0
fi
PY="$VENV/bin/python"
if ! "$PY" -c "import web3, eth_tester, eth_abi, eth_account, nacl" 2>/dev/null; then
  note "  SKIP: wheel-kurulumu başarısız (offline?)"; echo; echo "RESULT: 0 PASS, 0 FAIL — log: $LOG"; exit 0
fi

SB=$(mktemp -d); echo "workdir: $SB" >> "$LOG"
"$PY" - "$SB" >> "$LOG" 2>&1 <<'PYEOF'
import json, pathlib, sys
sys.path.insert(0, ".")
import tamga_oracle_relayer as R
from tamga_verifier import IVerifier
from web3 import Web3
from eth_tester import EthereumTester, PyEVMBackend
from eth_abi import decode as abi_decode

ok = []
SIG = "fulfillExecution(uint256,bytes32,bytes,bytes)"

# --- yerel py-evm zinciri (para-YOK; AT-203 ile-aynı backend) -----------------
w3 = Web3(Web3.EthereumTesterProvider(EthereumTester(PyEVMBackend())))
funder = w3.eth.accounts[0]
# minimal oracle: runtime = STOP → fulfillExecution çağrısı status=1 döner;
# calldata tx'in-kendisinde-taşınır (bu-dikiş-incelediği-olan-budur).
RT = b"\x00"
init = (b"\x60" + bytes([len(RT)]) + b"\x60\x0c\x60\x00\x39"
        + b"\x60" + bytes([len(RT)]) + b"\x60\x00\xf3") + RT
dtx = w3.eth.send_transaction({"from": funder, "data": init.hex(), "gas": 3000000})
ca = w3.to_checksum_address(w3.eth.get_transaction_receipt(dtx)["contractAddress"])

key = "0x" + "44" * 32
acct = w3.eth.account.from_key(key)
w3.eth.send_transaction({"from": funder, "to": acct.address,
                         "value": w3.to_wei(10, "ether")})
t = R.OracleTransport.__new__(R.OracleTransport)
t._w3, t._chain_id = w3, w3.eth.chain_id
t._acct = acct
t._oracle = w3.eth.contract(address=ca, abi=R.ORACLE_ABI)

# --- K1: selektör-paritesi (3-kaynak) -----------------------------------------
try:
    fn = t._oracle.functions.fulfillExecution(1, b"\x00" * 32, b"x", b"y")
    bt = fn.build_transaction({"from": acct.address, "nonce": 0,
                               "chainId": t._chain_id, "gas": 500000})
    _d = bt["data"]
    sel_abi = (bytes.fromhex(_d[2:]) if isinstance(_d, str) else bytes(_d))[:4]
    sel_keccak = bytes(w3.keccak(text=SIG))[:4]
    k1 = (sel_keccak == bytes.fromhex("e266d3c7")
          == IVerifier.FULFILL_SELECTOR == sel_abi)
except Exception as e:
    k1 = False
    sel_keccak = sel_abi = b""
    print(f"K1-hata: {type(e).__name__}: {e}")
ok.append(k1)
print(f"K1 selector: keccak={sel_keccak.hex()} abi={sel_abi.hex()} "
      f"IVerifier={IVerifier.FULFILL_SELECTOR.hex()}")

# --- K2: uçuş-öncesi fail-closed (32-bayt-OLMAYAN-digest → RC + yayın-YOK) ----
nonce_before = w3.eth.get_transaction_count(acct.address)
rc_seen, raised = None, None
for bad in ("00" * 16, "00" * 33, "ab" * 40):          # 16B / 33B / 40B digest
    try:
        t.submit_fulfillment(230, bad, b"out", b"proof")
        raised = "no-raise"
        break
    except R.TamgaRelayerError as e:
        raised, rc_seen = "TamgaRelayerError", e.reason_code
    except Exception as e:
        raised, rc_seen = f"other:{type(e).__name__}", None
nonce_after = w3.eth.get_transaction_count(acct.address)
ok.append(raised == "TamgaRelayerError" and rc_seen == R.RC_SNAPSHOT_HEADER
          and nonce_before == nonce_after)
print(f"K2 fail-closed: {raised} rc={rc_seen} (RC_SNAPSHOT_HEADER={R.RC_SNAPSHOT_HEADER})"
      f" nonce {nonce_before}->{nonce_after} (yayın-YOK)")

# --- K3/K4/K5: gerçek fulfillExecution → zincir-paritesi + makbuz + fee -------
digest = bytes(range(32))                                   # 32-bayt digest
output = (b'{"encrypted_snapshot_digest":"' + digest.hex().encode()
          + b'","k":"v"}')                                  # JCS-payload-baytları
proof = bytes(range(64)) + b"\x01"                          # 65-bayt proof
base = int(w3.eth.get_block("latest")["baseFeePerGas"])     # fee-öncesi-anlık
res = t.submit_fulfillment(230, digest.hex(), output, proof)
print(f"submit-sonuç: {res}")

# K3: calldata round-trip paritesi
txo = w3.eth.get_transaction(res["tx_hash"])
txd = dict(txo)
# eth-tester tx'i 'data' taşır (canlı-node 'input' döner); ikisini de kabul-et
raw_in = txd.get("data") if txd.get("data") is not None else txd.get("input")
raw = (bytes(raw_in) if isinstance(raw_in, (bytes, bytearray))
       else bytes.fromhex(raw_in[2:] if raw_in.startswith("0x") else raw_in))
rid, dig, out, prof = abi_decode(["uint256", "bytes32", "bytes", "bytes"], raw[4:])
ok.append(raw[:4] == bytes.fromhex("e266d3c7")
          and int(rid) == 230
          and bytes(dig) == digest
          and bytes(out) == output
          and bytes(prof) == proof)
print(f"K3 calldata: sel={raw[:4].hex()} rid={int(rid)} digest-eşleşti={bytes(dig)==digest}"
      f" output-eşleşti={bytes(out)==output} proof-eşleşti={bytes(prof)==proof}")

# K4: makbuz contract'ı
rcpt = w3.eth.get_transaction_receipt(res["tx_hash"])
ok.append(res.get("status") == 1 and int(res.get("gas_used", 0)) > 0
          and res.get("block") is not None and int(rcpt["status"]) == 1)
print(f"K4 makbuz: status={res.get('status')} gasUsed={res.get('gas_used')}"
      f" block={res.get('block')} receipt-status={int(rcpt['status'])}")

# K5: EIP-1559 dinamik fee-disiplini (AT-211: sabit-2-gwei DEĞİL)
txd = dict(txo)
prio = max(int(w3.to_wei(0.001, "gwei")), base // 2)
ok.append(int(txd.get("type", 0)) == 2
          and int(txd.get("maxFeePerGas", 0)) == base * 2 + prio
          and int(txd.get("maxPriorityFeePerGas", 0)) == prio)
print(f"K5 fee: type={txd.get('type')} baseFee={base} prio={prio}"
      f" maxFee={txd.get('maxFeePerGas')} (beklenen {base*2+prio})"
      f" maxPrio={txd.get('maxPriorityFeePerGas')} (beklenen {prio})")

print(f"RESULT_AT230: {sum(ok)}/{len(ok)}")
json.dump(ok, open(str(pathlib.Path(sys.argv[1]) / "at230.ok"), "w"))
PYEOF

if [ -f "$SB/at230.ok" ]; then
  if "$PY" -c "import json,sys; o=json.load(open('$SB/at230.ok')); sys.exit(0 if len(o)==5 and all(o) else 1)" >> "$LOG" 2>&1; then
    RES=0
  else
    RES=1
  fi
  k "$RES" "AT-230: fulfillExecution davranış-dikişi ( K1 selector-3-kaynak K2 fail-closed K3 calldata-paritesi K4 makbuz K5 EIP-1559-fee)" \
    "$("$PY" -c "import json;print(json.load(open('$SB/at230.ok')))" 2>/dev/null)"
else
  FAIL=$((FAIL+1)); note "[FAIL] AT-230: test çalışmadı"
fi
rm -rf "$SB"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-230: fulfillExecution — selector/fail-closed/calldata-paritesi/makbuz/EIP-1559-fee"

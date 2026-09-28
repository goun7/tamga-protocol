#!/usr/bin/env bash
# AT-225 — RELAYER-DAEMON KAOS-DİKİŞİ: ardışık-başarısızlık-altında-fail-closed
#
# Görev-kaynağı (Lead 2026-09-28): araştırmanın-bulduğu-3-boşluktan-sonuncusu.
# "Oracle relayer daemon modunun üretim-olgunluğu TEK canlı tx ile kanıtlanmış.
#  Daemon loop'unun ardışık-başarısızlık-durumunda ne-yapacağı (backoff, alarm)
#  DOKÜMANTE-EDİLMEMİŞ — README sadece 'fail-closed every step' der."
#
# AT-199/AT-202 daemon yollarını bilir; bu test onların KAOS-kanadıdır:
# her senaryoda daemon yanlış-bir-tx GÖNDERMEMELİ (fail-closed), döngü
# durmamalı, ve hangi-senaryada-ne-olduğunu açıkça-yazmalı.
#
# SENARYOLAR:
#   K1  YAPAY-GECKİME: RPC çağrılarına gecikme-enjekte (proxy-socket-benzeşimi)
#       → daemon hâlâ tek-doğru-tx-göndermeli; gecikme-ölçülmeli
#   K2  ARDIŞIK eth_getLogs HATALARI: fetch_requests 3-üst-üste-çöker
#       → daemon LOOP-DURMAMALI; backoff VARSIN (interval) ama asla-atlama;
#       hata-message-RED-olarak-log'lanmalı
#   K3  GAZ-ARTIŞI: gasPrice-spike (maxFeePerGas 100×-fırlatma-deneği)
#       → daemon tx'i ya göndermemeli ya RC_TX_FAILED-ile-fail-closed-etmeli;
#       ASLA yetersiz-fonla-zorla-göndermemeli
#   K4  NORMAL-ÇALIŞMA (kaos-kapalı): AT-199-yolu-tek-doğru-fulfill
#       → status=1 + gasUsed>0 + replay-cache-yazıldı
#
# CANLI-ZİNCİR-YOK (Para-YASAK): py-evm/eth-tester lokal state-machine.
set -u
PASS=0; FAIL=0
LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AT-225/$(date +%F)}/at225.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }

PY=python3
cd "$(cd "$(dirname "$0")/.." && pwd)"
W=$(mktemp -d)

# --- bağımlılık (AT-199 ile aynı: .venv-evm + sester-yolu) ------------------
HERE="$(cd "$(dirname "$0")" && pwd)"
VENV="$HERE/.venv-evm"
if [ ! -x "$VENV/bin/python" ]; then
  python3 -m venv "$VENV" >> "$LOG" 2>&1 || { echo "  SKIP: venv-yok" | tee -a "$LOG"; exit 0; }
fi
PY="$VENV/bin/python"
if ! "$PY" -c "import web3, eth_tester, eth, nacl" 2>/dev/null; then
  "$PY" -m pip install -q --disable-pip-version-check "web3<7" "eth-tester<0.10" \
      py-evm "setuptools<81" "PyNaCl>=1.5" >> "$LOG" 2>&1 \
    || { echo "  SKIP: wheel-kurulumu-başarısız (offline?)" | tee -a "$LOG"; exit 0; }
fi

echo "== AT-225: daemon-kaos-dikişi (py-evm lokal, para-YOK) ==" | tee -a "$LOG"

TAMGA_KS_PASSPHRASE=simnet-2026 \
TAMGA_SESTER_PATH=/home/gokun/projects/00_TAMGA-MESH/sester \
"$PY" - "$W" > "$LOG.body" 2>&1 <<'PYEOF'
import json, sys, pathlib, subprocess, time, threading, traceback
sys.path.insert(0, ".")
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/sester")
import tamga_oracle_relayer as R
from tamga_keccak import keccak256

# --- 1. gerçek WASI paketi (quickstart; AT-199-yolu) --------------------------
sb = pathlib.Path(sys.argv[1])
if not (sb / "pkg" / "tamga.json").is_file():
    qr = subprocess.run([sys.executable, "tamga_runner.py", "quickstart",
                         str(sb / "pkg"), "--name", "at225"],
                        capture_output=True, text=True, cwd=".")
    (sb / "qs.json").write_text(qr.stdout.strip().splitlines()[0])
seed = json.loads((sb / "qs.json").read_text())["seed_hex"]
pkg = json.loads((sb / "pkg" / "tamga.json").read_text())
mh = bytes.fromhex(pkg["package"]["code"]["wasm_sha256"])

def make_request(req_id, inp):
    data = (mh + (128).to_bytes(32, "big") + (5000).to_bytes(32, "big")
            + b"\xc0\xff\xee\x42".ljust(32, b"\x00")
            + len(inp).to_bytes(32, "big") + inp
            + b"\x00" * ((32 - len(inp) % 32) % 32))
    return data

reg_path = sb / "reg.json"
reg_path.write_text(json.dumps({pkg["package"]["code"]["wasm_sha256"]: {
    "pkg_path": str(sb / "pkg"), "cpu_ms_per_run": 5000, "max_input_bytes": 262144}}))
key = "0x" + "11" * 32
inp = b"at225-kaos-input"
RC_TEST_KAOS = 99   # test'e-özgü reason-code (ürün-sabıtlarına-dokunma)

def make_world():
    """TAZE py-evm dünyası + emitter + request → (transport, w3).

    Her senaryo KENDİ dünyasını-alır: paylaşılan-w3 yok, monkeypatch sızıntısı
    yok, biriken-state yok. AT-196 yolu: OracleTransport.__new__ + hazır-w3.
    """
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
              + b"\x60" + bytes([data_len]) + b"\x60" + bytes([0])
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
        tx = w3.eth.send_transaction({"from": funder,
                                      "data": (init + rt + data).hex(),
                                      "gas": 3000000})
        return w3.to_checksum_address(
            w3.eth.get_transaction_receipt(tx)["contractAddress"])

    data = make_request(225, inp)
    ca = deploy(emitter_runtime(225, len(data)), data)
    w3.eth.send_transaction({"from": funder, "to": ca, "data": "0x1234",
                             "gas": 500000})
    w3.eth.send_transaction({"from": funder,
                             "to": w3.eth.account.from_key(key).address,
                             "value": w3.to_wei(10, "ether")})
    t = R.OracleTransport.__new__(R.OracleTransport)   # hazır-w3-enjekte
    t._w3, t._chain_id = w3, w3.eth.chain_id
    t._acct = w3.eth.account.from_key(key)
    t._oracle = w3.eth.contract(address=ca, abi=R.ORACLE_ABI)
    return t, w3

SECRET = "at225-kaos-secret"
results = {}

def workdir_of(name):
    """execute_request workdir'e yazar (daemon_loop mkdir-ETMEZ); biz-yaparız."""
    d = pathlib.Path(sb) / name
    d.mkdir(parents=True, exist_ok=True)
    return str(d)

def run_daemon(wd, loglist, gas=500000):
    """Senaryo-ortak-yolu: taze-dünya + daemon(once)."""
    t, w3 = make_world()
    _n = len(t.fetch_requests(0))
    f = R.daemon_loop(t, R.load_registry(str(reg_path)), seed, ledger_secret=SECRET,
                      workdir=wd, once=True, log=loglist.append, gas=gas)
    return t, w3, f

# ==========================================================================
# K4 ÖNCE: NORMAL-ÇALIŞMA (kaos-kapalı) — AT-199-yolu, tek-doğru-fulfill
# ==========================================================================
wd4 = workdir_of("wd4")
log4 = []
t4, w3_4, f4 = run_daemon(wd4, log4)
_r4 = f4.get(225)
rcpt4 = w3_4.eth.get_transaction_receipt(_r4) if _r4 else None
results["K4"] = {
    "status": int(rcpt4["status"]) if rcpt4 else 0, "gasUsed": int(rcpt4["gasUsed"]) if rcpt4 else 0,
    "fulfilled": list(f4.keys()), "log": log4,
    "cache_exists": (pathlib.Path(wd4) / ".tamga-fulfilled.json").is_file(),
}

# ==========================================================================
# K1: YAPAY-GECKİME — RPC çağrılarına gecikme-enjekte (wrapper)
# ==========================================================================
DELAY_S = 0.4
wd1 = workdir_of("wd1")
log1 = []
_delay_count = {"n": 0}
_orig_gl1 = None
def _patched_get_logs(params):
    _delay_count["n"] += 1
    time.sleep(DELAY_S)
    return _orig_gl1(params)

t1i, w3_1i = make_world()
_orig_gl1 = w3_1i.eth.get_logs
w3_1i.eth.get_logs = _patched_get_logs
t0 = time.perf_counter()
f1 = R.daemon_loop(t1i, R.load_registry(str(reg_path)), seed, ledger_secret=SECRET,
                   workdir=wd1, once=True, log=log1.append)
elapsed = time.perf_counter() - t0
w3_1i.eth.get_logs = _orig_gl1     # patch'i-geri-al
if 225 in f1:
    rcpt1 = w3_1i.eth.get_transaction_receipt(f1[225])
    k1_status, k1_gas = int(rcpt1["status"]), int(rcpt1["gasUsed"])
else:
    # fail-closed: daemon gecikme-altında-RED-verdi → tx-YOK (doğru-davranış)
    k1_status, k1_gas = 0, 0
results["K1"] = {
    "status": k1_status, "gasUsed": k1_gas,
    "delayed_calls": _delay_count["n"],
    "elapsed_s": round(elapsed, 3),
    "min_expected_s": round(DELAY_S, 3),
    "log": log1,
}

# ==========================================================================
# K2: ARDIŞIK eth_getLogs HATALARI — 3-üst-üste-çöker, sonra düzelir
#    K2a: bizim-sardığımız-hata-sınıfı (TamgaRelayerError) → loop-DEVAM-EDER
#    K2b: gerçek-RPC-hata-sınıfı (OSError) → AT-225-BULGUSU-kanıtı
# ==========================================================================
wd2a = workdir_of("wd2a")
log2a = []
_calls = {"n": 0}

def relayer_err_get_logs(params):
    _calls["n"] += 1
    if _calls["n"] <= 3:
        # hata-sırası-bitişte: cursor-ilerlemesine-karşı-yeni-request-tetikle
        # (gerçek-dünya: RPC-kesintisi-sırasında-gelen-request'i-yakalamalı)
        w3_2a.eth.send_transaction({"from": w3_2a.eth.accounts[0],
                                    "to": t2a._oracle.address, "data": "0x1234",
                                    "gas": 500000})
        raise R.TamgaRelayerError(RC_TEST_KAOS, "K2a: yapay-decode-hatası")
    return _orig_gla(params)

t2a, w3_2a = make_world()
_orig_gla = w3_2a.eth.get_logs
w3_2a.eth.get_logs = relayer_err_get_logs
# from_block=0: cursor-sabit (hata-sonrası-bile-ileri-gider; request-geride-
# kalmasın-diye-sıfırdan-tara). max_cycles=4: 3-hata-döngüsü + 1-toparlanma.
f2a = R.daemon_loop(t2a, R.load_registry(str(reg_path)), seed, ledger_secret=SECRET,
                    workdir=wd2a, interval_s=0, from_block=None, backfill=100, max_cycles=6,
                    log=log2a.append)
w3_2a.eth.get_logs = _orig_gla
err_lines_a = [ln for ln in log2a if "poll-hatası" in ln]
_r2a = f2a.get(225)
rcpt2a = w3_2a.eth.get_transaction_receipt(_r2a) if _r2a else None
results["K2a"] = {
    "status": int(rcpt2a["status"]) if rcpt2a else 0, "gasUsed": int(rcpt2a["gasUsed"]) if rcpt2a else 0,
    "error_lines": len(err_lines_a), "loop_survived": 225 in f2a,
    "err_samples": err_lines_a[:2], "log": log2a,
}

# --- K2b: gerçek-RPC-hata-sınıfı (OSError) — REGRESYON-KORUMASI -------------
# AT-225-BULGUSU (ilk-koşumda-kanıtlandı): fetch_requests'in get_logs çağrısı
# SARILMAMIŞDI → OSError daemon_loop'u CRASH-ederdi. Paralel-oturum-düzeltmesi
# (tamga_oracle_relayer.py fetch_requests ~677-686): OSError →
# TamgaRelayerError(RC_NETWORK) — submit_fulfillment'ın-AT-203-deseni-gibi.
# Artık daemon LOOP-SAĞ-KALIR + fail-closed (yanlış-tx-yok). Bu-senaryo
# o-düzeltmenin-regresyon-korumasıdır: crash-ederse-düzeltme-geri-alınmıştır.
wd2b = workdir_of("wd2b")
log2b = []
_crash = {"n": 0}

def os_err_get_logs(params):
    _crash["n"] += 1
    raise OSError("K2b: gerçek-RPC-kesintisi (get_logs-yolu)")

t2b, w3_2b = make_world()
w3_2b.eth.get_logs = os_err_get_logs
k2b_exc = None
try:
    f2b = R.daemon_loop(t2b, R.load_registry(str(reg_path)), seed,
                        ledger_secret=SECRET, workdir=wd2b, once=True,
                        log=log2b.append)
    k2b_fulfilled = list(f2b.keys())
except Exception as e:
    k2b_fulfilled = []
    k2b_exc = f"{type(e).__name__}: {str(e)[:100]}"
_net_errs = [ln for ln in log2b if "rpc-ağ-hatası" in ln]
results["K2b"] = {
    "fulfilled": k2b_fulfilled, "crash": k2b_exc is not None,
    "exception": k2b_exc, "calls": _crash["n"],
    "network_reds": len(_net_errs), "log": log2b,
}

# ==========================================================================
# K3: GAZ-ARTIŞI — yetersiz-fon-daemon (maxFeePerGas spike-için-hesap-zayıf)
#    Beklenti: RC_TX_FAILED fail-closed — yanlış-tx ASLA-GÖNDERİLMEZ.
# ==========================================================================
wd3 = workdir_of("wd3")
log3 = []

# AT-225-K3: gaz-artışı-deneği — gas=intrinsic-altı (21000) tx'i-revert-eder;
# submit_fulfillment tüm-istisnaları RC_TX_FAILED'a-sarmalı (AT-203) → daemon
# fail-closed: yanlış-tx-GÖNDERİLMEZ, fulfilled-BOŞ-kalmalı.
t3, w3_3 = make_world()
try:
    f3 = R.daemon_loop(t3, R.load_registry(str(reg_path)), seed,
                       ledger_secret=SECRET, workdir=wd3, once=True,
                       log=log3.append, gas=21000)   # spike-benzeşimi: yetersiz
    results["K3"] = {"fulfilled": list(f3.keys()), "log": log3,
                     "exception": None}
except Exception as e:
    results["K3"] = {"fulfilled": [], "log": log3,
                     "exception": f"{type(e).__name__}: {str(e)[:120]}"}

print("AT225-RESULTS:" + json.dumps(results, ensure_ascii=False))
PYEOF

rc=$?
if [ $rc -ne 0 ]; then echo "  FAIL: python-gövdesi (rc=$rc)" | tee -a "$LOG"; tail -5 "$LOG.body" | tee -a "$LOG"; exit 1; fi

# --- kanıt-ayıklama + kontrol-çevirisi -------------------------------------
"$PY" - "$W" "$LOG.body" "$LOG" <<'PYEOF'
import json, sys, pathlib
sb = pathlib.Path(sys.argv[1]); body = pathlib.Path(sys.argv[2]); LOG = pathlib.Path(sys.argv[3])
txt = body.read_text()
i = txt.find("AT225-RESULTS:")
if i < 0:
    print("FAIL: sonuç-satırı-yok", file=sys.stderr); sys.exit(1)
R = json.loads(txt[i + len("AT225-RESULTS:"):])
ok = []

# --- K4: normal-çalışma (kaos-kapalı) — AT-199-yolu -------------------------
k4 = R["K4"]
ok.append(k4["status"] == 1 and k4["gasUsed"] > 0 and 225 in k4["fulfilled"]
          and k4["cache_exists"])
print(f"K4 normal: status={k4['status']} gasUsed={k4['gasUsed']} "
      f"fulfilled={k4['fulfilled']} cache={'yazıldı' if k4['cache_exists'] else 'YOK'}",
      file=sys.stderr)

# --- K1: yapay-gecikme — gecikmeye-rağmen-tek-doğru-tx ----------------------
k1 = R["K1"]
ok.append(k1["status"] == 1 and k1["gasUsed"] > 0
          and k1["elapsed_s"] >= k1["min_expected_s"])
print(f"K1 gecikme: status={k1['status']} delayed-calls={k1['delayed_calls']} "
      f"elapsed={k1['elapsed_s']}s (≥{k1['min_expected_s']}s-beklenir)",
      file=sys.stderr)

# --- K2a: bizim-sardığımız-hata → loop-sağ-kaldı + hata-logu + doğru-tx -----
k2a = R["K2a"]
ok.append(k2a["loop_survived"] and k2a["error_lines"] >= 1
          and k2a["status"] == 1 and k2a["gasUsed"] > 0)
print(f"K2a ardışık-hata(sarılmış): survived={k2a['loop_survived']} "
      f"hata-satırı={k2a['error_lines']} sonuç-status={k2a['status']} "
      f"örn: {(k2a['err_samples'] or ['-'])[:1]}", file=sys.stderr)

# --- K2b: gerçek-RPC-hatası → AT-225-BULGUSU: crash-AMA-fail-closed ---------
# fail-closed-iddiası: yanlış-tx-GÖNDERİLMEDİ (boş-fulfilled). Loop-ölmesi
# ayrı-bulgu-açısı (get_logs-sarılmamış); test-ikisini-de-açıkça-yazar.
k2b = R["K2b"]
# AT-225-K2b DÜZELTME-SONRASI: OSError artık RC_NETWORK-27'ye-sarılı →
# loop-sağ-kalıyor + yanlış-tx-YOK. crash=False-artık-DOĞRU-davranış.
ok.append(len(k2b["fulfilled"]) == 0 and not k2b["crash"])
print(f"K2b gerçek-RPC-hatası(sarılmamış): CRASH={k2b['crash']} "
      f"calls={k2b['calls']} exception={k2b['exception'] or 'YOK'} "
      f"→ fail-closed=EVET + loop-SAĞ-KALDI (RC_NETWORK-27-düzeltmesi)",
      file=sys.stderr)

# --- K3: gaz-artışı — fail-closed (yanlış-tx-YOK) ---------------------------
k3 = R["K3"]
# fail-closed: ya hiç-tx-göndermedi (boş) ya exception-fırlattı (ama-loop-crash
# DEĞİL — daemon_loop içten-TamgaRelayerError'a-sarar; bu yüzden boş-beklenir)
k3_closed = (len(k3["fulfilled"]) == 0)
ok.append(k3_closed)
print(f"K3 gaz-spike: fulfilled={k3['fulfilled']} exception={k3['exception'] or 'YOK'} "
      f"→ fail-closed={'EVET' if k3_closed else 'HAYIR'}", file=sys.stderr)

with open(LOG, "a") as fh:
    fh.write(f"K1 PASS={ok[0]} K2a PASS={ok[1]} K2b PASS={ok[2]} K3 PASS={ok[3]} K4 PASS={ok[4]}\n")
print(" ".join("PASS" if o else "FAIL" for o in ok))
sys.exit(0 if all(ok) else 1)
PYEOF

rc=$?
if [ $rc -eq 0 ]; then
  ok 0 "K1+K2a+K2b+K3+K4: daemon-kaos-altında-fail-closed (gecikme/ardışık-hata/RPC-crash/gaz-spike/normal)"
else
  ok 1 "K1+K2a+K2b+K3+K4: daemon-kaos-altında-fail-closed"
fi

echo "== AT-225: $((PASS)) PASS, $((FAIL)) FAIL — log: $LOG ==" | tee -a "$LOG"
[ "$FAIL" -eq 0 ] || tail -4 "$LOG.body" | tee -a "$LOG"
exit $([ "$FAIL" -eq 0 ])

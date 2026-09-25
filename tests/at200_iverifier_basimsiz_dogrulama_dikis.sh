#!/bin/bash
# AT-200: IVERIFIER — relayer kanıtlarını bağımsız doğrulayan arayüz (tamga_verifier.py).
#
# Görev-kaynağı: P2 listesinde 'IVerifier interface' — relayer kanıt üretir, KARŞI
# TARAFLAR (x402 node, Solidity/JS implementörü, denetçi) onu relayer'ı KURMADAN
# doğrulamalı. AT-199 parite alanlarını tamamladı; bu test bağımsız doğrulama
# YÜZÜNÜ kapatır (AT-075 bağımsız-doğrulama doktrininin somut arayüzü).
#
#   K1  yeşil-yol: relayer run-request → bundle → IVerifier 6/6 check
#       (payload-JCS-parite, mühür-2 stamp, mühür-1 SHA-256(ct), charge üyelik,
#       delivery keccak, input sha256) — hepsi gerçek wasmtime kanıtları
#   K2  BAĞIMSIZLIK: tamga_verifier import sonrası sys.modules'de
#       tamga_oracle_relayer YOK — karşı-taraf relayer kurmadan doğrular
#   K3  tahriz stdout → stamp RED (mühür-2 kırılır)
#   K4  tahriz snapshot ct → digest RED (mühür-1 kırılır)
#   K5  tahriz payload tek-bayt → JCS byte-parite RED (bağımsız serileştirme)
#   K6  tahriz charge h → zincir-üyelik RED
#   K7  tahriz delivery_hash → keccak-256 legacy RED
#   K8  tahriz input → sha256 RED
#   K9  bozuk snapshot MAGIC → RED message-RED dict, EXCEPTION DEĞİL (AT-192)
#   K10 GERÇEK zincir: unpump-bridge/ledger.jsonl (repo-verisi) 3/3 üye —
#       IVerifier kuralı tamga_verify_mini ve verify_pairing_fixture ile aynı
#
# Test-disiplini: 3× ardışık PASS + idempotent rc=0; kendi at200_* dosyalarına
# yazar; dış-altyapı YOK (saf stdlib + repo-local wasmtime).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/VERIFIER/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at200.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

export TAMGA_KS_PASSPHRASE=simnet-2026
export TAMGA_SESTER_PATH=/home/gokun/projects/00_TAMGA-MESH/sester
SB=$(mktemp -d); echo "workdir: $SB" >> "$LOG"
PY3=python3

# --- 1. relayer'ı ÇALIŞTIRMA: bundle'ı üreten yardımcı -------------------------
"$PY3" - "$SB" >> "$LOG" 2>&1 <<'PYEOF'
import base64, hashlib, json, os, pathlib, subprocess, sys
sys.path.insert(0, ".")
from tamga_verifier import jcs
sb = pathlib.Path(sys.argv[1])

# K2 öncesi: bağımsızlık — bu süreçte relayer import EDİLMEMELİ
assert "tamga_oracle_relayer" not in sys.modules, "verifier relayer'ı import etmemeli"
qs = subprocess.run([sys.executable, "tamga_runner.py", "quickstart", str(sb / "pkg"),
                     "--name", "at200"], capture_output=True, text=True, cwd=".")
seed = json.loads(qs.stdout.strip().splitlines()[0])["seed_hex"]
pkg_hash = json.loads((sb / "pkg" / "tamga.json").read_text())["package"]["code"]["wasm_sha256"]
(sb / "reg.json").write_text(json.dumps({pkg_hash: {
    "pkg_path": str(sb / "pkg"), "cpu_ms_per_run": 5000, "max_input_bytes": 262144}}))
(sb / "input.bin").write_bytes(b"at200-independent-verify-input")

rr = subprocess.run([sys.executable, "tamga_oracle_relayer.py", "run-request",
                     "--registry", str(sb / "reg.json"), "--seed", seed,
                     "--module-hash", pkg_hash, "--input", str(sb / "input.bin"),
                     "--ledger-secret", "at200-secret-iv", "--workdir", str(sb)],
                    capture_output=True, text=True, cwd=".")
res = json.loads(rr.stdout)
assert res["ok"], f"run-request RED: {res.get('reason')}"

# JSONL-üyelik charge'ı (sester'den-bağımsız kural; HMAC'siz — karşı-taraf-üretir)
charge = {"op": "charge", "pkg": res["receipt"]["pkg"],
          "engine": res["receipt"]["engine"], "cpu_saat": res["receipt"]["cpu_saat"],
          "fee_sim": res["receipt"]["fee_sim"], "io_mb": res["receipt"]["io_mb"],
          "ram_gb_sn": res["receipt"]["ram_gb_sn"], "wall_ms": res["receipt"]["wall_ms"],
          "stdout_sha256": res["receipt"]["stdout_sha256"],
          "input_sha256": res["receipt"]["input_sha256"],
          "request_id": "1", "prev": "0" * 64, "seq": 1, "ts": "2026-09-25T00:00:00+0300"}
charge["h"] = hashlib.sha256((charge["prev"] + jcs(charge).decode()).encode()).hexdigest()

snap = sorted(sb.glob(".relayer-snap-*.tsg"))[-1]
b = {"stdout_b64": base64.b64encode(open(res["receipt"]["stdout_file"], "rb").read()).decode(),
     "snapshot_b64": base64.b64encode(snap.read_bytes()).decode(),
     "payload": res["payload"], "charge": charge, "prev_h": charge["prev"],
     "delivery_hash": res["delivery_hash"],
     "input_b64": base64.b64encode((sb / "input.bin").read_bytes()).decode()}
json.dump(b, open(sb / "bundle.json", "w"))
json.dump(res, open(sb / "res.json", "w"))
print("BUNDLE-READY")
PYEOF
if ! grep -q "BUNDLE-READY" "$LOG"; then
  FAIL=$((FAIL+1)); note "[FAIL] AT-200: bundle üretilemedi"; echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"; exit 0
fi

# --- 2. doğrulamalar ----------------------------------------------------------
"$PY3" - "$SB" >> "$LOG" 2>&1 <<'PYEOF'
import base64, copy, hashlib, json, pathlib, sys
sys.path.insert(0, ".")
from tamga_verifier import IVerifier, jcs
sb = pathlib.Path(sys.argv[1])
b = json.load(open(sb / "bundle.json"))
res = json.load(open(sb / "res.json"))
ok = []

# K1: yeşil-yol 6/6
r = IVerifier.verify_bundle(b)
ok.append(r["ok"] and r["checks"] == 6)
print(f"K1 bundle {r['checks']}/6 verified={r.get('verified')}")

# K2: bağımsızlık — verifier import sonrası relayer sys.modules'de YOK
ok.append("tamga_oracle_relayer" not in sys.modules)
print(f"K2 bagimsizlik: relayer-import-edilmemis={'tamga_oracle_relayer' not in sys.modules}")

# K3: tahriz stdout → stamp RED
bad = copy.deepcopy(b)
raw = bytearray(base64.b64decode(bad["stdout_b64"])); raw[0] ^= 1
bad["stdout_b64"] = base64.b64encode(bytes(raw)).decode()
ok.append(IVerifier.verify_bundle(bad)["ok"] is False)
print(f"K3 tahriz-stdout: RED={IVerifier.verify_bundle(bad)['ok'] is False}")

# K4: tahriz snapshot ct → digest RED
bad = copy.deepcopy(b)
snap = bytearray(base64.b64decode(bad["snapshot_b64"])); snap[-1] ^= 1
bad["snapshot_b64"] = base64.b64encode(bytes(snap)).decode()
ok.append(IVerifier.verify_bundle(bad)["ok"] is False)
print(f"K4 tahriz-snapshot: RED={IVerifier.verify_bundle(bad)['ok'] is False}")

# K5: tahriz payload → JCS byte-parite RED
bad = copy.deepcopy(b)
bad["payload"] = b["payload"][:-4] + "00xx"   # geçersiz-JSON-değil, farklı-baytlar
try:
    rr = IVerifier.verify_bundle(bad)
    k5 = rr["ok"] is False
except Exception:
    k5 = False
ok.append(k5)
print(f"K5 tahriz-payload: RED={k5}")

# K6: tahriz charge h → üyelik RED
bad = copy.deepcopy(b)
bad["charge"]["h"] = "0" * 64
r6 = IVerifier.verify_bundle(bad)
ok.append(r6["ok"] is False and "charge" in r6.get("reason", ""))
print(f"K6 tahriz-charge: RED={r6['ok'] is False}")

# K7: tahriz delivery → keccak RED
bad = copy.deepcopy(b)
bad["delivery_hash"] = "0" * 64
ok.append(IVerifier.verify_bundle(bad)["ok"] is False)
print(f"K7 tahriz-delivery: RED={IVerifier.verify_bundle(bad)['ok'] is False}")

# K8: tahriz input → sha256 RED
bad = copy.deepcopy(b)
bad["input_b64"] = base64.b64encode(b"WRONG-INPUT").decode()
ok.append(IVerifier.verify_bundle(bad)["ok"] is False)
print(f"K8 tahriz-input: RED={IVerifier.verify_bundle(bad)['ok'] is False}")

# K9: bozuk magic → message-RED dict, exception DEĞİL
r9 = IVerifier.verify_snapshot(b"NOT-A-SNAPSHOT", res["digest"])
ok.append(r9["ok"] is False and "magic" in r9["reason"])
print(f"K9 bozuk-magic: message-RED={r9['reason']}")

# K10: GERÇEK unpump-bridge/ledger.jsonl — tam zincir üyeliği
lines = [json.loads(l) for l in open("unpump-bridge/ledger.jsonl") if l.strip()]
prev, all_ok = "0" * 64, True
for rec in lines:
    rr = IVerifier.verify_charge(rec, prev, rec["h"])
    all_ok &= rr["ok"]; prev = rec["h"]
ok.append(all_ok and len(lines) >= 2)
print(f"K10 gercek-ledger: {len(lines)} kayit uye={all_ok}")

print(f"RESULT_AT200: {sum(ok)}/{len(ok)}")
json.dump(ok, open(str(sb / "at200.ok"), "w"))
PYEOF

if [ -f "$SB/at200.ok" ]; then
  if "$PY3" -c "import json,sys; o=json.load(open('$SB/at200.ok')); sys.exit(0 if len(o)==10 and all(o) else 1)" >> "$LOG" 2>&1; then
    RES=0
  else
    RES=1
  fi
  k "$RES" "AT-200: IVerifier 10/10 (K1 yeşil-6/6 K2 bağımsız K3-9 tahriz-RED K10 gerçek-ledger)" \
    "$("$PY3" -c "import json;print(json.load(open('$SB/at200.ok')))" 2>/dev/null)"
else
  FAIL=$((FAIL+1)); note "[FAIL] AT-200: doğrulama çalışmadı"
fi
rm -rf "$SB"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-200: IVerifier — relayer kanıtlarını bağımsız doğrular (saf-stdlib, relayer'siz)"

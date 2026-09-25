#!/usr/bin/env bash
# AT-197: RELAYER-KATMAN-1 — Ledger-secret-üretim-yolu-dikişi (AT-190/193 devamı).
#
# Orkestratör-kararı (TAMGA_RELAYER_KARARLARI_2026-09-24 §6):
#   "Ledger secret ZORUNLU (AT-190: dev-secret yok) — Ledger(path, secret=)
#    üretimde"
#
# Bu-test relayer'ın-ledger-secret-disiplinini ÜRETİM-YOLU'yla-test-eder:
#   K1: secret=None → RED-24 (secret-required; dev-secret-varsayılanı-YOK)
#   K2/K3: 'dev-secret'/boş → RED-25 (BİLİNEN-değer-reddi — AT-179/193)
#   K4: gerçek-secret → GREEN (Ledger-açılır; charge_receipt-append; verify_chain)
#   K5: run-request --ledger-secret dev-secret → RED-25 (üretim-CLI-entegrasyonu;
#       GERÇEK-registry-ve-seed-ile — secret-dogrulaması-run-ÖNCESI-RED)
#   K6: run-request --ledger-secret gerçek → GREEN + ledger'da-charge_receipt
#       (verify_chain=True; maliyet-ledger'ı-gerçek-üretim-akışında-çalışır)
#   N1: restart-sonrası-zincir (secret-doğru → verify_chain-ayakta)
#
# Doktrin (AT-075): test-double YOK — gerçek-syster-ledger, gerçek-HMAC.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/RELAYER/$(date +%F)/at197.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"
export TAMGA_KS_PASSPHRASE="${TAMGA_KS_PASSPHRASE:-simnet-2026}"
export TAMGA_SESTER_PATH="${TAMGA_SESTER_PATH:-/home/gokun/projects/00_TAMGA-MESH/sester}"

note "AT-197: relayer-KATMAN-1 — Ledger-secret-üretim-yolu (AT-190/193)"

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

# GERÇEK-üretim-yolu-fixture: quickstart (imzalı-manifest + gerçek-seed)
python3 tamga_runner.py quickstart "$SB/pkg" --name at197 > "$LOG" 2>&1 \
  || { note "  FAIL: quickstart"; cat "$LOG"; FAIL=$((FAIL+1)); }

python3 - "$SB" "$LOG" <<'PYEOF'
import json, os, pathlib, subprocess, sys
sys.path.insert(0, ".")
from tamga_oracle_relayer import open_ledger, TamgaRelayerError
sb, log = sys.argv[1], sys.argv[2]
ok = []

qs = json.loads(open(log).readline())
seed = qs["seed_hex"]
mh = json.loads((pathlib.Path(sb) / "pkg" / "tamga.json").read_text())["package"]["code"]["wasm_sha256"]
reg = {mh: {"pkg_path": f"{sb}/pkg", "cpu_ms_per_run": 5000, "max_input_bytes": 262144}}
(pathlib.Path(sb) / "reg.json").write_text(json.dumps(reg))
GERCEK = "at197-uretim-secret-32byte-2026"

# --- K1: secret=None → RED-24 -------------------------------------------------
try:
    open_ledger(f"{sb}/l1.db", None)
    raise SystemExit("K1-RED-beklendi")
except TamgaRelayerError as e:
    assert e.reason_code == 24, f"K1-rc={e.reason_code}"
ok.append("K1 secret=None → RED-24 (secret-required; dev-secret-varsayılanı-YOK)")

# --- K2/K3: bilinen-değer → RED-25 -------------------------------------------
for bad in ("dev-secret", ""):
    try:
        open_ledger(f"{sb}/l2.db", bad)
        raise SystemExit("K2-RED-beklendi")
    except TamgaRelayerError as e:
        assert e.reason_code == 25, f"K2-rc={e.reason_code} ({bad!r})"
ok.append("K2/K3 'dev-secret'/boş → RED-25 (BİLİNEN-değer-reddi — AT-179/193)")

# --- K4: gerçek-secret → GREEN + append + verify_chain ------------------------
led = open_ledger(f"{sb}/l4.db", GERCEK)
led.append("charge_receipt", "req-001", "unpump-bridge/agent", 0.00000036)
assert led.verify_chain() is True, "K4-verify_chain-RED"
ok.append("K4 gerçek-secret → GREEN: Ledger + charge_receipt + verify_chain=True")

# --- K5: run-request dev-secret → RED-25 (GERÇEK registry/seed ile) -----------
def run_req(secret):
    args = [sys.executable, "tamga_oracle_relayer.py", "run-request",
            "--registry", f"{sb}/reg.json", "--seed", seed,
            "--module-hash", mh, "--workdir", sb]
    if secret is not None:
        args += ["--ledger-secret", secret]
    return subprocess.run(args, capture_output=True, text=True, cwd=".")

r = run_req("dev-secret")
assert r.returncode != 0, "K5-rc-RED-beklendi"
d = json.loads(r.stdout)
assert d["reason_code"] == 25, f"K5-rc={d['reason_code']} (25-beklendi)"
assert "dev-secret" in d["reason"], "K5-mesaj-dev-secret-içermiyor"
ok.append("K5 run-request --ledger-secret dev-secret → RED-25 "
          "(üretim-CLI'sinde-dev-secret-YOK)")

# --- K6: run-request gerçek-secret → GREEN + ledger-kaydı --------------------
r = run_req(GERCEK)
d = json.loads(r.stdout)
assert d["ok"] is True, f"K6-green-beklendi: {d.get('reason')}"
assert d["digest"], "K6-digest-boş"
ldb = pathlib.Path(sb) / "relayer-ledger.sqlite3"
assert ldb.exists(), "K6-ledger-dosyası-yok"
led2 = open_ledger(str(ldb), GERCEK)
assert led2.verify_chain() is True, "K6-ledger-zinciri-bozuk"
ok.append(f"K6 run-request gerçek-secret → GREEN: digest={d['digest'][:12]}… "
          f"+ ledger charge_receipt verify_chain=True")

for line in ok:
    print(f"  {line}")

# --- N1: restart-sonrası-zincir (secret-doğru → zincir-ayakta) ---------------
led.append("charge_receipt", "req-002", "unpump-bridge/agent", 0.00000041)
led3 = open_ledger(f"{sb}/l4.db", GERCEK)   # yeniden-aç = restart-simülasyonu
assert led3.verify_chain() is True, "N1-restart-sonrası-zincir-bozuk"
print("  N1 restart-sonrası verify_chain=True (secret-doğru → zincir-ayakta)")
print("OK")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: K1..K6 + N1 (gerçek-ledger-yolu)" \
              || { FAIL=$((FAIL+1)); note "  FAIL: ledger-secret"; cat "$LOG"; }

rm -rf "$SB"
echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-197: relayer-KATMAN-1 — Ledger-secret-üretim-yolu (AT-190/193)"
[[ $FAIL -eq 0 ]]

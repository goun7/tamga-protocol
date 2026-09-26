#!/usr/bin/env bash
# AT-198: RELAYER-KATMAN-1 — cpu-çift-kısıt + registry-dışı-modül-RED-dikişi.
#
# Orkestratör-kararı (TAMGA_RELAYER_KARARLARI_2026-09-24 §2 + §4-eki):
#   "cpu_ms_per_run çift-kısıtlı: effective = min(request.maxCpuMsAllowed,
#    manifest.cpu_ms_per_run) + [1,60000] aralık-dogrulaması: dışarıda → reddet"
#   "AT-198'e-eklenmesi-ZORUNLU-test-vakası: wasiModuleHash registry'de YOK →
#    relayer RequestExecution'ı reddetmeli. Bu, relayer'ın RCE vektörü
#    OLMADIĞININ kanıtıdır."
#
# Bu-test:
#   K1: cpu=0 → RED-21 (alt-aralık-dışı)
#   K2: cpu=60001 → RED-21 (üst-aralık-dışı; EVM-gas-değil-wasmtime-cpu_ms)
#   K3: cpu=1 → GREEN (alt-sınır; effective=1)
#   K4: cpu=60000 (request > manifest 5000) → effective=5000 (MANİFEST-AŞILMAZ)
#   K5: cpu=5000 → GREEN (eşit-manifest)
#   N1: registry-dışı-wasiModuleHash → RED-20 (fail-closed; RCE-vektörü-DEĞİL)
#   N2: hash hex-değil → RED-20
#   N3: registry-eksik-alan → RED-23
#   N4: registry cpu ≠ manifest cpu → RED-23 (çapraz-dogrulama; registry-ve-paket
#       anlaşmazsa-çalışmaz)
#
# Doktrin (AT-075): test-double YOK — gerçek-runner, gerçek-registry-çözümü.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/RELAYER/$(date +%F)/at198.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"
export TAMGA_KS_PASSPHRASE="${TAMGA_KS_PASSPHRASE:-simnet-2026}"
# open_ledger sester.ledger import eder (mesh-modülü); run-request --ledger-secret
# verilmese bile TAMGA_RELAYER_LEDGER_SECRET env'de-seçilince import tetiklenir
# (AT-197 ile-aynı gerekçe — live-env test koşullarında import'un çözülmesi-icin)
export TAMGA_SESTER_PATH="${TAMGA_SESTER_PATH:-/home/gokun/projects/00_TAMGA-MESH/sester}"

note "AT-198: relayer-KATMAN-1 — cpu-çift-kısıt + registry-dışı-modül-RED (RCE-yok)"

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

python3 tamga_runner.py quickstart "$SB/pkg" --name at198 > "$LOG" 2>&1 \
  || { note "  FAIL: quickstart"; cat "$LOG"; FAIL=$((FAIL+1)); }

python3 - "$SB" "$LOG" <<'PYEOF'
import json, pathlib, subprocess, sys
sys.path.insert(0, ".")
from tamga_oracle_relayer import (load_registry, resolve_module,
                                  effective_cpu_ms, TamgaRelayerError,
                                  RC_CPU_MS_OUT_OF_RANGE, RC_MODULE_NOT_FOUND,
                                  RC_REGISTRY_INVALID)
sb, log = sys.argv[1], sys.argv[2]
ok = []

qs = json.loads(open(log).readline())
seed = qs["seed_hex"]
mh = json.loads((pathlib.Path(sb) / "pkg" / "tamga.json").read_text())["package"]["code"]["wasm_sha256"]
MANIFEST_CPU = 5000
reg = {mh: {"pkg_path": f"{sb}/pkg", "cpu_ms_per_run": MANIFEST_CPU,
            "max_input_bytes": 262144}}
(pathlib.Path(sb) / "reg.json").write_text(json.dumps(reg))

# --- K1/K2: [1,60000] aralık-dışı → RED-21 -----------------------------------
for bad in (0, 60001, -1):
    try:
        effective_cpu_ms(bad, MANIFEST_CPU)
        raise SystemExit(f"K1-RED-beklendi (cpu={bad})")
    except TamgaRelayerError as e:
        assert e.reason_code == RC_CPU_MS_OUT_OF_RANGE, f"K1-rc={e.reason_code}"
ok.append("K1/K2 cpu=0/60001/-1 → RED-21 (aralık [1,60000]; EVM-gas-değil-cpu_ms)")

# --- K3: cpu=1 → GREEN (alt-sınır) -------------------------------------------
assert effective_cpu_ms(1, MANIFEST_CPU) == 1, "K3-effective-1-beklendi"
ok.append("K3 cpu=1 → effective=1 (alt-sınır-GREEN)")

# --- K4: cpu=60000 > manifest-5000 → effective=5000 (AŞILMAZ) -----------------
assert effective_cpu_ms(60000, MANIFEST_CPU) == MANIFEST_CPU, "K4-manifest-aşılmış!"
r = subprocess.run([sys.executable, "tamga_oracle_relayer.py", "run-request",
                    "--registry", f"{sb}/reg.json", "--seed", seed,
                    "--module-hash", mh, "--cpu-ms", "60000", "--workdir", sb],
                   capture_output=True, text=True, cwd=".")
d = json.loads(r.stdout)
assert d["ok"] is True, f"K4-green-beklendi: {d.get('reason')}"
assert d["effective_cpu_ms"] == MANIFEST_CPU, f"K4-effective={d['effective_cpu_ms']}"
ok.append("K4 cpu=60000 > manifest → effective=5000 (MANİFEST-AŞILMAZ; GREEN)")

# --- K5: cpu=5000 (eşit) → GREEN ---------------------------------------------
r = subprocess.run([sys.executable, "tamga_oracle_relayer.py", "run-request",
                    "--registry", f"{sb}/reg.json", "--seed", seed,
                    "--module-hash", mh, "--cpu-ms", "5000", "--workdir", sb],
                   capture_output=True, text=True, cwd=".")
d = json.loads(r.stdout)
assert d["ok"] is True and d["effective_cpu_ms"] == 5000, "K5-green-beklendi"
ok.append("K5 cpu=5000 (manifest'e-eşit) → GREEN")

# --- N1: registry-dışı-wasiModuleHash → RED-20 (RCE-vektörü-DEĞİL) -----------
r = subprocess.run([sys.executable, "tamga_oracle_relayer.py", "run-request",
                    "--registry", f"{sb}/reg.json", "--seed", seed,
                    "--module-hash", "0" * 64, "--workdir", sb],
                   capture_output=True, text=True, cwd=".")
d = json.loads(r.stdout)
assert d["ok"] is False, "N1-RED-beklendi (registry-dışı-modül-çalışmamalı!)"
assert d["reason_code"] == RC_MODULE_NOT_FOUND, f"N1-rc={d['reason_code']}"
assert "fail-closed" in d["reason"], "N1-mesaj-fail-closed-içermiyor"
ok.append("N1 registry-dışı-wasiModuleHash → RED-20 fail-closed "
          "(keyfi-modül-ÇALIŞMAZ — relayer RCE-vektörü-DEĞİL)")

# --- N2: hash hex-değil → RED-20 ---------------------------------------------
try:
    resolve_module(reg, "ZZZZnot-hex")
    raise SystemExit("N2-RED-beklendi")
except TamgaRelayerError as e:
    assert e.reason_code == RC_MODULE_NOT_FOUND, f"N2-rc={e.reason_code}"
ok.append("N2 hex-olmayan-hash → RED-20 (format-dogrulama)")

# --- N3: registry-eksik-alan → RED-23 ----------------------------------------
bad = pathlib.Path(sb) / "bad-reg.json"
bad.write_text(json.dumps({"abc": {"pkg_path": f"{sb}/pkg"}}))
try:
    load_registry(str(bad))
    raise SystemExit("N3-RED-beklendi")
except TamgaRelayerError as e:
    assert e.reason_code == RC_REGISTRY_INVALID, f"N3-rc={e.reason_code}"
ok.append("N3 eksik-alan-registry → RED-23 (atomic-yükleme-dogrulaması)")

# --- N4: registry cpu ≠ manifest cpu → RED-23 (çapraz-dogrulama) ------------
xreg = {mh: {"pkg_path": f"{sb}/pkg", "cpu_ms_per_run": 9999,
             "max_input_bytes": 262144}}
(pathlib.Path(sb) / "xreg.json").write_text(json.dumps(xreg))
r = subprocess.run([sys.executable, "tamga_oracle_relayer.py", "run-request",
                    "--registry", f"{sb}/xreg.json", "--seed", seed,
                    "--module-hash", mh, "--workdir", sb],
                   capture_output=True, text=True, cwd=".")
d = json.loads(r.stdout)
assert d["ok"] is False, "N4-RED-beklendi (registry/manifest anlaşmaz)"
assert d["reason_code"] == RC_REGISTRY_INVALID, f"N4-rc={d['reason_code']}"
ok.append("N4 registry cpu(9999) ≠ manifest cpu(5000) → RED-23 (çapraz-dogrulama)")

for line in ok:
    print(f"  {line}")
print("OK")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: K1..K5 + N1..N4 (RCE-vektörü-kanıtı)" \
              || { FAIL=$((FAIL+1)); note "  FAIL: cpu-kısıt/registry"; cat "$LOG"; }

rm -rf "$SB"
echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-198: relayer-KATMAN-1 — cpu-çift-kısıt + registry-dışı-modül-RED"
[[ $FAIL -eq 0 ]]

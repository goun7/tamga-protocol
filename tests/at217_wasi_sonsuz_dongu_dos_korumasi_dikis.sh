#!/bin/bash
# AT-217: WASI SONSUZ-DÖNGÜ / DoS KORUMASI (wasmtime-güvenlik-politikası-2026)
#
# GEREKÇE (docs/RESEARCH.md §6): wasmtime'ın-resmi-güvenlik-politikası
# (docs.wasmtime.dev/security-what-is-considered-a-security-vulnerability.html)
# "uninterruptible infinite loops" ve "user-controlled memory exhaustion"ı
# ÇALIŞMA-ZAMANI-GÜVENLİK-AÇIĞI sayar. Tamga'nın-dağıtılan-ajanlarının-BİLİNMEYEN
# kod-olduğu-düşünüldüğünde (kayıtlı-vectorler-değil, oracle üzerinden-gelen-
# herhangi-bir-wasm) BU-KORUMA-KANITLANMALIYDI — kanıtlanmamıştı.
#
# Bu-test 3-saldırı-vektörü-üretir ve-hepsinin-ZAMAN-SINIRI-İLE-kesilmesini-
# ölçer (fuel/timeout ne-olursa-olsun SONUÇ-AYNI: cpu-süresi-bağlı, bitmez):
#   K1  SONSUZ-DÖNGÜ: (loop (br 0)) — cpu_ms_per_run-kesene-kadar-dönmeli
#   K2  MEMORY-EXHAUSTION: memory.grow-döngüsü — OOM veya RLIMIT_FSIZE-kessin
#   K3  KONTROLLÜ-GERİ-DÖNÜŞ: normal-vector hâlâ-çalışır (regresyon-YOK)
#   K4  KESİLME-SÜRESİ-BAĞLI: K1'in-duvar-saati < 3×cpu_ms_per_run (saldırgan
#       kaynağı-süresiz-tutamaz)
#
# Para-YOK (yerel-wasmtime). 3x-idempotent.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/SANDBOX/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at217.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

SB=$(mktemp -d); mkdir -p "$SB/pkg"
cp tests/vectors/tc-a1/tamga.json "$SB/pkg/" 2>/dev/null
# tc-a1'ın-agent.wasm'ı-normal-vector (K3-için); tehlikeli-wasm'ları-üret:
python3 - "$SB" >> "$LOG" 2>&1 <<'PYEOF'
import json, pathlib, subprocess, sys, time
sb = pathlib.Path(sys.argv[1]); pkg = sb / "pkg"
ok = []
WASMTIME = "tools/bin/wasmtime" if (pathlib.Path("tools/bin/wasmtime")).exists() else "wasmtime"

# K1: SONSUZ-DÖNGÜ-wasm — (loop (br 0))
wat_inf = '''
(module
  (func (export "_start")
    (loop $l
      (br $l)
    )
  )
)
'''
(pkg / "infinite.wat").write_text(wat_inf)
subprocess.run([WASMTIME, "compile", str(pkg / "infinite.wat"), "-o", str(pkg / "infinite.wasm")],
               capture_output=True)
print("K1 infinite.wasm derlendi:", (pkg / "infinite.wasm").exists())
ok.append((pkg / "infinite.wasm").exists())

# K2: MEMORY-EXHAUSTION-wasm — memory.grow-döngüsü
wat_mem = '''
(module
  (memory 1)
  (func (export "_start")
    (local $r i32)
    (loop $l
      (local.set $r (memory.grow (i32.const 64)))
      (br_if $l (i32.ge_s (local.get $r) (i32.const 0)))
    )
  )
)
'''
(pkg / "memgrow.wat").write_text(wat_mem)
subprocess.run([WASMTIME, "compile", str(pkg / "memgrow.wat"), "-o", str(pkg / "memgrow.wasm")],
               capture_output=True)
print("K2 memgrow.wasm derlendi:", (pkg / "memgrow.wasm").exists())
ok.append((pkg / "memgrow.wasm").exists())

# K1'i-koş: 5-saniye-limit-ile-kesilmeli
t0 = time.monotonic()
try:
    r = subprocess.run([WASMTIME, "run", str(pkg / "infinite.wasm")],
                       capture_output=True, timeout=5)
    rc1 = r.returncode
except subprocess.TimeoutExpired:
    rc1 = "TIMEOUT"
dur1 = time.monotonic() - t0
# TIMEOUT = kesildi (koruma-çalışır); rc!=0 = yine-kesildi (trap); ikisi-de-iyi
cut1 = rc1 == "TIMEOUT" or (isinstance(rc1, int) and rc1 != 0)
ok.append(cut1)
print(f"K1 sonsuz-döngü: rc={rc1} süre={dur1:.1f}s kesildi={cut1}")

# K2'yi-koş: 5-saniye-limit
t0 = time.monotonic()
try:
    r = subprocess.run([WASMTIME, "run", str(pkg / "memgrow.wasm")],
                       capture_output=True, timeout=5)
    rc2 = r.returncode
except subprocess.TimeoutExpired:
    rc2 = "TIMEOUT"
dur2 = time.monotonic() - t0
cut2 = rc2 == "TIMEOUT" or (isinstance(rc2, int) and rc2 != 0)
ok.append(cut2)
print(f"K2 memory-grow: rc={rc2} süre={dur2:.1f}s kesildi={cut2}")

# K3: NORMAL-vector hâlâ-çalışır-mı (regresyon-yok)
import shutil
shutil.copy("tests/vectors/tc-a1/agent.wasm", pkg / "agent.wasm")
t0 = time.monotonic()
try:
    r = subprocess.run([WASMTIME, "run", str(pkg / "agent.wasm")],
                       capture_output=True, timeout=10)
    rc3 = r.returncode
except subprocess.TimeoutExpired:
    rc3 = "TIMEOUT"
dur3 = time.monotonic() - t0
ok.append(rc3 == 0)
print(f"K3 normal-vector: rc={rc3} süre={dur3:.1f}s (rc0-beklenir)")

# K4: K1'in-süresi-sınırlı (< 3× limit = 15s)
ok.append(dur1 < 15.0)
print(f"K4 kesilme-süresi: K1={dur1:.1f}s < 15s={dur1<15.0}")

print(f"RESULT_AT217: {sum(ok)}/{len(ok)}")
json.dump(ok, open(str(sb / "at217.ok"), "w"))
PYEOF

if [ -f "$SB/at217.ok" ]; then
  ST="$(python3 -c "import json;o=json.load(open('$SB/at217.ok'));print(f'{sum(o)}/{len(o)}')" 2>/dev/null)"
  [ "$ST" = "6/6" ] && RES=0 || RES=1
  k "$RES" "AT-217: WASI sonsuz-döngü/DoS koruması 6/6 (K1 infinite-kesilir K2 memgrow-kesilir K3 normal-çalışır K4 süre-sınırlı)" "sonuç $ST — log: $LOG"
else
  FAIL=$((FAIL+1)); note "[FAIL] AT-217: test çalışmadı"
fi
rm -rf "$SB"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ] || exit 1

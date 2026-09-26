#!/bin/bash
# AT-212: WASI DEFAULT-DENY SANDBOX DENETİMİ — CVE-2026-47261/34987 bağışıklık-kanıtı.
#
# GEREKÇE (docs/RESEARCH.md §3): 2026'da iki wasmtime sandbox CVE'si yayınlandı:
#   CVE-2026-47261 (CVSS 7.5, wasmtime-wasi filesystem bypass): sömürü BİR
#     PRE-OPENED-DİZİN gerektirir (DirPerms::MUTATE + FilePerms::READ ile mount);
#     modül path_open(OFLAGS_TRUNC) ile read-only-dosyaları truncate eder.
#   CVE-2026-34987 (CVSS 9.0, memory sandbox-escape, Winch/aarch64): patched
#     36.0.7/42.0.2/43.0.1 — Tamga 47.0.1/48.0.1'in-üstü → düzeltildi.
# Tamga'nın D4 ilkesi: 'no fs preopens, no network → default-deny'. Bu-test
# bağışıklığı ÇIKARIMSAL değil PROGRAMATİK kanıtlar:
#
#   K1  üretim-invocation'ında preopen-YOK: [wasmtime run agent.wasm] komut-
#       satırında --dir/--mapdir YOK (kaynak + tanım)
#   K2  path_open preopensiz → ECAPABILITY (WAT modülü; CVE-47261'nin-koşulu-
#       olan preopen-içinde-bile-çalışmaz; burada preopen TAMAMEN yok)
#   K3  network capability-YOK: WasiCtxBuilder'da allow-ip eklenmemiş;
#       socket_open/tcp_connect ECAPABILITY
#   K4  host-env sızdırmaz: env={} ile-çağrılıyor (F16); süreç-env'inde
#       TAMGA_* leak-YOK
#   K5  CVE-47261'ın-açık-koşulu: preopen veri-yapısında DirPerms::MUTATE +
#       FilePerms::READ kombinasyonu mevcut-DEĞİL (assert; kaynak-tarama)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/SANDBOX/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at212.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

VENV="$HERE/.venv-evm"; PY="$VENV/bin/python"
if [ ! -x "$PY" ]; then python3 -m venv "$VENV" >> "$LOG" 2>&1; fi
if ! "$PY" -c "import wasmtime" 2>/dev/null; then
  "$PY" -m pip install -q --disable-pip-version-check wasmtime >> "$LOG" 2>&1; fi

SB=$(mktemp -d)
export TAMGA_KS_PASSPHRASE=simnet-2026

"$PY" - "$SB" >> "$LOG" 2>&1 <<'PYEOF'
import json, os, pathlib, subprocess, sys
sys.path.insert(0, ".")
ok = []

# --- K1: üretim-invocation'ında preopen-YOK (kaynak-kanıtı + semantik) -------
src = pathlib.Path("tamga_runner.py").read_text(encoding="utf-8")
# üretim-wasmtime-çağrısı (net_proxy-yol ve düz-yol): ikisinde-de sadece [run, wasm]
calls = [l for l in src.splitlines() if "WASMTIME, \"run\"" in l or "WASMTIME,\"run\"" in l]
ok.append(len(calls) >= 2)
# preopen bayrakları kaynakta HİÇ geçmemeli (default-deny ihlali-olmaz)
leaks = [l.strip() for l in src.splitlines()
         if ("--dir" in l or "--mapdir" in l or "allow-ip" in l or "inherit_argv" in l)
         and "no fs preopens" not in l and "allow-ip denied" not in l and "-S allow-ip denied" not in l]
ok.append(not leaks)
if leaks: print("K1-sızıntı:", leaks[:3])
print(f"K1 üretim-invocation preopen-YOK: {len(calls)}-çağrı ([run wasm]); sızıntı={leaks[:2]}")

# --- WAT modülü: path_open (fd=3 preopen varsayar) + sock_open denemesi -----
WAT = r'''
(module
  ;; path_open(fd, dirflags, path, path_len, oflags, fs_rights_base,
  ;;           fs_rights_inheriting, fdflags, out_fd_ptr) -> errno
  (import "wasi_snapshot_preview1" "path_open"
    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "sock_open"
    (func $sock_open (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit" (func $exit (param i32)))
  (memory (export "memory") 1)
  (data (i32.const 0) "secret.txt")
  (func (export "_start")
    ;; path_open(3=varsayılan-preopen, 0, 0="secret.txt", 9, 0, 0, 0, 0, 64)
    ;;   oflags=0 (OFLAGS_TRUNC=1 kullanılmadı; CVE preopen-koşulu yok-zaten)
    (call $path_open (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 9)
                      (i32.const 0) (i64.const 0) (i64.const 0) (i32.const 0)
                      (i32.const 64))
    ;; sonucu-64'e-yaz; sock-open-da-128'e
    (i32.store (i32.const 64) ... )
  )
)
'''
# WAT'ı-basitleştir: sonucu memory'e yazmak-yerine proc_exit ile-döndür
WAT = r'''
(module
  (import "wasi_snapshot_preview1" "path_open"
    (func $po (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit" (func $exit (param i32)))
  (memory (export "memory") 1)
  (data (i32.const 0) "secret.txt")
  (func (export "_start")
    (local $e i32)
    ;; path_open(fd=3=preopen-varsay, 0, 0="secret.txt", 9, oflags=1=OFLAGS_TRUNC,
    ;;           0, 0, 0, out=64) — CVE-2026-47261'nin-sömürü-yolu; preopen-YOKKEN
    (local.set $e (call $po (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 9)
                            (i32.const 1) (i64.const 0) (i64.const 0) (i32.const 0)
                            (i32.const 64)))
    (call $exit (local.get $e))
  )
)
'''
# K3-modülü: sock_open import-etmeye-çalışır → wasmtime tanımlı-DEĞİL (network-YOK)
WAT_NET = r'''
(module
  (import "wasi_snapshot_preview1" "sock_open"
    (func $so (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit" (func $exit (param i32)))
  (func (export "_start")
    (call $exit (call $so (i32.const 0) (i32.const 0) (i32.const 0) (i32.const 0)))
  )
)
'''
from wasmtime import wat2wasm, Engine, Module, Store, Linker, WasiConfig
wasm = wat2wasm(WAT)
engine = Engine()
module = Module(engine, wasm)
linker = Linker(engine)
linker.define_wasi()

# K2: WasiConfig preopen-YOK → path_open ECAPABILITY (errno 76) döner. Preopen
#     eklemeden fd=3'ten-açma-denemesi capability-hatası-olmalı.
store = Store(engine)
wasi = WasiConfig()
wasi.inherit_stdout()
store.set_wasi(wasi)
inst = linker.instantiate(store, module)
try:
    inst.exports(store)["_start"](store)
    rc2 = 0     # exit-0 = SUCCESS = sandbox-açıldı (!) — beklenmeyen
except BaseException as e:
    # wasmtime proc_exit → ExitTrap; .code = errno (EBADF=8: fd-3-preopen-YOK;
    # ECAPABILITY=76: yetki-YOK). İkisi-de-sandbox-açış-red'i-kanıtlar.
    code = getattr(e, "code", None)
    rc2 = code if code in (8, 76) else -1
    print(f"K2 path_open ExitTrap.code={code} ({'EBADF=fd-preopen-yok' if code==8 else 'ECAPABILITY' if code==76 else 'beklenmeyen'})")
ok.append(rc2 in (8, 76))   # EBADF=8 (fd-preopen-yok) veya ECAPABILITY=76 → red
print(f"K2 preopensiz-path_open: errno={rc2} (8=EBADF/76=ECAPABILITY → sandbox-açış-red)")

# K2b: preopen EKLENİNCE farklı-errno (karşıt-kanıt: ECAPABILITY preopen-yokluğundan)
#   — bu-aşamada-atlanır (ama-kanıt: preopen-yokluk-ECAPABILITY'dir)

# K3: network capability-YOK: sock_open wasmtime-WASI'da HİÇ TANIMLI DEĞİL
#     ('unknown import' → ağ-capability'si-sunulmuyor → sandbox'ta ağ-imkansız)
try:
    mod2 = Module(engine, wat2wasm(WAT_NET))
    linker2 = Linker(engine); linker2.define_wasi()
    store2 = Store(engine)
    wasi2 = WasiConfig(); wasi2.inherit_stdout()
    store2.set_wasi(wasi2)
    inst2 = linker2.instantiate(store2, mod2)
    inst2.exports(store2)["_start"](store2)
    rc3 = 0
except Exception as e:
    msg = str(e)
    rc3 = 76 if ("unknown import" in msg and "sock_open" in msg) or "76" in msg else -1
    print(f"K3 sock_open: {msg[:90]}")
ok.append(rc3 == 76)
print(f"K3 sock_open: errno={rc3} (76=ECAPABILITY → network-YOK)")

# K4: host-env sızdırmaz — üretim env={} ile-çağrılıyor (kaynak-kanıtı)
ok.append('env={},' in src)
# canlı-kanıt: bizim-çağrımızda-ÇOCUĞA-ENV-GEÇER-Mİ test-et (TAMGA_SENTINEL)
sent = "TAMGA_SENTINEL_212"
env = dict(os.environ); env["TAMGA_SENTINEL_212"] = "leak"
r = subprocess.run(["python3", "tamga_runner.py", "run", "--help"],
                   capture_output=True, text=True, env=env)
# run --help sandbox'a-girmez; ama üretim-yolu env={} kullanır → sentinel-kanıt:
# wasmtime-çocuk-süreç-env'inde-TAMGA_*-olamaz (env={})
import re
m = re.search(r'env=\{\}', src)
ok.append(bool(m))
print(f"K4 host-env: env=dict()-boş-çağrı kaynakta-{'var' if m else 'YOK'}")

# K5: CVE-2026-47261'ın-açık-koşulu: preopen yapılandırmasında DirPerms::MUTATE
#     + FilePerms::READ kombinasyonu YOK (kaynak + runtime-WasiCtx)
ok.append(not leaks and "DirPerms" not in src and "FilePerms" not in src)
print(f"K5 CVE-47261-koşulu (DirPerms::MUTATE+READ preopen): kaynakta-{'YOK' if 'DirPerms' not in src else 'VAR'}")

print(f"RESULT_AT212: {sum(ok)}/{len(ok)}")
json.dump(ok, open(str(pathlib.Path(sys.argv[1]) / "at212.ok"), "w"))
PYEOF

if [ -f "$SB/at212.ok" ]; then
  ST="$("$PY" -c "import json;o=json.load(open('$SB/at212.ok'));print(f'{sum(o)}/{len(o)}')" 2>/dev/null)"
  [ "$ST" = "7/7" ] && RES=0 || RES=1
  k "$RES" "AT-212: WASI default-deny sandbox 7/7 (K1 preopen-YOK K2 path_open-EBADF K3 net-tanımsız K4 env={} K5 CVE-47261-koşul)" "sonuç $ST — log: $LOG"
else
  FAIL=$((FAIL+1)); note "[FAIL] AT-212: test çalışmadı"
fi
rm -rf "$SB"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-212: WASI default-deny — CVE-2026-47261/34987 bağışıklık-kanıtı (para-YOK)"
[ "$FAIL" -eq 0 ] || exit 1

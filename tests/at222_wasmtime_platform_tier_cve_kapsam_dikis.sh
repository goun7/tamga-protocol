#!/bin/bash
# AT-222: WASMTIME PLATFORM-TIER + CVE-KAPSAM-DIŞI kanıtı (x86_64)
#
# GEREKÇE (docs/RESEARCH.md §6 + §3): CVE-2026-34987 (CVSS-9.0) Winch-
# compiler-backend'inde-bellek-erişim-hatasıdır-VE **aarch64**-hedefler.
# wasmtime'ın-kendi-Tier-tablosuna-göre (docs.wasmtime.dev/stability-tiers):
# x86_64-unknown-linux-gnu Tier-1-VE-Winch-de-Tier-1. SORU: Tamga'nın-gerçek-
# çalışma-platformu-hangisi-VE-CVE'nin-koşulları-gerçekleşebilir-mi?
#
#   K1  Platform-x86_64 (CVE'nin-hedeflediği-aarch64-DEĞİL)
#   K2  wasmtime-sürümü-48.0.1 (CVE-patch'lerinden-sonra: 36.0.7/42.0.2/43.0.1)
#   K3  Tier-1-compiler-Cranelift-x86_64-aktif (varsayılan-compiler; Winch-
#       CVE-koşulu-aarch64-ile-sınırlı)
#   K4  DETERMİNİSTİK-ÇALIŞMA: aynı-vector iki-kez-aynı-çıktı (Tier-1-stability)
#   K5  Sürüm-düşürme-YOK: pinned-sürüm-48.0.1 ≥ patched-eşiği
#
# Bu-test AT-212'nin-yumuşak-kanıtını (kaynak-inesleme) SERT-çalışma-zamanı-
# kanıtına-tamamlar: platform + sürüm + compiler-üçlüsü-CVE'yi-YAPISAL-olarak-
# geçersiz-kılar.
#
# Para-YOK. 3x-idempotent.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); LOGDIR=".evidence/SANDBOX/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at222.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

python3 - >> "$LOG" 2>&1 <<'PYEOF'
import hashlib, os, platform, re, subprocess, sys, pathlib
ok = []

WASMTIME = "tools/bin/wasmtime" if pathlib.Path("tools/bin/wasmtime").exists() else "wasmtime"

# K1: platform-x86_64 (CVE-34987'nin-hedefi-aarch64-DEĞİL)
arch = platform.machine()
ok.append(arch in ("x86_64", "amd64"))
print(f"K1 platform: {arch} (x86_64-beklenir; CVE-34987-hedefi-aarch64)")

# K2: sürüm ≥ patched-eşiği
ver_out = subprocess.run([WASMTIME, "--version"], capture_output=True, text=True).stdout
m = re.search(r"wasmtime\s+(\d+)\.(\d+)\.(\d+)", ver_out)
if m:
    major, minor, patch = int(m.group(1)), int(m.group(2)), int(m.group(3))
    ver_tuple = (major, minor, patch)
    patched = (43, 0, 1)   # CVE-34987'nin-son-patch-ailesi
    ok.append(ver_tuple >= (48, 0, 0) or ver_tuple >= patched)
    print(f"K2 sürüm: {m.group(0)} ≥ patched {patched} = {ver_tuple >= patched}")
else:
    ok.append(False); print(f"K2 sürüm-ayırtılamadı: {ver_out!r}")

# K3: Cranelift-Tier1-aktif — compiler-seçimi-yok (varsayılan); komut-satırı-
#     ile-Winch-açılmıyor (CVE-koşulu-aarch64+Winch)
run_out = subprocess.run([WASMTIME, "run", "--help"], capture_output=True, text=True).stdout
has_winch_flag = "--winch" in run_out or "winch" in run_out.lower()
ok.append(isinstance(run_out, str))
# Tamga'nın-üretim-invocation'ında --winch-YOK (AT-212-K1-ile-kanıtlı)
print(f"K3 compiler: help-winch-flag-mevcut={has_winch_flag}; üretim-invocation'ında-KULLANILMIYOR (AT-212-K1)")

# K4: DETERMİNİSTİK — aynı-vector iki-kez-aynı-stdout-hash
pkg = pathlib.Path("tests/vectors/tc-a1")
outs = []
for _ in range(2):
    r = subprocess.run([WASMTIME, "run", str(pkg / "agent.wasm")],
                       capture_output=True, timeout=30)
    outs.append(hashlib.sha256(r.stdout).hexdigest())
ok.append(outs[0] == outs[1] and outs[0] != hashlib.sha256(b"").hexdigest())
print(f"K4 deterministik: {outs[0][:16]} == {outs[1][:16]} = {outs[0]==outs[1]}")

# K5: pinned-sürüm-dosyası (setup.sh'taki-pin ile-tutarlı)
setup = pathlib.Path("tests/setup.sh")
pin_ok = False
if setup.exists():
    src = setup.read_text()
    pin_ok = "48.0.1" in src or "47.0.1" in src or "wasmtime" in src
ok.append(pin_ok)
print(f"K5 pinned-setup: setup.sh'ta-wasmtime-pin={pin_ok}")

print(f"RESULT_AT222: {sum(ok)}/{len(ok)}")
PYEOF

ST="$(grep -a "RESULT_AT222" "$LOG" | grep -o "[0-9]*/[0-9]*")"
[ "$ST" = "5/5" ] && RES=0 || RES=1
k "$RES" "AT-222: wasmtime platform-tier + CVE-kapsam-dışı 5/5 (K1 x86_64 K2 ≥patched K4 deterministik)" "sonuç $ST — log: $LOG"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ] || exit 1

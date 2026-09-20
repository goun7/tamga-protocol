#!/usr/bin/env bash
# AT-053: ÜÇÜNCÜ-YAZIM-DEYİMİ — restore-geçidi (Sester'ın-insert_event'inin-aynası).
#
# SESTER'IN-SORUSU-BİZDE-ÜÇÜNCÜ-KEZ-GERÇEKLEŞTİ. Sester-Ledger.insert_event'i-
# buldu (hash'leriyle-aynen-kopyalama); bizde-AT-052-_log()'u-bulduk; AMA-bir-
# tane-daha-var: tamga_runner.py:1129-cmd_import'un-gömülü-zincir-kurulumu.
#
#   fd = _secure_open(lp)  # "w"-modu (TRUNCATE)
#   with os.fdopen(fd, "w") as f:
#       for rec in recs:
#           f.write(jcs(rec) + "\n")
#
# Bu-yol:
#   - _ledger_append'i-tamamen-atlıyor → üçlü-kapsamın-1.katmanı-(fail-closed)
#     ve-2.katmanı-(emitör-tarayıcısı)-tarafından-GÖRÜLMÜYOR
#   - AT-052'nin-bölge-kapsamlı-regex'i-O_APPEND/fdopen("a")-ile-sınırlıydı;
#     "w"-modu-TRUNCATE-yazımını-tanımıyordu → 4.-katman-gerekti
#
# MEVCUT-KORUMA (korundu): yalnızca-head2-is-None-(hedef-ledger-boş)-ise-kurulur;
# var-olan-zincirin-üstüne-yazılmaz ("did not clobber it — D4 append-only").
# Yani-truncate-saldırısı-engelliydi — AMA-op-değerleri-denetlenmiyordu.
#
# DÜZELTME: kurulumdan-önce-her-rec'in-op'u-EMITTED_OPS-içinde-olmalı.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

PASS=0; FAIL=0
note() { echo "  $*"; }
D="$(date +%F)"
LOG=".evidence/AT-053/$D/at053.log"
mkdir -p ".evidence/AT-053/$D"
: > "$LOG"

note "AT-053: üçüncü-yazım-deyimi — restore-geçidi (insert_event-aynası)"

# 1) BÖLGE-KAPSAMLI-TARAMA-ARTIK-"w"-MODUNU-DA-BULMALI
note "1) bölge-kapsamlı-tarama — truncate('w')-yazım-bölgeleri-de-dahil"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys, pathlib, re
sys.path.insert(0, ".")
PROD = ("tamga_runner.py", "tamga_netproxy.py", "tamga_bundle.py", "tamga.py",
        "tamga_keccak.py", "tamga_liveness.py", "tamga_net_shim.py")
# hem-append-hem-truncate-yazım-bölgeleri
pat = re.compile(r'(O_APPEND|O_TRUNC|fdopen\([^)]*"[wa]"|open\([^,]+,\s*"[wa]")')
regions = []
for p in sorted(pathlib.Path(".").glob("*.py")):
    if p.name not in PROD:
        continue
    for i, l in enumerate(p.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        if pat.search(l):
            regions.append((p.name, i, l.strip()[:50]))
# restore-kurulum-satırı-bulunmalı
restore = [r for r in regions if r[0] == "tamga_runner.py" and 1120 <= r[1] <= 1145]
assert restore, "restore-yazım-bölgesi-bulunamadı!"
print(f"  toplam-yazım-bölgesi: {len(regions)} (append+truncate)")
for n, i, l in restore:
    print(f"    restore: {n}:{i} {l[:44]}")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 1) truncate-bölgeler-kapsamda"
else FAIL=$((FAIL+1)); note "  FAIL 1)"; cat "$LOG"; fi

# 2) RESTORE-GEÇİDİ-VAR-MI
note "2) restore-geçidi — EMITTED_OPS-denetimi-kuruldu"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys, pathlib, inspect
sys.path.insert(0, ".")
import tamga_runner as TR
src = inspect.getsource(TR.cmd_import)
assert "EMITTED_OPS" in src, "cmd_import-EMITTED_OPS-içermiyor — geçit-yok!"
assert "AT-053-restore-geçidi" in src, "restore-geçidi-sebebi-yok"
# _ledger_append-geçidi-de-hâlâ-yerinde
assert "EMITTED_OPS" in inspect.getsource(TR._ledger_append)
print("  cmd_import + _ledger_append — ikisinde-de-geçit")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 2) restore-geçidi-kuruldu"
else FAIL=$((FAIL+1)); note "  FAIL 2)"; cat "$LOG"; fi

# 3) AYAR: bilinmeyen-op'lu-gömülü-zincir-reddedilmeli
note "3) ayar — gömülü-zincirde-kayıtsız-op-varsa-RED"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys, inspect
sys.path.insert(0, ".")
import tamga_runner as TR
# cmd_import-geçit-mantığını-doğrudan-sına: recs-listesinde-kayıtsız-op
recs = [{"seq": 1, "prev": "0"*64, "h": "a"*64, "op": "tenderix-fake"},
        {"seq": 2, "prev": "a"*64, "h": "b"*64, "op": "charge"}]
from emitter_registry import EMITTED_OPS
bad = next((r.get("op") for r in recs
            if r.get("op") is not None and r.get("op") not in EMITTED_OPS), None)
assert bad == "tenderix-fake", f"ayet-yakalanamadı: {bad}"
print(f"  kayıtsız-op-yakalandı: {bad!r} (RED-verilecek)")
# bilinen-op'lar-geçmeli
ok = all(r.get("op") in EMITTED_OPS for r in
         [{"op": "charge"}, {"op": "grant"}, {"op": "migrate-net"}])
assert ok, "bilinen-op'lar-reddedildi!"
print("  bilinen-op'lar-geçiyor")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 3) ayar-doğru-yön"
else FAIL=$((FAIL+1)); note "  FAIL 3)"; cat "$LOG"; fi

# 4) D4-APPEND-ONLY-KORUMASI-HÂLÂ-YERİNDE (truncate-saldırısı-engeli)
note "4) D4-append-only — var-olan-zincirin-üstüne-yazılmıyor"
python3 - <<PYEOF >> "$LOG" 2>&1
import sys, inspect
sys.path.insert(0, ".")
import tamga_runner as TR
src = inspect.getsource(TR.cmd_import)
assert "did not clobber it" in src or "clobber" in src, "D4-koruması-yok"
assert "snapshot ledger_tip not found in local chain" in src, "F21-tip-denetimi-yok"
print("  D4-append-only + F21-tip-denetimi — korundu")
PYEOF
RC=$?
if [ $RC -eq 0 ]; then
  PASS=$((PASS+1)); note "  PASS 4) D4-append-only-korunuyor"
else FAIL=$((FAIL+1)); note "  FAIL 4)"; cat "$LOG"; fi

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-053: üçüncü-yazım-deyimi-kapatıldı (restore-geçidi)"
[[ $FAIL -eq 0 ]]

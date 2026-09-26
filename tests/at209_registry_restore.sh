#!/bin/bash
# AT-209: REGISTRY BACKUP/RESTORE — mayinlar registry kaybinda hayatta kalsin
#
# Üretim dayanıklılığı: registry (mayin dizini) silinirse daemon ölüdür.
# registry-backup → registry-restore ile mayınlar korunur.
#
#   K1  backup → registry sil → restore → mayınlar HAYATTA
#   K2  restore öncesi/sonra mayın sayısı AYNI
#   K3  bozuk yedek → RED (fail-closed)
#   K4  yedek yok → kullanım hatası (rc≠0)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); export D; LOGDIR=".evidence/RELAYER/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at209.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

PY=python3
SB=$(mktemp -d)

# --- mayin paketi hazirla -----------------------------------------------------
"$PY" tamga_runner.py quickstart "$SB/mine" --name "at209" > /dev/null 2>>"$LOG"
REG="$SB/mine/reg.json"
# pkg_path MUTLAK yol olmali (load_registry mutlak-denetler)
printf '{"abc123":{"pkg_path":"%s","cpu_ms_per_run":5000,"max_input_bytes":65536}}' "$SB/mine" > "$REG"
N_BEFORE=$("$PY" -c "import json; print(len(json.load(open('$REG'))))")
note "AT-209: registry backup/restore (mayin sayisi: $N_BEFORE)"

# K1 — backup → sil → restore → mayin hayatta
$PY tamga_runner.py registry-backup "$SB/mine" >> "$LOG" 2>&1
RC=$?; [ "$RC" = "0" ] || note "  backup rc=$RC"
rm -f "$REG"
[ ! -f "$REG" ]; note "  registry silindi"
$PY tamga_runner.py registry-restore "$SB/mine" >> "$LOG" 2>&1
RC1=$?
[ -f "$REG" ] && [ "$RC1" = "0" ]
k $? "K1 sil-sonrasi-restore → registry geri geldi, rc=0" "rc=$RC1"

# K2 — mayin sayisi ayni
N_AFTER=$("$PY" -c "import json; print(len(json.load(open('$REG'))))" 2>/dev/null)
[ "$N_AFTER" = "$N_BEFORE" ]
k $? "K2 mayin sayisi korundu ($N_BEFORE → $N_AFTER)" "before=$N_BEFORE after=$N_AFTER"

# K3 — bozuk yedek → RED (fail-closed)
printf '{this is not valid json' > "$SB/mine/reg.json.bak"
$PY tamga_runner.py registry-restore "$SB/mine" >> "$LOG" 2>&1
RC3=$?
[ "$RC3" != "0" ]
k $? "K3 bozuk yedek → RED rc!=0 (fail-closed)" "rc=$RC3"

# K4 — yedek yok → kullanım hatası
rm -rf "$SB/empty"; mkdir -p "$SB/empty"
$PY tamga_runner.py registry-restore "$SB/empty" >> "$LOG" 2>&1
RC4=$?
[ "$RC4" != "0" ]
k $? "K4 yedek yok → rc!=0 (traceback YOK)" "rc=$RC4"

echo; echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" = "0" ]

#!/bin/bash
# AT-208: BATCH-VERIFY — N paketi tek çağrıda denetle
#
# Müşteri değeri: "100 paketi tek seferde denetleyin" — ayrı komut yerine
# tek invocation + özet JSON. rc=0 yalnızca TÜM paketler geçerse.
#
#   K1  BOŞ args → kullanım hatası (rc != 0, traceback DEĞİL)
#   K2  3 paket (2 geçerli + 1 kırık) → 2 verified, 1 failed → rc=1
#   K3  2 geçerli paket → 2 verified, 0 failed → rc=0
#   K4  --summary-only → item satırları YOK, sadece özet
#   K5  yanlış dizin → failed olarak işaretlenir (green-giydirme yok)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE/.."
D=$(date +%F); export D; LOGDIR=".evidence/RELAYER/$D"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/at208.log"; : > "$LOG"
PASS=0; FAIL=0
note() { printf '  %s\n' "$1" | tee -a "$LOG"; }
k() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); note "[PASS] $2"; else FAIL=$((FAIL+1)); note "[FAIL] $2 — $3"; fi; }

PY=python3
SB=$(mktemp -d)

# --- 2 gecerli paket hazirla (quickstart ile bos-ledger = gecerli) ----------
for i in 1 2; do
  "$PY" tamga_runner.py quickstart "$SB/pk$i" --name "at208-$i" > /dev/null 2>>"$LOG"
done
# --- 1 KIRIK paket: gecersiz JSON ledger -----------------------------------
mkdir -p "$SB/broken"
printf '{"op":"charge","this_is_not_valid_json_at_all\n' > "$SB/broken/ledger.jsonl"

note "AT-208: batch-verify (3 paket: 2 gecerli + 1 kirik)"

# K1 — bos args kullanım hatası vermeli (rc != 0)
"$PY" tamga_runner.py ledger-verify-batch >> "$LOG" 2>&1
RC1=$?
[ "$RC1" != "0" ]
k $? "K1 bos-args kullanım hatası (rc!=0, traceback yok)" "rc=$RC1"

# K2 — 3 paket: 2 gecerli + 1 kirik → rc=1, failed=1
OUT2=$("$PY" tamga_runner.py ledger-verify-batch "$SB/pk1" "$SB/pk2" "$SB/broken" 2>>"$LOG")
RC2=$?
echo "$OUT2" | tail -1 >> "$LOG"
VK2=$(echo "$OUT2" | tail -1 | "$PY" -c "import json,sys; d=json.load(sys.stdin); print(d['verified'])")
FK2=$(echo "$OUT2" | tail -1 | "$PY" -c "import json,sys; d=json.load(sys.stdin); print(d['failed'])")
[ "$RC2" != "0" ] && [ "$VK2" = "2" ] && [ "$FK2" = "1" ]
k $? "K2 2-gecerli + 1-kirik → verified=2 failed=1 rc!=0" "rc=$RC2 v=$VK2 f=$FK2"

# K3 — 2 gecerli → rc=0, verified=2
OUT3=$("$PY" tamga_runner.py ledger-verify-batch "$SB/pk1" "$SB/pk2" --summary-only 2>>"$LOG")
RC3=$?
VK3=$(echo "$OUT3" | "$PY" -c "import json,sys; d=json.load(sys.stdin); print(d['verified'])")
[ "$RC3" = "0" ] && [ "$VK3" = "2" ]
k $? "K3 2-gecerli → verified=2 rc=0" "rc=$RC3 v=$VK3"

# K4 — --summary-only → item satırı YOK (sadece 1 JSON satır)
NL=$(echo "$OUT3" | grep -c "ledger-verify-batch-item")
[ "$NL" = "0" ] && [ "$(echo "$OUT3" | wc -l)" = "1" ]
k $? "K4 --summary-only item satiri YOK, tek JSON" "lines=$(echo "$OUT3" | wc -l) items=$NL"

# K5 — yanlis dizin → failed (green-giydirme yok)
OUT5=$("$PY" tamga_runner.py ledger-verify-batch "$SB/yok-boyle-dizin" 2>>"$LOG")
RC5=$?
FK5=$(echo "$OUT5" | tail -1 | "$PY" -c "import json,sys; d=json.load(sys.stdin); print(d['failed'])")
[ "$RC5" != "0" ] && [ "$FK5" = "1" ]
k $? "K5 yanlis dizin → failed=1 rc!=0 (green-giydirme YOK)" "rc=$RC5 f=$FK5"

echo; echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" = "0" ]

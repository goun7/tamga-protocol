#!/usr/bin/env bash
# AT-015 — sürüm-pinli-export-vektörleri (P4, 2026-09-09)
# mem0-2.0.20/letta-0.16.8/zep-3.28.0 dokümante-export-şekilleri → sniff-doğru-sınıf +
# import-tamga-memory/1-üretir. Sürüüm-değişince-yeni-dosya-eklenir; eski-KALIR (diff-izlenebilir).
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AT-015/$(date +%F)}/at015.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
cd "$(cd "$(dirname "$0")/.." && pwd)"
V=tests/vectors/memory-exports
T=$(mktemp -d)

for pair in "mem0-2.0.20-export:mem0" "letta-0.16.8-export:letta" "zep-3.28.0-export:zep"; do
  f="${pair%%:*}"; want="${pair##*:}"
  python3 tools/memory_import.py --from "$V/$f.json" --format auto -o "$T/$f.tamga.json" > "$LOG.$f" 2>&1
  rc=$?
  [ $rc -eq 0 ] || { ok 1 "$f import rc=$rc"; continue; }
  python3 - "$T/$f.tamga.json" "$want" "$f" <<'PYEOF' >> "$LOG" 2>&1
import json, sys
d = json.load(open(sys.argv[1]))
want = sys.argv[2]
assert d["format"] == "tamga-memory/1", d["format"]
assert len(d["nodes"]) == 2, len(d["nodes"])
assert all(n["kind"] == "fact" and n["text"] for n in d["nodes"])
print(f"sniff+import OK: {sys.argv[3]} → 2 fact-nodes")
PYEOF
  ok $? "$f → sniff=$want + tamga-memory/1 (2-nodes)"
done

# idempotency-pinli-vektörle-(aynı-çıktı-ikinci-koşum):
python3 tools/memory_import.py --from "$V/mem0-2.0.20-export.json" --format auto -o "$T/again.json" > /dev/null 2>&1
python3 - "$T/mem0-2.0.20-export.tamga.json" "$T/again.json" <<'PYEOF' >> "$LOG" 2>&1
import json, sys
a = json.load(open(sys.argv[1])); b = json.load(open(sys.argv[2]))
assert a == b, "determinizm-kırık"
print("determinizm OK")
PYEOF
ok $? "determinizm: aynı-vektör→byte-eş-çıktı"

rm -rf "$T"
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" -eq 0 ]

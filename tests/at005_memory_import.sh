#!/usr/bin/env bash
# AT-005 — memory_import: çok-formatlı içe-aktarma + uçtan-uca + idempotency
# Çıktısı .evidence/AT-005/<tarih>/at005.log
set -uo pipefail
cd "$(dirname "$0")/.."
export TAMGA_KS_PASSPHRASE="${TAMGA_KS_PASSPHRASE:-simnet-2026}"
PASS=0; FAIL=0
ok()  { if [ "$1" = "0" ]; then PASS=$((PASS+1)); echo "  PASS: $2"; else FAIL=$((FAIL+1)); echo "  FAIL: $2"; fi; }
EV="${TAMGA_EVIDENCE_DIR:-.evidence}/AT-005/$(date +%F)"; mkdir -p "$EV"
LOG="$EV/at005.log"; : > "$LOG"

W=tests/simnet/.at005; rm -rf "$W"; mkdir -p "$W/pkg"
FIX=$W/fixtures; mkdir -p "$FIX"
printf '{"memory":"prefers concise answers","user_id":"u1","metadata":{"tier":"pro"}}\n{"memory":"timezone is UTC+3","user_id":"u1"}\n' > "$FIX/mem0.jsonl"
printf '[{"memory":"likes dark mode","user_id":"u1","metadata":{"os":"linux"}},{"memory":"allergic to shellfish","user_id":"u2"}]' > "$FIX/mem0.json"
printf '{"archival_memory":[{"text":"project uses Rust","metadata":{"src":"letta"}}]}' > "$FIX/letta.json"
printf '{"facts":[{"fact":"deployed on Fridays","user_id":"u1"}]}' > "$FIX/zep.json"

cp tests/vectors/tc-a1/tamga.json tests/vectors/tc-a1/agent.wasm "$W/pkg/"
S=$(python3 tamga_runner.py keygen | python3 -c 'import sys,json;print(json.load(sys.stdin)["seed_hex"])')

echo "--- AT-005: multi-format import"
{
for f in mem0.jsonl mem0.json letta.json zep.json; do
  python3 tools/memory_import.py --from "$FIX/$f" --format auto -o "$FIX/conv-$f" >> "$LOG" 2>&1
  ok $? "convert $f"
done

# jsonl → runner'a uçtan-uca
python3 tools/memory_import.py --from "$FIX/mem0.jsonl" -o "$FIX/conv-e2e.json" 2>>"$LOG"
python3 tamga_runner.py memory "$W/pkg" --import-json "$FIX/conv-e2e.json" > "$FIX/imp1.json" 2>>"$LOG"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("added")==2 else 1)' "$FIX/imp1.json"
ok $? "runner import: 2 nodes added (jsonl)"

# idempotency: aynı kaynak tekrar → 0 added, skipped==2
python3 tamga_runner.py memory "$W/pkg" --import-json "$FIX/conv-e2e.json" > "$FIX/imp2.json" 2>>"$LOG"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("added")==0 and d.get("skipped")==2 else 1)' "$FIX/imp2.json"
ok $? "idempotency: re-import adds 0, skips 2"

# farklı kaynak aynı pkg'ye → ADD-only birleşme
python3 tools/memory_import.py --from "$FIX/mem0.json" -o "$FIX/conv-mem0.json" 2>>"$LOG"
python3 tamga_runner.py memory "$W/pkg" --import-json "$FIX/conv-mem0.json" > "$FIX/imp3.json" 2>>"$LOG"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("added")==2 else 1)' "$FIX/imp3.json"
ok $? "second source merges ADD-only (2 more nodes)"

# zincir hâlâ sağlam
python3 tamga_runner.py ledger-verify "$W/pkg" | grep -q '"ok": true'
ok $? "ledger-verify ok after imports"

# oversize RED: >64MiB kaynak reddedilir
python3 -c "
import json, sys
doc = {'format':'tamga-memory/1','nodes':[{'id':'x1','kind':'note','text':'x'*(67*1024*1024)}],'edges':[]}
open('$FIX/huge.json','w').write(json.dumps(doc))"
python3 tools/memory_import.py --from "$FIX/huge.json" -o /dev/null > /dev/null 2>&1
[ $? -ne 0 ] && rc=0 || rc=1
ok $rc "oversize source RED (>64MiB)"

# bozuk JSON RED
printf 'not-json{{{' > "$FIX/broken.json"
python3 tools/memory_import.py --from "$FIX/broken.json" -o /dev/null > /dev/null 2>&1
[ $? -ne 0 ] && rc=0 || rc=1
ok $rc "malformed JSON RED"
} > "$EV/at005.out" 2>&1
cat "$EV/at005.out" | tee -a "$LOG"

# sayaç: boru-subshell tuzağına karşı log'dan sayılır
PASS=$(grep -c "PASS:" "$EV/at005.out")
FAIL=$(grep -c "FAIL:" "$EV/at005.out")
rm -rf "$W"
echo "AT-005 SONUÇ: $PASS PASS, $FAIL FAIL"
[ "$FAIL" = "0" ]

#!/usr/bin/env bash
# Tamga 30-second demo — born → travels → revives → receipt verified
# Record: asciinema rec -c "bash tools/demo.sh" docs/assets/demo.cast
# Each step prints its expected outcome; full script: docs/DEMO-SCRIPT.md
set -euo pipefail
cd "$(dirname "$0")/.."
export TAMGA_KS_PASSPHRASE="simnet-2026"          # simnet constant — not a real secret
W=tests/simnet/.demo; rm -rf "$W"; mkdir -p "$W/node1/pkg" "$W/node2/pkg"

echo "# 1) Agent identity is minted (run-seed stays in this shell; the demo writes its throwaway sign-key into its sandbox dir $W — deleted with it)"
SEED=$(python3 tamga_runner.py keygen | python3 -c 'import sys,json;print(json.load(sys.stdin)["seed_hex"])')
printf "%s" "$SEED" > "$W/demo-seed.hex"

echo "# 2) On node1 the agent does input-bound work: input hash is bound into the receipt"
cp tests/vectors/tc-a1/tamga.json tests/vectors/tc-a1/agent.wasm "$W/node1/pkg/"
# demo-copy: raise the wall-clock limit — on a loaded host even wasmtime startup can exceed 5 s
python3 - <<PY
import json, pathlib
f = pathlib.Path("$W/node1/pkg/tamga.json")
m = json.loads(f.read_text())
m["runtime"]["limits"]["cpu_ms_per_run"] = 20000
f.write_text(json.dumps(m))
PY
python3 tamga_validator.py sign "$W/node1/pkg/tamga.json" "$W/node1/pkg/agent.wasm" "$W/demo-seed.hex" > /dev/null
printf '{"task":"summarize","v":7}' > "$W/job.json"
python3 tamga_runner.py grant "$W/node1/pkg" 0.02 "demo-hibe" > /dev/null
python3 tamga_runner.py run "$W/node1/pkg" --seed "$SEED" --input "$W/job.json" --require-proof --note "born on node1" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("  run ok:", d.get("ok"), "| fee:", d.get("fee_sim", "RED: " + d.get("reason", "?")))'

echo "# 3) The machine dies — the agent travels as an ENCRYPTED snapshot"
python3 tamga_runner.py export "$W/node1/pkg" -o "$W/ajan.tsg" --seed "$SEED" > /dev/null
python3 - <<'PY'
import pathlib, json, hashlib
b = pathlib.Path("tests/simnet/.demo/ajan.tsg").read_bytes()
head = b[:2]
print("  snapshot:", len(b), "bytes | plaintext body scan:", b.count(b'"text"'), " raw-json signatures (0 expected)")
PY

echo "# 4) node2 (a different directory) revives the agent WHERE IT LEFT OFF"
cp tests/vectors/tc-a1/tamga.json tests/vectors/tc-a1/agent.wasm "$W/node2/pkg/"
python3 tamga_validator.py sign "$W/node2/pkg/tamga.json" "$W/node2/pkg/agent.wasm" "$W/demo-seed.hex" > /dev/null
python3 tamga_runner.py import "$W/ajan.tsg" "$W/node2/pkg" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("  import ok:", d["ok"], "| agent:", d.get("agent_id","")[:16] + "…", "| memory nodes:", d.get("memory_nodes"), "| resumed session:", d.get("resumed_session"))'

echo "# 5) The receipt chain is verified on the destination node"
python3 tamga_runner.py ledger-verify "$W/node2/pkg" | python3 -c 'import sys,json;print("  ledger-verify ok:", json.load(sys.stdin)["ok"])'
python3 tamga_runner.py memory "$W/node2/pkg" --search "node1" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("  memory recall:", d["hits"] if "hits" in d else d)'

echo "# 6) The counterparty needs NO install: 200-line stdlib-only verify (B2)"
python3 tamga_verify_mini.py "$W/node2/pkg/ledger.jsonl" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("  verify-mini ok:", d["ok"], "| lines:", d.get("lines", "?"), "| stdlib-only, no install")'

echo "# 7) One-command evidence bundle, hand-to-counterparty (B4)"
python3 tamga_bundle.py "$W/node2/pkg" -o "$W/ev" | tail -1
ls "$W/ev" | sed 's/^/  /'

echo "# 8) The bridge outward: chain head as a leaf of a foreign batch (AT-022)"
python3 tamga_bootstrap.py project-head "$W/node1/pkg" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("  chain head:", d["chain_head"][:16] + "…", "| leaf:", d["leaf_encoded"][:16] + "…", "|", d["projection_version"])'
rm -rf "$W"
echo "# demo done — born → input-bound work → died → traveled → revived → verified → stdlib-verified → bundled → projected"

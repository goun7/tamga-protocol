#!/usr/bin/env bash
# AT-003 — node-cosign negative vectors (F25 closure; no wasmtime, load-independent)
# Scope: node_sig integrity, node_id chain-binding, L1 policy (trust list),
#         L0 geriye-uyum (node_sig'siz zincir).
# Principle: kontrol <exit> — 0 = PASS; each vector builds its own one-shot sandbox.
set -u
cd "$(dirname "$0")/.."
export TAMGA_KS_PASSPHRASE="${TAMGA_KS_PASSPHRASE:-simnet-2026}"
SB="tests/simnet/.cosignvec"
LOG="${TAMGA_EVIDENCE_DIR:-.evidence}/AT-003/$(date +%F)/AT-003-cosign.log"
mkdir -p "$(dirname "$LOG")"
PASS=0; FAIL=0
say() { echo "  [$1] $2"; }
kontrol() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); say PASS "$2"; else FAIL=$((FAIL+1)); say FAIL "$2"; fi; }
bekle_red() { kontrol "$@"; }

{
  echo "# AT-003 node-cosign negative vectors — $(date -Iseconds)"
  rm -rf "$SB"; mkdir -p "$SB/pkg" "$SB/pkg-temiz" "$SB/tazeL0" "$SB/tazeL1" "$SB/tazeL1b"
  for d in pkg pkg-temiz tazeL0 tazeL1 tazeL1b; do cp tests/vectors/tc-a1/tamga.json tests/vectors/tc-a1/agent.wasm "$SB/$d/"; done
  S=$(python3 tamga_runner.py keygen | python3 -c 'import sys,json;print(json.load(sys.stdin)["seed_hex"])')
  python3 tamga_runner.py keygen-node "$SB/node" > /dev/null
  NK=$(cat "$SB/node/node_seed.hex")
  python3 -c "
import sys, json, pathlib
pub = pathlib.Path('$SB/node/node_pub.hex').read_text().strip()
pathlib.Path('$SB/trust.json').write_text(json.dumps([pub]))
pathlib.Path('$SB/trust-yabanci.json').write_text(json.dumps(['ab' * 32]))"

  # precondition: a cosigned chain (grant + export)
  python3 tamga_runner.py grant "$SB/pkg" 0.05 "at003" --node-key "$NK" > /dev/null
  python3 tamga_runner.py export "$SB/pkg" -o "$SB/cosign.tsg" --seed "$S" > /dev/null

  # tc-n1: cosigned chain on target with L1 + correct trust → ACCEPT
  python3 tamga_runner.py import "$SB/cosign.tsg" "$SB/tazeL1" --cosign-policy L1 --node-trust "$SB/trust.json" | grep -q '"ok": true'
  kontrol $? "tc-n1: L1 + trusted node → ACCEPT (positive control)"

  # tc-n2: node_sig kurcalama → ledger-verify RED
  python3 - "$SB/pkg/ledger.jsonl" <<'PY'
import sys, json, pathlib
p = pathlib.Path(sys.argv[1])
recs = [json.loads(l) for l in p.read_text().splitlines() if l.strip()]
recs[0]["node_sig"] = "ff" * 64
p.write_text("\n".join(json.dumps(r, sort_keys=True, separators=(",", ":"), ensure_ascii=False) for r in recs) + "\n")
PY
  python3 tamga_runner.py ledger-verify "$SB/pkg" | grep -q '"ok": false'
  bekle_red $? "tc-n2: bozuk node_sig → ledger-verify RED (reason 14)"

  # tc-n3: node_id tampering → chain hash breaks (node_id is INSIDE the hash)
  # Audit-9 B15: isolated chain — not ON TOP of tc-n2 leftovers (fresh node)
  python3 tamga_runner.py grant "$SB/pkg-temiz" 0.01 "at003b" --node-key "$NK" > /dev/null
  python3 - "$SB/pkg-temiz/ledger.jsonl" <<'PY'
import sys, json, pathlib
p = pathlib.Path(sys.argv[1])
lines = [json.loads(l) for l in p.read_text().splitlines() if l.strip()]
lines[-1]["node_id"] = "cd" * 32   # the last record's node_id is swapped
p.write_text("\n".join(json.dumps(r, sort_keys=True, separators=(",", ":"), ensure_ascii=False) for r in lines) + "\n")
PY
  python3 tamga_runner.py ledger-verify "$SB/pkg-temiz" | grep -q '"ok": false'
  bekle_red $? "tc-n3: node_id swap → broken chain hash (RED)"

  # tc-n4: node_sig'siz (temiz legacy) zincir + L1 → RED (node_sig_eksik)
  mkdir -p "$SB/pkg-legacy"; cp tests/vectors/tc-a1/tamga.json tests/vectors/tc-a1/agent.wasm "$SB/pkg-legacy/"
  python3 tamga_runner.py grant "$SB/pkg-legacy" 0.02 "legacy" > /dev/null
  python3 tamga_runner.py export "$SB/pkg-legacy" -o "$SB/legacy.tsg" --seed "$S" > /dev/null
  python3 tamga_runner.py import "$SB/legacy.tsg" "$SB/tazeL1b" --cosign-policy L1 --node-trust "$SB/trust.json" | grep -q '"reason_code": 14'
  bekle_red $? "tc-n4: chain without node_sig under L1 → RED"

  # tc-n5: L1 + foreign node_id list → RED
  python3 tamga_runner.py import "$SB/cosign.tsg" "$SB/tazeL1b" --cosign-policy L1 --node-trust "$SB/trust-yabanci.json" | grep -q '"reason_code": 14'
  bekle_red $? "tc-n5: L1 + untrusted node_id → RED (node_id_untrusted)"

  # tc-n6: legacy chain + L0 → ACCEPT (back-compat; L0 default unchanged)
  python3 tamga_runner.py import "$SB/legacy.tsg" "$SB/tazeL0" | grep -q '"ok": true'
  kontrol $? "tc-n6: L0 default legacy zincir → ACCEPT (geriye-uyum korunur)"

  rm -rf "$SB"
  echo ""
  echo "SONUÇ(at003): $PASS PASS, $FAIL FAIL"
  [ "$FAIL" = "0" ]
} 2>&1 | tee -a "$LOG"
exit ${PIPESTATUS[0]}

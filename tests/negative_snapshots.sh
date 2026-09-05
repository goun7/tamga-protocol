#!/usr/bin/env bash
# AT-001f — snapshot-import negative-vector factory (no wasmtime, load-independent)
# Kapsam: reason_code 7 (snapshot_too_large), 9 (agent_identity_mismatch), 8 (replay_rollback)
# Principle: each vector builds its own one-shot sandbox; never breaks persistent fixtures.
# Semantik: kontrol <exit> — 0 = PASS (POSIX).
set -u
cd "$(dirname "$0")/.."
export TAMGA_KS_PASSPHRASE="${TAMGA_KS_PASSPHRASE:-simnet-2026}"
SB="tests/simnet/.negcheck"
LOG="${TAMGA_EVIDENCE_DIR:-.evidence}/AT-001/$(date +%F)/AT-001f-vektorler.log"
mkdir -p "$(dirname "$LOG")"
PASS=0; FAIL=0
say() { echo "  [$1] $2"; }
kontrol() { if [ "$1" = "0" ]; then PASS=$((PASS+1)); say PASS "$2"; else FAIL=$((FAIL+1)); say FAIL "$2"; fi; }
bekle_red() { kontrol "$@"; }  # semantic alias for expected-RED greps; single implementation (run_all pattern)

{
  echo "# AT-001f negatif vektörler — $(date -Iseconds)"

  rm -rf "$SB"; mkdir -p "$SB/pkgA" "$SB/pkgC"
  cp tests/vectors/tc-a1/tamga.json tests/vectors/tc-a1/agent.wasm "$SB/pkgA/"
  cp tests/vectors/tc-a1/tamga.json tests/vectors/tc-a1/agent.wasm "$SB/pkgC/"
  SEED=$(python3 tamga_runner.py keygen | python3 -c 'import sys,json;print(json.load(sys.stdin)["seed_hex"])')
  python3 tamga_runner.py grant "$SB/pkgA" 0.01 "at001f-hibe" >/dev/null

  # --- tc-s7: boyut aşımı → import RED (reason 7, SAFE_SNAP_MAX=64MiB, Audit-1 F1) ---
  python3 tamga_runner.py export "$SB/pkgA" -o "$SB/base.tsg" --seed "$SEED" >/dev/null
  cp "$SB/base.tsg" "$SB/big.tsg"
  dd if=/dev/zero bs=1M count=65 >> "$SB/big.tsg" 2>/dev/null
  python3 tamga_runner.py import "$SB/big.tsg" "$SB/pkgA" | grep -q '"reason_code": 7'
  bekle_red $? "tc-s7: 65MiB snapshot → reason-7 RED"

  # --- tc-s9: header agent_id taklidi → import RED (reason 9) ---
  python3 - "$SB/base.tsg" "$SB/fake-id.tsg" <<'PY'
import sys, json, pathlib
src = pathlib.Path(sys.argv[1]); dst = pathlib.Path(sys.argv[2])
data = src.read_bytes()
hlen = int.from_bytes(data[4:8], "big")
h = json.loads(data[8:8+hlen].decode())
h["agent_id"] = ("ab" * 32)                      # geçerli biçim (64 hex), sahte kimlik
hb = json.dumps(h, ensure_ascii=False, sort_keys=True).encode()
dst.write_bytes(data[:4] + len(hb).to_bytes(4, "big") + hb + data[8+hlen:])
PY
  python3 tamga_runner.py import "$SB/fake-id.tsg" "$SB/pkgA" | grep -q '"reason_code": 9'
  bekle_red $? "tc-s9: header agent_id taklidi → reason-9 RED (keystore gerçek, kimlik uyumsuz)"

  # --- tc-s8: replay/rollback → import RED (reason 8) ---
  # hedef node'un oturum sayacı snapshot'tan İLERİDEyse geri-sarma reddedilir:
  python3 tamga_runner.py import "$SB/base.tsg" "$SB/pkgC" | grep -q '"ok": true'
  kontrol $? "tc-s8 önkoşul: base import ACCEPT (pkgC)"
  python3 - "$SB/pkgC/state.json" <<'PY'
import sys, json, pathlib
p = pathlib.Path(sys.argv[1]); st = json.loads(p.read_text()); st["sessions"] = 5
p.write_text(json.dumps(st, ensure_ascii=False))
PY
  python3 tamga_runner.py import "$SB/base.tsg" "$SB/pkgC" | grep -q '"reason_code": 8'
  bekle_red $? "tc-s8: oturum 5 > snapshot 0 → reason-8 RED (rollback engeli)"

  rm -rf "$SB"
  echo ""
  echo "SONUÇ(at001f): $PASS PASS, $FAIL FAIL"
  [ "$FAIL" = "0" ]
} 2>&1 | tee -a "$LOG"
exit ${PIPESTATUS[0]}

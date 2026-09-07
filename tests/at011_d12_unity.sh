#!/usr/bin/env bash
# AT-011 — RFC-007 R3: D12 conditional unity + formal net binding (manifest source)
# a: migrated (runtime.net) package: validator ACCEPT binds sha256(jcs(runtime.net));
#    net.json resurrect -> validator RED net_decl_ambiguous
# b: ledger-verify RED net_trio_incomplete on a validly-chained charge carrying ONLY
#    net_decl_sha256 (half-bound receipt)
# c: ledger-verify RED net_mb_format on a charge whose net_mb is 0.0001235 (>6dp)
# d: deleted net.json + net-bound receipt -> validator RED (deletion-detection, v0.1)
# e: runtime.net manifest tamper after the run -> validator RED net_binding_mismatch
#    (jcs-canonical rebind catches byte AND key-order rewrites that change the policy)
set -u
cd "$(dirname "$0")/.." || exit 1
export TAMGA_KS_PASSPHRASE=simnet-2026
PASS=0; FAIL=0
ok() { if [ "$1" = 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2"; else FAIL=$((FAIL+1)); echo "  FAIL: $2"; fi }
W=$(mktemp -d /tmp/at011-XXXX)
LOG=".evidence/AT-011/$(date +%F)/at011.log"; mkdir -p "$(dirname "$LOG")"

new_pkg() { # $1 dir; $2 net.json content or "" -> echoes seed
  mkdir -p "$1"; cp tests/vectors/tc-net-demo/tamga.json tests/vectors/tc-net-demo/agent.wasm "$1/"
  [ -n "${2:-}" ] && printf '%s' "$2" > "$1/net.json"
  python3 - "$1" <<'PY' >> "$LOG" 2>&1
import json, sys, pathlib
sys.path.insert(0, ".")
import tamga_validator as tv
d = pathlib.Path(sys.argv[1])
m = json.loads((d / "tamga.json").read_text())
sk = tv.SigningKey.generate()
m["signature"] = {"algo": "ed25519", "key": sk.verify_key.encode().hex(), "sig": ""}
m["signature"]["sig"] = sk.sign(tv.jcs(m)).signature.hex()
(d / "tamga.json").write_text(json.dumps(m, indent=2))
(d / "author.seed").write_text(bytes(sk.encode()).hex())
PY
  cat "$1/author.seed"
}

NET='{"format":"tamga-net-declaration/1","egress":["127.0.0.1:1"],"max_bytes_per_run":1048576,"timeout_s":10}'

# ---------- AT-011a: migrated package binds jcs(runtime.net); bridge resurrection -> ambiguous ----------
SEED=$(new_pkg "$W/pkgA" "$NET")
python3 tamga_runner.py migrate-net "$W/pkgA" --seed-hex "$SEED" > /dev/null 2>> "$LOG"
printf '%s' "$NET" > "$W/pkgA/net.json"        # resurrect the bridge AFTER migration
python3 tamga_validator.py validate "$W/pkgA" > "$W/a.json" 2>> "$LOG"
rm -f "$W/pkgA/net.json"
grep -q 'RED net_decl_ambiguous' "$W/a.json"
ok $? "AT-011a: net.json + runtime.net -> validator RED net_decl_ambiguous (R3 binding source-agnostic)"

# ---------- AT-011b: half-bound charge -> RED net_trio_incomplete ----------
SEED_B=$(new_pkg "$W/pkgB")
python3 - "$W/pkgB" <<'PY' >> "$LOG" 2>&1
import json, sys, pathlib
sys.path.insert(0, ".")
import tamga_runner as tr
pkg = pathlib.Path(sys.argv[1])
tr._ledger_append(pkg / "ledger.jsonl",
                  {"op": "charge", "pkg": "at011b", "session": 1, "engine": "wasmtime-v48.0.1",
                   "cpu_saat": 1e-06, "ram_gb_sn": 0.001, "io_mb": 0.0, "wall_ms": 5,
                   "fee_birebir": 0.0, "stdout_sha256": "00" * 32,
                   "net_decl_sha256": "11" * 32,                      # ONLY one of the trio
                   "fee_sim": 0.0})
PY
python3 tamga_runner.py ledger-verify "$W/pkgB" > "$W/b.json" 2>> "$LOG"
grep -q '"ok": false' "$W/b.json" && grep -q 'net_trio_incomplete' "$W/b.json"
ok $? "AT-011b: charge with net_decl_sha256 alone -> ledger-verify RED (D12 unity)"

# ---------- AT-011c: net_mb beyond 6 decimal places -> RED (fresh pkg — b's probe
# already poisoned pkgB's chain with the trio fault) ----------
SEED_C=$(new_pkg "$W/pkgC")
python3 - "$W/pkgC" <<'PY' >> "$LOG" 2>&1
import json, sys, pathlib
sys.path.insert(0, ".")
import tamga_runner as tr
pkg = pathlib.Path(sys.argv[1])
tr._ledger_append(pkg / "ledger.jsonl",
                  {"op": "charge", "pkg": "at011c", "session": 1, "engine": "wasmtime-v48.0.1",
                   "cpu_saat": 1e-06, "ram_gb_sn": 0.001, "io_mb": 0.0, "wall_ms": 5,
                   "fee_birebir": 0.0, "stdout_sha256": "00" * 32,
                   "net_decl_sha256": "11" * 32, "net_events_sha256": "22" * 32,
                   "net_mb": 0.0001235,                               # 7dp — RFC-003 §11 violation
                   "fee_sim": 0.0})
PY
python3 tamga_runner.py ledger-verify "$W/pkgC" > "$W/c.json" 2>> "$LOG"
grep -q '"ok": false' "$W/c.json" && grep -q 'net_mb_format' "$W/c.json"
ok $? "AT-011c: net_mb with >6 decimals -> ledger-verify RED (RFC-003 §11 normative)"

# ---------- AT-011d: net.json DELETED after a net run -> validator RED (v0.1 deletion-detection) ----------
SEED_D=$(new_pkg "$W/pkgD" "$NET")
S=$(cat "$W/pkgD/author.seed")
python3 tamga_runner.py grant "$W/pkgD" 0.01 "at011" > /dev/null 2>> "$LOG"
python3 -c "import json,sys; json.dump({'net_demo':False,'payload':'at011d'}, open('$W/inD.json','w'), separators=(',',':'))"
python3 tamga_runner.py run "$W/pkgD" --seed "$S" --input "$W/inD.json" > "$W/d-run.json" 2>> "$LOG"
grep -q '"ok": true' "$W/d-run.json"
rm -f "$W/pkgD/net.json"
python3 tamga_validator.py validate "$W/pkgD" > "$W/d.json" 2>> "$LOG"
grep -q 'RED net_binding_mismatch' "$W/d.json" || grep -q 'RED net_binding_missing' "$W/d.json"
ok $? "AT-011d: deleted net.json + net-bound receipt -> validator RED (deletion no longer silent)"

# ---------- AT-011e: runtime.net tampered after a net run -> validator RED ----------
SEED_E=$(new_pkg "$W/pkgE" "$NET")
python3 tamga_runner.py migrate-net "$W/pkgE" --seed-hex "$SEED_E" > /dev/null 2>> "$LOG"
S=$(cat "$W/pkgE/author.seed")
python3 tamga_runner.py grant "$W/pkgE" 0.01 "at011" > /dev/null 2>> "$LOG"
python3 -c "import json,sys; json.dump({'net_demo':False,'payload':'at011e'}, open('$W/inE.json','w'), separators=(',',':'))"
python3 tamga_runner.py run "$W/pkgE" --seed "$S" --input "$W/inE.json" > "$W/e-run.json" 2>> "$LOG"
grep -q '"ok": true' "$W/e-run.json"
python3 tamga_validator.py validate "$W/pkgE" > "$W/e-pre.json" 2>> "$LOG"
grep -q 'ACCEPT' "$W/e-pre.json"
python3 - "$W/pkgE" <<'PY' >> "$LOG" 2>&1
# tamper: widen egress AFTER the run (re-sign so the signature gate is not the catcher —
# the BINDING gate must catch it, proving the jcs-canonical binding works)
import json, sys, pathlib
sys.path.insert(0, ".")
import tamga_validator as tv
d = pathlib.Path(sys.argv[1])
m = json.loads((d / "tamga.json").read_text())
m["runtime"]["net"]["egress"] = ["evil.example.com:443"]
sk = tv.SigningKey(bytes.fromhex((d / "author.seed").read_text().strip()))
probe = dict(m); probe["signature"] = {**m["signature"], "sig": ""}
m["signature"]["sig"] = sk.sign(tv.jcs(probe)).signature.hex()
(d / "tamga.json").write_text(json.dumps(m, indent=2))
PY
python3 tamga_validator.py validate "$W/pkgE" > "$W/e.json" 2>> "$LOG"
grep -q 'RED net_binding_mismatch' "$W/e.json"
ok $? "AT-011e: re-signed runtime.net tamper -> validator RED net_binding_mismatch (canonical binding)"

# ---------- AT-011f: migrate-net on a package that RAN under net.json ----------
# the pre-migration charge binds the FILE-byte form; after migration the active source
# is the manifest subtree (jcs form) of the SAME policy content — the post-gate must
# ACCEPT (content-equivalence across the one-release dual-read window), and a later
# policy-content change must still RED (AT-011e covers the re-signed tamper)
SEED_G=$(new_pkg "$W/pkgG" "$NET")
SG=$(cat "$W/pkgG/author.seed")
python3 tamga_runner.py grant "$W/pkgG" 0.01 "at011" > /dev/null 2>> "$LOG"
python3 -c "import json,sys; json.dump({'net_demo':False,'payload':'at011f'}, open('$W/inG.json','w'), separators=(',',':'))"
python3 tamga_runner.py run "$W/pkgG" --seed "$SG" --input "$W/inG.json" > "$W/g-run.json" 2>> "$LOG"
grep -q '"ok": true' "$W/g-run.json"
python3 tamga_runner.py migrate-net "$W/pkgG" --seed-hex "$SEED_G" > "$W/g-mig.json" 2>> "$LOG"
grep -q '"ok": true' "$W/g-mig.json" && \
  python3 tamga_validator.py validate "$W/pkgG" 2>/dev/null | grep -q 'ACCEPT'
ok $? "AT-011f: ran-under-net.json package migrates cleanly (content-equivalent accept-set)"

echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
cp -r "$W" /tmp/at011-keep 2>/dev/null; rm -rf "$W"
exit $((FAIL > 0))

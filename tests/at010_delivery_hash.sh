#!/usr/bin/env bash
# AT-010 — RFC-007 R2: labeled delivery digest in the charge record (D10)
# a: run --delivery-alg keccak256 -> charge.delivery_hash {alg, hex} present; hex ==
#    keccak256(stdout bytes); ledger-verify ok (chain intact with the new field)
# b: run --delivery-alg sha256 -> hex == stdout_sha256 (same bytes, labeled sha256)
# c: --delivery-alg md5 (unknown alg) -> RED delivery_alg_invalid BEFORE any run
# d: ledger-verify RED delivery_hash_invalid on a validly-chained record whose
#    delivery_hash breaks shape (unknown alg / short hex) — defensive depth
# e: no flag -> NO delivery_hash field in the charge (D4 silence), ledger-verify ok
# f: pairing end-to-end: fixture generated with --delivery-alg keccak256 verifies
#    6/6 checks incl. delivery_hash_chain; tampered hex -> verify RED
set -u
cd "$(dirname "$0")/.." || exit 1
export TAMGA_KS_PASSPHRASE=simnet-2026
PASS=0; FAIL=0
ok() { if [ "$1" = 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2"; else FAIL=$((FAIL+1)); echo "  FAIL: $2"; fi }
W=$(mktemp -d /tmp/at010-XXXX)
LOG=".evidence/AT-010/$(date +%F)/at010.log"; mkdir -p "$(dirname "$LOG")"

new_pkg() { # $1 dir -> echoes seed
  mkdir -p "$1"; cp tests/vectors/tc-net-demo/tamga.json tests/vectors/tc-net-demo/agent.wasm "$1/"
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

run_agent() { # $1 pkg; $2 input; $3 outfile; rest: extra flags — agent identity = author seed (R7 ownership)
  local pkg="$1" inp="$2" outf="$3"; shift 3
  S=$(cat "$pkg/author.seed")
  python3 tamga_runner.py grant "$pkg" 0.01 "at010" > /dev/null 2>> "$LOG"
  python3 tamga_runner.py run "$pkg" --seed "$S" --input "$inp" "$@" > "$outf" 2>> "$LOG"
}

# ---------- AT-010a: labeled keccak256 digest lands in the charge ----------
SEED=$(new_pkg "$W/pkgA")
python3 -c "import json,sys; json.dump({'net_demo':False,'payload':'at010a'}, open('$W/in.json','w'), separators=(',',':'))"
run_agent "$W/pkgA" "$W/in.json" "$W/a.json" --delivery-alg keccak256
grep -q '"ok": true' "$W/a.json" && \
  python3 -c "
import json, sys, subprocess
sys.path.insert(0, 'tools')
from keccak256 import keccak256
ch = [r for r in [json.loads(l) for l in open('$W/pkgA/ledger.jsonl') if l.strip()] if r.get('op') == 'charge'][-1]
dh = ch.get('delivery_hash')
assert dh == {'alg': 'keccak256', 'hex': keccak256(open('$W/pkgA/session-1.stdout','rb').read()).hex()}, dh
raw = (pathlib.Path if False else __import__('pathlib').Path)('$W/pkgA/session-1.stdout').read_bytes()
assert dh['hex'] == keccak256(raw).hex()
v = json.loads(subprocess.run(['python3','tamga_runner.py','ledger-verify','$W/pkgA'], capture_output=True, text=True).stdout)
assert v['ok'] is True, v
print('charge.delivery_hash = keccak256(stdout) ✓, chain ok')"
ok $? "AT-010a: keccak256 delivery digest bound into the charge (chain intact)"

# ---------- AT-010b: labeled sha256 digest == stdout_sha256 ----------
run_agent "$W/pkgA" "$W/in.json" "$W/b.json" --delivery-alg sha256
grep -q '"ok": true' "$W/b.json" && \
  python3 -c "
import json
recs = [json.loads(l) for l in open('$W/pkgA/ledger.jsonl') if l.strip()]
ch = [r for r in recs if r.get('op') == 'charge'][-1]
dh = ch['delivery_hash']
assert dh == {'alg': 'sha256', 'hex': ch['stdout_sha256']}, (dh, ch['stdout_sha256'])
print('delivery_hash(sha256) == stdout_sha256 ✓')"
ok $? "AT-010b: sha256 delivery digest equals stdout_sha256 (label disambiguates)"

# ---------- AT-010c: unknown alg -> RED before any state change ----------
BEFORE=$(wc -l < "$W/pkgA/ledger.jsonl")
run_agent "$W/pkgA" "$W/in.json" "$W/c.json" --delivery-alg md5
grep -q '"ok": false' "$W/c.json" && grep -q 'delivery_alg_invalid' "$W/c.json" && \
  python3 -c "
import json, os
recs = [json.loads(l) for l in open('$W/pkgA/ledger.jsonl') if l.strip()]
assert len(recs) == $BEFORE + 1, (len(recs), $BEFORE)   # only the grant, no charge
assert recs[-1]['op'] == 'grant'
print('md5-RED ✓; no charge appended — digest never enters the chain')"
ok $? "AT-010c: unknown alg RED pre-run (grant only; no charge, no digest)"

# ---------- AT-010d: validly-chained record with broken delivery_hash shape -> RED 10 ----------
python3 - "$W/pkgA" <<'PY' >> "$LOG" 2>&1
# append a VALIDLY-CHAINED grant carrying a malformed delivery_hash (unit-level probe:
# the CLI never produces this — the gate is defensive depth against future tools)
import json, sys, pathlib
sys.path.insert(0, ".")
import tamga_runner as tr
pkg = pathlib.Path(sys.argv[1])
tr._ledger_append(pkg / "ledger.jsonl",
                  {"op": "grant", "pkg": "at010", "amount": 0.001, "note": "shape-probe",
                   "delivery_hash": {"alg": "sha3_256", "hex": "00" * 32}})
PY
python3 tamga_runner.py ledger-verify "$W/pkgA" > "$W/d.json" 2>> "$LOG"
grep -q '"ok": false' "$W/d.json" && grep -q 'delivery_hash_invalid' "$W/d.json"
ok $? "AT-010d: chained-but-mislabeled delivery_hash -> ledger-verify RED (depth gate)"

# ---------- AT-010e: no flag -> field absent (D4 silence) ----------
# (d'deki-shape-probe'undan-SONRA-koşar: probe-pkgA'yı-kalıcı-RED'ler — e-fresh-pkg'da)
SEED_E=$(new_pkg "$W/pkgE")
python3 -c "import json,sys; json.dump({'net_demo':False,'payload':'at010e'}, open('$W/inE.json','w'), separators=(',',':'))"
run_agent "$W/pkgE" "$W/inE.json" "$W/e.json"
grep -q '"ok": true' "$W/e.json" && \
  python3 -c "
import json, subprocess
recs = [json.loads(l) for l in open('$W/pkgE/ledger.jsonl') if l.strip()]
ch = [r for r in recs if r.get('op') == 'charge'][-1]
assert 'delivery_hash' not in ch, ch.get('delivery_hash')
v = json.loads(subprocess.run(['python3','tamga_runner.py','ledger-verify','$W/pkgE'], capture_output=True, text=True).stdout)
assert v['ok'] is True
print('delivery_hash yok — D4 sessizliği, zincir-ok')"
ok $? "AT-010e: absent flag -> no field (D4 silence), verify ok"

# ---------- AT-010f: pairing fixture end-to-end with the labeled digest ----------
# generate into a TEMP dir — the committed docs/pairing stays untouched (AT-007 owns it)
run_pair_out=$(python3 tools/make_pairing_fixture.py "$W/fxwork" "$W/pairing" 2>> "$LOG")
PD="$W/pairing"
python3 tools/verify_pairing_fixture.py "$PD" > "$W/f.json" 2>> "$LOG"
grep -q '"ok": true' "$W/f.json" && grep -q 'delivery_hash_chain' "$W/f.json"
ok $? "AT-010f: pairing fixture verifies 6/6 incl. delivery_hash_chain"
# tamper: flip one hex char in the charge's delivery_hash -> verify RED (on the COPY)
python3 - "$PD" <<'PY' >> "$LOG" 2>&1
import json, sys, pathlib
d = pathlib.Path(sys.argv[1])
fx = json.loads((d / "pairing-fixture.json").read_text(encoding="utf-8"))
hx = fx["tamga_observed"]["charge_record"]["value"]["delivery_hash"]["hex"]
fx["tamga_observed"]["charge_record"]["value"]["delivery_hash"]["hex"] = \
    ("0" if hx[0] != "0" else "1") + hx[1:]
(d / "pairing-fixture.json").write_text(json.dumps(fx, ensure_ascii=False, indent=2))
PY
python3 tools/verify_pairing_fixture.py "$PD" > "$W/f2.json" 2>> "$LOG"
grep -q '"ok": false' "$W/f2.json"
ok $? "AT-010f-neg: doctored charge (delivery_hash flipped) -> verify RED (membership h-recomputation catches it)"

echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
cp -r "$W" /tmp/at010-keep 2>/dev/null; rm -rf "$W"
exit $((FAIL > 0))

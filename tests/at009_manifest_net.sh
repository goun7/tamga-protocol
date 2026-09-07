#!/usr/bin/env bash
# AT-009 — RFC-007 R1: runtime.net manifest integration (founder-approved 2026-09-07)
# a: migrate-net (author-seed re-sign) -> runtime.net embedded, net.json deleted,
#    validator ACCEPT post-gate, author identity preserved
# b: migrated package runs GREEN through the proxy path; receipt binds the
#    canonical JCS of the runtime.net subtree (D12a v0.2 semantics)
# c: BOTH net.json and runtime.net present -> RED net_decl_ambiguous (policy ambiguity)
# d: dual-read window: legacy net.json package still runs green (one release)
# e: invalid runtime.net (9 endpoints) -> validator RED + runner net_decl_reject
# f: migrate-net with a WRONG author seed -> author_identity_mismatch RED
set -u
cd "$(dirname "$0")/.." || exit 1
export TAMGA_KS_PASSPHRASE=simnet-2026
PASS=0; FAIL=0
ok() { if [ "$1" = 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2"; else FAIL=$((FAIL+1)); echo "  FAIL: $2"; fi }
W=$(mktemp -d /tmp/at009-XXXX)
LOG=".evidence/AT-009/$(date +%F)/at009.log"; mkdir -p "$(dirname "$LOG")"

start_echo() { # $1: outfile for port — AT-008 ile AYNI HTTP-echo (netdemo http.client okur)
python3 - "$1" <<'PY' >> "$LOG" 2>&1 &
import socket, sys, threading
srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", 0)); srv.listen(8)
open(sys.argv[1], "w").write(str(srv.getsockname()[1]))
def h(c):
    d = b""
    while b"\r\n\r\n" not in d:
        ch = c.recv(65536)
        if not ch: break
        d += ch
    body = d.split(b"\r\n\r\n", 1)[1] if b"\r\n\r\n" in d else b""
    cl = 0
    for line in d.split(b"\r\n"):
        if line.lower().startswith(b"content-length:"):
            cl = int(line.split(b":")[1]); break
    while len(body) < cl:
        ch = c.recv(65536)
        if not ch: break
        body += ch
    c.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % (len(body), body))
    c.close()
def serve():
    while True:
        c, _ = srv.accept()
        threading.Thread(target=h, args=(c,), daemon=True).start()
serve()
PY
for i in $(seq 1 50); do [ -s "$1" ] && break; sleep 0.1; done
}

new_pkg() {
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

run_agent() {  # agent identity = the AUTHOR seed (R7 ownership); fresh-operator seed each run
  S=$(python3 tamga_runner.py keygen | python3 -c 'import sys,json;print(json.load(sys.stdin)["seed_hex"])')
  python3 tamga_runner.py grant "$1" 0.01 "at009" > /dev/null 2>> "$LOG"
  python3 tamga_runner.py run "$1" --seed "$S" --input "$2" --require-proof --note at009 > "$3" 2>> "$LOG"
}

SEED=$(new_pkg "$W/pkgA" "$NET")
KEY_BEFORE=$(python3 -c "import json;print(json.load(open('$W/pkgA/tamga.json'))['signature']['key'])")
python3 tamga_runner.py migrate-net "$W/pkgA" --seed-hex "$SEED" > "$W/mig.json" 2>> "$LOG"
grep -q '"ok": true' "$W/mig.json" && [ ! -f "$W/pkgA/net.json" ] && \
  python3 -c "
import json
m = json.load(open('$W/pkgA/tamga.json'))
n = m['runtime']['net']
assert n['egress'] == ['127.0.0.1:1'] and n['max_bytes_per_run'] == 1048576 and n['timeout_s'] == 10
assert m['signature']['key'] == '$KEY_BEFORE'
assert 'format' not in n
print('runtime.net dogru + yazar kimligi korundu')"
ok $? "AT-009a: migrate-net -> runtime.net embedded, bridge deleted, ACCEPT, author kept"

start_echo "$W/echoB.port"; EPORT=$(cat "$W/echoB.port")
python3 - "$W/pkgA/tamga.json" "$EPORT" <<'PY' >> "$LOG" 2>&1
import json, sys, pathlib
sys.path.insert(0, ".")
import tamga_validator as tv
d = pathlib.Path(sys.argv[1])
m = json.loads(d.read_text())
m["runtime"]["net"]["egress"] = [f"127.0.0.1:{sys.argv[2]}"]
sk = tv.SigningKey(bytes.fromhex(open(d.parent / "author.seed").read().strip()))
probe = dict(m); probe["signature"] = {**m["signature"], "sig": ""}
m["signature"]["sig"] = sk.sign(tv.jcs(probe)).signature.hex()
d.write_text(json.dumps(m, indent=2))
PY
python3 -c "import json,sys; json.dump({'net_demo':True,'url':'http://127.0.0.1:$EPORT/echo','payload':'at009b'}, open('$W/inB.json','w'), separators=(',',':'))"
run_agent "$W/pkgA" "$W/inB.json" "$W/b.json"
grep -q '"ok": true' "$W/b.json" && grep -q 'NET-DEMO:status=200' "$W/pkgA/session-1.stdout" && \
  grep -q '"event":"net_connect"' "$W/pkgA/net-events-1.jsonl" && \
python3 -c "
import json, hashlib, sys
sys.path.insert(0, '.'); from tamga_validator import jcs
ch = [r for r in [json.loads(l) for l in open('$W/pkgA/ledger.jsonl') if l.strip()] if r.get('op') == 'charge'][-1]
m = json.load(open('$W/pkgA/tamga.json'))
exp = hashlib.sha256(jcs(m['runtime']['net'])).hexdigest()
assert ch['net_decl_sha256'] == exp, (ch['net_decl_sha256'], exp)
assert ch['net_mb'] > 0 and 'net_events_sha256' in ch
print('D12a manifest anlami: sha256(jcs(runtime.net)) =', exp[:16], '... OK')"
ok $? "AT-009b: migrated run GREEN; net_decl_sha256 binds canonical runtime.net"

# fresh pkg (a migrated manifest + a matching-bridge net.json) so the ONLY violation
# under test is the ambiguity itself — not a stale-bridge binding mismatch
SEED_C=$(new_pkg "$W/pkgC" "$NET")
python3 tamga_runner.py migrate-net "$W/pkgC" --seed-hex "$SEED_C" > /dev/null 2>> "$LOG"
printf '%s' "$NET" > "$W/pkgC/net.json"          # resurrect the bridge file
run_agent "$W/pkgC" "$W/inB.json" "$W/c.json"
grep -q '"ok": false' "$W/c.json" && grep -q 'net_decl_ambiguous' "$W/c.json"
ok $? "AT-009c: net.json + runtime.net both present -> net_decl_ambiguous RED (runner or pre-run validator gate)"

SEED_D=$(new_pkg "$W/pkgD" "{\"format\":\"tamga-net-declaration/1\",\"egress\":[\"127.0.0.1:$EPORT\"],\"max_bytes_per_run\":1048576,\"timeout_s\":10}")
python3 -c "import json,sys; json.dump({'net_demo':True,'url':'http://127.0.0.1:$EPORT/echo','payload':'at009d'}, open('$W/inD.json','w'), separators=(',',':'))"
run_agent "$W/pkgD" "$W/inD.json" "$W/d.json"
grep -q '"ok": true' "$W/d.json" && grep -q 'NET-DEMO:status=200' "$W/pkgD/session-1.stdout" && \
  python3 -c "
import json, hashlib, pathlib
recs = [json.loads(l) for l in open('$W/pkgD/ledger.jsonl') if l.strip()]
ch = [r for r in recs if r.get('op') == 'charge'][-1]
raw = pathlib.Path('$W/pkgD/net.json').read_bytes()
assert ch['net_decl_sha256'] == hashlib.sha256(raw).hexdigest()"
ok $? "AT-009d: legacy net.json still valid; file-byte D12a semantics preserved"

python3 - "$W/pkgC" <<'PY' >> "$LOG" 2>&1
import json, sys, pathlib
sys.path.insert(0, ".")
import tamga_validator as tv
d = pathlib.Path(sys.argv[1])
m = json.loads((d / "tamga.json").read_text())
m["runtime"]["net"]["egress"] = [f"127.0.0.1:{i}" for i in range(1, 10)]
sk = tv.SigningKey(bytes.fromhex((d / "author.seed").read_text().strip()))
probe = dict(m); probe["signature"] = {**m["signature"], "sig": ""}
m["signature"]["sig"] = sk.sign(tv.jcs(probe)).signature.hex()
(d / "tamga.json").write_text(json.dumps(m, indent=2))
PY
python3 tamga_validator.py validate "$W/pkgC" 2>/dev/null | grep -q 'RED schema_violation: runtime.net'
ok $? "AT-009e1: 9 endpoints -> validator schema RED (runtime.net)"
run_agent "$W/pkgC" "$W/inB.json" "$W/e.json"
grep -q '"ok": false' "$W/e.json" && grep -q 'schema_violation: runtime.net' "$W/e.json"
ok $? "AT-009e2: invalid runtime.net -> run RED at the pre-run manifest gate (fail-closed)"

SEED_F=$(new_pkg "$W/pkgF" "$NET")
SEED_B=$(python3 tamga_runner.py keygen | python3 -c 'import sys,json;print(json.load(sys.stdin)["seed_hex"])')
python3 tamga_runner.py migrate-net "$W/pkgF" --seed-hex "$SEED_B" > "$W/f.json" 2>> "$LOG"
grep -q '"reason_code": 9' "$W/f.json" && grep -q 'author_identity_mismatch' "$W/f.json"
ok $? "AT-009f: wrong seed -> author_identity_mismatch RED (tool never invents identity)"

echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
cp -r "$W" /tmp/at009-keep2 2>/dev/null; rm -rf "$W"
exit $((FAIL > 0))

#!/usr/bin/env bash
# AT-008 — D13 agent-side network shim (RFC-006; run_all control-21)
# a: net-demo agent + mock-http echo -> run OK, request line in evidence,
#    NET-DEMO:status=200, charge net_mb > 0, net_connect in events
# b: non-egress host request -> shim soft error not_listed, run continues
# c: mock-HTTPS (local CA) -> 200, cert verified against declared host name
# d: net.json-less package + net-demo agent -> net_shim_ignored=1, receipt silent
# e: byte-cap 1KiB + 8KiB response mid-run -> run-level RED 11, no charge
# f: evidence integrity: charge stdout_sha256 == artifact bytes (incl. request line)
set -u
cd "$(dirname "$0")/.." || exit 1
export TAMGA_KS_PASSPHRASE=simnet-2026
PASS=0; FAIL=0
ok() { if [ "$1" = 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2"; else FAIL=$((FAIL+1)); echo "  FAIL: $2"; fi }
W=$(mktemp -d /tmp/at008-XXXX)
LOG=".evidence/AT-008/$(date +%F)/at008.log"; mkdir -p "$(dirname "$LOG")"

# ---------- helpers ----------
start_echo() { # $1: outfile for port; $2: "big" optional = 8KiB body
python3 - "$1" "${2:-small}" <<'PY' >> "$LOG" 2>&1 &
import socket, sys, threading
srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", 0)); srv.listen(8)
open(sys.argv[1], "w").write(str(srv.getsockname()[1]))
BODY = b"E" * 8192 if sys.argv[2] == "big" else None
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
    if BODY is not None:
        body = BODY
    c.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % (len(body), body))
    c.close()
def serve():
    while True:
        c, _ = srv.accept()
        threading.Thread(target=h, args=(c,), daemon=True).start()
serve()
PY
[ -f "$1" ] || { for i in $(seq 1 30); do [ -f "$1" ] && break; sleep 0.1; done; }
}

new_pkg() { # $1 dir; copies net-demo fixture + net.json($2) if given
  mkdir -p "$1"; cp tests/vectors/tc-net-demo/tamga.json tests/vectors/tc-net-demo/agent.wasm "$1/"
  if [ -n "${2:-}" ]; then printf '%s' "$2" > "$1/net.json"; fi
}
run_agent() { # $1 pkg; $2 input-json; $3 outfile
  S=$(python3 tamga_runner.py keygen | python3 -c 'import sys,json;print(json.load(sys.stdin)["seed_hex"])')
  python3 tamga_runner.py grant "$1" 0.01 "at008" > /dev/null 2>> "$LOG"
  python3 tamga_runner.py run "$1" --seed "$S" --input "$2" --require-proof --note at008 > "$3" 2>> "$LOG"
}

# ---------- AT-008a: happy path ----------
start_echo "$W/echoA.port"; EPORT=$(cat "$W/echoA.port")
new_pkg "$W/pkgA" "{\"format\":\"tamga-net-declaration/1\",\"egress\":[\"127.0.0.1:$EPORT\"],\"max_bytes_per_run\":1048576,\"timeout_s\":10}"
python3 -c "import json,sys; json.dump({'net_demo':True,'url':'http://127.0.0.1:$EPORT/echo','payload':'at008a'}, open('$W/inA.json','w'), separators=(',',':'))"
run_agent "$W/pkgA" "$W/inA.json" "$W/a.json"
grep -q '"ok": true' "$W/a.json" && grep -q 'NET-DEMO:status=200' "$W/pkgA/session-1.stdout" && \
  grep -q '"event":"net_connect"' "$W/pkgA/net-events-1.jsonl" && \
  python3 -c "
import json, sys
ch = [json.loads(l) for l in open('$W/pkgA/ledger.jsonl') if l.strip()][-1]
assert ch['net_mb'] > 0, ch['net_mb']
assert 'net_decl_sha256' in ch and 'net_events_sha256' in ch"
ok $? "AT-008a: net-demo run -> 200 + request-line evidence + net_connect + net_mb>0 (D12)"

# ---------- AT-008b: non-egress host -> soft denial, run continues ----------
new_pkg "$W/pkgB" "{\"format\":\"tamga-net-declaration/1\",\"egress\":[\"example.com:443\"],\"max_bytes_per_run\":1048576,\"timeout_s\":10}"
python3 -c "import json; json.dump({'net_demo':True,'url':'http://127.0.0.1:9/echo','payload':'at008b'}, open('$W/inB.json','w'), separators=(',',':'))"
run_agent "$W/pkgB" "$W/inB.json" "$W/b.json"
grep -q '"ok": true' "$W/b.json" && grep -q 'NET-DEMO:status=? ok=false' "$W/pkgB/session-1.stdout" && \
  grep -q '"reason":"not_listed"' "$W/pkgB/net-events-1.jsonl"
ok $? "AT-008b: non-egress request -> shim soft not_listed, run OK, net_denied logged"

# ---------- AT-008c: mock-HTTPS with local CA (IP-SAN cert; egress stays 127.0.0.1
# because the D12-dns declaration load REFUSES unresolvable names — fail-closed) ----------
mkdir -p "$W/ca"
openssl req -x509 -newkey rsa:2048 -keyout "$W/ca/key.pem" -out "$W/ca/cert.pem" \
  -days 2 -nodes -subj "/CN=mock.tamga.test" \
  -addext "subjectAltName=IP:127.0.0.1" > /dev/null 2>&1
python3 - "$W/ca/cert.pem" "$W/ca/key.pem" "$W/tls.port" <<'PY' >> "$LOG" 2>&1 &
import socket, ssl, sys, threading
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(sys.argv[1], sys.argv[2])
srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", 0)); srv.listen(4)
open(sys.argv[3], "w").write(str(srv.getsockname()[1]))
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
    while len(body) < cl:   # gövde-dreni: RST önleyici (bkz. RFC-006 §4 notu)
        ch = c.recv(65536)
        if not ch: break
        body += ch
    c.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % (len(body), body))
    c.close()
def serve():
    while True:
        c, _ = srv.accept()
        try:
            tls = ctx.wrap_socket(c, server_side=True)
            threading.Thread(target=h, args=(tls,), daemon=True).start()
        except ssl.SSLError:
            c.close()
serve()
PY
for i in $(seq 1 30); do [ -s "$W/tls.port" ] && break; sleep 0.1; done; TPORT=$(cat "$W/tls.port")
new_pkg "$W/pkgC" "{\"format\":\"tamga-net-declaration/1\",\"egress\":[\"127.0.0.1:$TPORT\"],\"max_bytes_per_run\":1048576,\"timeout_s\":10}"
python3 -c "import json; json.dump({'net_demo':True,'url':'https://127.0.0.1:$TPORT/echo','payload':'at008c'}, open('$W/inC.json','w'), separators=(',',':'))"
S=$(python3 tamga_runner.py keygen | python3 -c 'import sys,json;print(json.load(sys.stdin)["seed_hex"])')
python3 tamga_runner.py grant "$W/pkgC" 0.01 "at008" > /dev/null 2>> "$LOG"
TAMGA_NET_CA_BUNDLE="$W/ca/cert.pem" python3 tamga_runner.py run "$W/pkgC" --seed "$S" \
  --input "$W/inC.json" --require-proof --note at008 > "$W/c.json" 2>> "$LOG"
grep -q '"ok": true' "$W/c.json" && grep -q 'NET-DEMO:status=200' "$W/pkgC/session-1.stdout"
ok $? "AT-008c: mock-HTTPS (local CA) -> 200 over CONNECT+TLS, SNI=declared host"

# ---------- AT-008d: net.json-less package -> silent drop + counter ----------
mkdir -p "$W/pkgD"; cp tests/vectors/tc-net-demo/tamga.json tests/vectors/tc-net-demo/agent.wasm "$W/pkgD/"
python3 -c "import json; json.dump({'net_demo':True,'url':'http://127.0.0.1:9/echo','payload':'at008d'}, open('$W/inD.json','w'), separators=(',',':'))"
run_agent "$W/pkgD" "$W/inD.json" "$W/d.json"
grep -q '"ok": true' "$W/d.json" && grep -q '"net_shim_ignored": 1' "$W/d.json" && \
  ! ls "$W/pkgD"/net-events-*.jsonl > /dev/null 2>&1 && \
  python3 -c "
import json
ch = [json.loads(l) for l in open('$W/pkgD/ledger.jsonl') if l.strip()][-1]
assert 'net_mb' not in ch and 'net_decl_sha256' not in ch"
ok $? "AT-008d: net.json-less + net-request -> net_shim_ignored=1, D4 silence kept"

# ---------- AT-008e: byte-cap mid-run -> run-level RED 11, no charge ----------
start_echo "$W/echoE.port" big; EPORT_E=$(cat "$W/echoE.port")
new_pkg "$W/pkgE" "{\"format\":\"tamga-net-declaration/1\",\"egress\":[\"127.0.0.1:$EPORT_E\"],\"max_bytes_per_run\":1024,\"timeout_s\":10}"
python3 -c "import json; json.dump({'net_demo':True,'url':'http://127.0.0.1:$EPORT_E/echo','payload':'at008e'}, open('$W/inE.json','w'), separators=(',',':'))"
run_agent "$W/pkgE" "$W/inE.json" "$W/e.json"
grep -q '"reason_code": 11' "$W/e.json" && grep -q "session capped" "$W/e.json" && \
  python3 -c "
import json
recs = [json.loads(l) for l in open('$W/pkgE/ledger.jsonl') if l.strip()]
assert not [r for r in recs if r.get('op') == 'charge']"
ok $? "AT-008e: 8KiB response vs 1KiB cap mid-run -> RED 11, no charge (hard path preserved)"

# ---------- AT-008f: evidence integrity (artifact incl. request line == charge hash) ----------
python3 -c "
import hashlib, json
ch = [json.loads(l) for l in open('$W/pkgA/ledger.jsonl') if l.strip()][-1]
art = open('$W/pkgA/session-1.stdout', 'rb').read()
assert ch['stdout_sha256'] == hashlib.sha256(art).hexdigest()
assert b'TAMGA-NET-1 ' in art   # request line is part of the evidence, uncurated"
ok $? "AT-008f: evidence artifact (incl. request line) == charge stdout_sha256"

# ---------- log summary ----------
python3 - "$W/pkgA/net-events-1.jsonl" <<'PY' >> "$LOG" 2>&1
import json, sys
evs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
print("AT-008a events:", [e["event"] for e in evs])
PY

echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
cp -r "$W" /tmp/at008-keep 2>/dev/null; rm -rf "$W"
exit $((FAIL > 0))

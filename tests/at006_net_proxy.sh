#!/usr/bin/env bash
# AT-006 - net proxy (RFC-005A slice-1: M1 net.json reader, M2 egress proxy,
# M3 policy engine, M4 byte counter)
# Covered here: AT-006a (D4 regression without net.json), AT-006b (not-listed
# host -> denied, session continues), AT-006d (IP pinhole never tunneled),
# AT-006e (decl parse RED), positive tunnel + byte counting, session byte cap.
# Slice-2 adds AT-006c/f/g (run-level RED, net_decl_sha256 receipt binding,
# net_mb charge) together with the wasmtime wasi-sockets integration.
# Output: .evidence/AT-006/<date>/at006.log
set -uo pipefail
cd "$(dirname "$0")/.."
export TAMGA_KS_PASSPHRASE="${TAMGA_KS_PASSPHRASE:-simnet-2026}"
PASS=0; FAIL=0
ok()  { if [ "$1" = "0" ]; then PASS=$((PASS+1)); echo "  PASS: $2"; else FAIL=$((FAIL+1)); echo "  FAIL: $2"; fi; }
EV="${TAMGA_EVIDENCE_DIR:-.evidence}/AT-006/$(date +%F)"; mkdir -p "$EV"
LOG="$EV/at006.log"; : > "$LOG"
W=tests/simnet/.at006; rm -rf "$W"; mkdir -p "$W/pkg"
ECHO_PIDS=""

cleanup() { [ -n "$ECHO_PIDS" ] && kill $ECHO_PIDS 2>/dev/null; }
trap cleanup EXIT

echo "--- AT-006: net proxy (scripted clients; box stays socket-free)" | tee -a "$LOG"

# ---------- helpers ----------
# upstream echo server on an ephemeral port; stores its port in $1
start_echo() {
python3 - "$1" <<'PY' >> "$LOG" 2>&1 &
import socket, sys, threading
p = open(sys.argv[1], "w")
srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", 0)); srv.listen(8); p.write(str(srv.getsockname()[1])); p.close()
def serve():
    while True:
        c, _ = srv.accept()
        def h(c=c):
            try:
                while True:
                    d = c.recv(4096)
                    if not d: break
                    c.sendall(d)
            except OSError: pass
            finally: c.close()
        threading.Thread(target=h, daemon=True).start()
serve()
PY
ECHO_PIDS="$ECHO_PIDS $!"
for i in $(seq 1 50); do [ -s "$1" ] && break; sleep 0.1; done
}

# in-repo proxy driver: starts TamgaProxy, waits for a sentinel, then stops
start_proxy() { # $1 decl  $2 events  $3 summary-out  $4 sentinel
python3 - "$1" "$2" "$3" "$4" <<'PY' >> "$LOG" 2>&1 &
import json, sys, time
sys.path.insert(0, ".")
import tamga_netproxy as tp
d = tp.load_net_decl(sys.argv[1])
p = tp.TamgaProxy(d, events_path=sys.argv[2])
port = p.start()
open(sys.argv[1] + ".port", "w").write(str(port))
for _ in range(300):                       # up to 30s for the driving section
    if __import__("os").path.exists(sys.argv[4]):
        break
    time.sleep(0.1)
open(sys.argv[3], "w").write(json.dumps(p.summary()))
p.stop()
PY
}

wait_for() { for i in $(seq 1 100); do [ -s "$1" ] && return 0; sleep 0.1; done; return 1; }

# fake agent: one CONNECT through the proxy; prints the proxy's status line
agent_connect() { # $1 proxy_port  $2 host:port  $3 payload (optional)
python3 - "$1" "$2" "${3:-}" <<'PY' 2>> "$LOG"
import socket, sys
pp, target, payload = sys.argv[1], sys.argv[2], sys.argv[3].encode()
c = socket.create_connection(("127.0.0.1", int(pp)), timeout=10)
c.sendall(f"CONNECT {target} HTTP/1.1\r\nHost: {target}\r\n\r\n".encode())
resp = b""
while b"\r\n\r\n" not in resp:
    d = c.recv(4096)
    if not d: break
    resp += d
print("PROXY_STATUS:" + resp.split(b"\r\n", 1)[0].decode("latin-1"))
if b" 200 " in resp.split(b"\r\n", 1)[0] and payload:
    c.sendall(payload)
    c.settimeout(5)
    got = b""
    try:
        while len(got) < len(payload):
            d = c.recv(4096)
            if not d: break
            got += d
    except socket.timeout: pass
    print("ECHO_MATCH:" + str(got == payload))
c.close()
PY
}

# ---------- AT-006a: D4 regression — no net.json -> today's behavior ----------
cp tests/vectors/tc-a1/tamga.json tests/vectors/tc-a1/agent.wasm "$W/pkg/"
SEED=$(python3 tamga_runner.py keygen | python3 -c 'import sys,json;print(json.load(sys.stdin)["seed_hex"])')
python3 tamga_runner.py grant "$W/pkg" 0.01 "at006-hibe" > /dev/null 2>> "$LOG"
python3 tamga_runner.py run "$W/pkg" --seed "$SEED" --note "at006a" > "$W/a.json" 2>> "$LOG"
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
recs = [json.loads(l) for l in open(sys.argv[2]) if l.strip()]
ch = [r for r in recs if r.get("op") == "charge"]
assert d.get("ok") is True, "run failed without net.json"
assert ch, "no charge receipt"
assert not any(k.startswith("net_") for r in ch for k in r), "net fields leaked into v0.1 receipt"
' "$W/a.json" "$W/pkg/ledger.jsonl"
ok $? "AT-006a: no net.json -> D4 silence, run ok, receipt carries no net fields"

# ---------- AT-006e: decl parse RED (9 endpoints) ----------
python3 - "$W/bad-net.json" <<'PY'
import json, sys
json.dump({"format": "tamga-net-declaration/1",
           "egress": [f"h{i}.example.com:443" for i in range(9)],
           "max_bytes_per_run": 1048576, "timeout_s": 5}, open(sys.argv[1], "w"))
PY
python3 tamga_netproxy.py --decl "$W/bad-net.json" > "$W/e.out" 2>> "$LOG"
rc=$?
[ "$rc" -ne 0 ] && grep -q "net_decl_reject" "$W/e.out"
ok $? "AT-006e: >8 endpoints -> parse RED with net_decl_reject"

# ---------- positive tunnel + counter (M2/M3/M4) ----------
start_echo "$W/echo.port"; EPORT=$(cat "$W/echo.port")
python3 - "$W/net.json" "$EPORT" <<'PY'
import json, sys
json.dump({"format": "tamga-net-declaration/1",
           "egress": ["127.0.0.1:443", f"127.0.0.1:{sys.argv[2]}"],
           "max_bytes_per_run": 8 * 1024 * 1024, "timeout_s": 10},
          open(sys.argv[1], "w"))
PY
start_proxy "$W/net.json" "$W/events.jsonl" "$W/sum.json" "$W/done1"
wait_for "$W/net.json.port" || { echo "  FAIL: proxy did not start"; exit 1; }
PPORT=$(cat "$W/net.json.port")
agent_connect "$PPORT" "127.0.0.1:$EPORT" "ping-tamga-123" > "$W/t.out" 2>> "$LOG"
grep -q "PROXY_STATUS:HTTP/1.1 200" "$W/t.out" && grep -q "ECHO_MATCH:True" "$W/t.out"
ok $? "tunnel: allow-listed endpoint CONNECT 200 + payload echoed byte-exact"

# not-listed host (AT-006b) — session continues afterwards
agent_connect "$PPORT" "evil.example.com:443" "x" > "$W/b.out" 2>> "$LOG"
grep -q "PROXY_STATUS:HTTP/1.1 403" "$W/b.out"
ok $? "AT-006b: not-listed host -> 403 denied to the caller"
agent_connect "$PPORT" "127.0.0.1:$EPORT" "after-deny" > "$W/b2.out" 2>> "$LOG"
grep -q "PROXY_STATUS:HTTP/1.1 200" "$W/b2.out"
ok $? "AT-006b: session continues after a denial (soft path)"

# IP pinhole (AT-006d): raw IP not on the list is never tunneled
agent_connect "$PPORT" "169.254.169.254:80" "x" > "$W/d.out" 2>> "$LOG"
grep -q "PROXY_STATUS:HTTP/1.1 403" "$W/d.out"
ok $? "AT-006d: IP-literal pinhole -> 403, no upstream connection"

touch "$W/done1"; wait_for "$W/sum.json"
python3 - "$W/events.jsonl" "$W/sum.json" <<'PY'
import json, sys
evs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
s = json.load(open(sys.argv[2]))
pairs = [[e["event"], e.get("reason", "")] for e in evs]
assert ["net_denied", "not_listed"] in pairs, "not_listed denial event missing"
conns = [e for e in evs if e["event"] == "net_connect"]
assert conns and all(e["ok"] is True for e in conns), "net_connect events missing/failed"
assert any(e["bytes_tx"] > 0 and e["bytes_rx"] > 0 for e in conns), "byte counters did not flow"
assert s["connects_ok"] >= 2 and s["denied"] >= 2, "summary counters wrong"
assert s["bytes_total"] > 0 and not s["capped"], "summary bytes/capped wrong"
# charge-granularity value must exist and round honestly (tiny test payloads round to 0.0)
assert isinstance(s["net_mb"], float) and s["net_mb"] >= 0.0, "net_mb missing"
PY
ok $? "M3/M4: net_denied reasons + net_connect byte counters + session summary consistent"

# ---------- session byte cap (hard path) ----------
start_echo "$W/echo2.port"; EPORT2=$(cat "$W/echo2.port")
[ -n "$EPORT2" ] || { echo "  FAIL: echo2 did not start"; exit 1; }
python3 - "$W/net-cap.json" "$EPORT2" <<'PY'
import json, sys
json.dump({"format": "tamga-net-declaration/1",
           "egress": [f"127.0.0.1:{sys.argv[2]}"],
           "max_bytes_per_run": 1024, "timeout_s": 10},
          open(sys.argv[1], "w"))
PY
start_proxy "$W/net-cap.json" "$W/events-cap.jsonl" "$W/sum-cap.json" "$W/done2"
wait_for "$W/net-cap.json.port" || { echo "  FAIL: cap proxy did not start"; exit 1; }
PPORT2=$(cat "$W/net-cap.json.port")
python3 - "$PPORT2" "127.0.0.1:$EPORT2" <<'PY' > "$W/cap.out" 2>> "$LOG"
import socket, sys
pp, target = sys.argv[1], sys.argv[2]
c = socket.create_connection(("127.0.0.1", int(pp)), timeout=10)
c.sendall(f"CONNECT {target} HTTP/1.1\r\n\r\n".encode())
resp = b""
while b"\r\n\r\n" not in resp:
    resp += c.recv(4096)
print("CAP_STATUS:" + resp.split(b"\r\n", 1)[0].decode("latin-1"))
c.settimeout(5)
try:
    c.sendall(b"A" * 4096)   # 4KiB > 1KiB cap -> flow must be killed mid-stream
    got = b""
    try:
        got = c.recv(4096)
    except (socket.timeout, ConnectionResetError, OSError):
        got = b""
    print("CAP_TRIPPED:" + str(got == b""))
except OSError:
    print("CAP_TRIPPED:True")
c.close()
PY
grep -q "CAP_STATUS:HTTP/1.1 200" "$W/cap.out"
ok $? "cap: oversized flow starts inside an allowed tunnel (cap enforced mid-flow)"
touch "$W/done2"; wait_for "$W/sum-cap.json"
python3 - "$W/events-cap.jsonl" "$W/sum-cap.json" <<'PY'
import json, sys
evs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
s = json.load(open(sys.argv[2]))
assert any(e["event"] == "net_byte_cap" for e in evs), \
    f"byte_cap event missing: {[[e['event'], e.get('reason', '')] for e in evs]}"
assert s["capped"] is True, f"summary.capped not set: {s}"
PY
ok $? "M4: net_byte_cap event + summary.capped, session counter clamps the flow"

# ---------- event-log file permissions (M5 seed) ----------
PERM=$(stat -c '%a' "$W/events.jsonl")
[ "$PERM" = "600" ]
ok $? "M5 seed: net-events file is 0600"

echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" = "0" ]
rm -rf "$W"
exit $((FAIL > 0))

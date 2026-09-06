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

# upstream echo with an artificial echo delay (holds a tunnel slot open)
start_echo_slow() { # $1 port-file  $2 delay seconds
python3 - "$1" "$2" <<'PY' >> "$LOG" 2>&1 &
import socket, sys, threading, time
pf = open(sys.argv[1], "w")
srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", 0)); srv.listen(8); pf.write(str(srv.getsockname()[1])); pf.close()
delay = float(sys.argv[2])
def serve():
    while True:
        c, _ = srv.accept()
        def h(c=c):
            try:
                d = c.recv(4096)
                time.sleep(delay)
                if d: c.sendall(d)
                while True:
                    x = c.recv(4096)
                    if not x: break
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

# ---------- concurrency cap (post-review hardening) ----------
start_echo_slow "$W/echo3.port" 1.0; EPORT3=$(cat "$W/echo3.port")
python3 - "$W/net-cc.json" "$EPORT3" <<'PY'
import json, sys
json.dump({"format": "tamga-net-declaration/1",
           "egress": [f"127.0.0.1:{sys.argv[2]}"],
           "max_bytes_per_run": 8 * 1024 * 1024, "timeout_s": 10},
          open(sys.argv[1], "w"))
PY
start_proxy "$W/net-cc.json" "$W/events-cc.jsonl" "$W/sum-cc.json" "$W/done3"
wait_for "$W/net-cc.json.port" || { echo "  FAIL: cc proxy did not start"; exit 1; }
PPORT3=$(cat "$W/net-cc.json.port")
python3 - "$PPORT3" "127.0.0.1:$EPORT3" "$W/hold-ids.txt" <<'PY' > "$W/hold.out" 2>> "$LOG"
import socket, sys, threading
pp, target = sys.argv[1], sys.argv[2]
out = []
def one(i):
    c = socket.create_connection(("127.0.0.1", int(pp)), timeout=10)
    c.sendall(f"CONNECT {target} HTTP/1.1\r\n\r\n".encode())
    r = b""
    while b"\r\n\r\n" not in r:
        d = c.recv(4096)
        if not d: break
        r += d
    out.append((i, r.split(b"\r\n", 1)[0].decode("latin-1"), c))
ts = [threading.Thread(target=one, args=(i,)) for i in range(35)]
[t.start() for t in ts]; [t.join() for t in ts]
open(sys.argv[3], "w").write("\n".join(f"{i} {s}" for i, s, _ in out))
import time; time.sleep(2.5)     # hold the 32 slots while the excess CONNECTs arrive
for _, _, c in out:
    try: c.close()
    except OSError: pass
PY
n200=$(grep -c " 200 " "$W/hold-ids.txt" || true); n403=$(grep -c " 403 " "$W/hold-ids.txt" || true)
[ "$n200" -le 32 ] && [ "$n403" -ge 3 ]
ok $? "concurrency: 35 parallel CONNECTs -> at most 32 tunneled ($n200), excess 403 ($n403)"
python3 - "$PPORT3" "127.0.0.1:$EPORT3" <<'PY' > "$W/after-cc.out" 2>> "$LOG"
import socket, sys
c = socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=10)
c.sendall(f"CONNECT {sys.argv[2]} HTTP/1.1\r\n\r\n".encode())
r = b""
while b"\r\n\r\n" not in r:
    d = c.recv(4096)
    if not d: break
    r += d
print("AFTER:" + r.split(b"\r\n", 1)[0].decode("latin-1"))
c.close()
PY
grep -q "AFTER:HTTP/1.1 200" "$W/after-cc.out"
ok $? "concurrency: slots released after holders exit (service recovered)"
python3 - "$W/events-cc.jsonl" <<'PY'
import json, sys
evs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
assert any(e.get("reason") == "conn_limit" for e in evs), "conn_limit denial missing"
PY
ok $? "M3: conn_limit denial recorded in the event log"
touch "$W/done3"; wait_for "$W/sum-cc.json"

# ---------- AT-006g: D12 fields on a net-run (runner-side wiring) ----------
mkdir -p "$W/pkg-g"; cp tests/vectors/tc-a1/tamga.json tests/vectors/tc-a1/agent.wasm "$W/pkg-g/"
python3 - "$W/pkg-g/net.json" <<'PY'
import json, sys
json.dump({"format": "tamga-net-declaration/1",
           "egress": ["api.openai.com:443"],
           "max_bytes_per_run": 1048576, "timeout_s": 10}, open(sys.argv[1], "w"))
PY
SG=$(python3 tamga_runner.py keygen | python3 -c 'import sys,json;print(json.load(sys.stdin)["seed_hex"])')
python3 tamga_runner.py grant "$W/pkg-g" 0.01 "at006g" > /dev/null 2>> "$LOG"
python3 tamga_runner.py run "$W/pkg-g" --seed "$SG" --note "at006g" > "$W/g.json" 2>> "$LOG"
python3 - "$W/pkg-g" <<'PY'
import hashlib, json, sys, pathlib
pkg = pathlib.Path(sys.argv[1])
recs = [json.loads(l) for l in (pkg / "ledger.jsonl").read_text().splitlines() if l.strip()]
ch = [r for r in recs if r.get("op") == "charge"][-1]
for k in ("net_decl_sha256", "net_events_sha256", "net_mb"):
    assert k in ch, f"charge missing {k}"
assert ch["net_decl_sha256"] == hashlib.sha256((pkg / "net.json").read_bytes()).hexdigest()
assert ch["net_mb"] == 0.0                      # silent agent: zero traffic, honestly metered
ev = pkg / "net-events-1.jsonl"
assert ev.exists() and (ev.stat().st_mode & 0o777) == 0o600, "events file missing or not 0600"
first = json.loads(ev.read_text().splitlines()[0])
assert first["event"] == "proxy_start" and first["port"] > 0, "proxy_start missing"
PY
ok $? "AT-006g: net-run receipt carries net_decl_sha256 + net_events_sha256 + net_mb (0.0)"

# ---------- AT-006f: post-run declaration tamper -> validator RED ----------
python3 - "$W/pkg-g/net.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["egress"].append("api.anthropic.com:443")
json.dump(d, open(sys.argv[1], "w"))
PY
python3 tamga_validator.py validate "$W/pkg-g" > "$W/f.out" 2>> "$LOG"; cat "$W/f.out" >> "$LOG"
grep -q "RED net_binding_mismatch" "$W/f.out"
ok $? "AT-006f: post-run net.json tamper -> validator RED net_binding_mismatch"

# ---------- AT-006c: live byte cap trips a REAL run (slow agent + traffic) ----------
mkdir -p "$W/pkg-c"; cp tests/vectors/tc-net-slow/tamga.json tests/vectors/tc-net-slow/agent.wasm "$W/pkg-c/"
start_echo "$W/echo4.port"; EPORT4=$(cat "$W/echo4.port")
python3 - "$W/pkg-c/net.json" "$EPORT4" <<'PY'
import json, sys
json.dump({"format": "tamga-net-declaration/1",
           "egress": [f"127.0.0.1:{sys.argv[2]}"],
           "max_bytes_per_run": 1024, "timeout_s": 10}, open(sys.argv[1], "w"))
PY
SC=$(python3 tamga_runner.py keygen | python3 -c 'import sys,json;print(json.load(sys.stdin)["seed_hex"])')
python3 tamga_runner.py grant "$W/pkg-c" 0.01 "at006c" > /dev/null 2>> "$LOG"
python3 tamga_runner.py run "$W/pkg-c" --seed "$SC" --note "at006c" > "$W/c.json" 2>> "$LOG" &
RUNPID=$!
for i in $(seq 1 100); do
  [ -s "$W/pkg-c/net-events-1.jsonl" ] && grep -q proxy_start "$W/pkg-c/net-events-1.jsonl" && break
  sleep 0.1
done
PPORT4=$(python3 -c "
import json
for l in open('$W/pkg-c/net-events-1.jsonl'):
    e = json.loads(l)
    if e.get('event') == 'proxy_start':
        print(e['port']); break
")
python3 - "$PPORT4" "$EPORT4" <<'PY' >> "$LOG" 2>&1
import socket, sys, time
c = socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=10)
c.sendall(f"CONNECT 127.0.0.1:{sys.argv[2]} HTTP/1.1\r\n\r\n".encode())
r = b""
while b"\r\n\r\n" not in r:
    r += c.recv(4096)
assert b" 200 " in r.split(b"\r\n", 1)[0], r[:60]
c.sendall(b"B" * 8192)          # 8KiB > 1KiB cap -> session capped mid-run
time.sleep(0.5)
c.close()
PY
wait $RUNPID
grep -q '"reason_code": 11' "$W/c.json" && grep -q "session capped" "$W/c.json"
ok $? "AT-006c: live byte-cap during a real run -> run-level RED 11"
python3 -c "
import json
recs = [json.loads(l) for l in open('$W/pkg-c/ledger.jsonl') if l.strip()]
assert not [r for r in recs if r.get('op') == 'charge'], 'failed run must not append a charge'
"
ok $? "AT-006c: capped run appends no charge receipt"
python3 - "$W/pkg-c/net-events-1.jsonl" <<'PY'
import json, sys
evs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
assert any(e["event"] == "net_byte_cap" for e in evs), "byte_cap event missing in run events"
PY
ok $? "AT-006c: net_byte_cap recorded in the run's event log (0600)"

# ---------- IP-pinning proof: a tampered resolver cannot redirect a listed FQDN ----------
start_echo "$W/echo5.port"; EPORT5=$(cat "$W/echo5.port")
python3 - "$W/net-pin.json" "$EPORT5" <<'PY'
import json, sys
json.dump({"format": "tamga-net-declaration/1",
           "egress": [f"localhost:{sys.argv[2]}"],
           "max_bytes_per_run": 1048576, "timeout_s": 10}, open(sys.argv[1], "w"))
PY
python3 - "$W/net-pin.json" "$W/ev-pin.jsonl" "$W/sum-pin.json" "$W/done5" <<'PY' >> "$LOG" 2>&1 &
import json, os, socket, sys, time
sys.path.insert(0, ".")
import tamga_netproxy as tp
d = tp.load_net_decl(sys.argv[1])
assert d["_pinned"]["localhost"] == "127.0.0.1", "localhost not pinned to loopback"
p = tp.TamgaProxy(d, events_path=sys.argv[2])
port = p.start()
open(sys.argv[1] + ".port", "w").write(str(port))
_orig = socket.getaddrinfo
def _attacker(host, port=None, *a, **k):
    # Real rebinding model: NAME lookups are poisoned, IP-literal lookups pass.
    if host in ("localhost", "localhost."):
        return [(2, 1, 6, "", ("203.0.113.7", 0))]
    return _orig(host, port, *a, **k)
socket.getaddrinfo = _attacker
time.sleep(12)
socket.getaddrinfo = _orig
open(sys.argv[3], "w").write(json.dumps(p.summary()))
p.stop()
PY
wait_for "$W/net-pin.json.port" || { echo "  FAIL: pin proxy did not start"; exit 1; }
PPORT5=$(cat "$W/net-pin.json.port")
agent_connect "$PPORT5" "localhost:$EPORT5" "pin-stays" > "$W/pin.out" 2>> "$LOG"
grep -q "PROXY_STATUS:HTTP/1.1 200" "$W/pin.out" && grep -q "ECHO_MATCH:True" "$W/pin.out"
ok $? "D12-dns: attacker-resolver active, pinned endpoint still reaches the real host"
touch "$W/done5"; wait_for "$W/sum-pin.json"

# unresolvable endpoint -> declaration RED at load (fail-closed)
python3 - "$W/net-bad.json" <<'PY'
import json, sys
json.dump({"format": "tamga-net-declaration/1",
           "egress": ["no-such-host-tamga.invalid:443"],
           "max_bytes_per_run": 1048576, "timeout_s": 5}, open(sys.argv[1], "w"))
PY
python3 tamga_netproxy.py --decl "$W/net-bad.json" > "$W/bad.out" 2>> "$LOG"
[ $? -ne 0 ] && grep -q "cannot resolve" "$W/bad.out"
ok $? "D12-dns: unresolvable endpoint -> declaration RED at load (fail-closed)"

echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
[ "$FAIL" = "0" ]
cp -r "$W" /tmp/at006-keep 2>/dev/null; rm -rf "$W"
exit $((FAIL > 0))

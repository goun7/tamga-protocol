#!/usr/bin/env python3
"""tamga_net_shim.py — D13: agent-side network-request shim (RFC-006, founder-approved
2026-09-06). Streams a wasmtime child: reads the child's stdout line-by-line, detects
`TAMGA-NET-1` request lines, executes each over the TamgaProxy CONNECT tunnel
(SINGLE EDGE: the child itself never touches a socket), and writes one
`TAMGA-NET-RESP-1` line per request to the child's stdin. Non-request stdout is
written VERBATIM to the evidence artifact — request lines included (curating the
evidence file would be tampering). A net.json-less package gets agent requests
silently answered with net_shim_ignored (D4 silence preserved; counter reported).

Protocol (RFC-006 §2): request {"id","method","url","headers","body_b64"} ≤64KiB;
response {"id","ok",...}. One in-flight request; timeout = decl timeout_s.
"""
import base64
import http.client
import json
import os
import pathlib
import resource
import selectors
import socket
import ssl
import subprocess
import sys
import threading
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

MAX_REQ_BYTES = 64 * 1024
REQ_PREFIX = b"TAMGA-NET-1 "
RESP_PREFIX = "TAMGA-NET-RESP-1 "
_METHODS = {"GET", "POST", "PUT", "DELETE", "HEAD", "PATCH"}


def _respond(w, obj):
    try:
        w.write((RESP_PREFIX + json.dumps(obj, ensure_ascii=False,
                                          separators=(",", ":")) + "\n").encode("utf-8"))
        w.flush()
    except (BrokenPipeError, OSError):
        pass   # agent exited mid-request; evidence already holds its request line


def _exec_http(req, proxy, host_port, url_host, io_limit):
    """One HTTP round-trip over the tunnel -> (status, resp_headers_b64, body_b64)."""
    method = req.get("method", "GET").upper()
    if method not in _METHODS:
        raise ValueError("method_not_allowed")
    parsed = http.client.urlsplit(req["url"])
    if parsed.scheme not in ("http", "https"):
        raise ValueError("scheme_not_supported")
    path = parsed.path or "/"
    if parsed.query:
        path += "?" + parsed.query
    body = base64.b64decode(req["body_b64"]) if req.get("body_b64") else b""
    if len(body) > io_limit:
        raise ValueError("body_exceeds_io_limit")
    headers = {k: str(v) for k, v in (req.get("headers") or {}).items()}
    is_tls = parsed.scheme == "https"

    # CONNECT over the loopback tunnel (the single, policy-guarded edge)
    c = socket.create_connection(("127.0.0.1", proxy.port), timeout=proxy.timeout_s)
    try:
        c.sendall(f"CONNECT {host_port} HTTP/1.1\r\nHost: {host_port}\r\n\r\n".encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = c.recv(4096)
            if not chunk:
                raise ConnectionError("empty_connect_response")
            buf += chunk
        status_line = buf.split(b"\r\n", 1)[0].decode("latin-1")
        if " 200 " not in status_line + " ":
            raise ConnectionError("tunnel_denied:" + status_line.split(" ", 1)[-1][:40])
        sock = c
        if is_tls:
            ca = os.environ.get("TAMGA_NET_CA_BUNDLE")   # test-CA only via explicit env
            ctx = ssl.create_default_context(
                cafile=ca if ca and os.path.isfile(ca) else None)
            sock = ctx.wrap_socket(c, server_hostname=url_host)  # SNI = declared host
        conn = http.client.HTTPConnection(url_host, timeout=proxy.timeout_s)
        conn.sock = sock                              # inject the tunneled socket
        conn.request(method, path, body=body if method not in ("GET", "HEAD") else None,
                     headers=headers or None)
        r = conn.getresponse()
        rbody = r.read()
        rhdrs = json.dumps({k: v for k, v in r.getheaders()}).encode("utf-8")
        return r.status, base64.b64encode(rhdrs).decode("ascii"), rbody
    finally:
        try:
            c.close()
        except OSError:
            pass


def _pump(decl, proxy, art, proc, state, io_limit, net_capable=True):
    """Read child stdout; act on TAMGA-NET-1 lines; forward everything verbatim."""
    sel = selectors.DefaultSelector()
    sel.register(proc.stdout, selectors.EVENT_READ)
    buf = b""
    while not state["stop"]:
        for key, _ in sel.select(timeout=0.2):
            chunk = key.fileobj.read1(4096)
            if not chunk:
                state["eof"] = True
                return
            art.write(chunk)                       # evidence: verbatim, uncurated
            art.flush()
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                if not line.startswith(REQ_PREFIX):
                    continue
                if len(line) > MAX_REQ_BYTES:
                    state["inflight"] = False
                    _respond(proc.stdin, {"id": -1, "ok": False,
                                          "error": "request_too_large"})
                    continue
                if state["inflight"]:              # one in-flight request (RFC-006 §2)
                    _respond(proc.stdin, {"id": -1, "ok": False,
                                          "error": "request_while_inflight"})
                    continue
                state["inflight"] = True
                rid = -1
                try:
                    req = json.loads(line[len(REQ_PREFIX):].decode("utf-8"))
                    rid = req.get("id", -1)
                    host_port = req["url"].split("://", 1)[-1].split("/", 1)[0]
                    url_host = host_port.rsplit(":", 1)[0] if ":" in host_port else host_port
                    if decl is None or not net_capable:
                        # net.json-less (D4) OR legacy agent emitting a request line:
                        # silent drop — net capability requires the binary marker.
                        state["ignored"] += 1
                        _respond(proc.stdin, {"id": rid, "ok": False,
                                              "error": "net_shim_ignored"})
                        continue
                    t0 = time.monotonic()
                    st, rhdrs, rbody = _exec_http(req, proxy, host_port, url_host, io_limit)
                    proxy._log({"event": "net_request", "id": rid,
                                "url_host": url_host, "status": st,
                                "ms": round((time.monotonic() - t0) * 1000, 2)})
                    _respond(proc.stdin, {"id": rid, "ok": True, "status": st,
                                          "headers_b64": rhdrs,
                                          "body_b64": base64.b64encode(rbody).decode()})
                except Exception as e:             # soft path: shim errors don't kill the run
                    proxy._log({"event": "net_request", "id": rid,
                                "error": str(e)[:120]})
                    _respond(proc.stdin, {"id": rid, "ok": False,
                                          "error": str(e)[:120]})
                finally:
                    state["inflight"] = False


def run_streamed(argv, art_path, decl, proxy, timeout_s, io_limit, stdin_payload=None):
    """Spawn wasmtime with pipes and pump.
    Returns (rc, net_shim_ignored_count, timed_out).
    Agent capability sniffing (slice-4): if stdin_payload is present, the wasm
    binary is probed for the `TAMGA-NET-1 ` marker. Net-capable agents get the
    framed stdin contract (`TAMGA-STDIN-1 <len>\\n` + payload, stdin held open
    for response lines). Legacy agents (marker absent) get the D4-compatible
    byte-identical path: raw payload, stdin EOF immediately after — so agents
    that read stdin to EOF (like tc-a1) terminate instead of blocking forever."""
    art = open(art_path, "wb")
    state = {"inflight": False, "ignored": 0, "stop": False, "eof": False,
             "timed_out": False}
    net_capable = False
    if stdin_payload:
        try:
            wasm_idx = argv.index("run") + 1
            net_capable = b"TAMGA-NET-1 " in open(argv[wasm_idx], "rb").read()
        except (OSError, ValueError, IndexError):
            net_capable = False

    def _limits():
        resource.setrlimit(resource.RLIMIT_FSIZE, (io_limit, io_limit))

    proc = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, env={},
                            preexec_fn=_limits)   # Audit-3 F16 + Audit-9 B5 preserved
    timer = threading.Timer(timeout_s, lambda: state.update(stop=True, timed_out=True))
    timer.daemon = True
    timer.start()
    try:
        if proc.stdin and net_capable and stdin_payload is not None:
            frame = b"TAMGA-STDIN-1 %d\n" % len(stdin_payload) + stdin_payload
            proc.stdin.write(frame)
            proc.stdin.flush()      # net-capable: stdin held open for responses
        elif proc.stdin:
            if stdin_payload is not None:
                proc.stdin.write(stdin_payload)   # legacy: byte-identical D4 stdin
                proc.stdin.flush()
            proc.stdin.close()      # EOF NOW: legacy read_to_end agents terminate
            proc.stdin = None
        _pump(decl, proxy, art, proc, state, io_limit, net_capable=net_capable)
    finally:
        timer.cancel()
        try:
            if proc.stdin:
                proc.stdin.close()
        except OSError:
            pass
        try:
            rc = proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            rc = proc.wait()
        try:
            if proc.stdout:
                proc.stdout.close()
        except OSError:
            pass
        art.close()
    return rc, state["ignored"], state["timed_out"]

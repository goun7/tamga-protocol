#!/usr/bin/env python3
"""Tamga net proxy - RFC-005A slice-1 (M1 net.json reader, M2 egress proxy,
M3 policy engine, M4 byte counter).

Design contract (private/RFC-005A-vekil-uygulama-semasi.md):
- The declaration lives in <pkg>/net.json ("tamga-net-declaration/1"), NOT in the
  frozen v0.1 manifest. A package without net.json gets exactly the D4 behavior
  (no network) - this module is never started in that case.
- The proxy binds 127.0.0.1:<ephemeral>, one port per run, and acts as the single
  network edge. The wasmtime box itself stays socket-free; wiring the box to the
  proxy is slice-2 (wasi-sockets integration), not this module.
- Hard path (byte cap) vs soft path (per-operation timeout): exceeding
  max_bytes_per_run kills the connection and marks the session capped (the
  runner turns that into a run-level RED 11 in slice-2); a timeout kills only
  the affected connection and the run continues.

Known residual risk (honest note, slice-2 decision needed): a LISTED FQDN whose
DNS later rebinds to an attacker IP would be tunneled - the allow-list is
name-based and resolution happens at connect time from the operator's own
resolver. Slice-2 should pin resolved IPs at declaration load (connect by IP,
SNI preserved) or document the trust assumption explicitly.

Hardening notes (post-slice-1 adversarial self-review, 2026-09-06):
- timeout_s is an IDLE gap on a live connection (a slow streaming response
  survives; a silent endpoint is cut). It is NOT a total-duration limit - a
  total-duration policy is a slice-2 founder decision.
- Concurrent tunnels are capped (max_concurrent, default 32). Excess CONNECTs
  get 403 + net_denied(conn_limit), so a runaway agent cannot exhaust the
  proxy process with parallel connections.
- Header read is bounded (8KiB) and every connection thread is a daemon; a
  malformed request can never buffer beyond the cap.
- Half-close simplification: when either tunnel side ends, BOTH sockets close.
  Full TCP half-close semantics are a slice-2 refinement, not needed for the
  CONNECT usage pattern of slice-1.

CLI (for the slice-2 runner spawn and manual demos):
    python3 tamga_netproxy.py --decl <net.json> [--events <file>]
  prints one JSON line {"ok":true,"port":N,...} when listening, then serves
  until SIGTERM/SIGINT; on shutdown prints one JSON summary line.
"""

import argparse
import hashlib
import json
import os
import select
import signal
import socket
import sys
import threading
import time

NET_FORMAT = "tamga-net-declaration/1"
MAX_ENDPOINTS = 8
TIMEOUT_S_MIN, TIMEOUT_S_MAX = 1, 120
BYTES_MIN, BYTES_MAX = 1024, 8 * 1024 * 1024  # 1KiB .. 8MiB
HEADER_CAP = 8192
MiB = 1024 * 1024


class NetDeclError(ValueError):
    """net.json parse/validation failure (AT-006e family)."""


def _bad(msg):
    raise NetDeclError(msg)


def _check_endpoint(ep, idx):
    if not isinstance(ep, str) or not ep:
        _bad(f"egress[{idx}]: not a non-empty string")
    if "/" in ep or "@" in ep or " " in ep or "\\" in ep:
        _bad(f"egress[{idx}]: scheme/path/userinfo characters are not allowed")
    host, sep, port_s = ep.rpartition(":")
    if not sep or not host or not port_s:
        _bad(f"egress[{idx}]: expected host:port")
    if not port_s.isdigit():
        _bad(f"egress[{idx}]: port is not numeric")
    port = int(port_s)
    if not 1 <= port <= 65535:
        _bad(f"egress[{idx}]: port out of range")
    host = host.strip("[]").lower()  # brackets tolerated, IPv6 endpoints stay a v0.2 topic
    if len(host) > 253:
        _bad(f"egress[{idx}]: host too long")
    return f"{host}:{port}"


def load_net_decl(path):
    """Parse and validate net.json; returns the normalized declaration."""
    raw = open(path, "rb").read()  # read-only source; a declaration is host-authored
    if len(raw) > 64 * 1024:
        _bad("net.json > 64KiB: declaration files are tiny by design")
    try:
        d = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as e:
        _bad(f"net.json parse error: {e}")
    if not isinstance(d, dict):
        _bad("net.json: top level must be an object")
    if d.get("format") != NET_FORMAT:
        _bad(f"net.json: format must be {NET_FORMAT}")
    unknown = set(d) - {"format", "egress", "max_bytes_per_run", "timeout_s"}
    if unknown:
        _bad(f"net.json: unknown keys {sorted(unknown)} (strict schema)")
    egress = d.get("egress")
    if not isinstance(egress, list) or not (1 <= len(egress) <= MAX_ENDPOINTS):
        _bad(f"net.json: egress must be a list of 1..{MAX_ENDPOINTS} endpoints")
    endpoints = [_check_endpoint(e, i) for i, e in enumerate(egress)]
    if len(set(endpoints)) != len(endpoints):
        _bad("net.json: duplicate endpoints")
    mb = d.get("max_bytes_per_run")
    if not isinstance(mb, int) or isinstance(mb, bool) or not BYTES_MIN <= mb <= BYTES_MAX:
        _bad(f"net.json: max_bytes_per_run must be an int in [{BYTES_MIN}, {BYTES_MAX}]")
    ts = d.get("timeout_s")
    if not isinstance(ts, int) or isinstance(ts, bool) or not TIMEOUT_S_MIN <= ts <= TIMEOUT_S_MAX:
        _bad(f"net.json: timeout_s must be an int in [{TIMEOUT_S_MIN}, {TIMEOUT_S_MAX}]")
    return {"format": NET_FORMAT, "egress": endpoints,
            "max_bytes_per_run": mb, "timeout_s": ts,
            "_allowed": set(endpoints)}


def decl_sha256(path):
    """Receipt-side binding value (slice-2 stores this as net_decl_sha256)."""
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


class TamgaProxy:
    """Threaded HTTP-CONNECT loopback proxy with an exact host:port allow-list."""

    def __init__(self, decl, events_path=None, max_concurrent=32):
        self.allowed = decl["_allowed"]
        self.max_bytes = decl["max_bytes_per_run"]
        self.timeout_s = decl["timeout_s"]
        self.max_concurrent = max_concurrent
        self.events_path = events_path
        self._lock = threading.Lock()
        self._total = 0
        self._conns_ok = 0
        self._conns = 0
        self._denied = 0
        self.capped = False
        self._srv = None
        self._events = []
        self._stop = threading.Event()

    # ---- event log (M5 seed; 0600 file, JSONL) ----
    def _log(self, ev):
        ev["ts"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        with self._lock:
            self._events.append(ev)
        if self.events_path:
            line = (json.dumps(ev, separators=(",", ":")) + "\n").encode()
            try:
                fd = os.open(self.events_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
                with os.fdopen(fd, "ab") as f:
                    f.write(line)
            except OSError:
                pass

    def _add_bytes(self, n):
        with self._lock:
            self._total += n
            return self._total > self.max_bytes

    def summary(self):
        with self._lock:
            return {"net_mb": round(self._total / MiB, 2),
                    "bytes_total": self._total,
                    "connects_ok": self._conns_ok,
                    "denied": self._denied,
                    "capped": self.capped}

    # ---- server lifecycle ----
    def start(self):
        self._srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._srv.bind(("127.0.0.1", 0))   # loopback only, fresh port every run
        self._srv.listen(16)
        self._srv.settimeout(0.2)
        t = threading.Thread(target=self._accept_loop, daemon=True)
        t.start()
        return self._srv.getsockname()[1]

    def stop(self):
        self._stop.set()
        if self._srv:
            try:
                self._srv.close()
            except OSError:
                pass

    def _accept_loop(self):
        while not self._stop.is_set():
            try:
                c, _ = self._srv.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            threading.Thread(target=self._handle, args=(c,), daemon=True).start()

    # ---- per-connection policy (M3) ----
    def _handle(self, c):
        with self._lock:
            if self._conns >= self.max_concurrent:
                over = True
            else:
                over = False
                self._conns += 1
        if over:
            return self._deny(c, "?", "conn_limit")
        try:
            self._handle_gated(c)
        finally:
            with self._lock:
                self._conns -= 1

    def _handle_gated(self, c):
        try:
            c.settimeout(self.timeout_s)
            req = b""
            while b"\r\n\r\n" not in req and len(req) <= HEADER_CAP:
                try:
                    chunk = c.recv(4096)
                except socket.timeout:
                    return self._deny(c, "?", "timeout")
                if not chunk:
                    return
                req += chunk
            line = req.split(b"\r\n", 1)[0].decode("latin-1")
            parts = line.split()
            if len(parts) != 3 or parts[0].upper() != "CONNECT":
                return self._deny(c, "?", "bad_request")
            host_port = parts[1].lower()
            if self.capped:
                return self._deny(c, host_port, "byte_cap")
            if host_port not in self.allowed:
                return self._deny(c, host_port, "not_listed")
            host, _, port_s = host_port.rpartition(":")
            # DNS pinning antidote: the client may only NAME endpoints; resolution
            # happens here, after the list match, from the proxy's own resolver.
            try:
                infos = socket.getaddrinfo(host, int(port_s), socket.AF_INET, socket.SOCK_STREAM)
            except socket.gaierror:
                return self._deny(c, host_port, "dns_fail")
            addr = infos[0][4]
            try:
                up = socket.create_connection(addr, timeout=self.timeout_s)
            except OSError:
                return self._deny(c, host_port, "upstream_fail")
            c.sendall(b"HTTP/1.1 200 Connection established\r\n\r\n")
            with self._lock:
                self._conns_ok += 1
            self._tunnel(c, up, host_port)
        except (OSError, ValueError):
            try:
                c.close()
            except OSError:
                pass

    def _deny(self, c, host, reason):
        with self._lock:
            self._denied += 1
        self._log({"event": "net_denied", "host": host, "reason": reason})
        try:
            c.sendall(b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n")
            c.close()
        except OSError:
            pass

    # ---- byte-counted tunnel (M2 + M4) ----
    def _tunnel(self, c, up, host_port):
        t0 = time.monotonic()
        tx = rx = 0
        socks = [c, up]
        try:
            c.setblocking(False)
            up.setblocking(False)
            while True:
                r, _, _ = select.select(socks, [], [], self.timeout_s)
                if not r:
                    self._log({"event": "net_timeout", "host": host_port,
                               "ms": int((time.monotonic() - t0) * 1000)})
                    break
                for s in r:
                    try:
                        data = s.recv(65536)
                    except (BlockingIOError, InterruptedError):
                        continue
                    if not data:
                        socks = []  # peer half-closed; drain and stop
                        break
                    dst = up if s is c else c
                    n = len(data)
                    tx += n if s is c else 0
                    rx += n if s is not c else 0
                    if self._add_bytes(n):
                        self.capped = True
                        self._log({"event": "net_byte_cap", "host": host_port,
                                   "bytes_total": self.max_bytes + 1})
                        socks = []
                        break
                    # send in a blocking-friendly loop
                    dst.settimeout(self.timeout_s)
                    view = memoryview(data)
                    while view:
                        try:
                            sent = dst.send(view)
                        except (BlockingIOError, InterruptedError):
                            time.sleep(0.001)
                            continue
                        view = view[sent:]
                    dst.setblocking(False)
                if not socks:
                    break
        finally:
            for s in (c, up):
                try:
                    s.close()
                except OSError:
                    pass
        self._log({"event": "net_connect", "host": host_port, "ok": True,
                   "bytes_tx": tx, "bytes_rx": rx,
                   "ms": int((time.monotonic() - t0) * 1000)})


def main(argv=None):
    ap = argparse.ArgumentParser(description="Tamga loopback egress proxy (RFC-005A)")
    ap.add_argument("--decl", required=True, help="path to net.json")
    ap.add_argument("--events", default=None, help="JSONL event log path (0600)")
    ns = ap.parse_args(argv)
    try:
        decl = load_net_decl(ns.decl)
    except (NetDeclError, OSError) as e:
        print(json.dumps({"ok": False, "reason": f"net_decl_reject: {e}"}))
        return 2
    p = TamgaProxy(decl, events_path=ns.events)
    port = p.start()

    def _bye(*_):
        print(json.dumps({"ok": True, "summary": p.summary()}), flush=True)
        sys.exit(0)
    signal.signal(signal.SIGTERM, _bye)
    signal.signal(signal.SIGINT, _bye)
    print(json.dumps({"ok": True, "port": port, "egress": decl["egress"],
                      "max_bytes_per_run": decl["max_bytes_per_run"],
                      "timeout_s": decl["timeout_s"]}), flush=True)
    while True:
        time.sleep(3600)


if __name__ == "__main__":
    sys.exit(main())

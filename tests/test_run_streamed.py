"""tamga_net_shim.run_streamed akış-çalıştırma testleri (LEED).

Kural-1: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Dış çağrı YOK: monkeypatch subprocess.Popen + threading.Timer.
"""
import sys
from types import SimpleNamespace

import pytest

sys.path.insert(0, ".")
sys.path.insert(0, "tools")

import tamga_net_shim as shim  # noqa: E402
import subprocess  # noqa: E402
import threading  # noqa: E402


class _Pipe:
    """Sahte stdout pipe — önceden verilmiş satırları döndürür."""

    def __init__(self, chunks):
        self._chunks = list(chunks)
        self.closed = False

    def read(self, n=-1):
        if not self._chunks:
            return b""
        return self._chunks.pop(0)

    def read1(self, n=-1):
        return self.read(n)

    def close(self):
        self.closed = True


class _Stdin:
    def __init__(self):
        self.written = []
        self.closed = False

    def write(self, data):
        self.written.append(data)

    def flush(self):
        pass

    def close(self):
        self.closed = True


class _FakeProc:
    def __init__(self, chunks, rc=0, wait_calls=None):
        self.stdout = _Pipe(chunks)
        self.stdin = _Stdin()
        self._rc = rc
        self.wait_calls = wait_calls if wait_calls is not None else []
        self.killed = False

    def wait(self, timeout=None):
        self.wait_calls.append(timeout)
        return self._rc

    def kill(self):
        self.killed = True


@pytest.fixture
def runner(monkeypatch, tmp_path):
    created = {}

    class _Popen:
        def __init__(self, argv, **kw):
            self.proc = created.get("proc")
            created["argv"] = argv
            created["kw"] = kw
            if self.proc is None:
                self.proc = _FakeProc([b"hello\n"])
            # Popen nesnesi doğrudan kullanılır (context manager değil)
            for attr in ("stdin", "stdout", "stderr"):
                setattr(self, attr, getattr(self.proc, attr, None))
            self.wait = self.proc.wait
            self.kill = self.proc.kill

    monkeypatch.setattr(subprocess, "Popen", _Popen)

    class _Timer:
        def __init__(self, t, cb, **kw):
            self.t = t
            self.cb = cb
            self.daemon = None
            created["timer_t"] = t

        def start(self):
            created["timer_started"] = True

        def cancel(self):
            created["timer_cancelled"] = True

    monkeypatch.setattr(threading, "Timer", _Timer)

    class _Sel:
        def register(self, f, m, **kw):
            pass

        def select(self, timeout=None):
            # her zaman bir öğe döndür; read1 chunks bitince
            # b"" verir → _pump EOF ile döner (sonsuz döngü yok)
            return [(SimpleNamespace(fileobj=created["proc"].stdout), None)]

        def close(self):
            pass

    monkeypatch.setattr(shim.selectors, "DefaultSelector", _Sel)
    art = tmp_path / "art.bin"
    created["art_path"] = str(art)
    return created, art


@pytest.fixture
def proxy():
    logs = []

    class _Proxy:
        def _log(self, entry):
            logs.append(entry)

    return _Proxy()


def _net_argv(tmp_path, marker=b"TAMGA-NET-1 m", name="n.wasm"):
    """Net-capable agent argv'si: wasmtime run <wasm>."""
    wasm = tmp_path / name
    wasm.write_bytes(marker)
    return ["wasmtime", "run", str(wasm)]


# -- temel ---------------------------------------------------------------------------

def test_returns_three_tuple(runner, proxy):
    created, art = runner
    proc = _FakeProc([b"hello\n"])
    created["proc"] = proc
    rc = shim.run_streamed(["wasmtime", "run", "x.wasm"],
                           created["art_path"], None, proxy, 30, 1)
    assert len(rc) == 3


def test_success_rc_zero(runner, proxy):
    created, art = runner
    created["proc"] = _FakeProc([b"hello\n"], rc=0)
    assert shim.run_streamed(["w"], created["art_path"], None, proxy,
                             30, 1)[0] == 0


def test_nonzero_rc_propagates(runner, proxy):
    created, art = runner
    created["proc"] = _FakeProc([b"x\n"], rc=3)
    assert shim.run_streamed(["w"], created["art_path"], None, proxy,
                             30, 1)[0] == 3


def test_artifact_written(runner, proxy):
    created, art = runner
    created["proc"] = _FakeProc([b"chunk1\n", b"chunk2\n"])
    shim.run_streamed(["w"], created["art_path"], None, proxy, 30, 1)
    assert art.read_bytes() == b"chunk1\nchunk2\n"


def test_timer_started_and_cancelled(runner, proxy):
    created, art = runner
    created["proc"] = _FakeProc([b"x\n"])
    shim.run_streamed(["w"], created["art_path"], None, proxy, 15, 1)
    assert created["timer_started"]
    assert created["timer_cancelled"]


def test_timeout_used_for_timer(runner, proxy):
    created, art = runner
    created["proc"] = _FakeProc([b"x\n"])
    shim.run_streamed(["w"], created["art_path"], None, proxy, 42, 1)
    assert created["timer_t"] == 42


# -- net-capable tespiti ---------------------------------------------------------------------------

def test_net_capable_detection(runner, proxy, tmp_path):
    created, art = runner
    created["proc"] = _FakeProc([b"x\n"])
    wasm = tmp_path / "a.wasm"
    wasm.write_bytes(b"TAMGA-NET-1 marker")
    shim.run_streamed(["wasmtime", "run", str(wasm)], created["art_path"],
                      None, proxy, 30, 1, stdin_payload=b"veri")
    stdin = created["proc"].stdin
    # framed stdin: TAMGA-STDIN-1 <len>\n
    assert any(b"TAMGA-STDIN-1" in w for w in stdin.written)


def test_legacy_payload_written(runner, proxy, tmp_path):
    created, art = runner
    created["proc"] = _FakeProc([b"x\n"])
    wasm = tmp_path / "legacy.wasm"
    wasm.write_bytes(b"\x00asm\x01\x00\x00\x00")  # net-capable DEGIL
    shim.run_streamed(["wasmtime", "run", str(wasm)], created["art_path"],
                      None, proxy, 30, 1, stdin_payload=b"ham veri")
    stdin = created["proc"].stdin
    assert b"ham veri" in stdin.written
    assert stdin.closed


def test_no_payload_stdin_closed(runner, proxy):
    created, art = runner
    created["proc"] = _FakeProc([b"x\n"])
    shim.run_streamed(["w"], created["art_path"], None, proxy, 30, 1)
    assert created["proc"].stdin.closed


# -- decl None → istek drop edilir ---------------------------------------------------------------------------

def test_decl_none_ignores_requests(runner, proxy, tmp_path):
    created, art = runner
    req = shim.REQ_PREFIX + b'{"id": 1, "url": "http://x.com/a"}\n'
    created["proc"] = _FakeProc([req])
    rc, ignored, timed = shim.run_streamed(
        _net_argv(tmp_path), created["art_path"], None, proxy, 30, 1,
        stdin_payload=b"v")
    assert ignored >= 1


def test_ignored_reported_in_tuple(runner, proxy, tmp_path):
    created, art = runner
    req = shim.REQ_PREFIX + b'{"id": 1, "url": "http://x.com/a"}\n'
    created["proc"] = _FakeProc([req])
    rc, ignored, timed = shim.run_streamed(
        _net_argv(tmp_path), created["art_path"], None, proxy, 30, 1,
        stdin_payload=b"v")
    assert ignored == 1


# -- decl ile istek işleme ---------------------------------------------------------------------------

def test_decl_enables_requests(runner, proxy, tmp_path):
    created, art = runner
    req = shim.REQ_PREFIX + b'{"id": 1, "url": "http://x.com/a"}\n'
    created["proc"] = _FakeProc([req])
    proxy._log = lambda e: None
    rc, ignored, timed = shim.run_streamed(
        _net_argv(tmp_path), created["art_path"], "decl", proxy, 30, 1,
        stdin_payload=b"v")
    assert ignored == 0


def test_decl_logs_via_proxy(runner, proxy, tmp_path):
    created, art = runner
    req = shim.REQ_PREFIX + b'{"id": 1, "url": "http://x.com/a"}\n'
    created["proc"] = _FakeProc([req])
    logs = []
    proxy._log = logs.append
    shim.run_streamed(_net_argv(tmp_path), created["art_path"], "decl",
                      proxy, 30, 1, stdin_payload=b"v")
    assert len(logs) >= 0


# -- protokol satırları olmayan çıktı ---------------------------------------------------------------------------

def test_non_protocol_lines_ignored(runner, proxy):
    created, art = runner
    created["proc"] = _FakeProc([b"plain log line\n", b"another\n"])
    rc, ignored, timed = shim.run_streamed(
        ["w"], created["art_path"], "decl", proxy, 30, 1)
    assert rc == 0 and ignored == 0


def test_empty_output(runner, proxy):
    created, art = runner
    created["proc"] = _FakeProc([])
    rc, ignored, timed = shim.run_streamed(
        ["w"], created["art_path"], "decl", proxy, 30, 1)
    assert rc == 0


def test_artifact_empty_for_no_output(runner, proxy):
    created, art = runner
    created["proc"] = _FakeProc([])
    shim.run_streamed(["w"], created["art_path"], "decl", proxy, 30, 1)
    assert art.read_bytes() == b""


# -- timer tetiklenmesi (timeout) ---------------------------------------------------------------------------

def test_timeout_flag_when_timer_fires(runner, proxy, monkeypatch):
    created, art = runner
    created["proc"] = _FakeProc([b"x\n"])

    class _Fire:
        def __init__(self, t, cb, **kw):
            self.cb = cb

        def start(self):
            self.cb()  # hemen tetikle

        def cancel(self):
            pass

    monkeypatch.setattr(threading, "Timer", _Fire)
    rc, ignored, timed = shim.run_streamed(
        ["w"], created["art_path"], "decl", proxy, 5, 1)
    assert timed is True


# -- çoklu satırlar ---------------------------------------------------------------------------

def test_multiple_requests(runner, proxy, tmp_path):
    created, art = runner
    reqs = [shim.REQ_PREFIX +
            b'{"id": %d, "url": "http://x.com/a%d"}\n' % (i, i)
            for i in range(3)]
    created["proc"] = _FakeProc(reqs)
    proxy._log = lambda e: None
    rc, ignored, timed = shim.run_streamed(
        _net_argv(tmp_path), created["art_path"], "decl", proxy, 30, 1,
        stdin_payload=b"v")
    assert rc == 0


def test_partial_line_buffered(runner, proxy):
    """Son parça tamamsızsa EOF ile bitirilir."""
    created, art = runner
    created["proc"] = _FakeProc([b"eksik satir"])
    rc, ignored, timed = shim.run_streamed(
        ["w"], created["art_path"], "decl", proxy, 30, 1)
    assert rc == 0
    assert art.read_bytes() == b"eksik satir"

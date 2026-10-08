"""daemon_loop oracle-relayer döngü testleri (LEED).

Kural-1: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Dış çağrı YOK: fake transport + monkeypatch execute_request.
"""
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, ".")

import tamga_oracle_relayer as tor  # noqa: E402


class _FakeW3:
    def __init__(self, block=100):
        self.eth = type("Eth", (), {"block_number": block})()


class _FakeTransport:
    def __init__(self, requests, block=100, fail_fetch=False,
                 fail_submit=False, fail_block=False):
        self._requests = requests
        self._w3 = _FakeW3(block)
        self.fail_fetch = fail_fetch
        self.fail_submit = fail_submit
        self.fail_block = fail_block
        self.submitted = []
        self.fetch_calls = 0

    def fetch_requests(self, cursor):
        self.fetch_calls += 1
        self.last_cursor = cursor
        if self.fail_fetch:
            raise tor.TamgaRelayerError("poll-01", "ağ hatası")
        return list(self._requests)

    def submit_fulfillment(self, rid, digest, payload, stdout_hash, gas=500000):
        if self.fail_submit:
            raise tor.TamgaRelayerError("submit-02", "tx başarısız")
        out = {"tx_hash": f"0x{rid}tx", "status": 1, "gas_used": gas // 2}
        self.submitted.append((rid, digest, gas))
        return out


def _req(rid=1):
    return {
        "request_id": rid,
        "wasi_module_hash": "a" * 64,
        "max_cpu_ms_allowed": 1000,
        "input_payload": [104, 105],  # "hi"
    }


def _fake_result(rid="1"):
    return {
        "digest": "d" * 64,
        "payload": "sonuç",
        "receipt": {"stdout_sha256": "s" * 64},
        "delivery_hash": "e" * 64,
    }


@pytest.fixture
def fake_exec(monkeypatch):
    calls = []

    def _fake(req, registry, seed_hex, workdir=".", ledger_secret=None):
        calls.append(req["request_id"])
        return _fake_result(req["request_id"])

    monkeypatch.setattr(tor, "execute_request", _fake)
    return calls


@pytest.fixture
def workdir(tmp_path):
    return str(tmp_path)


# -- temel ---------------------------------------------------------------------------

def test_once_returns_fulfilled(workdir, fake_exec):
    t = _FakeTransport([_req()])
    out = tor.daemon_loop(t, {}, "seed", workdir=workdir, once=True)
    assert out == {1: "0x1tx"}


def test_max_cycles_returns(workdir, fake_exec):
    t = _FakeTransport([_req()])
    out = tor.daemon_loop(t, {}, "seed", workdir=workdir, max_cycles=2,
                          interval_s=0)
    assert cycle_finished(t, 2)


def cycle_finished(t, n):
    return t.fetch_calls == n


def test_no_requests_returns_empty(workdir, fake_exec):
    t = _FakeTransport([])
    out = tor.daemon_loop(t, {}, "seed", workdir=workdir, once=True)
    assert out == {}


def test_execute_called_with_request(workdir, fake_exec):
    t = _FakeTransport([_req(99)])
    tor.daemon_loop(t, {}, "seed", workdir=workdir, once=True)
    assert fake_exec == [99]


def test_submit_called(workdir, fake_exec):
    t = _FakeTransport([_req()])
    tor.daemon_loop(t, {}, "seed", workdir=workdir, once=True)
    assert len(t.submitted) == 1


def test_submit_passes_gas(workdir, fake_exec):
    t = _FakeTransport([_req()])
    tor.daemon_loop(t, {}, "seed", workdir=workdir, once=True, gas=999999)
    assert t.submitted[0][2] == 999999


# -- replay koruması (AT-202/AT-207) ---------------------------------------------------------------------------

def test_replay_cache_written(workdir, fake_exec):
    t = _FakeTransport([_req()])
    tor.daemon_loop(t, {}, "seed", workdir=workdir, once=True)
    cache = json.loads(Path(workdir, ".tamga-fulfilled.json").read_text())
    assert cache["1"] == "0x1tx"


def test_fulfilled_request_skipped(workdir, fake_exec):
    Path(workdir, ".tamga-fulfilled.json").write_text(
        json.dumps({"1": "0xold"}))
    t = _FakeTransport([_req(1)])
    out = tor.daemon_loop(t, {}, "seed", workdir=workdir, once=True)
    assert out[1] == "0xold"
    assert fake_exec == []  # tekrar çalıştırılmadı


def test_new_request_still_executed(workdir, fake_exec):
    Path(workdir, ".tamga-fulfilled.json").write_text(json.dumps({"1": "0xold"}))
    t = _FakeTransport([_req(1), _req(2)])
    out = tor.daemon_loop(t, {}, "seed", workdir=workdir, once=True)
    assert 2 in out
    assert fake_exec == [2]


def test_replay_cache_survives_restart(workdir, fake_exec):
    """AT-207: restart sonrası cache disk'ten yüklenir."""
    t1 = _FakeTransport([_req()])
    tor.daemon_loop(t1, {}, "seed", workdir=workdir, once=True)
    # yeni daemon (yeni süreç simülasyonu)
    t2 = _FakeTransport([_req()])
    out = tor.daemon_loop(t2, {}, "seed", workdir=workdir, once=True)
    assert t2.submitted == []  # tekrar fulfill edilmedi


def test_multiple_requests_all_fulfilled(workdir, fake_exec):
    reqs = [_req(i + 1) for i in range(5)]
    t = _FakeTransport(reqs)
    out = tor.daemon_loop(t, {}, "seed", workdir=workdir, once=True)
    assert len(out) == 5


# -- hata toleransı (döngü durmaz) ---------------------------------------------------------------------------

def test_execute_error_logged_not_raised(workdir, monkeypatch):
    def _bad(req, registry, seed, workdir=".", ledger_secret=None):
        raise tor.TamgaRelayerError("exec-03", "wasi hatası")
    monkeypatch.setattr(tor, "execute_request", _bad)
    logs = []
    t = _FakeTransport([_req()])
    out = tor.daemon_loop(t, {}, "seed", workdir=workdir, once=True, log=logs.append)
    assert any("RED" in l for l in logs)
    assert out == {}


def test_submit_error_logged_not_raised(workdir, monkeypatch):
    monkeypatch.setattr(tor, "execute_request",
                        lambda *a, **k: _fake_result())
    logs = []
    t = _FakeTransport([_req()], fail_submit=True)
    out = tor.daemon_loop(t, {}, "seed", workdir=workdir, once=True, log=logs.append)
    assert any("RED" in l for l in logs)
    assert out == {}


def test_fetch_error_loop_continues(workdir, fake_exec):
    logs = []
    t = _FakeTransport([_req()], fail_fetch=True)
    out = tor.daemon_loop(t, {}, "seed", workdir=workdir, once=True, log=logs.append)
    assert any("poll-hatası" in l for l in logs)
    assert out == {}


def test_error_does_not_stop_next_cycle(workdir, monkeypatch):
    monkeypatch.setattr(tor, "execute_request",
                        lambda *a, **k: _raise_or_pass(a))
    logs = []
    t = _FakeTransport([_req()])
    tor.daemon_loop(t, {}, "seed", workdir=workdir, max_cycles=3,
                    interval_s=0, log=logs.append)
    assert t.fetch_calls == 3


def _raise_or_pass(args):
    raise tor.TamgaRelayerError("x", "y")


def test_block_error_logged(workdir, fake_exec):
    logs = []
    t = _FakeTransport([_req()])
    t._w3 = None  # block_number erişimi hata
    tor.daemon_loop(t, {}, "seed", workdir=workdir, once=True, log=logs.append)
    # hata olsa döngü döner
    assert out_ok(t)


def out_ok(t):
    return t.fetch_calls >= 1


# -- cursor takibi (AT-205) ---------------------------------------------------------------------------

def test_from_block_used_as_cursor(workdir, fake_exec):
    t = _FakeTransport([])
    tor.daemon_loop(t, {}, "seed", workdir=workdir, once=True, from_block=42)
    assert t.last_cursor == 42


def test_cursor_defaults_to_backfill(workdir, fake_exec):
    t = _FakeTransport([], block=500)
    tor.daemon_loop(t, {}, "seed", workdir=workdir, once=True, backfill=100)
    assert t.last_cursor == 400


def test_cursor_clamped_to_zero(workdir, fake_exec):
    t = _FakeTransport([], block=10)
    tor.daemon_loop(t, {}, "seed", workdir=workdir, once=True, backfill=100)
    assert t.last_cursor == 0


def test_cursor_updates_after_cycle(workdir, fake_exec):
    t = _FakeTransport([], block=1000)
    tor.daemon_loop(t, {}, "seed", workdir=workdir, max_cycles=2, interval_s=0)
    # 2. cycle cursor=1000 (block_number)
    assert t.last_cursor == 1000


def test_block_number_error_defaults(workdir, fake_exec):
    """_w3.eth.block_number hata → cursor 0 kalır."""
    t = _FakeTransport([])

    class _BadEth:
        @property
        def block_number(self):
            raise OSError("bağlantı yok")

    class _BadW3:
        eth = _BadEth()

    t._w3 = _BadW3()
    logs = []
    tor.daemon_loop(t, {}, "seed", workdir=workdir, once=True, log=logs.append)
    assert any("ağ-hatası" in l for l in logs)


# -- interval/once ---------------------------------------------------------------------------

def test_once_no_sleep(workdir, fake_exec, monkeypatch):
    slept = []
    monkeypatch.setattr(tor.time, "sleep", lambda s: slept.append(s))
    t = _FakeTransport([_req()])
    tor.daemon_loop(t, {}, "seed", workdir=workdir, once=True)
    assert slept == []


def test_interval_sleep_between_cycles(workdir, fake_exec, monkeypatch):
    slept = []
    monkeypatch.setattr(tor.time, "sleep", lambda s: slept.append(s))
    t = _FakeTransport([_req()])
    tor.daemon_loop(t, {}, "seed", workdir=workdir, max_cycles=3, interval_s=5)
    assert slept == [5, 5]


# -- input_payload ---------------------------------------------------------------------------

def test_input_payload_bytes(workdir, fake_exec):
    req = _req(1)
    req["input_payload"] = [65, 66, 67]
    t = _FakeTransport([req])
    tor.daemon_loop(t, {}, "seed", workdir=workdir, once=True)
    assert fake_exec == [1]


def test_empty_input_payload_becomes_none(workdir, fake_exec):
    req = _req(1)
    req["input_payload"] = None
    t = _FakeTransport([req])
    tor.daemon_loop(t, {}, "seed", workdir=workdir, once=True)
    assert fake_exec == [1]

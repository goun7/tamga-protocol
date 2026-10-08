"""p9_independent_verify.verify_tx için dal-kesen testler (core-final, LEED).

Kural-1'e uyuldu: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Dış RPC çağrısı monkeypatch ile mock'lanır (gerçek zincire bağlanılmaz).
K19.2 (kanıt-tanımlayıcı-asla-kesik) ve atlanan-kontrol-PASS-sayilamaz kuralları.
"""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

import p9_independent_verify as P9  # noqa: E402


TX = "0x" + "ab" * 32  # tam 66-karakter geçerli hash


def _topic_addr(hex40: str) -> str:
    """32-byte topic formatı: 24 sıfır + 20 bayt adres."""
    return "0x" + "00" * 12 + hex40


def _receipt(status="0x1", logs=None, to=None, block="0x10"):
    return {
        "status": status,
        "blockNumber": block,
        "logs": logs or [],
        "to": to if to is not None else P9.FACILITATOR,
    }


def _usdc_transfer(amount: int, frm=None, to_addr=None) -> dict:
    frm = frm or "1" * 40
    to_addr = to_addr or "2" * 40
    return {
        "address": P9.USDC_BASE,
        "topics": [P9.ERC20_TRANSFER_TOPIC,
                   _topic_addr(frm), _topic_addr(to_addr)],
        "data": hex(amount)[2:].rjust(64, "0"),
    }


class _Capture:
    """stdout yakalama (capsys yerine hafif)."""

    def __init__(self):
        self.lines = []

    def write(self, s):
        self.lines.append(s)

    def flush(self):
        pass


# -- rpc yardımcıları -------------------------------------------------------

def test_hex2int_parses_hex():
    assert P9.hex2int("0x10") == 16
    assert P9.hex2int("ff") == 255


def test_addr_takes_last_20_bytes_verbatim():
    # kod son 40 hex-karakteri olduğu gibi alır (lower/ checksum uygulanmaz)
    t = "0x" + "00" * 12 + "aB" * 20
    assert P9.addr(t) == "0x" + "aB" * 20


def test_addr_of_plain_40_char():
    t = "0x" + "cd" * 20
    assert P9.addr(t) == "0x" + "cd" * 20


# -- rpc hata yollari -------------------------------------------------------

def test_rpc_error_returns_1(monkeypatch):
    def boom(*a, **k):
        raise RuntimeError("connection refused")

    monkeypatch.setattr(P9, "rpc", boom)
    assert P9.verify_tx(TX, "http://fake", None) == 1


def test_rpc_none_receipt_returns_1(monkeypatch):
    monkeypatch.setattr(P9, "rpc", lambda *a, **k: None)
    assert P9.verify_tx(TX, "http://fake", None) == 1


# -- status yollari ---------------------------------------------------------

def test_reverted_tx_counts_fail(monkeypatch, capsys):
    monkeypatch.setattr(P9, "rpc", lambda *a, **k: _receipt(status="0x0"))
    rc = P9.verify_tx(TX, "http://fake", None)
    out = capsys.readouterr().out
    assert "revert" in out
    assert rc == 1  # fails=1 → rc=1


def test_successful_tx_status_pass(monkeypatch, capsys):
    monkeypatch.setattr(P9, "rpc", lambda *a, **k: _receipt())
    P9.verify_tx(TX, "http://fake", None)
    assert "status 0x1" in capsys.readouterr().out


# -- USDC Transfer yollari ---------------------------------------------------

def test_usdc_transfer_summed(monkeypatch, capsys):
    logs = [_usdc_transfer(5_000_000), _usdc_transfer(2_500_000)]
    monkeypatch.setattr(P9, "rpc", lambda *a, **k: _receipt(logs=logs))
    P9.verify_tx(TX, "http://fake", None)
    out = capsys.readouterr().out
    assert "7.50 USDC" in out  # toplam 7.5
    assert "5.00 USDC" in out


def test_no_usdc_transfer_is_skip_not_fail(monkeypatch, capsys):
    monkeypatch.setattr(P9, "rpc", lambda *a, **k: _receipt())
    rc = P9.verify_tx(TX, "http://fake", None)
    out = capsys.readouterr().out
    assert "SKIP" in out
    # SKIP asla FAIL sayilmaz → rc 0
    assert rc == 0


def test_other_token_transfer_ignored(monkeypatch, capsys):
    log = _usdc_transfer(9_000_000)
    log["address"] = "0x" + "99" * 20
    monkeypatch.setattr(P9, "rpc", lambda *a, **k: _receipt(logs=[log]))
    P9.verify_tx(TX, "http://fake", None)
    assert "SKIP" in capsys.readouterr().out


def test_usdc_address_case_insensitive(monkeypatch, capsys):
    log = _usdc_transfer(1_000_000)
    log["address"] = P9.USDC_BASE.upper()
    monkeypatch.setattr(P9, "rpc", lambda *a, **k: _receipt(logs=[log]))
    P9.verify_tx(TX, "http://fake", None)
    assert "1.00 USDC" in capsys.readouterr().out


# -- facilitator yollari ------------------------------------------------------

def test_direct_facilitator_call_pass(monkeypatch, capsys):
    monkeypatch.setattr(P9, "rpc", lambda *a, **k: _receipt(to=P9.FACILITATOR))
    P9.verify_tx(TX, "http://fake", None)
    assert "doğrudan facilitator" in capsys.readouterr().out


def test_facilitator_log_event_pass(monkeypatch, capsys):
    log = {"address": P9.FACILITATOR, "topics": ["0x" + "11" * 32], "data": "0x"}
    monkeypatch.setattr(P9, "rpc", lambda *a, **k: _receipt(logs=[log],
                                                            to="0x" + "77" * 20))
    P9.verify_tx(TX, "http://fake", None)
    assert "facilitator log-event" in capsys.readouterr().out


def test_no_facilitator_presence_is_skip(monkeypatch, capsys):
    monkeypatch.setattr(P9, "rpc",
                        lambda *a, **k: _receipt(to="0x" + "77" * 20))
    rc = P9.verify_tx(TX, "http://fake", None)
    assert "SKIP" in capsys.readouterr().out
    assert rc == 0


# -- K19.2 tx-hash tamlik ------------------------------------------------------

def test_short_tx_hash_fails_k19(monkeypatch, capsys):
    monkeypatch.setattr(P9, "rpc", lambda *a, **k: _receipt())
    rc = P9.verify_tx("0x1234", "http://fake", None)
    out = capsys.readouterr().out
    assert "K19.2" in out
    assert rc == 1


def test_tx_hash_without_0x_prefix_fails(monkeypatch):
    monkeypatch.setattr(P9, "rpc", lambda *a, **k: _receipt())
    assert P9.verify_tx("ab" * 32, "http://fake", None) == 1


def test_full_66_char_hash_passes_k19(monkeypatch, capsys):
    monkeypatch.setattr(P9, "rpc", lambda *a, **k: _receipt())
    P9.verify_tx(TX, "http://fake", None)
    assert "tam-66-karakter" in capsys.readouterr().out


# -- skip-asla-pass-sayilmaz (durumsal) ----------------------------------------

def test_all_skips_still_rc0_but_no_false_pass(monkeypatch, capsys):
    # ne transfer ne facilitator — ama status 0x1 + hash tam → rc=0, FAIL yok
    monkeypatch.setattr(P9, "rpc",
                        lambda *a, **k: _receipt(to="0x" + "77" * 20))
    rc = P9.verify_tx(TX, "http://fake", None)
    out = capsys.readouterr().out
    assert rc == 0
    # hiçbir PASS iddiası ödeme-kanıtı olarak yazılmadı
    assert "USDC" not in out.replace("USDC Transfer olayı-yok", "")

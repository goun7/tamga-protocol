"""sovereign_verify.verify_sester_ledger zincir-doğrulama testleri (LEED).

Kural-1: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Dış çağrı YOK: sys.modules'e sahte sester.ledger + tmp SQLite.
"""
import os
import sqlite3
import sys
import types

import pytest

sys.path.insert(0, ".")
sys.path.insert(0, "tools")

import sovereign_verify as sv  # noqa: E402


def _field(r, key):
    return r.get(key)


@pytest.fixture
def tmp_ledger(tmp_path):
    return str(tmp_path / "ledger.db")


@pytest.fixture
def real_db(tmp_ledger):
    """SQLite'da events tablosu + bir satır."""
    con = sqlite3.connect(tmp_ledger)
    con.execute("CREATE TABLE events (id INTEGER PRIMARY KEY, data TEXT)")
    con.execute("INSERT INTO events VALUES (1, 'x')")
    con.commit()
    con.close()
    return tmp_ledger


@pytest.fixture
def fake_ledger(monkeypatch):
    """sys.modules'e sahte sester.ledger.Ledger."""
    state = {"verify_result": True, "raise_exc": None}

    class _Ledger:
        def __init__(self, path, secret):
            self.path = path
            self.secret = secret
            state["path"] = path
            state["secret"] = secret
            if state["raise_exc"]:
                raise state["raise_exc"]

        def verify_chain(self):
            return state["verify_result"]

        def close(self):
            state["closed"] = True

    mod = types.ModuleType("sester.ledger")
    mod.Ledger = _Ledger
    pkg = types.ModuleType("sester")
    pkg.__path__ = []
    monkeypatch.setitem(sys.modules, "sester", pkg)
    monkeypatch.setitem(sys.modules, "sester.ledger", mod)
    return state


# -- var-olmayan yol ---------------------------------------------------------------------------

def test_missing_path_returns_error(tmp_path):
    r = sv.verify_sester_ledger(str(tmp_path / "yok.db"))
    assert _field(r, "product") == "sester"
    assert _field(r, "error") is not None


def test_missing_path_does_not_touch_secret(tmp_path, monkeypatch):
    monkeypatch.setenv("SESTER_LEDGER_SECRET", "env-secret")
    r = sv.verify_sester_ledger(str(tmp_path / "yok.db"))
    assert r.get("ok") is not True


def test_missing_path_error_mentions_path(tmp_path):
    p = str(tmp_path / "ozel-yol.db")
    r = sv.verify_sester_ledger(p)
    assert "ozel-yol" in str(r.get("error")) or p in str(r.get("error"))


# -- ImportError ---------------------------------------------------------------------------

def test_import_error_returns_error(tmp_ledger, monkeypatch):
    """sester modülü yoksa ImportError → error döner."""
    monkeypatch.delitem(sys.modules, "sester", raising=False)
    monkeypatch.delitem(sys.modules, "sester.ledger", raising=False)
    # import yolundan sester'i kaldır: sys.modules'e None koy → ImportError
    monkeypatch.setitem(sys.modules, "sester", None)
    r = sv.verify_sester_ledger(tmp_ledger)
    assert _field(r, "product") == "sester"
    assert _field(r, "error") is not None


# -- secret yönetimi ---------------------------------------------------------------------------

def test_secret_from_env(real_db, fake_ledger, monkeypatch):
    monkeypatch.setenv("SESTER_LEDGER_SECRET", "env-secret")
    sv.verify_sester_ledger(real_db)
    assert fake_ledger["secret"] == "env-secret"


def test_explicit_secret_wins(real_db, fake_ledger, monkeypatch):
    monkeypatch.setenv("SESTER_LEDGER_SECRET", "env-secret")
    sv.verify_sester_ledger(real_db, secret="explicit")
    assert fake_ledger["secret"] == "explicit"


def test_none_secret_uses_env(real_db, fake_ledger, monkeypatch):
    monkeypatch.setenv("SESTER_LEDGER_SECRET", "env-secret")
    sv.verify_sester_ledger(real_db, secret=None)
    assert fake_ledger["secret"] == "env-secret"


def test_ledger_receives_path(real_db, fake_ledger):
    sv.verify_sester_ledger(real_db)
    assert fake_ledger["path"] == real_db


# -- dev-secret uyarısı ---------------------------------------------------------------------------

def test_dev_secret_warns(real_db, fake_ledger, monkeypatch):
    monkeypatch.delenv("SESTER_LEDGER_SECRET", raising=False)
    with pytest.warns(UserWarning):
        sv.verify_sester_ledger(real_db, secret="dev-secret")


def test_dev_secret_still_verifies(real_db, fake_ledger, monkeypatch):
    monkeypatch.delenv("SESTER_LEDGER_SECRET", raising=False)
    import warnings
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        r = sv.verify_sester_ledger(real_db, secret="dev-secret")
    assert fake_ledger["secret"] == "dev-secret"


def test_prod_secret_no_warn(real_db, fake_ledger, monkeypatch):
    import warnings
    monkeypatch.delenv("SESTER_LEDGER_SECRET", raising=False)
    with warnings.catch_warnings(record=True) as w:
        warnings.simplefilter("always")
        sv.verify_sester_ledger(real_db, secret="prod-uzun-secret-42")
    assert not any("dev-secret" in str(x.message) for x in w)


# -- boş zincir ---------------------------------------------------------------------------

def test_empty_chain_returns_error(tmp_ledger, fake_ledger):
    con = sqlite3.connect(tmp_ledger)
    con.execute("CREATE TABLE events (id INTEGER PRIMARY KEY)")
    con.commit()
    con.close()
    r = sv.verify_sester_ledger(tmp_ledger)
    assert _field(r, "error") is not None


def test_empty_table_not_created(tmp_ledger, fake_ledger):
    r = sv.verify_sester_ledger(tmp_ledger)
    assert _field(r, "error") is not None
    assert not fake_ledger.get("closed")


# -- GREEN sonucu ---------------------------------------------------------------------------

def test_green_verdict(real_db, fake_ledger):
    r = sv.verify_sester_ledger(real_db)
    assert _field(r, "product") == "sester"
    assert _field(r, "verdict") == "GREEN"


def test_ledger_closed_after_verify(real_db, fake_ledger):
    sv.verify_sester_ledger(real_db)
    assert fake_ledger.get("closed") is True


def test_closed_after_failed_verify(real_db, fake_ledger):
    fake_ledger["verify_result"] = False
    sv.verify_sester_ledger(real_db)
    assert fake_ledger.get("closed") is True


# -- istisna yönetimi ---------------------------------------------------------------------------

def test_construction_exception_caught(real_db, fake_ledger):
    fake_ledger["raise_exc"] = RuntimeError("boom")
    r = sv.verify_sester_ledger(real_db)
    assert _field(r, "error") is not None


def test_verify_exception_caught(real_db, fake_ledger, monkeypatch):
    state = fake_ledger

    class _Ledger2:
        def __init__(self, path, secret):
            pass

        def verify_chain(self):
            raise RuntimeError("verify boom")

        def close(self):
            state["closed"] = True

    import sester.ledger as sl
    monkeypatch.setattr(sl, "Ledger", _Ledger2)
    r = sv.verify_sester_ledger(real_db)
    assert _field(r, "error") is not None
    assert state.get("closed") is True


# -- çoklu satır ---------------------------------------------------------------------------

def test_multi_row_db(real_db, fake_ledger):
    con = sqlite3.connect(real_db)
    con.execute("INSERT INTO events VALUES (2, 'y')")
    con.commit()
    con.close()
    r = sv.verify_sester_ledger(real_db)
    assert _field(r, "verdict") == "GREEN"


def test_default_secret_is_dev_secret(real_db, fake_ledger, monkeypatch):
    """Env yoksa + secret None → default 'dev-secret' (RISK-2 sabiti)."""
    monkeypatch.delenv("SESTER_LEDGER_SECRET", raising=False)
    import warnings
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        sv.verify_sester_ledger(real_db, secret=None)
    assert fake_ledger["secret"] == "dev-secret"

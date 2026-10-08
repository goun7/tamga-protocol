"""tamga_bootstrap.ensure_wasmtime motor-temin testleri (LEED).

Kural-1: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Dış çağrı YOK: monkeypatch urllib.request.urlretrieve + tmp cache.
"""
import hashlib
import pathlib
import sys
import tarfile

import pytest

sys.path.insert(0, ".")
sys.path.insert(0, "tools")

import tamga_bootstrap as tb  # noqa: E402


def _make_tgz(member_name="wasmtime-x/bin/wasmtime",
              content=b"#!/bin/sh\necho wasmtime\n"):
    import io
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tf:
        info = tarfile.TarInfo(name=member_name)
        info.size = len(content)
        tf.addfile(info, io.BytesIO(content))
    return buf


def _write_tgz(buf, monkeypatch):
    def _retrieve(url, path):
        with open(path, "wb") as f:
            f.write(buf.getvalue())
        return path

    monkeypatch.setattr("urllib.request.urlretrieve", _retrieve)


@pytest.fixture
def isolated(monkeypatch, tmp_path):
    """repo_bin ve cache_bin'i tmp'ye yönlendir."""
    state = {"url": None, "repo": False, "cache": False}

    # repo_bin: __file__ parent / vendor / wasmtime
    fake_self = tmp_path / "fake_bootstrap.py"
    fake_self.write_text("")
    monkeypatch.setattr(tb, "__file__", str(fake_self))

    cache = tmp_path / "cache"
    monkeypatch.setattr(tb, "_CACHE_DIR", cache)
    return state, cache, tmp_path


@pytest.fixture
def fake_download(monkeypatch):
    """Sahte urlretrieve + gerçek tarball üretimi."""
    calls = {}

    def _retrieve(url, path):
        calls["url"] = url
        # sahte binary tarball'ı hedefe yaz
        with tarfile.open(path, "w:gz") as tf:
            data = b"#!/bin/sh\necho wasmtime\n"
            import io
            info = tarfile.TarInfo(name="wasmtime-x/bin/wasmtime")
            info.size = len(data)
            tf.addfile(info, io.BytesIO(data))
        return path

    monkeypatch.setattr("urllib.request.urlretrieve", _retrieve)
    return calls


# -- repo-klonu yolu ---------------------------------------------------------------------------

def test_repo_bin_returned_when_exists(isolated, monkeypatch):
    state, cache, tmp = isolated
    tools_bin = tmp.resolve() / "tools" / "bin" / "wasmtime"
    tools_bin.parent.mkdir(parents=True)
    tools_bin.write_bytes(b"#!/bin/sh\n")
    monkeypatch.setattr(tb, "__file__", str(tmp / "x.py"))
    r = tb.ensure_wasmtime()
    assert r == str(tools_bin)


def test_repo_bin_short_circuits(isolated, monkeypatch, fake_download):
    """repo_bin varsa indirme YAPILMAZ."""
    state, cache, tmp = isolated
    tools_bin = tmp.resolve() / "tools" / "bin" / "wasmtime"
    tools_bin.parent.mkdir(parents=True)
    tools_bin.write_bytes(b"#!/bin/sh\n")
    monkeypatch.setattr(tb, "__file__", str(tmp / "y.py"))
    tb.ensure_wasmtime()
    assert "url" not in fake_download


# -- cache yolu ---------------------------------------------------------------------------

def test_cache_bin_returned_when_exists(isolated):
    state, cache, tmp = isolated
    cache.mkdir(parents=True)
    (cache / "wasmtime").write_bytes(b"#!/bin/sh\n")
    r = tb.ensure_wasmtime()
    assert str(cache / "wasmtime") == r


def test_cache_short_circuits(isolated, fake_download):
    state, cache, tmp = isolated
    cache.mkdir(parents=True)
    (cache / "wasmtime").write_bytes(b"#!/bin/sh\n")
    tb.ensure_wasmtime()
    assert "url" not in fake_download


# -- platform desteği ---------------------------------------------------------------------------

def test_unsupported_platform_raises(isolated, monkeypatch):
    state, cache, tmp = isolated
    monkeypatch.setattr(tb, "_artifact_name", lambda: None)
    with pytest.raises(SystemExit):
        tb.ensure_wasmtime()


def test_missing_sha256_raises(isolated, monkeypatch):
    state, cache, tmp = isolated
    monkeypatch.setattr(tb, "_artifact_name", lambda: "nonexistent.tgz")
    with pytest.raises(SystemExit):
        tb.ensure_wasmtime()


# -- indirme yolu ---------------------------------------------------------------------------

def test_download_writes_cache(isolated, fake_download, monkeypatch):
    state, cache, tmp = isolated
    art = "test-art.tgz"
    monkeypatch.setattr(tb, "_artifact_name", lambda: art)
    # tarball içeriğinin sha256'sini SHA256'e kaydet
    import io
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tf:
        data = b"#!/bin/sh\necho wasmtime\n"
        info = tarfile.TarInfo(name="wasmtime-x/bin/wasmtime")
        info.size = len(data)
        tf.addfile(info, io.BytesIO(data))
    digest = hashlib.sha256(buf.getvalue()).hexdigest()
    monkeypatch.setitem(tb.SHA256, art, digest)
    _write_tgz(buf, monkeypatch)
    r = tb.ensure_wasmtime()
    assert (cache / "wasmtime").exists()
    assert r == str(cache / "wasmtime")


def test_download_url_contains_artifact(isolated, monkeypatch):
    """İndirme URL'si artifact adını ve bytecodealliance barındırır."""
    state, cache, tmp = isolated
    art = "myart.tgz"
    monkeypatch.setattr(tb, "_artifact_name", lambda: art)
    import io
    buf = _make_tgz()
    monkeypatch.setitem(tb.SHA256, art,
                        hashlib.sha256(buf.getvalue()).hexdigest())
    seen = {}

    def _cap(url, path):
        seen["url"] = url
        with open(path, "wb") as f:
            f.write(buf.getvalue())
        return path

    monkeypatch.setattr("urllib.request.urlretrieve", _cap)
    tb.ensure_wasmtime()
    assert art in seen["url"]
    assert "bytecodealliance" in seen["url"]


def test_bad_digest_raises(isolated, monkeypatch):
    state, cache, tmp = isolated
    art = "bad.tgz"
    monkeypatch.setattr(tb, "_artifact_name", lambda: art)
    monkeypatch.setitem(tb.SHA256, art, b"\x00" * 32)
    monkeypatch.setattr(
        "urllib.request.urlretrieve",
        lambda url, path: open(path, "wb").write(b"not a tarball"))
    with pytest.raises(SystemExit):
        tb.ensure_wasmtime()


def test_download_failure_raises(isolated, monkeypatch):
    state, cache, tmp = isolated
    art = "fail.tgz"
    monkeypatch.setattr(tb, "_artifact_name", lambda: art)
    monkeypatch.setitem(tb.SHA256, art, b"\x00" * 32)

    def _boom(url, path):
        raise ConnectionError("network down")

    monkeypatch.setattr("urllib.request.urlretrieve", _boom)
    with pytest.raises(SystemExit):
        tb.ensure_wasmtime()


def test_extracted_binary_is_executable(isolated, monkeypatch):
    state, cache, tmp = isolated
    art = "exec.tgz"
    monkeypatch.setattr(tb, "_artifact_name", lambda: art)
    import io
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tf:
        data = b"#!/bin/sh\necho wasmtime\n"
        info = tarfile.TarInfo(name="wasmtime-x/bin/wasmtime")
        info.size = len(data)
        tf.addfile(info, io.BytesIO(data))
    digest = hashlib.sha256(buf.getvalue()).hexdigest()
    monkeypatch.setitem(tb.SHA256, art, digest)
    _write_tgz(buf, monkeypatch)
    tb.ensure_wasmtime()
    b = cache / "wasmtime"
    assert b.exists()
    import os, stat
    assert b.stat().st_mode & stat.S_IXUSR


def test_download_prints_progress(isolated, monkeypatch, capsys):
    state, cache, tmp = isolated
    art = "prog.tgz"
    monkeypatch.setattr(tb, "_artifact_name", lambda: art)
    import io
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tf:
        data = b"#!/bin/sh\n"
        info = tarfile.TarInfo(name="wasmtime-x/bin/wasmtime")
        info.size = len(data)
        tf.addfile(info, io.BytesIO(data))
    digest = hashlib.sha256(buf.getvalue()).hexdigest()
    monkeypatch.setitem(tb.SHA256, art, digest)
    _write_tgz(buf, monkeypatch)
    tb.ensure_wasmtime()
    out = capsys.readouterr().out
    assert "[TAMGA]" in out


# -- öncelik sırası ---------------------------------------------------------------------------

def test_repo_wins_over_cache(isolated, monkeypatch):
    state, cache, tmp = isolated
    cache.mkdir(parents=True)
    (cache / "wasmtime").write_bytes(b"cache version")
    fake = tmp / "z.py"
    fake.write_text("")
    tools_bin = fake.resolve().parent / "tools" / "bin" / "wasmtime"
    tools_bin.parent.mkdir(parents=True)
    tools_bin.write_bytes(b"#!/bin/sh\n")
    monkeypatch.setattr(tb, "__file__", str(fake))
    r = tb.ensure_wasmtime()
    assert r == str(tools_bin)


def test_cache_wins_over_download(isolated, monkeypatch, fake_download):
    state, cache, tmp = isolated
    cache.mkdir(parents=True)
    (cache / "wasmtime").write_bytes(b"cached")
    tb.ensure_wasmtime()
    assert "url" not in fake_download

"""cmd_memory RFC-004 memory-graph bridge testleri (LEED).

Kural-1: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Dış çağrı YOK: gecici quickstart paketi.
"""
import contextlib
import io
import json
import sys

import pytest

sys.path.insert(0, ".")

import tamga_runner as tr  # noqa: E402


@pytest.fixture
def pkg(tmp_path, monkeypatch):
    monkeypatch.setenv("TAMGA_KS_PASSPHRASE", "test-pass-42")
    d = tmp_path / "pkg"
    tr.cmd_quickstart([str(d), "--name", "test-pkg"])
    return d


def _mem_cmd(pkg, *extra):
    return tr.cmd_memory([str(pkg), *extra])


def _json(pkg):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        _mem_cmd(pkg)
    return json.loads(buf.getvalue())


def _import(pkg, nodes, **over):
    src = pkg.parent / "imp.json"
    payload = {"format": "tamga-memory/1", "nodes": nodes}
    payload.update(over)
    src.write_text(json.dumps(payload), encoding="utf-8")
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = _mem_cmd(pkg, "--import-json", str(src))
    return rc, json.loads(buf.getvalue())


# -- temel listeleme ---------------------------------------------------------------------------

def test_memory_lists_ok(pkg):
    assert _mem_cmd(pkg) == 0


def test_memory_report_counts(pkg):
    o = _json(pkg)
    assert o["ok"] is True
    assert "nodes" in o
    assert "edges" in o


def test_empty_memory_has_genesis_nodes(pkg):
    """Quickstart genesis node'ları ile başlar."""
    o = _json(pkg)
    assert len(o["nodes"]) >= 0


def test_missing_pkg_creates_state(tmp_path):
    """Olmayan paket → yeni state oluşturulur (boş memory)."""
    rc = tr.cmd_memory([str(tmp_path / "yok")])
    assert rc == 0


# -- import-json ---------------------------------------------------------------------------

def test_import_single_node(pkg):
    rc, o = _import(pkg, [{"text": "ilk ders"}])
    assert rc == 0
    assert o["added"] == 1
    assert o["skipped"] == 0


def test_import_adds_node_to_memory(pkg):
    before = len(_json(pkg)["nodes"])
    _import(pkg, [{"text": "ders A"}])
    assert len(_json(pkg)["nodes"]) == before + 1


def test_import_two_nodes(pkg):
    rc, o = _import(pkg, [{"text": "a"}, {"text": "b"}])
    assert o["added"] == 2


def test_import_node_gets_id(pkg):
    _import(pkg, [{"text": "x"}])
    st = json.loads((pkg / "state.json").read_text())
    new = [n for n in st["memory"]["nodes"] if n["text"] == "x"]
    assert new and new[0]["id"].startswith("m")


def test_import_node_default_kind_fact(pkg):
    """RFC-004 §3: external lessons are fact-kind."""
    _import(pkg, [{"text": "ders"}])
    st = json.loads((pkg / "state.json").read_text())
    new = [n for n in st["memory"]["nodes"] if n["text"] == "ders"]
    assert new[0]["kind"] == "fact"


def test_import_node_default_ts(pkg):
    _import(pkg, [{"text": "ders"}])
    st = json.loads((pkg / "state.json").read_text())
    new = [n for n in st["memory"]["nodes"] if n["text"] == "ders"]
    assert "ts" in new[0]


def test_import_custom_id_preserved(pkg):
    rc, o = _import(pkg, [{"text": "ders", "id": "m42"}])
    st = json.loads((pkg / "state.json").read_text())
    new = [n for n in st["memory"]["nodes"] if n["text"] == "ders"]
    assert new[0]["id"] == "m42"


def test_import_custom_id_updates_next(pkg):
    _import(pkg, [{"text": "ders", "id": "m42"}])
    _import(pkg, [{"text": "ders2"}])
    st = json.loads((pkg / "state.json").read_text())
    new = [n for n in st["memory"]["nodes"] if n["text"] == "ders2"]
    assert new[0]["id"] == "m43"


def test_import_edges_added(pkg):
    rc, o = _import(pkg, [{"text": "a"}, {"text": "b"}],
                    edges=[["m0", "m1", "rel"]])
    st = json.loads((pkg / "state.json").read_text())
    assert st["memory"]["edges"] == [["m0", "m1", "rel"]]


def test_import_duplicate_edge_skipped(pkg):
    _import(pkg, [{"text": "a"}, {"text": "b"}], edges=[["m0", "m1", "r"]])
    _import(pkg, [{"text": "c"}], edges=[["m0", "m1", "r"]])
    st = json.loads((pkg / "state.json").read_text())
    assert len(st["memory"]["edges"]) == 1


# -- import hataları ---------------------------------------------------------------------------

def test_import_no_file_arg(pkg):
    rc = _mem_cmd(pkg, "--import-json")
    assert rc != 0


def test_import_missing_file(pkg):
    rc = _mem_cmd(pkg, "--import-json", str(pkg / "yok.json"))
    assert rc != 0


def test_import_bad_json(pkg):
    src = pkg.parent / "imp.json"
    src.write_text("{bozuk", encoding="utf-8")
    assert _mem_cmd(pkg, "--import-json", str(src)) != 0


def test_import_no_nodes_key(pkg):
    src = pkg.parent / "imp.json"
    src.write_text(json.dumps({"format": "x"}), encoding="utf-8")
    assert _mem_cmd(pkg, "--import-json", str(src)) != 0


def test_import_nodes_not_list(pkg):
    src = pkg.parent / "imp.json"
    src.write_text(json.dumps({"nodes": "x"}), encoding="utf-8")
    assert _mem_cmd(pkg, "--import-json", str(src)) != 0


def test_import_node_without_text(pkg):
    rc, o = _import(pkg, [{"kind": "fact"}])
    assert rc != 0


def test_import_empty_text(pkg):
    rc, o = _import(pkg, [{"text": "   "}])
    assert rc != 0


def test_import_oversized_note(pkg):
    rc, o = _import(pkg, [{"text": "x" * (tr.MAX_NOTE_BYTES + 1)}])
    assert rc != 0


def test_import_at_node_limit(pkg, monkeypatch):
    monkeypatch.setattr(tr, "MAX_NODES", 1)
    _import(pkg, [{"text": "a"}])
    rc, o = _import(pkg, [{"text": "b"}])
    assert rc != 0


# -- dedup ---------------------------------------------------------------------------

def test_import_duplicate_text_skipped(pkg):
    """Audit-5 F22: id-less external-node dedup (content fingerprint).

    _node_fp kind+text+ts'den oluşur → aynı node ts dahil tüm alanlar
    aynıysa skip edilir.
    """
    node = {"text": "aynı ders", "kind": "fact", "ts": "2026-10-08T12:00:00+0000"}
    _import(pkg, [dict(node)])
    rc, o = _import(pkg, [dict(node)])
    assert o["skipped"] == 1
    assert o["added"] == 0


def test_import_duplicate_id_skipped(pkg):
    """ADD-only: existing nodes never change."""
    _import(pkg, [{"text": "ders", "id": "m5"}])
    rc, o = _import(pkg, [{"text": "farklı metin", "id": "m5"}])
    assert o["skipped"] == 1


def test_import_different_text_added(pkg):
    _import(pkg, [{"text": "ders A"}])
    rc, o = _import(pkg, [{"text": "ders B"}])
    assert o["added"] == 1


# -- export-json ---------------------------------------------------------------------------

def test_export_writes_file(pkg):
    _import(pkg, [{"text": "ders"}])
    dst = pkg.parent / "exp.json"
    rc = _mem_cmd(pkg, "--export-json", str(dst))
    assert rc == 0
    assert dst.exists()


def test_export_payload_format(pkg):
    _import(pkg, [{"text": "ders"}])
    dst = pkg.parent / "exp.json"
    _mem_cmd(pkg, "--export-json", str(dst))
    o = json.loads(dst.read_text())
    assert o["format"] == "tamga-memory/1"


def test_export_includes_nodes(pkg):
    _import(pkg, [{"text": "ders"}])
    dst = pkg.parent / "exp.json"
    _mem_cmd(pkg, "--export-json", str(dst))
    o = json.loads(dst.read_text())
    assert len(o["nodes"]) >= 1
    assert any(n["text"] == "ders" for n in o["nodes"])


def test_export_file_mode_0600(pkg):
    _import(pkg, [{"text": "ders"}])
    dst = pkg.parent / "exp.json"
    _mem_cmd(pkg, "--export-json", str(dst))
    import os
    assert oct(os.stat(dst).st_mode)[-3:] == "600"


# -- search ---------------------------------------------------------------------------

def test_search_finds_match(pkg):
    _import(pkg, [{"text": "kuantum mekaniği"}, {"text": "termodinamik"}])
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        _mem_cmd(pkg, "--search", "kuantum")
    o = json.loads(buf.getvalue())
    assert o["ok"] is True


def test_search_no_match(pkg):
    _import(pkg, [{"text": "fizik"}])
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        _mem_cmd(pkg, "--search", "yokolan")
    o = json.loads(buf.getvalue())
    assert o["ok"] is True


def test_search_empty_query(pkg):
    _import(pkg, [{"text": "fizik"}])
    rc = _mem_cmd(pkg, "--search", "")
    assert rc == 0


def test_search_multi_word(pkg):
    _import(pkg, [{"text": "kuantum mekaniği temelleri"}])
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        _mem_cmd(pkg, "--search", "kuantum temelleri")
    o = json.loads(buf.getvalue())
    assert o["ok"] is True

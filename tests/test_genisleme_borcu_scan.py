"""genisleme_borcu.scan genişleme-borcu tarama testleri (LEED).

Kural-1: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Dış çağrı YOK: ROOT monkeypatch ile tmp proje-kökü.
"""
import sys

import pytest

sys.path.insert(0, ".")
sys.path.insert(0, "tools")

import genisleme_borcu as gb  # noqa: E402


@pytest.fixture
def fake_root(tmp_path, monkeypatch):
    monkeypatch.setattr(gb, "ROOT", tmp_path)
    return tmp_path


def _write(path, content="# Başlık\n\nmetin\n"):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


# -- temel yapı ---------------------------------------------------------------------------

def test_returns_dict(fake_root):
    r = gb.scan()
    assert isinstance(r, dict)


def test_all_expected_keys(fake_root):
    r = gb.scan()
    for k in ("primitive_pages", "vision_pages", "process_pages",
              "total_pages", "primitive_pct", "vision_pct", "gate",
              "blindspot", "primitive_files", "vision_files"):
        assert k in r


def test_empty_project(fake_root):
    r = gb.scan()
    assert r["primitive_pages"] == 0
    assert r["vision_pages"] == 0
    assert r["total_pages"] == 0


# -- ilkel sayfa ---------------------------------------------------------------------------

def test_primitive_file_counted(fake_root):
    _write(fake_root / "docs" / "RFC-001-temel.md", "# a\n\n# b\n")
    r = gb.scan()
    assert r["primitive_pages"] >= 1
    assert r["primitive_files"][0].startswith("docs/RFC-001-temel.md (")


def test_primitive_pct(fake_root):
    _write(fake_root / "docs" / "RFC-001-temel.md", "# a\n")
    r = gb.scan()
    assert r["primitive_pct"] == 100


def test_gate_ok_when_dominant(fake_root):
    _write(fake_root / "docs" / "RFC-001-temel.md", "# a\n")
    r = gb.scan()
    assert r["gate"] == "OK"


def test_gate_fail_when_low(fake_root):
    _write(fake_root / "docs" / "WHITEPAPER.md", "# a\n")
    r = gb.scan()
    assert r["gate"] != "OK"


# -- vizyon sayfa ---------------------------------------------------------------------------

def test_vision_file_counted(fake_root):
    _write(fake_root / "docs" / "WHITEPAPER.md", "# a\n")
    r = gb.scan()
    assert r["vision_pages"] >= 1
    assert r["vision_files"][0].startswith("docs/WHITEPAPER.md (")


def test_vision_pct(fake_root):
    _write(fake_root / "docs" / "WHITEPAPER.md", "# a\n")
    r = gb.scan()
    assert r["vision_pct"] == 100


def test_vision_pct_zero_when_primitive(fake_root):
    _write(fake_root / "docs" / "RFC-001-temel.md", "# a\n")
    r = gb.scan()
    assert r["vision_pct"] == 0


def test_total_equals_prim_plus_vis(fake_root):
    _write(fake_root / "docs" / "RFC-001-temel.md", "# a\n")
    _write(fake_root / "docs" / "WHITEPAPER.md", "# a\n# b\n")
    r = gb.scan()
    assert r["total_pages"] == r["primitive_pages"] + r["vision_pages"]


def test_pct_60_boundary_ok(fake_root):
    """ratio >= 60 → OK (eşitlik dahil)."""
    lp = gb.LINES_PER_PAGE
    _write(fake_root / "docs" / "RFC-001-temel.md",
           "\n".join("x" for _ in range(lp * 3)) + "\n")
    _write(fake_root / "docs" / "WHITEPAPER.md",
           "\n".join("x" for _ in range(lp * 2)) + "\n")
    r = gb.scan()
    assert r["primitive_pages"] == 3
    assert r["vision_pages"] == 2
    assert r["primitive_pct"] == 60
    assert r["gate"] == "OK"


def test_pct_59_boundary_fail(fake_root):
    _write(fake_root / "docs" / "RFC-001-temel.md", "# a\n# b\n# c\n")
    _write(fake_root / "docs" / "WHITEPAPER.md", "# a\n# b\n# c\n# d\n# e\n")
    r = gb.scan()
    assert r["primitive_pct"] < 60
    assert r["gate"] != "OK"


# -- süreç sayfaları ---------------------------------------------------------------------------

def test_process_file_counted(fake_root):
    _write(fake_root / "private" / "tasarim.md", "# a\n")
    r = gb.scan()
    assert r["process_pages"] >= 1


def test_process_not_in_total(fake_root):
    _write(fake_root / "private" / "tasarim.md", "# a\n")
    r = gb.scan()
    assert r["total_pages"] == 0


def test_public_non_matched_is_blindspot(fake_root):
    _write(fake_root / "docs" / "random.md", "# a\n")
    r = gb.scan()
    assert len(r["blindspot"]) >= 1


def test_private_not_in_blindspot(fake_root):
    _write(fake_root / "private" / "tasarim.md", "# a\n")
    r = gb.scan()
    assert len(r["blindspot"]) == 0


# -- kök-düzey markdown ---------------------------------------------------------------------------

def test_root_md_seen(fake_root):
    _write(fake_root / "README.md", "# a\n")
    r = gb.scan()
    # kök md'ler seen'e eklenir ama kategorize edilmez
    assert "README.md" not in r["primitive_files"]


def test_root_md_not_double_counted(fake_root):
    _write(fake_root / "README.md", "# a\n")
    r = gb.scan()
    assert r["total_pages"] == 0


# -- node_modules filtresi ---------------------------------------------------------------------------

def test_node_modules_skipped(fake_root):
    _write(fake_root / "docs" / "RFC-001-temel.md", "# a\n")
    _write(fake_root / "docs" / "node_modules" / "x" / "RFC-001-temel.md",
           "# a\n# b\n# c\n")
    r = gb.scan()
    assert "node_modules" not in str(r["primitive_files"])


# -- çoklu sayfa ---------------------------------------------------------------------------

def test_pages_counts_by_lines(fake_root):
    """pages() = max(1, satir_sayisi // LINES_PER_PAGE)."""
    _write(fake_root / "docs" / "RFC-001-temel.md",
           "\n".join("x" for _ in range(gb.LINES_PER_PAGE * 2)) + "\n")
    r = gb.scan()
    assert r["primitive_pages"] == 2


def test_single_page(fake_root):
    _write(fake_root / "docs" / "RFC-001-temel.md", "# a\n")
    r = gb.scan()
    assert r["primitive_pages"] == 1


# -- eksik dizinler ---------------------------------------------------------------------------

def test_missing_docs_ok(fake_root):
    r = gb.scan()
    assert r["gate"] != "OK" or r["total_pages"] == 0


def test_missing_private_ok(fake_root):
    _write(fake_root / "docs" / "RFC-001-temel.md", "# a\n")
    r = gb.scan()
    assert r["gate"] == "OK"


# -- göreceli yol ---------------------------------------------------------------------------

def test_relative_paths_in_files(fake_root):
    _write(fake_root / "docs" / "RFC-001-temel.md", "# a\n")
    r = gb.scan()
    assert r["primitive_files"][0].startswith("docs/")


def test_vision_relative_paths(fake_root):
    _write(fake_root / "docs" / "WHITEPAPER.md", "# a\n")
    r = gb.scan()
    assert r["vision_files"][0].startswith("docs/")

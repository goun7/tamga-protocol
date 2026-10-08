"""spec_code_scan AT-046 spec/code-parite tarayıcısı testleri (LEED).

Kural-1: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Dış çağrı YOK: repo-dışı-test-yapıları monkeypatch ile sahte-repo.
"""
import json
import sys

import pytest

sys.path.insert(0, "tools")
sys.path.insert(0, ".")

import spec_code_scan as scs  # noqa: E402


@pytest.fixture
def result():
    return scs.scan()


# -- scan() temel yapı ---------------------------------------------------------------------------

def test_scan_returns_dict(result):
    assert isinstance(result, dict)


def test_scanner_tag(result):
    assert result["scanner"] == "AT-046-tri-product"


def test_product_is_tamga(result):
    assert result["product"] == "tamga"


def test_rules_is_list(result):
    assert isinstance(result["rules"], list)
    assert len(result["rules"]) > 0


def test_summary_keys(result):
    assert set(result["summary"]) == {"aligned", "spec_only", "code_only",
                                      "untested"}


def test_errata_present(result):
    assert result["errata_applied"] == ["E1(a)", "E1(b)"]


def test_summary_counts_match_rules(result):
    s = result["summary"]
    for k in s:
        expected = sum(1 for r in result["rules"] if r["divergence"] == k)
        assert s[k] == expected


def test_total_rules_equals_summary_sum(result):
    s = result["summary"]
    assert len(result["rules"]) == sum(s.values())


# -- kural satırı yapısı ---------------------------------------------------------------------------

def test_rule_row_keys(result):
    r = result["rules"][0]
    assert set(r) >= {"id", "rule", "spec_ref", "spec_documented",
                      "code_enforced", "independent_parity", "divergence",
                      "evidence"}


def test_divergence_valid_values(result):
    valid = {"aligned", "spec-only", "code-only", "untested"}
    assert all(r["divergence"] in valid for r in result["rules"])


def test_rule_ids_unique(result):
    ids = [r["id"] for r in result["rules"]]
    assert len(ids) == len(set(ids))


def test_aligned_means_documented_and_enforced(result):
    for r in result["rules"]:
        if r["divergence"] == "aligned":
            assert r["spec_documented"] is True
            assert r["code_enforced"] is True


def test_spec_only_means_documented_not_enforced(result):
    for r in result["rules"]:
        if r["divergence"] == "spec-only":
            assert r["spec_documented"] is True
            assert not r["code_enforced"]


def test_code_only_means_enforced_not_documented(result):
    for r in result["rules"]:
        if r["divergence"] == "code-only":
            assert not r["spec_documented"]
            assert r["code_enforced"] is True


# -- _table ---------------------------------------------------------------------------

def test_table_is_string(result):
    assert isinstance(scs._table(result), str)


def test_table_shows_product(result):
    t = scs._table(result)
    assert "tamga" in t


def test_table_shows_aligned_count(result):
    t = scs._table(result)
    assert f"aligned={result['summary']['aligned']}" in t


def test_table_marks(result):
    t = scs._table(result)
    for mark in ("✓", "S", "C", "?"):
        if mark == "✓" and result["summary"]["aligned"] == 0:
            continue
        if mark == "S" and result["summary"]["spec_only"] == 0:
            continue
        if mark == "C" and result["summary"]["code_only"] == 0:
            continue
        if mark == "?" and result["summary"]["untested"] == 0:
            continue
        assert mark in t


def test_table_legend(result):
    t = scs._table(result)
    assert "E=evet" in t


# -- main ---------------------------------------------------------------------------

def test_main_json_format(capsys):
    rc = scs.main(["--format", "json"])
    out = capsys.readouterr().out
    d = json.loads(out)
    assert d["product"] == "tamga"


def test_main_table_format(capsys):
    rc = scs.main([])
    out = capsys.readouterr().out
    assert "Ürün: tamga" in out


def _fake_scan(div):
    return {"scanner": "x", "product": "tamga", "errata_applied": [],
            "summary": {"aligned": int(div == "aligned"), "spec_only": 0,
                        "code_only": 0, "untested": int(div == "untested")},
            "rules": [{"id": "R1", "rule": "test-rule", "spec_ref": "x",
                       "spec_documented": True, "code_enforced": True,
                       "independent_parity": True, "divergence": div,
                       "evidence": "test"}]}


def test_main_returns_zero_when_no_untested(monkeypatch, capsys):
    """untested kural yoksa rc=0."""
    monkeypatch.setattr(scs, "scan", lambda: _fake_scan("aligned"))
    assert scs.main([]) == 0


def test_main_returns_one_when_untested(monkeypatch, capsys):
    monkeypatch.setattr(scs, "scan", lambda: _fake_scan("untested"))
    assert scs.main([]) == 1


def test_main_json_output_valid(monkeypatch, capsys):
    monkeypatch.setattr(scs, "scan", lambda: _fake_scan("aligned"))
    scs.main(["--format", "json"])
    d = json.loads(capsys.readouterr().out)
    assert len(d["rules"]) == 1


# -- RULES / ANCHOR_RULES tutarlılık ---------------------------------------------------------------------------

def test_rules_have_five_tuple(result):
    """Her kural (rid, desc, spec_ref, red_case, green_case) formatında."""
    assert len(scs.RULES) > 0
    for r in scs.RULES:
        assert len(r) == 5


def test_anchor_rules_have_five_tuple(result):
    assert len(scs.ANCHOR_RULES) > 0
    for r in scs.ANCHOR_RULES:
        assert len(r) == 5


def test_anchor_rows_in_result(result):
    """ANCHOR_RULES sonuçlara eklenir."""
    n_anchor = len(scs.ANCHOR_RULES)
    assert len(result["rules"]) >= n_anchor


def test_all_rules_have_evidence(result):
    assert all(r["evidence"] for r in result["rules"])


# -- spec documentasyon gerçekten okunuyor ---------------------------------------------------------------------------

def test_spec_ledger_file_exists():
    from pathlib import Path
    p = scs.REPO / "tests" / "conformance" / "spec" / "LEDGER-SPEC.md"
    assert p.exists()


def test_anchor_spec_file_exists():
    from pathlib import Path
    p = scs.REPO / "tests" / "conformance" / "spec" / "ANCHOR-SPEC.md"
    assert p.exists()


def test_documented_rules_have_real_spec_refs(result):
    """spec_documented=True ise spec_ref gerçekten LEDGER-SPEC'te var."""
    ledger = (scs.REPO / "tests" / "conformance" / "spec" /
              "LEDGER-SPEC.md").read_text(encoding="utf-8")
    for r in result["rules"][:len(scs.RULES)]:
        if r["spec_documented"]:
            assert r["spec_ref"] in ledger

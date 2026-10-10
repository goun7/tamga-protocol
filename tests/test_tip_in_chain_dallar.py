"""tamga_runner._tip_in_chain dal-kesen testleri (LEED).

Kural-1: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory (tmp_path ile yerel dosya, dis cagri YOK).
F21 countermeasure: tip hash zincirin bir uyesi mi?
"""
import json
import sys

import pytest

sys.path.insert(0, ".")
from tamga_runner import _tip_in_chain  # noqa: E402

H1 = "a" * 64
H2 = "b" * 64


@pytest.fixture()
def ledger(tmp_path):
    def _write(recs):
        p = tmp_path / "l.jsonl"
        p.write_text("\n".join(json.dumps(r) for r in recs) + "\n",
                     encoding="utf-8")
        return p
    return _write


# -- bulunan ---------------------------------------------------------------------------------

def test_tip_found(ledger):
    p = ledger([{"h": H1}, {"h": H2}])
    assert _tip_in_chain(p, H2) is True


def test_first_tip_found(ledger):
    p = ledger([{"h": H1}, {"h": H2}])
    assert _tip_in_chain(p, H1) is True


def test_tip_not_found(ledger):
    p = ledger([{"h": H1}])
    assert _tip_in_chain(p, H2) is False


def test_empty_file(ledger):
    p = ledger([])
    assert _tip_in_chain(p, H1) is False


def test_returns_bool(ledger):
    p = ledger([{"h": H1}])
    assert isinstance(_tip_in_chain(p, H1), bool)


def test_missing_file_raises(tmp_path):
    """URETIM-SINIR: olmayan dosya -> FileNotFoundError (False DEGIL)."""
    with pytest.raises(FileNotFoundError):
        _tip_in_chain(tmp_path / "nope.jsonl", H1)


def test_invalid_utf8_raises(tmp_path):
    """URETIM-SINIR: gecersiz-UTF8 -> UnicodeDecodeError YAYILIR."""
    p = tmp_path / "l.jsonl"
    p.write_bytes(b'{"h": "a"}\xff\xfe\n')
    with pytest.raises(UnicodeDecodeError):
        _tip_in_chain(p, "a")


# -- bos satirlar -----------------------------------------------------------------------------

def test_blank_lines_skipped(ledger, tmp_path):
    p = tmp_path / "l.jsonl"
    p.write_text(f'{{"h": "{H1}"}}\n\n\n{{"h": "{H2}"}}\n\n', encoding="utf-8")
    assert _tip_in_chain(p, H2) is True


def test_all_blank(tmp_path):
    p = tmp_path / "l.jsonl"
    p.write_text("\n\n\n", encoding="utf-8")
    assert _tip_in_chain(p, H1) is False


def test_whitespace_only(tmp_path):
    p = tmp_path / "l.jsonl"
    p.write_text("   \n\t\n", encoding="utf-8")
    assert _tip_in_chain(p, H1) is False


def test_strip_indent(tmp_path):
    """line.strip() — girintili kayitlar da calisir."""
    p = tmp_path / "l.jsonl"
    p.write_text(f'  {{"h": "{H1}"}}  \n', encoding="utf-8")
    assert _tip_in_chain(p, H1) is True


# -- hatali json ------------------------------------------------------------------------------

def test_invalid_json_aborts_before_match(tmp_path):
    """ORTAM: hatali JSON -> except Exception -> return False (ABORT)."""
    p = tmp_path / "l.jsonl"
    p.write_text("bad\n" + json.dumps({"h": H1}) + "\n", encoding="utf-8")
    assert _tip_in_chain(p, H1) is False


def test_invalid_json_after_match_short_circuits(tmp_path):
    """ORTAM: match bulununca TRUE doner — SONRADAN gelen bozuk
    satir okunmaz (short-circuit, F21 found=True)."""
    p = tmp_path / "l.jsonl"
    p.write_text(json.dumps({"h": H1}) + "\nbad\n", encoding="utf-8")
    assert _tip_in_chain(p, H1) is True


def test_missing_h_key(ledger):
    """json.loads().get('h') -> None != tip -> devam, sonunda False."""
    p = ledger([{"x": 1}])
    assert _tip_in_chain(p, H1) is False


def test_none_h_value(ledger):
    p = ledger([{"h": None}])
    assert _tip_in_chain(p, H1) is False


def test_h_none_matches_none_tip(ledger):
    p = ledger([{"h": None}])
    assert _tip_in_chain(p, None) is True


def test_h_is_number(ledger):
    p = ledger([{"h": 12345}])
    assert _tip_in_chain(p, 12345) is True


def test_h_is_string(ledger):
    p = ledger([{"h": "metin"}])
    assert _tip_in_chain(p, "metin") is True


# -- tip eslesme -------------------------------------------------------------------------------

def test_case_sensitive(ledger):
    p = ledger([{"h": "ABC"}])
    assert _tip_in_chain(p, "abc") is False


def test_full_match_required(ledger):
    """64-char hash tam eslesme."""
    p = ledger([{"h": H1}])
    assert _tip_in_chain(p, H1[:60]) is False


def test_tip_longer(ledger):
    p = ledger([{"h": H1}])
    assert _tip_in_chain(p, H1 + "x") is False


def test_empty_tip(ledger):
    p = ledger([{"h": ""}])
    assert _tip_in_chain(p, "") is True


def test_empty_tip_no_match(ledger):
    p = ledger([{"h": H1}])
    assert _tip_in_chain(p, "") is False


def test_duplicate_hashes(ledger):
    p = ledger([{"h": H1}, {"h": H1}])
    assert _tip_in_chain(p, H1) is True


def test_matches_first_of_duplicates(ledger):
    p = ledger([{"h": H1}, {"h": H2}, {"h": H1}])
    assert _tip_in_chain(p, H1) is True


# -- unicode ---------------------------------------------------------------------------------

def test_turkish_h(tmp_path):
    p = tmp_path / "l.jsonl"
    p.write_text(json.dumps({"h": "Gökhan-İstanbul"}) + "\n",
                 encoding="utf-8")
    assert _tip_in_chain(p, "Gökhan-İstanbul") is True


def test_emoji_h(tmp_path):
    p = tmp_path / "l.jsonl"
    p.write_text(json.dumps({"h": "😀"}) + "\n", encoding="utf-8")
    assert _tip_in_chain(p, "😀") is True


# -- gecersiz-utf8 ---------------------------------------------------------------------------

def test_invalid_utf8_before_match_raises(tmp_path):
    """decode hatasi match'ten once -> UnicodeDecodeError."""
    p = tmp_path / "l.jsonl"
    p.write_bytes(b'\xff\xfe{"h": "a"}\n')
    with pytest.raises(UnicodeDecodeError):
        _tip_in_chain(p, "a")


# -- cesitli ---------------------------------------------------------------------------------

def test_many_records(ledger):
    recs = [{"h": f"{'0'*63}{i:01x}"} for i in range(100)]
    p = ledger(recs)
    assert _tip_in_chain(p, recs[-1]["h"]) is True
    assert _tip_in_chain(p, recs[50]["h"]) is True


def test_repeatable(ledger):
    p = ledger([{"h": H1}])
    assert _tip_in_chain(p, H1) == _tip_in_chain(p, H1)


def test_independent(ledger):
    p = ledger([{"h": H1}, {"h": H2}])
    assert _tip_in_chain(p, H1) and not _tip_in_chain(p, "c" * 64)


def test_pathlike_str(ledger):
    p = ledger([{"h": H1}])
    assert _tip_in_chain(str(p), H1) is True


def test_not_short_circuit_on_h_key(ledger):
    """.get() None doner, loop devam eder."""
    p = ledger([{"prev": "x"}, {"h": H1}])
    assert _tip_in_chain(p, H1) is True


def test_finds_in_middle(ledger):
    recs = [{"h": f"{'0'*63}{i:01x}"} for i in range(5)]
    p = ledger(recs)
    assert _tip_in_chain(p, recs[2]["h"]) is True


def test_jsonl_trailing_newline(tmp_path):
    p = tmp_path / "l.jsonl"
    p.write_text(json.dumps({"h": H1}), encoding="utf-8")
    assert _tip_in_chain(p, H1) is True

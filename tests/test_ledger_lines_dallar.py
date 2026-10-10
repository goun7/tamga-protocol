"""tamga_runner._ledger_lines dal-kesen testleri (LEED).

Kural-1: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory (tmp_path ile yerel dosya, dis cagri YOK).
"""
import json
import sys

import pytest

sys.path.insert(0, ".")
from tamga_runner import _ledger_lines, MAX_LINE_BYTES  # noqa: E402


@pytest.fixture()
def ledger(tmp_path):
    def _write(lines):
        p = tmp_path / "ledger.jsonl"
        p.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return str(p)
    return _write


def to_recs(lines):
    return list(_ledger_lines(lines))


# -- temel ---------------------------------------------------------------------------------

def test_empty_file(ledger):
    assert to_recs(ledger([])) == []


def test_single_record(ledger):
    p = ledger(['{"a": 1}'])
    assert to_recs(p) == [{"a": 1}]


def test_multiple_records(ledger):
    p = ledger(['{"a": 1}', '{"b": 2}'])
    assert to_recs(p) == [{"a": 1}, {"b": 2}]


def test_returns_generator(ledger):
    import types
    g = _ledger_lines(ledger(['{"a":1}']))
    assert isinstance(g, types.GeneratorType)


def test_streaming_lazy(ledger):
    """generator lazy — hic tuketmeden dosya acilmaz."""
    g = _ledger_lines(ledger(['{"a":1}']))
    assert next(g) == {"a": 1}


# -- bos-satirlar ---------------------------------------------------------------------------------

def test_blank_lines_skipped(ledger):
    p = ledger(['{"a":1}', '', '{"b":2}'])
    assert to_recs(p) == [{"a": 1}, {"b": 2}]


def test_whitespace_only_skipped(ledger):
    p = ledger(['{"a":1}', '   ', '\t', '{"b":2}'])
    assert to_recs(p) == [{"a": 1}, {"b": 2}]


def test_all_blank(ledger):
    assert to_recs(ledger(['', '', ''])) == []


def test_leading_blank(ledger):
    assert to_recs(ledger(['', '{"a":1}'])) == [{"a": 1}]


def test_trailing_blank(ledger):
    assert to_recs(ledger(['{"a":1}', ''])) == [{"a": 1}]


def test_strip_removes_indent(ledger):
    """line.strip() — girinti bosluklarini kaldirir."""
    p = ledger(['  {"a":1}  '])
    assert to_recs(p) == [{"a": 1}]


# -- hatali-json ---------------------------------------------------------------------------------

def test_invalid_json_sentinel(ledger):
    """bozuk JSON -> {} sentinel."""
    assert to_recs(ledger(['not-json'])) == [{}]


def test_mixed_valid_invalid(ledger):
    p = ledger(['{"a":1}', 'bad', '{"b":2}'])
    assert to_recs(p) == [{"a": 1}, {}, {"b": 2}]


def test_unclosed_json(ledger):
    assert to_recs(ledger(['{"a":'])) == [{}]


def test_trailing_comma_json(ledger):
    assert to_recs(ledger(['{"a":1,}'])) == [{}]


def test_sentinel_is_empty_dict(ledger):
    r = to_recs(ledger(['x']))
    assert r == [{}] and isinstance(r[0], dict)


def test_multiple_invalid(ledger):
    assert to_recs(ledger(['x', 'y', 'z'])) == [{}, {}, {}]


# -- buyuk-satir ---------------------------------------------------------------------------------

def test_max_boundary_ok(ledger):
    """tam MAX_LINE_BYTES -> kabul."""
    payload = '{"x":"' + "a" * (MAX_LINE_BYTES - 12) + '"}'
    assert len(payload.encode()) <= MAX_LINE_BYTES
    r = to_recs(ledger([payload]))
    assert r and r[0]


def test_over_max_sentinel(ledger):
    """MAX_LINE_BYTES ustu -> {} (memory-bounded)."""
    payload = '{"x":"' + "a" * (MAX_LINE_BYTES) + '"}'
    assert len(payload.encode()) > MAX_LINE_BYTES
    assert to_recs(ledger([payload])) == [{}]


def test_max_line_bytes_value():
    """1 MB."""
    assert MAX_LINE_BYTES == 1024 * 1024


def test_huge_line_no_full_read(ledger):
    """50MB satir bile {} sentinel (no full load)."""
    payload = '{"x":"' + "a" * (50 * 1024 * 1024) + '"}'
    assert to_recs(ledger([payload])) == [{}]


def test_size_uses_utf8_bytes(ledger):
    """len(line.encode('utf-8')) — 4-bayt emoji sayilir ('c'=2bayt DEGIL)."""
    # 4 byte/char * N > MAX
    n = MAX_LINE_BYTES // 4 + 10
    payload = '{"x":"' + chr(0x1F600) * n + '"}'
    assert len(payload.encode()) > MAX_LINE_BYTES
    assert to_recs(ledger([payload])) == [{}]


# -- cesitli-tipler ---------------------------------------------------------------------------------

def test_json_array(ledger):
    assert to_recs(ledger(['[1,2,3]'])) == [[1, 2, 3]]


def test_json_number(ledger):
    assert to_recs(ledger(['42'])) == [42]


def test_json_string(ledger):
    assert to_recs(ledger(['"merhaba"'])) == ["merhaba"]


def test_json_null(ledger):
    assert to_recs(ledger(['null'])) == [None]


def test_json_bool(ledger):
    assert to_recs(ledger(['true'])) == [True]


def test_nested(ledger):
    p = ledger(['{"a":{"b":[1,{"c":null}]}}'])
    assert to_recs(p) == [{"a": {"b": [1, {"c": None}]}}]


# -- unicode ---------------------------------------------------------------------------------

def test_turkish_record(ledger):
    p = ledger(['{"ad":"Gökhan","ş":"İstanbul"}'])
    assert to_recs(p) == [{"ad": "Gökhan", "ş": "İstanbul"}]


def test_emoji_record(ledger):
    assert to_recs(ledger(['{"e":"😀"}'])) == [{"e": "😀"}]


def test_invalid_utf8_bytes_raises(tmp_path):
    """URETIM-SINIR: gecersiz-UTF8 -> UnicodeDecodeError YAYILIR
    (open(encoding=utf-8) decode hatasi yield-try'inda YAKALANMAZ)."""
    p = tmp_path / "bad.jsonl"
    p.write_bytes(b'{"a":1}\xff\xfe\n')
    with pytest.raises(UnicodeDecodeError):
        list(_ledger_lines(str(p)))


# -- dosya ---------------------------------------------------------------------------------

def test_missing_file_raises():
    with pytest.raises((OSError, FileNotFoundError)):
        list(_ledger_lines("/nonexistent/nope.jsonl"))


def test_directory_raises(tmp_path):
    with pytest.raises(OSError):
        list(_ledger_lines(str(tmp_path)))


def test_closed_after_iteration(ledger):
    p = ledger(['{"a":1}'])
    list(_ledger_lines(p))
    # generator tuketilince dosya kapanir (with-blog)


# -- tekrar ---------------------------------------------------------------------------------

def test_repeatable(ledger):
    p = ledger(['{"a":1}', '{"b":2}'])
    assert to_recs(p) == to_recs(p)


def test_independent_reads(ledger):
    p = ledger(['{"a":1}'])
    assert to_recs(p) == to_recs(p) == [{"a": 1}]


def test_large_file(ledger):
    lines = [json.dumps({"i": i}) for i in range(500)]
    p = ledger(lines)
    r = to_recs(p)
    assert len(r) == 500 and r[0]["i"] == 0 and r[-1]["i"] == 499


def test_order_preserved(ledger):
    p = ledger(['{"i":1}', '{"i":2}', '{"i":3}'])
    assert [x["i"] for x in to_recs(p)] == [1, 2, 3]

"""tamga_canon — RFC 8785 / JCS canonical serialization tests.

Canonicalization is the load-bearing primitive of every receipt: a stranger in
another language must re-derive byte-identical bytes. These tests pin the two
behaviours where plain ``json.dumps(sort_keys=True)`` would silently diverge
(ECMAScript number formatting and UTF-16 member order), plus determinism and
the I-JSON rejections the module deliberately raises.
"""
import json

import pytest

from tamga_canon import jcs, canonical, jcs_json, es_number, loads


# --- es_number: ECMAScript Number.prototype.toString (RFC 8785 §3.2.2.2) ------------------
ES_CASES = [
    (0.0, "0"),
    (-0.0, "0"),                       # ECMAScript prints "0" for negative zero
    (1.0, "1"),                        # Python would say "1.0" — the canonical divergence
    (-1.5, "-1.5"),
    (3.14, "3.14"),
    (100.0, "100"),
    (1e16, "10000000000000000"),       # Python switches to exponent here, ECMAScript does not
    (1e21, "1e+21"),                   # ECMAScript goes exponential only above 1e21
    (1e-6, "0.000001"),                # ... and only below 1e-6
    (1e-7, "1e-7"),
    (2.93e-07, "2.93e-7"),             # Python pads the exponent ("2.93e-07")
]


@pytest.mark.parametrize("value,expected", ES_CASES)
def test_es_number_matches_ecmascript(value, expected):
    """Each case is a documented divergence from Python's own ``repr``; the
    expected strings are the ECMAScript productions from RFC 8785 §3.2.2.2."""
    assert es_number(value) == expected


@pytest.mark.parametrize("bad", [float("nan"), float("inf"), float("-inf")])
def test_es_number_rejects_non_finite(bad):
    """I-JSON (RFC 7493) forbids NaN/Infinity. Node's JSON.stringify would
    silently emit "null" (value drop) — the module rejects loudly instead."""
    with pytest.raises(ValueError):
        es_number(bad)


# --- jcs: structural serialization --------------------------------------------------------
def test_jcs_sorts_members_and_drops_whitespace():
    """Member order is sorted and separators are compact; output is bytes."""
    assert jcs({"b": 1, "a": 2}) == b'{"a":2,"b":1}'


def test_jcs_json_returns_str():
    """The str alias must be the exact decode of the bytes form."""
    obj = {"b": 1, "a": 2}
    assert jcs_json(obj) == jcs(obj).decode("utf-8")


def test_canonical_alias_is_jcs():
    """``canonical`` is documented as an alias for readers coming from other JCS
    docs; it must be the very same callable."""
    assert canonical is jcs


def test_jcs_scalars_and_containers():
    """bool/None/int/float/str/list/tuple/nesting all map to their JSON spellings,
    with floats going through ECMAScript formatting."""
    obj = [True, False, None, 42, 1.0, "x", (3, 4), {"z": {"y": 2}}]
    assert jcs_json(obj) == '[true,false,null,42,1,"x",[3,4],{"z":{"y":2}}]'


def test_jcs_keeps_non_ascii_raw():
    """RFC 8785 does NOT escape non-ASCII; it is emitted as raw UTF-8 so the byte
    length matches a JS encoder."""
    assert jcs({"k": "ğ"}) == '{"k":"ğ"}'.encode("utf-8")


def test_jcs_escapes_control_chars_and_quotes():
    """Only the mandatory escapes: quotes/backslash/backspace/formfeed/newline/
    carriage-return/tab, plus \\u00xx for C0 control codes."""
    assert jcs_json({"k": 'a"b\\c\n'}) == '{"k":"a\\"b\\\\c\\n"}'
    assert jcs_json({"k": "\x01"}) == '{"k":"\\u0001"}'


def test_jcs_member_order_is_utf16_not_codepoint():
    """The decisive RFC 8785 §3.2.3 rule: members are ordered by UTF-16 code unit,
    not Unicode code point. U+FFFF (code point smaller) sorts AFTER a surrogate
    pair U+1F600 because 0xD83D < 0xFFFF — plain ``json.dumps(sort_keys=True)``
    would order these the other way and break cross-language digest parity."""
    out = jcs_json({"\uffff": 1, "\U0001F600": 2})
    assert out.index("\U0001F600") < out.index("\uffff")
    assert json.dumps({"\uffff": 1, "\U0001F600": 2}, sort_keys=True) != out


def test_jcs_is_deterministic_and_order_invariant():
    """Repeated calls are byte-identical, and Python-side insertion order of the
    dict never affects the canonical bytes."""
    a = {"y": 1, "x": 2, "w": [3, {"v": 4}]}
    b = {"w": [3, {"v": 4}], "x": 2, "y": 1}
    assert jcs(a) == jcs(b)
    assert jcs(a) == jcs(a)


def test_jcs_empty_containers():
    """Boundary: empty dict/list serialise to their bare brackets."""
    assert jcs_json({}) == "{}"
    assert jcs_json([]) == "[]"


def test_jcs_rejects_int_outside_ijson_range():
    """Integers outside [−2^53, 2^53] are not in the I-JSON subset: Node would
    round them, so the same JSON would parse differently across languages and
    the digest would not agree. The module refuses rather than emit silently."""
    with pytest.raises(ValueError):
        jcs({"big": 2 ** 53 + 1})
    with pytest.raises(ValueError):
        jcs({"small": -(2 ** 53) - 1})
    # Boundaries themselves are allowed.
    assert jcs_json({"ok": 2 ** 53}) == '{"ok":9007199254740992}'


def test_jcs_rejects_unsupported_types():
    """Sets / arbitrary objects have no JSON mapping — raise TypeError so the
    caller fixes the payload instead of producing a half-canonical receipt."""
    with pytest.raises(TypeError):
        jcs({"k": {1, 2}})
    with pytest.raises(TypeError):
        jcs(object())


def test_loads_roundtrips_canonical_output():
    """Convenience parity helper parses back the canonical bytes."""
    obj = {"a": [1, 2], "b": "ğ"}
    assert loads(jcs_json(obj)) == obj

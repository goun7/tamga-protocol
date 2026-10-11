"""tools/attest_verify_bagimsiz JCS serilestirme + Keccak sponge dal-kesen testleri (LEED).

Kural-1: MEVCUT DOSYALARA DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory (str/obj/list girdi; dis ag YOK).

Kapsanan _-prefixed fonksiyonlar (AST backlog):
  _esc_string  RFC 8785 §3.2.2 string-kacis (7-ozel + \\uXXXX kontrol)
  _jcs         RFC 8785 canonical-serialization (null/bool/int/str/dict/list)
  _keccak_f    Keccak-f[1600] sponge-permutasyonu (24-round theta/rho/pi/chi/iota)
"""
import sys

import pytest

sys.path.insert(0, ".")
sys.path.insert(0, "tools")
from attest_verify_bagimsiz import _esc_string, _jcs, _keccak_f  # noqa: E402


# == _esc_string: temel ==========================================================================

def test_esc_string_simple():
    assert _esc_string("hello") == '"hello"'


def test_esc_string_empty():
    assert _esc_string("") == '""'


@pytest.mark.parametrize("s", ["hello", "", "a", "space x", "CamelCase", "123"])
def test_esc_string_plain_passthrough(s):
    """Ozel-karakter-olmayanlar oldugu gibi gecer."""
    assert _esc_string(s) == '"' + s + '"'


def test_esc_string_returns_str():
    assert isinstance(_esc_string("x"), str)


def test_esc_string_always_quoted():
    """Sonuc daima tirnak-icinde."""
    assert _esc_string("x").startswith('"')
    assert _esc_string("x").endswith('"')


# == _esc_string: 7-ozel-kacis (RFC 8785 §3.2.2) =================================================

@pytest.mark.parametrize("ch,esc", [
    ('"', '\\"'), ('\\', '\\\\'), ('\b', '\\b'), ('\f', '\\f'),
    ('\n', '\\n'), ('\r', '\\r'), ('\t', '\\t'),
])
def test_esc_string_special_chars(ch, esc):
    """RFC 8785 zorunlu 7-kacis."""
    assert _esc_string("a" + ch + "b") == '"a' + esc + 'b"'


@pytest.mark.parametrize("inp,expect", [
    ('a"b', '"a\\"b"'),
    ('a\\b', '"a\\\\b"'),
    ('tab\there', '"tab\\there"'),
    ('new\nline', '"new\\nline"'),
    ('cr\rhere', '"cr\\rhere"'),
    ('back\bbone', '"back\\bbone"'),
    ('form\feed', '"form\\feed"'),
])
def test_esc_string_special_in_context(inp, expect):
    assert _esc_string(inp) == expect


def test_esc_string_all_specials_together():
    r = _esc_string('"\b\f\n\r\t\\')
    assert r == '"\\"\\b\\f\\n\\r\\t\\\\"'


def test_esc_string_backslash_first():
    """Cift-backslash once (parse sirasi onemli DEGIL — kacis-geri-alinamaz)."""
    assert _esc_string("\\x") == '"\\\\x"'


# == _esc_string: kontrol-karakterleri (\uXXXX) ==================================================

@pytest.mark.parametrize("cp", [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
                                0x0B, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x1E, 0x1F])
def test_esc_string_control_chars(cp):
    """ord < 0x20 -> \\uXXXX (4-hex, kucuk-harf, sifir-dolgulu).
    NOT: 0x08/0x09/0x0A/0x0C/0x0D isimli-kacislardir (\\b\\t\\n\\f\\r)."""
    s = _esc_string("x" + chr(cp))
    assert s == '"x\\u%04x"' % cp


def test_esc_string_named_escapes_not_u():
    """ORTAM-ANATOMI: 0x08/0x09/0x0A/0x0C/0x0D _ESC-sozlugunden gelir (\\uXXXX DEGIL)."""
    for cp, nm in ((8, "b"), (9, "t"), (10, "n"), (12, "f"), (13, "r")):
        assert _esc_string(chr(cp)) == '"\\' + nm + '"'


def test_esc_string_all_control_range():
    """0x00..0x1F tumu ya-isimli-5 ya \\uXXXX (16'si)."""
    named = {8, 9, 10, 12, 13}
    for cp in range(0x20):
        s = _esc_string(chr(cp))
        if cp in named:
            assert "\\u" not in s
        else:
            assert "\\u%04x" % cp in s


def test_esc_string_control_high_boundary():
    """0x1F (31) henuz \\uXXXX; 0x20 (space) ise DEGIL."""
    assert _esc_string("\x1f") == '"\\u001f"'
    assert _esc_string("\x20") == '" "'


def test_esc_string_del_is_literal():
    """ORTAM-KARAKTERIZASYON: 0x7F (DEL) literal-gecer — RFC 8785 yalniz < 0x20
    kontrol-olarak tanimlar; 0x7F 'ordinary' sayilir."""
    assert _esc_string("\x7f") == '"\x7f"'


@pytest.mark.parametrize("cp", [0x00, 0x07, 0x1B])
def test_esc_string_control_not_special_named(cp):
    """0x07 (bell) vb. isimli-kacis YOK — \\uXXXX."""
    assert _esc_string(chr(cp)) == '"\\u%04x"' % cp


# == _esc_string: unicode ========================================================================

@pytest.mark.parametrize("s", ["unicode-ğ", "emoji-🎉", "日本語", "Ω≈ç√"])
def test_esc_string_unicode_literal(s):
    """RFC 8785: >0x20 UTF-8 olarak literal (\\u-gerekmez)."""
    assert _esc_string(s) == '"' + s + '"'


def test_esc_string_ascii_printable():
    for cp in range(0x20, 0x7F):
        ch = chr(cp)
        if ch in '"\\':
            continue          # bu ikisi kacar
        assert _esc_string(ch) == '"' + ch + '"'


def test_esc_string_combining_marks():
    """Birlestirici-isaretler literal-gecer (U+0301)."""
    s = "e" + chr(0x301)
    assert _esc_string(s) == '"' + s + '"'


def test_esc_string_supplementary_plane():
    """4-byte UTF-8 (U+1F600) literal-gecer."""
    assert _esc_string("😀") == '"😀"'


def test_esc_string_surrogate_pair_ok():
    """Python-str olarak sorrogate-cifti tek-char (\\uD83D\\uDE00 DEGIL)."""
    assert len("🎉") == 1
    assert _esc_string("🎉").count("\\u") == 0


def test_esc_string_deterministic():
    assert _esc_string("x\ty") == _esc_string("x\ty")


# == _jcs: skaler ================================================================================

@pytest.mark.parametrize("inp,expect", [
    (None, "null"), (True, "true"), (False, "false"),
    (0, "0"), (42, "42"), (-7, "-7"), (2**53, "9007199254740992"),
])
def test_jcs_scalars(inp, expect):
    """RFC 8785 skaler-sembolleri."""
    assert _jcs(inp) == expect


def test_jcs_int_str():
    assert _jcs(12345) == "12345"


def test_jcs_negative_int():
    assert _jcs(-1) == "-1"


def test_jcs_zero():
    assert _jcs(0) == "0"


def test_jcs_bool_true_before_int():
    """ORTAM-ANATOMI: bool-kontrolu int-kontrolundan ONCE (True/False isinstance int)."""
    assert _jcs(True) == "true"
    assert _jcs(False) == "false"


# == _jcs: string ================================================================================

@pytest.mark.parametrize("inp,expect", [
    ("", '""'), ("x", '"x"'), ('a"b', '"a\\"b"'), ("a\nb", '"a\\nb"'),
    ("\t", '"\\t"'), ("ctrl\x01", '"ctrl\\u0001"'),
])
def test_jcs_string(inp, expect):
    assert _jcs(inp) == expect


def test_jcs_string_delegates():
    """_jcs str icin _esc_string'i cagirir."""
    assert _jcs('x"y') == _esc_string('x"y')


# == _jcs: list ===================================================================================

@pytest.mark.parametrize("inp,expect", [
    ([], "[]"), ([1], "[1]"), ([1, 2, 3], "[1,2,3]"),
    (["a", "b"], '["a","b"]'), ([[1, 2], [3]], "[[1,2],[3]]"),
])
def test_jcs_list(inp, expect):
    assert _jcs(inp) == expect


def test_jcs_tuple_is_list():
    """tuple list-gibi serilesir (dizi-paritesi)."""
    assert _jcs((1, 2)) == "[1,2]"


def test_jcs_nested_list():
    assert _jcs([[1], [2, [3]]]) == "[[1],[2,[3]]]"


def test_jcs_list_order_preserved():
    """Liste sirasi KORUNUR (siralama YOK)."""
    assert _jcs([3, 1, 2]) == "[3,1,2]"


def test_jcs_list_mixed_types():
    assert _jcs([1, "a", None, True]) == '[1,"a",null,true]'


def test_jcs_empty_list():
    assert _jcs([]) == "[]"


# == _jcs: object =================================================================================

def test_jcs_empty_object():
    assert _jcs({}) == "{}"


def test_jcs_single_key():
    assert _jcs({"a": 1}) == '{"a":1}'


def test_jcs_keys_sorted():
    """ORTAM-ANATOMI: key siralama [ord(c) for c in s] — yani A < a < b."""
    assert _jcs({"b": 1, "A": 2, "a": 3}) == '{"A":2,"a":3,"b":1}'


def test_jcs_keys_sorted_numerically():
    assert _jcs({"b": 1, "a": 2}) == '{"a":2,"b":1}'


def test_jcs_single_char_keys():
    assert _jcs({"z": 0, "y": 0, "x": 0}) == '{"x":0,"y":0,"z":0}'


def test_jcs_key_string_escapes():
    """Key'lerde de _esc_string uygulanir."""
    assert _jcs({'a"b': 1}) == '{"a\\"b":1}'


def test_jcs_nested_object():
    assert _jcs({"z": {"y": 1}}) == '{"z":{"y":1}}'


def test_jcs_object_in_list():
    assert _jcs([{"a": 1}]) == '[{"a":1}]'


def test_jcs_values_recursed():
    assert _jcs({"a": {"b": {"c": 1}}}) == '{"a":{"b":{"c":1}}}'


def test_jcs_deterministic():
    assert _jcs({"b": 1, "a": 2}) == _jcs({"a": 2, "b": 1})


def test_jcs_unicode_key_sort():
    """RFC 8785 §3.2.3 UTF-16 kod-birim sirasi (ASCII'de kod-noktasiyla ayni)."""
    assert _jcs({"é": 1, "z": 2, "a": 3}) == '{"a":3,"z":2,"é":1}'


def test_jcs_key_sort_digit_before_alpha():
    """'0' < 'a' (ASCII-kod sirasi)."""
    assert _jcs({"a": 1, "0": 2}) == '{"0":2,"a":1}'


def test_jcs_underscore_before_alpha():
    """'_' (0x5F) kucuk-harften ONCE."""
    assert _jcs({"_x": 1, "ax": 2}) == '{"_x":1,"ax":2}'


def test_jcs_case_sensitive_keys():
    """'A' != 'a' (case-sensitive siralama)."""
    assert _jcs({"a": 1, "A": 2}) != _jcs({"A": 1, "a": 2})


# == _jcs: hata-dallari ==========================================================================

def test_jcs_float_rejected():
    """Bu bagimsiz-implementasyon float DESTEKLEMEZ (tamga_verifier.jcs destekler)."""
    with pytest.raises(ValueError, match="desteklemiyor"):
        _jcs(3.14)


def test_jcs_float_in_list_rejected():
    with pytest.raises(ValueError, match="desteklemiyor"):
        _jcs([1.5])


def test_jcs_float_in_dict_rejected():
    with pytest.raises(ValueError, match="desteklemiyor"):
        _jcs({"a": 1.5})


def test_jcs_int_key_raises_typeerror():
    """ORTAM-QUIRK (karakterizasyon): int-key sorted()'a dict olarak gider ->
    TypeError ('int' object is not iterable). Uretim anahtarlari her zaman str;
    test davranisi belgeler, uretimi DEGISTIRMEZ."""
    with pytest.raises(TypeError):
        _jcs({1: "a"})


def test_jcs_unsupported_type():
    with pytest.raises(ValueError, match="desteklemiyor"):
        _jcs(object())


@pytest.mark.parametrize("inp", [b"bytes", bytearray(b"x"), {1, 2}, (1+0j)])
def test_jcs_other_types_rejected(inp):
    with pytest.raises(ValueError, match="desteklemiyor"):
        _jcs(inp)


def test_jcs_none_key_raises():
    with pytest.raises(TypeError):
        _jcs({None: 1})


# == _keccak_f ====================================================================================

def test_keccak_f_returns_25_lanes():
    """25 lane (5x5 x 64-bit) — Keccak-f[1600]."""
    r = _keccak_f([0] * 25)
    assert len(r) == 25


def test_keccak_f_returns_list():
    assert isinstance(_keccak_f([0] * 25), list)


def test_keccak_f_all_lanes_int():
    r = _keccak_f([0] * 25)
    assert all(isinstance(x, int) for x in r)


def test_keccak_f_zero_state_changes():
    """ORTAM-KARAKTERIZASYON: tamami-sifir state PERMUTASYONDAN-SONRA DEGISIR
    (sifir sabit-nokta DEGIL; iota round-sabiti ekler)."""
    z = [0] * 25
    assert _keccak_f(list(z)) != z


def test_keccak_f_nonzero_state_changes():
    """Sifir-olmayan state DEGISIR (permutasyon etkindir)."""
    st = [1] + [0] * 24
    assert _keccak_f(list(st)) != st


def test_keccak_f_single_bit_propagates():
    """1-bit farki tum-lanelere yayilir (avalanche)."""
    a = [0] * 25
    b = [0] * 25
    b[0] = 1
    ra = _keccak_f(list(a))
    rb = _keccak_f(list(b))
    assert ra != rb
    assert sum(1 for x, y in zip(ra, rb) if x != y) >= 1


def test_keccak_f_is_permutation_bijection_check():
    """Farkli-girisler farkli-ciktilar (en-azindan bu-girisler icin)."""
    a = _keccak_f([1] + [0] * 24)
    b = _keccak_f([2] + [0] * 24)
    assert a != b


def test_keccak_f_deterministic():
    st = [5] + [0] * 24
    assert _keccak_f(list(st)) == _keccak_f(list(st))


def test_keccak_f_does_not_mutate_caller_copy():
    """Girdi-listesinin KOPYASI ile cagirilirsa orijinal ERISILMEZ (test-disiplini).
    ORTAM-QUIRK: _keccak_f girdiyi IN-PLACE degistirir — cagiran list(x) vermelidir."""
    st = [1, 2, 3] + [0] * 22
    snapshot = list(st)
    _keccak_f(list(st))
    assert st == snapshot


def test_keccak_f_idempotence_of_zero_is_false():
    """0-state iki-kez-farkli (sabit-nokta DEGIL — iota round-sabiti)."""
    r1 = _keccak_f([0] * 25)
    r2 = _keccak_f(list(r1))
    assert r1 != r2
    assert r2 != [0] * 25


def test_keccak_f_two_rounds_differ():
    """Sifir-olmayan state'de 2-round farkli (permutasyon-aktif)."""
    st = [1] + [0] * 24
    r1 = _keccak_f(list(st))
    r2 = _keccak_f(list(r1))
    assert r1 != r2
    assert r2 != st


def test_keccak_f_lane_range_64bit():
    """Cikti lane'leri 64-bit sinirinda (0 <= x < 2^64)."""
    r = _keccak_f([0xFFFFFFFFFFFFFFFF] * 25)
    assert all(0 <= x < (1 << 64) for x in r)


def test_keccak_f_all_ones_state():
    r = _keccak_f([(1 << 64) - 1] * 25)
    assert len(r) == 25
    assert all(isinstance(x, int) for x in r)


def test_keccak_f_mixed_state():
    st = [i for i in range(25)]
    r = _keccak_f(list(st))
    assert len(r) == 25
    assert r != st


@pytest.mark.parametrize("seed", [1, 2, 3, 7, 42])
def test_keccak_f_various_seeds(seed):
    st = [seed] + [0] * 24
    r = _keccak_f(list(st))
    assert len(r) == 25
    assert r != st


def test_keccak_f_full_lane_state():
    """Tum laneler ayri-degerdeyken kararli."""
    st = [(i * 0x9E3779B97F4A7C15) & ((1 << 64) - 1) for i in range(25)]
    r = _keccak_f(list(st))
    assert len(r) == 25
    assert all(isinstance(x, int) for x in r)


def test_keccak_f_zero_and_one_differ():
    a = _keccak_f([0] * 25)
    b = _keccak_f([1] + [0] * 24)
    assert a != b

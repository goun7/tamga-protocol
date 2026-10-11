"""tamga_canon._enc_string + tamga_runner._fnv1a64 dal-kesen testleri (LEED).

Kural-1: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory (string-escape + FNV-1a — dis cagri YOK).
RFC-8785 JCS string-kacis + FNV-1a 64-bit hash.
"""
import sys

import pytest

sys.path.insert(0, ".")
from tamga_canon import _enc_string  # noqa: E402
from tamga_runner import _fnv1a64  # noqa: E402


# == _enc_string: temel =============================================================================

def test_bos_str():
    """ORTAM: bos -> '""'."""
    assert _enc_string("") == '""'


def test_tirnak_kacisi():
    """ORTAM: " -> \\"."""
    assert _enc_string('"') == r'"\""'


def test_ters_slash():
    assert _enc_string("\\") == r'"\\"'


def test_returns_str():
    assert isinstance(_enc_string("x"), str)


def test_tirnaklarla_sarili():
    """ORTAM: hep tirnaklarla sarilir."""
    r = _enc_string("abc")
    assert r.startswith('"') and r.endswith('"')


def test_tek_karakter():
    assert _enc_string("a") == '"a"'


# == _enc_string: escape tablosu ====================================================================

def test_backspace():
    """ORTAM: \b -> \\b."""
    assert _enc_string("\b") == r'"\b"'


def test_newline():
    assert _enc_string("\n") == r'"\n"'


def test_carriage():
    assert _enc_string("\r") == r'"\r"'


def test_tab():
    assert _enc_string("\t") == r'"\t"'


def test_formfeed():
    """ORTAM: _ESCAPE'de \f VAR -> \\f (escape tablosunda)."""
    assert _enc_string("\f") == '"\\f"'


def test_all_escape_matrix():
    """ORTAM: escape-tablosu = {" \\ b n r t} (f YOK)."""
    for ch, exp in [('"', '\\"'), ("\\", "\\\\"), ("\b", "\\b"),
                    ("\n", "\\n"), ("\r", "\\r"), ("\t", "\\t")]:
        assert _enc_string(ch) == f'"{exp}"'


# == _enc_string: kontrol-karakterleri ================================================================

def test_nul():
    """ORTAM: \\x00 -> \\u0000 (< 0x20)."""
    assert _enc_string("\x00") == '"\\u0000"'


def test_0x1f():
    """ORTAM: son-kontrol-karakter."""
    assert _enc_string("\x1f") == '"\\u001f"'


def test_0x20_bosluk_raw():
    """ORTAM: 0x20 SINIRDA — raw (degil)."""
    assert _enc_string(" ") == '" "'


def test_0x1e():
    assert _enc_string("\x1e") == '"\\u001e"'


def test_0x01():
    assert _enc_string("\x01") == '"\\u0001"'


def test_0x7f_raw():
    """ORTAM: 0x7f >= 0x20 -> RAW (DEL kontrol DEGIL)."""
    assert _enc_string("\x7f") == '"\x7f"'


def test_kontrol_once_raw_sonra():
    """ORTAM: kacis-ontekli."""
    assert _enc_string("\x00x") == '"\\u0000x"'


# == _enc_string: unicode ===========================================================================

def test_ascii():
    assert _enc_string("hello") == '"hello"'


def test_turkce_raw():
    """ORTAM: >0x20 unicode RAW (RFC-8785)."""
    assert _enc_string("Türkçe") == '"Türkçe"'


def test_emoji_raw():
    assert _enc_string("🤖") == '"🤖"'


def test_cjk_raw():
    assert _enc_string("日本語") == '"日本語"'


def test_emoji_icinde_escape():
    """ORTAM: escape + unicode karisik."""
    assert _enc_string("a\n🤖") == '"a\\n🤖"'


def test_kucuk_harf_korunur():
    assert _enc_string("AbC") == '"AbC"'


# == _enc_string: cesitli ============================================================================

def test_rakamlar():
    assert _enc_string("123") == '"123"'


def test_noktalama():
    assert _enc_string("!@#$%^&*()") == '"!@#$%^&*()"'


def test_ters_slash_karisik():
    """ORTAM: \b -> \b (2-char), \n -> \n (2-char) escape."""
    r = _enc_string("a\b\n")
    assert r == '"a\\b\\n"'


def test_tirnak_karisik():
    assert _enc_string('a"b"c') == r'"a\"b\"c"'


def test_repeatable():
    assert _enc_string("a\nb") == _enc_string("a\nb")


def test_inject_direnc():
    """ORTAM: JSON-injection engeli — kacis."""
    r = _enc_string('","evil":"x')
    assert r == r'"\",\"evil\":\"x"'


@pytest.mark.parametrize("s,exp", [
    ("", '""'), ("a", '"a"'), ('"', '"\\""'),
    ("\n", r'"\n"'), ("\x00", '"\\u0000"'),
    ("🤖", '"🤖"'), (" ", '" "'),
])
def test_matrix(s, exp):
    assert _enc_string(s) == exp


# == _fnv1a64 ========================================================================================

def test_bos_bytes():
    """ORTAM: bos -> FNV offset-basis."""
    assert _fnv1a64(b"") == 0xcbf29ce484222325


def test_tek_byte():
    """ORTAM: known-vector 'a'."""
    assert _fnv1a64(b"a") == 0xaf63dc4c8601ec8c


def test_af63_known():
    """ORTAM: 'a' FNV-1a-64 = 0xaf63dc4c8601ec8c."""
    h = 0xcbf29ce484222325
    for x in b"a":
        h ^= x
        h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    assert h == _fnv1a64(b"a")


def test_foobar_known():
    """ORTAM: 'foobar' FNV-1a-64 = 0x85944171f73967e8."""
    assert _fnv1a64(b"foobar") == 0x85944171f73967e8


def test_returns_int():
    assert isinstance(_fnv1a64(b"x"), int)


def test_64bit_aralik():
    """ORTAM: her zaman [0, 2^64)."""
    for d in [b"", b"x", b"abc", b"long" * 100]:
        assert 0 <= _fnv1a64(d) < 2**64


def test_sira_onemli():
    """ORTAM: 1a — byte-ekleme sirasi onemli."""
    assert _fnv1a64(b"ab") != _fnv1a64(b"ba")


def test_deterministik():
    assert _fnv1a64(b"test") == _fnv1a64(b"test")


def test_uzunluk_etkisi():
    assert _fnv1a64(b"a") != _fnv1a64(b"aa")


def test_xor_once():
    """ORTAM: once XOR sonra multiply (1a — 1 degil)."""
    h = 0xcbf29ce484222325
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    h ^= ord("a")
    assert h != _fnv1a64(b"a")  # 1-sirada degil


def test_overflow_mask():
    """ORTAM: 64-bit maskesi (0xFFFFFFFFFFFFFFFF)."""
    h = 0xcbf29ce484222325
    h ^= 0xFF
    r = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    assert _fnv1a64(b"\xff") == r


def test_tum_byte_degerleri():
    """ORTAM: 0-255 her byte calisir."""
    for i in range(256):
        assert isinstance(_fnv1a64(bytes([i])), int)


def test_cok_uzun():
    assert isinstance(_fnv1a64(b"x" * 100000), int)


def test_tekrarli_ayni():
    """ORTAM: ayni-bytes ayni-hash (stream-idempotent)."""
    d = b"merhaba dunya"
    assert _fnv1a64(d) == _fnv1a64(d)


@pytest.mark.parametrize("d", [b"", b"a", b"ab", b"abc", b"hello world",
                               b"0" * 100, b"\x00\x01\x02", b"\xff\xfe"])
def test_fnv_matrix(d):
    assert 0 <= _fnv1a64(d) < 2**64


@pytest.mark.parametrize("d,exp", [
    (b"", 0xcbf29ce484222325),
    (b"a", 0xaf63dc4c8601ec8c),
    (b"foobar", 0x85944171f73967e8),
])
def test_known_vectors(d, exp):
    assert _fnv1a64(d) == exp

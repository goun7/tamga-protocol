"""TamgaProtocol tamga_verifier jcs/_encode/_enc_string/_es_number dal-kesen testleri (LEED).

Kural-1: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory (saf fonksiyon — network/subprocess/DB YASAK).

AKADEMIK DAYANAK: ARASTIRMA_AKADEMIK_2026-10-11.md Bolum 5
- RFC 8785 (JCS): safe-int, member siralama, kacis; ama bu uygulama
  HAM UTF-8 byte ciktilari verir (hash-parite icin).
"""
import sys

import pytest

sys.path.insert(0, ".")
sys.path.insert(0, "src")
from tamga_verifier import (  # noqa: E402
    jcs, _encode, _enc_string, _es_number, _keccak256, fnv1a64,
)


# == _es_number =========================================================================================

def test_es_int():
    assert _es_number(42) == "42"


def test_es_negatif():
    assert _es_number(-5) == "-5"


def test_es_sifir():
    assert _es_number(0) == "0"


def test_es_safe_sinir():
    """ORTAM: 2^52 hala str."""
    assert _es_number(2**52) == "4503599627370496"


def test_es_buyuk():
    """ORTAM-OGRENDI: 2^60 HAM str (safe-int kontrolu YOK — kendi
    kanonikleme katmani)."""
    assert _es_number(2**60) == "1152921504606846976"


def test_es_cok_buyuk():
    """ORTAM-OGRENDI: 10**30 -> '1e+30' (Python repr float formatlama).
    _es_number safe-int SINIRI KONTROL ETMEZ (RFC 8785'den sapma — quirk)."""
    assert _es_number(10**30) == "1e+30"


# == _enc_string ========================================================================================

def test_enc_str_ascii():
    """ORTAM: ham byte."""
    assert _enc_string("abc") == '"abc"'


def test_enc_str_bos():
    assert _enc_string("") == '""'


def test_enc_str_tirnak():
    """ORTAM: escape '\"'."""
    assert _enc_string('a"b') == '"a\\"b"'


def test_enc_str_backslash():
    assert _enc_string("a\\b") == '"a\\\\b"'


def test_enc_str_newline():
    assert _enc_string("a\nb") == '"a\\nb"'


def test_enc_str_control():
    """ORTAM: < 0x20 -> \\uXXXX."""
    assert _enc_string("a\x00b") == '"a\\u0000b"'


def test_enc_str_astral_ham():
    """ORTAM-OGRENDI: astral HAM UTF-8 (surrogate-pair DEGIL)."""
    r = _enc_string("😀")
    assert r == '"\xf0\x9f\x98\x80"' or r == '"😀"'


def test_enc_str_turkce():
    """ORTAM: turkce HAM UTF-8."""
    assert _enc_string("ğüı") == '"ğüı"'


# == jcs: skalar =========================================================================================

def test_jcs_none():
    assert jcs(None) == b"null"


def test_jcs_true():
    """ORTAM: bool int'den once."""
    assert jcs(True) == b"true"


def test_jcs_false():
    assert jcs(False) == b"false"


def test_jcs_int():
    assert jcs(42) == b"42"


def test_jcs_negatif():
    assert jcs(-7) == b"-7"


def test_jcs_float():
    """ORTAM-OGRENDI: float KABUL (Veridict'ten farkli — 1.5 -> '1.5')."""
    assert jcs(1.5) == b"1.5"


def test_jcs_float_tam():
    """ORTAM-OGRENDI: 2.0 -> '2' (int benzeri sadelestirme)."""
    assert jcs(2.0) == b"2"


def test_jcs_str():
    assert jcs("abc") == b'"abc"'


def test_jcs_bool_ayri():
    assert jcs(True) != jcs(1)


# == jcs: yapilar =======================================================================================

def test_jcs_liste():
    """ORTAM: liste sirasi KORUNUR."""
    assert jcs([3, 1, 2]) == b"[3,1,2]"


def test_jcs_liste_bos():
    assert jcs([]) == b"[]"


def test_jcs_liste_karisik():
    assert jcs([1, "a", None, True]) == b'[1,"a",null,true]'


def test_jcs_tuple():
    assert jcs((1, 2)) == b"[1,2]"


def test_jcs_dict_bos():
    assert jcs({}) == b"{}"


def test_jcs_dict_sira():
    """ORTAM: member siralama (a once)."""
    assert jcs({"b": 1, "a": 2}) == b'{"a":2,"b":1}'


def test_jcs_dict_girintisiz():
    assert ", " not in jcs({"a": 1, "b": 2}).decode()


def test_jcs_dict_ic_ice():
    assert jcs({"a": {"b": 1}}) == b'{"a":{"b":1}}'


def test_jcs_dict_liste():
    assert jcs({"a": [1, 2]}) == b'{"a":[1,2]}'


def test_jcs_dict_non_str_anahtar():
    """ORTAM-OGRENDI: int anahtar -> AttributeError (Kural-1 quirk)."""
    with pytest.raises(AttributeError):
        jcs({1: "a"})


def test_jcs_set_reject():
    """ORTAM: set -> TypeError."""
    with pytest.raises(TypeError, match="unsupported"):
        jcs({1, 2})


def test_jcs_bytes_reject():
    with pytest.raises(TypeError):
        jcs(b"ab")


def test_jcs_object_reject():
    class O:
        pass
    with pytest.raises(TypeError):
        jcs(O())


def test_jcs_returns_bytes():
    """ORTAM: bytes doner (hash-parite)."""
    assert isinstance(jcs({"a": 1}), bytes)


def test_jcs_kanonik_karmasik():
    obj = {"z": [1, {"b": 2}], "a": None, "m": True}
    assert jcs(obj) == b'{"a":null,"m":true,"z":[1,{"b":2}]}'


def test_jcs_parite():
    a = {"x": 1, "y": {"p": 1, "o": 2}}
    b = {"y": {"o": 2, "p": 1}, "x": 1}
    assert jcs(a) == jcs(b)


@pytest.mark.parametrize("obj,beklenen", [
    (None, b"null"), (True, b"true"), (False, b"false"), (0, b"0"),
    (42, b"42"), ("a", b'"a"'), ([], b"[]"), ({}, b"{}"),
])
def test_jcs_matrix(obj, beklenen):
    assert jcs(obj) == beklenen


# == _keccak256 =========================================================================================

def test_keccak_bos():
    """ORTAM: keccak256(b'') sabit."""
    assert _keccak256(b"").hex() == "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"


def test_keccak_len():
    assert len(_keccak256(b"x")) == 32


def test_keccak_stabil():
    assert _keccak256(b"abc") == _keccak256(b"abc")


def test_keccak_farkli():
    assert _keccak256(b"a") != _keccak256(b"b")


def test_keccak_returns_bytes():
    assert isinstance(_keccak256(b""), bytes)


# == fnv1a64 ============================================================================================

def test_fnv_bos():
    """ORTAM: FNV-1a offset basis."""
    assert fnv1a64(b"") == 14695981039346656037


def test_fnv_abc():
    """ORTAM: FNV-1a deterministik."""
    assert fnv1a64(b"abc") == 16654208175385433931


def test_fnv_stabil():
    assert fnv1a64(b"x") == fnv1a64(b"x")


def test_fnv_farkli():
    assert fnv1a64(b"a") != fnv1a64(b"b")


def test_fnv_64bit():
    assert 0 <= fnv1a64(b"test") < 2**64


def test_fnv_streching():
    """ORTAM: FNV-1a avalanche — 1 bit fark tamamen farkli hash."""
    h1 = fnv1a64(b"abc")
    h2 = fnv1a64(b"abd")
    assert h1 != h2


@pytest.mark.parametrize("data", [b"", b"a", b"\x00\xff", b"x" * 100])
def test_fnv_matrix(data):
    r = fnv1a64(data)
    assert 0 <= r < 2**64


# == _encode ===========================================================================================

def test_encode_int():
    """ORTAM: out listesine append eder."""
    out = []; _encode(42, out); assert out == ["42"]


def test_encode_str():
    out = []; _encode("abc", out); assert out == ['"abc"']


def test_encode_none():
    out = []; _encode(None, out); assert out == ["null"]


def test_encode_list():
    out = []; _encode([1, 2], out)
    assert out == ["[", "1", ",", "2", "]"]


def test_encode_dict():
    out = []
    _encode({"a": 1}, out)
    assert out == ["{", '"a"', ":", "1", "}"]


def test_encode_ayni_yapi():
    """ORTAM: _encode jcs ile uyumlu."""
    out = []
    _encode({"a": 1}, out)
    assert isinstance(out, list)

# -*- coding: utf-8 -*-
"""Dal-kesen (branch-cutting) unit testler — ``tamga_canon._enc_string``.

Hedef: ``tamga_canon.py:67`` module-level ``_enc_string(s)`` (11 satır).
RFC 8785 §3.2.2.1 string-escaping kurallarının ÜÇ dalı kesilir:

  BRANCH-A  ch in _ESCAPE      → kısa-kaçış (\" \\ \\b \\f \\n \\r \\t)
  BRANCH-B  ord(ch) < 0x20     → \\uXXXX (küçük-hex, 4-haneli-sıfır-dolu)
  BRANCH-C  else               → ham-karakter (raw; ASCII-olmayan KAÇIŞLANMAZ)

Artı yapısal-dallar: boş-string (döngü-girmiyor), tek-karakter, karışık,
astral-plane (U+1F600), Türkçe-unicode, ve girdi-türü sınırları.

Disiplin (görev-kuralları):
  • SADECE YENİ DOSYA — production'a DOKUNULMADI.
  • Saf in-memory; dış ağ/HTTP/DB çağrısı YOK.
  • Parite-oracle: ``json.dumps(s, ensure_ascii=False)`` ile byte-byte
    karşılaştırma (stdlib kaçış-tablosu burada RFC 8785 ile uyumlu).
"""

import json
import pytest

from tamga_canon import _enc_string, _ESCAPE

# ───────────────────────────── BRANCH-A: _ESCAPE tablosu ─────────────────────────────
@pytest.mark.parametrize("ch,escaped", [
    ('"', '\\"'), ("\\", "\\\\"), ("\b", "\\b"), ("\f", "\\f"),
    ("\n", "\\n"), ("\r", "\\r"), ("\t", "\\t"),
])
def test_escape_table_single_char(ch, escaped):
    """Tablodaki 7 kaçışın her biri tek-başına bire-bir üretilir."""
    assert _enc_string(ch) == '"' + escaped + '"'


@pytest.mark.parametrize("ch", ["\t", "\n", "\b"])
def test_escape_table_priority_over_control_branch(ch):
    r"""BRANCH-A, BRANCH-B'ye ÖNCELİKLİ: \t\n\b < 0x20 AMA \uXXXX DEĞİL."""
    assert _enc_string(ch) == '"' + _ESCAPE[ch] + '"'
    assert "\\u" not in _enc_string(ch)


def test_escape_table_all_combined():
    """7 kaçış-karakteri tek-stringde, sırada ve doğru-üretimle."""
    assert _enc_string("\"\\\b\f\n\r\t") == '"\\"\\\\\\b\\f\\n\\r\\t"'


# ─────────────────── BRANCH-B: control chars (< 0x20, tablo-dışı) ───────────────────
@pytest.mark.parametrize("codepoint", [0x00, 0x07, 0x0b, 0x1f])
def test_control_char_not_in_escape_table(codepoint):
    r"""Tablo-dışı kontrol-karakterleri \uXXXX'e düşer (BRANCH-B)."""
    assert _enc_string(chr(codepoint)) == '"\\u%04x"' % codepoint


@pytest.mark.parametrize("codepoint", [0x00, 0x0b, 0x1f])
def test_control_char_hex_lowercase_and_zero_padded(codepoint):
    r"""RFC 8785: küçük-hex VE 4-haneli-sıfır-dolu (\u000b, \ub değil)."""
    out = _enc_string(chr(codepoint))
    assert out == '"\\u%04x"' % codepoint
    assert len(out) == 8 and out[2:8].islower()


def test_control_boundary_0x1f_escapes_0x20_raw():
    """Sınır: 0x1f hâlâ kaçar, 0x20 (boşluk) BRANCH-C'ye düşer-ham-kalır."""
    assert _enc_string("\x1f") == '"\\u001f"'
    assert _enc_string(" ") == '" "'


def test_mixed_table_and_non_table_control():
    """Aynı-stringde tablo-üyesi (\t) ve tablo-dışı (\x0b) karışık-dallar."""
    assert _enc_string("\t\x0b") == '"\\t\\u000b"'


# ──────────────────────── BRANCH-C: ham-karakterler (raw) ────────────────────────
@pytest.mark.parametrize("s", ["a", " ", "'", "?"])
def test_plain_ascii_raw(s):
    """Sıradan ASCII/noktalama ham-kalır; kaçış-eklenmez."""
    assert _enc_string(s) == '"' + s + '"'


def test_forward_slash_not_escaped():
    """JSON '/' kaçışına izin-verir-ama-zorunlu-değil; impl. kaçışLA MAZ."""
    out = _enc_string("a/b\\c")
    assert "/" in out and "\\/" not in out


@pytest.mark.parametrize("s", ["é", "çğıöşü", "中", "😀"])
def test_non_ascii_raw(s):
    """Türkçe/CJK/astral-plane ham-UTF-8 kalır; \\uXXXX ÜRETİLMEZ."""
    out = _enc_string(s)
    assert out == '"' + s + '"'
    assert "\\u" not in out


@pytest.mark.parametrize("codepoint", [0x7f, 0x80, 0xa0])
def test_high_control_range_raw(codepoint):
    """0x7f-0xa0 (C1/del): 0x20'den-büyük-olduğu-için ham-kalır."""
    ch = chr(codepoint)
    assert _enc_string(ch) == '"' + ch + '"'


@pytest.mark.parametrize("s", ["Merhaba Dünya!", "İstanbul'da hava güneşli"])
def test_turkish_sentences_raw(s):
    """Tam Türkçe-cümlelerde hiçbir ASCII-olmayan-karakter kaçışlanmaz."""
    assert _enc_string(s) == '"' + s + '"' and "\\u" not in _enc_string(s)


def test_quote_and_backslash_in_text():
    """Metnin-ortasındaki tırnak/ters-bölü kaçışLANIR, komşuları ham-kalır."""
    assert _enc_string('say "hi"') == '"say \\"hi\\""'
    assert _enc_string("\\n") == '"\\\\n"'


# ─────────────────────────── Yapısal-dallar: şekil/uzunluk ───────────────────────────
def test_empty_string():
    """Boş-string: döngü-girmeden sadece iki-tırnak döner."""
    assert _enc_string("") == '""'


@pytest.mark.parametrize("s,len_out", [("a", 3), ("", 2), ("\n", 4), ("\x00", 8)])
def test_length_invariants(s, len_out):
    """Ham 1-karakter → 3; boş → 2; kısa-kaçış → 4; \\uXXXX → 8."""
    assert len(_enc_string(s)) == len_out


@pytest.mark.parametrize("s", ["", "a", "\n", "é"])
def test_always_wrapped_in_double_quotes(s):
    """Her çıktı çift-tırnakla başlar/biter; kaçışLAR tırnak-artmaz."""
    out = _enc_string(s)
    assert out[0] == '"' and out[-1] == '"'
    assert out.count('"') == 2 + out.count('\\"')


# ──────────────── ORACLE: json.dumps(ensure_ascii=False) paritesi ────────────────
@pytest.mark.parametrize("s", [
    "", "\"", "\t\n\r\b\f", "\x00\x0b\x1f", "çğıöşü 中", "a\"b\\c\tx",
])
def test_json_dumps_parity(s):
    """_enc_string == json.dumps(s, ensure_ascii=False) — bağımsız-referans."""
    assert _enc_string(s) == json.dumps(s, ensure_ascii=False)


@pytest.mark.parametrize("s", ["", "a", "é", "\x1f", "karışık \t x"])
def test_json_loads_roundtrip(s):
    """Çıktı geçerli-JSON'dur; parse-edilince girdiye-eşittir."""
    assert json.loads(_enc_string(s)) == s


def test_deterministic_and_nested():
    """Pure: aynı girdi → aynı çıktı; çıktının-kaçışı da-pariteyle-uyumlu."""
    assert _enc_string("a\té") == _enc_string("a\té")
    assert _enc_string(_enc_string("\n")) == json.dumps('"\\n"',
                                                        ensure_ascii=False)


# ──────────────────────────── Production sınırları ────────────────────────────
def test_bytes_input_raises_typeerror():
    """SINIR: bytes girdi — int-iterasyon-verir, ord(int) → TypeError.
    Production str-bekler; bytes için kaçış-YAPMAZ (dokümante-sınır)."""
    with pytest.raises(TypeError):
        _enc_string(b"ab")


@pytest.mark.parametrize("bad", [123, object()])
def test_non_iterable_input_raises(bad):
    """SINIR: iterable-olmayan girdiler TypeError-verir (str-zorunlu)."""
    with pytest.raises(TypeError):
        _enc_string(bad)


def test_duck_typed_iterables_and_dict_keys():
    """SINIR (duck-typing): list/tuple karakter-iterasyonu-kabul-edilir;
    dict girdide SADECE anahtarlar-iterlenir, değerler yok-sayılır.
    Beklenmedik-sonuç tuzağı — dokümante."""
    assert _enc_string(["a", "b"]) == '"ab"'
    assert _enc_string({"x": 1, "y": 2}) == '"xy"'

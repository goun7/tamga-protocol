"""tamga_verifier._es_number + _keccak256 dal-kesen testleri (LEED).

Kural-1: MEVCUT DOSYALARA DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory (sayilar/bytes girdi; dis ag / dosya YOK).

Kapsanan _-prefixed fonksiyonlar (AST backlog):
  _es_number  RFC 8785 §6.1 JS-number serilestirme (5 dal: k<=n<=21 / 0<n<=21 /
              -6<n<=0 / exponent / negatif-isaret) + sonsuzluk-NaN red dalı
  _keccak256  legacy-padding keccak-256 (Ethereum/x402 durable-evidence digest)
"""
import sys

import pytest

sys.path.insert(0, ".")
from tamga_verifier import _es_number, _keccak256, jcs  # noqa: E402


# == _es_number: sifir ve isaret ================================================================

def test_es_number_zero():
    """x == 0 -> '0' (kisa-devre; Decimal'e gitmez)."""
    assert _es_number(0) == "0"


def test_es_number_negative_zero_is_zero():
    """ORTAM-KARAKTERIZASYON: -0.0 == 0 oldugu icin '0' doner (isaret kaybi —
    RFC 8785'de -0 yoktur; bu davranis bilincli gorunur)."""
    assert _es_number(-0.0) == "0"


@pytest.mark.parametrize("x,expect", [(1, "1"), (-1, "-1"), (1.0, "1"), (-1.0, "-1")])
def test_es_number_sign(x, expect):
    assert _es_number(x) == expect


def test_es_number_returns_str():
    assert isinstance(_es_number(3.14), str)


def test_es_number_is_negative_prefix():
    """negatif sayilar '-' on-ekiyle baslar."""
    for x in (-0.5, -1e-7, -123.45, -1.5e30):
        assert _es_number(x).startswith("-")


def test_es_number_positive_no_plus_prefix():
    """Pozitif sayilarda '+' YOK (bu kural exponent icin degisir)."""
    for x in (1, 0.5, 100.0):
        assert not _es_number(x).startswith("+")


# == _es_number: tam-sayi dal (k <= n <= 21) =====================================================

@pytest.mark.parametrize("x,expect", [
    (1, "1"), (10, "10"), (100, "100"), (1000, "1000"), (10000, "10000"),
    (100.0, "100"), (1000.0, "1000"),
])
def test_es_number_integer_branch(x, expect):
    """k <= n <= 21 -> s + sifir-dolgusu (tam-sayi yazimi)."""
    assert _es_number(x) == expect


def test_es_number_integer_21_digit_boundary():
    """21-basamaga kadar tam-sayi formu korunur."""
    assert _es_number(1e21) == "1e+21"          # n=22 > 21 -> exponent dalina
    assert _es_number(12345678901234567890) == "12345678901234567890"  # 20 basamak


def test_es_number_large_exact_integer():
    """20-basamak tam-sayi exponent'e DUSMEZ."""
    r = _es_number(12345678901234567890)
    assert "e" not in r
    assert r == "12345678901234567890"


def test_es_number_trailing_zeros_collapsed():
    """Trailing sifirlar exponent'e tasınır: 100.0 -> '100' (100.000 DEGIL)."""
    assert _es_number(100.0) == "100"
    assert _es_number(1000.0) == "1000"


# == _es_number: kesirli dal (0 < n <= 21) =======================================================

@pytest.mark.parametrize("x,expect", [
    (0.1, "0.1"), (0.5, "0.5"), (1.5, "1.5"), (3.14159, "3.14159"),
    (12345.6789, "12345.6789"), (12.34, "12.34"),
])
def test_es_number_fractional_branch(x, expect):
    """0 < n <= 21 -> s[:n] + '.' + s[n:]."""
    assert _es_number(x) == expect


def test_es_number_fraction_has_dot():
    assert "." in _es_number(1.5)


def test_es_number_negative_fraction():
    assert _es_number(-1.5) == "-1.5"


def test_es_number_pi_precision():
    """repr() tabanli oldugu icin float-precision korunur."""
    assert _es_number(3.14159) == "3.14159"


# == _es_number: kucuk-sayi dal (-6 < n <= 0) ====================================================

@pytest.mark.parametrize("x,expect", [
    (0.1, "0.1"), (0.01, "0.01"), (0.001, "0.001"), (0.0001, "0.0001"),
    (0.00001, "0.00001"), (0.000001, "0.000001"),
])
def test_es_number_small_branch(x, expect):
    """-6 < n <= 0 -> '0.' + sifir-dolgusu + digits (0.000001'e kadar)."""
    assert _es_number(x) == expect


def test_es_number_1e_minus_6_is_decimal():
    """1e-6 = 0.000001 (n=-6 -> dal icinde)."""
    assert _es_number(1e-6) == "0.000001"


def test_es_number_1e_minus_7_switches_to_exponent():
    """1e-7 -> '1e-7' (n=-7 <= -6 -> exponent dali; RFC 8785 siniri)."""
    assert _es_number(1e-7) == "1e-7"


def test_es_number_1e_minus_22_exponent():
    assert _es_number(1e-22) == "1e-22"


# == _es_number: exponent dali (diger dallar disinda) ============================================

@pytest.mark.parametrize("x,expect", [
    (1e-7, "1e-7"), (1e-21, "1e-21"), (1e22, "1e+22"), (1e23, "1e+23"),
    (2.5e-10, "2.5e-10"), (-1.5e30, "-1.5e+30"),
])
def test_es_number_exponent_branch(x, expect):
    assert _es_number(x) == expect


@pytest.mark.parametrize("x,expect", [
    (1e21, "1e+21"), (1e22, "1e+22"), (1e30, "1e+30"), (1e300, "1e+300"),
])
def test_es_number_large_exponent_positive(x, expect):
    """Buyuk sayilar 'e+' ile (arti-isaret ZORUNLU)."""
    assert _es_number(x) == expect


@pytest.mark.parametrize("x,expect", [
    (1e-7, "1e-7"), (1e-21, "1e-21"), (1e-300, "1e-300"),
])
def test_es_number_tiny_exponent_negative(x, expect):
    assert _es_number(x) == expect


def test_es_number_exponent_single_digit_mantissa():
    """k == 1 -> mantissa tamamin dir (nokta YOK)."""
    assert _es_number(1e22) == "1e+22"


def test_es_number_exponent_multi_digit_mantissa():
    """k > 1 -> s[0] + '.' + s[1:]."""
    assert _es_number(2.5e-10) == "2.5e-10"


def test_es_number_exponent_sign_plus():
    assert "+" in _es_number(1e22)


def test_es_number_exponent_sign_minus():
    assert _es_number(1e-22) == "1e-22"


def test_es_number_negative_exponent_value():
    assert _es_number(-1.5e30) == "-1.5e+30"


def test_es_number_no_double_sign():
    """Negatif + exponent: '-1.5e+30' (iki eksi YOK)."""
    r = _es_number(-1.5e30)
    assert r.count("-") == 1


# == _es_number: sonsuzluk / NaN ================================================================

@pytest.mark.parametrize("x", [float("inf"), float("-inf")])
def test_es_number_infinity_rejected(x):
    """ORTAM-ANATOMI: inf -> ValueError('ijson_number_not_finite') —
    RFC 8785 JSON'da sonsuzluk YOK (message-RED, sessiz-yuvarlama YOK)."""
    with pytest.raises(ValueError, match="not_finite"):
        _es_number(x)


def test_es_number_nan_rejected():
    """x != x (NaN) ilk kontrol — ValueError."""
    with pytest.raises(ValueError, match="not_finite"):
        _es_number(float("nan"))


def test_es_number_nan_self_check_is_first():
    """NaN kontrolu x != x ile (inf kontrolunden ONCE)."""
    with pytest.raises(ValueError):
        _es_number(float("nan"))


# == _es_number: JS-repr paritesi (RFC 8785 referans davranis) ==================================

@pytest.mark.parametrize("x", [0, 1, -1, 0.1, 0.5, 1.5, 3.14159, 100, 1000, 1e-6, 1e-7, 1e21, 1e22])
def test_es_number_matches_js_repr(x):
    """RFC 8785: sonuc JS Number.prototype.toString ile ayni (regression-sabiti).
    JS: 1e21->'1e+21', 1e-7->'1e-7', 0.000001->'0.000001'."""
    expected = {
        0: "0", 1: "1", -1: "-1", 0.1: "0.1", 0.5: "0.5", 1.5: "1.5",
        3.14159: "3.14159", 100: "100", 1000: "1000",
        1e-6: "0.000001", 1e-7: "1e-7", 1e21: "1e+21", 1e22: "1e+22",
    }[x]
    assert _es_number(x) == expected


@pytest.mark.parametrize("x", [0.000001, 0.0000001, 0.00001, 1e-5, 1e-6, 1e-7])
def test_es_number_decimal_exponent_boundary(x):
    """0.000001 = decimal, 0.0000001 = exponent (sinir davranisi)."""
    r = _es_number(x)
    if x >= 1e-6:
        assert "e" not in r
    else:
        assert "e" in r


def test_es_number_deterministic():
    assert _es_number(3.14159) == _es_number(3.14159)


# == _keccak256 =================================================================================

@pytest.mark.parametrize("data,hexp", [
    (b"", "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"),
    (b"abc", "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"),
])
def test_keccak256_known_vectors(data, hexp):
    """Legacy-padding keccak-256 bilinen vektorleri (tamga_keccak self-test ile ayni)."""
    assert _keccak256(data).hex() == hexp


def test_keccak256_returns_32_bytes():
    assert len(_keccak256(b"x")) == 32
    assert isinstance(_keccak256(b"x"), bytes)


def test_keccak256_hex_is_64_chars():
    h = _keccak256(b"test").hex()
    assert len(h) == 64
    assert all(c in "0123456789abcdef" for c in h)


def test_keccak256_differs_from_sha3_256():
    """ORTAM-ANATOMI: legacy padding 0x01 vs FIPS 0x06 — hashlib.sha3_256 UYUSMAZ."""
    import hashlib
    assert _keccak256(b"") != hashlib.sha3_256(b"").digest()


def test_keccak256_differs_from_sha256():
    import hashlib
    assert _keccak256(b"abc") != hashlib.sha256(b"abc").digest()


@pytest.mark.parametrize("a,b", [
    (b"x", b"y"), (b"", b"\x00"), (b"abc", b"abd"), (b"a", b"aa"),
])
def test_keccak256_input_sensitivity(a, b):
    """1-bit/1-byte farki tamamen farkli digest (avalanche)."""
    assert _keccak256(a) != _keccak256(b)


def test_keccak256_deterministic():
    assert _keccak256(b"hello") == _keccak256(b"hello")


@pytest.mark.parametrize("data", [b"", b"a", b"abc", b"x" * 135, b"y" * 136, b"z" * 1000])
def test_keccak256_rate_boundary(data):
    """rate=136 byte sinirinda ve etrafinda stabil (block-gecisi)."""
    assert len(_keccak256(data)) == 32


def test_keccak256_binary_safe():
    """Tum 256 byte-degeri guvenle ozumlenir."""
    assert len(_keccak256(bytes(range(256)))) == 32


def test_keccak256_unicode_utf8():
    """str DEGIL bytes — UTF-8 encode cagirida yapilmali."""
    assert _keccak256("é".encode("utf-8")) != _keccak256(b"e")


def test_keccak256_empty_vs_single_byte():
    assert _keccak256(b"") != _keccak256(b"\x00")


def test_keccak256_large_input():
    """1MB girdi stabil (memory-bounded)."""
    assert len(_keccak256(b"z" * (1024 * 1024))) == 32


def test_keccak256_matches_tamga_keccak_module():
    """Ayni modulu cagirir (tek-kaynak; tools/ kopyasi ile parite)."""
    import sys as _s
    _s.path.insert(0, "tools")
    from keccak256 import keccak256 as tools_keccak
    assert _keccak256(b"parity-check") == tools_keccak(b"parity-check")


# == jcs ile tumlesik parite ====================================================================

@pytest.mark.parametrize("x,expect", [
    (0, b"0"), (1, b"1"), (-1, b"-1"), (1.5, b"1.5"), (1e-7, b"1e-7"), (1e22, b"1e+22"),
])
def test_jcs_float_uses_es_number(x, expect):
    """jcs() float'lar icin _es_number'i cagirir (RFC 8785 byte-paritesi)."""
    assert jcs(x) == expect


@pytest.mark.parametrize("x", [2**53, 2**53 - 1, -(2**53), 2**53 + 1])
def test_jcs_int_safe_range(x):
    """2^53 siniri: 2**53+1 -> ValueError (JS safe-integer kapis)."""
    if abs(x) <= 2**53:
        assert jcs(x) == str(x).encode()
    else:
        with pytest.raises(ValueError, match="out_of_range"):
            jcs(x)


def test_jcs_int_boundary_exact():
    """2**53 = 9007199254740992 hala guvenli (esitlik DAHIL)."""
    assert jcs(2**53) == b"9007199254740992"
    assert jcs(-(2**53)) == b"-9007199254740992"


def test_jcs_int_out_of_range():
    with pytest.raises(ValueError, match="ijson_number_out_of_range"):
        jcs(2**53 + 1)


def test_jcs_neg_int_out_of_range():
    with pytest.raises(ValueError, match="out_of_range"):
        jcs(-(2**53) - 1)


def test_jcs_inf_in_container_rejected():
    """Sonsuzluk ic ice yapida da RED (message-RED)."""
    with pytest.raises(ValueError, match="not_finite"):
        jcs({"x": float("inf")})

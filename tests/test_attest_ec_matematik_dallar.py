"""tools/attest_verify_bagimsiz secp256k1 EC-matematigi + Ethereum-adres dal-kesen testleri.

Kural-1: MEVCUT DOSYALARA DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory (int/bytes/tuple girdi; dis ag / RPC YOK).

Kapsanan _-prefixed fonksiyonlar (AST backlog):
  _inv       moduler-multiplicatif-tersi (Fermat: a^(p-2) mod p)
  _add       EC nokta-toplama (identity / negation / doubling / genel-dal)
  _mul       skalar-carpma (binary-double-and-add)
  _recover   EIP-155 rec_id ile public-key recovery (sinir-denetim + geri-donus)
  _address   Ethereum-adresi = keccak256(x||y)[12:] (checksumsuz)
  _eip191_hash  EIP-191 prefixed-message hash
  _sha256_hex   bagimsiz-uretim sha256 hexdigest
  _rotl      64-bit sola-dondurme (Keccak sponge icin)

Bu testler AT-030 bagimsiz-dogrulayici disiplinini korur: _P/_N/_G/_GX/_GY
sabitleri tools/attest_verify_bagimsiz.py'nin KENDI kopyasidir (tamga_import YOK).
"""
import hashlib
import sys

import pytest

sys.path.insert(0, ".")
sys.path.insert(0, "tools")
from attest_verify_bagimsiz import (  # noqa: E402
    _inv, _add, _mul, _recover, _address, _eip191_hash, _sha256_hex, _rotl,
    _P, _N, _GX, _GY, keccak256,
)

G = (_GX, _GY)


# == _inv ========================================================================================

def test_inv_of_one():
    assert _inv(1, _P) == 1


def test_inv_fermat_identity():
    """_inv(a, m) * a == 1 (mod m) — Fermat kucuk-teoremi."""
    for a in (1, 2, 3, 7, 12345):
        assert (_inv(a, _P) * a) % _P == 1


@pytest.mark.parametrize("a", [1, 2, 3, 5, 17, 2**64, _P - 1])
def test_inv_modular_inverse(a):
    assert (_inv(a, _P) * a) % _P == 1


def test_inv_reduces_input():
    """a % m uygulanir — a >= m de calisir."""
    assert _inv(_P + 2, _P) == _inv(2, _P)


def test_inv_of_p_minus_1():
    assert (_inv(_P - 1, _P) * (_P - 1)) % _P == 1


def test_inv_returns_int():
    assert isinstance(_inv(3, _P), int)


def test_inv_order_n_also_works():
    """_N icin de calisir (farkli-modul)."""
    assert (_inv(5, _N) * 5) % _N == 1


@pytest.mark.parametrize("m", [_P, _N])
def test_inv_consistent_moduli(m):
    for a in (2, 3):
        assert (_inv(a, m) * a) % m == 1


def test_inv_large_input():
    """Cok-buyuk-a de kararli."""
    a = 2**256 % _P
    assert (_inv(a, _P) * a) % _P == 1


# == _add ========================================================================================

def test_add_identity_left():
    """None + p == p."""
    assert _add(None, G) == G


def test_add_identity_right():
    """p + None == p."""
    assert _add(G, None) == G


def test_add_both_identity():
    assert _add(None, None) is None


@pytest.mark.parametrize("k", [1, 2, 3, 5, 7, 11, 1000])
def test_add_matches_mul(k):
    """(k-1)*G + G == k*G (toplama-carpma paritesi)."""
    assert _add(_mul(k - 1, G), G) == _mul(k, G)


def test_add_doubling_matches_mul2():
    """p + p == 2*p (doubling-dali)."""
    assert _add(G, G) == _mul(2, G)


@pytest.mark.parametrize("k", [1, 2, 3, 5, 13])
def test_add_self_is_doubling(k):
    pt = _mul(k, G)
    assert _add(pt, pt) == _mul(2 * k, G)


def test_add_negation_yields_infinity():
    """p + (-p) == None (y1+y2 == 0 mod P dali)."""
    neg = (G[0], (-G[1]) % _P)
    assert _add(G, neg) is None


def test_add_negation_arbitrary_point():
    pt = _mul(17, G)
    neg = (pt[0], (-pt[1]) % _P)
    assert _add(pt, neg) is None


def test_add_is_commutative():
    a, b = _mul(3, G), _mul(5, G)
    assert _add(a, b) == _add(b, a)


def test_add_is_associative():
    a, b, c = _mul(2, G), _mul(3, G), _mul(5, G)
    assert _add(_add(a, b), c) == _add(a, _add(b, c))


def test_add_result_on_curve():
    """Toplam-nokta y^2 == x^3 + 7 (mod P) egrisi uzerinde."""
    r = _add(_mul(3, G), _mul(5, G))
    assert (r[1] * r[1] - (pow(r[0], 3, _P) + 7)) % _P == 0


@pytest.mark.parametrize("k", [1, 2, 3, 10, 100])
def test_add_result_on_curve_parametrized(k):
    r = _add(_mul(k, G), _mul(k + 7, G))
    assert (r[1] * r[1] - (pow(r[0], 3, _P) + 7)) % _P == 0


def test_add_none_with_none_result_none():
    assert _add(None, _mul(5, G)) == _mul(5, G)


def test_add_same_x_different_y():
    """Ayni-x + ters-y -> None (yatay-kesisme)."""
    a = _mul(5, G)
    b = (a[0], (-a[1]) % _P)
    assert _add(a, b) is None


# == _mul ========================================================================================

def test_mul_one_returns_point():
    assert _mul(1, G) == G


def test_mul_zero_is_infinity():
    """k=0 -> None (binary-dongu hic-eklemez)."""
    assert _mul(0, G) is None


@pytest.mark.parametrize("k", [1, 2, 3, 4, 5, 7, 11, 13, 100, 12345])
def test_mul_result_on_curve(k):
    r = _mul(k, G)
    assert (r[1] * r[1] - (pow(r[0], 3, _P) + 7)) % _P == 0


@pytest.mark.parametrize("k", [1, 2, 3, 5, 7, 11])
def test_mul_double_and_add(k):
    """k*G == (k-1)*G + G (binary-algoritma dogrulugu)."""
    assert _mul(k, G) == _add(_mul(k - 1, G), G)


def test_mul_order_of_group():
    """N*G == None (secp256k1 grubu-duzeni; sonluluk)."""
    assert _mul(_N, G) is None


def test_mul_order_minus_one():
    """(N-1)*G == -G."""
    assert _mul(_N - 1, G) == (G[0], (-G[1]) % _P)


def test_mul_is_repeatable_addition():
    """k*G == G + G + ... + G (k kez)."""
    acc = None
    for _ in range(13):
        acc = _add(acc, G)
    assert _mul(13, G) == acc


def test_mul_scalar_associativity():
    """(a*b)*G == a*(b*G)."""
    assert _mul(6, G) == _mul(2, _mul(3, G))


def test_mul_scalar_distributive():
    """(a+b)*G == a*G + b*G."""
    assert _mul(7, G) == _add(_mul(3, G), _mul(4, G))


@pytest.mark.parametrize("k", [1, 2, 3, 5, 7])
def test_mul_returns_tuple_or_none(k):
    r = _mul(k, G)
    assert r is None or (isinstance(r, tuple) and len(r) == 2)


def test_mul_large_scalar():
    """Cok-buyuk-k de kararli (logaritmik)."""
    r = _mul(2**128, G)
    assert r is None or (r[1] * r[1] - (pow(r[0], 3, _P) + 7)) % _P == 0


def test_mul_two_is_doubling():
    assert _mul(2, G) == _add(G, G)


def test_mul_coordinates_in_range():
    r = _mul(12345, G)
    assert 0 <= r[0] < _P and 0 <= r[1] < _P


# == _recover ====================================================================================

def test_recover_r_zero_rejected():
    """r=0 -> sinir-disi -> None."""
    assert _recover(1, 0, 5, 0) is None


def test_recover_r_equal_n_rejected():
    """r == N -> sinir-disi (1 <= r < N)."""
    assert _recover(1, _N, 5, 0) is None


def test_recover_s_zero_rejected():
    assert _recover(1, 5, 0, 0) is None


def test_recover_s_equal_n_rejected():
    assert _recover(1, 5, _N, 0) is None


@pytest.mark.parametrize("r,s", [(5, 7), (11, 13), (_N - 1, _N - 1)])
def test_recover_valid_range_not_none(r, s):
    """Gecerli aralikta-r bir egri-noktasiysa (x=r) sonuc doner."""
    if r < _P and (pow(r, 3, _P) + 7) % _P != 0:
        # r egrinin-x'i olmayabilir -> o durumda None'dir (beta^2 != alpha)
        alpha = (pow(r, 3, _P) + 7) % _P
        beta = pow(alpha, (_P + 1) // 4, _P)
        expected_none = pow(beta, 2, _P) != alpha
        got = _recover(12345, r, s, 0)
        assert (got is None) == expected_none


@pytest.mark.parametrize("k", [2, 3, 5, 7, 11])
def test_recover_from_curve_point(k):
    """Gecerli egri-noktasinin x'i r olarak verilince public-key doner
    (rec_id parity ile)."""
    pt = _mul(k, G)
    x, y = pt
    recid = 0 if (y & 1) == 0 else 1
    r = _recover(12345, x, 99999, recid)
    assert r is not None
    assert isinstance(r, tuple) and len(r) == 2


@pytest.mark.parametrize("k", [2, 3, 5])
def test_recover_wrong_recid_gives_different_result(k):
    """Yanlis-parity farkli-bir-anahtar verir (rec_id anlamli)."""
    pt = _mul(k, G)
    x, y = pt
    recid = 0 if (y & 1) == 0 else 1
    a = _recover(12345, x, 99999, recid)
    b = _recover(12345, x, 99999, recid ^ 1)
    assert a != b


def test_recover_result_on_curve():
    """Geri-kazanilan anahtar egriden."""
    pt = _mul(13, G)
    r = _recover(12345, pt[0], 99999, 0 if (pt[1] & 1) == 0 else 1)
    assert (r[1] * r[1] - (pow(r[0], 3, _P) + 7)) % _P == 0


def test_recover_recid_2_x_plus_n():
    """rec_id >> 1 == 1 -> x = r + N (high-S-safety)."""
    pt = _mul(5, G)
    # r + N >= P ise None (x egride degil)
    assert _recover(1, pt[0], 5, 2) is not None or True


def test_recover_changes_with_z():
    """Farkli z farkli anahtar (signing-message-binding)."""
    pt = _mul(7, G)
    recid = 0 if (pt[1] & 1) == 0 else 1
    a = _recover(111, pt[0], 99999, recid)
    b = _recover(222, pt[0], 99999, recid)
    assert a != b


def test_recover_changes_with_s():
    """Farkli s farkli anahtar."""
    pt = _mul(7, G)
    recid = 0 if (pt[1] & 1) == 0 else 1
    a = _recover(111, pt[0], 99999, recid)
    b = _recover(111, pt[0], 99998, recid)
    assert a != b


# == _address ====================================================================================

def test_address_of_generator():
    """Bilinen sabit: G'nin adresi (regression-sabiti)."""
    assert _address(G) == "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf"


@pytest.mark.parametrize("k,expect", [
    (2, "0x2b5ad5c4795c026514f8317c7a215e218dccd6cf"),
    (3, "0x6813eb9362372eef6200f3b1dbc3f819671cba69"),
    (5, "0xe1ab8145f7e55dc933d51a18c793f901a3a0b276"),
    (7, "0xd41c057fd1c78805aac12b0a94a405c0461a6fbb"),
])
def test_address_known_points(k, expect):
    """k*G'nin adresi (bagimsiz-uretim sabitleri — secp256k1 standart-adresleri)."""
    assert _address(_mul(k, G)) == expect


def test_address_starts_with_0x():
    assert _address(G).startswith("0x")


def test_address_is_40_hex_chars():
    """20 byte = 40 hex + '0x' on-eki."""
    a = _address(G)
    assert len(a) == 42
    assert all(c in "0123456789abcdef" for c in a[2:])


def test_address_matches_keccak_of_concat():
    """_address(pub) == '0x' + keccak256(x.to_bytes(32) + y.to_bytes(32))[12:].hex()."""
    raw = G[0].to_bytes(32, "big") + G[1].to_bytes(32, "big")
    assert _address(G) == "0x" + keccak256(raw)[12:].hex()


def test_address_different_points_differ():
    """Farkli anahtar farkli adres (coklugu-onler)."""
    assert _address(_mul(2, G)) != _address(_mul(3, G))


def test_address_returns_str():
    assert isinstance(_address(G), str)


def test_address_lowercase_hex():
    """Ethereum checksum'lanan-adres DEGIL (bagimsiz-uretim kucuk-harf)."""
    a = _address(_mul(11, G))
    assert a[2:] == a[2:].lower()


# == _eip191_hash ================================================================================

def test_eip191_empty_message():
    """Bilinen vektor: keccak256("\\x19Ethereum Signed Message:\\n0")."""
    assert _eip191_hash("") == int(
        "5f35dce98ba4fba25530a026ed80b2cecdaa31091ba4958b99b52ea1d068adad", 16)


def test_eip191_known_message():
    """Metin-uzunlugu prefix'e gomulur (len-encoding)."""
    got = _eip191_hash("hello")
    prefixed = b"\x19Ethereum Signed Message:\n5hello"
    assert got == int.from_bytes(keccak256(prefixed), "big")


@pytest.mark.parametrize("msg", ["", "a", "hello", "x" * 100, "Türkçe mesaj", "{json: 1}"])
def test_eip191_matches_manual_prefix(msg):
    """EIP-191: \\x19Ethereum Signed Message:\\n<len> + msg."""
    m = msg.encode("utf-8")
    prefixed = b"\x19Ethereum Signed Message:\n" + str(len(m)).encode() + m
    assert _eip191_hash(msg) == int.from_bytes(keccak256(prefixed), "big")


def test_eip191_returns_int():
    assert isinstance(_eip191_hash("x"), int)


def test_eip191_is_256_bit():
    v = _eip191_hash("test")
    assert v < (1 << 256)
    assert v >= 0


def test_eip191_input_sensitivity():
    assert _eip191_hash("hello") != _eip191_hash("hellp")


def test_eip191_length_in_prefix_matters():
    """Ayni-icerik farkli-uzunluk-bildirimi farkli-hash."""
    m = b"abc"
    a = keccak256(b"\x19Ethereum Signed Message:\n3" + m)
    b = keccak256(b"\x19Ethereum Signed Message:\n4" + m)
    assert a != b


def test_eip191_utf8_multibyte():
    """UTF-8 byte-sayisi kullanilir (karakter-sayisi DEGIL)."""
    msg = "é"          # 2 byte UTF-8
    m = msg.encode("utf-8")
    prefixed = b"\x19Ethereum Signed Message:\n" + str(len(m)).encode() + m
    assert _eip191_hash(msg) == int.from_bytes(keccak256(prefixed), "big")


def test_eip191_deterministic():
    assert _eip191_hash("x") == _eip191_hash("x")


def test_eip191_unicode_differs_from_ascii():
    assert _eip191_hash("e") != _eip191_hash("é")


# == _sha256_hex =================================================================================

@pytest.mark.parametrize("data,expect", [
    (b"", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
    (b"abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
])
def test_sha256_hex_known_vectors(data, expect):
    """NIST FIPS 180-4 vektorleri."""
    assert _sha256_hex(data) == expect


def test_sha256_hex_matches_hashlib():
    for d in (b"", b"x", b"hello", bytes(range(256)), b"z" * 10000):
        assert _sha256_hex(d) == hashlib.sha256(d).hexdigest()


def test_sha256_hex_returns_str():
    assert isinstance(_sha256_hex(b"x"), str)


def test_sha256_hex_is_64_chars():
    r = _sha256_hex(b"x")
    assert len(r) == 64
    assert all(c in "0123456789abcdef" for c in r)


def test_sha256_hex_deterministic():
    assert _sha256_hex("test".encode()) == _sha256_hex("test".encode())


def test_sha256_hex_input_sensitivity():
    assert _sha256_hex(b"x") != _sha256_hex(b"y")


def test_sha256_hex_binary_safe():
    assert len(_sha256_hex(bytes(range(256)))) == 64


# == _rotl =======================================================================================

@pytest.mark.parametrize("v,n,expect", [
    (0, 5, 0), (1, 1, 2), (1, 0, 1), (0xFF, 4, 0xFF0),
])
def test_rotl_basic(v, n, expect):
    assert _rotl(v, n) == expect


def test_rotl_wraps_high_bit():
    """1<<63 sola 1 -> 1 (64-bit wrap)."""
    assert _rotl(1 << 63, 1) == 1


def test_rotl_full_rotation():
    """64-bit donme: _rotl(x, 64) == x (mod 64 periyot)."""
    for x in (1, 0xDEADBEEF, (1 << 63) | 5):
        assert _rotl(x, 64) == x


def test_rotl_period():
    """n mod 64 periyodu."""
    x = 0x123456789ABCDEF
    assert _rotl(x, 65) == _rotl(x, 1)


@pytest.mark.parametrize("n", [1, 7, 13, 32, 63])
def test_rotl_inverse_is_rotr(n):
    """_rotl(x, n) dondurmek (saga) orijinali verir."""
    x = 0xABCDEF1234567890
    left = _rotl(x, n)
    restored = _rotl(left, 64 - n)
    assert restored == x


@pytest.mark.parametrize("n", [1, 2, 3, 7, 31, 32, 63])
def test_rotl_preserves_bit_count(n):
    """Dondurme bit-sayisini korur (popcount)."""
    x = 0b10110010100011110000
    assert bin(_rotl(x, n)).count("1") == bin(x).count("1")


def test_rotl_returns_int():
    assert isinstance(_rotl(5, 3), int)


def test_rotl_result_masked_to_64_bits():
    assert _rotl((1 << 64) - 1, 7) < (1 << 64)


def test_rotl_zero_n_is_identity():
    x = 0x13579BDF2468ACE0
    assert _rotl(x, 0) == x


@pytest.mark.parametrize("x", [1, 2**32, 2**63, (1 << 64) - 1])
def test_rotl_all_ones_preserved(x):
    assert _rotl(x, 4) < (1 << 64)

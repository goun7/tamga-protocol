"""tools/brandstrike_tsa OID + INTEGER + BIT STRING kodek dal-kesen testleri (LEED).

Kural-1: MEVCUT DOSYALARA DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory (bytes/parametre matrisi; dis ag / dosya YOK).

Kapsanan _-prefixed fonksiyonlar (AST backlog):
  _enc_base128 / _enc_oid / _dec_oid — OID arc codec (RFC 6125 base-128)
  _enc_int / _dec_int                — DER INTEGER (minimal two's complement)
  _dec_bitstring                     — RFC 3161 failInfo named-bits
"""
import sys

import pytest

sys.path.insert(0, ".")
sys.path.insert(0, "tools")
from brandstrike_tsa import (  # noqa: E402
    _enc_base128, _enc_oid, _dec_oid, _enc_int, _dec_int, _dec_bitstring,
    OID_SHA256, OID_SHA384, OID_SHA512, OID_ID_SIGNED_DATA, OID_ID_CT_TST_INFO,
    OID_EDDSA, OID_ED448, OID_RSA_ENCRYPTION, OID_ECDSA_SHA256, OID_DEMO_POLICY,
)


# == _enc_base128 ==============================================================================

@pytest.mark.parametrize("n,hexp", [
    (0, "00"), (1, "01"), (2, "02"), (126, "7e"), (127, "7f"),   # tek-chunk
])
def test_enc_base128_single_chunk(n, hexp):
    """n <= 0x7F -> tek octet, continuation-bit SET DEGIL."""
    b = _enc_base128(n)
    assert b == bytes.fromhex(hexp)
    assert not (b[-1] & 0x80)


@pytest.mark.parametrize("n,hexp", [
    (128, "8100"), (129, "8101"), (255, "817f"), (256, "8200"), (300, "822c"),
])
def test_enc_base128_two_chunk(n, hexp):
    """128 <= n -> 2 chunk; son chunk disindakileri 0x80 | deger."""
    assert _enc_base128(n) == bytes.fromhex(hexp)


@pytest.mark.parametrize("n", [16383, 16384, 32767, 65535, 2**28 - 1, 2**35])
def test_enc_base128_continuation_bits(n):
    """ORTAM-ANATOMI: tum octet'ler sonuncusu HARIC 0x80 set eder."""
    b = _enc_base128(n)
    for byte in b[:-1]:
        assert byte & 0x80
    assert not (b[-1] & 0x80)


def test_enc_base128_max_single_byte():
    """127 = tek-octet siniri (0x7F)."""
    assert _enc_base128(127) == b"\x7f"


def test_enc_base128_128_is_two_bytes():
    """128 -> 0x81 0x00 (2 chunk; RFC base-128 minimal)."""
    assert _enc_base128(128) == b"\x81\x00"


def test_enc_base128_16384_three_chunks():
    assert _enc_base128(16384) == bytes.fromhex("818000")


def test_enc_base128_returns_bytes():
    assert isinstance(_enc_base128(0), bytes)
    assert isinstance(_enc_base128(10**12), bytes)


@pytest.mark.parametrize("n", [0, 1, 127, 128, 255, 300, 16384, 2**28 - 1, 2**35, 2**56 - 1])
def test_enc_base128_decode_back(n):
    """Self-consistency: base-128 decode reference ile geri okunur."""

    def dec(b):
        v = 0
        for byte in b:
            v = (v << 7) | (byte & 0x7F)
        return v

    assert dec(_enc_base128(n)) == n


# == _enc_oid ==================================================================================

@pytest.mark.parametrize("oid,hexp", [
    (OID_SHA256, "608648016503040201"),
    (OID_SHA384, "608648016503040202"),
    (OID_SHA512, "608648016503040203"),
    (OID_ID_SIGNED_DATA, "2a864886f70d010702"),
    (OID_ID_CT_TST_INFO, "2a864886f70d0109100104"),
    (OID_EDDSA, "2b6570"),
    (OID_ED448, "2b6571"),
    (OID_RSA_ENCRYPTION, "2a864886f70d010101"),
    (OID_ECDSA_SHA256, "2a8648ce3d040302"),
    (OID_DEMO_POLICY, "2b0601040183ff7f0101"),
    ("0.0", "00"),
    ("2.5.4.3", "550403"),
])
def test_enc_oid_known_vectors(oid, hexp):
    """RFC 3161 / PKI OID'leri DER content'ine bayt-bayt eslesir."""
    assert _enc_oid(oid) == bytes.fromhex(hexp)


def test_enc_oid_first_two_arcs_formula():
    """Ilk iki arc -> 40*first + second (RFC base: 0.0..2.39打包)."""
    assert _enc_oid("1.2") == b"\x2a"      # 40*1+2 = 42 = 0x2a
    assert _enc_oid("0.0") == b"\x00"
    assert _enc_oid("2.5") == b"\x55"      # 40*2+5 = 85 = 0x55


def test_enc_oid_two_arcs_only():
    """Minimum gecerli OID 2 arc'tir."""
    assert _enc_oid("1.3") == b"\x2b"


@pytest.mark.parametrize("s", ["1", "2", "0", "5"])
def test_enc_oid_rejects_single_arc(s):
    """len(parts) < 2 -> ValueError (malformed OID)."""
    with pytest.raises(ValueError, match="malformed OID"):
        _enc_oid(s)


def test_enc_oid_returns_bytes():
    assert isinstance(_enc_oid("1.2.3"), bytes)


def test_enc_oid_large_arc_uses_base128():
    """65535 arc'i 3-chunk base-128 (0x83 0xff 0x7f)."""
    assert _enc_oid("1.3.65535") == b"\x2b\x83\xff\x7f"


def test_enc_oid_840_in_cms_oid():
    """840 = 0x86 0x48 (2-chunk base-128) — CMS OID'lerinde gecer."""
    assert _enc_oid("1.2.840").endswith(b"\x86\x48")


# == _dec_oid ==================================================================================

@pytest.mark.parametrize("hexp,oid", [
    ("2a864886f70d010702", OID_ID_SIGNED_DATA),
    ("608648016503040201", OID_SHA256),
    ("2b6570", OID_EDDSA),
    ("2a8648ce3d040302", OID_ECDSA_SHA256),
    ("2b0601040183ff7f0101", OID_DEMO_POLICY),
])
def test_dec_oid_known_vectors(hexp, oid):
    assert _dec_oid(bytes.fromhex(hexp)) == oid


@pytest.mark.parametrize("oid", [
    OID_SHA256, OID_ID_SIGNED_DATA, OID_EDDSA, OID_RSA_ENCRYPTION, OID_ECDSA_SHA256,
    OID_DEMO_POLICY, "1.2.840.113549.1.9.16.1.4", "2.16.840.1.101.3.4.2.3",
    "0.0", "2.5.4.3", "1.3.101.113", "1.2.840.10045.4.3.2",
])
def test_oid_roundtrip(oid):
    """enc→dec her bilinen OID'de kimlik (RFC parite)."""
    assert _dec_oid(_enc_oid(oid)) == oid


def test_dec_oid_single_byte():
    """1 byte body -> 2 arc (40*a+b)."""
    assert _dec_oid(b"\x2a") == "1.2"
    assert _dec_oid(b"\x00") == "0.0"
    assert _dec_oid(b"\x7c") == "3.4"     # ORTAM-QUIRK: 40*3+4=124 -> '3.4' (ilk-arc >2)


def test_dec_oid_empty_raises():
    with pytest.raises(ValueError, match="empty OID"):
        _dec_oid(b"")


def test_dec_oid_dangling_continuation_raises():
    """Son octet'te continuation-bit set -> truncated OID."""
    with pytest.raises(ValueError, match="truncated OID"):
        _dec_oid(bytes([0x2a, 0x80]))


@pytest.mark.parametrize("body", [b"\x2a\x81", b"\x2a\xff", b"\x2a\x80\x80"])
def test_dec_oid_dangling_variants(body):
    with pytest.raises(ValueError, match="truncated OID"):
        _dec_oid(body)


def test_dec_oid_multi_chunk_arc():
    """0x86 0x48 = 840 (2-chunk) — CMS OID'lerindeki arc."""
    assert _dec_oid(b"\x2a\x86\x48\x86\xf7\x0d\x01\x07\x02") == OID_ID_SIGNED_DATA


def test_dec_oid_large_arc_roundtrip():
    """65535 arc'i encode→decode kimlik."""
    assert _dec_oid(_enc_oid("1.3.65535")) == "1.3.65535"


# == _enc_int ==================================================================================

@pytest.mark.parametrize("n,hexp", [
    (0, "00"), (1, "01"), (-1, "ff"), (127, "7f"), (-127, "81"),
    (128, "0080"), (-128, "80"), (129, "0081"), (-129, "ff7f"),
    (255, "00ff"), (-255, "ff01"), (256, "0100"), (-256, "ff00"),
    (32767, "7fff"), (-32768, "8000"), (32768, "008000"), (-32769, "ff7fff"),
])
def test_enc_int_known(n, hexp):
    """DER INTEGER minimal two's-complement (RFC ASN.1 §8.3)."""
    assert _enc_int(n) == bytes.fromhex(hexp)


def test_enc_int_zero_single_byte():
    """0 -> 0x00 (tek byte, minimallik)."""
    assert _enc_int(0) == b"\x00"


def test_enc_int_positive_high_bit_gets_leading_zero():
    """128 = 0x00 0x80 — pozitif sayida isaret-bit'i korumak icin on-sifir."""
    assert _enc_int(128) == b"\x00\x80"
    assert _enc_int(255) == b"\x00\xff"


def test_enc_int_negative_high_bit_gets_leading_ff():
    """-129 = 0xff 0x7f — negatif sayida isaret-bit'i korumak icin on-0xff."""
    assert _enc_int(-129) == b"\xff\x7f"
    assert _enc_int(-256) == b"\xff\x00"


def test_enc_int_no_leading_zero_for_small_positive():
    assert _enc_int(100) == b"\x64"
    assert _enc_int(1) == b"\x01"


def test_enc_int_returns_bytes():
    assert isinstance(_enc_int(5), bytes)


@pytest.mark.parametrize("n", [2**16, 2**24 - 1, 2**31 - 1, -2**31, 2**32, 2**64 - 1, -2**63])
def test_enc_int_roundtrip(n):
    assert _dec_int(_enc_int(n)) == n


# == _dec_int ==================================================================================

@pytest.mark.parametrize("hexp,v", [
    ("00", 0), ("01", 1), ("ff", -1), ("7f", 127), ("80", -128),
    ("0080", 128), ("ff7f", -129), ("0100", 256), ("ff00", -256),
])
def test_dec_int_known(hexp, v):
    assert _dec_int(bytes.fromhex(hexp)) == v


def test_dec_int_empty_raises():
    with pytest.raises(ValueError, match="empty INTEGER"):
        _dec_int(b"")


def test_dec_int_signed_big_endian():
    """ORTAM-ANATOMI: int.from_bytes(signed=True) — MSB isaret-bit."""
    assert _dec_int(b"\x00\x80") == 128
    assert _dec_int(b"\xff\x80") == -128
    assert _dec_int(b"\x01\x00") == 256


def test_dec_int_minimal_two_bytes_negative():
    assert _dec_int(b"\xff\x7f") == -129


def test_dec_int_returns_int():
    assert isinstance(_dec_int(b"\x01"), int)


@pytest.mark.parametrize("n", [0, 1, -1, 127, -128, 128, -129, 255, -256, 32767, -32768, 2**32, -2**31])
def test_int_roundtrip(n):
    """enc→dec tam sayi kimligi (two's-complement minimallik)."""
    assert _dec_int(_enc_int(n)) == n


# == _dec_bitstring ============================================================================

@pytest.mark.parametrize("hexp,expect_len", [
    ("030206c0", 21), ("03020780", 21), ("030000", 13), ("030101ff", 21),
])
def test_dec_bitstring_length(hexp, expect_len):
    """ORTAM-ANATOMI: bit sayisi = 8*(len-1) - unused; MSB-first named bits."""
    assert len(_dec_bitstring(bytes.fromhex(hexp))) == expect_len


def test_dec_bitstring_msb_first():
    """RFC 3161: bit 0 = ILK named bit = content'in MSB'si.
    ORTAM-ANATOMI: girdi 'unused || content' bicimindedir (TLV govdesi)."""
    bits = _dec_bitstring(bytes([0, 0x80, 0x00]))
    assert bits[0] == 1                      # 0x80 MSB set
    assert bits[1:8] == [0] * 7
    assert bits[8] == 0


def test_dec_bitstring_unused_zero_no_truncation():
    """unused=0 -> bits ASLA kesilmez (tum octet'lerin tum bitleri).
    0x06 0xC0 = 00000110 11000000 (16 bit, unused=0)."""
    b = _dec_bitstring(bytes([0, 0x06, 0xC0]))
    assert len(b) == 16
    assert b == [0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0]


@pytest.mark.parametrize("unused", [1, 2, 3, 4, 5, 6, 7])
def test_dec_bitstring_unused_truncates(unused):
    """unused > 0 -> SON unused-bitler kesilir (named-bit semantics)."""
    b = _dec_bitstring(bytes([unused, 0xFF]))
    assert len(b) == 8 - unused
    assert all(x == 1 for x in b)


def test_dec_bitstring_unused_7_single_bit():
    assert _dec_bitstring(bytes([7, 0xFF])) == [1]


def test_dec_bitstring_empty_raises():
    with pytest.raises(ValueError, match="empty BIT STRING"):
        _dec_bitstring(b"")


def test_dec_bitstring_unused_8_raises():
    """unused > 7 gecersiz (bir octet'te 8 bit var)."""
    with pytest.raises(ValueError, match="invalid unused-bit count"):
        _dec_bitstring(b"\x08")


@pytest.mark.parametrize("unused", [9, 100, 255])
def test_dec_bitstring_unused_large_raises(unused):
    with pytest.raises(ValueError, match="invalid unused-bit count"):
        _dec_bitstring(bytes([unused]))


def test_dec_bitstring_no_content_bytes():
    """Sadece unused-octet (content yok) -> bos bit listesi (unused>0 ise)."""
    assert _dec_bitstring(bytes([0])) == []


def test_dec_bitstring_all_zero_bits():
    assert _dec_bitstring(bytes([0, 0x00, 0x00])) == [0] * 16


def test_dec_bitstring_returns_list():
    assert isinstance(_dec_bitstring(bytes.fromhex("030206c0")), list)


def test_dec_bitstring_multi_byte_pattern():
    """0x01 0x02 0x03 0x04 unused=0 — MSB-first bit sirasi."""
    b = _dec_bitstring(bytes([0, 0x01, 0x02, 0x03, 0x04]))
    assert b[:8] == [0, 0, 0, 0, 0, 0, 0, 1]
    assert b[8:16] == [0, 0, 0, 0, 0, 0, 1, 0]


# == birlesik parite (gercek RSA-paritesi deseni) ===============================================

def test_enc_oid_matches_tsa_module_constants():
    """Moduldeki OID sabitleri ile encode bayt-bayt tutarlidir."""
    assert _enc_oid(OID_SHA256) == bytes.fromhex("608648016503040201")
    assert _enc_oid(OID_ID_SIGNED_DATA) == bytes.fromhex("2a864886f70d010702")


@pytest.mark.parametrize("oid", [OID_SHA256, OID_SHA384, OID_SHA512, OID_EDDSA, OID_ED448])
def test_oid_algorithm_roundtrip(oid):
    assert _dec_oid(_enc_oid(oid)) == oid


def test_int_two_octet_boundary_pair():
    """127/128 ve -127/-128 sinir-ciftleri minimallik acisindan kritik."""
    assert _enc_int(127) == b"\x7f"
    assert _enc_int(128) == b"\x00\x80"
    assert _enc_int(-127) == b"\x81"
    assert _enc_int(-128) == b"\x80"


def test_bitstring_failinfo_style():
    """RFC 3161 failInfo bit-0 = badAlg — 0x06 0xC0 deseni."""
    b = _dec_bitstring(bytes.fromhex("030206c0"))
    assert b[6] == 1   # bit 0 (badAlg) set

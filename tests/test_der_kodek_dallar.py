"""tools/brandstrike_tsa DER kodek dal-kesen testleri (LEED).

Kural-1: MEVCUT DOSYALARA DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory (bytes/parametre matrisi; dis ag / dosya YOK).

Kapsanan _-prefixed fonksiyonlar (AST backlog):
  _enc_len   — DER uzunluk-kodlamasi (kisa-form < 0x80 / uzun-form 0x80|n)
  _tlv       — Tag-Length-Value insasi
  _read_tlv  — tek TLV cozme + fail-loud truncation/non-minimal DALlari
  _iter_tlv  — constructed icindeki ardisik TLV'leri yield
"""
import sys

import pytest

sys.path.insert(0, ".")
sys.path.insert(0, "tools")
from brandstrike_tsa import _enc_len, _tlv, _read_tlv, _iter_tlv  # noqa: E402


# == _enc_len ==================================================================================

@pytest.mark.parametrize("n,hexp", [
    (0, "00"), (1, "01"), (0x7E, "7e"), (0x7F, "7f"),     # kisa-form sinir (128 hariç)
])
def test_enc_len_short_form(n, hexp):
    """n < 0x80 -> tek octet (DER kesin-form)."""
    assert _enc_len(n) == bytes.fromhex(hexp)


@pytest.mark.parametrize("n,hexp", [
    (0x80, "8180"), (0xFF, "81ff"),                        # 1-octet uzun-form
    (0x100, "820100"), (0xFFFF, "82ffff"),                # 2-octet uzun-form
    (0x10000, "83010000"), (0xFFFFFF, "83ffffff"),        # 3-octet uzun-form
])
def test_enc_len_long_form(n, hexp):
    """n >= 0x80 -> 0x80|kac-octet + buyuk-endian uzunluk."""
    assert _enc_len(n) == bytes.fromhex(hexp)


def test_enc_len_short_form_boundary_inclusive():
    """0x7F (127) hala kisa-formdadir — 128'e kadar DEGIL, 0x80 = 128 esiktir."""
    assert len(_enc_len(127)) == 1
    assert len(_enc_len(128)) == 2


def test_enc_len_minimal_octet_count():
    """Uzun-form minimum octet sayisi kullanir (DER minimallik)."""
    assert _enc_len(256) == bytes.fromhex("820100")
    assert _enc_len(255) == bytes.fromhex("81ff")   # 255 1-octet'e sigar


def test_enc_len_max_8_octets():
    """2**64-1 -> 0x88 + 8 octet (maksimum DAR uzunluk alani)."""
    assert _enc_len(2**64 - 1) == bytes.fromhex("88ffffffffffffffff")


def test_enc_len_returns_bytes():
    assert isinstance(_enc_len(5), bytes)
    assert isinstance(_enc_len(500), bytes)


def test_enc_len_zero():
    assert _enc_len(0) == b"\x00"


# == _tlv ======================================================================================

@pytest.mark.parametrize("tag,content,hexp", [
    (0x04, b"", "0400"),
    (0x04, b"abc", "0403616263"),
    (0x02, b"\x01", "020101"),
    (0x30, b"\x02\x01\x01", "3003020101"),
    (0x06, b"\x2a\x03", "06022a03"),
    (0x01, b"\xff", "0101ff"),
])
def test_tlv_assembly(tag, content, hexp):
    """_tlv = tag || _enc_len(len(content)) || content."""
    assert _tlv(tag, content) == bytes.fromhex(hexp)


def test_tlv_uses_enc_len():
    """Uzun icerikte uzun-form uzunluk otomatik gelir."""
    big = _tlv(0x04, b"a" * 200)
    assert big[:3] == bytes.fromhex("0481c8")


def test_tlv_empty_content():
    assert _tlv(0x05, b"") == bytes.fromhex("0500")


def test_tlv_returns_bytes():
    assert isinstance(_tlv(0x04, b"x"), bytes)


def test_tlv_high_tag_numbers():
    assert _tlv(0xA0, b"z") == bytes.fromhex("a0017a")
    assert _tlv(0xFF, b"z") == bytes.fromhex("ff017a")


# == _read_tlv (basari dallari) ================================================================

def test_read_tlv_basic():
    """(tag, content, next_off) uc-lusu doner."""
    assert _read_tlv(bytes.fromhex("0403616263")) == (0x04, b"abc", 5)


def test_read_tlv_returns_next_offset():
    """next_off = tag(1) + len-octet(sayisi) + content — sonraki TLV'nin baslangici."""
    assert _read_tlv(bytes.fromhex("020101"))[2] == 3
    # 0x82 -> 2 uzunluk-octeti (0x0100 = 256) + 256-byte content → off = 4 + 256
    derb = b"\x04\x82\x01\x00" + b"\x61" * 256
    assert _read_tlv(derb)[2] == 4 + 256
    # 0x81 -> 1 uzunluk-octeti (0x80 = 128) + 128-byte content → off = 3 + 128
    derb2 = b"\x04\x81\x80" + b"\x61" * 128
    assert _read_tlv(derb2)[2] == 3 + 128


@pytest.mark.parametrize("der,expect", [
    ("0400", (0x04, b"", 2)),
    ("0500", (0x05, b"", 2)),
    ("020105", (0x02, b"\x05", 3)),
])
def test_read_tlv_short_content(der, expect):
    assert _read_tlv(bytes.fromhex(der)) == expect


@pytest.mark.parametrize("hdr,content", [
    (b"\x04\x81\x80", 128),        # 1 uzunluk-octeti (0x80 = 128)
    (b"\x04\x82\x01\x00", 256),    # 2 uzunluk-octeti (0x0100 = 256)
    (b"\x04\x83\x01\x00\x00", 65536),  # 3 uzunluk-octeti (0x010000 = 65536)
])
def test_read_tlv_long_form_valid(hdr, content):
    """Gecerli minimal uzun-form: content tam uzunluk kadar, next_off dogru."""
    body = b"\x61" * content
    tag, val, off = _read_tlv(hdr + body)
    assert (tag, val) == (0x04, body)
    assert off == len(hdr) + content


def test_read_tlv_long_form_length_oversized():
    """ORTAM-ANATOMI: 0x83 → 3 uzunluk-octeti = 0x010203 = 66051 ister;
    gercekte 0 byte content var → 'content cut' (fail-loud, sessiz-truncate YOK)."""
    with pytest.raises(ValueError, match="content cut"):
        _read_tlv(bytes.fromhex("0483010203"))


def test_read_tlv_explicit_offset():
    """off parametri verilen konumdan okur (constructed icinde gezme)."""
    assert _read_tlv(bytes.fromhex("0000020101"), 2) == (0x02, b"\x01", 5)


def test_read_tlv_offset_at_end():
    """off == len(der) -> truncation hatasi (karakteristik: tag-okuma adimi)."""
    with pytest.raises(ValueError, match="missing tag"):
        _read_tlv(b"\x04\x03abc", 5)


def test_read_tlv_content_exactly_to_end():
    """Content tam dosya sonuna bitiyorsa next_off == len(der)."""
    d = bytes.fromhex("0403616263")
    assert _read_tlv(d, 0)[2] == len(d)


# == _read_tlv (hata dallari — fail-loud DER) ==================================================

@pytest.mark.parametrize("der,match", [
    ("", "missing tag"),
    ("04", "missing length"),
    ("0480", "indefinite length is not DER"),
    ("0489" + "00" * 9, "length field too large"),
    ("04830102", "length octets cut"),
    ("0405" + "616263", "content cut"),
    ("04810161", "non-minimal length encoding"),
])
def test_read_tlv_rejects_malformed(der, match):
    """Her bozuk-DER sekli ValueError ile reddedilir (forged-length yeniden-yorumu YOK)."""
    with pytest.raises(ValueError, match=match):
        _read_tlv(bytes.fromhex(der))


def test_read_tlv_indefinite_length_rejected():
    """0x80 uzunluk-octeti DER'de yasak (BER indefinite)."""
    with pytest.raises(ValueError):
        _read_tlv(b"\x04\x80\x61\x62")


def test_read_tlv_length_octets_cut():
    """0x83 der ama sadece 2 octet var -> 'length octets cut'."""
    with pytest.raises(ValueError, match="length octets cut"):
        _read_tlv(b"\x04\x83\x01\x02")


def test_read_tlv_non_minimal_long_form():
    """Content 1 byte iken 2-octet uzunluk (0x81 0x01) non-minimal -> RED."""
    with pytest.raises(ValueError, match="non-minimal"):
        _read_tlv(b"\x04\x81\x01\x61")


def test_read_tlv_non_minimal_short_threshold():
    """0x81 0x7F = 127 byte; 0x7F kisa-formun esigi — uzun-form non-minimal."""
    with pytest.raises(ValueError, match="non-minimal"):
        _read_tlv(b"\x04\x81\x7f" + b"\x61" * 127)


def test_read_tlv_content_truncation():
    """Length 0x05 ama 3 byte content -> 'content cut'."""
    with pytest.raises(ValueError, match="content cut"):
        _read_tlv(b"\x04\x05\x61\x62\x63")


def test_read_tlv_missing_length_octet():
    """Tag var, uzunluk-octeti yok (1-byte girdi)."""
    with pytest.raises(ValueError, match="missing length"):
        _read_tlv(b"\x04")


def test_read_tlv_error_is_valueerror_not_silent():
    """Fail-loud: hata ValueError turunde (sessiz tolere YOK)."""
    with pytest.raises(ValueError):
        _read_tlv(b"")


# == _iter_tlv =================================================================================

def test_iter_tlv_yields_pairs():
    assert list(_iter_tlv(bytes.fromhex("020101020102"))) == [(0x02, b"\x01"), (0x02, b"\x02")]


def test_iter_tlv_empty():
    assert list(_iter_tlv(b"")) == []


def test_iter_tlv_single():
    assert list(_iter_tlv(bytes.fromhex("0403616263"))) == [(0x04, b"abc")]


def test_iter_tlv_mixed_tags():
    d = bytes.fromhex("020101") + bytes.fromhex("06022a03") + bytes.fromhex("0500")
    assert list(_iter_tlv(d)) == [(0x02, b"\x01"), (0x06, b"\x2a\x03"), (0x05, b"")]


def test_iter_tlv_is_lazy_generator():
    """_iter_tlv generator doner (memory-bounded streaming)."""
    g = _iter_tlv(bytes.fromhex("020101"))
    assert not isinstance(g, list)
    assert hasattr(g, "__next__")


def test_iter_tlv_stops_at_content_end():
    """Cursor content'in sonunda durur — asiri okuma YOK."""
    d = bytes.fromhex("020101020102")
    assert len(list(_iter_tlv(d))) == 2


def test_iter_tlv_nested_structure():
    """SEQUENCE(two INTEGER) constructed yapiyi satir-satir gezer."""
    inner = bytes.fromhex("020101") + bytes.fromhex("020102")
    seq = _tlv(0x30, inner)
    assert list(_iter_tlv(inner)) == [(0x02, b"\x01"), (0x02, b"\x02")]
    assert seq == bytes.fromhex("3006020101020102")


def test_iter_tlv_many():
    d = b"".join(bytes.fromhex("0201%02x" % i) for i in range(20))
    out = list(_iter_tlv(d))
    assert len(out) == 20
    assert [v for _, v in out] == [bytes([i]) for i in range(20)]


def test_iter_tlv_propagates_malformed():
    """Truncated TLV iceride ValueError yayar (sessiz-atla YOK)."""
    with pytest.raises(ValueError):
        list(_iter_tlv(bytes.fromhex("0201010405")))


# == round-trip paritesi =======================================================================

@pytest.mark.parametrize("tag,content", [
    (0x02, b"\x01"), (0x04, b"hello world"), (0x05, b""),
    (0x06, b"\x2a\x86\x48\x86\xf7\x0d\x01\x07\x02"),
    (0x30, b"\x02\x01\x01\x02\x01\x02"), (0x01, b"\xff"),
])
def test_tlv_read_roundtrip(tag, content):
    """_tlv ile insa edilen hersey _read_tlv ile geri cozunur."""
    t, v, off = _read_tlv(_tlv(tag, content))
    assert (t, v) == (tag, content)
    assert off == len(_tlv(tag, content))


@pytest.mark.parametrize("n", [0, 1, 127, 128, 255, 256, 65535, 65536, 2**24 - 1, 2**32 - 1])
def test_enc_len_decodes_back(n):
    """Uzunluk-kodlamasinin decode edilebilen karsiligi (self-consistency)."""
    enc = _enc_len(n)
    assert enc[0] < 0x80 or (enc[0] & 0x7F) == len(enc) - 1
    # kisa-form: deger dogrudan; uzun-form: 0x80|n octet sayisi
    if enc[0] < 0x80:
        assert enc[0] == n
    else:
        assert int.from_bytes(enc[1:], "big") == n


def test_tlv_of_tlv_composition():
    """Ic ice DER insasi (AlgorithmIdentifier deseni)."""
    alg = _tlv(0x30, _tlv(0x06, b"\x2a\x03"))
    top = _tlv(0x30, alg + _tlv(0x04, b"\xab\xcd"))
    tag, content, _ = _read_tlv(top)
    assert tag == 0x30
    sub = list(_iter_tlv(content))
    assert sub[0][0] == 0x30
    assert sub[1] == (0x04, b"\xab\xcd")

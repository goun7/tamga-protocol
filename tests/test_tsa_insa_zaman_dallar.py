"""tools/brandstrike_tsa RFC-3161 insa + zaman-ekseni dal-kesen testleri (LEED).

Kural-1: MEVCUT DOSYALARA DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory (bytes/datetime girdi; dis ag / TSA-sunucu YOK).

Kapsanan _-prefixed fonksiyonlar (AST backlog):
  _message_imprint             RFC 3161 messageImprint (AlgorithmIdentifier + digest)
  _tst_info                    TSTInfo insasi (version/policy/imprint/serial/genTime/nonce)
  _parse_algorithm_identifier  AlgorithmIdentifier OID cikarimi (NULL-params tolerans)
  dec_gen_time / gen_time_iso  GeneralizedTime <-> ISO-8601 (zaman-ekseni paritesi)
"""
import datetime
import hashlib
import sys

import pytest

sys.path.insert(0, ".")
sys.path.insert(0, "tools")
from brandstrike_tsa import (  # noqa: E402
    _message_imprint, _tst_info, _parse_algorithm_identifier,
    dec_gen_time, gen_time_iso, _read_tlv, _iter_tlv, _dec_int, _dec_oid, _dec_bitstring,
    OID_SHA256, OID_SHA384, OID_SHA512, OID_DEMO_POLICY,
)

D32 = hashlib.sha256(b"x").digest()
D48 = hashlib.sha384(b"x").digest()
D64 = hashlib.sha512(b"x").digest()
GT = "20261005120530Z"


# == _message_imprint ===========================================================================

def test_message_imprint_structure():
    """SEQUENCE { SEQUENCE { OID }, OCTET STRING(digest) }."""
    der = _message_imprint(D32)
    tag, content, _ = _read_tlv(der)
    assert tag == 0x30
    parts = list(_iter_tlv(content))
    assert [p[0] for p in parts] == [0x30, 0x04]
    assert parts[1][1] == D32


def test_message_imprint_oid_is_sha256():
    """AlgorithmIdentifier icinde SHA-256 OID."""
    der = _message_imprint(D32)
    _, content, _ = _read_tlv(der)
    alg = list(_iter_tlv(content))[0][1]
    assert _parse_algorithm_identifier(alg) == OID_SHA256


def test_message_imprint_known_hex():
    """Bayt-bayt sabit vektor (regression-sabiti)."""
    assert _message_imprint(D32).hex() == (
        "302f300b06096086480165030402010420"
        + D32.hex()
    )


@pytest.mark.parametrize("oid,digest,expect_len", [
    (OID_SHA256, D32, 49),
    (OID_SHA384, D48, 65),
    (OID_SHA512, D64, 81),
])
def test_message_imprint_per_alg(oid, digest, expect_len):
    """Her desteklenen alg icin length-gate dogru calisir; toplam uzunluk
    digest-boyutuyla_buyur (49/65/81 — ORTAM-ANATOMI: 17-octet sabit + digest)."""
    der = _message_imprint(digest, oid)
    assert len(der) == expect_len
    _, content, _ = _read_tlv(der)
    parts = list(_iter_tlv(content))
    assert _parse_algorithm_identifier(parts[0][1]) == oid
    assert parts[1][1] == digest


@pytest.mark.parametrize("oid,plen", [(OID_SHA256, 32), (OID_SHA384, 48), (OID_SHA512, 64)])
def test_message_imprint_length_grows_with_digest(oid, plen):
    """Imprint uzunlugu = 17 sabit-octet + digest-boyu."""
    import os
    d = os.urandom(plen)
    assert len(_message_imprint(d, oid)) == 17 + plen


def test_message_imprint_returns_bytes():
    assert isinstance(_message_imprint(D32), bytes)


def test_message_imprint_no_null_params():
    """AlgorithmIdentifier'da NULL parametre YOK (modern hash'ler)."""
    der = _message_imprint(D32)
    _, content, _ = _read_tlv(der)
    alg = list(_iter_tlv(content))[0][1]
    assert len(list(_iter_tlv(alg))) == 1     # sadece OID


def test_message_imprint_empty_digest_rejected():
    """0-byte digest -> length gate RED."""
    with pytest.raises(ValueError, match="digest length 0"):
        _message_imprint(b"", OID_SHA256)


@pytest.mark.parametrize("ln", [0, 1, 31, 33, 63, 65, 100])
def test_message_imprint_wrong_digest_length(ln, ):
    """Digest uzunlugu alg'in bekledigine esit OLMALI (fail-loud)."""
    with pytest.raises(ValueError, match="digest length"):
        _message_imprint(b"\x00" * ln, OID_SHA256)


def test_message_imprint_unsupported_oid():
    """Bilinmeyen hash OID -> RED (domain-yesi)."""
    with pytest.raises(ValueError, match="unsupported hash algorithm"):
        _message_imprint(D32, "1.2.3.4.5")


@pytest.mark.parametrize("oid", ["1.2.3", "0.0", OID_DEMO_POLICY])
def test_message_imprint_non_hash_oid(oid):
    """Hash-olmayan OID reddedilir (TSA yalniz SHA-2 ailesini destekler)."""
    with pytest.raises(ValueError, match="unsupported"):
        _message_imprint(D32, oid)


def test_message_imprint_digest_sensitivity():
    """1-bit farkli digest tamamen farkli imprint (avalanche)."""
    a = _message_imprint(D32)
    b = _message_imprint(bytes([D32[0] ^ 1]) + D32[1:])
    assert a != b


def test_message_imprint_random_digest_roundtrip_structure():
    """Rastgele digest de ayni yapiyi korur."""
    import os
    d = os.urandom(32)
    _, content, _ = _read_tlv(_message_imprint(d))
    parts = list(_iter_tlv(content))
    assert parts[1][1] == d


# == _parse_algorithm_identifier ================================================================

def test_parse_alg_identifier_sha256():
    assert _parse_algorithm_identifier(
        bytes.fromhex("0609608648016503040201")) == OID_SHA256


def test_parse_alg_identifier_returns_oid_str():
    r = _parse_algorithm_identifier(bytes.fromhex("0609608648016503040201"))
    assert isinstance(r, str)
    assert r.startswith("2.")


@pytest.mark.parametrize("hexp,oid", [
    ("0609608648016503040201", OID_SHA256),
    ("0609608648016503040202", OID_SHA384),
    ("0609608648016503040203", OID_SHA512),
    ("06032b6570", "1.3.101.112"),
    ("06092a864886f70d010702", "1.2.840.113549.1.7.2"),
])
def test_parse_alg_identifier_known(hexp, oid):
    assert _parse_algorithm_identifier(bytes.fromhex(hexp)) == oid


def test_parse_alg_identifier_tolerates_null_params():
    """NULL params (0x05 0x00) tolere edilir (eski TSA'lar gonderir)."""
    der = bytes.fromhex("0609608648016503040201") + bytes.fromhex("0500")
    assert _parse_algorithm_identifier(der) == OID_SHA256


def test_parse_alg_identifier_rejects_missing_oid():
    with pytest.raises(ValueError, match="missing algorithm OID"):
        _parse_algorithm_identifier(b"")


def test_parse_alg_identifier_rejects_non_oid_first():
    with pytest.raises(ValueError, match="missing algorithm OID"):
        _parse_algorithm_identifier(bytes.fromhex("020101"))


@pytest.mark.parametrize("hexp", ["020101", "0403aabbcc", "3003020101"])
def test_parse_alg_identifier_rejects_bad_first_tag(hexp):
    """Ilk eleman OID (0x06) OLMALI."""
    with pytest.raises(ValueError, match="missing algorithm OID"):
        _parse_algorithm_identifier(bytes.fromhex(hexp))


def test_parse_alg_identifier_rejects_non_null_params():
    """NULL-olmayan params RED (tolerans yalniz 0x05 0x00)."""
    der = bytes.fromhex("0609608648016503040201") + bytes.fromhex("020101")
    with pytest.raises(ValueError, match="unexpected params"):
        _parse_algorithm_identifier(der)


def test_parse_alg_identifier_rejects_null_with_content():
    """NULL (0x05) sifir-uzunluklu OLMALI."""
    der = bytes.fromhex("0609608648016503040201") + bytes.fromhex("0501ff")
    with pytest.raises(ValueError, match="unexpected params"):
        _parse_algorithm_identifier(der)


def test_parse_alg_identifier_multi_oid_rejected():
    """ iki OID RED (ilk tanimlanir, ikincisi unexpected params)."""
    der = bytes.fromhex("0609608648016503040201") + bytes.fromhex("0609608648016503040202")
    with pytest.raises(ValueError, match="unexpected params"):
        _parse_algorithm_identifier(der)


# == _tst_info ==================================================================================

def _fields(der):
    """TSTInfo alanlarini (tag, value) listesi olarak doner — tekrarlanan tag'lar
    oldugu icin dict DEGIL liste (0x02 x3: version/serial/nonce; 0x30 x2: imprint/accuracy)."""
    tag, content, _ = _read_tlv(der)
    assert tag == 0x30
    return list(_iter_tlv(content))


def _ints(der):
    return [_dec_int(v) for t, v in _fields(der) if t == 0x02]


def test_tst_info_outer_sequence():
    tag, _, _ = _read_tlv(_tst_info(_message_imprint(D32), 1, GT, 7))
    assert tag == 0x30


def test_tst_info_field_tags_in_order():
    """Alan sirasi: version(02) policy(06) imprint(30) serial(02) genTime(18) accuracy(30) ordering(01) nonce(02)."""
    der = _tst_info(_message_imprint(D32), 1, GT, 7)
    tags = [t for t, _ in _fields(der)]
    assert tags == [0x02, 0x06, 0x30, 0x02, 0x18, 0x30, 0x01, 0x02]


def test_tst_info_version_is_one():
    assert _ints(_tst_info(_message_imprint(D32), 5, GT, 9))[0] == 1


def test_tst_info_policy_default():
    pol = [v for t, v in _fields(_tst_info(_message_imprint(D32), 5, GT, 9)) if t == 0x06][0]
    assert _dec_oid(pol) == OID_DEMO_POLICY


def test_tst_info_custom_policy():
    der = _tst_info(_message_imprint(D32), 5, GT, 9, policy="1.3.6.1.4.1.65535.9.9")
    pol = [v for t, v in _fields(der) if t == 0x06][0]
    assert _dec_oid(pol) == "1.3.6.1.4.1.65535.9.9"


def test_tst_info_imprint_embedded():
    """messageImprint TSTInfo'nun icinde gomulur (binding).
    ORTAM-ANATOMI: _tst_info imprint TLV'sinin KENDISINI ekler; _iter_tlv dis-0x30
    tag'ini soyar ve icindeki (AlgorithmIdentifier + OCTET STRING) content'ini
    field-degeri yapar. Bu yuzden karsilastirma ic-icerik uzerinden yapilir."""
    imp = _message_imprint(D32)
    _, imp_content, _ = _read_tlv(imp)
    seqs = [v for t, v in _fields(_tst_info(imp, 5, GT, 9)) if t == 0x30]
    assert imp_content in seqs


@pytest.mark.parametrize("serial", [1, 2, 42, 65535, 2**31 - 1])
def test_tst_info_serial(serial):
    """ORTAM-ANATOMI: INTEGER sirasi [version, serial, nonce]."""
    assert _ints(_tst_info(_message_imprint(D32), serial, GT, 9))[1] == serial


@pytest.mark.parametrize("nonce", [1, 7, 12345, 2**32, 2**63 - 1])
def test_tst_info_nonce(nonce):
    assert _ints(_tst_info(_message_imprint(D32), 1, GT, nonce)) == [1, 1, nonce]


def test_tst_info_gen_time_ascii():
    gt = [v for t, v in _fields(_tst_info(_message_imprint(D32), 1, GT, 9)) if t == 0x18][0]
    assert gt == GT.encode("ascii")


def test_tst_info_genTime_tag_is_generalizedtime():
    """0x18 = GeneralizedTime (UTCTime 0x17 DEGIL)."""
    assert any(t == 0x18 for t, _ in _fields(_tst_info(_message_imprint(D32), 1, GT, 9)))


def test_tst_info_ordering_false():
    bl = [v for t, v in _fields(_tst_info(_message_imprint(D32), 1, GT, 9)) if t == 0x01][0]
    assert bl == b"\x00"


@pytest.mark.parametrize("seconds", [1, 2, 60])
def test_tst_info_accuracy_seconds(seconds):
    """accuracy SEQUENCE{INTEGER} saniye cinsinden (0x30 tag'imprint ile ayni)."""
    der = _tst_info(_message_imprint(D32), 1, GT, 9, seconds=seconds)
    seqs = [v for t, v in _fields(der) if t == 0x30]
    # son 0x30 accuracy'dir (ilki imprint)
    inner = list(_iter_tlv(seqs[-1]))
    assert _dec_int(inner[0][1]) == seconds


def test_tst_info_returns_bytes():
    assert isinstance(_tst_info(_message_imprint(D32), 1, GT, 9), bytes)


def test_tst_info_binds_imprint_bytes():
    """Imprint degisirse TSTInfo baytlari degisir (time-axis binding)."""
    a = _tst_info(_message_imprint(D32), 1, GT, 9)
    b = _tst_info(_message_imprint(D48, OID_SHA384), 1, GT, 9)
    assert a != b


def test_tst_info_serial_changes_output():
    a = _tst_info(_message_imprint(D32), 1, GT, 9)
    b = _tst_info(_message_imprint(D32), 2, GT, 9)
    assert a != b


def test_tst_info_nonce_changes_output():
    a = _tst_info(_message_imprint(D32), 1, GT, 9)
    b = _tst_info(_message_imprint(D32), 1, GT, 10)
    assert a != b


# == dec_gen_time ===============================================================================

@pytest.mark.parametrize("s,expect", [
    ("20261005120530Z", datetime.datetime(2026, 10, 5, 12, 5, 30, tzinfo=datetime.timezone.utc)),
    ("20260101000000Z", datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc)),
    ("19700101000000Z", datetime.datetime(1970, 1, 1, tzinfo=datetime.timezone.utc)),
])
def test_dec_gen_time_canonical(s, expect):
    """DER canonical GeneralizedTime (YYYYMMDDHHMMSSZ) → aware UTC datetime."""
    d = dec_gen_time(s)
    assert d == expect
    assert d.tzinfo == datetime.timezone.utc


@pytest.mark.parametrize("s,frac", [
    ("20261005120530.123Z", 123000),
    ("20261005120530.5Z", 500000),
    ("20261005120530.000001Z", 1),
])
def test_dec_gen_time_fractional_seconds(s, frac):
    """Kesirli-saniye GERCEK TSA'larin gonderdigi gevsek form."""
    d = dec_gen_time(s)
    assert d.microsecond == frac


@pytest.mark.parametrize("s,off", [
    ("20261005120530+0300", datetime.timezone(datetime.timedelta(hours=3))),
    ("20261005120530-0500", datetime.timezone(datetime.timedelta(hours=-5))),
    ("20261005120530+0530", datetime.timezone(datetime.timedelta(hours=5, minutes=30))),
])
def test_dec_gen_time_offsets(s, off):
    """Acik offset kabul edilir (offset-ile-beraber aware)."""
    d = dec_gen_time(s)
    assert d.tzinfo == off
    assert d.utcoffset() == off.utcoffset(None)


def test_dec_gen_time_no_tz_defaults_utc():
    """ORTAM-KARAKTERIZASYON: tz YOKSA UTC varsayilir (Z-tagi olmadan da)."""
    d = dec_gen_time("20261005120530")
    assert d.tzinfo == datetime.timezone.utc


def test_dec_gen_time_accepts_bytes():
    """bytes girdi ASCII-decode edilir."""
    assert dec_gen_time(b"20261005120530Z") == dec_gen_time("20261005120530Z")


def test_dec_gen_time_accepts_bytearray():
    assert dec_gen_time(bytearray(b"20261005120530Z")) == dec_gen_time("20261005120530Z")


def test_dec_gen_time_strips_whitespace():
    """ortada/basta whitespace tolere edilir (.strip())."""
    assert dec_gen_time("  20261005120530Z  ") == dec_gen_time("20261005120530Z")


@pytest.mark.parametrize("s,expect", [
    ("20261005120530,5Z", 500000),
])
def test_dec_gen_time_comma_decimal(s, expect):
    """Virgul-ayracli kesir (RFC 3161 §2.4.1 relaxed form)."""
    assert dec_gen_time(s).microsecond == expect


@pytest.mark.parametrize("s", [
    "", "not-a-date", "abcd", "2026", "20261005",
    "2026-10-05T12:05:30Z",          # ISO format DEGIL
    "20261005120530+",               # yarim offset
    "20261005 120530Z",              # bosluk
])
def test_dec_gen_time_rejects_malformed(s):
    """Her gevsek-format-disi giris ValueError (sessiz-tolerans YOK)."""
    with pytest.raises(ValueError, match="malformed GeneralizedTime"):
        dec_gen_time(s)


@pytest.mark.parametrize("s,msg", [
    ("20261340120530Z", "month"),
    ("20261005259999Z", "hour"),
    ("20261005129999Z", "minute"),
    ("20260230120530Z", "day"),
])
def test_dec_gen_time_rejects_impossible_dates(s, msg):
    """Imkansiz tarihler wrap-around YAPMAZ — ValueError (DER disiplini)."""
    with pytest.raises(ValueError, match=msg):
        dec_gen_time(s)


def test_dec_gen_time_returns_aware_datetime():
    d = dec_gen_time(GT)
    assert isinstance(d, datetime.datetime)
    assert d.tzinfo is not None


def test_dec_gen_time_leap_year():
    """2028 artik-yil: 29 Subat gecerli."""
    assert dec_gen_time("20280229120530Z").day == 29


def test_dec_gen_time_non_leap_rejects_feb29():
    with pytest.raises(ValueError, match="day"):
        dec_gen_time("20260229120530Z")


# == gen_time_iso ===============================================================================

@pytest.mark.parametrize("s,expect", [
    ("20261005120530Z", "2026-10-05T12:05:30Z"),
    ("20260101000000Z", "2026-01-01T00:00:00Z"),
    ("20261231235959Z", "2026-12-31T23:59:59Z"),
])
def test_gen_time_iso_canonical(s, expect):
    """GeneralizedTime → ISO-8601 Z (receipt-alan)."""
    assert gen_time_iso(dec_gen_time(s)) == expect


def test_gen_time_iso_normalizes_offset():
    """+03:00 offset UTC'ye normalize edilir (20261005120530+0300 → 09:05:30Z)."""
    assert gen_time_iso(dec_gen_time("20261005120530+0300")) == "2026-10-05T09:05:30Z"


def test_gen_time_iso_negative_offset():
    assert gen_time_iso(dec_gen_time("20261005120530-0500")) == "2026-10-05T17:05:30Z"


def test_gen_time_iso_fractional_truncated():
    """Kesirli-saniye ISO'da GOSTERILMEZ (%S format)."""
    assert gen_time_iso(dec_gen_time("20261005120530.999Z")) == "2026-10-05T12:05:30Z"


def test_gen_time_iso_returns_str():
    assert isinstance(gen_time_iso(dec_gen_time(GT)), str)


def test_gen_time_iso_accepts_aware_directly():
    """datetime girdisi dogrudan kabul (parse gerektirmez)."""
    d = datetime.datetime(2026, 10, 5, 12, 5, 30, tzinfo=datetime.timezone.utc)
    assert gen_time_iso(d) == "2026-10-05T12:05:30Z"


def test_gen_time_iso_z_suffix():
    r = gen_time_iso(dec_gen_time(GT))
    assert r.endswith("Z")
    assert "T" in r


# == zaman-ekseni round-trip ====================================================================

@pytest.mark.parametrize("s", [
    "20261005120530Z", "20260101000000Z", "20261231235959Z", "19700101000000Z",
])
def test_gen_time_dec_roundtrip(s):
    """dec → iso: UTC degeri GeneralizedTime UTC'ye doner (Z-form korumasi)."""
    assert gen_time_iso(dec_gen_time(s)) == (
        f"{s[:4]}-{s[4:6]}-{s[6:8]}T{s[8:10]}:{s[10:12]}:{s[12:14]}Z")


@pytest.mark.parametrize("s", ["20261005120530+0300", "20261005120530-0500", "20261005120530+0530"])
def test_offset_to_utc_roundtrip(s):
    """Offset'li giris UTC-normalize edilir ve Z ile biter."""
    r = gen_time_iso(dec_gen_time(s))
    assert r.endswith("Z")


# == birlesik: imprint → tst_info → parse paritesi ==============================================

def test_tst_info_imprint_is_parseable():
    """TSTInfo'nun icindeki imprint parse_message_imprint ile geri okunur.
    ORTAM-ANATOMI: parse_message_imprint SEQUENCE *content*'ini alir — _fields
    zaten dis-0x30 tag'ini soydugu icin dogrudan verilir."""
    from brandstrike_tsa import parse_message_imprint
    imp = _message_imprint(D32)
    der = _tst_info(imp, 7, GT, 11)
    fields = _fields(der)
    imprint_field = next(v for t, v in fields if t == 0x30)
    assert parse_message_imprint(imprint_field) == {
        "hash_alg": "sha256", "hash_oid": OID_SHA256, "imprint": D32.hex()}


def test_imprint_algorithm_roundtrip_all_algs():
    """Her alg icin insa-ettigimiz imprint'in algoritmasi geri okunur."""
    from brandstrike_tsa import parse_message_imprint
    for oid, d, alg in ((OID_SHA256, D32, "sha256"),
                        (OID_SHA384, D48, "sha384"),
                        (OID_SHA512, D64, "sha512")):
        imp = _message_imprint(d, oid)
        _, content, _ = _read_tlv(imp)
        assert parse_message_imprint(content)["hash_alg"] == alg
        assert parse_message_imprint(content)["hash_oid"] == oid


def test_full_tst_info_byte_length_stable():
    """Ayni girdi ayni cikti (deterministic-builder, zaman-disi)."""
    a = _tst_info(_message_imprint(D32), 3, GT, 5)
    b = _tst_info(_message_imprint(D32), 3, GT, 5)
    assert a == b
    assert len(a) == 97

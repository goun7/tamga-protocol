"""snapshot_body_digest TSG1 snapshot-parse testleri (LEED).

Kural-1: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Dış çağrı YOK: sentetik TSG1 blob'ları (gerçek şifreleme YOK —
digest şifreli gövdenin SHA-256'sıdır, decrypt edilmez).
"""
import hashlib
import json
import struct
import sys

import pytest

sys.path.insert(0, ".")

import tamga_oracle_relayer as tor  # noqa: E402

_HEADER_KEYS = ("format", "pkg_name", "pkg_wasm_sha256", "agent_id",
                "cipher", "body_nonce", "created")


def _header(**over):
    h = dict(
        format=tor.SNAPSHOT_FORMAT,
        pkg_name="test-pkg",
        pkg_wasm_sha256="a" * 64,
        agent_id="did:web:test",
        cipher=tor.SNAPSHOT_CIPHER,
        body_nonce="b" * 32,
        created="2026-10-08T12:00:00Z",
    )
    h.update(over)
    return h


def _snap(path, header=None, ct=b"CIPHERTEXT-BODY", magic=tor.SNAPSHOT_MAGIC,
          hlen_override=None, prefix=b""):
    h = json.dumps(header if header is not None else _header(),
                   separators=(",", ":")).encode("utf-8")
    hlen = len(h) if hlen_override is None else hlen_override
    blob = prefix + magic + struct.pack(">I", hlen) + h + ct
    path.write_bytes(blob)
    return blob


@pytest.fixture
def snap(tmp_path):
    p = tmp_path / "snap.tsg"
    return p


# -- temel başarı ---------------------------------------------------------------------------

def test_valid_snapshot_parses(snap):
    _snap(snap)
    r = tor.snapshot_body_digest(snap)
    assert isinstance(r, dict)


def test_returns_header(snap):
    h = _header(pkg_name="paket-1")
    _snap(snap, header=h)
    assert tor.snapshot_body_digest(snap)["header"]["pkg_name"] == "paket-1"


def test_returns_ct(snap):
    _snap(snap, ct=b"ozel-govde")
    assert tor.snapshot_body_digest(snap)["ct"] == b"ozel-govde"


def test_digest_is_sha256_of_ct(snap):
    """Mühür-1 standardı: digest = SHA-256(ct), tüm-blob DEĞİL."""
    ct = b"govde-123"
    _snap(snap, ct=ct)
    r = tor.snapshot_body_digest(snap)
    assert r["digest"] == hashlib.sha256(ct).hexdigest()


def test_digest_stable_across_created_change(snap):
    """D3 portabilite: header.created değişse digest AYNI (ct kararlı)."""
    _snap(snap, header=_header(created="2026-10-01T00:00:00Z"))
    d1 = tor.snapshot_body_digest(snap)["digest"]
    _snap(snap, header=_header(created="2026-10-08T00:00:00Z"))
    d2 = tor.snapshot_body_digest(snap)["digest"]
    assert d1 == d2


def test_blob_sha256_is_full_blob(snap):
    blob = _snap(snap)
    r = tor.snapshot_body_digest(snap)
    assert r["blob_sha256"] == hashlib.sha256(blob).hexdigest()


def test_blob_differs_from_digest(snap):
    """digest (ct) ≠ blob_sha256 (tüm blob) — farklı değerler."""
    _snap(snap)
    r = tor.snapshot_body_digest(snap)
    assert r["digest"] != r["blob_sha256"]


def test_bytes_field(snap):
    blob = _snap(snap)
    assert tor.snapshot_body_digest(snap)["bytes"] == len(blob)


def test_ct_not_decrypted(snap):
    """Relayer seed tutmaz — ct ASLA decrypt edilmez."""
    _snap(snap, ct=b"plain-looking-text")
    r = tor.snapshot_body_digest(snap)
    assert r["ct"] == b"plain-looking-text"
    assert "plaintext" not in r


# -- MAGIC ---------------------------------------------------------------------------

def test_bad_magic_rejected(snap):
    _snap(snap, magic=b"XXXX")
    with pytest.raises(tor.TamgaRelayerError) as e:
        tor.snapshot_body_digest(snap)
    assert e.value.reason_code == tor.RC_SNAPSHOT_BAD_MAGIC


def test_empty_file_rejected(snap):
    snap.write_bytes(b"")
    with pytest.raises(tor.TamgaRelayerError) as e:
        tor.snapshot_body_digest(snap)
    assert e.value.reason_code == tor.RC_SNAPSHOT_BAD_MAGIC


def test_truncated_magic_rejected(snap):
    snap.write_bytes(b"TS")
    with pytest.raises(tor.TamgaRelayerError):
        tor.snapshot_body_digest(snap)


def test_missing_file_rejected(tmp_path):
    with pytest.raises(tor.TamgaRelayerError) as e:
        tor.snapshot_body_digest(tmp_path / "yok.tsg")
    assert e.value.reason_code == tor.RC_SNAPSHOT_BAD_MAGIC


# -- header uzunluğu ---------------------------------------------------------------------------

def test_zero_hlen_rejected(snap):
    _snap(snap, hlen_override=0)
    with pytest.raises(tor.TamgaRelayerError) as e:
        tor.snapshot_body_digest(snap)
    assert e.value.reason_code == tor.RC_SNAPSHOT_HEADER


def test_hlen_beyond_data_rejected(snap):
    _snap(snap, hlen_override=99999)
    with pytest.raises(tor.TamgaRelayerError) as e:
        tor.snapshot_body_digest(snap)
    assert e.value.reason_code == tor.RC_SNAPSHOT_HEADER


def test_hlen_exactly_file_end(snap):
    """8+hlen == len(data) → ct boş → gövde-yok hatası."""
    h = json.dumps(_header(), separators=(",", ":")).encode()
    snap.write_bytes(tor.SNAPSHOT_MAGIC + struct.pack(">I", len(h)) + h)
    with pytest.raises(tor.TamgaRelayerError) as e:
        tor.snapshot_body_digest(snap)
    assert e.value.reason_code == tor.RC_SNAPSHOT_HEADER


def test_hlen_negative_rejected(snap):
    """uint32 olarak 0xFFFFFFFF çok büyük → aralık-dışı."""
    _snap(snap, hlen_override=0xFFFFFFFF)
    with pytest.raises(tor.TamgaRelayerError):
        tor.snapshot_body_digest(snap)


# -- header şema ---------------------------------------------------------------------------

@pytest.mark.parametrize("missing", _HEADER_KEYS)
def test_missing_header_key_rejected(snap, missing):
    h = _header()
    del h[missing]
    _snap(snap, header=h)
    with pytest.raises(tor.TamgaRelayerError) as e:
        tor.snapshot_body_digest(snap)
    assert e.value.reason_code == tor.RC_SNAPSHOT_HEADER


def test_wrong_format_rejected(snap):
    _snap(snap, header=_header(format="tamga-snapshot/2"))
    with pytest.raises(tor.TamgaRelayerError) as e:
        tor.snapshot_body_digest(snap)
    assert e.value.reason_code == tor.RC_SNAPSHOT_HEADER


def test_wrong_cipher_rejected(snap):
    _snap(snap, header=_header(cipher="AES-256-GCM"))
    with pytest.raises(tor.TamgaRelayerError) as e:
        tor.snapshot_body_digest(snap)
    assert e.value.reason_code == tor.RC_SNAPSHOT_HEADER


def test_header_not_json_rejected(snap):
    hlen = 10
    snap.write_bytes(tor.SNAPSHOT_MAGIC + struct.pack(">I", hlen)
                     + b"not-json!" + b"ct")
    with pytest.raises(tor.TamgaRelayerError) as e:
        tor.snapshot_body_digest(snap)
    assert e.value.reason_code == tor.RC_SNAPSHOT_HEADER


def test_header_not_object_rejected(snap):
    raw = json.dumps([1, 2, 3]).encode()
    snap.write_bytes(tor.SNAPSHOT_MAGIC + struct.pack(">I", len(raw))
                     + raw + b"ct")
    with pytest.raises(tor.TamgaRelayerError):
        tor.snapshot_body_digest(snap)


def test_empty_ct_rejected(snap):
    _snap(snap, ct=b"")
    with pytest.raises(tor.TamgaRelayerError) as e:
        tor.snapshot_body_digest(snap)
    assert e.value.reason_code == tor.RC_SNAPSHOT_HEADER


# -- boyut sınırı ---------------------------------------------------------------------------

def test_oversized_snapshot_rejected(snap, monkeypatch):
    monkeypatch.setattr(tor, "SAFE_SNAP_MAX", 100)
    _snap(snap, ct=b"x" * 200)
    with pytest.raises(tor.TamgaRelayerError) as e:
        tor.snapshot_body_digest(snap)
    assert e.value.reason_code == tor.RC_SNAPSHOT_TOO_LARGE


def test_at_size_limit_ok(snap, monkeypatch):
    monkeypatch.setattr(tor, "SAFE_SNAP_MAX", 4096)
    _snap(snap)
    assert tor.snapshot_body_digest(snap)["bytes"] < 4096


# -- ct多变 ---------------------------------------------------------------------------

def test_large_ct_digest_ok(snap):
    ct = b"\x00\xff" * 5000
    _snap(snap, ct=ct)
    r = tor.snapshot_body_digest(snap)
    assert r["digest"] == hashlib.sha256(ct).hexdigest()


def test_single_byte_ct_ok(snap):
    _snap(snap, ct=b"X")
    r = tor.snapshot_body_digest(snap)
    assert len(r["ct"]) == 1


def test_binary_ct_ok(snap):
    ct = bytes(range(256))
    _snap(snap, ct=ct)
    r = tor.snapshot_body_digest(snap)
    assert r["ct"] == ct


def test_digest_length_64(snap):
    _snap(snap)
    assert len(tor.snapshot_body_digest(snap)["digest"]) == 64


def test_digest_is_hex(snap):
    _snap(snap)
    d = tor.snapshot_body_digest(snap)["digest"]
    assert all(c in "0123456789abcdef" for c in d)

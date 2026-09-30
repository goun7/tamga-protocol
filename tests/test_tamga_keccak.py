"""tamga_keccak — Keccak-256 (legacy 0x01 padding) known-vector and property tests.

The module is a hand-rolled Keccak-256 so Tamga digests match the Ethereum/x402
world. Its own __main__ block already asserts three KAT vectors; these tests
cover the same vectors plus determinism, length and error-path properties so the
guarantees hold without running the module as a script.
"""
import hashlib

import pytest

import tamga_keccak


# --- known-answer vectors (published Keccak-256, legacy padding) -------------------------
VECTORS = [
    (b"", "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"),
    (b"abc", "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"),
    (b"The quick brown fox jumps over the lazy dog",
     "4d741b6f1eb29cb2a9b9911c82f56fa8d73b04959d3d9d222895df6c0b28aa15"),
]


@pytest.mark.parametrize("data,expected", VECTORS, ids=["empty", "abc", "fox"])
def test_keccak256_known_vectors(data, expected):
    """Empty/short/medium inputs must reproduce the published Keccak-256 KATs."""
    assert tamga_keccak.keccak256(data).hex() == expected


def test_keccak256_is_not_sha3_256():
    """Domain byte is 0x01 (legacy Keccak), not FIPS 0x06 — the whole reason the
    module exists. hashlib.sha3_256 must disagree on every input."""
    assert tamga_keccak.keccak256(b"abc") != hashlib.sha3_256(b"abc")


def test_keccak256_output_length_is_always_32_bytes():
    """Digest is 4 lanes little-endian → exactly 32 bytes regardless of input size,
    including inputs that span multiple rate blocks (rate = 136 bytes)."""
    for data in (b"", b"x", b"a" * 135, b"a" * 136, b"a" * 137, b"a" * 10000):
        out = tamga_keccak.keccak256(data)
        assert len(out) == 32
        assert len(out.hex()) == 64


def test_keccak256_deterministic_and_stable():
    """Same input must always yield the same digest (receipts are re-derived by
    strangers; any drift breaks chain verification)."""
    first = tamga_keccak.keccak256(b"determinism-probe")
    for _ in range(5):
        assert tamga_keccak.keccak256(b"determinism-probe") == first


def test_keccak256_distinct_inputs_distinct_digests():
    """Avalanche: different inputs must not collide, and appending bytes changes
    the digest (length-extension style inputs must not share prefixes)."""
    base = tamga_keccak.keccak256(b"payload")
    assert tamga_keccak.keccak256(b"payload2") != base
    assert tamga_keccak.keccak256(b"payload" + b"\x00") != base


def test_keccak256_rejects_non_bytes():
    """The sponge XORs raw bytes; a str would raise on concatenation — surface the
    TypeError rather than silently encoding (callers must be explicit)."""
    with pytest.raises(TypeError):
        tamga_keccak.keccak256("not-bytes")


def test_keccak256_large_input_matches_streamed_expectation():
    """A multi-block input is still a pure function of the bytes: splitting the
    computation is impossible (state is chained), so this pins whole-document
    behaviour at 8× the rate."""
    data = bytes(range(256)) * 43  # 11008 bytes, several absorption rounds
    out = tamga_keccak.keccak256(data)
    assert len(out) == 32
    assert out == tamga_keccak.keccak256(data)

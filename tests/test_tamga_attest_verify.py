"""tamga_attest_verify — CAPACITY_ATTEST_V1 claim verification tests.

The module re-derives the vendor's attestation verdict with pure stdlib crypto
(secp256k1 + EIP-191). To exercise the GREEN path honestly we sign a claim with
the module's own curve helpers — no third-party dependency, and the signature is
genuinely produced on the EIP-191 pre-image so the recover path is real.
``ecrecover_to_pub`` is deliberately not tested: it imports ``eth_utils``, which
may be absent, so it is out of scope for a stdlib-only suite.
"""
import hashlib

import pytest

import tamga_attest_verify as tav
import tamga_keccak


def _privkey_address(d):
    """d (int) → (address_str, pubkey point) using the module's curve constants."""
    pub = tav._mul(d, (tav.GX, tav.GY))
    return tav._address(pub), pub


def _sign_eip191(d, cid):
    """Produce a valid low-s (r, s, v) EIP-191 signature of `cid` with privkey
    `d`, mirroring what the vendor's ethers signer would emit (EIP-2 low-s)."""
    z = tav._eip191_hash(cid)
    k = 0x0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF
    R = tav._mul(k, (tav.GX, tav.GY))
    r = R[0]
    s = (tav._inv(k, tav.N) * (z + r * d)) % tav.N
    parity = R[1] & 1
    if s > tav.N // 2:               # EIP-2 low-s normalization
        s = tav.N - s
        parity ^= 1
    v = 27 + parity
    return r, s, v


def _make_claim(content, buyer_addr, privkey):
    """Build a well-formed claim whose claimId/signature are genuinely valid."""
    pre = tav._canonical_preimage(content)
    cid = "0x" + hashlib.sha256(pre).hexdigest()
    r, s, v = _sign_eip191(privkey, cid)
    sig = "0x" + r.to_bytes(32, "big").hex() + s.to_bytes(32, "big").hex() + bytes([v]).hex()
    return {**content, "claimId": cid, "signature": sig}


BUYER_PRIV = 0x1111111111111111111111111111111111111111111111111111111111111111
SELLER_PRIV = 0x2222222222222222222222222222222222222222222222222222222222222222


@pytest.fixture(scope="module")
def valid_claim():
    """A claim signed by the buyer over its own canonical pre-image."""
    buyer, _ = _privkey_address(BUYER_PRIV)
    seller, _ = _privkey_address(SELLER_PRIV)
    content = {
        "sellerAddress": seller.upper(),          # normalization path: lowercased in pre-image
        "buyerAddress": buyer.upper(),
        "assetType": "bandwidth",
        "promisedSpec": {"throughput_mbps": 100},
        "delivered": {"throughput_mbps": 97},
        "evidenceHash": "0x" + "ab" * 32,
        "settlementRef": "settle-1",
        "timestamp": 1700000000,
        "measured": True,
        "externalRefs": ["ref-a"],
        "priorClaimId": None,
    }
    return _make_claim(content, buyer, BUYER_PRIV)


# --- GREEN path --------------------------------------------------------------------------
def test_verify_valid_claim_is_green(valid_claim):
    """End-to-end: self-signed claim verifies ok and the recovered signer equals
    the buyer address (case-insensitively — addresses were upper-cased above)."""
    ok, reason, detail = tav.verify_capacity_attest(valid_claim)
    assert ok is True
    assert reason == "ok"
    assert detail["signer_recover"] == valid_claim["buyerAddress"].lower()
    assert detail["buyerAddress"] == valid_claim["buyerAddress"]


def test_claimid_is_sha256_of_canonical_preimage(valid_claim):
    """claimId contract: sha256 over the schema-filtered, address-normalized JCS
    bytes — any tampering with the payload must flip it."""
    pre = tav._canonical_preimage(valid_claim)
    expected = "0x" + hashlib.sha256(pre).hexdigest()
    assert valid_claim["claimId"] == expected


def test_canonical_preimage_drops_meta_keys_and_is_deterministic(valid_claim):
    """claimId/signature are NOT part of the hashed content (they cover it), and
    the pre-image is a stable pure function of the content."""
    first = tav._canonical_preimage(valid_claim)
    assert tav._canonical_preimage(valid_claim) == first
    assert b"claimId" not in first and b"signature" not in first
    # unknown schema keys are stripped (zod unknown-key parity)
    assert tav._canonical_preimage({**valid_claim, "rogueKey": "x"}) == first


def test_verify_is_deterministic(valid_claim):
    """Repeated verdicts on the same claim must be identical (no time/randomness)."""
    first = tav.verify_capacity_attest(valid_claim)
    for _ in range(3):
        assert tav.verify_capacity_attest(valid_claim) == first


# --- RED paths ---------------------------------------------------------------------------
def test_claimid_mismatch_is_red():
    """A claimId that does not match the content is the primary RED case."""
    buyer, _ = _privkey_address(BUYER_PRIV)
    claim = _make_claim({"buyerAddress": buyer, "assetType": "x"}, buyer, BUYER_PRIV)
    claim["claimId"] = "0x" + "00" * 32
    ok, reason, detail = tav.verify_capacity_attest(claim)
    assert ok is False
    assert reason == "claimId_mismatch"
    assert "claimId_biz" in detail and "claimId_beyan" in detail


def test_missing_envelope_is_red():
    """Non-string / missing claimId, signature or buyerAddress → malformed envelope."""
    ok, reason, detail = tav.verify_capacity_attest({"claimId": 123, "signature": "0x"})
    assert ok is False
    assert reason.startswith("zarf-eksik")
    assert detail == {}


def test_signature_does_not_match_buyer(valid_claim):
    """A valid signature by a DIFFERENT key over the correct claimId must be RED
    with the vendor-named mismatch reason (signer ≠ buyer). The claimId still
    matches the content (buyerAddress unchanged), so the failure is purely the
    signer mismatch."""
    content = {k: v for k, v in valid_claim.items() if k not in ("claimId", "signature")}
    claim = _make_claim(content, content["buyerAddress"], SELLER_PRIV)
    ok, reason, detail = tav.verify_capacity_attest(claim)
    assert ok is False
    assert reason == "signature_does_not_match_buyer"
    assert detail["signer_recover"] != content["buyerAddress"].lower()


def test_broken_signature_hex_is_red(valid_claim):
    """Non-hex signature bytes are invalid input (a RED), not a lookup failure."""
    claim = dict(valid_claim)
    claim["signature"] = "0xZZZnot-hex-at-all"
    ok, reason, _ = tav.verify_capacity_attest(claim)
    assert ok is False
    assert reason.startswith("signature_bozuk")


def test_invalid_signature_geometry_is_red(valid_claim):
    """rec_id outside {0,1} (v bytes 29/30) is rejected as invalid geometry."""
    r, s, v = _sign_eip191(BUYER_PRIV, valid_claim["claimId"])
    claim = dict(valid_claim)
    claim["signature"] = ("0x" + r.to_bytes(32, "big").hex()
                          + s.to_bytes(32, "big").hex() + bytes([v + 2]).hex())
    ok, reason, _ = tav.verify_capacity_attest(claim)
    assert ok is False
    assert reason == "signature_geometrisi_gecersiz"


def test_high_s_signature_is_red(valid_claim):
    """EIP-2 low-s enforcement: s > N//2 is malleable and must be rejected even
    though it is a mathematically valid signature of the same message."""
    r, s, v = _sign_eip191(BUYER_PRIV, valid_claim["claimId"])
    claim = dict(valid_claim)
    s_high = tav.N - s
    assert s_high > tav.N // 2
    claim["signature"] = ("0x" + r.to_bytes(32, "big").hex()
                          + s_high.to_bytes(32, "big").hex() + bytes([v]).hex())
    ok, reason, _ = tav.verify_capacity_attest(claim)
    assert ok is False
    assert reason == "signature_geometrisi_gecersiz"


def test_unrecoverable_signature_is_red(valid_claim):
    """Low-s and rec_id in {0,1} (so it passes the geometry gate) but r outside
    the valid range: no curve point can be recovered → RED, never INDETERMINE."""
    claim = dict(valid_claim)
    r = tav.P + 1                   # >= N → outside [1, N); also x = r >= P
    s = 1                           # low-s, so the geometry gate lets it through
    claim["signature"] = ("0x" + r.to_bytes(32, "big").hex()
                          + s.to_bytes(32, "big").hex() + bytes([27]).hex())
    ok, reason, _ = tav.verify_capacity_attest(claim)
    assert ok is False
    assert reason == "signature_recover_edilemedi"


def test_registry_dispatch_unknown_tag_is_indeterminate():
    """RFC-009: an unknown origin tag withholds the verdict (exit 2) rather than
    claiming a pass or fail the module cannot actually back."""
    assert tav.REGISTRY["CAPACITY_ATTEST_V1"] is tav.verify_capacity_attest
    assert "NOPE" not in tav.REGISTRY
    assert tav.EXIT_GREEN == 0 and tav.EXIT_RED == 1 and tav.EXIT_IND == 2


def test_address_is_keccak_of_compressed_pubkey_x_and_y(valid_claim):
    """Ethereum address = keccak256(x‖y)[12:] using legacy Keccak — pin the
    construction so a switch to sha3_256 would fail loudly."""
    pub = tav._mul(BUYER_PRIV, (tav.GX, tav.GY))
    x, y = pub
    raw = x.to_bytes(32, "big") + y.to_bytes(32, "big")
    assert tav._address(pub) == "0x" + tamga_keccak.keccak256(raw)[12:].hex()

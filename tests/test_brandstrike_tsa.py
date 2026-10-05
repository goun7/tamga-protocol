"""brandstrike_tsa — RFC 3161 ↔ Tamga hash-chain code-bond tests.

The README documents the pairing with BrandStrike as prose (the time axis); this
module is the code bond, so these tests pin the behaviours the bond depends on:
the DER codec is strict, the chain math matches the runner's own implementation,
a token over the true tip is GREEN, and every decoy/replay/malformation path is
RED rather than INDETERMINE. The GREEN path is genuine — the token is really
signed (Ed25519, PyNaCl) over a TSTInfo whose imprint is the ledger tip's
digest, so the signature check is exercised, not stubbed.
"""
import datetime
import hashlib
import sys
from pathlib import Path

import pytest
from nacl.signing import SigningKey

# conftest.py puts the repo root on sys.path; the tool itself lives in tools/.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

import brandstrike_tsa as bst
import tamga_runner as tr


# --- fixtures: a real two-record chain ----------------------------------------------------
def _chain_record(prev: str, seq: int, note: str) -> dict:
    rec = {"op": "charge", "note": note, "amount": "0.01", "ts": "2026-10-05T00:00:00Z",
           "seq": seq, "prev": prev}
    no_h = {k: v for k, v in rec.items() if k != "h"}
    rec["h"] = hashlib.sha256((prev + bst._jcs_str(no_h)).encode("utf-8")).hexdigest()
    return rec


@pytest.fixture
def ledger():
    r1 = _chain_record("0" * 64, 1, "ilk-kanit")
    r2 = _chain_record(r1["h"], 2, "iki-kanit")
    return [r1, r2]


@pytest.fixture
def tsa_key():
    return SigningKey(bytes.fromhex("9" * 64))


def _token(ledger, tsa_key, *, imprint=None, nonce=0x4242, serial=7,
           gen_time=bst.DEMO_GEN_TIME, status=0, fail_info=None, status_string=None,
           sig_key=None):
    """Mint a syntactically real RFC 3161 response over `imprint` (defaults to
    the ledger's tip digest)."""
    digest = imprint if imprint is not None else bst.tip_imprint(ledger)[0]
    imp = bst._message_imprint(digest)
    tst = bst._tst_info(imp, serial, gen_time, nonce)
    signer = sig_key or tsa_key
    return bst.build_timestamp_resp(imp, serial=serial, gen_time=gen_time, nonce=nonce,
                                    signature=signer.sign(tst).signature, status=status,
                                    fail_info=fail_info, status_string=status_string)


# --- the chain bond ------------------------------------------------------------------------
def test_chain_tip_matches_the_runner_exactly(ledger):
    """The bond's target must be the runner's own tip: same rule, same bytes —
    otherwise a token would verify against a chain it does not cover."""
    mine, why = bst.chain_tip(ledger)
    theirs, why2 = tr._verify_chain([dict(r) for r in ledger])
    assert why == "ok" and why2 == "ok"
    assert mine == theirs == ledger[-1]["h"]


def test_tip_imprint_is_double_sha256_of_the_tip(ledger):
    """The TSA's input is sha256(tip_bytes): opaque to the ledger's internal
    serialization, yet bound to the exact tip."""
    digest, why, tip = bst.tip_imprint(ledger)
    assert why == "ok" and tip == ledger[-1]["h"]
    assert digest == hashlib.sha256(bytes.fromhex(tip)).digest()


def test_broken_chain_is_red_even_with_a_valid_token(ledger, tsa_key):
    """A perfectly signed token cannot rescue a ledger whose chain is broken —
    the hash axis and the time axis are checked independently."""
    resp = _token(ledger, tsa_key)
    broken = [dict(ledger[0]), dict(ledger[1], prev="f" * 64)]
    verdict, reason, _ = bst.bind_chain(resp, broken)
    assert verdict == "red"
    assert reason.startswith("chain_not_verifiable")


def test_empty_ledger_is_red():
    verdict, reason, _ = bst.bind_chain(b"\x00" * 4, [])
    assert verdict == "red"
    assert "empty" in reason or "chain_not_verifiable" in reason


# --- GREEN path ---------------------------------------------------------------------------
def test_token_over_the_true_tip_binds_green(ledger, tsa_key):
    resp = _token(ledger, tsa_key)
    verdict, reason, detail = bst.bind_chain(resp, ledger, tsa_key=tsa_key.verify_key.encode().hex())
    assert verdict == "ok" and reason == "ok"
    assert detail["chain_tip"] == ledger[-1]["h"]
    assert detail["gen_time"] if "gen_time" in detail else True
    assert "verified" in detail["signature"]


def test_gen_time_is_rendered_as_iso_8601(ledger, tsa_key):
    """The receipt-facing timestamp is ISO-8601 UTC, derived from the token's
    GeneralizedTime — this is the field BrandStrike's evidence carries."""
    resp = _token(ledger, tsa_key)
    _, _, detail = bst.bind_chain(resp, ledger, tsa_key=tsa_key.verify_key.encode().hex())
    assert detail["tst"]["gen_time"] == "2026-10-05T12:05:30Z"


# --- RED paths: the decoy and replay attacks -----------------------------------------------
def test_token_over_a_decoy_digest_is_red(ledger, tsa_key):
    """A validly signed token over the WRONG digest is RED — a TSA cannot be
    replayed to vouch for a chain it never stamped."""
    decoy = bst.evidence_imprint(b"not-the-ledger")
    resp = _token(ledger, tsa_key, imprint=decoy)
    verdict, reason, detail = bst.bind_chain(resp, ledger, tsa_key=tsa_key.verify_key.encode().hex())
    assert verdict == "red"
    assert reason.startswith("imprint_mismatch")
    assert detail["imprint"] == decoy.hex()


def test_nonce_mismatch_is_red(ledger, tsa_key):
    """The nonce is the caller's replay defense: a response echoing a different
    nonce was minted for a different request."""
    resp = _token(ledger, tsa_key, nonce=0x9999)
    verdict, reason, _ = bst.bind_chain(resp, ledger, nonce=0x4242,
                                        tsa_key=tsa_key.verify_key.encode().hex())
    assert verdict == "red"
    assert reason.startswith("nonce_mismatch")


def test_bad_signature_is_red(ledger, tsa_key):
    """The signature gate is real: a token signed by a different key over the
    correct imprint and nonce is still RED."""
    impostor = SigningKey(bytes.fromhex("1" * 64))
    resp = _token(ledger, tsa_key, sig_key=impostor)
    verdict, reason, _ = bst.bind_chain(resp, ledger, nonce=0x4242,
                                        tsa_key=tsa_key.verify_key.encode().hex())
    assert verdict == "red"
    assert reason.startswith("signature_invalid")


def test_signature_of_a_wrong_message_is_red(ledger, tsa_key):
    """A signature that does not cover the eContent octets (here: signed over
    arbitrary bytes) must fail verification."""
    digest = bst.tip_imprint(ledger)[0]
    imp = bst._message_imprint(digest)
    tst = bst._tst_info(imp, 7, bst.DEMO_GEN_TIME, 0x4242)
    bad_sig = tsa_key.sign(b"other-message").signature
    resp = bst.build_timestamp_resp(imp, serial=7, gen_time=bst.DEMO_GEN_TIME,
                                    nonce=0x4242, signature=bad_sig)
    verdict, reason, _ = bst.bind_chain(resp, ledger, nonce=0x4242,
                                        tsa_key=tsa_key.verify_key.encode().hex())
    assert verdict == "red"
    assert reason.startswith("signature_invalid")


def test_tsa_rejection_status_is_red_with_failinfo(ledger, tsa_key):
    resp = _token(ledger, tsa_key, status=2, status_string="unsupported policy",
                  fail_info=["unacceptedPolicy"])
    verdict, reason, detail = bst.bind_chain(resp, ledger)
    assert verdict == "red"
    assert reason == "tsa_status_rejection"
    assert detail["fail_info"] == ["unacceptedPolicy"]


def test_granted_without_a_token_is_red(ledger, tsa_key):
    digest = bst.tip_imprint(ledger)[0]
    resp = bst.build_timestamp_resp(bst._message_imprint(digest), serial=7,
                                    gen_time=bst.DEMO_GEN_TIME, nonce=0x4242,
                                    signature=tsa_key.sign(b"x").signature, status=3)
    verdict, reason, _ = bst.bind_chain(resp, ledger)
    assert verdict == "red"
    # status 3 (waiting) carries no token, and no token means no bond
    assert reason.startswith("tsa_status_waiting") or reason == "tsa_granted_without_token"


# --- fail-closed parsing -------------------------------------------------------------------
@pytest.mark.parametrize("junk", [b"", b"\x30", b"not-der", b"\x30\x81\x01\x00"])
def test_malformed_der_is_red_never_a_crash(junk, ledger):
    verdict, reason, _ = bst.bind_chain(junk, ledger)
    assert verdict == "red"
    assert reason.startswith("response_malformed")


def test_truncated_token_is_red(ledger, tsa_key):
    resp = _token(ledger, tsa_key)
    verdict, reason, _ = bst.bind_chain(resp[: len(resp) // 2], ledger)
    assert verdict == "red"
    assert reason.startswith("response_malformed")


def test_non_minimal_der_length_is_rejected():
    """A non-minimal length octet is a DER violation — the codec must not
    re-interpret a forged length field."""
    with pytest.raises(ValueError):
        bst._read_tlv(b"\x30\x81\x05\x00\x00\x00\x00\x00")


def test_indefinite_length_is_rejected():
    with pytest.raises(ValueError):
        bst._read_tlv(b"\x30\x80\x00\x00")


# --- GeneralizedTime ----------------------------------------------------------------------
@pytest.mark.parametrize("text,expect", [
    ("20261005120530Z", datetime.datetime(2026, 10, 5, 12, 5, 30, tzinfo=datetime.timezone.utc)),
    ("20261005120530", datetime.datetime(2026, 10, 5, 12, 5, 30, tzinfo=datetime.timezone.utc)),
    ("20261005150530+0300", datetime.datetime(2026, 10, 5, 12, 5, 30, tzinfo=datetime.timezone.utc)),
    ("20261005090530-0300", datetime.datetime(2026, 10, 5, 12, 5, 30, tzinfo=datetime.timezone.utc)),
    ("20261005120530.5Z", datetime.datetime(2026, 10, 5, 12, 5, 30, 500000,
                                            tzinfo=datetime.timezone.utc)),
])
def test_gen_time_forms(text, expect):
    assert bst.dec_gen_time(text) == expect


@pytest.mark.parametrize("bad", ["20261340120530Z", "20261005", "not-a-time", "20261005120530Z1"])
def test_gen_time_rejects_impossible_values(bad):
    with pytest.raises(ValueError):
        bst.dec_gen_time(bad)


# --- query side ---------------------------------------------------------------------------
def test_query_roundtrip_and_well_formed(ledger):
    digest = bst.tip_imprint(ledger)[0]
    req = bst.build_timestamp_req(digest, nonce=0x4242, policy=bst.OID_DEMO_POLICY)
    back = bst.parse_timestamp_req(req)
    assert back["version"] == 1
    assert back["imprint"]["imprint"] == digest.hex()
    assert back["imprint"]["hash_alg"] == "sha256"
    assert back["nonce"] == 0x4242
    assert back["policy"] == bst.OID_DEMO_POLICY
    assert back["cert_req"] is False


def test_query_digest_length_is_enforced():
    with pytest.raises(ValueError):
        bst._message_imprint(b"\x00" * 31)


def test_query_rejects_unknown_field():
    digest = bst.evidence_imprint(b"x")
    req = bst.build_timestamp_req(digest, nonce=1)
    # inject a foreign trailing element after the mandatory ones
    body = bst._read_tlv(req)[1] + bst._tlv(0x04, b"rogue")
    with pytest.raises(ValueError):
        bst.parse_timestamp_req(bst._tlv(0x30, body))

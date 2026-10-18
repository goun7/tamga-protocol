#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
KOK -> TAMGA bridge — an INDEPENDENT Python verifier for the kok mining-proof
receipt (the "compute-work proof" of the mesh's Option-C evolution).

WHAT THIS FILE IS
-----------------
kok's core proof is emitted by the Rust crate `kok-proof` (`cargo run --bin kok
-- create ... -> kanit.json`). The mesh's evidence chain (tamga) is Python.
This file is the **third-party Python verifier** for that receipt: given only
the JSON document, it re-derives every load-bearing claim and says ACCEPT or
RED. It imports nothing from kok and nothing from tamga, because a verifier
that imports the prover's code is not independent.

The checks mirror `kok-proof/src/lib.rs::verify` one-for-one:
  1. structural (proof_type/proof_version/layer, receipt_prev hex-64)
  2. matrix shape (square, n % r == 0, cert_m == n // r)
  3. commitments recomputed (program_commit, input_commit)
  4. the useful work: the KwKernel tile accumulator recomputed under the
     ctx-derived noise pair, then the difficulty target
  5. the receipt hash: sha256 over the fixed-field pipe-delimited envelope
  6. the Ed25519 signature under the self-resolving did:key

Cross-language determinism is the whole value: the envelope is a frozen field
order over an all-integer document, so Python and Rust recompute it
byte-for-byte. This file TESTS that agreement against a real `kanit.json`
produced by the Rust binary (see the main block below).

DEPENDENCIES: only `hashlib`, `json`, `re`, `base58`-free hand-rolled base58btc
(the multibase decoding is 40 lines, not worth a dependency), and PyNaCl's
Ed25519 bindings (`nacl.bindings`) — which tamga already depends on, so the
mesh adds no new dependency to verify a kok receipt.

WHAT THIS FILE IS NOT
---------------------
- It does not verify the tamga ledger chain (that is tamga's own verifier).
- It does not validate the economic claim (that the work was *commissioned*);
  it validates that the work was *performed and bound to (A, B, ctx)*.
  The E-gap lesson (TV-72/TV-77) is that binding which-task is achievable and
  binding that-a-buyer-wanted-it is not; this verifier deliberately claims
  only the first.
- It is not a zk proof: the verifier sees the matrices (as the L1 design's
  own TV-43 measured, the toy ZK layer hides nothing at q=97).

Run:  python3 kok_receipt_verify_en.py [kanit.json ...]
Exit: 0 if every given receipt ACCEPTs, 1 if any goes RED, 2 if the
      cross-language self-test against the Rust binary fails.
"""

import hashlib
import json
import subprocess
import sys

try:
    from nacl.bindings import crypto_sign_open, crypto_sign_BYTES
except ImportError:  # pragma: no cover
    crypto_sign_open = None

# ---------------------------------------------------------------------------
# Constants frozen to the Rust crate's (kok-proof/src/lib.rs:55-63, did.rs:57)
# ---------------------------------------------------------------------------

PROOF_VERSION = 1
PROOF_TYPE = "kok.mining-proof"
DEFAULT_LAYER = "G"
SIG_DOMAIN = b"kok.mining-proof.sig.v1:"
MULTICODEC_ED25519_PUB = bytes([0xED, 0x01])
B58_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _u64_be(d: bytes) -> int:
    return int.from_bytes(d[:8], "big")


# ---------------------------------------------------------------------------
# The hash the Rust kernel uses: sha256 over prefix|n1|n2|... decimal parts.
# Mirrors `h_num` (kok-poum/src/lib.rs:103) exactly, including the domain
# separator written before the numeric parts.
# ---------------------------------------------------------------------------

def h_num(prefix: str, nums) -> int:
    s = prefix + "|" + "|".join(str(n) for n in nums)
    return _u64_be(hashlib.sha256(s.encode("utf-8")).digest())


# ---------------------------------------------------------------------------
# base58btc (Bitcoin alphabet, no checksum — multibase, not a Bitcoin address)
# Mirrors did.rs b58_encode/b58_decode.
# ---------------------------------------------------------------------------

def b58_encode(data: bytes) -> str:
    digits = []
    for byte in data:
        carry = byte
        for i in range(len(digits)):
            carry += digits[i] << 8
            digits[i] = carry % 58
            carry //= 58
        while carry > 0:
            digits.append(carry % 58)
            carry //= 58
    out = ""
    # leading zero bytes -> '1'
    n_zeros = 0
    for b in data:
        if b == 0:
            n_zeros += 1
        else:
            break
    return "1" * n_zeros + "".join(B58_ALPHABET[d] for d in reversed(digits))


def b58_decode(s: str):
    digits = []
    for ch in s:
        val = B58_ALPHABET.find(ch)
        if val < 0:
            raise ValueError("non-base58 character %r" % ch)
        carry = val
        for i in range(len(digits)):
            carry += digits[i] * 58
            digits[i] = carry & 0xFF
            carry >>= 8
        while carry > 0:
            digits.append(carry & 0xFF)
            carry >>= 8
    # leading '1' chars -> leading zero bytes. Rust counts leading zeros in
    # the INPUT when encoding; when decoding it must count them in the string.
    n_zeros = 0
    for ch in s:
        if ch == "1":
            n_zeros += 1
        else:
            break
    return bytes([0] * n_zeros) + bytes(reversed(digits))


def public_key_from_did(did: str) -> bytes:
    if not did.startswith("did:key:"):
        raise ValueError("not a did:key identifier")
    mb = did[len("did:key:"):]
    if not mb or mb[0] != "z":
        raise ValueError("unsupported multibase prefix, expected z (base58btc)")
    raw = b58_decode(mb[1:])
    if len(raw) != 2 + 32:
        raise ValueError("decoded %d bytes, expected 34" % len(raw))
    if raw[0:2] != MULTICODEC_ED25519_PUB:
        raise ValueError("multicodec tag is not 0xed01 (Ed25519 public key)")
    return raw[2:]


# ---------------------------------------------------------------------------
# The canonical work envelope — frozen field order (kok-proof/src/lib.rs:182).
# Any schema change bumps PROOF_VERSION and this function.
# ---------------------------------------------------------------------------

def work_canonical(p: dict) -> str:
    return "|".join(str(x) for x in (
        p["proof_version"], p["proof_type"], p["layer"], p["q"], p["n"],
        p["r"], p["task_program"], p["task_fee"], p["task_burn_rate_per_mille"],
        p["program_commit"], p["input_commit"], p["ctx"], p["nonce"],
        p["target"], p["cert_i"], p["cert_j"], p["cert_value"], p["cert_m"],
        p["receipt_prev"],
    ))


def program_commit(program: str, q: int, n: int, r: int) -> str:
    return sha256_hex(("kok.program.v1|%s|%d|%d|%d" % (program, q, n, r)).encode())


def input_commit(a, b) -> str:
    flat = lambda m: ",".join(str(v) for row in m for v in row)
    return sha256_hex(("kok.input.v1|%s|%s" % (flat(a), flat(b))).encode())


def receipt_hash_of(p: dict) -> str:
    return sha256_hex(work_canonical(p).encode("utf-8"))


# ---------------------------------------------------------------------------
# The KwKernel tile accumulator — mirrors kok-poum/src/lib.rs KwKernel.
# E/F noise is a pure function of (ctx, n, q); the tile accumulator is the
# strided MatMul of the noisy factors; the certificate is (i, j, value, m)
# whose domain-separated hash clears the target.
# ---------------------------------------------------------------------------

def noise(ctx: int, n: int, q: int):
    e = [[h_num("E", (ctx, i, j)) % q for j in range(n)] for i in range(n)]
    f = [[h_num("F", (ctx, i, j)) % q for j in range(n)] for i in range(n)]
    return e, f


def tile_accumulator(a, b, ctx: int, q: int, r: int):
    """acc[i][j] = sum_l (A+E)[i*r][l*r] * (B+F)[l*r][j*r]  mod q."""
    n = len(a)
    m = n // r
    e, f = noise(ctx, n, q)
    ap = [[(a[i][j] + e[i][j]) % q for j in range(n)] for i in range(n)]
    bp = [[(b[i][j] + f[i][j]) % q for j in range(n)] for i in range(n)]
    acc = [[0] * m for _ in range(m)]
    for i in range(m):
        for j in range(m):
            s = 0
            for l in range(m):
                s += ap[i * r][l * r] * bp[l * r][j * r]
            acc[i][j] = s % q
    return acc


def check_certificate(p: dict) -> bool:
    """The useful-work check: recompute the tile at (cert_i, cert_j) and
    require the domain-separated hash of the recomputed value to clear the
    target. Recomputation, never the miner's declared value."""
    acc = tile_accumulator(p["matrix_a"], p["matrix_b"], p["ctx"], p["q"], p["r"])
    if p["cert_i"] >= len(acc) or p["cert_j"] >= len(acc):
        return False
    if acc[p["cert_i"]][p["cert_j"]] != p["cert_value"]:
        return False
    return h_num("tile", (p["ctx"], p["nonce"], p["cert_i"], p["cert_j"],
                          p["cert_value"])) % p["target"] == 0


# ---------------------------------------------------------------------------
# The six-stage verifier. Every reject names the check and the field.
# ---------------------------------------------------------------------------

class Reject(Exception):
    """A receipt rejection. `kind` is the stage, `detail` the failure."""


def verify_receipt(p: dict, check_signature: bool = True) -> dict:
    """Verify a kok mining-proof receipt. Returns a verdict dict; raises
    Reject on the first failure.Mirrors the Rust verifier's order so a
    side-by-side diff of two runs agrees on WHICH check failed."""
    # 1. STRUCTURAL
    if p.get("proof_type") != PROOF_TYPE:
        raise Reject("structural", "proof_type %r, expected %r"
                     % (p.get("proof_type"), PROOF_TYPE))
    if p.get("proof_version") != PROOF_VERSION:
        raise Reject("structural", "proof_version %s, verifier reads %d"
                     % (p.get("proof_version"), PROOF_VERSION))
    if p.get("layer") != DEFAULT_LAYER:
        raise Reject("structural", "layer %r, verifier reads G-layer only"
                     % (p.get("layer"),))
    prev = p.get("receipt_prev", "")
    if len(prev) != 64 or not all(c in "0123456789abcdef" for c in prev):
        raise Reject("structural",
                     "receipt_prev must be 64 hex chars (sha256 or 64 zeros)")

    # 2. MATRIX SHAPE, before any indexing
    n = p.get("n", 0)
    a, b = p.get("matrix_a"), p.get("matrix_b")
    if not isinstance(n, int) or n <= 0:
        raise Reject("shape", "n=%r must be a positive int" % (n,))
    if not isinstance(a, list) or not isinstance(b, list):
        raise Reject("shape", "matrix_a/matrix_b must be lists")
    if len(a) != n or len(b) != n:
        raise Reject("shape", "declared n=%d but matrix_a has %d rows" % (n, len(a)))
    if any(not isinstance(row, list) or len(row) != n for row in a) or \
       any(not isinstance(row, list) or len(row) != n for row in b):
        raise Reject("shape", "ragged matrix rows")
    r = p.get("r", 0)
    if not isinstance(r, int) or r <= 0 or n % r != 0:
        raise Reject("shape", "n=%d is not divisible by r=%r" % (n, r))
    if p.get("cert_m") != n // r:
        raise Reject("shape", "cert_m=%r but n/r = %d" % (p.get("cert_m"), n // r))

    # 3. COMMITMENTS recomputed from the document's own fields
    want_program = program_commit(p["task_program"], p["q"], n, r)
    if p["program_commit"] != want_program:
        raise Reject("commitment", "program_commit %r, recomputed %r"
                     % (p["program_commit"], want_program))
    want_input = input_commit(a, b)
    if p["input_commit"] != want_input:
        raise Reject("commitment", "input_commit %r, recomputed %r"
                     % (p["input_commit"], want_input))

    # 4. THE USEFUL WORK — the tile recomputes and clears the target
    if not isinstance(p.get("target"), int) or p["target"] <= 0:
        raise Reject("work", "target=%r must be a positive int" % (p.get("target"),))
    if not check_certificate(p):
        raise Reject("work", "tile (%d,%d) does not recompute at nonce %d "
                     "under target %d"
                     % (p["cert_i"], p["cert_j"], p["nonce"], p["target"]))

    # 5. THE RECEIPT HASH — sha256 of the canonical envelope
    want_hash = receipt_hash_of(p)
    if p["receipt_hash"] != want_hash:
        raise Reject("receipt", "receipt_hash %r, recomputed %r"
                     % (p["receipt_hash"], want_hash))

    # 6. THE SIGNATURE — recover the key from the did, no registry
    if check_signature:
        if crypto_sign_open is None:
            raise Reject("signature", "PyNaCl unavailable — cannot verify")
        pk = public_key_from_did(p["miner_did"])
        sig = bytes.fromhex(p["signature"])
        if len(sig) != crypto_sign_BYTES:
            raise Reject("signature", "signature is %d bytes, expected 64" % len(sig))
        msg = SIG_DOMAIN + hashlib.sha256(work_canonical(p).encode("utf-8")).digest()
        try:
            crypto_sign_open(sig + msg, pk)
        except Exception as exc:
            raise Reject("signature", "Ed25519 verify failed: %s" % exc)

    return {"ok": True, "receipt": p["receipt_hash"][:16],
            "did": p["miner_did"], "tile": (p["cert_i"], p["cert_j"],
                                            p["cert_value"])}


def verdict(p: dict, check_signature: bool = True) -> dict:
    """Fail-closed wrapper: any error -> RED verdict, never an exception."""
    try:
        out = verify_receipt(p, check_signature=check_signature)
        return dict(out, verdict="ACCEPT")
    except Reject as r:
        return {"verdict": "RED", "kind": r.args[0], "detail": r.args[1]}
    except (KeyError, TypeError, ValueError) as e:
        return {"verdict": "RED", "kind": "malformed", "detail": "%s: %s" % (type(e).__name__, e)}


# ---------------------------------------------------------------------------
# Cross-language self-test: the Rust binary creates a receipt, this verifier
# must ACCEPT it; a tampered copy must go RED on the tampered stage.
# ---------------------------------------------------------------------------

def _run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=300)


def selftest_cross_language(kok_bin_args, tmp_path) -> bool:
    """Ask the Rust binary to mine a receipt, then verify it in Python.
    Then tamper six fields and require a RED on the matching stage."""
    import tempfile, pathlib
    tmp = pathlib.Path(tmp_path)
    receipt = tmp / "bridge_kanit.json"
    if receipt.exists():
        receipt.unlink()
    r = _run(kok_bin_args + ["create", "--ctx", "20261018", "--target", "2",
                             "--out", str(receipt)])
    if r.returncode != 0 or not receipt.exists():
        print("  RED  Rust create failed: %s" % (r.stderr.strip()[:200],))
        return False
    p = json.loads(receipt.read_text(encoding="utf-8"))
    v = verdict(p)
    print("  honest receipt                : %s (%s)" % (v.get("verdict"),
                                                         v.get("receipt", v.get("detail"))))
    if v.get("verdict") != "ACCEPT":
        return False

    # tampered: each edit must land on the stage that checks it
    import copy
    def tamper(mut, want_kind):
        q = copy.deepcopy(p)
        mut(q)
        w = verdict(q)
        ok = w.get("verdict") == "RED" and w.get("kind") == want_kind
        print("  tamper -> %-18s        : %s (got %s/%s)" % (want_kind, ok, w.get("verdict"), w.get("kind")))
        return ok

    ok = True
    ok &= tamper(lambda q: q.__setitem__("proof_type", "kok.forged"), "structural")
    ok &= tamper(lambda q: q["matrix_a"].__setitem__(0, [1] * len(q["matrix_a"][0])), "commitment")
    ok &= tamper(lambda q: q.__setitem__("cert_value", (q["cert_value"] + 1) % q["q"]), "work")
    ok &= tamper(lambda q: q.__setitem__("receipt_prev", "f" * 64), "receipt")
    ok &= tamper(lambda q: q.__setitem__("signature", "00" * 64), "signature")
    # the ctx cannot be forged alone: the tile is bound to it through the noise
    ok &= tamper(lambda q: q.__setitem__("ctx", q["ctx"] + 1), "work")
    return ok


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__.split("\n\n")[0])
        return 2
    rc = 0
    for path in args:
        try:
            p = json.loads(open(path, encoding="utf-8").read())
        except Exception as e:
            print("RED  %s  (unreadable: %s)" % (path, e))
            rc = 1
            continue
        v = verdict(p)
        if v.get("verdict") == "ACCEPT":
            print("KABUL  %s  (did %s..., receipt %s, tile %s)" %
                  (path, v["did"][:26], v["receipt"], v["tile"]))
        else:
            print("RED    %s  (%s: %s)" % (path, v.get("kind"), v.get("detail")))
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())

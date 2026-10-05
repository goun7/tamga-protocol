#!/usr/bin/env python3
"""brandstrike_tsa — the time axis, CODE-bonded to Tamga's hash-chain (RFC 3161).

README's "The time axis — BrandStrike" paragraph documents the pairing: Tamga
proves *what* an agent did and that it was not altered afterwards (JCS
hash-chain); BrandStrike anchors *when* by collecting evidence that carries
SHA-256 + ISO timestamp plus an optional RFC 3161 TSA token a third party can
verify independently. That paragraph was a DOC bond — this module is the CODE
bond. It:

  1. builds an RFC 3161 TimeStampReq whose messageImprint is the SHA-256 of a
     Tamga ledger tip (or of any evidence octets),
  2. parses an RFC 3161 TimeStampResp — PKIStatusInfo + CMS SignedData +
     TSTInfo (policy / messageImprint / serial / genTime / nonce),
  3. verifies the TSA token is bound to the SAME digest the hash-chain commits
     to, so a token minted over a decoy or a different chain is RED, and
     optionally verifies the CMS signature against the trusted TSA public key.

Chain math mirrors tamga_runner._verify_chain exactly (h = sha256(prev ‖
jcs(record-without-h-and-node_sig)), seq counted from 1) — a token minted over
tip N cannot be replayed against tip M. node_sig (node-cosign layer) is out of
scope here: its verification stays the runner's job; this module binds the time
axis to the *hash* axis.

Zero external dependencies beyond the declared set (PyNaCl + jsonschema): DER
is hand-rolled, EdDSA (RFC 8419) signature verification uses PyNaCl. RSA/ECDSA
TSA tokens need `cryptography`; when it is absent that path is reported
INDETERMINE rather than silently skipped (AT-082 discipline).

Kullanım:
    python3 tools/brandstrike_tsa.py selftest
    python3 tools/brandstrike_tsa.py query  <ledger.jsonl|->
    python3 tools/brandstrike_tsa.py verify <response.der> <ledger.jsonl|->
    python3 tools/brandstrike_tsa.py demo   [--tsa-key 64hex] [--out-response f]
"""
import datetime
import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tamga_canon import jcs  # RFC 8785 JCS — the ledger's canonicalization
# tamga_runner wraps tamga_canon.jcs with .decode(): the chain rule is
# h = sha256(prev_str ‖ jcs(rec).decode()); mirror it byte-for-byte.


def _jcs_str(obj) -> str:
    """The runner's jcs() returns *text* (it hashes prev+canon as a string);
    tamga_canon returns bytes — this is the exact parity point."""
    return jcs(obj).decode("utf-8")

# --- exit contract (tamga_attest_verify convention) ---------------------------------------
EXIT_GREEN, EXIT_RED, EXIT_IND = 0, 1, 2

# --- OIDs ----------------------------------------------------------------------------------
OID_SHA256 = "2.16.840.1.101.3.4.2.1"
OID_SHA384 = "2.16.840.1.101.3.4.2.2"
OID_SHA512 = "2.16.840.1.101.3.4.2.3"
OID_ID_SIGNED_DATA = "1.2.840.113549.1.7.2"          # CMS content type
OID_ID_CT_TST_INFO = "1.2.840.113549.1.9.16.1.4"     # encapsulated TSTInfo
OID_EDDSA = "1.3.101.112"                            # RFC 8419 (Ed25519)
OID_ED448 = "1.3.101.113"
OID_RSA_ENCRYPTION = "1.2.840.113549.1.1.1"
OID_ECDSA_SHA256 = "1.2.840.10045.4.3.2"

# Demo TSA policy — a private-enterprise arc, NOT a real TSA's policy. RFC 3161
# leaves the policy OID to each TSA; callers pin their own via --policy.
OID_DEMO_POLICY = "1.3.6.1.4.1.65535.1.1"

_HASH_ALGS = {OID_SHA256: ("sha256", 32), OID_SHA384: ("sha384", 48), OID_SHA512: ("sha512", 64)}

_STATUS_LABELS = {
    0: "granted", 1: "grantedWithMods", 2: "rejection", 3: "waiting",
    4: "revocationWarning", 5: "revocationNotification",
}
# RFC 3161 §2.4.2 / PKIStatus: a usable token only comes with these statuses.
_USABLE_STATUS = (0, 1)

DEMO_GEN_TIME = "20261005120530Z"   # fixed → deterministic round-trip (no clock in tests)


# --- minimal DER codec (stdlib; DER requires definite, minimal lengths) --------------------
def _enc_len(n: int) -> bytes:
    if n < 0x80:
        return bytes([n])
    b = n.to_bytes((n.bit_length() + 7) // 8, "big")
    return bytes([0x80 | len(b)]) + b


def _tlv(tag: int, content: bytes) -> bytes:
    return bytes([tag]) + _enc_len(len(content)) + content


def _read_tlv(der: bytes, off: int = 0):
    """Decode exactly one TLV → (tag, content, next_off). Fail-loud on truncation
    or a non-minimal DER length (a forged length field must never be silently
    re-interpreted)."""
    if off >= len(der):
        raise ValueError("truncated TLV: missing tag")
    tag = der[off]
    i = off + 1
    if i >= len(der):
        raise ValueError("truncated TLV: missing length")
    b = der[i]
    i += 1
    if b < 0x80:
        ln = b
    else:
        nb = b & 0x7F
        if nb == 0:
            raise ValueError("indefinite length is not DER")
        if nb > 8:
            raise ValueError("length field too large")
        if i + nb > len(der):
            raise ValueError("truncated TLV: length octets cut")
        ln = int.from_bytes(der[i:i + nb], "big")
        i += nb
        if ln < 0x80:
            raise ValueError("non-minimal length encoding (DER violation)")
    if i + ln > len(der):
        raise ValueError("truncated TLV: content cut")
    return tag, der[i:i + ln], i + ln


def _iter_tlv(content: bytes):
    """Yield (tag, value) for each TLV inside a constructed value."""
    off = 0
    while off < len(content):
        tag, val, off = _read_tlv(content, off)
        yield tag, val


def _enc_base128(n: int) -> bytes:
    if n == 0:
        return b"\x00"
    chunks = []
    while n > 0:
        chunks.append(n & 0x7F)
        n >>= 7
    chunks.reverse()
    return bytes([c | 0x80 for c in chunks[:-1]] + [chunks[-1]])


def _enc_oid(s: str) -> bytes:
    parts = [int(x) for x in s.split(".")]
    if len(parts) < 2:
        raise ValueError(f"malformed OID: {s!r}")
    body = [40 * parts[0] + parts[1]]
    for p in parts[2:]:
        body.extend(_enc_base128(p))
    return bytes(body)


def _dec_oid(body: bytes) -> str:
    if not body:
        raise ValueError("empty OID")
    out = [str(body[0] // 40), str(body[0] % 40)]
    val, pending = 0, False
    for b in body[1:]:
        val = (val << 7) | (b & 0x7F)
        pending = True
        if not (b & 0x80):
            out.append(str(val))
            val, pending = 0, False
    if pending:
        raise ValueError("truncated OID (dangling continuation bit)")
    return ".".join(out)


def _enc_int(n: int) -> bytes:
    if n == 0:
        return b"\x00"
    length = (n.bit_length() // 8) + 1
    b = n.to_bytes(length, "big", signed=True)
    while len(b) > 1 and ((b[0] == 0xFF and b[1] & 0x80) or (b[0] == 0x00 and not (b[1] & 0x80))):
        b = b[1:]
    return b


def _dec_int(b: bytes) -> int:
    if not b:
        raise ValueError("empty INTEGER")
    return int.from_bytes(b, "big", signed=True)


def _dec_bitstring(b: bytes) -> list:
    """Named bits per RFC 3161 failInfo (bit 0 = first named bit)."""
    if not b:
        raise ValueError("empty BIT STRING")
    unused = b[0]
    if unused > 7:
        raise ValueError("invalid unused-bit count")
    bits = []
    for byte in b[1:]:
        for i in range(7, -1, -1):
            bits.append((byte >> i) & 1)
    return bits[:-unused] if (bits and unused) else bits


_GEN_TIME_RE = re.compile(
    r"^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(?:[.,](\d+))?(Z|[+-]\d{4})?$")


def dec_gen_time(s) -> datetime.datetime:
    """GeneralizedTime → aware datetime. Accepts the DER canonical form
    (YYYYMMDDHHMMSSZ) and relaxed forms real TSAs emit (fractional seconds,
    explicit offsets). Rejects impossible dates rather than wrapping around."""
    s = s.decode("ascii") if isinstance(s, (bytes, bytearray)) else str(s)
    m = _GEN_TIME_RE.match(s.strip())
    if not m:
        raise ValueError(f"malformed GeneralizedTime: {s!r}")
    y, mo, d, hh, mm, ss, frac, tz = m.groups()
    micro = int((frac + "000000")[:6]) if frac else 0
    dt = datetime.datetime(int(y), int(mo), int(d), int(hh), int(mm), int(ss), micro)
    if tz is None or tz == "Z":
        dt = dt.replace(tzinfo=datetime.timezone.utc)
    else:
        sign = 1 if tz[0] == "+" else -1
        off = datetime.timedelta(hours=int(tz[1:3]), minutes=int(tz[3:5])) * sign
        dt = dt.replace(tzinfo=datetime.timezone(off))
    return dt


def gen_time_iso(dt: datetime.datetime) -> str:
    """ISO-8601 rendering for a receipt's timestamp field."""
    return dt.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# --- RFC 3161 builders ----------------------------------------------------------------------
def _message_imprint(digest: bytes, oid: str = OID_SHA256) -> bytes:
    if oid not in _HASH_ALGS:
        raise ValueError(f"unsupported hash algorithm OID: {oid}")
    if len(digest) != _HASH_ALGS[oid][1]:
        raise ValueError(f"digest length {len(digest)} does not match {oid}")
    alg = _tlv(0x30, _tlv(0x06, _enc_oid(oid)))          # AlgorithmIdentifier (no NULL params)
    return _tlv(0x30, alg + _tlv(0x04, digest))


def build_timestamp_req(digest: bytes, *, hash_alg: str = OID_SHA256,
                        nonce: int, policy: str | None = None,
                        cert_req: bool = False) -> bytes:
    """RFC 3161 §2.4.1 TimeStampReq. The nonce is the caller's replay defense —
    a response that does not echo it back is RED (see verify_response)."""
    body = _tlv(0x02, _enc_int(1))                        # version (1)
    body += _message_imprint(digest, hash_alg)
    if policy:
        body += _tlv(0x06, _enc_oid(policy))              # reqPolicy (optional)
    body += _tlv(0x02, _enc_int(nonce))                   # nonce (we always send one)
    body += _tlv(0x01, b"\xff" if cert_req else b"\x00")  # certReq BOOLEAN
    return _tlv(0x30, body)


def _tst_info(imprint: bytes, serial: int, gen_time: str, nonce: int,
              policy: str = OID_DEMO_POLICY, *, seconds: int = 1) -> bytes:
    body = _tlv(0x02, _enc_int(1))                        # version
    body += _tlv(0x06, _enc_oid(policy))                  # policy
    body += imprint                                       # messageImprint
    body += _tlv(0x02, _enc_int(serial))                  # serialNumber
    body += _tlv(0x18, gen_time.encode("ascii"))          # genTime GeneralizedTime
    if seconds is not None:                               # accuracy (optional)
        body += _tlv(0x30, _tlv(0x02, _enc_int(seconds)))
    body += _tlv(0x01, b"\x00")                           # ordering BOOLEAN FALSE
    body += _tlv(0x02, _enc_int(nonce))                   # nonce
    return _tlv(0x30, body)


def build_signed_data(tst_info_der: bytes, signature: bytes, sig_alg: str = OID_EDDSA) -> bytes:
    """CMS SignedData (RFC 5652) carrying TSTInfo with one signerInfo. For EdDSA
    (RFC 8419) the signature covers the eContent octets directly — PyNaCl does
    the hashing, so the digestAlgorithm set is empty."""
    econtent = _tlv(0x30, _tlv(0x06, _enc_oid(OID_ID_CT_TST_INFO))
                    + _tlv(0xA0, _tlv(0x04, tst_info_der)))
    digest_algs = _tlv(0x31, b"")                         # SET OF (empty for EdDSA)
    sid = _tlv(0x80, b"\x01\x02\x03\x04\x05")             # subjectKeyIdentifier [0] (demo TSA)
    signer = _tlv(0x30, _tlv(0x02, _enc_int(3)) + sid
                  + _tlv(0x06, _enc_oid(sig_alg))
                  + _tlv(0x04, signature))
    sd = digest_algs + econtent + _tlv(0x31, signer)
    return _tlv(0x30, sd)


def build_timestamp_resp(imprint: bytes, *, serial: int, gen_time: str, nonce: int,
                         signature: bytes, policy: str = OID_DEMO_POLICY,
                         sig_alg: str = OID_EDDSA, status: int = 0,
                         status_string: str | None = None,
                         fail_info: list[str] | None = None) -> bytes:
    """RFC 3161 §2.4.2 TimeStampResp. Only used on the demo path (a locally
    generated test TSA key) — a real TSA's response is never built here, only
    verified."""
    if status not in _STATUS_LABELS:
        raise ValueError(f"unknown PKIStatus: {status}")
    st = _tlv(0x02, _enc_int(status))
    if status_string is not None:
        st += _tlv(0x30, _tlv(0x0C, status_string.encode("utf-8")))
    if fail_info is not None:                    # BIT STRING, bit 0 = first named bit
        names = ["badAlg", "badRequest", "badDataFormat", "timeNotAvailable",
                 "unacceptedPolicy", "unacceptedExtension", "badCert", "badTime",
                 "badCertId"]
        bits = [1 if n in fail_info else 0 for n in names]
        unused = (8 - (len(bits) % 8)) % 8
        bits += [0] * unused
        raw = bytes([unused] + [int("".join(map(str, bits[i:i + 8])), 2)
                                for i in range(0, len(bits), 8)])
        st += _tlv(0x03, raw)
    body = _tlv(0x30, st)
    if status in _USABLE_STATUS:
        tst = build_signed_data(_tst_info(imprint, serial, gen_time, nonce, policy),
                                signature, sig_alg)
        body += _tlv(0x30, _tlv(0x06, _enc_oid(OID_ID_SIGNED_DATA)) + _tlv(0xA0, tst))
    return _tlv(0x30, body)


# --- RFC 3161 parser ------------------------------------------------------------------------
def parse_timestamp_req(der: bytes) -> dict:
    """RFC 3161 §2.4.1 TimeStampReq → version, imprint, policy, nonce, certReq.
    Fields are positional in the spec; unknown trailing elements are rejected so
    a request is never silently re-interpreted."""
    tag, content, _ = _read_tlv(der)
    if tag != 0x30:
        raise ValueError("TimeStampReq: outer tag is not SEQUENCE")
    parts = list(_iter_tlv(content))
    if len(parts) < 2:
        raise ValueError("TimeStampReq: missing version or messageImprint")
    if parts[0][0] != 0x02 or _dec_int(parts[0][1]) != 1:
        raise ValueError("TimeStampReq: version must be INTEGER 1")
    out = {"version": 1, "imprint": parse_message_imprint(parts[1][1])}
    for t, v in parts[2:]:                    # optional, in spec order
        if t == 0x06 and "policy" not in out:
            out["policy"] = _dec_oid(v)
        elif t == 0x02 and "nonce" not in out:
            out["nonce"] = _dec_int(v)
        elif t == 0x01 and "cert_req" not in out:
            out["cert_req"] = (v != b"\x00")
        else:
            raise ValueError(f"TimeStampReq: unexpected field (tag {t:#x})")
    return out


def _parse_algorithm_identifier(content: bytes) -> str:
    parts = list(_iter_tlv(content))
    if not parts or parts[0][0] != 0x06:
        raise ValueError("AlgorithmIdentifier: missing algorithm OID")
    oid = _dec_oid(parts[0][1])
    for tag, val in parts[1:]:                        # tolerate optional NULL params
        if not (tag == 0x05 and val == b""):
            raise ValueError(f"AlgorithmIdentifier: unexpected params (tag {tag:#x})")
    return oid


def parse_message_imprint(content: bytes) -> dict:
    parts = list(_iter_tlv(content))
    if len(parts) != 2 or parts[0][0] != 0x30 or parts[1][0] != 0x04:
        raise ValueError("MessageImprint: expected SEQUENCE{AlgorithmIdentifier, OCTET STRING}")
    oid = _parse_algorithm_identifier(parts[0][1])
    if oid not in _HASH_ALGS:
        raise ValueError(f"MessageImprint: unsupported hash algorithm {oid}")
    digest = parts[1][1]
    want = _HASH_ALGS[oid][1]
    if len(digest) != want:
        raise ValueError(f"MessageImprint: {oid} digest must be {want} bytes, got {len(digest)}")
    return {"hash_alg": _HASH_ALGS[oid][0], "hash_oid": oid, "imprint": digest.hex()}


def parse_tst_info(der: bytes) -> dict:
    """TSTInfo (RFC 3161 §2.4.2 / §5). The five mandatory fields must all be
    present and well-formed; unknown optional fields are tolerated."""
    tag, content, _ = _read_tlv(der)
    if tag != 0x30:
        raise ValueError("TSTInfo: outer tag is not SEQUENCE")
    out, seen = {}, set()
    for t, v in _iter_tlv(content):
        if t == 0x02 and "version" not in seen:
            out["version"] = _dec_int(v); seen.add("version")
        elif t == 0x06 and "policy" not in seen:
            out["policy"] = _dec_oid(v); seen.add("policy")
        elif t == 0x30 and "imprint" not in seen:
            out["imprint"] = parse_message_imprint(v); seen.add("imprint")
        elif t == 0x02 and "serial" not in seen:
            out["serial"] = _dec_int(v); seen.add("serial")
        elif t == 0x18 and "gen_time" not in seen:
            dt = dec_gen_time(v.decode("ascii"))
            out["gen_time"] = gen_time_iso(dt)
            out["gen_time_epoch"] = int(dt.timestamp())
            seen.add("gen_time")
        elif t == 0x30 and "accuracy" not in seen:            # accuracy SEQUENCE
            secs = None
            for at, av in _iter_tlv(v):
                if at == 0x02 and secs is None:
                    secs = _dec_int(av)
            out["accuracy_seconds"] = secs
            seen.add("accuracy")
        elif t == 0x01 and "ordering" not in seen:
            out["ordering"] = (v != b"\x00"); seen.add("ordering")
        elif t == 0x02 and "nonce" not in seen:
            out["nonce"] = _dec_int(v); seen.add("nonce")
        elif t == 0xA0 and "tsa" not in seen:                 # tsa [0] GeneralName
            out["tsa_raw"] = v.hex(); seen.add("tsa")
        elif t == 0xA1:                                        # extensions [1] IMPLICIT
            out["extensions_present"] = True
        else:
            raise ValueError(f"TSTInfo: unexpected field (tag {t:#x})")
    missing = [k for k in ("version", "policy", "imprint", "serial", "gen_time") if k not in seen]
    if missing:
        raise ValueError(f"TSTInfo: missing mandatory field(s): {missing}")
    if out["version"] != 1:
        raise ValueError(f"TSTInfo: unsupported version {out['version']}")
    return out


def parse_signed_data(der: bytes) -> dict:
    """CMS SignedData → encapsulated TSTInfo + signer material. Certificates and
    CRLs are skipped on purpose: this validator takes the trusted TSA key
    out-of-band (RFC 3161 §4 trust model), so a self-asserted cert inside the
    token adds no security and is not parsed."""
    tag, content, _ = _read_tlv(der)
    if tag != 0x30:
        raise ValueError("SignedData: outer tag is not SEQUENCE")
    out, econtent, signer = {}, None, None
    for t, v in _iter_tlv(content):
        if "version" not in out and t == 0x02:
            out["version"] = _dec_int(v)
        elif t == 0x31 and "digest_algs" not in out:
            out["digest_algs"] = [_dec_oid(x) for _, x in _iter_tlv(v)] or [None]
        elif t == 0x30 and econtent is None:
            et = list(_iter_tlv(v))
            if not et or et[0][0] != 0x06:
                raise ValueError("EncapsulatedContentInfo: missing eContentType")
            out["e_content_type"] = _dec_oid(et[0][1])
            if out["e_content_type"] != OID_ID_CT_TST_INFO:
                raise ValueError("SignedData: eContentType is not TSTInfo "
                                 f"({out['e_content_type']})")
            ev = None
            for ct, cv in et[1:]:
                if ct == 0xA0:
                    it, iv, _ = _read_tlv(cv)               # [0] EXPLICIT OCTET STRING
                    if it != 0x04:
                        raise ValueError("eContent is not an OCTET STRING")
                    ev = iv
            if ev is None:
                raise ValueError("SignedData: detached eContent is not supported")
            econtent = ev
        elif t in (0xA0, 0xA1):                               # certificates / crls
            continue
        elif t == 0x31 and signer is None:
            signers = list(_iter_tlv(v))
            if len(signers) != 1:
                raise ValueError(f"SignedData: expected one signerInfo, got {len(signers)}")
            st, sv = signers[0]
            if st != 0x30:
                raise ValueError("SignerInfo: not a SEQUENCE")
            si, sig_alg, signature = {}, None, None
            for ft, fv in _iter_tlv(sv):
                if "version" not in si and ft == 0x02:
                    si["version"] = _dec_int(fv)
                elif ft in (0x30, 0x80, 0x81) and "sid" not in si:
                    si["sid"] = fv.hex()
                elif ft == 0x02 and "digest_alg" not in si:
                    si["digest_alg"] = _dec_int(fv)
                elif ft == 0xA0 and "signed_attrs" not in si:
                    si["signed_attrs"] = fv.hex()
                elif ft == 0x06 and sig_alg is None:
                    sig_alg = _dec_oid(fv)
                elif ft == 0x04 and signature is None:
                    signature = fv
                elif ft == 0xA1:
                    si["unsigned_attrs"] = True
                else:
                    raise ValueError(f"SignerInfo: unexpected field (tag {ft:#x})")
            if sig_alg is None or signature is None:
                raise ValueError("SignerInfo: missing signatureAlgorithm or signature")
            if si.get("signed_attrs"):
                raise ValueError("signedAttrs signing is not implemented (RFC 8419 "
                                 "direct-signing only) — token unverifiable here")
            signer = {"sig_alg": sig_alg, "signature": signature.hex(), **si}
    if econtent is None or signer is None:
        raise ValueError("SignedData: missing encapContentInfo or signerInfos")
    out["e_content"] = econtent.hex()
    out["signer"] = signer
    out["tst_info"] = parse_tst_info(econtent)
    return out


def parse_timestamp_resp(der: bytes) -> dict:
    """RFC 3161 §2.4.2 TimeStampResp → status, optional failInfo, optional token."""
    tag, content, _ = _read_tlv(der)
    if tag != 0x30:
        raise ValueError("TimeStampResp: outer tag is not SEQUENCE")
    parts = list(_iter_tlv(content))
    if not parts:
        raise ValueError("TimeStampResp: missing PKIStatusInfo")
    st_tag, st_val = parts[0]
    if st_tag != 0x30:
        raise ValueError("PKIStatusInfo: not a SEQUENCE")
    sp = list(_iter_tlv(st_val))
    if not sp or sp[0][0] != 0x02:
        raise ValueError("PKIStatusInfo: missing status INTEGER")
    out = {"status": _dec_int(sp[0][1])}
    if out["status"] not in _STATUS_LABELS:
        raise ValueError(f"PKIStatusInfo: unknown status {out['status']}")
    out["status_label"] = _STATUS_LABELS[out["status"]]
    for t, v in sp[1:]:
        if t == 0x30 and "status_string" not in out:        # SEQUENCE OF UTF8String
            out["status_string"] = [x.decode("utf-8", "replace")
                                    for tt, x in _iter_tlv(v) if tt in (0x0C, 0x1E)]
        elif t == 0x03 and "fail_info" not in out:           # BIT STRING
            bits = _dec_bitstring(v)
            names = ["badAlg", "badRequest", "badDataFormat", "timeNotAvailable",
                     "unacceptedPolicy", "unacceptedExtension", "badCert", "badTime",
                     "badCertId"][: len(bits)]
            out["fail_info"] = [n for n, b in zip(names, bits) if b]
    if len(parts) > 1:
        ct, cv = parts[1]
        if ct != 0x30:
            raise ValueError("ContentInfo: not a SEQUENCE")
        ci = list(_iter_tlv(cv))
        if len(ci) < 2 or ci[0][0] != 0x06:
            raise ValueError("ContentInfo: missing contentType OID")
        ctype = _dec_oid(ci[0][1])
        if ctype != OID_ID_SIGNED_DATA:
            raise ValueError(f"ContentInfo: contentType is not signedData ({ctype})")
        inner = None
        for it, iv in ci[1:]:
            if it == 0xA0:
                inner = iv
        if inner is None:
            raise ValueError("ContentInfo: missing [0] content")
        out["signed_data"] = parse_signed_data(inner)
        out["tst_info"] = out["signed_data"]["tst_info"]
    return out


# --- Tamga hash-chain bond -------------------------------------------------------------------
def chain_tip(records) -> tuple:
    """Mirror of tamga_runner._verify_chain's hash rule (seq from 1, prev from
    64×'0', h = sha256(prev ‖ jcs(record without h/node_sig))). Returns
    (tip_hex, 'ok') or (None, 'broken@<n>'). The node_sig layer is deliberately
    NOT checked here — that is the runner's node-cosign axis (L1); this module
    binds the time axis to the hash axis only."""
    prev_h, n = "0" * 64, 0
    try:
        for rec in records:
            n += 1
            no_h = {k: v for k, v in rec.items() if k != "h" and k != "node_sig"}
            exp = hashlib.sha256((rec.get("prev", "") + _jcs_str(no_h)).encode("utf-8")).hexdigest()
            if rec.get("prev") != prev_h or rec.get("h") != exp or rec.get("seq") != n:
                return None, f"broken@{n}"
            prev_h = rec["h"]
    except Exception:
        return None, f"broken@{n}"
    if n == 0:
        return None, "empty"
    return prev_h, "ok"


def tip_imprint(records) -> tuple:
    """The SHA-256 a TSA must stamp to cover a whole ledger: sha256(tip_bytes).
    Double hashing keeps the TSA's input opaque to the ledger's internal
    serialization while still binding it to the exact chain tip.
    → (digest_bytes, 'ok', tip_hex) or (None, reason, None)."""
    tip, why = chain_tip(records)
    if tip is None:
        return None, why, None
    return hashlib.sha256(bytes.fromhex(tip)).digest(), "ok", tip


def evidence_imprint(raw: bytes) -> bytes:
    """SHA-256 over arbitrary evidence octets (BrandStrike's per-evidence hash)."""
    return hashlib.sha256(raw).digest()


def load_ledger(path) -> list:
    """Stream a ledger.jsonl the way _ledger_lines does: an unparseable line is a
    sentinel break, never silently dropped (a broken chain is a RED, not noise)."""
    recs = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                recs.append(json.loads(line))
            except Exception:
                recs.append({})          # sentinel → chain check flags it broken
    return recs


def _as_verify_key(tsa_key):
    """Accept hex/bytes VerifyKey material or a VerifyKey object."""
    from nacl.signing import VerifyKey
    if isinstance(tsa_key, VerifyKey):
        return tsa_key
    if isinstance(tsa_key, str):
        return VerifyKey(bytes.fromhex(tsa_key))
    if isinstance(tsa_key, (bytes, bytearray)):
        return VerifyKey(bytes(tsa_key))
    raise TypeError("tsa_key must be hex/bytes VerifyKey material")


def verify_signature(signed_data: dict, tsa_key) -> tuple:
    """Verify the CMS signerInfo signature over the eContent (TSTInfo).

    EdDSA (RFC 8419) is verified with PyNaCl — a declared dependency. RSA and
    ECDSA need the optional `cryptography` package: if it is absent the verdict
    is INDETERMINE, never a silent PASS (AT-082 discipline).
    → (state, reason): state ∈ {'ok', 'red', 'indeterminate'}."""
    sig_alg = signed_data["signer"]["sig_alg"]
    signature = bytes.fromhex(signed_data["signer"]["signature"])
    content = bytes.fromhex(signed_data["e_content"])
    if sig_alg in (OID_EDDSA, OID_ED448):
        from nacl.exceptions import BadSignatureError
        try:
            _as_verify_key(tsa_key).verify(content, signature)
        except BadSignatureError:
            return "red", "signature_invalid: EdDSA verification failed"
        except Exception as exc:
            return "red", f"signature_invalid: {exc}"
        return "ok", "eddsa-verified (PyNaCl)"
    if sig_alg in (OID_RSA_ENCRYPTION, OID_ECDSA_SHA256):
        try:
            from cryptography.hazmat.primitives.asymmetric import ec, padding, rsa
            from cryptography.hazmat.primitives import hashes
            from cryptography.hazmat.primitives.asymmetric.utils import (
                decode_dss_signature, encode_dss_signature)
        except ImportError:
            return ("indeterminate",
                    f"signature_alg {sig_alg} needs the optional 'cryptography' "
                    "package — not verified (INDETERMINE, not a PASS)")
        pub = _as_verify_key(tsa_key)
        try:
            if sig_alg == OID_ECDSA_SHA256:
                r, s = decode_dss_signature(signature)
                pub.verify(encode_dss_signature(r, s), content, ec.ECDSA(hashes.SHA256()))
            else:
                pub.verify(signature, content, padding.PKCS1v15(), hashes.SHA256())
        except Exception as exc:
            return "red", f"signature_invalid: {exc}"
        return "ok", "rsa/ecdsa-verified (cryptography)"
    return "indeterminate", f"signature_alg {sig_alg} is not implemented"


# --- the bond -------------------------------------------------------------------------------
def verify_token(resp_der: bytes, *, expected_imprint: bytes,
                 nonce: int | None = None, tsa_key=None,
                 policy: str | None = None) -> tuple:
    """Verify an RFC 3161 response is bound to a specific digest.

    The order of the gates matters: the imprint check comes BEFORE the signature
    check, so a token whose content does not cover our digest is RED regardless
    of whether its signature is valid — a TSA cannot be tricked into vouching for
    a digest it never stamped, and a stolen valid token cannot be replayed
    against a different chain.

    → (verdict, reason, detail); verdict ∈ {'ok', 'red', 'indeterminate'}."""
    try:
        resp = parse_timestamp_resp(resp_der)
    except Exception as exc:
        return "red", f"response_malformed: {exc}", {}
    detail = {"status": resp.get("status"), "status_label": resp.get("status_label")}
    if resp["status"] not in _USABLE_STATUS:
        detail["fail_info"] = resp.get("fail_info")
        detail["status_string"] = resp.get("status_string")
        return "red", f"tsa_status_{resp['status_label']}", detail
    if "tst_info" not in resp:
        return "red", "tsa_granted_without_token", detail
    tst = resp["tst_info"]
    detail["tst"] = {k: tst.get(k) for k in
                     ("policy", "serial", "gen_time", "gen_time_epoch", "nonce",
                      "accuracy_seconds")}
    if policy is not None and tst.get("policy") != policy:
        detail["tst"]["policy"] = tst.get("policy")
        return "red", f"policy_mismatch: expected {policy}, got {tst.get('policy')}", detail
    got = tst["imprint"]["imprint"]
    detail["imprint"] = got
    if got != expected_imprint.hex():
        return "red", "imprint_mismatch: token does not cover this digest", detail
    if nonce is not None and tst.get("nonce") != nonce:
        return "red", f"nonce_mismatch: expected {nonce}, got {tst.get('nonce')}", detail
    if tsa_key is not None:
        state, why = verify_signature(resp["signed_data"], tsa_key)
        detail["signature"] = why
        if state == "red":
            return "red", why, detail
        if state == "indeterminate":
            return "indeterminate", why, detail
    else:
        detail["signature"] = "not-checked (no TSA key supplied)"
    detail["hash_alg"] = tst["imprint"]["hash_alg"]
    return "ok", "ok", detail


def bind_chain(resp_der: bytes, records, *, nonce: int | None = None,
               tsa_key=None, policy: str | None = None) -> tuple:
    """The CODE bond: a TSA token + a Tamga ledger → third-party-anchored time.

    1. the ledger must be a valid hash-chain (runner's own rule), and
    2. the token's messageImprint must be sha256 over the chain's tip, so the
       TSA is vouching for exactly the ledger state the caller holds.
    A token minted over a decoy digest, or a ledger whose tip moved after
    stamping, is RED. → (verdict, reason, detail)."""
    digest, why, tip = tip_imprint(records)
    if digest is None:
        return "red", f"chain_not_verifiable: {why}", {"chain": why}
    verdict, reason, detail = verify_token(resp_der, expected_imprint=digest,
                                           nonce=nonce, tsa_key=tsa_key, policy=policy)
    detail["chain_tip"] = tip
    return verdict, reason, detail


# --- CLI -------------------------------------------------------------------------------------
def _print(obj) -> None:
    print(json.dumps(obj, ensure_ascii=False, indent=2))


def _load_der(path: str) -> bytes:
    """A .der may be raw bytes or hex text; both are accepted (tests emit hex)."""
    raw = Path(path).read_bytes()
    text = raw.strip()
    if text and all(c in b"0123456789abcdefABCDEF \n\r\t" for c in text):
        return bytes.fromhex(text.decode("ascii"))
    return raw


def _demo_ledger():
    """A two-record ledger whose hashes are real (chain math runs, not faked)."""
    base = {"op": "charge", "note": "brandstrike-demo", "amount": "0.01", "ts": "2026-10-05T00:00:00Z"}
    recs, prev = [], "0" * 64
    for i, note in enumerate(("ilk", "iki"), start=1):
        rec = dict(base, note=f"{note}-kanit")
        rec["seq"] = i
        rec["prev"] = prev
        no_h = {k: v for k, v in rec.items() if k != "h"}
        rec["h"] = hashlib.sha256((prev + _jcs_str(no_h)).encode("utf-8")).hexdigest()
        recs.append(rec)
        prev = rec["h"]
    return recs


def cmd_query(argv) -> int:
    if not argv:
        print("kullanim: query <ledger.jsonl|->", file=sys.stderr)
        return EXIT_IND
    recs = (load_ledger("/dev/stdin") if argv[0] == "-"
            else load_ledger(argv[0]))
    digest, why, tip = tip_imprint(recs)
    if digest is None:
        _print({"ok": False, "reason": f"chain_not_verifiable: {why}"})
        return EXIT_RED
    nonce = int.from_bytes(digest, "big") % (1 << 63)
    req = build_timestamp_req(digest, nonce=nonce)
    _print({"ok": True, "tip": tip, "imprint": digest.hex(), "nonce": nonce,
            "query_der_hex": req.hex(), "query_der_bytes": len(req)})
    return EXIT_GREEN


def cmd_verify(argv) -> int:
    if len(argv) < 2:
        print("kullanim: verify <response.der> <ledger.jsonl|-> [--tsa-key hex] [--nonce N]",
              file=sys.stderr)
        return EXIT_IND
    tsa_key, policy, nonce = None, None, None
    rest = argv[2:]
    while rest:
        if rest[0] == "--tsa-key" and len(rest) > 1:
            tsa_key = rest[1]; rest = rest[2:]
        elif rest[0] == "--policy" and len(rest) > 1:
            policy = rest[1]; rest = rest[2:]
        elif rest[0] == "--nonce" and len(rest) > 1:
            nonce = int(rest[1]); rest = rest[2:]
        else:
            print(f"bilinmeyen argüman: {rest[0]}", file=sys.stderr)
            return EXIT_IND
    try:
        resp_der = _load_der(argv[0])
    except OSError as exc:
        _print({"ok": False, "reason": f"load: {exc}"})
        return EXIT_RED
    recs = (load_ledger("/dev/stdin") if argv[1] == "-" else load_ledger(argv[1]))
    verdict, reason, detail = bind_chain(resp_der, recs, nonce=nonce,
                                         tsa_key=tsa_key, policy=policy)
    _print({"ok": verdict == "ok", "verdict": verdict, "reason": reason, "detail": detail})
    return {"ok": EXIT_GREEN, "red": EXIT_RED, "indeterminate": EXIT_IND}[verdict]


def cmd_demo(argv) -> int:
    """Round-trip proof with a locally generated test TSA key (no network, no
    real TSA). Builds a query over a ledger's tip, mints a valid token, then
    verifies the bond — and that a tampered imprint is RED."""
    from nacl.signing import SigningKey
    tsa_hex, out_path, bad, ledger = None, None, False, None
    rest = list(argv)
    while rest:
        if rest[0] == "--tsa-key" and len(rest) > 1:
            tsa_hex = rest[1]; rest = rest[2:]
        elif rest[0] == "--out-response" and len(rest) > 1:
            out_path = rest[1]; rest = rest[2:]
        elif rest[0] == "--ledger" and len(rest) > 1:
            ledger = rest[1]; rest = rest[2:]
        elif rest[0] == "--bad-imprint":
            bad = True; rest = rest[1:]
        else:
            print(f"bilinmeyen argüman: {rest[0]}", file=sys.stderr)
            return EXIT_IND
    sk = SigningKey(bytes.fromhex(tsa_hex)) if tsa_hex else SigningKey.generate()
    recs = load_ledger(ledger) if ledger else _demo_ledger()
    digest, why, tip = tip_imprint(recs)
    if digest is None:
        _print({"ok": False, "reason": f"chain_not_verifiable: {why}"})
        return EXIT_RED
    nonce = 0x1122334455667788
    stamp_over = evidence_imprint(b"decoy-evidence") if bad else digest
    tst = _tst_info(_message_imprint(stamp_over), 7, DEMO_GEN_TIME, nonce)
    resp = build_timestamp_resp(_message_imprint(stamp_over), serial=7,
                                gen_time=DEMO_GEN_TIME, nonce=nonce,
                                signature=sk.sign(tst).signature)
    if out_path:
        Path(out_path).write_text(resp.hex() + "\n", encoding="ascii")
    verdict, reason, detail = bind_chain(resp, recs, nonce=nonce, tsa_key=sk.verify_key.encode().hex())
    _print({"ok": verdict == ("ok" if not bad else "red"),
            "verdict": verdict, "reason": reason,
            "tsa_key": sk.verify_key.encode().hex(), "chain_tip": tip,
            "detail": detail,
            "note": "demo TSA key generated locally — not a real timestamp authority"})
    if not bad and verdict != "ok":
        return EXIT_RED
    if bad and verdict != "red":
        return EXIT_RED
    return EXIT_GREEN


def _selftest() -> tuple:
    """In-process assertions (the bash harness and pytest both build on these)."""
    from nacl.signing import SigningKey
    checks = []

    def chk(name, cond, extra=""):
        checks.append((name, bool(cond), extra))

    recs = _demo_ledger()
    digest, why, tip = tip_imprint(recs)
    chk("chain-tip-derivable", digest is not None, why)
    chk("tip-is-64-hex", tip is not None and len(tip) == 64 and int(tip, 16) >= 0)

    # K: ledger math parity with tamga_runner (same rule, independent module)
    import tamga_runner as tr
    tip_runner, runner_why = tr._verify_chain([dict(r) for r in recs])
    chk("chain-tip-parity-with-runner", tip == tip_runner, f"{why} / {runner_why}")

    # K: query round-trips through our own parser and re-encodes to itself
    nonce = 0x4242
    req = build_timestamp_req(digest, nonce=nonce, policy=OID_DEMO_POLICY)
    req_back = parse_timestamp_req(req)
    chk("query-imprint-roundtrip", req_back["imprint"]["imprint"] == digest.hex())
    chk("query-nonce-roundtrip", req_back["nonce"] == nonce)
    chk("query-policy-roundtrip", req_back["policy"] == OID_DEMO_POLICY)
    chk("query-der-is-der", _tlv(0x30, _read_tlv(req)[1]) == req)

    # K: a valid token over the tip verifies GREEN, signature and all
    sk = SigningKey(bytes.fromhex("9" * 64))
    tst = _tst_info(_message_imprint(digest), 7, DEMO_GEN_TIME, nonce)
    resp = build_timestamp_resp(_message_imprint(digest), serial=7, gen_time=DEMO_GEN_TIME,
                                nonce=nonce, signature=sk.sign(tst).signature)
    v, r, d = bind_chain(resp, recs, nonce=nonce, tsa_key=sk.verify_key.encode().hex())
    chk("valid-token-binds-green", v == "ok", r)
    chk("signature-checked", "verified" in d.get("signature", ""))

    # K: a token over a decoy digest is RED despite a valid signature
    decoy = evidence_imprint(b"not-the-ledger")
    tst2 = _tst_info(_message_imprint(decoy), 8, DEMO_GEN_TIME, nonce)
    resp2 = build_timestamp_resp(_message_imprint(decoy), serial=8, gen_time=DEMO_GEN_TIME,
                                 nonce=nonce, signature=sk.sign(tst2).signature)
    v2, r2, _ = bind_chain(resp2, recs, nonce=nonce, tsa_key=sk.verify_key.encode().hex())
    chk("decoy-imprint-is-red", v2 == "red" and r2.startswith("imprint_mismatch"), r2)

    # K: nonce mismatch is RED (replay defense)
    tst3 = _tst_info(_message_imprint(digest), 9, DEMO_GEN_TIME, 0x9999)
    resp3 = build_timestamp_resp(_message_imprint(digest), serial=9, gen_time=DEMO_GEN_TIME,
                                 nonce=0x9999, signature=sk.sign(tst3).signature)
    v3, r3, _ = bind_chain(resp3, recs, nonce=nonce, tsa_key=sk.verify_key.encode().hex())
    chk("nonce-mismatch-is-red", v3 == "red" and r3.startswith("nonce_mismatch"), r3)

    # K: a bad signature is RED, and no-key is not a PASS
    forged = build_timestamp_resp(_message_imprint(digest), serial=10, gen_time=DEMO_GEN_TIME,
                                  nonce=nonce,
                                  signature=SigningKey(b"0" * 32).sign(tst).signature)
    v4, r4, _ = bind_chain(forged, recs, nonce=nonce,
                           tsa_key=sk.verify_key.encode().hex())
    chk("bad-signature-is-red", v4 == "red" and r4.startswith("signature_invalid"), r4)
    v4b, _, d4b = verify_token(forged, expected_imprint=digest, nonce=nonce)
    chk("no-key-not-a-pass", v4b == "ok" and "not-checked" in d4b["signature"])

    # K: a rejection status is RED with its failInfo surfaced
    rej = build_timestamp_resp(_message_imprint(digest), serial=11, gen_time=DEMO_GEN_TIME,
                               nonce=nonce, signature=sk.sign(tst).signature, status=2,
                               status_string="unsupported policy",
                               fail_info=["unacceptedPolicy"])
    v5, r5, d5 = bind_chain(rej, recs, nonce=nonce)
    chk("rejection-status-is-red", v5 == "red" and r5 == "tsa_status_rejection", r5)
    chk("failinfo-surfaced", d5.get("fail_info") == ["unacceptedPolicy"], str(d5.get("fail_info")))

    # K: tampered DER is RED, never a crash
    v6, r6, _ = bind_chain(resp[: len(resp) // 2] + b"\x00\x00", recs, nonce=nonce)
    chk("truncated-der-is-red", v6 == "red" and r6.startswith("response_malformed"), r6)
    v7, r7, _ = bind_chain(b"not-der-at-all", recs, nonce=nonce)
    chk("garbage-der-is-red", v7 == "red" and r7.startswith("response_malformed"), r7)

    # K: a broken ledger is RED even with a perfectly valid token
    broken = [dict(recs[0]), dict(recs[1], prev="f" * 64)]
    v8, r8, _ = bind_chain(resp, broken, nonce=nonce)
    chk("broken-chain-is-red", v8 == "red" and r8.startswith("chain_not_verifiable"), r8)

    # K: genTime parses (canonical and offset forms)
    chk("gentime-canonical",
        dec_gen_time("20261005120530Z") == datetime.datetime(2026, 10, 5, 12, 5, 30,
                                                             tzinfo=datetime.timezone.utc))
    chk("gentime-offset",
        dec_gen_time("20261005150530+0300")
        == datetime.datetime(2026, 10, 5, 12, 5, 30, tzinfo=datetime.timezone.utc))
    chk("gentime-bad-is-raised", _raises(dec_gen_time, "20261340120530Z"))
    return checks


def _raises(fn, *a):
    try:
        fn(*a)
        return False
    except ValueError:
        return True


def cmd_selftest(argv) -> int:
    checks = _selftest()
    failed = [c for c in checks if not c[1]]
    _print({"ok": not failed, "checks": len(checks), "passed": len(checks) - len(failed),
            "failed": [f"{n} ({x})" for n, _, x in failed],
            "name": "brandstrike_tsa — RFC 3161 ↔ Tamga hash-chain code bond"})
    return EXIT_GREEN if not failed else EXIT_RED


def main(argv) -> int:
    if len(argv) < 2:
        print(__doc__)
        return EXIT_IND
    cmd = argv[1]
    if cmd == "selftest":
        return cmd_selftest(argv[2:])
    if cmd == "query":
        return cmd_query(argv[2:])
    if cmd == "verify":
        return cmd_verify(argv[2:])
    if cmd == "demo":
        return cmd_demo(argv[2:])
    print(f"bilinmeyen komut: {cmd}", file=sys.stderr)
    return EXIT_IND


if __name__ == "__main__":
    sys.exit(main(sys.argv))

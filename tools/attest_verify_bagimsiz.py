#!/usr/bin/env python3
"""BAĞIMSIZ attest-verify — sıfır-tamga-import'lu foreign-claim doğrulayıcı.

Amaç (AT-030'un-son-parçası): bir FOREIGN capacity-attest claim'inin
**hiçbir tamga-modülünü-import-etmeden** doğrulanabildiğini kanıtlamak.
P8'in verify-mini-kanıdının attest-verify-versiyonu.

İmzalanan-protokol-kodu-yok: keccak256 + RFC-8785 JCS + secp256k1 ecrecover'un
hepsi-bu-dosyanın-içinde-saf-Python. Yalnızca-stdlib (hashlib'siz bile — keccak
elle).

Kullanım: python3 tools/attest_verify_bagimsiz.py <claim.json>
Çıkış: verdict + signer_recover (tamga_attest_verify-ile-birebir-olmalı)
"""
from __future__ import annotations

import json
import sys

# ---------------------------------------------------------------------------
# Keccak-256 (saf-Python; Ethereum-adresi-ve-EIP-191-hash-için)
# ---------------------------------------------------------------------------

_MASK = (1 << 64) - 1

_RC = [
    0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
    0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
    0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
    0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
    0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
]

_ROT = [
    [0, 36, 3, 41, 18],
    [1, 44, 10, 45, 2],
    [62, 6, 43, 15, 61],
    [28, 55, 25, 21, 56],
    [27, 20, 39, 8, 14],
]


def _rotl(v: int, n: int) -> int:
    n &= 63
    if not n:
        return v
    return ((v << n) | (v >> (64 - n))) & _MASK


def _keccak_f(state: list[int]) -> list[int]:
    for rnd in range(24):
        # theta
        C = [state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20]
             for x in range(5)]
        D = [C[(x - 1) % 5] ^ _rotl(C[(x + 1) % 5], 1) for x in range(5)]
        for x in range(5):
            for y in range(5):
                state[x + 5 * y] ^= D[x]
        # rho + pi
        B = [0] * 25
        for x in range(5):
            for y in range(5):
                B[y + 5 * ((2 * x + 3 * y) % 5)] = _rotl(state[x + 5 * y], _ROT[x][y])
        # chi
        for x in range(5):
            for y in range(5):
                state[x + 5 * y] = (B[x + 5 * y]
                                    ^ ((~B[(x + 1) % 5 + 5 * y]) & B[(x + 2) % 5 + 5 * y]))
        # iota
        state[0] ^= _RC[rnd]
    return state


_RATE = 136  # 1088-bit-Rate (keccak-256)


def keccak256(data: bytes) -> bytes:
    """Keccak-256 (SHA3-256-DEĞİL: padding 0x01, domain-bit'i-yok)."""
    padded = bytearray(data)
    padded.append(0x01)
    while len(padded) % _RATE != _RATE - 1:
        padded.append(0x00)
    padded.append(0x80)  # pad10*1: son-bayt-0x80
    if len(padded) % _RATE != 0:
        # tek-bayt-kalan-durumu: 0x81-olarak-birleşmiş-olmalı
        padded[-1] = 0x81 if len(padded) % _RATE == 1 else padded[-1]
    state = [0] * 25
    for off in range(0, len(padded), _RATE):
        block = padded[off:off + _RATE]
        for i in range(_RATE // 8):
            lane = int.from_bytes(block[i * 8:(i + 1) * 8], "little")
            state[i] ^= lane
        state = _keccak_f(state)
    out = bytearray()
    for i in range(4):  # 32-bayt-çıktı
        out += state[i].to_bytes(8, "little")
        if len(out) >= 32:
            break
    return bytes(out[:32])


# ---------------------------------------------------------------------------
# RFC-8785 JCS (bu-claim-subset'i-için: nesne + string; sayılar-tam-sayı)
# ---------------------------------------------------------------------------

_ESC = {'"': '\\"', "\\": "\\\\", "\b": "\\b", "\f": "\\f",
        "\n": "\\n", "\r": "\\r", "\t": "\\t"}


def _esc_string(s: str) -> str:
    out = []
    for ch in s:
        if ch in _ESC:
            out.append(_ESC[ch])
        elif ord(ch) < 0x20:
            out.append(f"\\u{ord(ch):04x}")
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def _jcs(obj) -> str:
    if obj is None:
        return "null"
    if obj is True:
        return "true"
    if obj is False:
        return "false"
    if isinstance(obj, str):
        return _esc_string(obj)
    if isinstance(obj, int) and not isinstance(obj, bool):
        return str(obj)
    if isinstance(obj, dict):
        # RFC-8785 §3.2.3: UTF-16 kod-birim-sıralı (ASCII'de kod-noktasıyla-aynı)
        parts = []
        for k in sorted(obj, key=lambda s: [ord(c) for c in s]):
            parts.append(_esc_string(k) + ":" + _jcs(obj[k]))
        return "{" + ",".join(parts) + "}"
    if isinstance(obj, (list, tuple)):
        return "[" + ",".join(_jcs(i) for i in obj) + "]"
    raise ValueError(f"JCS-bu-tipi-desteklemiyor: {type(obj).__name__}")


# ---------------------------------------------------------------------------
# secp256k1 ecrecover (saf-Python, affine)
# ---------------------------------------------------------------------------

_P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
_N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
_GX = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798
_GY = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8


def _inv(a: int, m: int) -> int:
    return pow(a % m, m - 2, m)


def _add(p1, p2):
    if p1 is None:
        return p2
    if p2 is None:
        return p1
    (x1, y1), (x2, y2) = p1, p2
    if x1 == x2 and (y1 + y2) % _P == 0:
        return None
    if p1 == p2:
        lam = (3 * x1 * x1) * _inv(2 * y1, _P) % _P
    else:
        lam = (y2 - y1) * _inv(x2 - x1, _P) % _P
    x3 = (lam * lam - x1 - x2) % _P
    return (x3, (lam * (x1 - x3) - y1) % _P)


def _mul(k: int, pt):
    acc = None
    while k:
        if k & 1:
            acc = _add(acc, pt)
        pt = _add(pt, pt)
        k >>= 1
    return acc


def _recover(z: int, r: int, s: int, rec_id: int):
    if not (1 <= r < _N and 1 <= s < _N):
        return None
    x = r + (rec_id >> 1) * _N
    if x >= _P:
        return None
    alpha = (pow(x, 3, _P) + 7) % _P
    beta = pow(alpha, (_P + 1) // 4, _P)
    if pow(beta, 2, _P) != alpha:
        return None
    y = beta if (beta & 1) == (rec_id & 1) else _P - beta
    ri = _inv(r, _N)
    u1, u2 = (-z * ri) % _N, (s * ri) % _N
    return _add(_mul(u1, (_GX, _GY)), _mul(u2, (x, y)))


def _address(pub) -> str:
    x, y = pub
    raw = x.to_bytes(32, "big") + y.to_bytes(32, "big")
    return "0x" + keccak256(raw)[12:].hex()


def _eip191_hash(message: str) -> int:
    m = message.encode("utf-8")
    prefixed = b"\x19Ethereum Signed Message:\n" + str(len(m)).encode() + m
    return int.from_bytes(keccak256(prefixed), "big")


# ---------------------------------------------------------------------------
# CAPACITY_ATTEST_V1 profili — tamga_attest_verify-ile-aynı-sözleşme,
# ama-tamamen-bağımsız-üretim
# ---------------------------------------------------------------------------

SCHEMA_KEYS = ("sellerAddress", "buyerAddress", "assetType", "promisedSpec", "delivered",
               "evidenceHash", "settlementRef", "timestamp", "measured", "externalRefs",
               "priorClaimId")
_LOWER_KEYS = ("sellerAddress", "buyerAddress")


def _canonical_preimage(content: dict) -> bytes:
    clean = {}
    for k in SCHEMA_KEYS:
        if k in content:
            v = content[k]
            clean[k] = v.lower() if (k in _LOWER_KEYS and isinstance(v, str)) else v
    return _jcs(clean).encode("utf-8")


def verify(claim: dict) -> tuple[bool, str, dict]:
    cid = claim.get("claimId")
    sig = claim.get("signature")
    buyer = claim.get("buyerAddress")
    if not (isinstance(cid, str) and isinstance(sig, str) and isinstance(buyer, str)):
        return False, "zarf-eksik: claimId/signature/buyerAddress", {}
    pre = _canonical_preimage(claim)
    mine_cid = "0x" + _sha256_hex(pre)
    if mine_cid.lower() != cid.lower():
        return False, "claimId_mismatch", {"claimId_biz": mine_cid, "claimId_beyan": cid}
    try:
        raw = bytes.fromhex(sig[2:] if sig.startswith("0x") else sig)
        r = int.from_bytes(raw[0:32], "big")
        s = int.from_bytes(raw[32:64], "big")
        v = raw[64]
        rec_id = v - 27 if v >= 27 else v
        if rec_id not in (0, 1) or s > _N // 2:  # EIP-2 low-s
            return False, "signature_geometrisi_gecersiz", {}
        pub = _recover(_eip191_hash(cid), r, s, rec_id)
    except Exception as e:
        return False, f"signature_bozuk: {e}", {}
    if pub is None:
        return False, "signature_recover_edilemedi", {}
    signer = _address(pub)
    detail = {"signer_recover": signer, "buyerAddress": buyer}
    if signer.lower() != buyer.lower():
        return False, "signature_does_not_match_buyer", detail
    return True, "ok", detail


def _sha256_hex(data: bytes) -> str:
    # claimId = sha256(canonical) — bağımsız-üretim
    import hashlib
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    if len(sys.argv) != 2:
        print("kullanim: attest_verify_bagimsiz.py <claim.json>")
        return 2
    claim = json.loads(open(sys.argv[1], encoding="utf-8").read())
    ok, reason, detail = verify(claim)
    print(json.dumps({"verdict": "GREEN" if ok else "RED", "reason": reason,
                      "registry": "CAPACITY_ATTEST_V1", **detail},
                     ensure_ascii=False, indent=2))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

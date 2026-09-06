#!/usr/bin/env python3
"""Keccak-256 (legacy padding, domain byte 0x01) — the Ethereum/x402 durable-evidence
digest. Python's hashlib.sha3_256 is FIPS SHA-3 (0x06 padding) and does NOT match it;
this standalone implementation exists so Tamga can label and compare hashes across the
two worlds without adding a dependency. Self-tests assert the known empty and "abc"
vectors on import failure paths (see main)."""

_MASK = 0xFFFFFFFFFFFFFFFF

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


def _rol(x, n):
    return ((x << n) | (x >> (64 - n))) & _MASK


def keccak256(data: bytes) -> bytes:
    rate = 136                       # keccak-256: capacity 512, rate 1088 bits
    padded = data + b"\x01"          # legacy Keccak domain byte (NOT FIPS 0x06)
    padded += b"\x00" * ((-len(padded)) % rate)
    padded = padded[:-1] + bytes([padded[-1] | 0x80])
    state = [[0] * 5 for _ in range(5)]

    def _f():
        for rnd in range(24):
            c = [state[x][0] ^ state[x][1] ^ state[x][2] ^ state[x][3] ^ state[x][4]
                 for x in range(5)]
            d = [c[(x - 1) % 5] ^ _rol(c[(x + 1) % 5], 1) for x in range(5)]
            for x in range(5):
                for y in range(5):
                    state[x][y] ^= d[x]
            b = [[0] * 5 for _ in range(5)]
            for x in range(5):
                for y in range(5):
                    b[y][(2 * x + 3 * y) % 5] = _rol(state[x][y], _ROT[x][y])
            for x in range(5):
                for y in range(5):
                    state[x][y] = b[x][y] ^ ((~b[(x + 1) % 5][y]) & b[(x + 2) % 5][y] & _MASK)
            state[0][0] ^= _RC[rnd]

    for off in range(0, len(padded), rate):
        block = padded[off:off + rate]
        for i in range(rate // 8):
            lane = int.from_bytes(block[i * 8:(i + 1) * 8], "little")
            state[i % 5][i // 5] ^= lane
        _f()
    out = bytearray()
    for i in range(4):               # 32 bytes = 4 lanes
        out += state[i % 5][i // 5].to_bytes(8, "little")
    return bytes(out)


if __name__ == "__main__":
    v_empty = "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
    v_abc = "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"
    assert keccak256(b"").hex() == v_empty, "keccak256('') vector FAILED"
    assert keccak256(b"abc").hex() == v_abc, "keccak256('abc') vector FAILED"
    print("keccak256 self-test OK (2/2 known vectors)")

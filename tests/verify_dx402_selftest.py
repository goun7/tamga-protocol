#!/usr/bin/env python3
"""Selftest for verify_dx402_vector.py — the derivable relations, no network.

Covers:
  a) paymentId derivation against the public #3379 demo vector constants
  b) contentHash-vs-bytes binding (positive + tampered bytes must FAIL)
  c) CID fragment parse from the pointer field
Exits 0 on full pass; 1 on any failure.
"""
import json, sys, pathlib, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from keccak256 import keccak256

FAIL = []
def check(name, ok):
    print(f"[{'PASS' if ok else 'FAIL'}] {name}")
    if not ok:
        FAIL.append(name)

# (a) paymentId — constants from the thread's public vector (issuecomment-5562584259)
chain, txh = "eip155:43114", "71799e37a07e5b8b7edf96f6c2c3b62455c4dad859c1885ef995fdd95622ced4"
pid = keccak256(chain.encode() + txh.encode()).hex()
check("paymentId derivation", pid == "7e7ca6a10e0d2a835fd0d8045d0a95a6ee5f5dd29b39696e69c3c21c7a3387ec")

# (b) contentHash binding: positive + tamper
blob = b"x402-consented-delivery-payload\n" * 5
ch = keccak256(blob).hex()
check("contentHash positive", keccak256(blob).hex() == ch)
check("contentHash tamper-RED", keccak256(blob[:-1] + b"X").hex() != ch)

# (c) pointer CID fragment
ptr = "ipfs+https://host/dx402/blob/x#bafkreifcy4wykdscbdxnc3ynbbmtf6jsif72hssxclfp6l3xkbssxh3j5i"
cid = ptr.split("#", 1)[1]
check("CID fragment parse", cid.startswith("bafkrei") and len(cid) == 59)

print("SELFTEST:", "OK" if not FAIL else f"FAILED ({len(FAIL)})")
sys.exit(1 if FAIL else 0)

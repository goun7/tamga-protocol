#!/usr/bin/env python3
"""verify_dx402_vector.py — offline x402 payment-vector checker (RFC-007 pairing track).

Verifies the PAYMENT half of a DX402 vector without touching the network (the
facilitator may 404 by the time you verify — the point is the math):

  1. paymentId = keccak256(ascii(chainId) || ascii(lowercase tx hash, no 0x))
  2. contentHash binding: keccak256(delivery bytes) vs the receipt's hash field
     (--delivery-file); without the file the field is ASSERTED-only.
  3. EIP-712 signer recovery of the Dx402EvidenceReceipt — ONLY if `eth_account`
     is importable; otherwise SKIPPED with an explicit note (never silently).

Usage:
  python3 tools/verify_dx402_vector.py receipt.json [--delivery-file out.bin]

Exit 0 = no mandatory FAIL; 1 = any FAIL; 2 = precondition (bad args).
Honesty rules: checks are labeled PASS/FAIL/SKIP; a skipped optional check is
never reported as PASS. Fields read from the receipt are trusted as *claimed*
values; only the derived relations are proven here.
"""
import json, sys, pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from keccak256 import keccak256  # pure-python, self-testing

def out(ok, label, detail=""):
    tag = "PASS" if ok is True else ("FAIL" if ok is False else "SKIP")
    print(f"[{tag}] {label}" + (f" — {detail}" if detail else ""))
    return 0 if ok is True else (1 if ok is False else 0)

def main(a):
    if len(a) < 1:
        print(__doc__)
        return 2
    rec = json.loads(pathlib.Path(a[0]).read_text(encoding="utf-8"))
    rc = 0
    # --- 1. paymentId derivation (derived) ---
    chain = rec.get("network") or rec.get("chainId")
    txh = (rec.get("txHash") or "").lower().removeprefix("0x")
    pid_exp = (rec.get("paymentId") or "").lower()
    if chain and txh and pid_exp:
        pid = keccak256(str(chain).encode() + txh.encode()).hex()
        rc |= out(pid == pid_exp.removeprefix("0x"),
                  "paymentId = keccak256(chainId || txHash)", "0x" + pid)
    else:
        rc |= out(None, "paymentId derivation", "network/txHash/paymentId missing")
    # --- 2. contentHash binding (derived vs asserted) ---
    ch = rec.get("contentHash") or (rec.get("delivery_hash") or {}).get("hex") or ""
    if len(a) >= 3 and a[1] == "--delivery-file":
        blob = pathlib.Path(a[2]).read_bytes()
        if ch:
            rc |= out(keccak256(blob).hex() == ch.lower().removeprefix("0x"),
                      "contentHash = keccak256(delivery bytes)", f"{len(blob)}B")
        else:
            rc |= out(False, "contentHash", "receipt has no hash field")
    else:
        rc |= out(None, "contentHash binding",
                  "no --delivery-file: asserted-only (facilitator claim, not derived)")
    # --- 3. EIP-712 signer (derived) — optional dependency ---
    if rec.get("signature") and rec.get("signer"):
        try:
            from eth_account import Account
            from eth_account.messages import encode_typed_data
            dom = {"name": "DX402 Evidence", "version": "1",
                   "chainId": 43114}  # Avalanche; vector's domain has no verifyingContract/salt
            msg = {"paymentId": bytes.fromhex(pid_exp.removeprefix("0x")),
                   "contentHash": bytes.fromhex(ch.lower().removeprefix("0x")),
                   "pointer": rec["pointer"], "payer": rec["payer"], "payee": rec["payee"],
                   "txHash": bytes.fromhex(txh),
                   "mode": int(rec.get("mode_num", rec.get("mode", 0)) if str(rec.get("mode_num", rec.get("mode", 0))).isdigit() else 0),
                   "anchoredAt": int(rec["anchoredAt"]),
                   "retentionUntil": int(rec["retentionUntil"])}
            types = {"EIP712Domain": [{"name": "name", "type": "string"},
                                      {"name": "version", "type": "string"},
                                      {"name": "chainId", "type": "uint256"}],
                     "Dx402EvidenceReceipt": [{"name": "paymentId", "type": "bytes32"},
                                              {"name": "contentHash", "type": "bytes32"},
                                              {"name": "pointer", "type": "string"},
                                              {"name": "payer", "type": "address"},
                                              {"name": "payee", "type": "address"},
                                              {"name": "txHash", "type": "bytes32"},
                                              {"name": "mode", "type": "uint8"},
                                              {"name": "anchoredAt", "type": "uint64"},
                                              {"name": "retentionUntil", "type": "uint64"}]}
            sig = bytes.fromhex(rec["signature"].removeprefix("0x"))
            v = sig[-1] if sig[-1] < 27 else sig[-1] - 27
            full = {"types": types, "primaryType": "Dx402EvidenceReceipt",
                    "domain": dom, "message": msg}
            sm = encode_typed_data(full_message=full)
            addr = Account.recover_message(sm, vrs=(v, sig[:32], sig[32:64]))
            rc |= out(addr.lower() == rec["signer"].lower(),
                      "EIP-712 ecrecover(signer)", addr)
        except ImportError:
            rc |= out(None, "EIP-712 ecrecover",
                      "eth_account yok — pip install eth-account (SKIP, sessiz-değil)")
    else:
        rc |= out(None, "EIP-712 ecrecover", "signature/signer alanı yok")
    return 1 if rc else 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

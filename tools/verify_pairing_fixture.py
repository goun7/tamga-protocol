#!/usr/bin/env python3
"""Verify a pairing fixture directory (x402 <-> Tamga, #3379).

Checks, in order (first failure exits 1 with a JSON error line):
  1. labeling discipline: every fixture field carries
     source in {simulated, observed, derived}
  2. hash membership: receiptHash == sha256(prev + jcs(charge_record without h))
     (recomputeable without the ledger; full chain membership is ledger-verify)
  3. observed delivery bytes: sha256(delivery.stdout) == charge stdout_sha256
     == fixture delivery_bytes.sha256
  4. derived digest: keccak256(delivery.stdout) == fixture delivery_bytes.keccak256
  5. input commitment: sha256(input.json) == charge input_sha256

Usage: python3 tools/verify_pairing_fixture.py <dir>
"""
import hashlib
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "tools"))
from keccak256 import keccak256  # noqa: E402

SOURCES = {"simulated", "observed", "derived"}


def jcs(d):
    return json.dumps(d, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def _check_labels(node, path, errs):
    if isinstance(node, dict):
        if {"value", "source"} <= set(node.keys()):
            if node.get("source") not in SOURCES:
                errs.append(f"{path}: bad source {node.get('source')!r}")
        elif "value" in node:
            # a value-field without a label breaks the labeling discipline entirely
            errs.append(f"{path}: value-field missing source label")
        else:
            for k, v in node.items():
                _check_labels(v, f"{path}.{k}", errs)


def main():
    d = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / "docs" / "pairing")
    fx = json.loads((d / "pairing-fixture.json").read_text(encoding="utf-8"))

    # 1) labeling discipline (safal207 request: simulated vs observed made explicit)
    errs = []
    _check_labels(fx.get("x402_settlement", {}), "x402_settlement", errs)
    _check_labels(fx.get("tamga_observed", {}), "tamga_observed", errs)
    _check_labels(fx.get("input_commitment", {}), "input_commitment", errs)
    _check_labels(fx.get("delivery_bytes", {}), "delivery_bytes", errs)
    if errs:
        print(json.dumps({"ok": False, "where": "labeling", "errors": errs}))
        sys.exit(1)

    charge = fx["tamga_observed"]["charge_record"]["value"]
    # 2) hash membership: recompute the receipt hash from the shipped record
    rec = {k: v for k, v in charge.items() if k not in ("h", "node_sig")}
    h = hashlib.sha256((charge["prev"] + jcs(rec)).encode("utf-8")).hexdigest()
    if h != fx["tamga_observed"]["receiptHash"]["value"]:
        print(json.dumps({"ok": False, "where": "membership",
                          "error": "recomputed h != receiptHash"}))
        sys.exit(1)

    delivery = (d / "delivery.stdout").read_bytes()
    # 3) observed bytes
    d_sha = hashlib.sha256(delivery).hexdigest()
    if d_sha != charge.get("stdout_sha256") or \
       d_sha != fx["delivery_bytes"]["sha256"]["value"]:
        print(json.dumps({"ok": False, "where": "delivery_bytes",
                          "error": "sha256(delivery.stdout) mismatch"}))
        sys.exit(1)
    if len(delivery) != fx["delivery_bytes"]["byte_count"]["value"]:
        print(json.dumps({"ok": False, "where": "delivery_bytes",
                          "error": "byte_count mismatch"}))
        sys.exit(1)
    # 4) derived digest (Keccak-256, legacy padding)
    if keccak256(delivery).hex() != fx["delivery_bytes"]["keccak256"]["value"]:
        print(json.dumps({"ok": False, "where": "delivery_bytes",
                          "error": "keccak256 mismatch"}))
        sys.exit(1)
    # 5) input commitment (D11)
    inp = (d / "input.json").read_bytes()
    if hashlib.sha256(inp).hexdigest() != fx["input_commitment"]["input_sha256"]["value"]:
        print(json.dumps({"ok": False, "where": "input_commitment",
                          "error": "sha256(input.json) mismatch"}))
        sys.exit(1)

    print(json.dumps({"ok": True, "receiptHash": h,
                      "stdout_sha256": d_sha,
                      "checks": ["labeling", "membership", "delivery_sha256",
                                 "delivery_keccak256", "input_sha256"]}))


if __name__ == "__main__":
    main()

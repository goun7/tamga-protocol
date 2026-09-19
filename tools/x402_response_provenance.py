#!/usr/bin/env python3
"""
response-provenance dogrulayici — x402 spec/extensions/response-provenance.md (PR #3304)

Bagimsiz urcum: RFC 8785 (JCS) kanoniklestirmesi Tamga'nin tamga_canon moduluyle
yapilir, ama bu aracin kendisi x402'ye HICBIR bagimlilik kurmaz — sadece sha256 +
JCS. Amac: PR #3304'nun normative worked vector'unu ve g-verileri ureten herhangi
bir fixed-point'i bagimsizca re-derive edebilmek.

Kullanim:
    python3 tools/x402_response_provenance.py verify <fixedpoint.json>
    python3 tools/x402_response_provenance.py vector
"""
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tamga_canon import jcs  # RFC 8785 JCS, Node ile parite-kanitli (17/17)


SPEC_VECTOR = {
    "endpoint": "/v1/echo-sum",
    "inputs": {"a": 2, "b": 3},
    "result": {"sum": 5},
    "method": "sum = a + b, integer addition",
    "dataVintage": "2026-07",
}
SPEC_HASH = "81ea1f2227fd9df5b868954e6d26d091810352f148dade483b260844788ede03"
SPEC_CANON_LEN = 134

# PR #3304 normative: kapali kume, baska uye YOK
REQUIRED_MEMBERS = ("endpoint", "inputs", "result", "method", "dataVintage")


def canonical_bytes(obj) -> bytes:
    """RFC 8785 JCS. Number/Unicode divergence'lari reddeder (I-JSON subset)."""
    return jcs(obj)


def verify_fixed_point(fp: dict) -> dict:
    """PR #3304'nun kapali-kume kuralini uygulayip hash'i re-derive eder."""
    extra = set(fp.keys()) - set(REQUIRED_MEMBERS)
    if extra:
        return {
            "verdict": "unverifiable",
            "reason": f"extra member(s) in fixed point: {sorted(extra)}",
        }
    missing = set(REQUIRED_MEMBERS) - set(fp.keys())
    if missing:
        return {
            "verdict": "unverifiable",
            "reason": f"missing required member(s): {sorted(missing)}",
        }
    canon = canonical_bytes(fp)
    return {
        "verdict": "ok",
        "canonical": canon.decode(),
        "canonical_bytes": len(canon),
        "responseHash": hashlib.sha256(canon).hexdigest(),
    }


def cmd_vector() -> int:
    r = verify_fixed_point(SPEC_VECTOR)
    if r["verdict"] != "ok":
        print(json.dumps({"ok": False, "error": r}, ensure_ascii=False))
        return 1
    match = r["responseHash"] == SPEC_HASH
    print(
        json.dumps(
            {
                "ok": match,
                "spec": "response-provenance.md (PR #3304)",
                "fixedPoint": SPEC_VECTOR,
                "canonical": r["canonical"],
                "canonical_bytes": r["canonical_bytes"],
                "expected_bytes": SPEC_CANON_LEN,
                "responseHash": r["responseHash"],
                "expectedHash": SPEC_HASH,
                "byte_exact": match,
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0 if match else 1


def cmd_verify(path: str) -> int:
    try:
        with open(path, "r", encoding="utf-8") as f:
            fp = json.load(f)
    except (OSError, ValueError) as e:
        print(json.dumps({"ok": False, "error": f"load: {e}"}, ensure_ascii=False))
        return 1
    r = verify_fixed_point(fp)
    if r["verdict"] != "ok":
        print(json.dumps({"ok": False, **r}, ensure_ascii=False))
        return 1
    print(json.dumps({"ok": True, **r}, ensure_ascii=False, indent=2))
    return 0


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd = argv[1]
    if cmd == "vector":
        return cmd_vector()
    if cmd == "verify":
        if len(argv) < 3:
            print("kullanim: verify <fixedpoint.json>", file=sys.stderr)
            return 2
        return cmd_verify(argv[2])
    print(f"bilinmeyen komut: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))

#!/usr/bin/env python3
# Copyright (c) 2026 Anomly, Inc. Author: Ry Bruscoe. Licensed per LICENSES.md (Apache-2.0 code / CC-BY-4.0 docs).
"""conformance_runner.py — self-certify a third-party CR implementation against the vectors.

§9 of the spec says the point of a standard is that someone can *implement CR without this
repository*. This is the tool that lets them prove they did: emit your conformance vectors in
the published schema, run this, and get a per-vector PASS/FAIL with a precise diff on any
mismatch. It has no dependency on `cr.receipt` beyond loading the published reference file, so
it is a neutral referee, not the reference grading itself.

Schema. A candidate file is a JSON array of objects, each `{"name": "<vector name>", …value
fields…}`. This runner compares, for each named vector, every VALUE field the reference pins:

  canonical          the exact canonical-JSON string (§2)
  digest             a "<alg>:<hex>" digest (§3)
  certificate        the manifest certificate (§5)
  manifest_canonical the canonical bytes of a receipt's manifest (§4–§5)
  sample_indices     the derived sampled-unit indices (§10) — pinned separately because a
                     matching sample digest does NOT prove the same index rule was used
  chain_digest       the receipt-chain digest (§12)
  expect_verdict     the verdict a conforming verifier MUST return for a refuse/* vector (§6)

`input` and `why` are not graded (input is what you feed in; why is prose).

Coverage. The canonicalisation layer (`canonical/*`, `tensor/*`, `tensors/*`) needs no
arithmetic and is the first thing any implementation should reproduce (spec §9/§10). The
receipt / chain / refuse vectors additionally exercise the manifest builders and the verdict
rules. The runner reports coverage per layer and only PASSES overall when every reference
vector is both present and correct.

Usage:
  python3 conformance_runner.py <candidate-vectors.json>
  python3 conformance_runner.py --demo         # grade the reference against itself (all PASS)
  python3 conformance_runner.py --emit > mine.json   # print the reference schema to fill in
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

REFERENCE = Path(__file__).resolve().parents[1] / "spec" / "CR-v0.1-conformance-vectors.json"

# value fields that are graded (everything the reference pins as a reproducible output)
GRADED = ("canonical", "digest", "certificate", "manifest_canonical",
          "sample_indices", "chain_digest", "expect_verdict")

CANON_LAYER = ("canonical/", "tensor/", "tensors/")


def _layer(name: str) -> str:
    return "canonicalisation" if name.startswith(CANON_LAYER) else "receipt/verdict"


def _fmt(v) -> str:
    s = json.dumps(v) if not isinstance(v, str) else v
    return s if len(s) <= 72 else s[:69] + "…"


def grade(reference: list, candidate: list) -> tuple[int, int, list]:
    """Return (n_pass, n_total, lines). A vector passes iff it is present and every graded
    field the reference pins is present in the candidate and exactly equal."""
    cand = {v.get("name"): v for v in candidate if isinstance(v, dict)}
    lines, n_pass = [], 0
    for ref in reference:
        name = ref["name"]
        graded = [f for f in GRADED if f in ref]
        c = cand.get(name)
        if c is None:
            lines.append(f"  FAIL  {name:38} [{_layer(name)}]  — not provided by the candidate")
            continue
        diffs = []
        for f in graded:
            if f not in c:
                diffs.append(f"missing field {f!r}")
            elif c[f] != ref[f]:
                diffs.append(f"{f}: got {_fmt(c[f])!r} != expected {_fmt(ref[f])!r}")
        if diffs:
            lines.append(f"  FAIL  {name:38} [{_layer(name)}]")
            lines.extend(f"          {d}" for d in diffs)
        else:
            n_pass += 1
            lines.append(f"  PASS  {name:38} [{_layer(name)}]  ({', '.join(graded)})")
    return n_pass, len(reference), lines


def main(argv: list) -> int:
    reference = json.loads(REFERENCE.read_text(encoding="utf-8"))

    # --require <layer>: pass (exit 0) if every vector in that layer is reproduced, ignoring
    # the others. A canonicalisation-only implementation is conforming for that layer (§9's
    # first step needs no arithmetic), so `--require canonicalisation` gives it a clean check.
    require = None
    if "--require" in argv:
        i = argv.index("--require")
        require = argv[i + 1] if i + 1 < len(argv) else ""
        argv = argv[:i] + argv[i + 2:]

    if argv and argv[0] == "--emit":
        # print the reference schema with value fields blanked, as a template to fill in
        tmpl = [{k: (v if k in ("name", "input") else "<your value>") for k, v in vec.items()
                 if k != "why"} for vec in reference]
        print(json.dumps(tmpl, indent=2, ensure_ascii=False))
        return 0

    if argv and argv[0] == "--demo":
        candidate = reference                       # grade the reference against itself
        src = "the reference implementation (self-check)"
    elif argv:
        candidate = json.loads(Path(argv[0]).read_text(encoding="utf-8"))
        src = argv[0]
    else:
        print(__doc__)
        return 2
    if not isinstance(candidate, list):
        print("candidate file must be a JSON array of vector objects")
        return 2

    print(f"# CR v0.1 conformance — grading {src}")
    n_pass, n_total, lines = grade(reference, candidate)
    print("\n".join(lines))
    layers = {}
    for ref in reference:
        layers.setdefault(_layer(ref["name"]), [0, 0])[1] += 1
    for ref in reference:
        c = next((v for v in candidate if isinstance(v, dict) and v.get("name") == ref["name"]), None)
        if c and all(f not in ref or c.get(f) == ref[f] for f in GRADED):
            layers[_layer(ref["name"])][0] += 1
    print()
    for layer, (p, t) in sorted(layers.items()):
        print(f"  {layer:16} {p}/{t}")

    if require is not None:
        if require not in layers:
            print(f"\nunknown layer {require!r}; layers are: {', '.join(sorted(layers))}")
            return 2
        p, t = layers[require]
        ok = p == t
        print(f"\n{'PASS' if ok else 'FAIL'}: required layer {require!r} reproduced {p}/{t}")
        return 0 if ok else 1

    print(f"\n{'PASS' if n_pass == n_total else 'FAIL'}: {n_pass}/{n_total} vectors reproduced")
    if n_pass != n_total:
        print("A conforming implementation reproduces every vector. See the diffs above; the "
              "canonicalisation layer (§2/§3) is the place to start — it needs no arithmetic.")
    return 0 if n_pass == n_total else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

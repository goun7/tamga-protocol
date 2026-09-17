"""Canonical JSON serialization (RFC 8785 / JCS) — stdlib-only, zero third-party deps.

Plain ``json.dumps(sort_keys=True, separators=(",", ":"))`` is NOT RFC 8785. Two divergences
matter enormously here, because the entire point of a receipt is that a stranger using a
DIFFERENT LANGUAGE re-derives the same bytes:

1. **Numbers** must use the ECMAScript number-to-string algorithm (RFC 8785 §3.2.2.2):
   ``1.0`` → ``"1"`` (Python says ``"1.0"``), ``2.93e-07`` → ``"2.93e-7"`` (Python pads the
   exponent), ``1e16`` → ``"10000000000000000"`` (Python switches to exponent form at 1e16;
   ECMAScript only above 1e21 or below 1e-6).
2. **Member order** is by UTF-16 code unit (RFC 8785 §3.2.3), which diverges from Python's
   code-point ordering when non-BMP characters mix with high-BMP characters.

History (honest): until 2026-09-17 this project's ``jcs`` *was* plain ``json.dumps``. It was
found not by us but by a stranger auditing the sibling project (Dümen issue #4,
stillmarcus24): a chain hash could only be recomputed by Python. The fix is this module.
Every digest computed after the fix uses it; the old digests were Python-specific and are
recorded as such.

Parity: ``tamga_verify_mini.py`` carries a deliberately-duplicated single-file copy so the
mini verifier stays a standalone audit artifact; ``tools/vauban_conformance.py --selftest``
machine-checks that all copies agree byte-for-byte, and the node reference
(``tools/jcs_ref.mjs``) cross-language-checks this implementation.
"""

import json
from decimal import Decimal

__all__ = ["jcs", "canonical", "es_number"]

_ESCAPE = {
    '"': '\\"', "\\": "\\\\", "\b": "\\b", "\f": "\\f",
    "\n": "\\n", "\r": "\\r", "\t": "\\t",
}


def es_number(x: float) -> str:
    """ECMAScript ``Number.prototype.toString`` (RFC 8785 §3.2.2.2); rejects NaN/Inf."""
    if x != x or x in (float("inf"), float("-inf")):
        raise TypeError("non-finite numbers are not canonicalizable (RFC 8785 forbids them)")
    if x == 0:                       # covers -0.0 → "0" (ECMAScript prints "0")
        return "0"
    neg = x < 0
    digits, exp = Decimal(repr(abs(x))).as_tuple()[-2:]
    # repr(1.0) → digits '10'; strip trailing zeros to reach the shortest form
    while len(digits) > 1 and digits[-1] == 0:
        digits, exp = digits[:-1], exp + 1
    k = len(digits)
    n = exp + k                      # value = s × 10^(n-k), 10^(k-1) ≤ s < 10^k
    s = "".join(map(str, digits))
    if k <= n <= 21:
        body = s + "0" * (n - k)
    elif 0 < n <= 21:
        body = s[:n] + "." + s[n:]
    elif -6 < n <= 0:
        body = "0." + "0" * (-n) + s
    else:
        e = n - 1
        mant = s if k == 1 else s[0] + "." + s[1:]   # single-digit mantissa: "1e+21", never "1.e+21"
        body = mant + "e" + ("+" if e >= 0 else "-") + str(abs(e))
    return ("-" if neg else "") + body


def _enc_string(s: str) -> str:
    out = ['"']
    for ch in s:
        if ch in _ESCAPE:
            out.append(_ESCAPE[ch])
        elif ord(ch) < 0x20:
            out.append(f"\\u{ord(ch):04x}")
        else:
            out.append(ch)           # raw UTF-8 on encode; non-ASCII is NOT escaped
    out.append('"')
    return "".join(out)


def _encode(o, out: list) -> None:
    if o is None:
        out.append("null")
    elif o is True:
        out.append("true")
    elif o is False:
        out.append("false")
    elif isinstance(o, bool):        # defensive: bool subclasses int
        out.append("true" if o else "false")
    elif isinstance(o, int):
        out.append(str(o))           # decimal digits; big ints stay exact (see module docstring)
    elif isinstance(o, float):
        out.append(es_number(o))
    elif isinstance(o, str):
        out.append(_enc_string(o))
    elif isinstance(o, dict):
        out.append("{")
        first = True
        for key in sorted(o, key=lambda k: k.encode("utf-16-be")):   # UTF-16 code-unit order (RFC 8785 §3.2.3)
            if not first:
                out.append(",")
            first = False
            out.append(_enc_string(str(key)))
            out.append(":")
            _encode(o[key], out)
        out.append("}")
    elif isinstance(o, (list, tuple)):
        out.append("[")
        first = True
        for item in o:
            if not first:
                out.append(",")
            first = False
            _encode(item, out)
        out.append("]")
    else:
        raise TypeError(f"unsupported canonical value: {type(o).__name__}")


def jcs(obj) -> bytes:
    """RFC 8785 canonical serialization (JCS) as UTF-8 bytes."""
    out: list = []
    _encode(obj, out)
    return "".join(out).encode("utf-8")


canonical = jcs                       # alias kept for readers coming from other JCS docs


def jcs_json(obj) -> str:
    """Same canonicalization, as ``str`` (for callers that compose digests as text)."""
    return jcs(obj).decode("utf-8")


def loads(s):                         # convenience for parity tests
    return json.loads(s)

"""Mesh-wide JCS bond parity — the frozen constant that 9 anchors reproduce.

TamgaProtocol's ``tamga_canon.jcs`` is the REFERENCE point of the mesh's JCS
parity anchor set. Nine sibling projects (Yieldix, Veridrome, Fleksa, TeleopAI,
LexBinder, Fractiona, KlinikKapici, Pacta, GNoME-Forge) each ship an
independent stdlib copy of the same RFC 8785 serializer, and every one of them
must derive BYTE-IDENTICAL bytes from the same input. If any one diverges, a
receipt issued there can no longer be re-derived by a stranger in another
language — the whole point of a receipt is lost.

This test freezes that bond as a pinned constant: it does not recompute the
expected bytes from a serializer (that would make the test tautological), it
asserts the concrete 56-byte production of the canonical parity vector. The
constant is the contract; the nine anchors are its provenance.

Optionally, when the anchor sources are present on this machine, the same
constant is re-derived through each anchor's OWN serializer copy and compared
byte-for-byte. Absent anchors are SKIP'd honestly (the suite stays hermetic in
CI); present ones must agree exactly.
"""
import ast
import json
import os

import pytest

from tamga_canon import jcs, jcs_json

# --- the mesh bond: frozen expected bytes --------------------------------------
# Vector chosen to exercise every load-bearing JCS rule at once:
#   * 'a': 2.93e-07  — ECMAScript shortest number form ("2.93e-7", NOT the
#     Python-padded "2.93e-07"); the divergence that once made digests
#     Python-only (2026-09-17, tamga_canon history).
#   * 'c': 'Üstanbul' — non-ASCII stays RAW UTF-8 (RFC 8785 does not escape it)
#     so the byte length matches a JS/Go/Rust encoder.
#   * 'd': [3, 1, 2]  — arrays are order-significant: NOT sorted.
#   * 'b': 1 / 'e': None — int and null spellings; insertion order is 'b'
#     first, yet canonical order is a,b,c,d,e.
MESH_VECTOR = {'b': 1, 'a': 2.93e-07, 'c': 'Üstanbul', 'd': [3, 1, 2], 'e': None}

# 9-anchor expected constant: {"a":2.93e-7,"b":1,"c":"Üstanbul","d":[3,1,2],"e":null}
MESH_BOND_HEX = (
    "7b2261223a322e3933652d372c2262223a312c"
    "2263223a22c39c7374616e62756c222c226422"
    "3a5b332c312c325d2c2265223a6e756c6c7d"
)
MESH_BOND_BYTES = bytes.fromhex(MESH_BOND_HEX)
MESH_BOND_TEXT = MESH_BOND_BYTES.decode("utf-8")


# --- the reference serializer must reproduce the bond exactly ------------------
def test_mesh_bond_constant_is_byte_exact():
    """THE bond: tamga_canon.jcs — the mesh reference — must emit the exact
    56-byte constant the nine anchors froze. One byte off and the mesh splits."""
    out = jcs(MESH_VECTOR)
    assert out == MESH_BOND_BYTES
    assert out.hex() == MESH_BOND_HEX
    assert len(out) == 56


def test_mesh_bond_constant_roundtrips_to_the_vector():
    """The frozen constant is not arbitrary: it decodes back to the vector, so
    the bond is a faithful (not lossy) canonicalization."""
    decoded = json.loads(MESH_BOND_TEXT)
    assert decoded == MESH_VECTOR
    assert jcs_json(decoded) == MESH_BOND_TEXT


def test_mesh_bond_members_are_in_utf16_canonical_order():
    """Members appear as a,b,c,d,e — UTF-16 code-unit order (RFC 8785 §3.2.3) —
    regardless of the 'b'-first insertion order of the vector."""
    assert [f'"{k}"' for k in "abcde"] == [f'"{k}"' for k in json.loads(MESH_BOND_TEXT)]
    # insertion order (b first) provably does not leak into the bytes
    shuffled = dict(reversed(list(MESH_VECTOR.items())))
    assert jcs(shuffled) == MESH_BOND_BYTES


def test_mesh_bond_float_is_ecmascript_not_python():
    """The number is the ECMAScript shortest form; Python's own repr would pad
    the exponent and break cross-language parity."""
    assert b'2.93e-7' in MESH_BOND_BYTES
    assert b'2.93e-07' not in MESH_BOND_BYTES
    assert json.dumps(MESH_VECTOR, sort_keys=True) != MESH_BOND_TEXT


def test_mesh_bond_non_ascii_is_raw_utf8():
    """Ü (U+00DC) is emitted as its two raw UTF-8 bytes 0xC3 0x9C, never as the
    six-character ``\\u00dc`` escape — byte length must match a JS encoder."""
    assert b'\xc3\x9c' in MESH_BOND_BYTES
    assert b'\\u00dc' not in MESH_BOND_BYTES
    assert MESH_BOND_BYTES.index(b'\xc3\x9c') == MESH_BOND_BYTES.index('Ü'.encode())


def test_mesh_bond_array_order_is_significant():
    """Arrays are NOT canonicalized-order: [3,1,2] stays [3,1,2]. Sorting it
    would change the receipt's meaning, not just its spelling."""
    assert b'"d":[3,1,2]' in MESH_BOND_BYTES
    assert b'"d":[1,2,3]' not in MESH_BOND_BYTES


def test_mesh_bond_scalar_spellings():
    """int 1 → ``1`` (not ``1.0``) and None → ``null`` — the JSON spellings a
    Node/Go verifier re-derives."""
    assert b'"b":1' in MESH_BOND_BYTES
    assert b'"b":1.0' not in MESH_BOND_BYTES
    assert MESH_BOND_BYTES.endswith(b'"e":null}')


def test_mesh_bond_is_deterministic():
    """The bond is stable across repeated serializations — a receipt must be
    re-derivable later, not just once."""
    assert jcs(MESH_VECTOR) == jcs(MESH_VECTOR) == MESH_BOND_BYTES


# --- optional: re-derive the bond through each anchor's OWN serializer --------
# CI does not carry the sibling repos, so absent anchors SKIP honestly; present
# ones must reproduce the same constant through their independent copy.
_ANCHOR_SOURCES = {
    "Yieldix": "/home/gokun/projects/01_unicorn/99-Yieldix/src/yieldix/mesh/tamga_anchor.py",
    "Veridrome": "/home/gokun/projects/01_unicorn/73-Veridrome/src/veridrome/certificate/tamga_anchor.py",
    "Fleksa": "/home/gokun/projects/01_unicorn/76-Fleksa/src/fleksa/audit/tamga_anchor.py",
    "TeleopAI": "/home/gokun/projects/04_hukuk_sarti/71-TeleopAI/faz0/tamga_anchor.py",
    "LexBinder": "/home/gokun/projects/02_sahis/02-LexBinder/lexbinder/bond/tamga_anchor.py",
    "Fractiona": "/home/gokun/projects/04_hukuk_sarti/65-Fractiona/kanit_meshi.py",
    "KlinikKapici": "/home/gokun/projects/02_sahis/06-KlinikKapici/klinikkapici/consent_tamga.py",
    "Pacta": "/home/gokun/projects/01_unicorn/03-Pacta/pacta/integrations/tamga_jcs.py",
    "GNoME-Forge": "/home/gokun/projects/01_unicorn/19-GNoME-Forge/gnome_forge/integrations/tamga_ledger.py",
}

_JCS_NAMES = {"_ESCAPE", "_SAFE_INT_LIMIT", "es_number", "_enc_string",
              "_encode", "jcs", "jcs_str", "canonical"}


def _anchor_jcs(path):
    """Exec the anchor's self-contained JCS block and return its ``jcs``.

    Anchor modules import project-specific siblings, so only the standalone
    JCS segment (module constants + serializer functions) is lifted out and run
    with ``Decimal`` — the serializer itself is stdlib-only by design.
    """
    src = open(path, encoding="utf-8").read()
    tree = ast.parse(src)
    nodes = []
    for node in tree.body:
        if isinstance(node, ast.Assign):
            if {t.id for t in node.targets if isinstance(t, ast.Name)} & _JCS_NAMES:
                nodes.append(node)
        elif isinstance(node, ast.FunctionDef) and node.name in _JCS_NAMES:
            nodes.append(node)
    if not nodes:
        raise RuntimeError("no JCS block found in anchor")
    block = "\n".join(src.splitlines()[nodes[0].lineno - 1:nodes[-1].end_lineno])
    ns = {}
    exec("from decimal import Decimal\n" + block, ns)  # noqa: S102 — isolated JCS copy
    fn = ns.get("jcs") or ns.get("canonical")
    if fn is None:
        raise RuntimeError("anchor defines neither jcs nor canonical")
    return fn


@pytest.mark.parametrize("anchor", sorted(_ANCHOR_SOURCES))
def test_anchor_reproduces_mesh_bond_constant(anchor):
    """Each anchor's independent serializer copy must re-derive the SAME bond
    constant from the vector — the mesh parity this bond exists to guarantee."""
    path = _ANCHOR_SOURCES[anchor]
    if not os.path.exists(path):
        pytest.skip(f"anchor source not present on this machine: {anchor}")
    out = _anchor_jcs(path)(MESH_VECTOR)
    # GNoME-Forge's copy returns str; the byte contract is its UTF-8 encoding
    out = out.encode("utf-8") if isinstance(out, str) else out
    assert out == MESH_BOND_BYTES, f"{anchor} diverged from the mesh bond"

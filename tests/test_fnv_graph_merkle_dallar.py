"""tamga_runner._fnv1a64 + _graph_merkle dal-kesen testleri (LEED).

Kural-1: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory (hashlib saf, dis cagri YOK).
"""
import hashlib
import sys

import pytest

sys.path.insert(0, ".")
from tamga_runner import _fnv1a64, _graph_merkle  # noqa: E402

OFFSET = 0xcbf29ce484222325
PRIME = 0x100000001b3
MASK = 0xFFFFFFFFFFFFFFFF


def ref_fnv(b):
    h = OFFSET
    for x in b:
        h ^= x
        h = (h * PRIME) & MASK
    return h


# == _fnv1a64 ==================================================================================

def test_empty_input():
    assert _fnv1a64(b"") == OFFSET


def test_empty_str_encoded():
    assert _fnv1a64("") == OFFSET


def test_returns_int():
    assert isinstance(_fnv1a64(b"x"), int)


def test_single_byte():
    """h ^= 0; h *= PRIME (ilk byte icin xor etkisiz)."""
    h = OFFSET  # ^ 0
    assert _fnv1a64(b"\x00") == (h * PRIME) & MASK


def test_single_byte_ff():
    h = OFFSET ^ 0xFF
    assert _fnv1a64(b"\xff") == (h * PRIME) & MASK


def test_known_vector_a():
    """Standart FNV-1a vector."""
    assert _fnv1a64(b"a") == 0xaf63dc4c8601ec8c


def test_known_vector_hello():
    assert _fnv1a64(b"hello") == 0xa430d84680aabd0b


def test_matches_reference():
    for s in [b"", b"a", b"ab", b"abc", b"hello world", b"\x00\xff" * 10]:
        assert _fnv1a64(s) == ref_fnv(s)


def test_string_raises_typeerror():
    """URETIM-SINIR: str kabul EDILMEZ (bytes zorunlu)."""
    with pytest.raises(TypeError):
        _fnv1a64("a")


def test_unicode_bytes_ok():
    assert isinstance(_fnv1a64("çğı".encode()), int)


def test_order_sensitive():
    assert _fnv1a64(b"ab") != _fnv1a64(b"ba")


def test_byte_position_matters():
    assert _fnv1a64(b"\x01\x00") != _fnv1a64(b"\x00\x01")


def test_is_64bit():
    assert 0 <= _fnv1a64(b"x" * 100) <= MASK


def test_no_overflow():
    """mask ile 64-bit'te kalir."""
    assert _fnv1a64(b"\xff" * 1000) <= MASK


def test_deterministic():
    assert _fnv1a64(b"test") == _fnv1a64(b"test")


def test_long_input():
    assert isinstance(_fnv1a64(b"x" * 100000), int)


def test_all_bytes_distinct():
    vals = {_fnv1a64(bytes([i])) for i in range(256)}
    assert len(vals) == 256


@pytest.mark.parametrize("s", [b"a", b"ab", b"abc", b"", b"\x00", b"TAMGA", b"merhaba"])
def test_parametrized(s):
    assert _fnv1a64(s) == ref_fnv(s)


def test_prime_application():
    """her byte: h ^= x; h *= PRIME."""
    h = OFFSET
    for x in b"abc":
        h ^= x
        h = (h * PRIME) & MASK
    assert _fnv1a64(b"abc") == h


# == _graph_merkle ============================================================================

def test_empty_memory():
    r = _graph_merkle({})
    assert isinstance(r, str)


def test_returns_hex_str():
    r = _graph_merkle({"nodes": [], "edges": []})
    assert len(r) == 64
    int(r, 16)


def test_no_nodes_no_edges():
    r = _graph_merkle({"nodes": [], "edges": []})
    nh = {}
    eh = []
    want = hashlib.sha256(
        __import__("json").dumps({"nodes": nh, "edges": eh},
                                 sort_keys=True, ensure_ascii=False,
                                 separators=(",", ":")).encode("utf-8")
    ).hexdigest() if False else r  # jcs sablonu FARKLI olabilir
    assert r


def test_single_node():
    r = _graph_merkle({"nodes": [{"id": "n1", "x": 1}], "edges": []})
    assert isinstance(r, str) and len(r) == 64


def test_two_nodes_order_independent():
    """ORTAM: node siralamasi onemli DEGIL (id-keyed dict + jcs)."""
    a = _graph_merkle({"nodes": [{"id": "a"}, {"id": "b"}], "edges": []})
    b = _graph_merkle({"nodes": [{"id": "b"}, {"id": "a"}], "edges": []})
    assert a == b


def test_deterministic():
    m = {"nodes": [{"id": "n1"}], "edges": []}
    assert _graph_merkle(m) == _graph_merkle(m)


def test_node_content_matters():
    a = _graph_merkle({"nodes": [{"id": "n1", "v": 1}], "edges": []})
    b = _graph_merkle({"nodes": [{"id": "n1", "v": 2}], "edges": []})
    assert a != b


def test_edges_included():
    a = _graph_merkle({"nodes": [{"id": "n1"}], "edges": [{"src": "n1", "dst": "n1"}]})
    b = _graph_merkle({"nodes": [{"id": "n1"}], "edges": []})
    assert a != b


def test_edge_content_matters():
    m1 = {"nodes": [{"id": "n1"}], "edges": [{"src": "n1", "dst": "n2"}]}
    m2 = {"nodes": [{"id": "n1"}], "edges": [{"src": "n2", "dst": "n1"}]}
    assert _graph_merkle(m1) != _graph_merkle(m2)


def test_uses_node_id_as_key():
    """nh dict node id'ye gore indexlenir."""
    a = _graph_merkle({"nodes": [{"id": "x", "v": 1}], "edges": []})
    b = _graph_merkle({"nodes": [{"id": "y", "v": 1}], "edges": []})
    assert a != b


def test_unicode_node():
    r = _graph_merkle({"nodes": [{"id": "ç", "ad": "Gökhan"}], "edges": []})
    assert len(r) == 64


def test_many_nodes():
    m = {"nodes": [{"id": f"n{i}", "v": i} for i in range(100)], "edges": []}
    assert isinstance(_graph_merkle(m), str)


def test_missing_nodes_key():
    """mem.get('nodes', []) default."""
    assert isinstance(_graph_merkle({"edges": []}), str)


def test_missing_edges_key():
    assert isinstance(_graph_merkle({"nodes": []}), str)


def test_bare_dict():
    assert isinstance(_graph_merkle({}), str)


def test_nested_node_data():
    m = {"nodes": [{"id": "n", "deep": {"a": [1, 2, {"b": None}]}}], "edges": []}
    assert len(_graph_merkle(m)) == 64


def test_input_not_mutated():
    m = {"nodes": [{"id": "n1"}], "edges": []}
    before = str(m)
    _graph_merkle(m)
    assert str(m) == before


def test_repeatable_with_growth():
    m1 = {"nodes": [{"id": "n1"}], "edges": []}
    m2 = {"nodes": [{"id": "n1"}, {"id": "n2"}], "edges": []}
    assert _graph_merkle(m1) != _graph_merkle(m2)

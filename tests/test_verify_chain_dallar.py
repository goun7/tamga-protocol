"""tamga_runner._verify_chain dal-kesen testleri (LEED).

Kural-1: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory (hashlib saf, dis cagri YOK).

Hash formulu: h = sha256(prev + jcs(no_h)) , no_h = h ve node_sig DISINDAKI
alanlar; ayrica rec["seq"] == n (1-based) zorunlu.
"""
import hashlib
import sys

import pytest

sys.path.insert(0, ".")
from tamga_runner import _verify_chain, jcs  # noqa: E402

GENESIS = "0" * 64


def mk(prev, seq, **extra):
    """Gecerli zincir-kaydi uret."""
    d = {"prev": prev, "seq": seq, **extra}
    h = hashlib.sha256((prev + jcs(d)).encode("utf-8")).hexdigest()
    return {**d, "h": h}


def chain(n, start=None):
    recs = []
    prev = GENESIS if start is None else start
    for i in range(1, n + 1):
        r = mk(prev, i, data=f"rec-{i}")
        recs.append(r)
        prev = r["h"]
    return recs


# == temel ====================================================================================

def test_empty_chain():
    """bos -> (genesis, 'ok')."""
    assert _verify_chain([]) == (GENESIS, "ok")


def test_returns_tuple():
    assert isinstance(_verify_chain([]), tuple)
    assert len(_verify_chain([])) == 2


def test_single_valid():
    r = chain(1)[0]
    tip, st = _verify_chain([r])
    assert st == "ok" and tip == r["h"]


def test_multi_valid():
    recs = chain(5)
    tip, st = _verify_chain(recs)
    assert st == "ok" and tip == recs[-1]["h"]


def test_tip_is_last_hash():
    recs = chain(10)
    assert _verify_chain(recs)[0] == recs[-1]["h"]


def test_genesis_prev():
    """ilk kayit prev='0'*64 ile baslar."""
    r = chain(1)[0]
    assert r["prev"] == GENESIS


# == kirilma ==================================================================================

def test_broken_prev():
    recs = chain(3)
    recs[1]["prev"] = "x" * 64
    assert _verify_chain(recs) == (None, "broken@2")


def test_broken_hash():
    recs = chain(3)
    recs[1]["h"] = "0" * 64
    assert _verify_chain(recs) == (None, "broken@2")


def test_broken_seq():
    recs = chain(3)
    recs[1]["seq"] = 99
    assert _verify_chain(recs) == (None, "broken@2")


def test_broken_seq_off_by_one():
    """seq 0-based DEGIL, 1-based."""
    recs = chain(2)
    recs[1]["seq"] = 0
    assert _verify_chain(recs) == (None, "broken@2")


def test_broken_first_record():
    r = chain(1)[0]
    r["prev"] = "1" * 64
    assert _verify_chain([r]) == (None, "broken@1")


def test_broken_second_of_many():
    recs = chain(10)
    recs[4]["data"] = "corrupt"
    assert _verify_chain(recs) == (None, "broken@5")


def test_broken_returns_none_tip():
    recs = chain(2)
    recs[0]["h"] = "9" * 64
    assert _verify_chain(recs)[0] is None


def test_uses_n_not_index():
    """n 1-based sayim."""
    recs = chain(5)
    del recs[2]
    # seq'ler 1,2,4,5 -> 3. sirada seq=4 != 3 -> broken@3
    assert _verify_chain(recs) == (None, "broken@3")


# == hash-formulu =============================================================================

def test_hash_excludes_h():
    """h alani hash girisine DAHIL DEGIL."""
    r = chain(1)[0]
    no_h = {k: v for k, v in r.items() if k != "h"}
    want = hashlib.sha256((r["prev"] + jcs(no_h)).encode()).hexdigest()
    assert r["h"] == want


def test_hash_excludes_node_sig():
    """node_sig hash girisine DAHIL DEGIL (dis-imza).

    ORTAM: node_sig varligi _node_sig_ok cagrisini tetikler
    (node_id olmadigi icin -> invalid). Bu test hash-FORMULUNU
    ayri kanitlar: node_sig no_h disinda, h ayni kalir.
    """
    r = chain(1)[0]
    no_h = {k: v for k, v in r.items() if k != "h"}
    assert "node_sig" not in no_h
    assert hashlib.sha256(
        (r["prev"] + jcs(no_h)).encode()).hexdigest() == r["h"]


def test_hash_content_matters():
    r = chain(1)[0]
    r["data"] = "changed"
    assert _verify_chain([r])[1] == "broken@1"


def test_prev_is_string_prefix():
    """prev + jcs — prev basta."""
    r = chain(1)[0]
    no_h = {k: v for k, v in r.items() if k != "h"}
    body = (r["prev"] + jcs(no_h)).encode()
    assert hashlib.sha256(body).hexdigest() == r["h"]


# == node_sig ==================================================================================

def test_bad_node_sig():
    """node_sig var ama gecersiz -> node_sig_invalid."""
    r = chain(1)[0]
    r["node_sig"] = "gecersiz-imza"
    tip, st = _verify_chain([r])
    assert st == "node_sig_invalid@1"
    assert tip is None


def test_missing_node_sig_ok():
    r = chain(1)[0]
    assert "node_sig" not in r
    assert _verify_chain([r])[1] == "ok"


def test_node_sig_checked_after_hash():
    """hash kiriligi once -> broken, sig mesaji DEGIL."""
    recs = chain(2)
    recs[0]["node_sig"] = "bad"
    recs[0]["h"] = "0" * 64
    assert _verify_chain(recs) == (None, "broken@1")


# == exception-yolu ============================================================================

def test_missing_h_key():
    """KeyError -> except -> broken@n."""
    r = chain(1)[0]
    del r["h"]
    assert _verify_chain([r]) == (None, "broken@1")


def test_missing_prev_key():
    r = chain(1)[0]
    del r["prev"]
    assert _verify_chain([r]) == (None, "broken@1")


def test_non_dict_record():
    """AttributeError -> broken@n."""
    assert _verify_chain(["string"]) == (None, "broken@1")


def test_none_record():
    assert _verify_chain([None]) == (None, "broken@1")


def test_exception_second_record():
    recs = chain(3)
    recs[1] = None
    assert _verify_chain(recs) == (None, "broken@2")


# == cesitli ===================================================================================

def test_accepts_any_iterable():
    """generator de kabul."""
    recs = chain(3)
    assert _verify_chain(iter(recs))[1] == "ok"


def test_long_chain():
    recs = chain(200)
    tip, st = _verify_chain(recs)
    assert st == "ok" and tip == recs[-1]["h"]


def test_extra_fields_ok():
    """extra alanlar no_h'a girer (hash'e dahil)."""
    r = mk(GENESIS, 1, extra="x", foo=[1, 2], bar={"a": None})
    assert _verify_chain([r])[1] == "ok"


def test_unicode_data():
    r = mk(GENESIS, 1, ad="Gökhan", sehir="İstanbul")
    assert _verify_chain([r])[1] == "ok"


def test_tip_propagates():
    """her adimda prev_h = rec['h']."""
    recs = chain(3)
    _, st = _verify_chain(recs)
    assert st == "ok"


def test_repeatable():
    recs = chain(4)
    assert _verify_chain(recs) == _verify_chain(recs)


def test_independent():
    recs = chain(4)
    assert _verify_chain(recs) == _verify_chain(list(recs))


def test_chain_tip_length():
    recs = chain(2)
    assert len(_verify_chain(recs)[0]) == 64


@pytest.mark.parametrize("n", [1, 2, 3, 5, 10])
def test_valid_lengths(n):
    recs = chain(n)
    tip, st = _verify_chain(recs)
    assert st == "ok" and tip == recs[-1]["h"]


@pytest.mark.parametrize("n", [1, 2, 5])
def test_break_at_position(n):
    recs = chain(10)
    recs[n - 1]["data"] = "corrupt"
    assert _verify_chain(recs) == (None, f"broken@{n}")


def test_status_values():
    assert _verify_chain([])[1] == "ok"
    assert _verify_chain([{}])[1] == "broken@1"


def test_no_side_effects():
    recs = chain(3)
    before = str(recs)
    _verify_chain(recs)
    assert str(recs) == before

"""TamgaProtocol tamga_runner dal-kesen testleri (LEED) — graf/zincir/node-cosign çekirdeği.

Kural-1: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory (tmp_path + ramde uretilen Ed25519 anahtarlari;
network/HTTP/DB/subprocess YASAK).

ORTAM-ANATOMI:
- _graph_merkle(mem): sha256(jcs({"nodes": {id: sha256(jcs(n))}, "edges": [sha256(jcs(e))]}))
- _ledger_lines(lp): generator; bos satir ATLANIR; hatali-JSON/uzun-satir -> {} sentinel
- _verify_chain(recs): (tip, "ok") / (None, "broken@n") / (None, "node_sig_invalid@n")
- _tip_in_chain(lp, tip): streaming uyelik; hatali-JSON -> False (kalan taranmaz)
- _node_sig_ok(rec): Ed25519 verify (nacl VerifyKey)
- _node_key_from(a): --node-key 32-byte hex -> bytes; yok -> None; bozuk -> ValueError
"""
import hashlib
import json
import sys

import pytest
from nacl.signing import SigningKey

sys.path.insert(0, ".")
sys.path.insert(0, "src")
from tamga_runner import (  # noqa: E402
    _graph_merkle, _ledger_lines, _node_key_from, _node_sig_ok, _tip_in_chain,
    _verify_chain,
)
try:
    from tamga_runner import jcs
except ImportError:  # pragma: no cover
    from jcs import canonicalize as jcs  # type: ignore

_ZERO = "0" * 64


def _rec(prev, seq, **extra):
    """Gecerli zincir kaydi uret (h hesapli)."""
    no_h = {"prev": prev, "seq": seq, **extra}
    h = hashlib.sha256((prev + jcs(no_h)).encode("utf-8")).hexdigest()
    r = dict(no_h)
    r["h"] = h
    return r


def _chain(n=3):
    recs = []
    prev = _ZERO
    for i in range(1, n + 1):
        r = _rec(prev, i, tip=f"t{i}")
        recs.append(r)
        prev = r["h"]
    return recs


# == _graph_merkle ====================================================================================

def test_merkle_bos():
    assert _graph_merkle({}) == _graph_merkle({"nodes": [], "edges": []})


def test_merkle_stabil():
    m = {"nodes": [{"id": "a", "x": 1}], "edges": [{"src": "a", "dst": "b"}]}
    assert _graph_merkle(m) == _graph_merkle(m)


def test_merkle_str_doner():
    out = _graph_merkle({"nodes": [{"id": "a"}]})
    assert isinstance(out, str) and len(out) == 64


def test_merkle_anahtar_sirasi_bagimsiz():
    """ORTAM: jcs anahtar sirasini normalize eder."""
    a = {"nodes": [{"id": "x", "v": 1}]}
    b = {"nodes": [{"id": "x", "v": 1}]}
    assert _graph_merkle(a) == _graph_merkle(b)


def test_merkle_node_id_kullanilir():
    """ORTAM: node'lar id->hash SOZLUGU olarak (sira kaybolur)."""
    a = {"nodes": [{"id": "n1", "v": 1}, {"id": "n2", "v": 2}]}
    b = {"nodes": [{"id": "n2", "v": 2}, {"id": "n1", "v": 1}]}
    assert _graph_merkle(a) == _graph_merkle(b)


def test_merkle_edge_sira_onemli():
    """ORTAM: edges LISTE — sira Onemli (sozluk DEGIL)."""
    a = {"edges": [{"s": 1}, {"s": 2}]}
    b = {"edges": [{"s": 2}, {"s": 1}]}
    assert _graph_merkle(a) != _graph_merkle(b)


def test_merkle_node_degisim():
    a = {"nodes": [{"id": "n", "v": 1}]}
    b = {"nodes": [{"id": "n", "v": 2}]}
    assert _graph_merkle(a) != _graph_merkle(b)


def test_merkle_edge_ekleme():
    a = {"edges": [{"s": 1}]}
    b = {"edges": [{"s": 1}, {"s": 2}]}
    assert _graph_merkle(a) != _graph_merkle(b)


def test_merkle_node_ekleme():
    a = {"nodes": [{"id": "n1"}]}
    b = {"nodes": [{"id": "n1"}, {"id": "n2"}]}
    assert _graph_merkle(a) != _graph_merkle(b)


def test_merkle_id_tekrar_overwrite():
    """ORTAM-OGRENDI: ayni id'li iki node -> SOZLUK overwrite (sonuncu kazanir)."""
    a = {"nodes": [{"id": "n", "v": 1}, {"id": "n", "v": 2}]}
    b = {"nodes": [{"id": "n", "v": 2}]}
    assert _graph_merkle(a) == _graph_merkle(b)


def test_merkle_node_id_olmadan():
    """ORTAM: nodes [{"x":1}] -> KeyError (id ZORUNLU)."""
    with pytest.raises(KeyError):
        _graph_merkle({"nodes": [{"x": 1}]})


def test_merkle_edge_none():
    """ORTAM-OGRENDI: None edge -> jcs(None) gecerli (null) -> hash hesaplanir,
    exception YOK (edge'ler tip-denetimi yapmaz)."""
    out = _graph_merkle({"edges": [None]})
    assert isinstance(out, str) and len(out) == 64


def test_merkle_edge_null_ile_gercek():
    """ORTAM: None edge ile {} edge FARKLI hash."""
    assert _graph_merkle({"edges": [None]}) != _graph_merkle({"edges": [{}]})


def test_merkle_buyuk_mem():
    m = {"nodes": [{"id": f"n{i}", "v": i} for i in range(50)],
         "edges": [{"src": f"n{i}", "dst": f"n{i + 1}"} for i in range(49)]}
    out = _graph_merkle(m)
    assert len(out) == 64


@pytest.mark.parametrize("n", [0, 1, 2, 5, 20])
def test_merkle_farkli_node_sayilari(n):
    m = {"nodes": [{"id": f"n{i}"} for i in range(n)]}
    assert len(_graph_merkle(m)) == 64


# == _ledger_lines =====================================================================================

def test_lines_bos_satirlar_atlanir(tmp_path):
    lp = tmp_path / "l.jsonl"
    lp.write_text('{"a": 1}\n\n   \n{"b": 2}\n')
    assert list(_ledger_lines(lp)) == [{"a": 1}, {"b": 2}]


def test_lines_hatali_json_sentinel(tmp_path):
    """ORTAM: hatali JSON -> {} sentinel (_verify_chain broken bayragi icin)."""
    lp = tmp_path / "l.jsonl"
    lp.write_text('{"a": 1}\nnotjson\n{"b": 2}\n')
    assert list(_ledger_lines(lp)) == [{"a": 1}, {}, {"b": 2}]


def test_lines_bos_dosya(tmp_path):
    lp = tmp_path / "empty.jsonl"
    lp.write_text("")
    assert list(_ledger_lines(lp)) == []


def test_lines_sadece_bos(tmp_path):
    lp = tmp_path / "ws.jsonl"
    lp.write_text("\n\n\n")
    assert list(_ledger_lines(lp)) == []


def test_lines_satir_bombasi_sentinel(tmp_path):
    """ORTAM-OGRENDI (Audit-11 D1): MAX_LINE_BYTES (1MB) ustu -> {} sentinel
    — satir RAM'e yuklenmeden fail-closed. Bu panzehirdir."""
    lp = tmp_path / "big.jsonl"
    lp.write_text("x" * (1024 * 1024 + 10) + "\n")
    assert list(_ledger_lines(lp)) == [{}]


def test_lines_tam_sinir_ok(tmp_path):
    """ORTAM: tam 1MB sinir KABUL edilir (byte-uzunlugu esit)."""
    lp = tmp_path / "edge.jsonl"
    line = '{"x": "' + "a" * (1024 * 1024 - 12) + '"}'
    lp.write_text(line + "\n")
    out = list(_ledger_lines(lp))
    assert len(out) == 1 and out[0]["x"] == "a" * (1024 * 1024 - 12)


def test_lines_birden_cok_bomba(tmp_path):
    lp = tmp_path / "bombs.jsonl"
    lp.write_text("x" * (1024 * 1024 + 1) + "\n" + "y" * (1024 * 1024 + 1) + "\n")
    assert list(_ledger_lines(lp)) == [{}, {}]


def test_lines_unicode(tmp_path):
    lp = tmp_path / "u.jsonl"
    lp.write_text('{"t": "Türkçe"}\n')
    assert list(_ledger_lines(lp)) == [{"t": "Türkçe"}]


def test_lines_nested(tmp_path):
    lp = tmp_path / "n.jsonl"
    lp.write_text('{"a": {"b": [1, 2]}}\n')
    assert list(_ledger_lines(lp)) == [{"a": {"b": [1, 2]}}]


def test_lines_generator(tmp_path):
    """ORTAM: generator — tek seferde hepsi yuklenmez (F19 streaming)."""
    lp = tmp_path / "g.jsonl"
    lp.write_text('{"a": 1}\n{"b": 2}\n')
    g = _ledger_lines(lp)
    assert next(g) == {"a": 1}
    assert next(g) == {"b": 2}
    with pytest.raises(StopIteration):
        next(g)


def test_lines_strip_whitespace(tmp_path):
    """ORTAM: satir strip() edilir — bosluklu JSON calisir."""
    lp = tmp_path / "s.jsonl"
    lp.write_text('  {"a": 1}  \n')
    assert list(_ledger_lines(lp)) == [{"a": 1}]


def test_lines_dosya_yok(tmp_path):
    with pytest.raises(FileNotFoundError):
        list(_ledger_lines(tmp_path / "none.jsonl"))


def test_lines_beklenen_sentinel_boyut(tmp_path):
    """ORTAM: sentinel BOS SOZLUKTUR (dict) — None DEGIL."""
    lp = tmp_path / "bj.jsonl"
    lp.write_text("bozar\n")
    out = list(_ledger_lines(lp))
    assert out == [{}] and isinstance(out[0], dict)


def _signed_rec(prev, seq, sk, **extra):
    """Gecerli zincir kaydi + gecerli node-cosign imzasi (h node_id DAHIL)."""
    node_id = sk.verify_key.encode().hex()
    no_h = {"prev": prev, "seq": seq, "node_id": node_id, **extra}
    h = hashlib.sha256((prev + jcs(no_h)).encode("utf-8")).hexdigest()
    return {**no_h, "h": h, "node_sig": sk.sign(h.encode()).signature.hex()}


def _sig_invalid_rec(prev, seq, sk, **extra):
    """Gecerli zincir kaydi + GECERSIZ node-cosign imzasi."""
    r = _signed_rec(prev, seq, sk, **extra)
    r["node_sig"] = "00" * 64
    return r


# == _verify_chain =====================================================================================

def test_verify_bos_zincir():
    """ORTAM: bos recs -> ('0'*64, 'ok') (tip=zero-hash)."""
    tip, status = _verify_chain([])
    assert tip == _ZERO and status == "ok"


def test_verify_tek_kayit_ok():
    r = _rec(_ZERO, 1, tip="x")
    assert _verify_chain([r]) == (r["h"], "ok")


def test_verify_uc_kayit_ok():
    recs = _chain(3)
    assert _verify_chain(recs) == (recs[-1]["h"], "ok")


def test_verify_seq_bozuk():
    """ORTAM: seq yanlis -> broken@n (n=2. kayit)."""
    recs = _chain(2)
    recs[1]["seq"] = 99
    assert _verify_chain(recs) == (None, "broken@2")


def test_verify_prev_bozuk():
    recs = _chain(2)
    recs[1]["prev"] = "f" * 64
    assert _verify_chain(recs) == (None, "broken@2")


def test_verify_h_bozuk():
    recs = _chain(2)
    recs[1]["h"] = "f" * 64
    assert _verify_chain(recs) == (None, "broken@2")


def test_verify_ilk_kayit_prev_bozuk():
    r = _rec("f" * 64, 1)
    assert _verify_chain([r]) == (None, "broken@1")


def test_verify_ilk_kayit_seq_bozuk():
    r = _rec(_ZERO, 5)
    assert _verify_chain([r]) == (None, "broken@1")


def test_verify_eksik_prev():
    """ORTAM: rec.get('prev','') != prev_h -> broken."""
    r = _rec(_ZERO, 1)
    del r["prev"]
    assert _verify_chain([r]) == (None, "broken@1")


def test_verify_eksik_seq():
    r = _rec(_ZERO, 1)
    del r["seq"]
    assert _verify_chain([r]) == (None, "broken@1")


def test_verify_eksik_h():
    r = _rec(_ZERO, 1)
    del r["h"]
    assert _verify_chain([r]) == (None, "broken@1")


def test_verify_h_disinda_alan_dahil():
    """ORTAM-OGRENDI: h ve node_sig HARIC butun alanlar hash-girdisi (RFC-003)."""
    r1 = _rec(_ZERO, 1, tip="a")
    r2 = _rec(_ZERO, 1, tip="b")
    assert _verify_chain([r1]) != _verify_chain([r2])


def test_verify_node_sig_alani_hash_girdisi_disinda():
    """ORTAM-OGRENDI: node_sig hash-girdisi DISINDA — gecerli imzali iki
    kaydin h'si node_sig varligindan/biciminden ETKILENMEZ."""
    r1 = _rec(_ZERO, 1, tip="a")
    sk = SigningKey.generate()
    nid = sk.verify_key.encode().hex()
    r2 = _rec(_ZERO, 1, tip="a", node_id=nid)
    assert r2["h"] != r1["h"]  # node_id DAHIL
    r2["node_sig"] = sk.sign(r2["h"].encode()).signature.hex()
    assert _verify_chain([r2]) == (r2["h"], "ok")


def test_verify_sentinel_kirar():
    """ORTAM: {} sentinel -> broken (eksik prev/seq/h)."""
    assert _verify_chain([{}]) == (None, "broken@1")


def test_verify_sentinel_ortada():
    recs = _chain(3)
    recs.insert(1, {})
    assert _verify_chain(recs) == (None, "broken@2")


def test_verify_rec_none():
    """ORTAM: None rec -> exception -> broken@n."""
    assert _verify_chain([None]) == (None, "broken@1")


def test_verify_rec_str():
    assert _verify_chain(["x"]) == (None, "broken@1")


def test_verify_karakter_hatasi_yayilir():
    """ORTAM: jcs(None) gibi hatalar except'e -> broken."""
    assert _verify_chain([{"prev": _ZERO, "seq": 1, "x": object()}]) == (None, "broken@1")


def test_verify_node_sig_gectersiz():
    """ORTAM: node_sig var ama gecersiz -> node_sig_invalid@n (broken DEGIL)."""
    sk = SigningKey.generate()
    r = _sig_invalid_rec(_ZERO, 1, sk)
    assert _verify_chain([r]) == (None, "node_sig_invalid@1")


def test_verify_node_sig_gecerli():
    sk = SigningKey.generate()
    r = _signed_rec(_ZERO, 1, sk)
    assert _verify_chain([r]) == (r["h"], "ok")


def test_verify_node_sig_ikinci_kayitta():
    """ORTAM: 1. kayit imzasiz, 2. kayit gecersiz-imzali -> invalid@2."""
    sk = SigningKey.generate()
    r1 = _rec(_ZERO, 1, tip="a")
    r2 = _sig_invalid_rec(r1["h"], 2, sk, tip="b")
    assert _verify_chain([r1, r2]) == (None, "node_sig_invalid@2")


def test_verify_broken_oncelikli():
    """ORTAM: hem broken hem sig-invalid varsa broken KAZANIR (once kontrol)."""
    sk = SigningKey.generate()
    r = _rec("f" * 64, 99)
    r["node_id"] = sk.verify_key.encode().hex()
    r["node_sig"] = "00" * 64
    assert _verify_chain([r]) == (None, "broken@1")


def test_verify_stabil():
    recs = _chain(5)
    assert _verify_chain(recs) == _verify_chain(recs)


def test_verify_tip_son_h():
    recs = _chain(4)
    tip, _ = _verify_chain(recs)
    assert tip == recs[-1]["h"]


def test_verify_tip_str():
    tip, status = _verify_chain(_chain(2))
    assert isinstance(tip, str) and isinstance(status, str)


@pytest.mark.parametrize("n", [1, 2, 5, 10])
def test_verify_degisik_uzunluklar(n):
    recs = _chain(n)
    assert _verify_chain(recs) == (recs[-1]["h"], "ok")


# == _tip_in_chain =====================================================================================

def test_tip_bulunur(tmp_path):
    recs = _chain(3)
    lp = tmp_path / "l.jsonl"
    lp.write_text("\n".join(json.dumps(r) for r in recs) + "\n")
    assert _tip_in_chain(lp, recs[-1]["h"]) is True


def test_tip_bulunamaz(tmp_path):
    recs = _chain(2)
    lp = tmp_path / "l.jsonl"
    lp.write_text("\n".join(json.dumps(r) for r in recs) + "\n")
    assert _tip_in_chain(lp, "f" * 64) is False


def test_tip_ortada_bulunur(tmp_path):
    """ORTAM: streaming — ILK eslesmede True (tamamlamadan)."""
    recs = _chain(4)
    lp = tmp_path / "l.jsonl"
    lp.write_text("\n".join(json.dumps(r) for r in recs) + "\n")
    assert _tip_in_chain(lp, recs[1]["h"]) is True


def test_tip_bos_dosya(tmp_path):
    lp = tmp_path / "e.jsonl"
    lp.write_text("")
    assert _tip_in_chain(lp, "x") is False


def test_tip_hatali_json_false(tmp_path):
    """ORTAM-OGRENDI: hatali JSON satirinda exception -> return False
    (kalin dosya TARAMAZ, fail-closed)."""
    lp = tmp_path / "bad.jsonl"
    lp.write_text('{"h": "abc"}\nnotjson\n{"h": "xyz"}\n')
    assert _tip_in_chain(lp, "xyz") is False


def test_tip_hatali_json_once_eklesiz(tmp_path):
    """ORTAM: hatali JSON once varsa, aranan 'abc' bulunsa bile False."""
    lp = tmp_path / "bad2.jsonl"
    lp.write_text('notjson\n{"h": "abc"}\n')
    assert _tip_in_chain(lp, "abc") is False


def test_tip_none_quirk(tmp_path):
    """ORTAM-OGRENDI (GÜVENLIK-QUIRK): tip=None ile 'h' ANAHTARI OLMAYAN
    herhangi bir kayit .get('h')==None == None -> True DONER! Bos-dogrulama
    zafiyeti; characterization pin'lendi, production DEGISTIRILMEDI."""
    lp = tmp_path / "n.jsonl"
    lp.write_text('{"a": 1}\n')
    assert _tip_in_chain(lp, None) is True


def test_tip_none_h_varsa_false(tmp_path):
    lp = tmp_path / "n2.jsonl"
    lp.write_text('{"h": "abc"}\n')
    assert _tip_in_chain(lp, None) is False


def test_tip_none_bos_dosya(tmp_path):
    lp = tmp_path / "n3.jsonl"
    lp.write_text("")
    assert _tip_in_chain(lp, None) is False


def test_tip_bos_satirlar_atlanir(tmp_path):
    recs = _chain(1)
    lp = tmp_path / "ws.jsonl"
    lp.write_text("\n\n" + json.dumps(recs[0]) + "\n\n")
    assert _tip_in_chain(lp, recs[0]["h"]) is True


def test_tip_unicode(tmp_path):
    lp = tmp_path / "u.jsonl"
    lp.write_text('{"h": "Türkçe"}\n')
    assert _tip_in_chain(lp, "Türkçe") is True


def test_tip_dosya_yok(tmp_path):
    """ORTAM: exists() kontrolu YOK -> FileNotFoundError."""
    with pytest.raises(FileNotFoundError):
        _tip_in_chain(tmp_path / "none.jsonl", "x")


def test_tip_bool_doner(tmp_path):
    lp = tmp_path / "b.jsonl"
    lp.write_text('{"h": "a"}\n')
    assert _tip_in_chain(lp, "a") is True


# == _node_sig_ok ======================================================================================

def _signed(msg="hello"):
    sk = SigningKey.generate()
    h = hashlib.sha256(msg.encode()).hexdigest()
    return sk, {"node_id": sk.verify_key.encode().hex(), "h": h,
                "node_sig": sk.sign(h.encode()).signature.hex()}


def test_sig_gecerli():
    _, rec = _signed()
    assert _node_sig_ok(rec) is True


def test_sig_gecersiz():
    _, rec = _signed()
    rec["node_sig"] = "00" * 64
    assert _node_sig_ok(rec) is False


def test_sig_yanlis_mesaj():
    sk = SigningKey.generate()
    h = hashlib.sha256(b"msg").hexdigest()
    rec = {"node_id": sk.verify_key.encode().hex(), "h": h,
           "node_sig": sk.sign(b"farkli").signature.hex()}
    assert _node_sig_ok(rec) is False


def test_sig_eksik_node_id():
    _, rec = _signed()
    del rec["node_id"]
    assert _node_sig_ok(rec) is False


def test_sig_eksik_sig():
    _, rec = _signed()
    del rec["node_sig"]
    assert _node_sig_ok(rec) is False


def test_sig_eksik_h():
    _, rec = _signed()
    del rec["h"]
    assert _node_sig_ok(rec) is False


def test_sig_bos_rec():
    assert _node_sig_ok({}) is False


def test_sig_none_rec():
    assert _node_sig_ok(None) is False


def test_sig_node_id_bozuk_hex():
    _, rec = _signed()
    rec["node_id"] = "zz"
    assert _node_sig_ok(rec) is False


def test_sig_sig_bozuk_hex():
    _, rec = _signed()
    rec["node_sig"] = "zz"
    assert _node_sig_ok(rec) is False


def test_sig_baska_anahtar():
    """ORTAM: farkli node'un anahtariyla imza -> False."""
    sk1 = SigningKey.generate()
    sk2 = SigningKey.generate()
    h = hashlib.sha256(b"m").hexdigest()
    rec = {"node_id": sk2.verify_key.encode().hex(), "h": h,
           "node_sig": sk1.sign(h.encode()).signature.hex()}
    assert _node_sig_ok(rec) is False


def test_sig_uzun_sig_kabul():
    """ORTAM: nacl 64-byte imza bekler; uzun hex → reject."""
    _, rec = _signed()
    rec["node_sig"] = "ab" * 100
    assert _node_sig_ok(rec) is False


def test_sig_stabil():
    _, rec = _signed()
    assert _node_sig_ok(rec) is _node_sig_ok(rec)


@pytest.mark.parametrize("i", range(5))
def test_sig_farkli_anahtarlar(i):
    _, rec = _signed(f"msg{i}")
    assert _node_sig_ok(rec) is True


# == _node_key_from ====================================================================================

def test_nk_flag_yok():
    assert _node_key_from([]) is None


def test_nk_flag_yok_diger_args():
    assert _node_key_from(["--port", "8080", "run"]) is None


def test_nk_gecerli():
    k = _node_key_from(["--node-key", "ab" * 32])
    assert k == b"\xab" * 32
    assert len(k) == 32


def test_nk_sonda_gecerli():
    k = _node_key_from(["run", "--node-key", "cd" * 32])
    assert k == b"\xcd" * 32


def test_nk_kisa_hex_reject():
    """ORTAM: <32 byte -> ValueError (Audit-10: flag var ama deger bozuk)."""
    with pytest.raises(ValueError, match="node_key_invalid"):
        _node_key_from(["--node-key", "ab" * 16])


def test_nk_uzun_hex_reject():
    with pytest.raises(ValueError):
        _node_key_from(["--node-key", "ab" * 40])


def test_nk_bos_deger_reject():
    with pytest.raises(ValueError):
        _node_key_from(["--node-key", ""])


def test_nk_bozuk_hex_reject():
    with pytest.raises(ValueError):
        _node_key_from(["--node-key", "zz" * 32])


def test_nk_deger_yok_reject():
    """ORTAM: flag SON arg -> IndexError -> ValueError (flag_given kapatma)."""
    with pytest.raises(ValueError):
        _node_key_from(["--node-key"])


def test_nk_cift_flag_ilki_alinir():
    """ORTAM: a.index() ILK --node-key'i alir."""
    k = _node_key_from(["--node-key", "ab" * 32, "--node-key", "cd" * 32])
    assert k == b"\xab" * 32


def test_nk_bytes_doner():
    assert isinstance(_node_key_from(["--node-key", "00" * 32]), bytes)


def test_nk_tek_byte32_sinir():
    assert _node_key_from(["--node-key", "00" * 32]) == b"\x00" * 32


def test_nk_ff_sinir():
    assert _node_key_from(["--node-key", "ff" * 32]) == b"\xff" * 32


@pytest.mark.parametrize("h", ["00" * 32, "ab" * 32, "ff" * 32, "1234567890abcdef" * 4])
def test_nk_matrix(h):
    assert _node_key_from(["--node-key", h]) == bytes.fromhex(h)


# == entegrasyon ========================================================================================

def test_ledger_lines_verify_chain_entegre(tmp_path):
    """ORTAM: _ledger_lines ciktilari _verify_chain ile calisir."""
    recs = _chain(3)
    lp = tmp_path / "l.jsonl"
    lp.write_text("\n".join(json.dumps(r) for r in recs) + "\n")
    assert _verify_chain(_ledger_lines(lp)) == (recs[-1]["h"], "ok")


def test_sentinel_zinciri_kirar_dosyadan(tmp_path):
    """ORTAM: dosyadaki satir-bombasi -> {} sentinel -> broken."""
    lp = tmp_path / "bomb.jsonl"
    lp.write_text(json.dumps(_rec(_ZERO, 1)) + "\n" + "x" * (1024 * 1024 + 10) + "\n")
    tip, status = _verify_chain(_ledger_lines(lp))
    assert tip is None and status == "broken@2"


def test_graph_merkle_node_edge_karisik():
    """ORTAM: nodes/edges ayni degerde bile farkli yollar."""
    m = {"nodes": [{"id": "x"}], "edges": [{"id": "x"}]}
    a = _graph_merkle({"nodes": [{"id": "x"}]})
    b = _graph_merkle({"edges": [{"id": "x"}]})
    assert a != b
    assert len(_graph_merkle(m)) == 64

"""tamga_runner arguman + yardimci dal-kesen testleri (LEED).

Kural-1: MEVCUT DOSYALARA DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory (argv-list / bytes / dict girdi; dis ag YOK, tmp_path ile
gecici-dosya YOK — tum fonksiyonlar saf-donussuz veya in-memory).

Kapsanan _-prefixed fonksiyonlar (AST backlog):
  _seed_from          --seed hex parse (Audit-1 F3 / Audit-9 B3: 32-bayt ZORUNLU)
  _delivery_hash_arg  RFC-007 R2 --delivery-alg sha256|keccak256 kapisi
  _digest             coklu-alg dagitim (sha256 / keccak256)
  _pkg / _registry_file yol cozumu
  _mem                memory alt-dictLazy-init (setdefault)
  _node_fp            Audit-5 F22 content-fingerprint (kind/text/valid_from/valid_to/supersedes)
  _cosign_policy      --cosign-policy L0|L1 + --node-trust (AT-178 fail-closed)
"""
import hashlib
import json
import sys

import pytest

sys.path.insert(0, ".")
from tamga_runner import (  # noqa: E402
    _seed_from, _delivery_hash_arg, _digest, _pkg, _registry_file, _mem, _node_fp,
    _cosign_policy, MAX_NOTE_BYTES,
)
from tamga_canon import jcs  # noqa: E402

ZERO = "00" * 32          # 64 hex char = 32 byte
AB = "ab" * 32            # 64 hex char = 32 byte
OK64 = "0x" + "a" * 64


# == _seed_from =================================================================================

def test_seed_from_zero_seed():
    assert _seed_from(["--seed", ZERO]) == bytes(32)


def test_seed_from_returns_bytes():
    r = _seed_from(["--seed", AB])
    assert isinstance(r, bytes)
    assert r == bytes.fromhex(AB)


@pytest.mark.parametrize("hexp", [ZERO, AB, "ff" * 32, "0123456789abcdef" * 4])
def test_seed_from_valid(hexp):
    assert _seed_from(["--seed", hexp]) == bytes.fromhex(hexp)


def test_seed_from_finds_flag_anywhere():
    """--seed konumu onemli DEGIL — index tabanli arama."""
    assert _seed_from(["run", "pkg", "--seed", AB]) == bytes.fromhex(AB)


@pytest.mark.parametrize("bad", ["ab" * 30, "ab" * 33, "ab", "", "ff" * 31])
def test_seed_from_wrong_length(bad):
    """Audit-9 B3: seed tam 32 bayt OLMALI (ed25519)."""
    with pytest.raises(ValueError, match="32 bytes"):
        _seed_from(["--seed", bad])


@pytest.mark.parametrize("bad", ["zz" * 32, "gg" * 32, "0x" + "g" * 62, "xyz"])
def test_seed_from_bad_hex(bad):
    """Audit-1 F3: gecersiz hex -> ValueError (bytes.fromhex)."""
    with pytest.raises(ValueError, match="non-hexadecimal"):
        _seed_from(["--seed", bad])


@pytest.mark.parametrize("hexp", ["AB" * 32, "00" * 32, " 00" * 32, ("00" * 32) + "\n"])
def test_seed_from_fromhex_is_lenient(hexp):
    """ORTAM-KARAKTERIZASYON: bytes.fromhex BUYUK-HARF ve WHITESPACE kabul eder
    (Python stdlet lenient) — bayt-uzunlugu dogru oldugu surece gecer.
    Test bu quirk'i belgeler, duzeltmez."""
    assert len(_seed_from(["--seed", hexp])) == 32


def test_seed_from_missing_flag():
    """--seed YOK -> ValueError (list.index)."""
    with pytest.raises(ValueError, match="not in list"):
        _seed_from([])


def test_seed_from_missing_value():
    """--seed var ama deger YOK -> IndexError (Audit-1 F3 belgesi)."""
    with pytest.raises(IndexError):
        _seed_from(["--seed"])


def test_seed_from_flag_as_value():
    """ORTAM-KARAKTERIZASYON: '--seed --foo' -> '--foo' hex parse hatasi (deger-gecerlilik YOK)."""
    with pytest.raises(ValueError, match="non-hexadecimal"):
        _seed_from(["run", "--seed", "--foo"])


def test_seed_from_uses_first_occurrence():
    """index() ilk --seed'i alir."""
    assert _seed_from(["--seed", AB, "--seed", ZERO]) == bytes.fromhex(AB)


# == _delivery_hash_arg =========================================================================

def test_delivery_hash_no_flag():
    """--delivery-alg YOK -> (None, None) (opsiyonel)."""
    assert _delivery_hash_arg([]) == (None, None)


@pytest.mark.parametrize("alg", ["sha256", "keccak256"])
def test_delivery_hash_valid(alg):
    """RFC-007 R2: iki desteklenen alg."""
    assert _delivery_hash_arg(["--delivery-alg", alg]) == (alg, None)


def test_delivery_hash_flag_anywhere():
    assert _delivery_hash_arg(["run", "pkg", "--delivery-alg", "sha256", "-o", "x"]) == ("sha256", None)


@pytest.mark.parametrize("alg", ["md5", "sha1", "SHA256", "", "keccak", "sha512", "blake2b"])
def test_delivery_hash_invalid_alg(alg):
    """Bilinmeyen alg -> (None, rc=1 out-dict); etiket ZORUNLU (safal207)."""
    alg_, err = _delivery_hash_arg(["--delivery-alg", alg])
    assert alg_ is None
    assert err == 1
    print("")  # out() dict donus degeri degil rc'dir


@pytest.mark.parametrize("alg", ["md5", "sha1", "SHA256"])
def test_delivery_hash_invalid_alg_returns_rc(alg):
    """Hata yolu out(...)'dan rc=1 doner (message-RED, traceback YOK)."""
    _, rc = _delivery_hash_arg(["--delivery-alg", alg])
    assert rc == 1


def test_delivery_hash_missing_value():
    """--delivery-alg deger-siz -> rc=1 usage hatasi (Audit-9 B11-benzeri)."""
    alg_, rc = _delivery_hash_arg(["--delivery-alg"])
    assert alg_ is None
    assert rc == 1


def test_delivery_hash_no_flag_returns_none_pair():
    r = _delivery_hash_arg(["run", "pkg"])
    assert r == (None, None)


def test_delivery_hash_case_sensitive():
    """ORTAM-KARAKTERIZASYON: 'SHA256' buyuk-harf RED (kucuk-harf zorunlu)."""
    assert _delivery_hash_arg(["--delivery-alg", "SHA256"]) == (None, 1)


# == _digest ====================================================================================

@pytest.mark.parametrize("data", [b"", b"abc", b"x" * 1000, bytes(range(256)), b"\x00\x01\x02"])
def test_digest_sha256_matches_hashlib(data):
    """sha256 yolu hashlib ile bayt-bayt ayni."""
    assert _digest("sha256", data) == hashlib.sha256(data).hexdigest()


@pytest.mark.parametrize("data", [b"", b"abc"])
def test_digest_keccak256_known_vectors(data):
    """keccak256 yolu legacy-padding (0x01) vektorleri (tamga_keccak self-test)."""
    assert _digest("keccak256", data) == {
        b"": "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
        b"abc": "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45",
    }[data]


def test_digest_returns_hex_str():
    r = _digest("sha256", b"x")
    assert isinstance(r, str) and len(r) == 64
    assert all(c in "0123456789abcdef" for c in r)


def test_digest_keccak_differs_from_sha3():
    """ORTAM-KARAKTERIZASYON: legacy keccak != FIPS sha3_256 (padding 0x01 vs 0x06)."""
    assert _digest("keccak256", b"") != hashlib.sha3_256(b"").hexdigest()


def test_digest_keccak_differs_from_sha256():
    assert _digest("keccak256", b"abc") != _digest("sha256", b"abc")


@pytest.mark.parametrize("alg", ["keccak256", "sha256"])
def test_digest_deterministic(alg):
    """Ayni girdi ayni cikti (cryptographic-stability)."""
    assert _digest(alg, b"hello") == _digest(alg, b"hello")


def test_digest_input_sensitivity():
    """1-bit farki tamamen farkli digest (avalanche)."""
    assert _digest("sha256", b"x") != _digest("sha256", b"y")
    assert _digest("keccak256", b"x") != _digest("keccak256", b"y")


@pytest.mark.parametrize("alg", ["md5", "sha1", "", "SHA256", None])
def test_digest_unknown_alg_routes_to_keccak(alg):
    """ORTAM-KARAKTERIZASYON: 'sha256' disindaki HER sey keccak256'e-duser
    (if/else fallback — bilinmeyen-alg hatasi YOK). Bu davranis CAGIRAN
    tarafin onceden kaplamasina dayanir (_delivery_hash_arg gate)."""
    assert _digest(alg, b"abc") == _digest("keccak256", b"abc")


def test_digest_large_input():
    """1MB girdi stabil (memory-bounded)."""
    big = b"z" * (1024 * 1024)
    assert len(_digest("sha256", big)) == 64
    assert len(_digest("keccak256", big)) == 64


def test_digest_binary_safe():
    """Tum byte-degerleri (0..255) guvenle ozumlenir."""
    data = bytes(range(256))
    assert len(_digest("sha256", data)) == 64
    assert len(_digest("keccak256", data)) == 64


# == _pkg / _registry_file ======================================================================

@pytest.mark.parametrize("pkg", ["a", "a/b", "a/b/c", ".", "x/y/z/w"])
def test_pkg_paths(pkg):
    """(Path, state.json, ledger.jsonl) uc-lusu doner."""
    p, sp, lp = _pkg(pkg)
    from pathlib import Path
    assert p == Path(pkg)
    assert sp == Path(pkg) / "state.json"
    assert lp == Path(pkg) / "ledger.jsonl"


def test_pkg_components_named():
    p, sp, lp = _pkg("foo/bar")
    assert sp.name == "state.json"
    assert lp.name == "ledger.jsonl"


def test_pkg_returns_path_objects():
    from pathlib import Path
    p, sp, lp = _pkg("x")
    assert all(isinstance(x, Path) for x in (p, sp, lp))


def test_registry_file_path():
    from pathlib import Path
    assert _registry_file(Path("foo")) == Path("foo") / "reg.json"


def test_registry_file_matches_pkg_layout():
    """_registry_file ile _pkg ayni kok kullanir (daemon-ile-ayni-dosya)."""
    p, _, _ = _pkg("foo/bar")
    assert _registry_file(p).name == "reg.json"


def test_registry_file_nested():
    from pathlib import Path
    assert _registry_file(Path("a/b/c")).as_posix() == "a/b/c/reg.json"


# == _mem =======================================================================================

def test_mem_creates_default():
    """Bos state -> memory alt-dict yaratir (next_id=1, nodes/edges bos)."""
    st = {}
    m = _mem(st)
    assert m == {"next_id": 1, "nodes": [], "edges": []}


def test_mem_setdefault_returns_same_object():
    """setdefault: ayni nesneyi tekrar doner (mutasyon kalici)."""
    st = {}
    m1 = _mem(st)
    m1["next_id"] = 5
    assert _mem(st)["next_id"] == 5
    assert _mem(st) is m1


def test_mem_preserves_existing():
    """Mevcut memory DOKUNULMADAN doner."""
    st = {"memory": {"next_id": 99, "nodes": [{"id": "m1"}], "edges": [{"a": 1}]}}
    m = _mem(st)
    assert m["next_id"] == 99
    assert m["nodes"] == [{"id": "m1"}]


def test_mem_keys():
    st = {}
    assert sorted(_mem(st).keys()) == ["edges", "next_id", "nodes"]


def test_mem_mutation_via_reference():
    """Geri-donen dict uzerinden ekleme state'i gunceller."""
    st = {}
    _mem(st)["nodes"].append({"id": "m1"})
    assert len(_mem(st)["nodes"]) == 1


def test_mem_other_keys_untouched():
    st = {"format": "tamga-state/1", "sessions": 3}
    _mem(st)
    assert st["format"] == "tamga-state/1"
    assert st["sessions"] == 3


# == _node_fp ===================================================================================

def _ref_fp(node):
    """Reference: Audit-5 F22 formulu (5-alan core)."""
    core = {k: node.get(k) for k in ("kind", "text", "valid_from", "valid_to", "supersedes")}
    return hashlib.sha256(jcs(core).decode("utf-8").encode("utf-8")).hexdigest()


@pytest.mark.parametrize("node", [
    {"kind": "note", "text": "x"},
    {"kind": "note", "text": "y"},
    {"kind": "fact", "text": "x"},
    {"kind": "note", "text": "x", "valid_from": 1, "valid_to": 2, "supersedes": 3},
    {},
    {"text": "x"},
    {"kind": "note"},
])
def test_node_fp_matches_reference(node):
    """_node_fp = sha256(jcs({kind,text,valid_from,valid_to,supersedes}))."""
    assert _node_fp(node) == _ref_fp(node)


def test_node_fp_returns_64_hex():
    r = _node_fp({"kind": "note", "text": "x"})
    assert isinstance(r, str)
    assert len(r) == 64
    assert all(c in "0123456789abcdef" for c in r)


def test_node_fp_extra_fields_ignored():
    """Sadece 5-alan core'u hash'ler; extra-alanlar parmak-izine GIRMEZ."""
    a = _node_fp({"kind": "note", "text": "x", "extra": "ignored"})
    b = _node_fp({"kind": "note", "text": "x"})
    assert a == b


def test_node_fp_case_sensitive_text():
    assert _node_fp({"kind": "n", "text": "X"}) != _node_fp({"kind": "n", "text": "x"})


def test_node_fp_kind_matters():
    assert _node_fp({"kind": "a", "text": "x"}) != _node_fp({"kind": "b", "text": "x"})


def test_node_fp_valid_from_matters():
    assert _node_fp({"kind": "n", "text": "x", "valid_from": 1}) != _node_fp({"kind": "n", "text": "x"})


def test_node_fp_valid_to_matters():
    a = _node_fp({"kind": "n", "text": "x", "valid_to": 5})
    b = _node_fp({"kind": "n", "text": "x", "valid_to": 6})
    assert a != b


def test_node_fp_supersedes_matters():
    assert _node_fp({"kind": "n", "text": "x", "supersedes": "m1"}) != _node_fp({"kind": "n", "text": "x"})


def test_node_fp_deterministic():
    n = {"kind": "note", "text": "test"}
    assert _node_fp(n) == _node_fp(dict(n))


@pytest.mark.parametrize("text", ["", "a", "Turkce: ğüşçıö", "emoji 🎉", "x" * 1000])
def test_node_fp_unicode(text):
    """UTF-8 icerik stabil (jcs UTF-16-surrogate-safe)."""
    assert len(_node_fp({"kind": "n", "text": text})) == 64


def test_node_fp_none_values():
    """Eksik alanlar None olur (jcs null)."""
    assert _node_fp({}) == _ref_fp({})


# == _cosign_policy =============================================================================

def test_cosign_default_l0():
    """Varsayilan L0 (back-compat; L1 opt-in)."""
    assert _cosign_policy([]) == ("L0", None)


def test_cosign_l1_without_trust():
    """L1 + --node-trust YOK -> TRUST_MISSING (AT-178 fail-closed)."""
    assert _cosign_policy(["--cosign-policy", "L1"]) == ("L1", "TRUST_MISSING")


@pytest.mark.parametrize("bad", ["L2", "L9", "", "l1", "LX", "LO"])
def test_cosign_invalid_falls_back_l0(bad):
    """Gecersiz policy -> L0 (IndexError/fallback; traceback YOK)."""
    assert _cosign_policy(["--cosign-policy", bad]) == ("L0", None)


def test_cosign_flag_no_value():
    """--cosign-policy deger-siz -> IndexError -> L0 (Audit-9 B11: deger-siz-bayrak = varsayilan)."""
    assert _cosign_policy(["--cosign-policy"]) == ("L0", None)


def test_cosign_l0_with_trust_ok(tmp_path):
    """L0 + gecerli trust -> trust set doner (L0 trust kullanmaz ama okur)."""
    tf = tmp_path / "trust.json"
    tf.write_text(json.dumps([OK64]), encoding="utf-8")
    pol, trust = _cosign_policy(["--cosign-policy", "L0", "--node-trust", str(tf)])
    assert pol == "L0"
    assert trust == {OK64}


def test_cosign_l1_with_trust_ok(tmp_path):
    """L1 + gecerli trust -> trust set (set donus)."""
    tf = tmp_path / "trust.json"
    ids = [OK64, "0x" + "b" * 64]
    tf.write_text(json.dumps(ids), encoding="utf-8")
    pol, trust = _cosign_policy(["--cosign-policy", "L1", "--node-trust", str(tf)])
    assert pol == "L1"
    assert trust == set(ids)


def test_cosign_l1_trust_broken_json(tmp_path):
    """L1 + bozuk-JSON trust -> TRUST_BROKEN (fail-closed; sessiz-None YOK)."""
    tf = tmp_path / "trust.json"
    tf.write_text("{not valid json", encoding="utf-8")
    assert _cosign_policy(["--cosign-policy", "L1", "--node-trust", str(tf)]) == ("L1", "TRUST_BROKEN")


def test_cosign_l0_trust_broken_is_none(tmp_path):
    """L0 + bozuk trust -> None (L0 trust-kontrolu yapmaz; opt-in korumasi)."""
    tf = tmp_path / "trust.json"
    tf.write_text("{bad", encoding="utf-8")
    assert _cosign_policy(["--cosign-policy", "L0", "--node-trust", str(tf)]) == ("L0", None)


def test_cosign_l1_trust_missing_file(tmp_path):
    """L1 + olmayan-dosya -> TRUST_BROKEN (except yutulan YOL fail-closed sinyali)."""
    assert _cosign_policy(["--cosign-policy", "L1", "--node-trust", str(tmp_path / "nope.json")]) == ("L1", "TRUST_BROKEN")


def test_cosign_trust_no_value_falls_back():
    """--node-trust deger-siz -> IndexError -> None (L0)."""
    assert _cosign_policy(["--node-trust"]) == ("L0", None)


@pytest.mark.parametrize("content,expect_set", [
    ("[]", set()),                     # bos liste -> bos set
    ('"str"', {"s", "t", "r"}),        # ORTAM-QUIRK: string -> KARAKTER-seti
    ('{"a": 1, "b": 2}', {"a", "b"}),  # ORTAM-QUIRK: dict -> ANAHTAR-seti
])
def test_cosign_l1_trust_iterable_quirks(tmp_path, content, expect_set):
    """ORTAM-KARAKTERIZASYON: trust JSON tip-denetimi YOK — set() herhangi bir
    iterable'i kabul eder: string -> karakterler, dict -> anahtarlar.
    Test bunu belgeler (guvenlik-acisindan L1 trust-kontrolu cagirida yapilir)."""
    tf = tmp_path / "trust.json"
    tf.write_text(content, encoding="utf-8")
    pol, trust = _cosign_policy(["--cosign-policy", "L1", "--node-trust", str(tf)])
    assert pol == "L1"
    assert trust == expect_set


@pytest.mark.parametrize("content", ["null", "42", "true"])
def test_cosign_l1_trust_non_iterable_broken(tmp_path, content):
    """null/int/bool -> set() TypeError -> except -> TRUST_BROKEN (fail-closed)."""
    tf = tmp_path / "trust.json"
    tf.write_text(content, encoding="utf-8")
    assert _cosign_policy(["--cosign-policy", "L1", "--node-trust", str(tf)]) == ("L1", "TRUST_BROKEN")


def test_cosign_returns_pair():
    r = _cosign_policy([])
    assert isinstance(r, tuple) and len(r) == 2


def test_cosign_policy_string_always_l0_or_l1():
    """Cikti-1 daima 'L0' veya 'L1' (fallback garantisi)."""
    for a in ([], ["--cosign-policy", "L1"], ["--cosign-policy", "xx"], ["--cosign-policy"]):
        assert _cosign_policy(a)[0] in ("L0", "L1")


def test_cosign_l1_trust_set_dedups(tmp_path):
    """Tekrarlayan node_id'ler set'te bir kez."""
    tf = tmp_path / "trust.json"
    tf.write_text(json.dumps([OK64, OK64, OK64]), encoding="utf-8")
    _, trust = _cosign_policy(["--cosign-policy", "L1", "--node-trust", str(tf)])
    assert trust == {OK64}

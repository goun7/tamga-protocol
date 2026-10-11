"""tamga_runner snapshot-header + anahtar + guvenli-dosya dal-kesen testleri (LEED).

Kural-1: MEVCUT DOSYALARA DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory (dict/argv-list girdi); _secure_open tmp_path ile gecici-dosya.

Kapsanan _-prefixed fonksiyonlar (AST backlog):
  _check_header  Audit-9 B9 snapshot-header sablon-deneti (8 zorunlu str + keystore)
  _node_key_from --node-key argv ayristirma (Audit-10: flag-var-deger-yok -> ValueError)
  _secure_open   Audit-9 B6 atomic 0600 (post-write chmod pencere YOK)
"""
import os
import stat

import pytest

sys = __import__("sys")
sys.path.insert(0, ".")
from tamga_runner import _check_header, _node_key_from, _secure_open  # noqa: E402

K64 = "a" * 64
N48 = "c" * 48


def _good_header(**over):
    """Audit-9 B9 sablonuna uyan minimal gecerli header."""
    h = {
        "format": "tamga-snapshot/1",
        "pkg_name": "demo",
        "pkg_wasm_sha256": K64,
        "agent_id": "b" * 64,
        "cipher": "XChaCha20-Poly1305",
        "body_nonce": N48,
        "created": "2026-10-05T12:05:30Z",
        "keystore_blob": {"kdf": "scrypt", "n": 1, "r": 1, "p": 1,
                          "salt": "s", "nonce": "n", "ct": "c"},
    }
    h.update(over)
    return h


# == _check_header: gecerli sablon ==============================================================

def test_check_header_valid():
    assert _check_header(_good_header()) is True


def test_check_header_returns_bool():
    assert isinstance(_check_header(_good_header()), bool)


def test_check_header_extra_fields_tolerated():
    """Ekstra-alanlar RED DEGIL (forward-compat)."""
    h = _good_header(extra="ignored", version=7)
    assert _check_header(h) is True


def test_check_header_keystore_extra_fields_tolerated():
    h = _good_header()
    h["keystore_blob"]["extra"] = "x"
    assert _check_header(h) is True


def test_check_header_keystore_int_fields_ok():
    """kdf/n/r/p/nonce/ct icin tip-deneti YOK — yalniz varlik + str-tipler."""
    h = _good_header(keystore_blob={"kdf": 1, "n": "x", "r": None, "p": [],
                                    "salt": "s", "nonce": "n", "ct": "c"})
    assert _check_header(h) is True


# == _check_header: tip-deneti (8 zorunlu str) ===================================================

@pytest.mark.parametrize("key", [
    "format", "pkg_name", "pkg_wasm_sha256", "agent_id", "cipher", "body_nonce", "created",
])
def test_check_header_non_string_field(key):
    """Her 7 zorunlu alan str OLMALI (int -> RED)."""
    h = _good_header()
    h[key] = 123
    assert _check_header(h) is False


@pytest.mark.parametrize("key", ["format", "pkg_name", "pkg_wasm_sha256", "agent_id",
                                 "cipher", "body_nonce", "created"])
def test_check_header_missing_field(key):
    """Eksik alan -> None -> isinstance(None, str) False -> RED."""
    h = _good_header()
    del h[key]
    assert _check_header(h) is False


@pytest.mark.parametrize("key", ["format", "cipher", "pkg_wasm_sha256", "agent_id", "body_nonce"])
def test_check_header_none_field(key):
    h = _good_header()
    h[key] = None
    assert _check_header(h) is False


@pytest.mark.parametrize("inp", [None, "string", 42, [], ["a"], b"bytes", True])
def test_check_header_non_dict(inp):
    """ORTAM-ANATOMI: header dict DEGILSE -> False (message-RED, exception YOK)."""
    assert _check_header(inp) is False


def test_check_header_empty_dict():
    assert _check_header({}) is False


# == _check_header: deger-deneti ================================================================

@pytest.mark.parametrize("fmt", ["tamga-snapshot/0", "tamga-snapshot/2", "TAMGA-SNAPSHOT/1", "", "x"])
def test_check_header_wrong_format(fmt):
    """format tam 'tamga-snapshot/1' OLMALI (surum-kilidi)."""
    assert _check_header(_good_header(format=fmt)) is False


def test_check_header_wrong_cipher():
    """cipher XChaCha20-Poly1305 OLMALI (algoritma-kilidi; AES RED)."""
    assert _check_header(_good_header(cipher="AES-256-GCM")) is False


@pytest.mark.parametrize("ln", [0, 1, 63, 65, 100])
def test_check_header_wrong_sha256_length(ln):
    """pkg_wasm_sha256 64-hex OLMALI."""
    assert _check_header(_good_header(pkg_wasm_sha256="a" * ln)) is False


@pytest.mark.parametrize("ln", [0, 1, 63, 65, 100])
def test_check_header_wrong_agent_id_length(ln):
    assert _check_header(_good_header(agent_id="b" * ln)) is False


@pytest.mark.parametrize("ln", [0, 1, 47, 49, 96])
def test_check_header_wrong_nonce_length(ln):
    """body_nonce 48-char (XChaCha20 nonce) OLMALI."""
    assert _check_header(_good_header(body_nonce="c" * ln)) is False


def test_check_header_exact_length_boundaries():
    """Esitlik DAHIL: 64/64/48 -> True."""
    h = _good_header(pkg_wasm_sha256="a" * 64, agent_id="b" * 64, body_nonce="c" * 48)
    assert _check_header(h) is True


# == _check_header: keystore_blob ===============================================================

@pytest.mark.parametrize("inp", [None, "str", 42, [], b"x"])
def test_check_header_keystore_not_dict(inp):
    """keystore_blob dict OLMALI."""
    assert _check_header(_good_header(keystore_blob=inp)) is False


def test_check_header_keystore_missing_entirely():
    assert _check_header(_good_header(keystore_blob=None)) is False


@pytest.mark.parametrize("missing", ["kdf", "n", "r", "p", "salt", "nonce", "ct"])
def test_check_header_keystore_missing_key(missing):
    """7 keystore-anahtarinin HEPSI zorunlu."""
    h = _good_header()
    del h["keystore_blob"][missing]
    assert _check_header(h) is False


def test_check_header_keystore_only_kdf():
    """Yalnizca kdf varsa RED."""
    assert _check_header(_good_header(keystore_blob={"kdf": "scrypt"})) is False


@pytest.mark.parametrize("key", ["salt", "nonce", "ct"])
def test_check_header_keystore_non_string(key):
    """salt/nonce/ct str OLMALI (base64-serialized)."""
    h = _good_header()
    h["keystore_blob"][key] = 123
    assert _check_header(h) is False


@pytest.mark.parametrize("key", ["salt", "nonce", "ct"])
def test_check_header_keystore_none(key):
    h = _good_header()
    h["keystore_blob"][key] = None
    assert _check_header(h) is False


@pytest.mark.parametrize("key", ["kdf", "n", "r", "p"])
def test_check_header_keystore_int_params_ok(key):
    """kdf/n/r/p icin tip-deneti YOK (kdf str, n/r/p int beklenir ama ZORLANMAZ)."""
    h = _good_header()
    h["keystore_blob"][key] = "anything"
    assert _check_header(h) is True


# == _node_key_from =============================================================================

def test_node_key_from_no_flag():
    """--node-key YOK -> None (opsiyonel; operator-anahtari)."""
    assert _node_key_from([]) is None


def test_node_key_from_no_flag_with_other_args():
    assert _node_key_from(["run", "pkg", "--seed", "00" * 32]) is None


def test_node_key_from_valid():
    r = _node_key_from(["--node-key", "ab" * 32])
    assert r == bytes.fromhex("ab" * 32)
    assert isinstance(r, bytes)
    assert len(r) == 32


def test_node_key_from_finds_flag_anywhere():
    """index() tabanli — konum onemli DEGIL."""
    assert _node_key_from(["run", "pkg", "--node-key", "cd" * 32]) == bytes.fromhex("cd" * 32)


def test_node_key_from_zero_key():
    """32-bytlik sifir-anahtar gecerli (crypto-deneti YOK, uzunluk-deneti VAR)."""
    assert _node_key_from(["--node-key", "00" * 32]) == bytes(32)


def test_node_key_from_ff_key():
    assert _node_key_from(["--node-key", "ff" * 32]) == b"\xff" * 32


@pytest.mark.parametrize("hexp", ["ab" * 31, "ab" * 33, "ab" * 16, "ab", "", "00" * 31, "ff" * 64])
def test_node_key_from_wrong_length(hexp):
    """Anahtar tam 32 bayt (64-hex) OLMALI — ed25519 seed-boyu."""
    with pytest.raises(ValueError, match="node_key_invalid"):
        _node_key_from(["--node-key", hexp])


@pytest.mark.parametrize("bad", ["xyz", "gg" * 32, "0x" + "g" * 62, "AB" * 32 + "!", "12 34"])
def test_node_key_from_bad_hex(bad):
    """Gecersiz hex -> ValueError (Audit-10: sessiz-None YOK)."""
    with pytest.raises(ValueError, match="node_key_invalid"):
        _node_key_from(["--node-key", bad])


def test_node_key_from_missing_value():
    """ORTAM-ANATOMI (Audit-10): --node-key var ama deger YOK -> ValueError,
    None DEGIL — 'flag_given=True, key=None' exploit'i kapatir
    (silent-unsigned-record kapatma)."""
    with pytest.raises(ValueError, match="node_key_invalid"):
        _node_key_from(["--node-key"])


def test_node_key_from_flag_as_value():
    """'--node-key --seed x' -> '--seed' hex-degil -> ValueError."""
    with pytest.raises(ValueError, match="node_key_invalid"):
        _node_key_from(["--node-key", "--seed", "x"])


def test_node_key_from_message_contains_64_hex_hint():
    with pytest.raises(ValueError, match="64-hex"):
        _node_key_from(["--node-key", "ab"])


def test_node_key_from_returns_32_bytes():
    assert len(_node_key_from(["--node-key", "11" * 32])) == 32


# == _secure_open ===============================================================================

def test_secure_open_creates_file(tmp_path):
    p = tmp_path / "secret.key"
    fd = _secure_open(str(p))
    os.write(fd, b"data")
    os.close(fd)
    assert p.read_bytes() == b"data"


def test_secure_open_mode_is_0600(tmp_path):
    """Audit-9 B6: dosya ACILIRKEN 0600 (atomic — post-write chmod penceresi YOK)."""
    p = tmp_path / "f"
    fd = _secure_open(str(p))
    os.close(fd)
    mode = stat.S_IMODE(p.stat().st_mode)
    assert mode == 0o600


def test_secure_open_existing_file_mode_unchanged(tmp_path):
    """ORTAM-KARAKTERIZASYON: O_CREAT mode yalnizca OLUSTURMA aninda uygulanir —
    MEVCUT dosyanin modu DEGISMEZ (0o644 kalir). '0600-atomic' vaadi yeni-dosya
    olusuminda gecerlidir; cagiran yeniden-yazimda eski-dosyayi once silmelidir."""
    p = tmp_path / "f"
    p.write_bytes(b"orig")
    p.chmod(0o644)
    fd = _secure_open(str(p))
    os.close(fd)
    assert stat.S_IMODE(p.stat().st_mode) == 0o644


def test_secure_open_truncates_by_default(tmp_path):
    """append=False -> O_TRUNC (mevcut icerik silinir)."""
    p = tmp_path / "f"
    p.write_bytes(b"original-content")
    fd = _secure_open(str(p))
    os.write(fd, b"new")
    os.close(fd)
    assert p.read_bytes() == b"new"


def test_secure_open_append_mode(tmp_path):
    """append=True -> O_APPEND (mevcut icerige ekler)."""
    p = tmp_path / "f"
    p.write_bytes(b"hello")
    fd = _secure_open(str(p), append=True)
    os.write(fd, b" world")
    os.close(fd)
    assert p.read_bytes() == b"hello world"


def test_secure_open_append_creates(tmp_path):
    p = tmp_path / "new"
    fd = _secure_open(str(p), append=True)
    os.write(fd, b"x")
    os.close(fd)
    assert p.read_bytes() == b"x"


def test_secure_open_returns_int_fd(tmp_path):
    p = tmp_path / "f"
    fd = _secure_open(str(p))
    assert isinstance(fd, int)
    os.close(fd)


def test_secure_open_fd_is_writable(tmp_path):
    p = tmp_path / "f"
    fd = _secure_open(str(p))
    assert os.write(fd, b"ok") == 2
    os.close(fd)


def test_secure_open_mode_0600_new_file_only(tmp_path):
    """Append-modunda YENI dosya yine 0600 olusur (atomic-sifir-pencere)."""
    p = tmp_path / "f"
    fd = _secure_open(str(p), append=True)
    os.close(fd)
    assert stat.S_IMODE(p.stat().st_mode) == 0o600


def test_secure_open_nested_dir_missing_raises(tmp_path):
    """Olmayan dizin -> OSError (mkdir YAPMAZ — cagiran hazirlamali)."""
    p = tmp_path / "nope" / "f"
    with pytest.raises(OSError):
        _secure_open(str(p))


def test_secure_open_truncate_removes_all(tmp_path):
    """Truncate sonra eski uzunluk kaybolur."""
    p = tmp_path / "f"
    p.write_bytes(b"y" * 1000)
    fd = _secure_open(str(p))
    os.write(fd, b"z")
    os.close(fd)
    assert len(p.read_bytes()) == 1


def test_secure_open_two_files_separate_fds(tmp_path):
    a = tmp_path / "a"
    b = tmp_path / "b"
    fa = _secure_open(str(a))
    fb = _secure_open(str(b))
    assert fa != fb
    os.close(fa)
    os.close(fb)


def test_secure_open_roundtrip_content(tmp_path):
    p = tmp_path / "f"
    for content in (b"", b"x", b"\x00\xff" * 100):
        fd = _secure_open(str(p))
        os.write(fd, content)
        os.close(fd)
        assert p.read_bytes() == content

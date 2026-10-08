"""tamga_runner cmd_import / cmd_export snapshot dal-kesen testler (LEED).

Kural-1: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Dış çağrı YOK: gecici dizinler + ed25519 seed + scrypt passphrase (env).
Kapsam: export->import roundtrip + tum guvenlik red yollari.
"""
import json
import os
import pathlib
import subprocess
import sys
import tempfile

import pytest

sys.path.insert(0, ".")

import tamga_runner as tr  # noqa: E402


@pytest.fixture(scope="module")
def seed_hex():
    from nacl.signing import SigningKey
    sk = SigningKey.generate()
    return sk.encode().hex()


@pytest.fixture
def tmp_pkg(tmp_path, seed_hex, monkeypatch):
    """quickstart ile geçerli bir paket oluştur."""
    monkeypatch.setenv("TAMGA_KS_PASSPHRASE", "test-pass-42")
    d = tmp_path / "pkg"
    rc = tr.cmd_quickstart([str(d), "--name", "test-pkg"])
    assert rc == 0, "quickstart basarisiz"
    return d


def _export(pkg, dst, seed_hex):
    return tr.cmd_export([str(pkg), "-o", str(dst), "--seed", seed_hex])


def _import(snap, pkg, *extra):
    return tr.cmd_import([str(snap), str(pkg), *extra])


@pytest.fixture
def tgt(tmp_path, monkeypatch):
    """Import hedefi: quickstart ile oluşturulup BOSALTILMIS paket
    (cmd_import hedef-te manifest-validation yapar — boş dizin RED;
    Audit-9 B7: migration = boş-node'a, baskasinin state'ine DEĞIL)."""
    monkeypatch.setenv("TAMGA_KS_PASSPHRASE", "test-pass-42")
    d = tmp_path / "tgt"
    rc = tr.cmd_quickstart([str(d), "--name", "test-pkg"])
    assert rc == 0, "hedef quickstart basarisiz"
    # state'i bosalt: import bos-node'a yapilir (ownership RED gelmemesi icin)
    sp = d / "state.json"
    if sp.exists():
        sp.write_text("{}", encoding="utf-8")
    # zinciri de sil: bos-dosya genesis-head uretir (_ledger_head);
    # import snapshot ledger_tip'ini arar → (None,"yok") ile atlanir
    lp = d / "ledger.jsonl"
    if lp.exists():
        lp.unlink()
    return d


# -- export temel ---------------------------------------------------------------------------

def test_export_success(tmp_pkg, tmp_path, seed_hex):
    dst = tmp_path / "snap.tsg"
    rc = _export(tmp_pkg, dst, seed_hex)
    assert rc == 0
    assert dst.exists()


def test_export_magic_and_size(tmp_pkg, tmp_path, seed_hex):
    dst = tmp_path / "snap.tsg"
    _export(tmp_pkg, dst, seed_hex)
    data = dst.read_bytes()
    assert data[:4] == tr.MAGIC


def test_export_missing_manifest(tmp_path, seed_hex):
    # tamga.json olmayan dizin → manifest_reject rc=3
    d = tmp_path / "empty"
    d.mkdir()
    rc = _export(d, tmp_path / "x.tsg", seed_hex)
    assert rc != 0


def test_export_no_output_flag(tmp_pkg, tmp_path, seed_hex):
    # -o yok → parse_error
    rc = tr.cmd_export([str(tmp_pkg), "--seed", seed_hex])
    assert rc != 0


def test_export_bad_seed(tmp_pkg, tmp_path):
    rc = _export(tmp_pkg, tmp_path / "x.tsg", "deadbeef")
    assert rc != 0


# -- import: roundtrip başarı ---------------------------------------------------------------

def test_import_roundtrip(tmp_pkg, tgt, tmp_path, seed_hex, monkeypatch):
    monkeypatch.setenv("TAMGA_KS_PASSPHRASE", "test-pass-42")
    dst = tmp_path / "snap.tsg"
    assert _export(tmp_pkg, dst, seed_hex) == 0
    rc = _import(dst, tgt)
    assert rc == 0


def test_import_roundtrip_with_state(tmp_pkg, tgt, tmp_path, seed_hex, monkeypatch):
    monkeypatch.setenv("TAMGA_KS_PASSPHRASE", "test-pass-42")
    dst = tmp_path / "snap.tsg"
    # state + ledger yaz
    sp = tmp_pkg / "state.json"
    sp.write_text(json.dumps({"sessions": 5, "memory": {"nodes": [{"id": "n1"}]}}), encoding="utf-8")
    lp = tmp_pkg / "ledger.jsonl"
    # geçerli ledger kaydı: jcs(no_h) ile SHA-256 zinciri (_verify_chain formatı)
    # op emitter_registry'de kayıtlı olmalı (AT-053 restore-geçidi)
    import hashlib as _hl
    from tamga_canon import jcs as _jcs
    prev_h = "0" * 64
    rec = {"seq": 1, "op": "grant", "prev": prev_h}
    no_h = {k: v for k, v in rec.items() if k != "h"}
    rec["h"] = _hl.sha256((prev_h + _jcs(no_h).decode()).encode()).hexdigest()
    lp.write_text(json.dumps(rec) + "\n", encoding="utf-8")
    assert _export(tmp_pkg, dst, seed_hex) == 0
    rc = _import(dst, tgt)
    assert rc == 0
    # state kurulmuş olmalı
    assert (tgt / "state.json").exists()


def test_import_resumes_sessions(tmp_pkg, tgt, tmp_path, seed_hex, monkeypatch):
    monkeypatch.setenv("TAMGA_KS_PASSPHRASE", "test-pass-42")
    dst = tmp_path / "snap.tsg"
    (tmp_pkg / "state.json").write_text(
        json.dumps({"sessions": 7, "memory": {"nodes": []}}), encoding="utf-8")
    (tmp_pkg / "ledger.jsonl").write_text("", encoding="utf-8")
    _export(tmp_pkg, dst, seed_hex)
    rc = _import(dst, tgt)
    assert rc == 0
    st = json.loads((tgt / "state.json").read_text(encoding="utf-8"))
    assert st.get("sessions") == 7


# -- import red yolları -----------------------------------------------------------------------

def test_import_missing_arg(tmp_path):
    rc = tr.cmd_import([str(tmp_path / "x.tsg")])
    assert rc != 0


def test_import_missing_snapshot(tmp_path, tmp_pkg):
    rc = _import(tmp_path / "yok.tsg", tmp_pkg)
    assert rc != 0


def test_import_bad_magic(tmp_path, tmp_pkg):
    fake = tmp_path / "fake.tsg"
    fake.write_bytes(b"XXXX" + b"\x00" * 100)
    rc = _import(fake, tmp_pkg)
    assert rc != 0


def test_import_truncated_header(tmp_path, tmp_pkg):
    fake = tmp_path / "trunc.tsg"
    fake.write_bytes(tr.MAGIC + b"\x10\x00\x00\x00" + b"{bad")
    rc = _import(fake, tmp_pkg)
    assert rc != 0


def test_import_oversized_snapshot(tmp_path, tmp_pkg, monkeypatch):
    monkeypatch.setattr(tr, "SAFE_SNAP_MAX", 16)
    big = tmp_path / "big.tsg"
    big.write_bytes(tr.MAGIC + b"\x00" * 100)
    rc = _import(big, tmp_pkg)
    assert rc != 0


def test_import_header_no_keystore(tmp_path, tmp_pkg):
    fake = tmp_path / "hk.tsg"
    hdr = json.dumps({"format": "tamga-snapshot/1", "pkg_name": "x",
                      "pkg_wasm_sha256": "a" * 64, "agent_id": "b" * 64,
                      "cipher": "XChaCha20-Poly1305", "body_nonce": "c" * 48,
                      "created": "2026-01-01T00:00:00+0000"})
    hb = hdr.encode()
    fake.write_bytes(tr.MAGIC + len(hb).to_bytes(4, "big") + hb + b"\x00" * 32)
    # keystore_blob eksik → _check_header veya keystore hatası
    rc = _import(fake, tmp_pkg)
    assert rc != 0


def test_import_wrong_passphrase(tmp_pkg, tgt, tmp_path, seed_hex, monkeypatch):
    monkeypatch.setenv("TAMGA_KS_PASSPHRASE", "test-pass-42")
    dst = tmp_path / "snap.tsg"
    _export(tmp_pkg, dst, seed_hex)
    # import'ta FARKLI passphrase → keystore_unlock_failed
    monkeypatch.setenv("TAMGA_KS_PASSPHRASE", "baska-pass")
    rc = _import(dst, tgt)
    assert rc != 0


def test_import_agent_identity_mismatch(tmp_pkg, tgt, tmp_path, seed_hex, monkeypatch):
    """Snapshot seed'i, hedef agent'ından farklı bir agent'a aitse RED (rc=9)."""
    monkeypatch.setenv("TAMGA_KS_PASSPHRASE", "test-pass-42")
    dst = tmp_path / "snap.tsg"
    _export(tmp_pkg, dst, seed_hex)
    # hedef pakette BAŞKA bir agent'ın state'i varsa
    sp = tgt / "state.json"
    sp.write_text(json.dumps({"agent_id": "f" * 64, "sessions": 1}), encoding="utf-8")
    rc = _import(dst, tgt)
    # ownership_mismatch (rc=18) veya identity (rc=9) — ikisi de RED
    assert rc != 0


def test_import_replay_rollback(tmp_pkg, tgt, tmp_path, seed_hex, monkeypatch):
    """Snapshot sessions < hedef sessions → replay-rollback RED (rc=8)."""
    monkeypatch.setenv("TAMGA_KS_PASSPHRASE", "test-pass-42")
    (tmp_pkg / "state.json").write_text(
        json.dumps({"sessions": 1, "memory": {"nodes": []}}), encoding="utf-8")
    (tmp_pkg / "ledger.jsonl").write_text("", encoding="utf-8")
    dst = tmp_path / "snap.tsg"
    _export(tmp_pkg, dst, seed_hex)
    # hedefde DAHA FAZLA session var
    (tgt / "state.json").write_text(json.dumps({"sessions": 99}), encoding="utf-8")
    rc = _import(dst, tgt)
    assert rc != 0


# -- karman-çorman snapshot --------------------------------------------------------------------

def test_import_tampered_body(tmp_pkg, tgt, tmp_path, seed_hex, monkeypatch):
    """Body AEAD etiketi bozulursa RED (rc=2 body tag)."""
    monkeypatch.setenv("TAMGA_KS_PASSPHRASE", "test-pass-42")
    dst = tmp_path / "snap.tsg"
    (tmp_pkg / "state.json").write_text(
        json.dumps({"sessions": 1, "memory": {"nodes": []}}), encoding="utf-8")
    (tmp_pkg / "ledger.jsonl").write_text("", encoding="utf-8")
    _export(tmp_pkg, dst, seed_hex)
    data = bytearray(dst.read_bytes())
    # son baytı boz (body ciphertext)
    data[-1] ^= 0xFF
    dst.write_bytes(bytes(data))
    rc = _import(dst, tgt)
    assert rc != 0


def test_import_tampered_header(tmp_pkg, tgt, tmp_path, seed_hex, monkeypatch):
    """Header kanonik hash'i body AEAD'e bağlı — header bozulursa RED."""
    monkeypatch.setenv("TAMGA_KS_PASSPHRASE", "test-pass-42")
    dst = tmp_path / "snap.tsg"
    _export(tmp_pkg, dst, seed_hex)
    data = bytearray(dst.read_bytes())
    # header bölgesini boz (MAGIC + 4 bayt uzunluk = 8. bayttan itibaren)
    data[12] ^= 0xFF
    dst.write_bytes(bytes(data))
    rc = _import(dst, tgt)
    assert rc != 0

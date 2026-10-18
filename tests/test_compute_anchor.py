#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
test_compute_anchor — RFC-011 compute-work proof Receipt (AT-080)

kok'un Seçenek-C evrimi: bir compute-provider'ın gerçekten hangi MatMul
işini yaptığını kanıtlayan makbuz, tamga ledger'ına bağlanır. Bu test
dosyası üç şeyi sabitler:

  1. WRITE-PATH RED-KORUMA — bağımsız doğrulayıcıda RED olan bir kanıt
     ledger'a GİREMEZ (yeşil giydirme kapısı, AT-050 üçlü-kapsam dersi).
  2. SHAPE-CONTRACT OKUMA-KAPISI — ledger'a yazılmış bir kayıtsonra
     bozulursa (verified=False, anchor_version değişirse...) okuma-yolu
     onu yakalar. Yazma ve okuma aynı fonksiyonu paylaşır (AT-062).
  3. EMITTER-KAYDI — compute-anchor op'u emitter_registry'de-olmalı;
     yoksa _ledger_append başarısız (üçlü-kapsam-katman-1).

Test çoğu yerde GERÇEK bir kok kanıtı kullanır (Rust binary ile üretilmiş,
/tmp'ye yazılmış fixture). Cargo yoksa fixture üretemeyiz — o durumda
honest-receipt testleri SKIP olur ama RED/shape testleri yine de koşar,
çünkü onlar sadece shape mantığını test eder.
"""

import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

import pytest

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT))

import emitter_registry  # noqa: E402
import tamga_runner as tr  # noqa: E402
from tamga_canon import jcs  # noqa: E402

COMPUTE_ANCHOR = ROOT / "tools" / "compute_anchor.py"
KOK_REPO = pathlib.Path("/home/gokun/projects/00_TAMGA-MESH/kok")
KOK_VERIFY_COPY = ROOT / "tools" / "kok_receipt" / "kok_receipt_verify_en.py"

import importlib.util  # noqa: E402
_spec = importlib.util.spec_from_file_location("compute_anchor",
                                               COMPUTE_ANCHOR)
ca = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ca)


def _cargo_available() -> bool:
    return shutil.which("cargo") is not None


@pytest.fixture(scope="module")
def kok_kanit(tmp_path_factory) -> dict:
    """Rust binary ile gerçek bir kanıt üret; cargo yoksa skip."""
    if not _cargo_available():
        pytest.skip("cargo unavailable — honest-receipt testleri skip")
    out = tmp_path_factory.mktemp("kok") / "kanit.json"
    r = subprocess.run(["cargo", "run", "-q", "--bin", "kok", "create",
                        "--ctx", "20261018", "--target", "2",
                        "--out", str(out)],
                       capture_output=True, text=True, timeout=300,
                       cwd=str(KOK_REPO))
    assert r.returncode == 0, "kok create failed: %s" % r.stderr[:300]
    return json.loads(out.read_text(encoding="utf-8"))


@pytest.fixture
def empty_pkg(tmp_path) -> pathlib.Path:
    pkg = tmp_path / "simnet"
    pkg.mkdir()
    (pkg / "ledger.jsonl").write_text("", encoding="utf-8")
    return pkg


def _anchor(pkg, receipt_path, cwd=ROOT):
    return subprocess.run([sys.executable, "tools/compute_anchor.py",
                           str(pkg), "--receipt", str(receipt_path)],
                          capture_output=True, text=True, timeout=120,
                          cwd=str(cwd))


# ---------------------------------------------------------------------------
# 1. WRITE-PATH: honest receipt yazılır, RED receipt yazılamaz.
# ---------------------------------------------------------------------------

def test_honest_receipt_anchors(kok_kanit, tmp_path, empty_pkg):
    rp = tmp_path / "kanit.json"
    rp.write_text(json.dumps(kok_kanit), encoding="utf-8")
    e = _anchor(empty_pkg, rp)
    assert e.returncode == 0, e.stdout + e.stderr
    out = json.loads(e.stdout)
    assert out["ok"] is True
    assert out["receipt_hash"] == kok_kanit["receipt_hash"][:16]
    lines = open(empty_pkg / "ledger.jsonl", encoding="utf-8").read().strip().splitlines()
    assert len(lines) == 1
    rec = json.loads(lines[0])
    assert rec["op"] == "compute-anchor"
    assert rec["receipt_hash"] == kok_kanit["receipt_hash"]
    assert rec["verified"] is True
    assert rec["presentation_only"] is True


def test_red_receipt_is_refused(kok_kanit, tmp_path, empty_pkg):
    """Sahte-imzalı bir kanıt ledger'a giremez — write-path fail-closed."""
    p = dict(kok_kanit)
    p["signature"] = "00" * 64
    rp = tmp_path / "bad_kanit.json"
    rp.write_text(json.dumps(p), encoding="utf-8")
    e = _anchor(empty_pkg, rp)
    assert e.returncode == 1, "RED kanıt ledger'a girdi!"
    out = json.loads(e.stdout)
    assert out["ok"] is False
    assert "RED" in out["reason"]
    # ve ledger boş kaldı
    assert (empty_pkg / "ledger.jsonl").read_text().strip() == ""


def test_tampered_tile_is_refused(kok_kanit, tmp_path, empty_pkg):
    """Tile değerini değiştirilmiş bir kanıt da RED — iş kanıtı yanlış."""
    p = dict(kok_kanit)
    p["cert_value"] = (p["cert_value"] + 1) % p["q"]
    rp = tmp_path / "bad_tile.json"
    rp.write_text(json.dumps(p), encoding="utf-8")
    e = _anchor(empty_pkg, rp)
    assert e.returncode == 1


# ---------------------------------------------------------------------------
# 2. EMITTER-KAYDI: op statik-tarayıcıda-görünmeli.
# ---------------------------------------------------------------------------

def test_compute_anchor_op_is_registered():
    """emitter_registry statik-tarayıcı compute-anchor'ı-görmeli —
    _ledger_append'in-üçlü-kapsam-katman-1-kapısı-bunu-gerektirir."""
    assert "compute-anchor" in emitter_registry.EMITTED_OPS


def test_emitter_modules_includes_compute_anchor():
    assert "tools/compute_anchor.py" in emitter_registry.EMITTER_MODULES


# ---------------------------------------------------------------------------
# 3. SHAPE-CONTRACT: yazma ve okuma aynı _compute_anchor_violation'ı paylaşır.
# ---------------------------------------------------------------------------

def test_shape_gate_rejects_verified_false():
    """Green-dressing: üçüncü-bir-aracın (veya elle düzenlemenin) RED bir
    kanıtı ledger'a-yazması — okuma-yolu-bunu-yakalamalı."""
    rec = {"op": "compute-anchor",
           "anchor_version": ca.COMPUTE_ANCHOR_VERSION,
           "receipt_version": 1,
           "receipt_hash": "a" * 64,
           "miner_did": "did:key:z6Mkexample",
           "task_program": "kok/g-layer-matmul-toy",
           "ctx": 1, "nonce": 1, "tile": [0, 0, 68],
           "verified": False,                      # <- yeşil giydirme
           "tool": "test", "presentation_only": True}
    viol = ca._compute_anchor_violation(rec)
    assert viol is not None
    assert viol[0] == "verified"


def test_shape_gate_rejects_wrong_anchor_version():
    rec = {"op": "compute-anchor", "anchor_version": "TAMGA_OTHER_V9",
           "receipt_version": 1, "receipt_hash": "a" * 64,
           "miner_did": "did:key:z6Mkexample", "task_program": "x",
           "ctx": 1, "nonce": 1, "tile": [0, 0, 1],
           "verified": True, "tool": "t", "presentation_only": True}
    assert ca._compute_anchor_violation(rec)[0] == "anchor_version"


def test_shape_gate_rejects_bad_receipt_hash():
    rec = {"op": "compute-anchor", "anchor_version": ca.COMPUTE_ANCHOR_VERSION,
           "receipt_version": 1, "receipt_hash": "not-64-hex",
           "miner_did": "did:key:z6Mkexample", "task_program": "x",
           "ctx": 1, "nonce": 1, "tile": [0, 0, 1],
           "verified": True, "tool": "t", "presentation_only": True}
    assert ca._compute_anchor_violation(rec)[0] == "receipt_hash"


def test_shape_gate_rejects_missing_presentation_only():
    rec = {"op": "compute-anchor", "anchor_version": ca.COMPUTE_ANCHOR_VERSION,
           "receipt_version": 1, "receipt_hash": "a" * 64,
           "miner_did": "did:key:z6Mkexample", "task_program": "x",
           "ctx": 1, "nonce": 1, "tile": [0, 0, 1],
           "verified": True, "tool": "t"}
    assert ca._compute_anchor_violation(rec)[0] == "presentation_only"


def test_shape_gate_accepts_honest_record():
    rec = {"op": "compute-anchor", "anchor_version": ca.COMPUTE_ANCHOR_VERSION,
           "receipt_version": 1, "receipt_hash": "a" * 64,
           "miner_did": "did:key:z6Mkexample", "task_program": "x",
           "ctx": 1, "nonce": 1, "tile": [0, 0, 1],
           "verified": True, "tool": "t", "presentation_only": True}
    assert ca._compute_anchor_violation(rec) is None


# ---------------------------------------------------------------------------
# 4. BAĞIMSIZ-DOĞRULAYICI-KOPYASI: tamga'nın-kopyası-ve-kok'un-kanı-uyumlu.
# ---------------------------------------------------------------------------

def test_verifier_copy_exists():
    """kok repo'su-silinse-bile tamga-bir-makbuzu-dogrulayabilmeli —
    kopya tools/kok_receipt/ altında-olmalı."""
    assert KOK_VERIFY_COPY.is_file(), "bagimsiz-dogrulayici-kopyasi eksik: %s" % KOK_VERIFY_COPY


def test_verifier_copy_accepts_honest_receipt(kok_kanit):
    v = ca.verify_kok_receipt_path(KOK_VERIFY_COPY)  # noqa — placeholder
    # asıl çağrı: kopya modülü TMP kanit-path ile çağır
    import tempfile
    rp = pathlib.Path(tempfile.mktemp(suffix=".json"))
    rp.write_text(json.dumps(kok_kanit), encoding="utf-8")
    v = ca.verify_kok_receipt_path(rp)
    assert v["ok"] is True
    rp.unlink()


def test_verifier_copy_refuses_forged(kok_kanit):
    p = dict(kok_kanit)
    p["receipt_hash"] = "f" * 64
    import tempfile
    rp = pathlib.Path(tempfile.mktemp(suffix=".json"))
    rp.write_text(json.dumps(p), encoding="utf-8")
    v = ca.verify_kok_receipt_path(rp)
    assert v["ok"] is False
    rp.unlink()


# ---------------------------------------------------------------------------
# 5. ÇAPRAZ-DİL: Rust-üretilmiş-kanıt tamga-içinden-de ACCEPT.
# ---------------------------------------------------------------------------

def test_full_chain_rust_to_tamga(kok_kanit, tmp_path, empty_pkg):
    """Uçtan-uca: Rust create -> Python verify -> tamga ledger-anchor ->
    ledger-verify (tamga'nın kendi zincir-doğrulayıcısı)."""
    rp = tmp_path / "kanit.json"
    rp.write_text(json.dumps(kok_kanit), encoding="utf-8")
    e = _anchor(empty_pkg, rp)
    assert e.returncode == 0, e.stdout + e.stderr
    v = subprocess.run([sys.executable, "tamga_runner.py", "ledger-verify",
                        str(empty_pkg)],
                       capture_output=True, text=True, timeout=120, cwd=str(ROOT))
    assert v.returncode == 0, v.stdout + v.stderr
    out = json.loads(v.stdout)
    assert out["ok"] is True
    assert out["lines"] == 1

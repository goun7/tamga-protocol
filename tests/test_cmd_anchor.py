"""cmd_anchor RFC-009 dış-zincir-anchor testleri (LEED).

Kural-1: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Dış çağrı YOK: gecici quickstart paketi.
"""
import contextlib
import io
import json
import sys

import pytest

sys.path.insert(0, ".")

import tamga_runner as tr  # noqa: E402

_H64 = "0x" + "a" * 64
_H64B = "0x" + "b" * 64
_TS = "2026-10-08T12:00:00Z"


@pytest.fixture
def pkg(tmp_path, monkeypatch):
    monkeypatch.setenv("TAMGA_KS_PASSPHRASE", "test-pass-42")
    d = tmp_path / "pkg"
    tr.cmd_quickstart([str(d), "--name", "test-pkg"])
    return d


def _anchor(pkg, **over):
    base = [str(pkg), "--foreign-registry", "apodix/epoch",
            "--foreign-fact", _H64, "--foreign-digest", _H64B,
            "--verified-at", _TS]
    base += over.get("extra", [])
    return tr.cmd_anchor(base)


def _res(rc):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc_val = rc
    return rc_val


# -- temel başarı ---------------------------------------------------------------------------

def test_valid_anchor_succeeds(pkg):
    assert _anchor(pkg) == 0


def test_success_returns_ok_json(pkg):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        _anchor(pkg)
    o = json.loads(buf.getvalue())
    assert o["ok"] is True
    assert o["op"] == "anchor"


def test_success_returns_anchor_id(pkg):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        _anchor(pkg)
    o = json.loads(buf.getvalue())
    assert o.get("anchor_id")


def test_success_returns_seq(pkg):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        _anchor(pkg)
    o = json.loads(buf.getvalue())
    assert o.get("seq") >= 1  # quickstart genesis kayıtları sonrası


def test_anchor_written_to_ledger(pkg):
    _anchor(pkg)
    lines = [l for l in (pkg / "ledger.jsonl").read_text().splitlines() if l.strip()]
    rec = json.loads(lines[-1])
    assert rec["op"] == "anchor"


def test_ledger_record_fields(pkg):
    _anchor(pkg)
    lines = [l for l in (pkg / "ledger.jsonl").read_text().splitlines() if l.strip()]
    rec = json.loads(lines[-1])
    assert rec["foreign_registry"] == "apodix/epoch"
    assert rec["foreign_fact"] == _H64
    assert rec["foreign_digest"] == _H64B
    assert rec["verified_at"] == _TS


def test_r91_anchor_version_fixed(pkg):
    _anchor(pkg)
    lines = [l for l in (pkg / "ledger.jsonl").read_text().splitlines() if l.strip()]
    rec = json.loads(lines[-1])
    assert rec["anchor_version"] == tr._ANCHOR_VERSION


def test_r95_presentation_only_true(pkg):
    """Dış-fact'in geçerliliği bizim iddiamız DEĞİL — presentation-only."""
    _anchor(pkg)
    lines = [l for l in (pkg / "ledger.jsonl").read_text().splitlines() if l.strip()]
    rec = json.loads(lines[-1])
    assert rec["presentation_only"] is True


def test_default_tool_value(pkg):
    _anchor(pkg)
    lines = [l for l in (pkg / "ledger.jsonl").read_text().splitlines() if l.strip()]
    rec = json.loads(lines[-1])
    assert "unspecified" in rec["tool"]


def test_custom_tool_recorded(pkg):
    _anchor(pkg, extra=["--tool", "my-verifier"])
    lines = [l for l in (pkg / "ledger.jsonl").read_text().splitlines() if l.strip()]
    rec = json.loads(lines[-1])
    assert rec["tool"] == "my-verifier"


# -- argüman doğrulama ---------------------------------------------------------------------------

def test_too_few_args_fails():
    assert tr.cmd_anchor(["x"]) != 0


def test_missing_pkg_fails(tmp_path):
    rc = tr.cmd_anchor([str(tmp_path / "yok"), "--foreign-registry", "apodix/epoch",
                        "--foreign-fact", _H64, "--foreign-digest", _H64B,
                        "--verified-at", _TS])
    assert rc != 0


def test_missing_required_flag_fails(pkg):
    rc = tr.cmd_anchor([str(pkg), "--foreign-registry", "apodix/epoch",
                        "--foreign-fact", _H64, "--foreign-digest", _H64B])
    assert rc != 0


def test_missing_registry_fails(pkg):
    rc = tr.cmd_anchor([str(pkg), "--foreign-fact", _H64, "--foreign-digest",
                        _H64B, "--verified-at", _TS])
    assert rc != 0


def test_missing_verified_at_fails(pkg):
    rc = tr.cmd_anchor([str(pkg), "--foreign-registry", "apodix/epoch",
                        "--foreign-fact", _H64, "--foreign-digest", _H64B])
    assert rc != 0


def test_odd_args_handled(pkg):
    """Eksik çift argüman → kv eksik → kullanım hatası."""
    rc = tr.cmd_anchor([str(pkg), "--foreign-registry", "apodix/epoch",
                        "--foreign-fact", _H64, "--foreign-digest", _H64B,
                        "--verified-at"])
    assert rc != 0


# -- R9-2 registry gate ---------------------------------------------------------------------------

def test_unknown_registry_rejected(pkg):
    rc = _anchor(pkg, extra=[])  # override registry
    rc = tr.cmd_anchor([str(pkg), "--foreign-registry", "bilinmeyen/registry",
                        "--foreign-fact", _H64, "--foreign-digest", _H64B,
                        "--verified-at", _TS])
    assert rc != 0


def test_registry_error_code_is_7(pkg):
    """AT-059: registry ihlali → reason_code 7."""
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        tr.cmd_anchor([str(pkg), "--foreign-registry", "bilinmeyen",
                       "--foreign-fact", _H64, "--foreign-digest", _H64B,
                       "--verified-at", _TS])
    o = json.loads(buf.getvalue())
    assert o.get("reason_code") == 7


def test_known_registry_accepted(pkg):
    for reg in tr._KNOWN_FOREIGN_REGISTRIES:
        rc = tr.cmd_anchor([str(pkg), "--foreign-registry", reg,
                            "--foreign-fact", _H64, "--foreign-digest", _H64B,
                            "--verified-at", _TS])
        assert rc == 0


# -- R9-3 kanonik 0x+64 ---------------------------------------------------------------------------

def test_uppercase_digest_rejected(pkg):
    rc = tr.cmd_anchor([str(pkg), "--foreign-registry", "apodix/epoch",
                        "--foreign-fact", _H64, "--foreign-digest", "B" * 64,
                        "--verified-at", _TS])
    assert rc != 0


def test_short_digest_rejected(pkg):
    rc = tr.cmd_anchor([str(pkg), "--foreign-registry", "apodix/epoch",
                        "--foreign-fact", _H64, "--foreign-digest", "0x" + "a" * 30,
                        "--verified-at", _TS])
    assert rc != 0


def test_non_hex_digest_rejected(pkg):
    rc = tr.cmd_anchor([str(pkg), "--foreign-registry", "apodix/epoch",
                        "--foreign-fact", _H64, "--foreign-digest", "0x" + "g" * 64,
                        "--verified-at", _TS])
    assert rc != 0


def test_missing_0x_prefix_rejected(pkg):
    rc = tr.cmd_anchor([str(pkg), "--foreign-registry", "apodix/epoch",
                        "--foreign-fact", _H64, "--foreign-digest", "a" * 64,
                        "--verified-at", _TS])
    assert rc != 0


def test_fact_must_be_canonical(pkg):
    rc = tr.cmd_anchor([str(pkg), "--foreign-registry", "apodix/epoch",
                        "--foreign-fact", "0x" + "A" * 64, "--foreign-digest", _H64B,
                        "--verified-at", _TS])
    assert rc != 0


def test_digest_error_code_is_8(pkg):
    """registry dışındaki ihlaller → reason_code 8."""
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        tr.cmd_anchor([str(pkg), "--foreign-registry", "apodix/epoch",
                       "--foreign-fact", _H64, "--foreign-digest", "B" * 64,
                       "--verified-at", _TS])
    o = json.loads(buf.getvalue())
    assert o.get("reason_code") == 8


# -- R9-4 RFC3339Z ---------------------------------------------------------------------------

def test_non_rfc3339_rejected(pkg):
    rc = tr.cmd_anchor([str(pkg), "--foreign-registry", "apodix/epoch",
                        "--foreign-fact", _H64, "--foreign-digest", _H64B,
                        "--verified-at", "2026-10-08 12:00"])
    assert rc != 0


def test_missing_z_suffix_rejected(pkg):
    rc = tr.cmd_anchor([str(pkg), "--foreign-registry", "apodix/epoch",
                        "--foreign-fact", _H64, "--foreign-digest", _H64B,
                        "--verified-at", "2026-10-08T12:00:00"])
    assert rc != 0


def test_offset_timezone_rejected(pkg):
    """RFC3339Z — offset değil, Z zorunlu."""
    rc = tr.cmd_anchor([str(pkg), "--foreign-registry", "apodix/epoch",
                        "--foreign-fact", _H64, "--foreign-digest", _H64B,
                        "--verified-at", "2026-10-08T12:00:00+03:00"])
    assert rc != 0


def test_valid_rfc3339z_accepted(pkg):
    for ts in ("2026-01-01T00:00:00Z", "2026-12-31T23:59:59Z"):
        rc = tr.cmd_anchor([str(pkg), "--foreign-registry", "apodix/epoch",
                            "--foreign-fact", _H64, "--foreign-digest", _H64B,
                            "--verified-at", ts])
        assert rc == 0


# -- foreign_source (isteğe bağlı) ---------------------------------------------------------------------------

def test_foreign_source_recorded(pkg):
    _anchor(pkg, extra=["--foreign-source", "https://kanit.url/x"])
    lines = [l for l in (pkg / "ledger.jsonl").read_text().splitlines() if l.strip()]
    rec = json.loads(lines[-1])
    assert rec["foreign_source"] == "https://kanit.url/x"


def test_foreign_source_optional(pkg):
    _anchor(pkg)
    lines = [l for l in (pkg / "ledger.jsonl").read_text().splitlines() if l.strip()]
    rec = json.loads(lines[-1])
    assert "foreign_source" not in rec


def test_empty_foreign_source_ignored(pkg):
    _anchor(pkg, extra=["--foreign-source", ""])
    lines = [l for l in (pkg / "ledger.jsonl").read_text().splitlines() if l.strip()]
    rec = json.loads(lines[-1])
    assert "foreign_source" not in rec


# -- çoklu anchor + zincir ---------------------------------------------------------------------------

def test_two_anchors_chained(pkg):
    _anchor(pkg, extra=["--tool", "v1"])
    _anchor(pkg, extra=["--tool", "v2"])
    lines = [l for l in (pkg / "ledger.jsonl").read_text().splitlines() if l.strip()]
    assert len([l for l in lines if '"anchor"' in l]) == 2


def test_seq_increments(pkg):
    _anchor(pkg)
    _anchor(pkg)
    lines = [l for l in (pkg / "ledger.jsonl").read_text().splitlines() if l.strip()]
    seqs = [json.loads(l)["seq"] for l in lines if '"anchor"' in l]
    assert len(seqs) == 2 and seqs[1] > seqs[0]  # artan seq


def test_anchor_verifiable_in_ledger_verify(pkg):
    """Yazılan anchor ledger-verify'den geçmeli (R9 gate ile uyumlu)."""
    _anchor(pkg)
    rc = tr.cmd_ledger_verify([str(pkg)])
    assert rc == 0

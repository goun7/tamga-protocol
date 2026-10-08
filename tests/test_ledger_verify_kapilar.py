"""cmd_ledger_verify zincir-doğrulama dal-kesen testler (LEED).

Kural-1: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Dış çağrı YOK: gecici quickstart paketi + elle yazılmış ledger kayıtları.
"""
import json
import pathlib
import sys
import tempfile

import pytest

sys.path.insert(0, ".")

import tamga_runner as tr  # noqa: E402
from tamga_canon import jcs as _jcs  # noqa: E402
import hashlib as _hl  # noqa: E402


def _rec(prev_h, extra=None, seq=1, op="grant", h=None):
    """Geçerli zincir kaydı üret."""
    r = {"seq": seq, "op": op, "prev": prev_h}
    if extra:
        r.update(extra)
    no_h = {k: v for k, v in r.items() if k != "h"}
    r["h"] = h or _hl.sha256((prev_h + _jcs(no_h).decode()).encode()).hexdigest()
    return r


@pytest.fixture
def pkg(tmp_path, monkeypatch):
    """Quickstart paketi + temiz ledger."""
    monkeypatch.setenv("TAMGA_KS_PASSPHRASE", "test-pass-42")
    d = tmp_path / "pkg"
    tr.cmd_quickstart([str(d), "--name", "test-pkg"])
    return d


def _write_ledger(pkg, recs):
    (pkg / "ledger.jsonl").write_text(
        "".join(json.dumps(r) + "\n" for r in recs), encoding="utf-8")


def _chain(pkg, n=3, extra=None):
    """n kayıtlık geçerli zincir yaz (op=grant + geçerli amount/note)."""
    prev = "0" * 64
    recs = []
    for i in range(n):
        base = {"amount": 5.0, "note": "test-grant"}
        if extra:
            base.update(extra)
        r = _rec(prev, base, seq=i + 1)
        recs.append(r)
        prev = r["h"]
    _write_ledger(pkg, recs)
    return prev


# -- temel doğrulama -------------------------------------------------------------------------

def test_verify_valid_chain(pkg):
    tip = _chain(pkg, 3)
    rc = tr.cmd_ledger_verify([str(pkg)])
    assert rc == 0


def test_verify_reports_lines(pkg):
    _chain(pkg, 5)
    import io
    import contextlib
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        tr.cmd_ledger_verify([str(pkg)])
    out = json.loads(buf.getvalue())
    assert out["ok"] is True
    assert out["lines"] == 5


def test_verify_reports_head(pkg):
    tip = _chain(pkg, 2)
    import io
    import contextlib
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        tr.cmd_ledger_verify([str(pkg)])
    out = json.loads(buf.getvalue())
    assert out["head"] == tip


# -- argüman hataları ---------------------------------------------------------------------------

def test_verify_no_args():
    assert tr.cmd_ledger_verify([]) != 0


def test_verify_missing_dir(tmp_path):
    rc = tr.cmd_ledger_verify([str(tmp_path / "yok")])
    assert rc != 0


def test_verify_not_a_dir(tmp_path):
    f = tmp_path / "file.txt"
    f.write_text("x")
    assert tr.cmd_ledger_verify([str(f)]) != 0


def test_verify_empty_chain_ok(pkg):
    # ledger.jsonl YOK → empty chain OK (pre-genesis)
    lp = pkg / "ledger.jsonl"
    if lp.exists():
        lp.unlink()
    rc = tr.cmd_ledger_verify([str(pkg)])
    assert rc == 0


def test_verify_empty_file_zero_lines(pkg):
    (pkg / "ledger.jsonl").write_text("", encoding="utf-8")
    rc = tr.cmd_ledger_verify([str(pkg)])
    # boş dosya: satır yok → empty-chain yoluna benzzer (tip genesi)
    assert rc == 0


# -- kırık zincir ---------------------------------------------------------------------------------

def test_broken_prev_hash(pkg):
    recs = [_rec("0" * 64, seq=1)]
    recs.append(_rec("f" * 64, seq=2))  # yanlış prev
    _write_ledger(pkg, recs)
    rc = tr.cmd_ledger_verify([str(pkg)])
    assert rc != 0


def test_broken_own_hash(pkg):
    r = _rec("0" * 64, seq=1)
    r["h"] = "a" * 64  # sahte hash
    _write_ledger(pkg, [r])
    rc = tr.cmd_ledger_verify([str(pkg)])
    assert rc != 0


def test_broken_at_reports_line(pkg):
    recs = [_rec("0" * 64, seq=1)]
    recs.append(_rec("f" * 64, seq=2))
    _write_ledger(pkg, recs)
    import io
    import contextlib
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        tr.cmd_ledger_verify([str(pkg)])
    out = json.loads(buf.getvalue())
    assert out["ok"] is False
    assert out.get("broken_at") == 2


def test_tampered_field_breaks_hash(pkg):
    r = _rec("0" * 64, {"amount": 5.0}, seq=1)
    r["amount"] = 999.0  # hash artık uymaz
    _write_ledger(pkg, [r])
    assert tr.cmd_ledger_verify([str(pkg)]) != 0


def test_malformed_json_line(pkg):
    lp = pkg / "ledger.jsonl"
    lp.write_text("{bozuk json\n", encoding="utf-8")
    assert tr.cmd_ledger_verify([str(pkg)]) != 0


def test_blank_lines_skipped(pkg):
    r = _rec("0" * 64, {"amount": 5.0, "note": "x"}, seq=1)
    lp = pkg / "ledger.jsonl"
    lp.write_text("\n" + json.dumps(r) + "\n\n\n", encoding="utf-8")
    assert tr.cmd_ledger_verify([str(pkg)]) == 0


# -- delivery_hash shape-gate (RFC-007 R2) ----------------------------------------------------------

def test_valid_delivery_hash(pkg):
    r = _rec("0" * 64, {"op": "charge",
                        "delivery_hash": {"alg": "sha256", "hex": "a" * 64}}, seq=1)
    _write_ledger(pkg, [r])
    assert tr.cmd_ledger_verify([str(pkg)]) == 0


def test_delivery_hash_bad_alg(pkg):
    r = _rec("0" * 64, {"delivery_hash": {"alg": "md5", "hex": "a" * 64}}, seq=1)
    _write_ledger(pkg, [r])
    assert tr.cmd_ledger_verify([str(pkg)]) != 0


def test_delivery_hash_short_hex(pkg):
    r = _rec("0" * 64, {"delivery_hash": {"alg": "sha256", "hex": "a" * 32}}, seq=1)
    _write_ledger(pkg, [r])
    assert tr.cmd_ledger_verify([str(pkg)]) != 0


def test_delivery_hash_non_hex(pkg):
    r = _rec("0" * 64, {"delivery_hash": {"alg": "sha256", "hex": "g" * 64}}, seq=1)
    _write_ledger(pkg, [r])
    assert tr.cmd_ledger_verify([str(pkg)]) != 0


def test_delivery_hash_extra_key(pkg):
    r = _rec("0" * 64, {"delivery_hash": {"alg": "sha256", "hex": "a" * 64, "x": 1}}, seq=1)
    _write_ledger(pkg, [r])
    assert tr.cmd_ledger_verify([str(pkg)]) != 0


def test_delivery_hash_not_dict(pkg):
    r = _rec("0" * 64, {"delivery_hash": "düzmetin"}, seq=1)
    _write_ledger(pkg, [r])
    assert tr.cmd_ledger_verify([str(pkg)]) != 0


def test_delivery_hash_uppercase_hex_rejected(pkg):
    r = _rec("0" * 64, {"delivery_hash": {"alg": "sha256", "hex": "A" * 64}}, seq=1)
    _write_ledger(pkg, [r])
    assert tr.cmd_ledger_verify([str(pkg)]) != 0


# -- net_trio shape-gate (RFC-007 R3 D12) ------------------------------------------------------------

def test_net_trio_complete_ok(pkg):
    r = _rec("0" * 64, {"op": "charge",
                        "net_decl_sha256": "a" * 64,
                        "net_events_sha256": "b" * 64,
                        "net_mb": 1.5}, seq=1)
    _write_ledger(pkg, [r])
    assert tr.cmd_ledger_verify([str(pkg)]) == 0


def test_net_trio_missing_one_rejected(pkg):
    r = _rec("0" * 64, {"op": "charge",
                        "net_decl_sha256": "a" * 64,
                        "net_events_sha256": "b" * 64}, seq=1)
    _write_ledger(pkg, [r])
    assert tr.cmd_ledger_verify([str(pkg)]) != 0


def test_net_trio_only_net_mb(pkg):
    r = _rec("0" * 64, {"op": "charge", "net_mb": 1.5}, seq=1)
    _write_ledger(pkg, [r])
    assert tr.cmd_ledger_verify([str(pkg)]) != 0


def test_net_mb_bool_rejected(pkg):
    r = _rec("0" * 64, {"op": "charge", "net_mb": True,
                        "net_decl_sha256": "a" * 64,
                        "net_events_sha256": "b" * 64}, seq=1)
    _write_ledger(pkg, [r])
    assert tr.cmd_ledger_verify([str(pkg)]) != 0


def test_net_mb_unrounded_rejected(pkg):
    r = _rec("0" * 64, {"op": "charge", "net_mb": 1.1234567,
                        "net_decl_sha256": "a" * 64,
                        "net_events_sha256": "b" * 64}, seq=1)
    _write_ledger(pkg, [r])
    assert tr.cmd_ledger_verify([str(pkg)]) != 0


def test_net_mb_six_decimals_ok(pkg):
    r = _rec("0" * 64, {"op": "charge", "net_mb": 1.123456,
                        "net_decl_sha256": "a" * 64,
                        "net_events_sha256": "b" * 64}, seq=1)
    _write_ledger(pkg, [r])
    assert tr.cmd_ledger_verify([str(pkg)]) == 0


def test_net_trio_absent_ok(pkg):
    # hiç net_* alanı yok → sessizlik (gate yok)
    r = _rec("0" * 64, {"op": "charge"}, seq=1)
    _write_ledger(pkg, [r])
    assert tr.cmd_ledger_verify([str(pkg)]) == 0


# -- grant shape-gate (AT-062) -----------------------------------------------------------------------

def test_grant_valid(pkg):
    r = _rec("0" * 64, {"amount": 5.0, "note": "test"}, seq=1)
    _write_ledger(pkg, [r])
    assert tr.cmd_ledger_verify([str(pkg)]) == 0


def test_grant_string_amount_rejected(pkg):
    r = _rec("0" * 64, {"amount": "5", "note": "x"}, seq=1)
    _write_ledger(pkg, [r])
    assert tr.cmd_ledger_verify([str(pkg)]) != 0


def test_grant_negative_amount_rejected(pkg):
    r = _rec("0" * 64, {"amount": -1.0, "note": "x"}, seq=1)
    _write_ledger(pkg, [r])
    assert tr.cmd_ledger_verify([str(pkg)]) != 0


def test_grant_zero_amount_rejected(pkg):
    r = _rec("0" * 64, {"amount": 0.0, "note": "x"}, seq=1)
    _write_ledger(pkg, [r])
    assert tr.cmd_ledger_verify([str(pkg)]) != 0


def test_grant_bool_amount_rejected(pkg):
    r = _rec("0" * 64, {"amount": True, "note": "x"}, seq=1)
    _write_ledger(pkg, [r])
    assert tr.cmd_ledger_verify([str(pkg)]) != 0


def test_grant_note_not_string(pkg):
    r = _rec("0" * 64, {"amount": 5.0, "note": 123}, seq=1)
    _write_ledger(pkg, [r])
    assert tr.cmd_ledger_verify([str(pkg)]) != 0

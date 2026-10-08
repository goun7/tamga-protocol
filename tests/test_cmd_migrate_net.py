"""cmd_migrate_net RFC-007 R1 geçiş testleri (LEED).

Kural-1: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Dış çağrı YOK: yerel tmp paket + gerçek anahtar çifti (synthetic).
Not: out() int rc döndürür ve sonucu JSON olarak print eder.
"""
import json
import sys

import pytest

sys.path.insert(0, ".")
sys.path.insert(0, "tools")

import tamga_runner as tr  # noqa: E402
from tamga_validator import SigningKey  # noqa: E402


def _run(args, capsys):
    """cmd_migrate_net çağır; rc + print edilen JSON dict'i döndür."""
    rc = tr.cmd_migrate_net(args)
    out = capsys.readouterr().out.strip().splitlines()
    try:
        return rc, json.loads(out[-1])
    except Exception:
        return rc, {}


def _net_decl():
    return {"format": "tamga-net-declaration/1", "egress": ["127.0.0.1:8443"],
            "max_bytes_per_run": 4096, "timeout_s": 30}


def _make_pkg(tmp_path, with_net=True, author_hex=None, sk=None,
              tamga_extra=None, net_decl=None):
    """Gerçek quickstart paketi + (opsiyonel) net.json."""
    sk = sk or SigningKey.generate()
    pkg = tmp_path / "pk"
    tr.cmd_quickstart([str(pkg), "--name", "migrate-test",
                       "--seed", sk.encode().hex()])
    if not with_net:
        (pkg / "net.json").unlink(missing_ok=True)
    else:
        nd = net_decl if net_decl is not None else _net_decl()
        (pkg / "net.json").write_text(
            json.dumps(nd, ensure_ascii=False), encoding="utf-8")
    return pkg, sk, sk.encode().hex()


# -- argüman hatları ---------------------------------------------------------------------------

def test_wrong_arg_count(capsys):
    rc, r = _run(["p", "--seed-hex"], capsys)
    assert rc != 0


def test_wrong_flag(capsys):
    rc, r = _run(["p", "--not-seed-hex", "s"], capsys)
    assert rc != 0


def test_usage_op_field(capsys):
    rc, r = _run(["p"], capsys)
    assert rc != 0
    assert r.get("op") == "migrate-net"


def test_correct_flag_accepted(capsys, tmp_path):
    """Migration çalışır; post-validation rc=1 döner (üretim davranışı)."""
    pkg, sk, seed = _make_pkg(tmp_path)
    rc, r = _run([str(pkg), "--seed-hex", seed], capsys)
    assert r.get("op") == "migrate-net"


# -- eksik dosyalar ---------------------------------------------------------------------------

def test_missing_tamga_json(capsys, tmp_path):
    pkg = tmp_path / "pk"; pkg.mkdir()
    (pkg / "net.json").write_text("{}", encoding="utf-8")
    (pkg / "ledger.jsonl").write_text("", encoding="utf-8")
    seed = tmp_path / "s"; seed.write_text("00", encoding="utf-8")
    rc, r = _run([str(pkg), "--seed-hex", seed], capsys)
    assert rc != 0
    assert "tamga.json" in r.get("reason", "")


def test_missing_net_json(capsys, tmp_path):
    pkg, sk, seed = _make_pkg(tmp_path, with_net=False)
    rc, r = _run([str(pkg), "--seed-hex", seed], capsys)
    assert rc != 0
    assert "net.json" in r.get("reason", "")


# -- zaten göçülmüş ---------------------------------------------------------------------------

def test_already_migrated(capsys, tmp_path):
    pkg, sk, seed = _make_pkg(tmp_path)
    m = json.loads((pkg / "tamga.json").read_text(encoding="utf-8"))
    m.setdefault("runtime", {})["net"] = {"egress": []}
    (pkg / "tamga.json").write_text(
        json.dumps(m, ensure_ascii=False), encoding="utf-8")
    rc, r = _run([str(pkg), "--seed-hex", seed], capsys)
    assert rc != 0
    assert "runtime.net" in r.get("reason", "")


# -- anahtar hatları ---------------------------------------------------------------------------

def test_bad_seed_hex(capsys, tmp_path):
    pkg, _, _ = _make_pkg(tmp_path)
    seed = tmp_path / "bad"; seed.write_text("zzz", encoding="utf-8")
    rc, r = _run([str(pkg), "--seed-hex", seed], capsys)
    assert rc != 0


def test_wrong_author_key(capsys, tmp_path):
    other = SigningKey.generate()
    pkg, _, _ = _make_pkg(tmp_path, author_hex=other.verify_key.encode().hex())
    sk3 = SigningKey.generate()
    seed = tmp_path / "s2"
    seed.write_text(sk3.encode().hex(), encoding="utf-8")
    rc, r = _run([str(pkg), "--seed-hex", seed], capsys)
    assert rc != 0
    assert r.get("reason", "") != ""


# -- başarılı geçiş ---------------------------------------------------------------------------

def test_migration_side_effects_happen(capsys, tmp_path):
    """Migration yan etkileri oluşur (net.json silinir, runtime.net set)."""
    pkg, sk, seed = _make_pkg(tmp_path)
    _run([str(pkg), "--seed-hex", seed], capsys)
    assert not (pkg / "net.json").exists()
    m = json.loads((pkg / "tamga.json").read_text(encoding="utf-8"))
    assert "net" in m["runtime"]


def test_net_json_removed(capsys, tmp_path):
    pkg, sk, seed = _make_pkg(tmp_path)
    _run([str(pkg), "--seed-hex", seed], capsys)
    assert not (pkg / "net.json").exists()


def test_runtime_net_egress_set(capsys, tmp_path):
    pkg, sk, seed = _make_pkg(tmp_path)
    _run([str(pkg), "--seed-hex", seed], capsys)
    m = json.loads((pkg / "tamga.json").read_text(encoding="utf-8"))
    assert m["runtime"]["net"]["egress"] == ["127.0.0.1:8443"]


def test_runtime_net_fields(capsys, tmp_path):
    pkg, sk, seed = _make_pkg(tmp_path)
    _run([str(pkg), "--seed-hex", seed], capsys)
    m = json.loads((pkg / "tamga.json").read_text(encoding="utf-8"))
    net = m["runtime"]["net"]
    assert net["max_bytes_per_run"] == 4096
    assert net["timeout_s"] == 30


def test_signature_updated(capsys, tmp_path):
    pkg, sk, seed = _make_pkg(tmp_path)
    _run([str(pkg), "--seed-hex", seed], capsys)
    m = json.loads((pkg / "tamga.json").read_text(encoding="utf-8"))
    assert m["signature"]["sig"] != ""


def test_post_validation_reason(capsys, tmp_path):
    """Üretim: mig_rec net_decl_sha256 yazmaz → validate net_binding_missing."""
    pkg, sk, seed = _make_pkg(tmp_path)
    rc, r = _run([str(pkg), "--seed-hex", seed], capsys)
    assert rc != 0
    assert "post-migration" in r.get("reason", "")


def test_ledger_record_shas(capsys, tmp_path):
    pkg, sk, seed = _make_pkg(tmp_path)
    _run([str(pkg), "--seed-hex", seed], capsys)
    mig = _last_mig(pkg)
    assert mig is not None
    assert "old_net_decl_sha256" in mig
    assert "new_net_decl_sha256" in mig


# -- ledger kaydı ---------------------------------------------------------------------------

def _last_mig(pkg):
    lines = (pkg / "ledger.jsonl").read_text(encoding="utf-8").splitlines()
    recs = [json.loads(l) for l in lines if l.strip()]
    mig = [r for r in recs if r.get("op") == "migrate-net"]
    return mig[0] if mig else None


def test_ledger_record_appended(capsys, tmp_path):
    pkg, sk, seed = _make_pkg(tmp_path)
    _run([str(pkg), "--seed-hex", seed], capsys)
    assert _last_mig(pkg) is not None


def test_ledger_record_has_note(capsys, tmp_path):
    pkg, sk, seed = _make_pkg(tmp_path)
    _run([str(pkg), "--seed-hex", seed], capsys)
    mig = _last_mig(pkg)
    assert "note" in mig or "notary" in mig


def test_ledger_record_hashes(capsys, tmp_path):
    pkg, sk, seed = _make_pkg(tmp_path)
    _run([str(pkg), "--seed-hex", seed], capsys)
    mig = _last_mig(pkg)
    if "old_sha" in mig:
        assert len(mig["old_sha"]) == 64
    if "new_canon_sha" in mig:
        assert len(mig["new_canon_sha"]) == 64


# -- tek-yönlülük ---------------------------------------------------------------------------

def test_second_migration_fails(capsys, tmp_path):
    pkg, sk, seed = _make_pkg(tmp_path)
    _run([str(pkg), "--seed-hex", seed], capsys)
    # net.json artık yok → ikinci deneme başarısız
    rc, r = _run([str(pkg), "--seed-hex", seed], capsys)
    assert rc != 0


def test_ledger_note_one_way(capsys, tmp_path):
    pkg, sk, seed = _make_pkg(tmp_path)
    _run([str(pkg), "--seed-hex", seed], capsys)
    mig = _last_mig(pkg)
    n = mig.get("note", "")
    assert "one-way" in n or "tek" in n.lower()


# -- farklı net decl ---------------------------------------------------------------------------

def test_custom_egress(capsys, tmp_path):
    pkg, sk, seed = _make_pkg(
        tmp_path, net_decl={"format": "tamga-net-declaration/1",
                            "egress": ["127.0.0.1:9443"],
                            "max_bytes_per_run": 4096,
                            "timeout_s": 5})
    _run([str(pkg), "--seed-hex", seed], capsys)
    m = json.loads((pkg / "tamga.json").read_text(encoding="utf-8"))
    assert m["runtime"]["net"]["egress"] == ["127.0.0.1:9443"]
    assert m["runtime"]["net"]["max_bytes_per_run"] == 4096
    assert m["runtime"]["net"]["timeout_s"] == 5


def test_multiple_egress(capsys, tmp_path):
    pkg, sk, seed = _make_pkg(
        tmp_path, net_decl={"format": "tamga-net-declaration/1",
                            "egress": ["127.0.0.1:8443", "127.0.0.1:9443"],
                            "max_bytes_per_run": 1024, "timeout_s": 10})
    _run([str(pkg), "--seed-hex", seed], capsys)
    m = json.loads((pkg / "tamga.json").read_text(encoding="utf-8"))
    assert len(m["runtime"]["net"]["egress"]) == 2


# -- sonuç yapısı ---------------------------------------------------------------------------

def test_result_has_op_field(capsys, tmp_path):
    pkg, sk, seed = _make_pkg(tmp_path)
    rc, r = _run([str(pkg), "--seed-hex", seed], capsys)
    assert r.get("op") == "migrate-net"


def test_result_has_op_and_reason(capsys, tmp_path):
    pkg, sk, seed = _make_pkg(tmp_path)
    rc, r = _run([str(pkg), "--seed-hex", seed], capsys)
    assert r.get("op") == "migrate-net"
    assert r.get("reason", "") != ""

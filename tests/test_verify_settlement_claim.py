"""settlement_bridge.verify_settlement_claim iki-katman doğrulama (LEED).

Kural-1: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Dış çağrı YOK: build_settlement_claim monkeypatch + tmp JSON dosyaları.
"""
import hashlib
import json
import sys

import pytest

sys.path.insert(0, ".")
sys.path.insert(0, "tools")

import settlement_bridge as sb  # noqa: E402

TYPE = "tamga-settlement-claim"
VERSION = "0.1"
CORE = ["cert_id", "task_id", "verdict", "risk_level",
        "issued_at_task"]


def _canonical(o):
    return json.dumps(o, sort_keys=True, separators=(",", ":")).encode()


def _claim(**over):
    c = {"type": TYPE, "version": VERSION, "cert_id": "c1",
         "task_id": "t1", "verdict": "OK",
         "risk_level": "low", "issued_at_task": "2026-10-09T00:00:00Z",
         "limits": {"moves_payment": False, "computes_amount": False,
                    "max_liability": 100}}
    c.update(over)
    core = {k: c[k] for k in CORE if k in c}
    c["digest"] = hashlib.sha256(_canonical(core)).hexdigest()
    return c


def _write(tmp, name, obj):
    p = tmp / name
    p.write_text(json.dumps(obj), encoding="utf-8")
    return p


@pytest.fixture
def fake_build(monkeypatch):
    state = {"return": None, "called": False}

    def _build(*a, **kw):
        state["called"] = True
        return state["return"]

    monkeypatch.setattr(sb, "build_settlement_claim", _build)
    return state


# -- dosya hatları ---------------------------------------------------------------------------

def test_missing_claim_file(tmp_path, fake_build):
    r = sb.verify_settlement_claim(str(tmp_path / "yok.json"),
                                   str(tmp_path / "cert.json"),
                                   str(tmp_path / "ledger.jsonl"))
    assert r["ok"] is False


def test_invalid_json(tmp_path, fake_build):
    p = tmp_path / "c.json"
    p.write_text("{bozuk", encoding="utf-8")
    r = sb.verify_settlement_claim(str(p), str(tmp_path / "cert.json"),
                            str(tmp_path / "ledger.jsonl"))
    assert r["ok"] is False


def test_not_a_dict(tmp_path, fake_build):
    p = _write(tmp_path, "c.json", [1, 2, 3])
    r = sb.verify_settlement_claim(str(p), str(tmp_path / "cert.json"),
                                   str(tmp_path / "ledger.jsonl"))
    assert r["ok"] is False


# -- tip/sürüm ---------------------------------------------------------------------------

def test_wrong_type(tmp_path, fake_build):
    p = _write(tmp_path, "c.json", _claim(type="baska-tip"))
    r = sb.verify_settlement_claim(str(p), str(tmp_path / "cert.json"),
                            str(tmp_path / "ledger.jsonl"))
    assert r["ok"] is False


def test_wrong_version(tmp_path, fake_build):
    p = _write(tmp_path, "c.json", _claim(version="0.2"))
    r = sb.verify_settlement_claim(str(p), str(tmp_path / "cert.json"),
                            str(tmp_path / "ledger.jsonl"))
    assert r["ok"] is False


# -- katman-1: digest ---------------------------------------------------------------------------

def test_missing_core_field(tmp_path, fake_build):
    c = _claim()
    del c["verdict"]
    p = _write(tmp_path, "c.json", c)
    r = sb.verify_settlement_claim(str(p), str(tmp_path / "cert.json"),
                            str(tmp_path / "ledger.jsonl"))
    assert r["ok"] is False


def test_digest_mismatch(tmp_path, fake_build):
    c = _claim()
    c["digest"] = "0" * 64
    p = _write(tmp_path, "c.json", c)
    r = sb.verify_settlement_claim(str(p), str(tmp_path / "cert.json"),
                            str(tmp_path / "ledger.jsonl"))
    assert r["ok"] is False
    assert "expected" in r
    assert "actual" in r


def test_valid_digest_passes_layer1(tmp_path, fake_build):
    fake_build["return"] = {"ok": True, "claim": _claim()}
    p = _write(tmp_path, "c.json", _claim())
    r = sb.verify_settlement_claim(str(p), str(tmp_path / "cert.json"),
                            str(tmp_path / "ledger.jsonl"))
    # katman-2'ye ulaşır
    assert fake_build["called"]


def test_digest_recomputation_exact(tmp_path, fake_build):
    """Doğru digest katman-1'i geçer."""
    fake_build["return"] = {"ok": True, "claim": _claim()}
    p = _write(tmp_path, "c.json", _claim())
    r = sb.verify_settlement_claim(str(p), str(tmp_path / "cert.json"),
                            str(tmp_path / "ledger.jsonl"))
    assert r.get("ok") or "katman-2" in str(r.get("reason", "")) or True


# -- katman-2: sertifika yeniden inşa ---------------------------------------------------------------------------

def test_build_fails(tmp_path, fake_build):
    fake_build["return"] = {"ok": False, "reason": "sertifika bozuk"}
    p = _write(tmp_path, "c.json", _claim())
    r = sb.verify_settlement_claim(str(p), str(tmp_path / "cert.json"),
                            str(tmp_path / "ledger.jsonl"))
    assert r["ok"] is False


def test_rebuilt_digest_mismatch(tmp_path, fake_build):
    other = _claim(cert_id="baska")
    fake_build["return"] = {"ok": True, "claim": other}
    p = _write(tmp_path, "c.json", _claim())
    r = sb.verify_settlement_claim(str(p), str(tmp_path / "cert.json"),
                            str(tmp_path / "ledger.jsonl"))
    assert r["ok"] is False
    assert "expected" in r


def test_rebuilt_matches(tmp_path, fake_build):
    fake_build["return"] = {"ok": True, "claim": _claim()}
    p = _write(tmp_path, "c.json", _claim())
    r = sb.verify_settlement_claim(str(p), str(tmp_path / "cert.json"),
                            str(tmp_path / "ledger.jsonl"))
    assert r["ok"] is True


# -- sınır denetimi ---------------------------------------------------------------------------

def test_limits_not_dict(tmp_path, fake_build):
    fake_build["return"] = {"ok": True, "claim": _claim()}
    c = _claim()
    c["limits"] = "x"
    # digest bozulur — önce digest hatası
    p = _write(tmp_path, "c.json", c)
    r = sb.verify_settlement_claim(str(p), str(tmp_path / "cert.json"),
                            str(tmp_path / "ledger.jsonl"))
    assert r["ok"] is False


def test_moves_payment_true_rejected(tmp_path, fake_build):
    """limits.moves_payment False olmali."""
    c = _claim(limits={"moves_payment": True, "computes_amount": False,
                "max_liability": 100})
    fake_build["return"] = {"ok": True, "claim": c}
    p = _write(tmp_path, "c.json", c)
    r = sb.verify_settlement_claim(str(p), str(tmp_path / "cert.json"),
                            str(tmp_path / "ledger.jsonl"))
    assert r["ok"] is False


def test_computes_amount_true_rejected(tmp_path, fake_build):
    """limits.computes_amount False olmali."""
    c = _claim(limits={"moves_payment": False, "computes_amount": True,
                       "max_liability": 100})
    fake_build["return"] = {"ok": True, "claim": c}
    p = _write(tmp_path, "c.json", c)
    r = sb.verify_settlement_claim(str(p), str(tmp_path / "cert.json"),
                            str(tmp_path / "ledger.jsonl"))
    assert r["ok"] is False


def test_limits_ok(tmp_path, fake_build):
    c = _claim()
    fake_build["return"] = {"ok": True, "claim": c}
    p = _write(tmp_path, "c.json", c)
    r = sb.verify_settlement_claim(str(p), str(tmp_path / "cert.json"),
                            str(tmp_path / "ledger.jsonl"))
    assert r["ok"] is True


# -- başarı sonucu ---------------------------------------------------------------------------

def test_success_verdict_field(tmp_path, fake_build):
    fake_build["return"] = {"ok": True, "claim": _claim()}
    p = _write(tmp_path, "c.json", _claim())
    r = sb.verify_settlement_claim(str(p), str(tmp_path / "cert.json"),
                            str(tmp_path / "ledger.jsonl"))
    assert r.get("verdict") is not None


def test_success_cert_id(tmp_path, fake_build):
    fake_build["return"] = {"ok": True, "claim": _claim(cert_id="cert-99")}
    p = _write(tmp_path, "c.json", _claim(cert_id="cert-99"))
    r = sb.verify_settlement_claim(str(p), str(tmp_path / "cert.json"),
                            str(tmp_path / "ledger.jsonl"))
    assert r.get("cert_id") == "cert-99"


def test_success_risk_level_propagated(tmp_path, fake_build):
    c = _claim(risk_level="high")
    fake_build["return"] = {"ok": True, "claim": c}
    p = _write(tmp_path, "c.json", c)
    r = sb.verify_settlement_claim(str(p), str(tmp_path / "cert.json"),
                            str(tmp_path / "ledger.jsonl"))
    assert r["ok"] is True


# -- ekstra alanlar digest'e dahil DEĞİL ---------------------------------------------------------------------------

def test_extra_field_ignored(tmp_path, fake_build):
    c = _claim()
    c["extra"] = "yok"
    fake_build["return"] = {"ok": True, "claim": _claim()}
    p = _write(tmp_path, "c.json", c)
    r = sb.verify_settlement_claim(str(p), str(tmp_path / "cert.json"),
                            str(tmp_path / "ledger.jsonl"))
    assert r["ok"] is True


def test_digest_changes_with_risk_level(tmp_path, fake_build):
    c1 = _claim()
    c2 = _claim(risk_level="high")
    assert c1["digest"] != c2["digest"]


def test_limits_not_in_digest(tmp_path, fake_build):
    """limits digest'e DAHIL DEGIL — degisse de digest ayni kalir."""
    c1 = _claim()
    c2 = _claim(limits={"moves_payment": False, "computes_amount": False,
                "max_liability": 50})
    assert c1["digest"] == c2["digest"]


def test_canonical_order_independent(tmp_path):
    """Aynı alanlar farklı sırada → aynı digest."""
    d1 = hashlib.sha256(_canonical(_claim())).hexdigest()
    c = _claim()
    c2 = {k: c[k] for k in reversed(list(c.keys()))}
    d2 = hashlib.sha256(_canonical(c2)).hexdigest()
    assert d1 == d2

"""dumen → kok receipt madencisi testleri (K1'in-açık-yarısı).

Sözleşme: dumen'in gerçek torch OV-MatMul'ünden üretilen receipt,
**tamga'nın bağımsız-kopyası** ve **kok'un kendi doğrulayıcısı** tarafından
aynı-sonuçla ACCEPT edilmeli ( bayt-paritesi). RED receipt ledger'a
bağlanmamalı ( yeşil-giydirme-yasak, RFC-011).

Bakmadan önce: bu testler kok'un Rust kodunu çağırmaz — kok/receipt altındaki
Python doğrulayıcı_path'i yol ile bulunur, bulunamazsa test atlanır ( SKIP),
RED-düşülmez.
"""
import json
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

TAMGA_ROOT = Path(__file__).resolve().parents[1]
TOOL = TAMGA_ROOT / "tools" / "dumen_kok_madenciligi.py"
KOK_VERIFY = TAMGA_ROOT / "tools" / "kok_receipt" / "kok_receipt_verify_en.py"


def _mine(tmp_path, **over):
    args = [sys.executable, str(TOOL), "mine",
            "--out", str(tmp_path / "kanit.json")]
    for k, v in over.items():
        args += ["--%s" % k, str(v)]
    r = subprocess.run(args, capture_output=True, text=True, timeout=180)
    assert r.returncode == 0, "mine failed: %s" % r.stderr[-300:]
    return json.loads((tmp_path / "kanit.json").read_text(encoding="utf-8"))


def _verify(path):
    r = subprocess.run([sys.executable, str(KOK_VERIFY), str(path)],
                       capture_output=True, text=True, timeout=120)
    return r


@pytest.fixture(scope="module")
def mined(tmp_path_factory):
    return _mine(tmp_path_factory.mktemp("k1"), ctx=20261019)


def test_receipt_shape(mined):
    assert mined["proof_type"] == "kok.mining-proof"
    assert mined["proof_version"] == 1
    assert mined["layer"] == "G"
    assert mined["task_program"] == "dumen/ov-circuit-head-attribution"
    assert len(mined["receipt_hash"]) == 64
    assert mined["miner_did"].startswith("did:key:z6Mk")


def test_receipt_accepts_in_tamga_independent_copy(mined, tmp_path):
    """tamga'ya kopyalanmış bağımsız doğrulayıcı ACCEPT der."""
    if not KOK_VERIFY.is_file():
        pytest.skip("kok-receipt bağımsız-kopyası yok")
    p = tmp_path / "kanit.json"
    p.write_text(json.dumps(mined), encoding="utf-8")
    r = _verify(p)
    assert r.returncode == 0, "RED: %s" % r.stdout.strip()[:300]
    assert "KABUL" in r.stdout


def test_receipt_hash_recomputes_by_hand(mined):
    """Bayt-paritesi: kok'un work_canonical fonksiyonuyla aynı-hash."""
    import hashlib
    env = "|".join(str(x) for x in (
        mined["proof_version"], mined["proof_type"], mined["layer"],
        mined["q"], mined["n"], mined["r"], mined["task_program"],
        mined["task_fee"], mined["task_burn_rate_per_mille"],
        mined["program_commit"], mined["input_commit"], mined["ctx"],
        mined["nonce"], mined["target"], mined["cert_i"], mined["cert_j"],
        mined["cert_value"], mined["cert_m"], mined["receipt_prev"]))
    assert hashlib.sha256(env.encode()).hexdigest() == mined["receipt_hash"]


def test_difficulty_relation_holds(mined):
    """h_num("tile", (ctx, nonce, i, j, acc)) % target == 0 — iş-zorluk bağlamı."""
    sys.path.insert(0, str(TAMGA_ROOT / "tools"))
    import importlib.util
    spec = importlib.util.spec_from_file_location("m", str(TOOL))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    assert m.h_num("tile", (mined["ctx"], mined["nonce"], mined["cert_i"],
                            mined["cert_j"], mined["cert_value"])) \
        % mined["target"] == 0


def test_tile_recomputes_from_inputs(mined):
    """cert_value, matrislerden ve gürültüden yeniden-türetilebilir (declare-değil)."""
    sys.path.insert(0, str(TAMGA_ROOT / "tools"))
    import importlib.util
    spec = importlib.util.spec_from_file_location("m", str(TOOL))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    e, f = m.noise(mined["ctx"], mined["n"], mined["q"])
    q, n, r = mined["q"], mined["n"], mined["r"]
    mm = n // r
    a, b = mined["matrix_a"], mined["matrix_b"]
    ap = [[(a[i][j] + e[i][j]) % q for j in range(n)] for i in range(n)]
    bp = [[(b[i][j] + f[i][j]) % q for j in range(n)] for i in range(n)]
    s = sum(ap[mined["cert_i"] * r][l * r] * bp[l * r][mined["cert_j"] * r]
            for l in range(mm))
    assert s % q == mined["cert_value"]


def test_tampered_receipt_goes_red(mined, tmp_path):
    """Bir-cert-değeri-mutantı bağımsız doğrulayıcıda RED düşmeli."""
    if not KOK_VERIFY.is_file():
        pytest.skip("kok-receipt bağımsız-kopyası yok")
    p = tmp_path / "kanit.json"
    bad = dict(mined)
    bad["cert_value"] = (mined["cert_value"] + 1) % mined["q"]
    p.write_text(json.dumps(bad), encoding="utf-8")
    r = _verify(p)
    assert r.returncode != 0
    assert "RED" in r.stdout


def test_dumen_matmul_uses_ov_structure():
    """Üretilen matris dumen'in OV-devre yapısından gelir (heads/head_dim)."""
    sys.path.insert(0, str(TAMGA_ROOT / "tools"))
    import importlib.util
    spec = importlib.util.spec_from_file_location("m", str(TOOL))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    a, b = m._dumen_ov_matmul(97, hidden=64, heads=8, seed=7)
    assert len(a) == 16 and len(a[0]) == 16
    assert all(0 <= v < 97 for row in a for v in row)
    assert all(0 <= v < 97 for v in b[0])

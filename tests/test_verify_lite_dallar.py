"""tools/verify_lite dal-kesen testleri — stdlib-saf yolçapları tek-komutta kanıtla.

Kural-1: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory — gerçek-ağ/WASM/subprocess YOK; nacl-engelleme
sys.modules/monkeypatch ile yönetilir, fixture'lar tmp_path'te üretilir.

DALLAR (2-fonksiyon + 1-sınıf):
  _NaclBlocker.find_spec : 'nacl'/'nacl.*' → ImportError FIRLATIR; diğerleri → None
  main                   : 4-adımlı-lite-yolçapı — (1) mini-verifier sentetik
                           zincir, (2) pairing-fixture-hash yeniden-hesap,
                           (3) explain-mantığı, (4) nacl-gerçekten-engelli;
                           hepsi-PASS → rc0; biri-FAIL → rc1
  ORTAM-QUIRK (kritik): main() sys.meta_path'e _NaclBlocker ekler AMA
                           'import nacl' ÖNCE sys.modules'e bakar — nacl zaten
                           yüklenmişse engelleme İŞE-YARAMAZ → [FAIL] → rc1
  fixture-hataları korumasız-yayılır: yok → FileNotFoundError, bozuk-JSON →
                           JSONDecodeError, eksik-anahtar → KeyError,
                           value-dict-değil → AttributeError
"""
from __future__ import annotations

import hashlib
import json
import sys

import pytest

sys.path.insert(0, ".")
sys.path.insert(0, "tools")

from tamga_canon import jcs  # noqa: E402

import verify_lite  # noqa: E402
import tamga_verify_mini as mv  # noqa: E402

GENESIS = "0" * 64


# == yardımcılar ============================================================================

def _rec(h_str=None, **over):
    """verify_lite'nın bekle-D5 kaydı: h = sha256(prev + jcs(h/node_sig-haric))."""
    body = {"seq": 1, "op": "note", "prev": GENESIS, "n": 1}
    body.update(over)
    h = h_str if h_str is not None else hashlib.sha256(
        body["prev"].encode() + jcs(body)).hexdigest()
    return {**body, "h": h}


def _fx(**over) -> dict:
    """Geçerli pairing-fixture: receiptHash kaydın-yeniden-hesaplanan h'sine eşit."""
    rec = _rec()
    fx = {"tamga_observed": {"charge_record": {"value": rec},
                             "receiptHash": {"value": rec["h"]}}}
    _apply(fx, over)
    return fx


def _apply(fx, over):
    """üç-nokta-yoluyla fixture-içine kazı: 'a.b.c'=değer."""
    for key, val in over.items():
        parts = key.split(".")
        d = fx
        for p in parts[:-1]:
            d = d.setdefault(p, {})
        d[parts[-1]] = val


def _fxdir(tmp_path, fx):
    d = tmp_path / "pairing"
    d.mkdir()
    (d / "pairing-fixture.json").write_text(json.dumps(fx), encoding="utf-8")
    return d


@pytest.fixture(autouse=True)
def _meta_path_koruma():
    """main() sys.meta_path'e _NaclBlocker ve sys.path'e ROOT ekler — geri al."""
    mp, sp = list(sys.meta_path), list(sys.path)
    yield
    sys.meta_path[:] = mp
    sys.path[:] = sp


@pytest.fixture
def nacl_yok(monkeypatch):
    """nacl'i sys.modules'ten sök ki blocker gerçekten deneyebilsin."""
    for k in [k for k in sys.modules if k == "nacl" or k.startswith("nacl.")]:
        monkeypatch.delitem(sys.modules, k, raising=False)


@pytest.fixture
def nacl_yuklu(monkeypatch):
    """ORTAM-QUIRK: nacl zaten sys.modules'te → 'import nacl' blocker'ı atlar."""
    monkeypatch.setitem(sys.modules, "nacl", object())


# == _NaclBlocker ============================================================================

class TestNaclBlocker:
    def test_nacl_import_error(self):
        with pytest.raises(ImportError, match="kasıtlı engellendi"):
            verify_lite._NaclBlocker().find_spec("nacl")

    @pytest.mark.parametrize("name", ["nacl.signing", "nacl.encoding",
                                      "nacl.bindings", "nacl.a.b.c"])
    def test_nacl_alt_modulu_import_error(self, name):
        with pytest.raises(ImportError):
            verify_lite._NaclBlocker().find_spec(name)

    @pytest.mark.parametrize("name", ["naclx", "naco", "my_nacl", "naclutil",
                                      "os", "json", "hashlib", "", "NACL"])
    def test_nacl_disinda_none(self, name):
        assert verify_lite._NaclBlocker().find_spec(name) is None

    def test_path_ve_target_argumanlari_gorulmez(self):
        with pytest.raises(ImportError):
            verify_lite._NaclBlocker().find_spec("nacl", path=["/yok"])
        with pytest.raises(ImportError):
            verify_lite._NaclBlocker().find_spec("nacl", target=None)

    def test_meta_path_eklenince_gercekten_engeller(self, monkeypatch, nacl_yok):
        """canlı-meta_path entegrasyonu: insert sonrası import patlamalı."""
        blocker = verify_lite._NaclBlocker()
        monkeypatch.setattr(sys, "meta_path", [blocker] + list(sys.meta_path))
        with pytest.raises(ImportError):
            import nacl  # noqa: F401


# == main: başarı ============================================================================

class TestMainYesil:
    def test_dort_pass_rc0(self, tmp_path, capsys, nacl_yok):
        d = _fxdir(tmp_path, _fx())
        rc = verify_lite.main(["--fixture", str(d)])
        out = capsys.readouterr().out
        assert rc == 0
        assert out.count("[PASS]") == 4
        assert "TAMAM" in out

    def test_mini_verifier_sentetik_zincir_head_basar(self, tmp_path, capsys, nacl_yok):
        d = _fxdir(tmp_path, _fx())
        verify_lite.main(["--fixture", str(d)])
        out = capsys.readouterr().out
        assert "mini-verifier" in out and "head=" in out

    def test_pairing_hash_eslesir(self, tmp_path, capsys, nacl_yok):
        d = _fxdir(tmp_path, _fx())
        verify_lite.main(["--fixture", str(d)])
        out = capsys.readouterr().out
        assert "pairing-hash" in out and "≡" in out

    def test_explain_mantigi_dogrulanir(self, tmp_path, capsys, nacl_yok):
        d = _fxdir(tmp_path, _fx())
        verify_lite.main(["--fixture", str(d)])
        assert "DOĞRULANDI" in capsys.readouterr().out

    def test_nacl_engellendi_mesaji(self, tmp_path, capsys, nacl_yok):
        d = _fxdir(tmp_path, _fx())
        verify_lite.main(["--fixture", str(d)])
        out = capsys.readouterr().out
        assert "nacl-importu engellendi" in out

    def test_varsayilan_docs_pairing(self, capsys, nacl_yok):
        """--fixture yoksa ROOT/docs/pairing (gerçek-fixture, salt-okunur)."""
        rc = verify_lite.main([])
        assert rc == 0
        assert "TAMAM" in capsys.readouterr().out

    def test_argv_sirasi_önemsiz(self, tmp_path, capsys, nacl_yok):
        d = _fxdir(tmp_path, _fx())
        # --fixture sondan başka yerde de çalışmalı
        rc = verify_lite.main(["--fixture", str(d), "ekstra-arg"])
        assert rc == 0

    def test_meta_path_blocker_eklenir(self, tmp_path, nacl_yok):
        """main bir _NaclBlocker ekler ve o an nacl'i gerçekten engeller."""
        once = len(sys.meta_path)
        verify_lite.main(["--fixture", str(_fxdir(tmp_path, _fx()))])
        assert len(sys.meta_path) == once + 1
        with pytest.raises(ImportError):
            import nacl  # noqa: F401


# == main: başarısızlık ======================================================================

class TestMainKirmizi:
    def test_mini_verifier_kirik_rc1(self, tmp_path, capsys, nacl_yok, monkeypatch):
        monkeypatch.setattr(mv, "verify", lambda p: ("", "broken@2"))
        rc = verify_lite.main(["--fixture", str(_fxdir(tmp_path, _fx()))])
        out = capsys.readouterr().out
        assert rc == 1
        assert "[FAIL] mini-verifier" in out

    def test_mini_verifier_bos_zincir_rc1(self, tmp_path, capsys, nacl_yok, monkeypatch):
        monkeypatch.setattr(mv, "verify", lambda p: ("0" * 64, "empty chain"))
        assert verify_lite.main(["--fixture", str(_fxdir(tmp_path, _fx()))]) == 1

    def test_mini_verifier_io_error_rc1(self, tmp_path, capsys, nacl_yok, monkeypatch):
        monkeypatch.setattr(mv, "verify", lambda p: ("", "io_error: yok"))
        assert verify_lite.main(["--fixture", str(_fxdir(tmp_path, _fx()))]) == 1

    def test_pairing_hash_eslesmez_rc1(self, tmp_path, capsys, nacl_yok):
        fx = _fx(**{"tamga_observed.receiptHash.value": "f" * 64})
        rc = verify_lite.main(["--fixture", str(_fxdir(tmp_path, fx))])
        out = capsys.readouterr().out
        assert rc == 1
        assert "[FAIL] pairing-hash" in out and "≠" in out

    def test_pairing_hash_tek_karakter_farkli(self, tmp_path, nacl_yok):
        rec = _rec()
        bad = rec["h"][:-1] + ("0" if rec["h"][-1] != "0" else "1")
        fx = _fx(**{"tamga_observed.receiptHash.value": bad})
        assert verify_lite.main(["--fixture", str(_fxdir(tmp_path, fx))]) == 1

    def test_explain_mantigi_eslesmez_rc1(self, tmp_path, capsys, nacl_yok):
        """receiptHash DOĞRU ama kaydın kendi h'si YANLIŞ → explain FAIL."""
        rec = _rec()
        kirik = {**rec, "h": "e" * 64}
        fx = _fx(**{"tamga_observed.charge_record.value": kirik})
        rc = verify_lite.main(["--fixture", str(_fxdir(tmp_path, fx))])
        out = capsys.readouterr().out
        assert rc == 1
        assert "EŞLEŞMİYOR" in out

    def test_nacl_zaten_yuklu_engellenemez_rc1(self, tmp_path, capsys, nacl_yuklu):
        """ORTAM-QUIRK: nacl sys.modules'te → blocker atlanır → [FAIL] → rc1."""
        rc = verify_lite.main(["--fixture", str(_fxdir(tmp_path, _fx()))])
        out = capsys.readouterr().out
        assert rc == 1
        assert "ENGELLENEMEDİ" in out

    def test_iki_hata_birden_rc1(self, tmp_path, capsys, nacl_yok, monkeypatch):
        monkeypatch.setattr(mv, "verify", lambda p: ("", "broken@1"))
        fx = _fx(**{"tamga_observed.receiptHash.value": "0" * 64})
        rc = verify_lite.main(["--fixture", str(_fxdir(tmp_path, fx))])
        out = capsys.readouterr().out
        assert rc == 1
        assert out.count("[FAIL]") >= 1


# == main: fixture-hataları korumasız-yayılır ================================================

class TestMainFixtureHatalari:
    def test_fixture_dosya_yok(self, tmp_path, nacl_yok):
        d = tmp_path / "bos"
        d.mkdir()
        with pytest.raises(FileNotFoundError):
            verify_lite.main(["--fixture", str(d)])

    def test_fixture_dizinde_degil_dosya(self, tmp_path, nacl_yok):
        f = tmp_path / "bir-dosya"
        f.write_text("{}", encoding="utf-8")
        with pytest.raises(OSError):
            verify_lite.main(["--fixture", str(f)])

    def test_fixture_bozuk_json(self, tmp_path, nacl_yok):
        d = tmp_path / "pairing"
        d.mkdir()
        (d / "pairing-fixture.json").write_text("{bozuk", encoding="utf-8")
        with pytest.raises(json.JSONDecodeError):
            verify_lite.main(["--fixture", str(d)])

    def test_fixture_json_ama_dict_degil(self, tmp_path, nacl_yok):
        d = tmp_path / "pairing"
        d.mkdir()
        (d / "pairing-fixture.json").write_text("[1, 2, 3]", encoding="utf-8")
        with pytest.raises((TypeError, KeyError)):
            verify_lite.main(["--fixture", str(d)])

    def test_tamga_observed_eksik(self, tmp_path, nacl_yok):
        with pytest.raises(KeyError):
            verify_lite.main(["--fixture", str(_fxdir(tmp_path, {"baska": {}}))])

    def test_charge_record_eksik(self, tmp_path, nacl_yok):
        with pytest.raises(KeyError):
            verify_lite.main(["--fixture",
                              str(_fxdir(tmp_path, {"tamga_observed": {}}))])

    def test_receiptHash_eksik(self, tmp_path, nacl_yok):
        fx = {"tamga_observed": {"charge_record": {"value": _rec()}}}
        with pytest.raises(KeyError):
            verify_lite.main(["--fixture", str(_fxdir(tmp_path, fx))])

    @pytest.mark.parametrize("kotu", ["bir-string", 42, None, ["a"]])
    def test_charge_record_value_dict_degil(self, tmp_path, nacl_yok, kotu):
        fx = {"tamga_observed": {"charge_record": {"value": kotu},
                                 "receiptHash": {"value": "0" * 64}}}
        with pytest.raises((AttributeError, TypeError)):
            verify_lite.main(["--fixture", str(_fxdir(tmp_path, fx))])

    def test_charge_record_value_eksik_alan_prev(self, tmp_path, nacl_yok):
        """rec['prev'] yok → KeyError (rec.get değil, doğrudan-indexleme)."""
        rec = _rec()
        del rec["prev"]
        fx = _fx(**{"tamga_observed.charge_record.value": rec})
        with pytest.raises(KeyError):
            verify_lite.main(["--fixture", str(_fxdir(tmp_path, fx))])

    def test_bos_charge_record_dict(self, tmp_path, nacl_yok):
        """{} kayıt → rec['prev'] KeyError."""
        fx = _fx(**{"tamga_observed.charge_record.value": {}})
        with pytest.raises(KeyError):
            verify_lite.main(["--fixture", str(_fxdir(tmp_path, fx))])


# == sentetik-zincir matematigi ===============================================================

class TestSentetikZincir:
    """main'in ürettiği 2-kayıtlı zincirin hash-formülü fixture-ile-aynı."""

    def test_h_formulu_jcs_ile_uyumlu(self):
        body = {"seq": 1, "op": "note", "prev": GENESIS, "n": 1}
        h = hashlib.sha256(body["prev"].encode() + jcs(body)).hexdigest()
        assert h == _rec()["h"]

    def test_h_node_sig_haric_hesaplanir(self):
        rec = {**_rec(), "node_sig": "imza-burada"}
        body = {k: v for k, v in rec.items() if k not in ("h", "node_sig")}
        h = hashlib.sha256(body["prev"].encode() + jcs(body)).hexdigest()
        assert h == rec["h"]

    def test_h_iceerige_duyarli_avalanche(self):
        a = _rec()
        b = _rec(n=2)
        assert a["h"] != b["h"]

    def test_prev_zincir_bagi(self):
        """2-kayıtlı zincirde ikinci-prev birincinin-h'si."""
        r1 = _rec()
        body2 = {"seq": 2, "op": "note", "prev": r1["h"], "n": 2}
        h2 = hashlib.sha256(body2["prev"].encode() + jcs(body2)).hexdigest()
        assert h2 != r1["h"]

    def test_jcs_canonical_siralamadan_bagimsiz(self):
        body = {"seq": 1, "op": "note", "prev": GENESIS, "n": 1}
        ters = {k: body[k] for k in reversed(list(body))}
        assert jcs(body) == jcs(ters)

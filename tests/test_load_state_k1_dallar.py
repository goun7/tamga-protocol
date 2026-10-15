"""K1 (P0-2) fail-closed pin'leri — `tamga_runner._load_state` graph_merkle
kapısı + import-gate simetrisi.

Dalga-3 bulgusu K1: `state.json`'da `memory` bir dict DEĞİLSE (None/list/str)
eski run-gate `st.get("memory")`-truthiness'ine düştüğü için doğrulamayı
sessizce ATLARDI (memory None/falsey → `if st.get(...) and ...` kısa-devre →
yeşil); truthy non-dict ise `_graph_merkle` AttributeError fırlatırdı.
Düzeltme: `"graph_merkle" in st` anahtar-varlığı (import-gate L1277 ile aynı
desen) + `memory` isinstance(dict) zorunluğu → her iki durumda RED rc5.

Ağaç:
  A1 graph_merkle-YOK → atla (geri-uyumlu, SystemExit YOK)
  A2 graph_merkle-VAR + memory-YOK → RED rc5
  A3 graph_merkle-VAR + memory=None → RED rc5 (eski sessiz-yeşil-deliğin-kapanışı)
  A4 graph_merkle-VAR + memory-str/list → RED rc5 (eski AttributeError-fırlatan-dal)
  A5 graph_merkle-VAR + memory-dict-TUTARLI → temiz-dönüş (SystemExit YOK)
  A6 graph_merkle-VAR + memory-dict-TUTARSIZ → RED rc5 "graph_merkle mismatch"
  A7 graph_merkle=null + memory-dict → RED rc5 (anahtar-var → doğrulanmak-zorunda)
  A8 biçim-dönüşümü (tamga-state/0) sonrası graph_merkle-KAPISI-devre-dışı (eski
      biçimde merkle yok → atla, yeni dict-politika-yok)

D1..D8 yukarıdaki dallar; saf-bellek (tmp_path + SystemExit-yakalama).
"""
from __future__ import annotations

import json

import pytest

import tamga_runner as runner


def _sp_yaz(tmp_path, st):
    """Saf state.json yazıcı — dosya-tabanlı-load için."""
    sp = tmp_path / "state.json"
    sp.write_text(json.dumps(st, ensure_ascii=False), encoding="utf-8")
    return sp


def _tutarli_state():
    """graph_merkle ile TUTARLI bir state üret (gerçek-_graph_merkle ile)."""
    mem = {"next_id": 1, "nodes": [{"id": "m1", "kind": "note", "text": "x"}],
           "edges": []}
    st = {"format": "tamga-state/1", "sessions": 3, "memory": mem}
    st["graph_merkle"] = runner._graph_merkle(mem)
    return st


class TestK1FailClosed:
    """A1-A7: graph_merkle-anahtarı varsa memory bir object olmak zorundadır."""

    def test_a1_anhtar_yok_atla(self, tmp_path):
        sp = _sp_yaz(tmp_path, {"format": "tamga-state/1", "sessions": 3})
        st = runner._load_state(sp)
        assert st["sessions"] == 3
        assert "graph_merkle" not in st

    def test_a2_memory_yok_red(self, tmp_path):
        st = _tutarli_state()
        del st["memory"]
        sp = _sp_yaz(tmp_path, st)
        with pytest.raises(SystemExit) as b:
            runner._load_state(sp)
        assert b.value.code == 1

    def test_a3_memory_none_red_sessiz_yesil_kapandi(self, tmp_path):
        st = _tutarli_state()
        st["memory"] = None
        sp = _sp_yaz(tmp_path, st)
        with pytest.raises(SystemExit):
            runner._load_state(sp)

    @pytest.mark.parametrize("kotu", ["degen-metin", [1, 2], 5, True])
    def test_a4_memory_non_dict_red(self, tmp_path, kotu):
        st = _tutarli_state()
        st["memory"] = kotu
        sp = _sp_yaz(tmp_path, st)
        with pytest.raises(SystemExit):
            runner._load_state(sp)

    def test_a5_tutarli_state_temiz_donuyor(self, tmp_path):
        sp = _sp_yaz(tmp_path, _tutarli_state())
        st = runner._load_state(sp)
        assert st["graph_merkle"] == runner._graph_merkle(st["memory"])

    def test_a6_memory_tahriz_red_mismatch(self, tmp_path):
        st = _tutarli_state()
        st["memory"]["nodes"][0]["text"] = "TAHRIF"
        sp = _sp_yaz(tmp_path, st)
        with pytest.raises(SystemExit) as b:
            runner._load_state(sp)
        assert b.value.code == 1

    def test_a7_merkle_null_red(self, tmp_path):
        st = _tutarli_state()
        st["graph_merkle"] = None
        sp = _sp_yaz(tmp_path, st)
        with pytest.raises(SystemExit):
            runner._load_state(sp)

    def test_a8_eski_bicim_donusum_atliyor(self, tmp_path):
        """tamga-state/0 → 1 dönüşümü: graph_merkle YOK → kapı devre-dışı."""
        sp = _sp_yaz(tmp_path, {"format": "tamga-state/0", "sessions": 1,
                                "memory_probe": ["a"]})
        st = runner._load_state(sp)
        assert st["format"] == "tamga-state/1"
        assert st["memory"]["next_id"] == 2
        assert "graph_merkle" not in st


class TestRedMesaji:
    """Kural-doğrulama: red mesajları 'memory bir object değil' / rc5 taşır."""

    def test_a3_mesaji_memory_object_degildir(self, tmp_path, capsys):
        st = _tutarli_state()
        st["memory"] = None
        sp = _sp_yaz(tmp_path, st)
        with pytest.raises(SystemExit):
            runner._load_state(sp)
        cik = capsys.readouterr().out
        yuk = json.loads(cik.strip().splitlines()[-1])
        assert yuk["ok"] is False
        assert yuk["reason_code"] == 5
        assert "memory bir object" in yuk["reason"]
        assert "fail-closed" in yuk["reason"]

    def test_a6_mesaji_graph_merkle_mismatch(self, tmp_path, capsys):
        st = _tutarli_state()
        st["memory"]["nodes"][0]["text"] = "TAHRIF"
        sp = _sp_yaz(tmp_path, st)
        with pytest.raises(SystemExit):
            runner._load_state(sp)
        yuk = json.loads(capsys.readouterr().out.strip().splitlines()[-1])
        assert yuk["ok"] is False
        assert yuk["reason_code"] == 5
        assert "graph_merkle mismatch" in yuk["reason"]

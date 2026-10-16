"""tools/sovereign_anchor.py dal-kesen testleri (LEED) — zincir-çapa kanıtı.

Kural-1: MEVCUT DOSYALARA DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory. sovereign_verify'nin-üç-üretim-doğrulayıcısı
(subprocess/SQLite/CLI-çağrısı-yapan) monkeypatch-ile-stub'lanır; gerçek
WASM/RPC/subprocess/dosya-yazımı YOK. Anchor'lar tmp_path-üzerinde-yönlendirilir.

Kapsanan fonksiyonlar (4):
  _canon   sıralı-JSON-kanonik-form (utf-8-bytes, sort_keys, sıkı-separatörler)
  build    üç-ürün-kanıtlarını-tek-ankora-bağlar (eksik-ürün RED, ERRATUM-A1)
  verify   iki-katmanlı-denetim: katman-1 presented-tutarlılık (kök-yeniden-hesap),
           katman-2 bağımsız-yeniden-hesap (sahte-yeşile-boyama-koruması, ERRATUM-A2)
  main     CLI-yüzeyi: build (rc 0/1), verify (rc 0/1), kullanım-hataları rc 2

Dal listesi (her-fonksiyon için başarı + başarısızlık + sınır):
  build : tamga-yeşil / tamga-kırmızı / verdict-eksik / sester-yeşil /
          sester-kırmızı / veridict-ikili-geçilmez / kaynaklar-köke-girer (A1) /
          belirleyici-kök
  verify: dosya-yok / bozuk-JSON / type-değil / version-değil / results-değil /
          root-uyuşmaz / products_proved-çelişki / all_proved-çelişki /
          sahte-yeşile-boyama-katman1 (A2) / kaynaklar-yok → UNVERIFIED /
          kaynaklar-var-ama-gerçekleme-boş → STRUCTURAL-GREEN /
          bağımsız-yeşil → GREEN / bağımsız-kırmızı → sahte-yeşil-yakalandı
"""
from __future__ import annotations

import hashlib
import json
import sys

import pytest

sys.path.insert(0, ".")
sys.path.insert(0, "tools")
import sovereign_anchor  # noqa: E402


# == stub altyapısı (Kural-4: subprocess/SQLite/CLI YOK) =======================================

@pytest.fixture
def sv(monkeypatch):
    """sovere_anchor'ın-çağırdığı-üç-doğrulayıcıyı-stub'la.

    sovereign_verify.verify_*-üçlüsü-üretimde-subprocess/SQLite çalıştırır;
    burada saf-dict-döner. Dönüş-değerleri test-başına-değiştirilebilir
    (sahte-yeşile-boyama-saldırı-senaryoları-için).
    """
    state = {
        "tamga": {"ok": True, "verdict": "GREEN"},
        "sester": {"ok": True, "verdict": "GREEN"},
        "veridict": {"ok": True, "verdict": "GREEN"},
        "calls": {"tamga": [], "sester": [], "veridict": []},
    }

    def cap(path):
        state["calls"]["tamga"].append(path)
        return dict(state["tamga"], product="tamga")

    def ses(path, secret=None):
        state["calls"]["sester"].append((path, secret))
        return dict(state["sester"], product="sester")

    def ver(ledger, cert):
        state["calls"]["veridict"].append((ledger, cert))
        return dict(state["veridict"], product="veridict")

    monkeypatch.setattr(sovereign_anchor, "verify_capacity_attest", cap)
    monkeypatch.setattr(sovereign_anchor, "verify_sester_ledger", ses)
    monkeypatch.setattr(sovereign_anchor, "verify_veridict_cert", ver)
    return state


def _recompute(a: dict) -> str:
    """verify'nin-katman-1'iyle-BİREBİR-aynı-kök-hesabı (aynı-kaynak-koruma)."""
    src = a.get("sources")
    return hashlib.sha256(sovereign_anchor._canon(
        {"results": a["results"],
         "sources": src if isinstance(src, dict) else {}})).hexdigest()


def _write(a: dict, tmp_path) -> str:
    p = tmp_path / "anchor.json"
    p.write_text(json.dumps(a, ensure_ascii=False), encoding="utf-8")
    return str(p)


# == _canon =====================================================================================

class TestCanan:
    @pytest.mark.parametrize("inp,expect", [
        ({"b": 2, "a": 1}, '{"a":1,"b":2}'),
        ({"a": 1}, '{"a":1}'),
        ({}, '{}'),
        ({"z": 1, "y": 2, "a": 3}, '{"a":3,"y":2,"z":1}'),
    ])
    def test_sorted_keys(self, inp, expect):
        """Anahtarlar-sıralı (sort_keys) — aynı-girdi → aynı-bytes."""
        assert sovereign_anchor._canon(inp) == expect.encode("utf-8")

    def test_returns_bytes(self):
        assert isinstance(sovereign_anchor._canon({"a": 1}), bytes)

    def test_separators_are_tight(self):
        """Ayraçlar ','-ve-':' — boşluk-yok (belirleyici-özet-için-şart)."""
        c = sovereign_anchor._canon({"a": 1, "b": 2})
        assert b" " not in c

    def test_ensure_ascii_false(self):
        """Türkçe-karakterler-kaçışsız (ensure_ascii=False) — utf-8-korunur."""
        c = sovereign_anchor._canon({"ad": "çğıöşü"})
        assert "çğıöşü".encode("utf-8") in c

    def test_nested_dicts_sorted(self):
        """İç-içe-nesneler-de-sıralanır (sort_keys-yinelemeli)."""
        c = sovereign_anchor._canon({"d": {"z": 1, "a": 2}})
        assert c == b'{"d":{"a":2,"z":1}}'

    def test_deterministic_same_input_same_output(self):
        assert sovereign_anchor._canon({"b": 1, "a": 2}) == \
            sovereign_anchor._canon({"a": 2, "b": 1})

    def test_different_input_different_output(self):
        assert sovereign_anchor._canon({"a": 1}) != sovereign_anchor._canon({"a": 2})


# == build: başarı ==============================================================================

class TestBuildYesil:
    def test_tamga_only_anchor_sekli(self, sv):
        a = sovereign_anchor.build("claim.json")
        assert a["type"] == "sovereign-anchor"
        assert a["version"] == "0.1"
        assert a["products_present"] == ["tamga"]
        assert a["products_proved"] == ["tamga"]
        assert a["all_proved"] is True

    def test_tamga_only_results(self, sv):
        a = sovereign_anchor.build("claim.json")
        assert a["results"]["tamga"] == {"ok": True, "verdict": "GREEN"}

    def test_anchor_root_is_sha256_hex(self, sv):
        a = sovereign_anchor.build("claim.json")
        assert len(a["anchor_root"]) == 64
        assert all(ch in "0123456789abcdef" for ch in a["anchor_root"])

    def test_anchor_root_matches_recompute(self, sv):
        """Kök, _canon-formülüyle-yeniden-hesaplanabilir (katman-1-parite)."""
        a = sovereign_anchor.build("claim.json")
        assert a["anchor_root"] == _recompute(a)

    def test_deterministic_same_args_same_root(self, sv):
        a1 = sovereign_anchor.build("claim.json")
        a2 = sovereign_anchor.build("claim.json")
        assert a1["anchor_root"] == a2["anchor_root"]

    def test_capacity_attest_called_with_claim_path(self, sv):
        sovereign_anchor.build("/yol/claim.json")
        assert sv["calls"]["tamga"] == ["/yol/claim.json"]

    def test_sources_carries_only_given_paths(self, sv):
        a = sovereign_anchor.build("c.json")
        assert a["sources"] == {"tamga_claim": "c.json"}

    def test_products_constant_order(self, sv):
        """products_present PRODUCTS-sırasına-uymalı (tamga, sester, veridict)."""
        a = sovereign_anchor.build("c.json", sester_db="s.db",
                                   veridict_ledger="l.jsonl", veridict_cert="c.cert")
        assert a["products_present"] == ["tamga", "sester", "veridict"]
        assert a["products_proved"] == ["tamga", "sester", "veridict"]
        assert a["all_proved"] is True

    def test_all_three_sources_present(self, sv):
        a = sovereign_anchor.build("c.json", sester_db="s.db", sester_secret="x",
                                   veridict_ledger="l.jsonl", veridict_cert="c.cert")
        assert a["sources"] == {"tamga_claim": "c.json", "sester_db": "s.db",
                                "sester_secret": "x",
                                "veridict_ledger": "l.jsonl", "veridict_cert": "c.cert"}


# == build: ürün-eksikliği / RED =================================================================

class TestBuildKirmizi:
    def test_tamga_red_all_proved_false(self, sv):
        sv["tamga"] = {"ok": False, "verdict": "RED"}
        a = sovereign_anchor.build("c.json")
        assert a["all_proved"] is False
        assert a["products_proved"] == []
        assert a["products_present"] == ["tamga"]

    def test_tamga_verdict_missing_defaults_red(self, sv):
        """Doğrulayıcı-verdict-döndürmezse varsayılan-RED (dürüst-eksiklik)."""
        sv["tamga"] = {"ok": False}
        a = sovereign_anchor.build("c.json")
        assert a["results"]["tamga"]["verdict"] == "RED"
        assert a["all_proved"] is False

    def test_tamga_ok_true_but_verdict_red_still_proved_in_build(self, sv):
        """ORTAM-KARAKTERİZASYON: build'in-proved-listesi-YALNIZCA-ok'a-bakar
        (verdict'e-değil). ok:True-ama-verdict:RED → build-bunu-yeşil-sayar;
        ok/verdict-çelişkisini-yakalayan-görev-verify'nin-A2-katmanındadır
        (bkz. TestVerifyKatman1.test_fake_green_layer1_a2)."""
        sv["tamga"] = {"ok": True, "verdict": "RED"}
        a = sovereign_anchor.build("c.json")
        assert a["products_proved"] == ["tamga"]
        assert a["all_proved"] is True

    def test_sester_green_proved(self, sv):
        a = sovereign_anchor.build("c.json", sester_db="s.db")
        assert a["products_proved"] == ["tamga", "sester"]
        assert a["all_proved"] is True

    def test_sester_red_blocks_all_proved(self, sv):
        sv["sester"] = {"ok": False, "verdict": "RED"}
        a = sovereign_anchor.build("c.json", sester_db="s.db")
        assert a["products_present"] == ["tamga", "sester"]
        assert a["products_proved"] == ["tamga"]
        assert a["all_proved"] is False

    def test_sester_db_only_no_secret_is_called(self, sv):
        """sester_secret-None → verify_sester_ledger(path, None) çağrılır."""
        sovereign_anchor.build("c.json", sester_db="s.db")
        assert sv["calls"]["sester"] == [("s.db", None)]

    def test_sester_secret_forwarded(self, sv):
        sovereign_anchor.build("c.json", sester_db="s.db", sester_secret="s3cr3t")
        assert sv["calls"]["sester"] == [("s.db", "s3cr3t")]

    def test_veridict_needs_both_ledger_and_cert(self, sv):
        """Sadece-ledger-geçilirse-veridict-çağrılmaz (eksik-ürün-sessiz-geçilmez)."""
        a = sovereign_anchor.build("c.json", veridict_ledger="l.jsonl")
        assert "veridict" not in a["results"]
        assert "veridict" not in a["products_present"]
        assert sv["calls"]["veridict"] == []

    def test_veridict_green_proved(self, sv):
        a = sovereign_anchor.build("c.json", veridict_ledger="l.jsonl",
                                   veridict_cert="c.cert")
        assert a["products_proved"] == ["tamga", "veridict"]
        assert a["all_proved"] is True

    def test_veridict_args_forwarded(self, sv):
        sovereign_anchor.build("c.json", veridict_ledger="l.jsonl",
                               veridict_cert="c.cert")
        assert sv["calls"]["veridict"] == [("l.jsonl", "c.cert")]

    def test_veridict_red_blocks_all_proved(self, sv):
        sv["veridict"] = {"ok": False, "verdict": "RED"}
        a = sovereign_anchor.build("c.json", veridict_ledger="l.jsonl",
                                   veridict_cert="c.cert")
        assert a["products_proved"] == ["tamga"]
        assert a["all_proved"] is False

    def test_sester_and_veridict_absent_when_not_given(self, sv):
        a = sovereign_anchor.build("c.json")
        assert "sester" not in a["results"]
        assert "veridict" not in a["results"]


# == build: ERRATUM-A1 (sources köke-girer) ======================================================

class TestBuildErratumA1:
    def test_sester_db_path_changes_root(self, sv):
        """A1: kaynak-yolu-köke-girer — saldırgan-yol-değiştirip-kökü-koruyamaz."""
        r1 = sovereign_anchor.build("c.json", sester_db="gercek.db")["anchor_root"]
        r2 = sovereign_anchor.build("c.json", sester_db="sahte.db")["anchor_root"]
        assert r1 != r2

    def test_sester_secret_changes_root(self, sv):
        r1 = sovereign_anchor.build("c.json", sester_db="s.db",
                                    sester_secret="a")["anchor_root"]
        r2 = sovereign_anchor.build("c.json", sester_db="s.db",
                                    sester_secret="b")["anchor_root"]
        assert r1 != r2

    def test_veridict_ledger_path_changes_root(self, sv):
        r1 = sovereign_anchor.build("c.json", veridict_ledger="l1.jsonl",
                                    veridict_cert="c.cert")["anchor_root"]
        r2 = sovereign_anchor.build("c.json", veridict_ledger="l2.jsonl",
                                    veridict_cert="c.cert")["anchor_root"]
        assert r1 != r2

    def test_tamga_claim_path_changes_root(self, sv):
        r1 = sovereign_anchor.build("c1.json")["anchor_root"]
        r2 = sovereign_anchor.build("c2.json")["anchor_root"]
        assert r1 != r2

    def test_results_change_root(self, sv):
        r1 = sovereign_anchor.build("c.json")["anchor_root"]
        sv["tamga"] = {"ok": False, "verdict": "RED"}
        r2 = sovereign_anchor.build("c.json")["anchor_root"]
        assert r1 != r2


# == verify: yükleme/format dalları =============================================================

class TestVerifyYukleme:
    def test_missing_file_red(self, tmp_path, sv):
        r = sovereign_anchor.verify(str(tmp_path / "yok.json"))
        assert r["ok"] is False
        assert "anchor-yüklenemedi" in r["reason"]

    def test_missing_file_reports_oserror(self, tmp_path, sv):
        r = sovereign_anchor.verify(str(tmp_path / "yok.json"))
        assert "FileNotFoundError" in r["reason"] or "OSError" in r["reason"]

    def test_corrupt_json_red(self, tmp_path, sv):
        p = tmp_path / "bozuk.json"
        p.write_text("{ geçerli-json-değil ", encoding="utf-8")
        r = sovereign_anchor.verify(str(p))
        assert r["ok"] is False
        assert "anchor-yüklenemedi" in r["reason"]

    def test_corrupt_json_reports_decode_error(self, tmp_path, sv):
        p = tmp_path / "bozuk.json"
        p.write_text("{{", encoding="utf-8")
        r = sovereign_anchor.verify(str(p))
        assert "JSONDecodeError" in r["reason"]

    def test_json_array_not_dict(self, tmp_path, sv):
        p = tmp_path / "liste.json"
        p.write_text("[1,2,3]", encoding="utf-8")
        r = sovereign_anchor.verify(str(p))
        assert r["ok"] is False
        assert r["reason"] == "type sovereign-anchor değil"

    def test_wrong_type_field(self, tmp_path, sv):
        p = tmp_path / "a.json"
        p.write_text(json.dumps({"type": "baska-sey", "version": "0.1",
                                 "results": {}, "sources": {}}), encoding="utf-8")
        r = sovereign_anchor.verify(str(p))
        assert r["ok"] is False
        assert "type sovereign-anchor değil" in r["reason"]

    @pytest.mark.parametrize("version", ["0.2", "1.0", "", None, "v0.1", 0.1])
    def test_wrong_version_rejected(self, tmp_path, sv, version):
        a = {"type": "sovereign-anchor", "version": version, "results": {},
             "sources": {}}
        p = tmp_path / "a.json"
        p.write_text(json.dumps(a), encoding="utf-8")
        r = sovereign_anchor.verify(str(p))
        assert r["ok"] is False
        assert "version 0.1 değil" in r["reason"]

    def test_results_not_dict_rejected(self, tmp_path, sv):
        a = {"type": "sovereign-anchor", "version": "0.1", "results": ["x"],
             "sources": {}}
        p = tmp_path / "a.json"
        p.write_text(json.dumps(a), encoding="utf-8")
        r = sovereign_anchor.verify(str(p))
        assert r["ok"] is False
        assert r["reason"] == "results bir nesne değil"

    def test_results_not_dict_string_rejected(self, tmp_path, sv):
        a = {"type": "sovereign-anchor", "version": "0.1", "results": "x",
             "sources": {}}
        p = tmp_path / "a.json"
        p.write_text(json.dumps(a), encoding="utf-8")
        r = sovereign_anchor.verify(str(p))
        assert r["ok"] is False
        assert r["reason"] == "results bir nesne değil"


# == verify: katman-1 presented-tutarlılık =======================================================

class TestVerifyKatman1:
    def _valid(self, sv, tmp_path, **kw):
        a = sovereign_anchor.build("c.json", **kw)
        return _write(a, tmp_path)

    def test_valid_anchor_passes_layer1(self, sv, tmp_path):
        r = sovereign_anchor.verify(self._valid(sv, tmp_path))
        assert r["ok"] is True

    def test_tampered_root_detected(self, sv, tmp_path):
        """anchor_root-değiştirilirse-katman-1-reddeder."""
        a = sovereign_anchor.build("c.json")
        a["anchor_root"] = "0" * 64
        r = sovereign_anchor.verify(_write(a, tmp_path))
        assert r["ok"] is False
        assert "anchor_root uyuşmaz" in r["reason"]

    def test_tampered_root_reports_expected_actual(self, sv, tmp_path):
        a = sovereign_anchor.build("c.json")
        a["anchor_root"] = "0" * 64
        r = sovereign_anchor.verify(_write(a, tmp_path))
        assert "expected" in r and "actual" in r

    def test_tampered_results_detected(self, sv, tmp_path):
        """results-kurcalanıp-kök-yeniden-hesaplanmamışsa-yakalanır."""
        a = sovereign_anchor.build("c.json")
        a["results"]["tamga"]["ok"] = False
        r = sovereign_anchor.verify(_write(a, tmp_path))
        assert r["ok"] is False
        assert "anchor_root uyuşmaz" in r["reason"]

    def test_tampered_source_path_detected(self, sv, tmp_path):
        """A1: sources-değişince-eski-kök-artık-eşleşmez."""
        a = sovereign_anchor.build("c.json")
        a["sources"]["tamga_claim"] = "baska.json"
        r = sovereign_anchor.verify(_write(a, tmp_path))
        assert r["ok"] is False
        assert "anchor_root uyuşmaz" in r["reason"]

    def test_removed_sources_breaks_root(self, sv, tmp_path):
        """sources-silinirse-kök-büsbütün-eşleşmez (silme-de-tutarsızlık)."""
        a = sovereign_anchor.build("c.json")
        del a["sources"]
        r = sovereign_anchor.verify(_write(a, tmp_path))
        assert r["ok"] is False
        assert "anchor_root uyuşmaz" in r["reason"]

    def test_products_proved_mismatch_detected(self, sv, tmp_path):
        a = sovereign_anchor.build("c.json")
        a["products_proved"] = []
        a["anchor_root"] = _recompute(a)  # kök-hala-tutarlı-olsun
        r = sovereign_anchor.verify(_write(a, tmp_path))
        assert r["ok"] is False
        assert "products_proved ile results çelişiyor" in r["reason"]

    def test_all_proved_mismatch_detected(self, sv, tmp_path):
        a = sovereign_anchor.build("c.json")
        a["all_proved"] = False
        a["anchor_root"] = _recompute(a)
        r = sovereign_anchor.verify(_write(a, tmp_path))
        assert r["ok"] is False
        assert "all_proved ile results çelişiyor" in r["reason"]

    def test_result_not_object_raises_before_a2_guard(self, sv, tmp_path):
        """ORTAM-KARAKTERİZASYON: results-değeri-dict-değilse-AttributeError.

        A2-döngüsündeki `isinstance(r, dict)`-savunma-koruması (satır-141)
        ERİŞİLEMEZ: ondan-önceki `proved`-hesabı `results.get(p, {}).get("ok")`
        yapar ve dict-olmayan-değerde-çöker. Test-bunu-belgeler, düzeltmez
        (build-her-zaman-dict-üretir; bu-yalnızca-kurcalanmış-girdide-olur)."""
        a = sovereign_anchor.build("c.json")
        a["results"]["tamga"] = "yazi"
        a["anchor_root"] = _recompute(a)
        with pytest.raises(AttributeError):
            sovereign_anchor.verify(_write(a, tmp_path))

    def test_fake_green_layer1_a2(self, sv, tmp_path):
        """ERRATUM-A2: ok:True-ama-verdict:RED — kök-yeniden-hesaplansa-bile-yakalanır.

        Saldırgan-ok'u-yeşile-boyayıp-kökü-de-yeniden-hesaplasa-bile-A2-katmanı
        'ok:True-VE-verdict:GREEN'-ikilisini-denetlediği-için-reddeder.
        """
        a = sovereign_anchor.build("c.json")
        a["results"]["tamga"] = {"ok": True, "verdict": "RED"}
        a["products_proved"] = ["tamga"]  # proved-yine-ok'a-bakar
        a["all_proved"] = True
        a["anchor_root"] = _recompute(a)
        r = sovereign_anchor.verify(_write(a, tmp_path))
        assert r["ok"] is False
        assert "sahte-yeşile-boyama" in r["reason"]
        assert "tamga" in r["reason"]

    def test_verdict_green_but_ok_false_not_flagged(self, sv, tmp_path):
        """Ters-yön (verdict:GREEN-ama-ok:False) A2'ye-takılmaz — proved-ok'a-bakar."""
        a = sovereign_anchor.build("c.json")
        a["results"]["tamga"] = {"ok": False, "verdict": "GREEN"}
        a["products_proved"] = []
        a["all_proved"] = True  # len(proved)==len(results) → 0==1 False aslında
        a["all_proved"] = (len(a["products_proved"]) == len(a["results"]))
        a["anchor_root"] = _recompute(a)
        r = sovereign_anchor.verify(_write(a, tmp_path))
        assert "sahte-yeşile-boyama" not in r.get("reason", "")


# == verify: SOV-1 boş-kanıt reddi (fail-closed) ==================================================

class TestVerifyKanitsizRedFailClosed:
    """DUZELTILDI (SOV-1): eskiden hiçbir-ürün-kanıtlamayan-anchor (proved-boş)
    katman-2-atlandığında ok:True (UNVERIFIED-INDEPENDENTLY / STRUCTURAL-GREEN)
    dönüyordu — boş-kanıt geçersiz-yeşil-alıyordu (ok-only false-proof). Artık
    verify proved-boş ise daima RED. Kapsam-azaltılmadı; yeni-pins-eklendi."""

    def test_empty_results_anchor_rejected(self, sv, tmp_path):
        """results={} (sıfır-ürün) → RED — taklit-boş-kanit artik gecmez."""
        a = {"type": "sovereign-anchor", "version": "0.1", "results": {},
             "products_present": [], "products_proved": [], "all_proved": True,
             "sources": {}}
        a["anchor_root"] = _recompute(a)
        r = sovereign_anchor.verify(_write(a, tmp_path))
        assert r["ok"] is False
        assert r["verdict"] == "RED"
        assert "kanıt-yok" in r["reason"]

    def test_all_products_red_rejected(self, sv, tmp_path):
        """Tüm-ürünler ok:False (proved-boş) → RED — hiçbir-şey-kanıtlanmadı."""
        a = {"type": "sovereign-anchor", "version": "0.1",
             "results": {"tamga": {"ok": False, "verdict": "RED"},
                         "sester": {"ok": False, "verdict": "RED"}},
             "products_present": ["tamga", "sester"], "products_proved": [],
             "all_proved": False, "sources": {}}
        a["anchor_root"] = _recompute(a)
        r = sovereign_anchor.verify(_write(a, tmp_path))
        assert r["ok"] is False
        assert r["verdict"] == "RED"
        assert "kanıt-yok" in r["reason"]

    def test_empty_proof_with_sources_still_rejected(self, sv, tmp_path):
        """proved-boş + kaynak-var: katman-2'ye-hiç-girmeden RED (fail-closed-önce)."""
        a = {"type": "sovereign-anchor", "version": "0.1",
             "results": {"tamga": {"ok": False, "verdict": "RED"}},
             "products_present": ["tamga"], "products_proved": [],
             "all_proved": False, "sources": {"tamga_claim": "c.json"}}
        a["anchor_root"] = _recompute(a)
        r = sovereign_anchor.verify(_write(a, tmp_path))
        assert r["ok"] is False
        assert "kanıt-yok" in r["reason"]

    def test_valid_proved_anchor_still_green(self, sv, tmp_path):
        """SOV-1 regresyon-koruma: en-az-bir-proved-ürün → yeşil-yolu-bozulmadı."""
        p = _write(sovereign_anchor.build("c.json"), tmp_path)
        r = sovereign_anchor.verify(p)
        assert r["ok"] is True
        assert r["verdict"] == "GREEN"


# == verify: katman-2 bağımsız-yeniden-hesap =====================================================

class TestVerifyKatman2:
    def test_green_independent_recheck(self, sv, tmp_path):
        """Kaynaklar-verildi-ve-bağımsız-doğrulama-yeşil → GREEN + independent."""
        p = _write(sovereign_anchor.build("c.json"), tmp_path)
        r = sovereign_anchor.verify(p)
        assert r["ok"] is True
        assert r["verdict"] == "GREEN"
        assert r["independent"] == {"tamga": True}

    def test_green_returns_tip_and_proved(self, sv, tmp_path):
        p = _write(sovereign_anchor.build("c.json"), tmp_path)
        r = sovereign_anchor.verify(p)
        assert r["products_proved"] == ["tamga"]
        assert r["anchor_root"] == _recompute(
            json.loads(open(p, encoding="utf-8").read()))

    def test_fake_green_layer2_caught(self, sv, monkeypatch, tmp_path):
        """Katman-2: anchor-GREEN-iddia-ediyor-ama-bağımsız-doğrulama-RED."""
        p = _write(sovereign_anchor.build("c.json"), tmp_path)
        # anchor'ı-yapan-doğrulayıcı-yeşildi; bağımsız-yeniden-doğrulama-kırmızı
        monkeypatch.setattr(sovereign_anchor, "verify_capacity_attest",
                            lambda path: {"ok": False, "verdict": "RED"})
        r = sovereign_anchor.verify(p)
        assert r["ok"] is False
        assert "sahte-yeşile-boyama-tamga" in r["reason"]
        assert r["independent"] == {"tamga": False}

    def test_sources_missing_unverified(self, sv, tmp_path):
        """Kaynaklar-taşınmıyor → UNVERIFIED-INDEPENDENTLY (sessiz-GREEN-yasak)."""
        a = sovereign_anchor.build("c.json")
        a["sources"] = {}
        a["anchor_root"] = _recompute(a)
        r = sovereign_anchor.verify(_write(a, tmp_path))
        assert r["ok"] is True
        assert r["verdict"] == "UNVERIFIED-INDEPENDENTLY"
        assert "bağımsız-yeniden-hesap-yapılamadı" in r["reason"]

    def test_unverified_returns_expected_root(self, sv, tmp_path):
        a = sovereign_anchor.build("c.json")
        a["sources"] = {}
        a["anchor_root"] = _recompute(a)
        r = sovereign_anchor.verify(_write(a, tmp_path))
        assert r["anchor_root"] == a["anchor_root"]

    def test_sources_not_dict_unverified(self, sv, tmp_path):
        a = sovereign_anchor.build("c.json")
        a["sources"] = "bozuk"
        a["anchor_root"] = _recompute(a)  # verify-de-{}-kullanır → tutarlı
        r = sovereign_anchor.verify(_write(a, tmp_path))
        assert r["verdict"] == "UNVERIFIED-INDEPENDENTLY"

    def test_structural_green_when_no_product_recheckable(self, sv, tmp_path):
        """Kaynaklar-var-ama-hiç-ürün-gerçeklenemiyor → STRUCTURAL-GREEN (AT-054b)."""
        a = sovereign_anchor.build("c.json")
        a["sources"] = {"sester_db": "s.db"}  # tamga-kaynağı-yok → rechecked-boş
        a["anchor_root"] = _recompute(a)
        r = sovereign_anchor.verify(_write(a, tmp_path))
        assert r["ok"] is True
        assert r["verdict"] == "STRUCTURAL-GREEN"
        assert r.get("structural") is True

    def test_structural_green_reports_tip(self, sv, tmp_path):
        a = sovereign_anchor.build("c.json")
        a["sources"] = {"sester_db": "s.db"}
        a["anchor_root"] = _recompute(a)
        r = sovereign_anchor.verify(_write(a, tmp_path))
        assert r["anchor_root"] == a["anchor_root"]

    def test_sester_independent_recheck_green(self, sv, tmp_path):
        p = _write(sovereign_anchor.build("c.json", sester_db="s.db"), tmp_path)
        r = sovereign_anchor.verify(p)
        assert r["verdict"] == "GREEN"
        assert r["independent"] == {"tamga": True, "sester": True}

    def test_sester_independent_recheck_red(self, sv, monkeypatch, tmp_path):
        p = _write(sovereign_anchor.build("c.json", sester_db="s.db"), tmp_path)
        monkeypatch.setattr(sovereign_anchor, "verify_sester_ledger",
                            lambda path, secret=None: {"ok": False, "verdict": "RED"})
        r = sovereign_anchor.verify(p)
        assert r["ok"] is False
        assert "sahte-yeşile-boyama-sester" in r["reason"]

    def test_veridict_independent_recheck_green(self, sv, tmp_path):
        p = _write(sovereign_anchor.build("c.json", veridict_ledger="l.jsonl",
                                          veridict_cert="c.cert"), tmp_path)
        r = sovereign_anchor.verify(p)
        assert r["verdict"] == "GREEN"
        assert r["independent"] == {"tamga": True, "veridict": True}

    def test_veridict_independent_recheck_red(self, sv, monkeypatch, tmp_path):
        p = _write(sovereign_anchor.build("c.json", veridict_ledger="l.jsonl",
                                          veridict_cert="c.cert"), tmp_path)
        monkeypatch.setattr(sovereign_anchor, "verify_veridict_cert",
                            lambda l, c: {"ok": False, "verdict": "RED"})
        r = sovereign_anchor.verify(p)
        assert r["ok"] is False
        assert "sahte-yeşile-boyama-veridict" in r["reason"]

    def test_red_product_not_rechecked_but_still_red(self, sv, monkeypatch, tmp_path):
        """products_proved'a-girmeyen-ürün-için-katman-2-koşulmaz-ama-zaten-RED."""
        sv["sester"] = {"ok": False, "verdict": "RED"}
        a = sovereign_anchor.build("c.json", sester_db="s.db")
        assert a["all_proved"] is False
        r = sovereign_anchor.verify(_write(a, tmp_path))
        assert r["verdict"] == "GREEN"  # anchor-un-tuttuğu-iddia-yeşil-diye-değil:
        # sester-ok:False-olduğu-için-rechecked-sester'e-girmez; tamga-yeşil → GREEN


# == main =======================================================================================

class TestMain:
    def test_no_args_prints_doc(self, capsys, sv):
        rc = sovereign_anchor.main([])
        assert rc == 2
        assert "AT-041" in capsys.readouterr().out

    def test_unknown_command(self, capsys, sv):
        rc = sovereign_anchor.main(["bogus", "fazla"])
        assert rc == 2
        assert "bilinmeyen komut" in capsys.readouterr().err

    def test_single_arg_prints_doc_regardless(self, capsys, sv):
        """ORTAM-KARAKTERİZASYON: tek-elemanlı-argv ('bogus'/'verify'/'build')
        en-tepedeki len(argv) < 2-kapısına-takılır → docstring-stdout'a, rc 2.
        Bu-yüzden-altkomutların-kendi-kullanım-hata-dalları-erişilemez-değildir-
        ama-tek-argümanla-asla-çoğalmaz (bkv. aşağıdaki-erişilemezlik-testi)."""
        for argv in (["bogus"], ["verify"], ["build"]):
            rc = sovereign_anchor.main(list(argv))
            assert rc == 2
            assert "AT-041" in capsys.readouterr().out

    def test_build_green_rc0(self, capsys, sv, tmp_path):
        c = tmp_path / "claim.json"
        c.write_text("{}", encoding="utf-8")
        rc = sovereign_anchor.main(["build", "--tamga", str(c)])
        assert rc == 0
        o = json.loads(capsys.readouterr().out)
        assert o["all_proved"] is True

    def test_build_red_rc1(self, capsys, sv, tmp_path):
        sv["tamga"] = {"ok": False, "verdict": "RED"}
        c = tmp_path / "claim.json"
        c.write_text("{}", encoding="utf-8")
        rc = sovereign_anchor.main(["build", "--tamga", str(c)])
        assert rc == 1
        o = json.loads(capsys.readouterr().out)
        assert o["all_proved"] is False

    def test_build_sester_and_veridict_flags(self, capsys, sv, tmp_path):
        c = tmp_path / "claim.json"
        c.write_text("{}", encoding="utf-8")
        rc = sovereign_anchor.main(["build", "--tamga", str(c), "--sester-db", "s.db",
                                    "--veridict-ledger", "l.jsonl",
                                    "--veridict-cert", "c.cert"])
        assert rc == 0
        o = json.loads(capsys.readouterr().out)
        assert o["products_proved"] == ["tamga", "sester", "veridict"]

    def test_build_missing_tamga_flag(self, sv, tmp_path):
        """--tamga zorunlu — argparse-hatası-yükselir (en-az-2-argüman-gerekli
        ki-tepe-kapısı-atlansın)."""
        with pytest.raises(SystemExit):
            sovereign_anchor.main(["build", "--sester-db", "s.db"])

    def test_verify_green_rc0(self, capsys, sv, tmp_path):
        p = _write(sovereign_anchor.build("c.json"), tmp_path)
        rc = sovereign_anchor.main(["verify", p])
        assert rc == 0
        o = json.loads(capsys.readouterr().out)
        assert o["verdict"] == "GREEN"

    def test_verify_red_rc1(self, capsys, sv, tmp_path):
        a = sovereign_anchor.build("c.json")
        a["anchor_root"] = "0" * 64  # kurcala
        bogus = tmp_path / "bad.json"
        bogus.write_text(json.dumps(a), encoding="utf-8")
        rc = sovereign_anchor.main(["verify", str(bogus)])
        assert rc == 1

    def test_verify_no_path_prints_doc(self, capsys, sv):
        """ORTAM-KARAKTERİZASYON: main(['verify']) → tepe-kapısı (len < 2)
        docstring-basıp rc 2-verir; stderr'deki 'kullanim'-dalı tek-argümanla
        erişilemez (çoğaltılamaz — argv-her-zaman-en-az-2-eleman-ister)."""
        rc = sovereign_anchor.main(["verify"])
        assert rc == 2
        assert "AT-041" in capsys.readouterr().out

    def test_verify_missing_file_rc1(self, sv, tmp_path):
        rc = sovereign_anchor.main(["verify", str(tmp_path / "yok.json")])
        assert rc == 1


# == uçtan-uca parite ============================================================================

class TestUctanUca:
    def test_build_then_verify_roundtrip_green(self, sv, tmp_path):
        """build-üretti-anchor'ı-verify-yeşil-doğrular ( aynı-stub-koşullarında)."""
        p = _write(sovereign_anchor.build("c.json", sester_db="s.db"), tmp_path)
        r = sovereign_anchor.verify(p)
        assert r["ok"] is True and r["verdict"] == "GREEN"

    def test_build_then_verify_roundtrip_red(self, sv, monkeypatch, tmp_path):
        """Bağımsız-doğrulama-arteryse-aynı-anchor-reddedilir."""
        p = _write(sovereign_anchor.build("c.json"), tmp_path)
        monkeypatch.setattr(sovereign_anchor, "verify_capacity_attest",
                            lambda path: {"ok": False, "verdict": "RED"})
        assert sovereign_anchor.verify(p)["ok"] is False

    def test_anchor_is_json_serializable(self, sv):
        """Üretilen-anchor-saf-JSON'da-yazılabilir-okunabilir (taşınabilirlik)."""
        a = sovereign_anchor.build("c.json")
        roundtrip = json.loads(json.dumps(a, ensure_ascii=False))
        assert roundtrip["anchor_root"] == a["anchor_root"]

"""tools/dispute_pointer_verify.py dal-kesen testleri (LEED) — anlaşmazlık-bacağı.

Kural-1: MEVCUT DOSYALARA DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory — girdiler saf-dict; gerçek ağ/RPC/WASM/subprocess YOK.
main()-dosya-okuma-dalları tmp_path-üzerinde-yönlendirilir.

Kapsanan fonksiyonlar (3):
  _rfc010_ok  RFC-010 dikiş-önkoşulu: settlement_bind dict + delivery_hash
              {alg, hex(64)} → True; eksik/bozuk → False
  verify      çelişkiyi-ALGILAR-ve-dış-çözüme-YÖNLENDİRİR (hakemlik-YAPMAZ):
              GREEN rc0 (itiraz-yok / status:none / resolved) ·
              RED rc1 (rfc010-geçersiz) · rc2 (dp dict-değil) ·
              rc3 (contradiction-ama-counter_claim-yok) ·
              rc9 (arbitration-yok/bozuk) · rc10 (bond <%20) ·
              İNDETERMİNE rc11 (bilinmeyen-protokol — sonuç-esirgenir) ·
              rc12 (çelişki + yönlendirme-sağlam → insan-gerekir)
  main        CLI: GREEN→rc0, RED→rc1, İNDETERMİNE→rc2, argc-hatası→rc1

Dal listesi (başarı + başarısızlık + sınır):
  _rfc010_ok : bind-dict / bind-yok / bind-list / dh-yok / dh-eksik-anahtar /
               dh-fazla-anahtar / hex-uzunluğu 63/64/65 / alg-eksik
  verify     : 12-yukarıdaki-her-verdict + status-escalation-sırası +
               counter_claim-şartı (buyer_signed-True + delivered-False) +
               terms_hash-uzunluk-sınırı + bond-sınırı (0.20-geçer / 0.19-red) +
               additive-protokol-listesi (her-bilinen-protokol rc12)
  main       : rc-eşlemi + dosya-yükleme
"""
from __future__ import annotations

import json
import sys

import pytest

sys.path.insert(0, ".")
sys.path.insert(0, "tools")
import dispute_pointer_verify as dpv  # noqa: E402

_H64 = "a" * 64
_ARBITRATION = {"protocol": "pacta/v1", "terms_hash": _H64}


def _charge(**over) -> dict:
    """Geçerli RFC-010 dikişi + isteğe-bağlı anlaşmazlık-bacağı."""
    c = {
        "settlement_bind": {"payee": "0xabc", "amount": 1.0},
        "delivery_hash": {"alg": "sha256", "hex": _H64},
    }
    c.update(over)
    return c


def _contradiction(**over) -> dict:
    """status:contradiction + geçerli counter_claim + yönlendirme + bond."""
    dp = {
        "status": "contradiction",
        "counter_claim": {"buyer_signed": True, "delivered": False},
        "arbitration": dict(_ARBITRATION),
        "bond_pct": 0.25,
    }
    dp.update(over)
    return _charge(dispute_pointer=dp)


# == _rfc010_ok =================================================================================

class TestRfc010Onkosul:
    def test_ok(self):
        assert dpv._rfc010_ok(_charge()) is True

    def test_ok_minimal_bind(self):
        """bind-içeriği-denetlenmez — dict-olması-yeterli."""
        assert dpv._rfc010_ok({"settlement_bind": {}, "delivery_hash": {
            "alg": "sha256", "hex": _H64}}) is True

    def test_bind_missing(self):
        assert dpv._rfc010_ok({"delivery_hash": {"alg": "sha256", "hex": _H64}}) is False

    def test_bind_not_dict(self):
        assert dpv._rfc010_ok({"settlement_bind": "x",
                               "delivery_hash": {"alg": "sha256", "hex": _H64}}) is False

    def test_delivery_hash_missing(self):
        assert dpv._rfc010_ok({"settlement_bind": {}}) is False

    def test_delivery_hash_not_dict(self):
        assert dpv._rfc010_ok({"settlement_bind": {},
                               "delivery_hash": _H64}) is False

    @pytest.mark.parametrize("dh", [
        {"alg": "sha256"},                       # hex eksik
        {"hex": _H64},                            # alg eksik
        {"alg": "sha256", "hex": _H64, "x": 1},   # fazla anahtar
        {"alg": "sha256", "hex": "a" * 63},       # kısa
        {"alg": "sha256", "hex": "a" * 65},       # uzun
        {},                                       # boş
    ])
    def test_delivery_hash_invalid(self, dh):
        assert dpv._rfc010_ok({"settlement_bind": {}, "delivery_hash": dh}) is False

    @pytest.mark.parametrize("hexv", ["g" * 64, "A" * 64, "G" * 32 + "A" * 32,
                                      " " * 64, "0" * 64])
    def test_only_length_checked_not_content(self, hexv):
        """ORTAM-KARAKTERİZASYON: kapı SADECE len(hex)==64-denetler —
        hex-içeriği-değil. 'g'*64-ve-'A'*64-uzunluk-64-olduğu-için-GEÇER.
        Karakter-doğrulaması-bu-gate'in-dışında; test-belgeler, düzeltmez."""
        assert dpv._rfc010_ok({"settlement_bind": {},
                               "delivery_hash": {"alg": "sha256",
                                                 "hex": hexv}}) is True

    def test_exact_64_lowercase_hex_ok(self):
        assert dpv._rfc010_ok({"settlement_bind": {},
                               "delivery_hash": {"alg": "sha256",
                                                 "hex": "0123456789abcdef" * 4}}) is True

    def test_returns_bool(self):
        assert isinstance(dpv._rfc010_ok(_charge()), bool)


# == verify: GREEN dalları =======================================================================

class TestVerifyYesil:
    def test_no_dispute_pointer_green(self):
        """dp-yok → geri-uyumlu GREEN (RFC-010 ekleyen eski kayıtlar)."""
        r = dpv.verify(_charge())
        assert r["ok"] is True
        assert r["verdict"] == "GREEN"
        assert r["reason_code"] == 0

    def test_no_dispute_pointer_reason(self):
        r = dpv.verify(_charge())
        assert "itiraz-yok" in r["reason"]

    def test_status_none_green(self):
        r = dpv.verify(_charge(dispute_pointer={"status": "none"}))
        assert r["verdict"] == "GREEN"
        assert r["reason_code"] == 0
        assert r["ok"] is True

    def test_status_resolved_green(self):
        r = dpv.verify(_charge(dispute_pointer={"status": "resolved"}))
        assert r["verdict"] == "GREEN"
        assert r["reason_code"] == 0
        assert "hakemlik-bitti" in r["reason"]

    @pytest.mark.parametrize("status", ["none", "resolved"])
    def test_green_statuses_ignore_other_fields(self, status):
        """none/resolved-için-çelişki-algılama-koşulmaz (sakin-durum)."""
        r = dpv.verify(_charge(dispute_pointer={
            "status": status, "counter_claim": {"buyer_signed": True,
                                                "delivered": False}}))
        assert r["verdict"] == "GREEN"

    def test_rfc010_check_recorded_true(self):
        r = dpv.verify(_charge())
        assert r["checks"]["1_rfc010"] is True


# == verify: RED rc1 (RFC-010 önkoşul) ===========================================================

class TestVerifyRc1:
    @pytest.mark.parametrize("charge", [
        {},                                              # dikiş-yok
        {"settlement_bind": "x"},                        # bind dict-değil
        {"settlement_bind": {}, "delivery_hash": {"alg": "x"}},   # hex eksik
        {"settlement_bind": {}, "delivery_hash": {"alg": "x", "hex": "a" * 10}},
    ])
    def test_rfc010_invalid_red_rc1(self, charge):
        r = dpv.verify(charge)
        assert r["verdict"] == "RED"
        assert r["reason_code"] == 1
        assert r["ok"] is None

    def test_rfc010_reason(self):
        r = dpv.verify({})
        assert "rfc010_missing" in r["reason"]

    def test_rfc010_short_circuits_dispute_pointer(self):
        """Önkoşul-tutarsa-dahi-dikiş-geçersizse-RED — dp'ye-bakılmaz."""
        r = dpv.verify({"settlement_bind": None,
                        "dispute_pointer": {"status": "contradiction"}})
        assert r["reason_code"] == 1

    def test_check_flagged_false(self):
        r = dpv.verify({})
        assert r["checks"]["1_rfc010"] is False


# == verify: RED rc2 (dp dict-değil) =============================================================

class TestVerifyRc2:
    @pytest.mark.parametrize("dp", ["yazi", 5, True, ["status"], 3.14])
    def test_dp_not_dict_red_rc2(self, dp):
        r = dpv.verify(_charge(dispute_pointer=dp))
        assert r["verdict"] == "RED"
        assert r["reason_code"] == 2

    def test_dp_not_dict_reason(self):
        r = dpv.verify(_charge(dispute_pointer="yazi"))
        assert "dispute_pointer_invalid" in r["reason"]

    def test_dp_false_is_not_none(self):
        """dp=False → None-değil → dict-kontrolüne-takılır (rc2, rc0 DEĞİL)."""
        r = dpv.verify(_charge(dispute_pointer=False))
        assert r["reason_code"] == 2

    def test_dp_zero_is_not_none(self):
        r = dpv.verify(_charge(dispute_pointer=0))
        assert r["reason_code"] == 2


# == verify: RED rc3 (contradiction-ama-counter_claim-yok) ========================================

class TestVerifyRc3:
    def test_contradiction_without_counter_claim_rc3(self):
        r = dpv.verify(_charge(dispute_pointer={"status": "contradiction"}))
        assert r["verdict"] == "RED"
        assert r["reason_code"] == 3

    def test_rc3_reason(self):
        r = dpv.verify(_charge(dispute_pointer={"status": "contradiction"}))
        assert "contradiction_status_ama_counter_claim_yok" in r["reason"]

    @pytest.mark.parametrize("cc", [
        None,
        {"buyer_signed": True},               # delivered eksik
        {"delivered": False},                 # buyer_signed eksik
        {"buyer_signed": False, "delivered": False},  # imzalı-değil
        {"buyer_signed": True, "delivered": True},    # teslim-edilmiş
        "imza-var",
    ])
    def test_weak_counter_claim_still_rc3(self, cc):
        """Geçerli-counter_claim = dict + buyer_signed:True + delivered:False.
        Bunun-dışındaki-her-şey has_cc=False → rc3."""
        r = dpv.verify(_charge(dispute_pointer={"status": "contradiction",
                                                "counter_claim": cc}))
        assert r["reason_code"] == 3

    def test_contradiction_check_flagged_false(self):
        r = dpv.verify(_charge(dispute_pointer={"status": "contradiction"}))
        assert r["checks"]["2_contradiction"] is False

    def test_valid_counter_claim_flags_true(self):
        r = dpv.verify(_contradiction())
        assert r["checks"]["2_contradiction"] is True


# == verify: RED rc9 (arbitration) ===============================================================

class TestVerifyRc9:
    @pytest.mark.parametrize("arb", [
        None,                                    # yok
        "pacta/v1",                              # dict-değil
        {},                                      # boş
        {"protocol": "pacta/v1"},                # terms_hash eksik
        {"terms_hash": _H64},                    # protocol eksik
        {"protocol": 5, "terms_hash": _H64},     # protocol str-değil
        {"protocol": "pacta/v1", "terms_hash": 5},  # terms_hash str-değil
        {"protocol": "pacta/v1", "terms_hash": "a" * 63},  # kısa
        {"protocol": "pacta/v1", "terms_hash": "a" * 65},  # uzun
    ])
    def test_arbitration_invalid_rc9(self, arb):
        """status 'open' → rc3-dalı-atlanır, arbitration-denetimi-vurur."""
        r = dpv.verify(_charge(dispute_pointer={"status": "open",
                                                "arbitration": arb}))
        assert r["verdict"] == "RED"
        assert r["reason_code"] == 9

    def test_rc9_reason(self):
        r = dpv.verify(_charge(dispute_pointer={"status": "open"}))
        assert "arbitration_missing" in r["reason"]

    def test_rc9_check_flagged_false(self):
        r = dpv.verify(_charge(dispute_pointer={"status": "open"}))
        assert r["checks"]["3_arbitration"] is False

    def test_valid_arbitration_passes_gate(self):
        """Geçerli-arbitration → rc9-dalı-atlanır (bond-a-geçilir)."""
        r = dpv.verify(_charge(dispute_pointer={"status": "open",
                                                "arbitration": _ARBITRATION,
                                                "bond_pct": 0.3}))
        assert r["reason_code"] != 9


# == verify: RED rc10 (bond) =====================================================================

class TestVerifyRc10:
    def _charge_with_bond(self, bond):
        return _charge(dispute_pointer={"status": "open",
                                        "arbitration": _ARBITRATION,
                                        "bond_pct": bond})

    @pytest.mark.parametrize("bond", [0.0, 0.05, 0.19, 0.199, -0.5])
    def test_bond_below_minimum_rc10(self, bond):
        r = dpv.verify(self._charge_with_bond(bond))
        assert r["verdict"] == "RED"
        assert r["reason_code"] == 10

    @pytest.mark.parametrize("bond", ["0.5", None, [0.5]])
    def test_bond_wrong_type_rc10(self, bond):
        """str/None/list → isinstance(bond, (int,float)) False → rc10.
        NOT: bool-bir-int-alt-türüdür — True==1.0 → GECER (aşağıdaki-test)."""
        r = dpv.verify(self._charge_with_bond(bond))
        assert r["reason_code"] == 10

    def test_bond_boundary_exact_minimum_ok(self):
        """MIN_BOND_PCT = 0.20 — tam-sınırdaki-değer-GEÇER (kapalı-sınır)."""
        r = dpv.verify(self._charge_with_bond(dpv.MIN_BOND_PCT))
        assert r["reason_code"] != 10

    def test_bond_one_hundred_pct_ok(self):
        r = dpv.verify(self._charge_with_bond(1.0))
        assert r["reason_code"] != 10

    def test_bond_bool_true_passes_type_gate(self):
        """ORTAM-KARAKTERİZASYON: bool-int-alt-türüdür → isinstance(True,(int,float))
        doğrudur; True >= 0.20 → bond-kapısını-geçer. Python-quirk-belgesi."""
        r = dpv.verify(self._charge_with_bond(True))
        assert r["reason_code"] != 10

    def test_rc10_reason_contains_value_and_minimum(self):
        r = dpv.verify(self._charge_with_bond(0.05))
        assert "bond_insufficient" in r["reason"]
        assert "0.05" in r["reason"]
        assert str(dpv.MIN_BOND_PCT) in r["reason"]

    def test_bond_check_flagged(self):
        r = dpv.verify(self._charge_with_bond(0.05))
        assert r["checks"]["4_bond"] is False
        r2 = dpv.verify(self._charge_with_bond(0.5))
        assert r2["checks"]["4_bond"] is True


# == verify: İNDETERMİNE rc11 (bilinmeyen-protokol) =================================================

class TestVerifyRc11:
    def test_unknown_protocol_indeterminate_rc11(self):
        """additive-terfi: bilinmeyen-protokol RED-değil-İNDETERMİNE (sonuç-esirgenir)."""
        r = dpv.verify(_contradiction(arbitration={"protocol": "bilinmiyor/v1",
                                                   "terms_hash": _H64}))
        assert r["verdict"] == "İNDETERMİNE"
        assert r["reason_code"] == 11
        assert r["ok"] is None

    def test_rc11_reason_lists_supported(self):
        r = dpv.verify(_contradiction(arbitration={"protocol": "x/y",
                                                   "terms_hash": _H64}))
        assert "unknown_arbitration_protocol" in r["reason"]
        for proto in dpv.SUPPORTED_PROTOCOLS:
            assert proto in r["reason"]

    @pytest.mark.parametrize("proto", [
        "PACTA/V1",                       # case-sensitive → bilinmiyor
        "pacta/v2",                       # versiyon-bilinmiyor
        "holistis/disputecontext",        # küçük-harf → bilinmiyor (case-sensitive)
        "",                               # boş
    ])
    def test_protocol_matching_is_case_sensitive(self, proto):
        r = dpv.verify(_contradiction(arbitration={"protocol": proto,
                                                   "terms_hash": _H64}))
        assert r["reason_code"] == 11


# == verify: İNDETERMİNE rc12 (çelişki + yönlendirme) ===============================================

class TestVerifyRc12:
    @pytest.mark.parametrize("proto", list(dpv.SUPPORTED_PROTOCOLS))
    def test_every_supported_protocol_reaches_rc12(self, proto):
        """additive-terfi: her-bilinen-protokol rc12-verir (insan/hakem-gerekir)."""
        r = dpv.verify(_contradiction(arbitration={"protocol": proto,
                                                   "terms_hash": _H64}))
        assert r["verdict"] == "İNDETERMİNE"
        assert r["reason_code"] == 12

    def test_rc12_reason_mentions_protocol(self):
        r = dpv.verify(_contradiction())
        assert "contradiction" in r["reason"]
        assert "pacta/v1" in r["reason"]

    def test_rc12_is_not_ok(self):
        """İNDETERMİNE 'ok' değeri None — yeşil-değil, sonuç-esirgenmiş."""
        r = dpv.verify(_contradiction())
        assert r["ok"] is not True

    def test_all_checks_true_at_rc12(self):
        r = dpv.verify(_contradiction())
        assert r["checks"]["1_rfc010"] is True
        assert r["checks"]["2_contradiction"] is True
        assert r["checks"]["3_arbitration"] is True
        assert r["checks"]["4_bond"] is True

    def test_resolved_with_full_payload_still_green(self):
        """status:resolved → çelişki-algılama-atlanır (rc12'ye-girmez)."""
        r = dpv.verify(_contradiction(status="resolved"))
        assert r["verdict"] == "GREEN"
        assert r["reason_code"] == 0


# == verify: çıkış şekli =========================================================================

class TestVerifyCikisSekli:
    def test_initial_keys_present(self):
        r = dpv.verify(_charge())
        for k in ("ok", "verdict", "reason", "reason_code", "checks"):
            assert k in r

    def test_checks_only_rfc010_when_no_dp(self):
        r = dpv.verify(_charge())
        assert set(r["checks"]) == {"1_rfc010"}

    def test_red_preserves_ok_none(self):
        r = dpv.verify({})
        assert r["ok"] is None


# == main ========================================================================================

class TestMain:
    """main(argv) argv[0]=program-adı, argv[1]=charge-yolu-kabul-eder
    (len(argv)==2-zorunlu). Kütüphane-çağrısı-main(["prog", yol])-şeklindedir."""

    def _run(self, tmp_path, charge):
        p = tmp_path / "charge.json"
        p.write_text(json.dumps(charge, ensure_ascii=False), encoding="utf-8")
        return dpv.main(["prog", str(p)])

    def test_green_rc0(self, tmp_path):
        assert self._run(tmp_path, _charge()) == 0

    @pytest.mark.parametrize("status", ["none", "resolved"])
    def test_green_status_rc0(self, tmp_path, status):
        c = _charge(dispute_pointer={"status": status})
        assert self._run(tmp_path, c) == 0

    @pytest.mark.parametrize("reason_code,expect_rc", [
        (1, 1), (2, 1), (3, 1), (9, 1), (10, 1),   # RED → rc1
    ])
    def test_red_rc1(self, tmp_path, reason_code, expect_rc):
        charges = {
            1: {},
            2: _charge(dispute_pointer="x"),
            3: _charge(dispute_pointer={"status": "contradiction"}),
            9: _charge(dispute_pointer={"status": "open"}),
            10: _charge(dispute_pointer={"status": "open",
                                         "arbitration": _ARBITRATION,
                                         "bond_pct": 0.01}),
        }
        assert self._run(tmp_path, charges[reason_code]) == expect_rc

    def test_indeterminate_rc2(self, tmp_path):
        c = _contradiction(arbitration={"protocol": "bilinmiyor/v1",
                                        "terms_hash": _H64})
        assert self._run(tmp_path, c) == 2

    def test_contradiction_rc2(self, tmp_path):
        assert self._run(tmp_path, _contradiction()) == 2

    @pytest.mark.parametrize("argv", [[], ["prog"], ["prog", "a", "b"]])
    def test_wrong_argc_prints_doc(self, capsys, argv):
        rc = dpv.main(list(argv))
        assert rc == 1
        assert "RFC-011" in capsys.readouterr().out

    def test_main_outputs_verdict_json(self, tmp_path, capsys):
        self._run(tmp_path, _charge())
        o = json.loads(capsys.readouterr().out)
        assert o["verdict"] == "GREEN"
        assert o["reason_code"] == 0


# == birleşik: dallar arası sıra ================================================================

class TestDalSirasi:
    @pytest.mark.parametrize("over,expect_code", [
        ({"settlement_bind": None}, 1),                            # rfc010-ilk
        ({"dispute_pointer": "x"}, 2),                              # dp-şekli
        ({"dispute_pointer": {"status": "contradiction"}}, 3),      # çelişki-şartı
        ({"dispute_pointer": {"status": "open"}}, 9),               # yönlendirme
        ({"dispute_pointer": {"status": "open",
                              "arbitration": _ARBITRATION}}, 10),   # bond
    ])
    def test_first_failure_wins(self, over, expect_code):
        """Kontrol-sırası: rfc010 → dp-şekli → status → çelişki → arbitration → bond."""
        c = _charge()
        c.update(over)
        assert dpv.verify(c)["reason_code"] == expect_code

    def test_bond_before_protocol(self):
        """bond-geçersiz-ve-protokol-bilinmiyorsa → rc10-önce (sıra)."""
        c = _contradiction(bond_pct=0.0,
                           arbitration={"protocol": "bilinmiyor/v1",
                                        "terms_hash": _H64})
        assert dpv.verify(c)["reason_code"] == 10

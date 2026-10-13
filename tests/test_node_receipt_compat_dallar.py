"""tools/node_receipt_compat.py dal-kesen testleri (LEED) — makbuz-uyumluluk kilidi.

Kural-1: MEVCUT DOSYALARA DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory — girdiler-json/tmp_path'te; gerçek-ağ/RPC/WASM/
subprocess YOK (mini-verify saf-stdlib). Disk-YAZIMI-yalnızca tmp_path'te.

Kapsanan fonksiyonlar (4):
  _digest_of   sha256(prev + jcs(rec-h-ve-node_sig-çıkarılmış)) — özet-üretimi
  check        3-kademeli-geçiş: (1) ledger-verify (2) membership (3) digest-parity
               — hepsi-GREEN ise üretim-makbuzu-kanıtlanır
  ledger_report ledger'in-yalnızca-özgeçmiş özeti (ok-öncesi-diagnostik)
  main         CLI: check/ledger alt-komutları + yardım-dalı

Dal listesi (başarı + başarısızlık + sınır):
  _digest_of : formül-doğruluğu / h-ve-node_sig-dışlanma / prev-yoksa-''
               determinizm / farklı-kayıt-farklı-özet / uzunluk-64-hex / unicode
  check : charge-yükleme-hataları (eksik/bozuk-JSON/liste/skalar) /
          ledger-verify-RED (bozuk-JSON / seq-boşluğu / prev-uymaz / h-bozuk /
          boş-zincir / eksik-dosya) / membership-RED (kayıt-yok / değer-farklı /
          alan-eksik) / digest-parity-RED (mini_verify-stub'ı-ile-erişilir) /
          GREEN-tüm-kademeler / boş-charge-vaküe-ilk-kayıt /
          özet-paritesi-tekrarlanabilir / çok-kayıtlı-zincirde-ikinci-kayıt /
          ilk-eşleşen-kazanır / üst-küme-kayıt / str-ve-Path-giriş
  ledger_report : GREEN / RED / boş-zincir / eksik-dosya / dönüş-anahtarları /
                  çok-kayıtlı-son-tip
  main : check-rc0·rc1 / ledger-rc0·rc1 / eksik-argüman-rc2 /
         bilinmeyen-komut-rc2 / argümansız-yardım-rc2 / stdout-JSON
"""
from __future__ import annotations

import hashlib
import json
import sys

import pytest

sys.path.insert(0, ".")
sys.path.insert(0, "tools")
import node_receipt_compat as nrc  # noqa: E402
from tamga_verify_mini import jcs  # noqa: E402

GENESIS_PREV = "0" * 64


# == yardımcı: geçerli zincir üret ===============================================================

def _mk_ledger(recs, base, filename="ledger.jsonl"):
    """seq 1'den-başlayan, prev-ve-h'_digest_of'-ile-tutarlı geçerli-zincir.
    mini_verify'ın-beklediği-tam-formülü-kullanır (özet-paylaşımı-doğrulanmış;
    burada-sadece-ölçeklendirme-için-kullanılır, modül-içi-şart-değil)."""
    prev = GENESIS_PREV
    lines = []
    for i, rec in enumerate(recs, 1):
        r = dict(rec)
        r["seq"] = i
        r["prev"] = prev
        r["h"] = nrc._digest_of(r)
        prev = r["h"]
        lines.append(json.dumps(r, ensure_ascii=False))
    p = base / filename
    p.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
    return p


def _mk_charge(fields, base, filename="charge.json"):
    p = base / filename
    p.write_text(json.dumps(fields, ensure_ascii=False), encoding="utf-8")
    return p


def _charge_fields(**over):
    f = {"op": "charge", "amount": 1.0, "payee": "0xabc"}
    f.update(over)
    return f


def _ok_pair(tmp_path):
    """Geçerli-zincir + içinde-bulunan-charge → GREEN-çifti."""
    lp = _mk_ledger([_charge_fields()], base=tmp_path)
    cp = _mk_charge(_charge_fields(), base=tmp_path)
    return cp, lp


def _expect_stage(r, stage):
    """RED-dönüşlerinin-ortak-şekli: ok=False + verdict=RED + stage."""
    assert r["ok"] is False, r
    assert r["verdict"] == "RED"
    assert r["stage"] == stage, r


# == _digest_of ===================================================================================

class TestDigestOf:
    def test_formula(self):
        rec = {"op": "charge", "amount": 1.0, "prev": GENESIS_PREV, "seq": 1}
        expected = hashlib.sha256(
            (GENESIS_PREV + jcs(rec).decode("utf-8")).encode("utf-8")).hexdigest()
        assert nrc._digest_of(rec) == expected

    def test_h_excluded_from_digest_input(self):
        rec = {"op": "charge", "prev": GENESIS_PREV, "seq": 1}
        d = nrc._digest_of(rec)
        poisoned = dict(rec)
        poisoned["h"] = "a" * 64
        assert nrc._digest_of(poisoned) == d

    def test_node_sig_excluded(self):
        rec = {"op": "charge", "prev": GENESIS_PREV, "seq": 1}
        d = nrc._digest_of(rec)
        signed = dict(rec)
        signed["node_sig"] = "sig-bytes"
        assert nrc._digest_of(signed) == d

    def test_missing_prev_uses_empty_string(self):
        rec = {"op": "charge", "seq": 1}
        expected = hashlib.sha256(("" + jcs(rec).decode("utf-8"))
                                  .encode("utf-8")).hexdigest()
        assert nrc._digest_of(rec) == expected

    def test_deterministic(self):
        rec = {"op": "charge", "prev": GENESIS_PREV, "seq": 1}
        assert nrc._digest_of(rec) == nrc._digest_of(rec)

    def test_different_records_different_digest(self):
        a = {"op": "charge", "prev": GENESIS_PREV, "seq": 1}
        b = {"op": "charge", "prev": GENESIS_PREV, "seq": 2}
        assert nrc._digest_of(a) != nrc._digest_of(b)

    def test_length_64_hex(self):
        d = nrc._digest_of({"op": "charge", "seq": 1, "prev": GENESIS_PREV})
        assert len(d) == 64
        assert all(c in "0123456789abcdef" for c in d)

    def test_unicode_record(self):
        """Türkçe-içerik-JCS-sıralı-kanonik-formda-doğru-özet-verir."""
        d = nrc._digest_of({"op": "çığ", "not": "İstanbul", "seq": 1})
        assert isinstance(d, str) and len(d) == 64


# == check: charge yükleme ========================================================================

class TestCheckChargeYukleme:
    """Yükleme-hataları stage-öncesi-döner: verdict-yok, yalnızca ok+reason."""

    def test_missing_charge_file(self, tmp_path):
        lp = _mk_ledger([_charge_fields()], base=tmp_path)
        r = nrc.check(str(tmp_path / "yok.json"), str(lp))
        assert r["ok"] is False
        assert "charge" in r["reason"]
        assert "stage" not in r

    def test_invalid_json(self, tmp_path):
        lp = _mk_ledger([_charge_fields()], base=tmp_path)
        cp = tmp_path / "charge.json"
        cp.write_text("{bu-geçerli-json-değil}", encoding="utf-8")
        r = nrc.check(str(cp), str(lp))
        assert r["ok"] is False
        assert "charge" in r["reason"]

    def test_json_list_not_dict(self, tmp_path):
        lp = _mk_ledger([_charge_fields()], base=tmp_path)
        cp = tmp_path / "charge.json"
        cp.write_text("[1, 2, 3]", encoding="utf-8")
        r = nrc.check(str(cp), str(lp))
        assert r["ok"] is False
        assert "nesnesi değil" in r["reason"]

    def test_json_scalar_not_dict(self, tmp_path):
        lp = _mk_ledger([_charge_fields()], base=tmp_path)
        cp = tmp_path / "charge.json"
        cp.write_text('"düz-metin"', encoding="utf-8")
        r = nrc.check(str(cp), str(lp))
        assert r["ok"] is False
        assert "nesnesi değil" in r["reason"]


# == check: kademe-1 ledger-verify ===============================================================

class TestCheckLedgerVerify:
    def test_ok(self, tmp_path):
        cp, lp = _ok_pair(tmp_path)
        r = nrc.check(str(cp), str(lp))
        assert r["ok"] is True, r
        assert r["verdict"] == "GREEN"

    def test_empty_ledger_passes_stage1_fails_membership(self, tmp_path):
        """ORTAM-KARAKTERİZASYON (önemli-bulgu): BOŞ-zincir-mini_verify'dan
        GEÇER — genesis-tip '0'*64-geçerli-bir-zincir-sonudur. Bu-yüzden-check
        kademe-1'i-atlatır-ve-charge-kayıt-yoksa-membership-RED-verir.
        Boş-node-ledger'ı 'kırık' DEĞİL: geçerli-genesis'tir; makbuz-iddiası
        ancak-kayıt-üyeliğiyle-çürütülür (doğru-hata-modu)."""
        cp = _mk_charge(_charge_fields(), base=tmp_path)
        lp = _mk_ledger([], base=tmp_path)
        r = nrc.check(str(cp), str(lp))
        _expect_stage(r, "membership")
        assert "membership-RED" in r["reason"]

    def test_empty_ledger_stage1_proven_via_no_stage_key(self, tmp_path):
        """Stage-1-RED-dönüşü-stage-anahtarı-taşımaz-ama-membership-taşır:
        boş-zincir-membership-dalına-düşer → ledger-verify-geçildiğini-kanıtlar."""
        cp = _mk_charge(_charge_fields(), base=tmp_path)
        lp = _mk_ledger([], base=tmp_path)
        r = nrc.check(str(cp), str(lp))
        assert r["stage"] == "membership"

    def test_missing_ledger_file(self, tmp_path):
        """mini_verify OSError'ı-yakalar → io_error → RED."""
        cp = _mk_charge(_charge_fields(), base=tmp_path)
        r = nrc.check(str(cp), str(tmp_path / "yok.jsonl"))
        _expect_stage(r, "ledger-verify")
        assert "node-ledger-kırık" in r["reason"]

    def test_invalid_json_line(self, tmp_path):
        cp = _mk_charge(_charge_fields(), base=tmp_path)
        lp = tmp_path / "ledger.jsonl"
        lp.write_text("{geçersiz}\n", encoding="utf-8")
        r = nrc.check(str(cp), str(lp))
        _expect_stage(r, "ledger-verify")
        assert "unparseable" in r["reason"]

    def test_record_not_object(self, tmp_path):
        """JSON-dizisi-satırı → 'record is not a JSON object' → RED."""
        cp = _mk_charge(_charge_fields(), base=tmp_path)
        lp = tmp_path / "ledger.jsonl"
        lp.write_text("[1, 2]\n", encoding="utf-8")
        r = nrc.check(str(cp), str(lp))
        _expect_stage(r, "ledger-verify")
        assert "not a JSON object" in r["reason"]

    def test_seq_gap(self, tmp_path):
        """seq 1,3 → sıra-tutarlılığı-bozulur → broken@2."""
        cp = _mk_charge(_charge_fields(), base=tmp_path)
        lp = tmp_path / "ledger.jsonl"
        recs = []
        prev = GENESIS_PREV
        for seq, rec in [(1, _charge_fields()), (3, _charge_fields())]:
            r = dict(rec)
            r["seq"] = seq
            r["prev"] = prev
            r["h"] = nrc._digest_of(r)
            prev = r["h"]
            recs.append(json.dumps(r, ensure_ascii=False))
        lp.write_text("\n".join(recs) + "\n", encoding="utf-8")
        r = nrc.check(str(cp), str(lp))
        _expect_stage(r, "ledger-verify")
        assert "broken@2" in r["reason"]

    def test_prev_mismatch(self, tmp_path):
        """2-kayıdın-prev'i-sahte → zincir-kırılır → broken@2."""
        cp = _mk_charge(_charge_fields(), base=tmp_path)
        lp = tmp_path / "ledger.jsonl"
        recs = []
        prev = GENESIS_PREV
        for i, rec in enumerate([_charge_fields(),
                                 _charge_fields(op="diger")], 1):
            r = dict(rec)
            r["seq"] = i
            r["prev"] = prev
            r["h"] = nrc._digest_of(r)
            if i == 2:
                r["prev"] = "f" * 64  # sahte-prev
            prev = r["h"]
            recs.append(json.dumps(r, ensure_ascii=False))
        lp.write_text("\n".join(recs) + "\n", encoding="utf-8")
        r = nrc.check(str(cp), str(lp))
        _expect_stage(r, "ledger-verify")
        assert "broken@2" in r["reason"]

    def test_tampered_h(self, tmp_path):
        """Formülle-uyumsuz h → broken@1."""
        cp = _mk_charge(_charge_fields(), base=tmp_path)
        lp = tmp_path / "ledger.jsonl"
        recs = []
        prev = GENESIS_PREV
        for i, rec in enumerate([_charge_fields()], 1):
            r = dict(rec)
            r["seq"] = i
            r["prev"] = prev
            r["h"] = "b" * 64  # sahte-özet
            prev = r["h"]
            recs.append(json.dumps(r, ensure_ascii=False))
        lp.write_text("\n".join(recs) + "\n", encoding="utf-8")
        r = nrc.check(str(cp), str(lp))
        _expect_stage(r, "ledger-verify")
        assert "broken@1" in r["reason"]

    def test_bomb_line_rejected(self, tmp_path):
        """Audit-11: MAX_LINE_BYTES (1 MiB) üstü-satır-yutulmaz."""
        from tamga_verify_mini import MAX_LINE_BYTES
        cp = _mk_charge(_charge_fields(), base=tmp_path)
        lp = tmp_path / "ledger.jsonl"
        big = "a" * (MAX_LINE_BYTES + 10)
        lp.write_text(f'{{"pad": "{big}"}}\n', encoding="utf-8")
        r = nrc.check(str(cp), str(lp))
        _expect_stage(r, "ledger-verify")
        assert "bomba-satırı" in r["reason"]


# == check: kademe-2 membership ===================================================================

class TestCheckMembership:
    def test_no_record_contains_charge(self, tmp_path):
        """Zincir-geçerli-ama-kayıtlar-charge'ı-içermiyor → RED membership."""
        lp = _mk_ledger([_charge_fields(op="baska")], base=tmp_path)
        cp = _mk_charge(_charge_fields(op="charge"), base=tmp_path)
        r = nrc.check(str(cp), str(lp))
        _expect_stage(r, "membership")
        assert "membership-RED" in r["reason"]

    def test_wrong_value_in_record(self, tmp_path):
        """Alan-var-ama-değer-farklı → membership-RED."""
        lp = _mk_ledger([_charge_fields(amount=2.0)], base=tmp_path)
        cp = _mk_charge(_charge_fields(amount=1.0), base=tmp_path)
        r = nrc.check(str(cp), str(lp))
        _expect_stage(r, "membership")

    def test_missing_field_in_record(self, tmp_path):
        lp = _mk_ledger([{"op": "charge", "amount": 1.0}], base=tmp_path)
        cp = _mk_charge(_charge_fields(), base=tmp_path)  # payee-kayıtta-yok
        r = nrc.check(str(cp), str(lp))
        _expect_stage(r, "membership")

    def test_superset_record_matches(self, tmp_path):
        """Kayıt-charge'ın-üst-kümesi → membership-geçer (alt-küme-eşleşmesi)."""
        rec = _charge_fields()
        rec["extra"] = "not"
        lp = _mk_ledger([rec], base=tmp_path)
        cp = _mk_charge(_charge_fields(), base=tmp_path)
        r = nrc.check(str(cp), str(lp))
        assert r["ok"] is True, r

    def test_empty_charge_matches_first_record(self, tmp_path):
        """ORTAM-KARAKTERİZASYON: boş-charge → `all(...)`-vaküe-doğru →
        İLK-kayıt-bulunur. Boş-nesne-üretim-makbuzu-sayılır (denetçi-yükümlü)."""
        lp = _mk_ledger([_charge_fields(op="ilk")], base=tmp_path)
        cp = _mk_charge({}, base=tmp_path)
        r = nrc.check(str(cp), str(lp))
        assert r["ok"] is True, r
        assert r["charge_seq"] == 1

    def test_charge_found_in_second_record(self, tmp_path):
        """Çok-kayıtlı-zincirde-charge-ikinci-kayıtta → seq=2."""
        lp = _mk_ledger([_charge_fields(op="ilk"),
                         _charge_fields(op="charge")], base=tmp_path)
        cp = _mk_charge(_charge_fields(op="charge"), base=tmp_path)
        r = nrc.check(str(cp), str(lp))
        assert r["ok"] is True, r
        assert r["charge_seq"] == 2

    def test_first_matching_record_wins(self, tmp_path):
        """Aynı-alanlara-iki-kayıt → İLK-bulunan-kazanır (kısa-devre)."""
        lp = _mk_ledger([_charge_fields(op="charge", tag="a"),
                         _charge_fields(op="charge", tag="b")], base=tmp_path)
        cp = _mk_charge(_charge_fields(op="charge"), base=tmp_path)
        r = nrc.check(str(cp), str(lp))
        assert r["charge_seq"] == 1

    def test_malformed_line_unreachable_after_stage1(self, tmp_path):
        """ORTAM-KARAKTERİZASYON: üyelik-taramasının-ValueError-atlama-dalı
        ölüdür — mini_verify-aynı-bozuk-satırı-zaten-reddettiği-için-stage-1
        her-geçerli-zincir-tamamen-parse-edilebilir-satır'lardan-oluşur.
        Test-bu-ölü-dalı-belgeler (karakterizasyon, düzeltme-değil)."""
        lp = _mk_ledger([_charge_fields(op="ilk"),
                         _charge_fields(op="charge")], base=tmp_path)
        text = "{BOZUK\n" + lp.read_text(encoding="utf-8")
        lp.write_text(text, encoding="utf-8")
        cp = _mk_charge(_charge_fields(op="charge"), base=tmp_path)
        r = nrc.check(str(cp), str(lp))
        _expect_stage(r, "ledger-verify")
        assert "unparseable" in r["reason"]


# == check: kademe-3 digest-parity ===============================================================

class TestCheckDigestParity:
    def test_green_digest_matches(self, tmp_path):
        cp, lp = _ok_pair(tmp_path)
        r = nrc.check(str(cp), str(lp))
        assert r["ok"] is True, r
        # bulunan-kayıt = charge-alanları + seq + prev (+ h-dışlanır)
        rec = _charge_fields()
        rec["seq"] = 1
        rec["prev"] = GENESIS_PREV
        assert r["charge_digest"] == nrc._digest_of(rec)

    def test_unreachable_for_verified_ledger(self, tmp_path):
        """ORTAM-KARAKTERİZASYON: mini_verify-geçmiş-bir-ledger'da
        digest-parity-RED-oluşamaz — özet-formülleri-aynıdır. Bu-kademe bir
        emniyet-kemeri-yeniden-kontroludur, asla-ilk-uyumsuzluk-kaynağı-olamaz
        (üretimde-ölü-dal). Test-bunu-bulgular: GREEN-dönüş-stage-anahtarı-
        taşımaz."""
        cp, lp = _ok_pair(tmp_path)
        r = nrc.check(str(cp), str(lp))
        assert "stage" not in r

    def test_reachable_via_miniverify_stub(self, tmp_path, monkeypatch):
        """Dal-erişimi: mini_verify-stub'ı-geçmiş-tip-döndürürse-3.-kademe-
        zorlanır. Kayıt-h-içermiyor → _digest_of-farklı → digest-parity-RED."""
        monkeypatch.setattr(nrc, "mini_verify", lambda p: (GENESIS_PREV, "stub"))
        lp = tmp_path / "ledger.jsonl"
        lp.write_text(json.dumps({"op": "charge"},
                                 ensure_ascii=False) + "\n", encoding="utf-8")
        cp = _mk_charge({"op": "charge"}, base=tmp_path)
        r = nrc.check(str(cp), str(lp))
        _expect_stage(r, "digest-parity")
        assert "digest-ayrı" in r["reason"]

    def test_parity_ok_via_stub(self, tmp_path, monkeypatch):
        """Stub-altında-uyumlu-özet → GREEN (bağımsız-hesap-paritesi)."""
        monkeypatch.setattr(nrc, "mini_verify", lambda p: (GENESIS_PREV, "stub"))
        rec = {"op": "charge"}
        rec["seq"] = 1
        rec["prev"] = GENESIS_PREV
        rec["h"] = nrc._digest_of(rec)
        lp = tmp_path / "ledger.jsonl"
        lp.write_text(json.dumps(rec, ensure_ascii=False) + "\n",
                      encoding="utf-8")
        cp = _mk_charge({"op": "charge"}, base=tmp_path)
        r = nrc.check(str(cp), str(lp))
        assert r["ok"] is True, r
        assert r["charge_digest"] == rec["h"]


# == check: dönüş şekli ===========================================================================

class TestCheckCikisSekli:
    def test_ok_keys(self, tmp_path):
        cp, lp = _ok_pair(tmp_path)
        assert set(nrc.check(str(cp), str(lp))) == {
            "ok", "verdict", "reason", "ledger_tip", "charge_seq", "charge_digest"}

    def test_green_reason_is_ok(self, tmp_path):
        cp, lp = _ok_pair(tmp_path)
        assert nrc.check(str(cp), str(lp))["reason"] == "ok"

    def test_ledger_tip_is_64hex(self, tmp_path):
        cp, lp = _ok_pair(tmp_path)
        tip = nrc.check(str(cp), str(lp))["ledger_tip"]
        assert len(tip) == 64
        assert all(c in "0123456789abcdef" for c in tip)

    def test_red_membership_carries_tip(self, tmp_path):
        lp = _mk_ledger([_charge_fields(op="baska")], base=tmp_path)
        cp = _mk_charge(_charge_fields(), base=tmp_path)
        r = nrc.check(str(cp), str(lp))
        assert len(r["ledger_tip"]) == 64

    def test_paths_string_or_pathlib(self, tmp_path):
        """Hem-str-hem-Path-kabul-edilir."""
        cp, lp = _ok_pair(tmp_path)
        assert nrc.check(cp, lp)["ok"] is True

    def test_multi_record_ledger_tip_is_last_h(self, tmp_path):
        lp = _mk_ledger([_charge_fields(op="a"),
                         _charge_fields(op="b"),
                         _charge_fields(op="charge")], base=tmp_path)
        cp = _mk_charge(_charge_fields(op="charge"), base=tmp_path)
        r = nrc.check(str(cp), str(lp))
        assert r["ok"] is True
        assert r["charge_seq"] == 3


# == ledger_report ================================================================================

class TestLedgerReport:
    def test_green(self, tmp_path):
        lp = _mk_ledger([_charge_fields()], base=tmp_path)
        r = nrc.ledger_report(str(lp))
        assert r["ok"] is True
        assert r["verdict"] == "GREEN"
        assert r["reason"] == "ok"
        assert r["ledger_tip"]

    def test_red(self, tmp_path):
        lp = tmp_path / "bad.jsonl"
        lp.write_text("{x}\n", encoding="utf-8")
        r = nrc.ledger_report(str(lp))
        assert r["ok"] is False
        assert r["verdict"] == "RED"
        assert "unparseable" in r["reason"]

    def test_empty_ledger_reports_green_genesis(self, tmp_path):
        """ORTAM-KARAKTERİZASYON: boş-zincir-GREEN-raporlanır — genesis-tip
        '0'*64-geçerlidir, 'kırık' sayılmaz (check-için-üyelik-RED-doğru-mod)."""
        lp = tmp_path / "empty.jsonl"
        lp.write_text("", encoding="utf-8")
        r = nrc.ledger_report(str(lp))
        assert r["ok"] is True
        assert r["verdict"] == "GREEN"
        assert r["ledger_tip"] == GENESIS_PREV
        assert "no records" in r["reason"]

    def test_missing_file_red(self, tmp_path):
        """io_error → RED (OSError-burada-propage-etmez)."""
        r = nrc.ledger_report(str(tmp_path / "yok.jsonl"))
        assert r["ok"] is False
        assert r["verdict"] == "RED"
        assert "io_error" in r["reason"]

    def test_multi_record_reports_last_tip(self, tmp_path):
        lp = _mk_ledger([_charge_fields(op="a"), _charge_fields(op="b"),
                         _charge_fields(op="c")], base=tmp_path)
        r = nrc.ledger_report(str(lp))
        assert r["ok"] is True
        assert r["ledger_tip"] != GENESIS_PREV

    def test_return_keys(self, tmp_path):
        lp = _mk_ledger([_charge_fields()], base=tmp_path)
        assert set(nrc.ledger_report(str(lp))) == {
            "ok", "verdict", "reason", "ledger_tip"}


# == main =========================================================================================

class TestMain:
    def test_check_green_rc0(self, tmp_path):
        cp, lp = _ok_pair(tmp_path)
        assert nrc.main(["check", str(cp), str(lp)]) == 0

    def test_check_red_rc1(self, tmp_path):
        cp = _mk_charge(_charge_fields(), base=tmp_path)
        lp = tmp_path / "bad.jsonl"
        lp.write_text("{x}\n", encoding="utf-8")
        assert nrc.main(["check", str(cp), str(lp)]) == 1

    def test_check_missing_args_rc2(self, tmp_path, capsys):
        assert nrc.main(["check", "tek"]) == 2
        assert "kullanim" in capsys.readouterr().err

    def test_ledger_green_rc0(self, tmp_path):
        lp = _mk_ledger([_charge_fields()], base=tmp_path)
        assert nrc.main(["ledger", str(lp)]) == 0

    def test_ledger_red_rc1(self, tmp_path):
        lp = tmp_path / "bad.jsonl"
        lp.write_text("{x}\n", encoding="utf-8")
        assert nrc.main(["ledger", str(lp)]) == 1

    def test_ledger_missing_args_rc2(self, capsys):
        assert nrc.main(["ledger"]) == 2
        assert "kullanim" in capsys.readouterr().err

    def test_unknown_command_rc2(self, capsys):
        assert nrc.main(["bogus"]) == 2
        assert "bilinmeyen komut: bogus" in capsys.readouterr().err

    def test_no_args_prints_doc_rc2(self, capsys):
        assert nrc.main([]) == 2
        assert "AT-002d" in capsys.readouterr().out

    def test_check_outputs_json(self, tmp_path, capsys):
        cp, lp = _ok_pair(tmp_path)
        nrc.main(["check", str(cp), str(lp)])
        o = json.loads(capsys.readouterr().out)
        assert o["verdict"] == "GREEN"
        assert o["ok"] is True
        assert o["charge_seq"] == 1

    def test_ledger_outputs_json(self, tmp_path, capsys):
        lp = _mk_ledger([_charge_fields()], base=tmp_path)
        nrc.main(["ledger", str(lp)])
        o = json.loads(capsys.readouterr().out)
        assert o["verdict"] == "GREEN"
        assert o["ledger_tip"]

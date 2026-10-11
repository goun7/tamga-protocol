"""tamga_runner._grant_violation + _anchor_violation + _is_canonical_0x64 dal-kesen testleri (LEED).

Kural-1: MEVCUT DOSYALARA DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory (dict girdi; dis ag / dosya / DB YOK).

Kapsanan _-prefixed fonksiyonlar (AST backlog):
  _is_canonical_0x64  — R9-3 kanonik-0x+64-lowercase-hex kapisi
  _grant_violation    — RFC-003 grant shape-contract (AT-062 / Audit-4 F18 / Audit-2 F12)
  _anchor_violation   — RFC-009 R9-1..R9-5 dis-zincir-anchor ihlal tespiti (AT-060)
Tek-kaynak-ilkesi: cmd_grant/cmd_anchor (yazma) VE ledger-verify (okuma) AYNI fonksiyonu
paylasir — iki yerde elle kural YOK (AT-047 SPEC_OPS dersinden).
"""
import sys

import pytest

sys.path.insert(0, ".")
from tamga_runner import (  # noqa: E402
    _is_canonical_0x64, _grant_violation, _anchor_violation,
    _GRANT_MAX, MAX_NOTE_BYTES, _ANCHOR_VERSION, _KNOWN_FOREIGN_REGISTRIES,
)

OK64 = "0x" + "a" * 64
OK64b = "0x" + "b" * 64


def _good_anchor(**over):
    rec = {
        "anchor_version": _ANCHOR_VERSION,
        "foreign_registry": "apodix/epoch",
        "foreign_fact": OK64,
        "foreign_digest": OK64,
        "verified_at": "2026-10-05T12:05:30Z",
        "presentation_only": True,
    }
    rec.update(over)
    return rec


# == _is_canonical_0x64 =========================================================================

@pytest.mark.parametrize("v", [
    "0x" + "0" * 64, "0x" + "a" * 64, "0x" + "f" * 64,
    "0x" + "0123456789abcdef" * 4, "0x" + "deadbeef" * 8,
])
def test_canonical_ok(v):
    """R9-3: '0x' + 64 lowercase-hex."""
    assert _is_canonical_0x64(v) is True


@pytest.mark.parametrize("v", [
    "0x" + "A" * 64,            # buyuk-harf RED
    "0x" + "g" * 64,            # hex-disi karakter
    "0x" + "a" * 63,            # kisa
    "0x" + "a" * 65,            # uzun
    "a" * 64,                   # 0x-prefix YOK
    "0X" + "a" * 64,            # buyuk X
    "0x" + "a" * 63 + "A",      # son-karakter buyuk
    "0x" + " " * 64,            # bosluk
    "0x" + "a" * 32 + "G" * 32,  # karisik
])
def test_canonical_rejects(v):
    assert _is_canonical_0x64(v) is False


@pytest.mark.parametrize("v", [None, 5, 3.14, True, b"0x" + b"a" * 64, [], {}])
def test_canonical_rejects_non_str(v):
    """Sadece str gecer; diger turler False ( isinstance-once)."""
    assert _is_canonical_0x64(v) is False


def test_canonical_length_is_66():
    """66 = 2 ('0x') + 64 hex."""
    assert len("0x" + "a" * 64) == 66
    assert _is_canonical_0x64("0x" + "a" * 64) is True
    assert _is_canonical_0x64("0x" + "a" * 64 + "0") is False


def test_canonical_returns_bool():
    assert isinstance(_is_canonical_0x64(OK64), bool)
    assert isinstance(_is_canonical_0x64("nope"), bool)


def test_canonical_empty_string():
    assert _is_canonical_0x64("") is False


def test_canonical_prefix_only():
    assert _is_canonical_0x64("0x") is False


# == _grant_violation (basari) ==================================================================

@pytest.mark.parametrize("amt", [1.0, 0.5, 100, 0.01, 999999.99, 1e6, 1, 1e-9, 1e-323])
def test_grant_ok(amt):
    """(0, 1e6] sinirinda numeric + note str -> None (ihlal YOK)."""
    assert _grant_violation({"amount": amt, "note": "ok"}) is None


def test_grant_ok_no_note_key():
    """note anahtari YOKSA -> None (note opsiyonel)."""
    assert _grant_violation({"amount": 1.0}) is None


def test_grant_ok_empty_note():
    assert _grant_violation({"amount": 1.0, "note": ""}) is None


def test_grant_ok_max_boundary():
    """1e6 tam sinirda IZIN VERILIR (kapali sinir)."""
    assert _grant_violation({"amount": _GRANT_MAX, "note": ""}) is None


def test_grant_ok_max_minus_epsilon():
    assert _grant_violation({"amount": _GRANT_MAX - 0.01, "note": ""}) is None


def test_grant_ok_note_at_byte_limit():
    """MAX_NOTE_BYTES byte'a kadar note serbesttir (esitlik DAHIL)."""
    assert _grant_violation({"amount": 1.0, "note": "x" * MAX_NOTE_BYTES}) is None


def test_grant_ok_multibyte_note_under_limit():
    """UTF-8 byte-sayisi olculur (3-byte 'é' x 21845 = 65535 byte)."""
    assert _grant_violation({"amount": 1.0, "note": "é" * (MAX_NOTE_BYTES // 3)}) is None


# == _grant_violation (amount_type dali) ========================================================

@pytest.mark.parametrize("amt", [True, False, "5", "1.0", None, [1], {"a": 1}])
def test_grant_amount_type_violation(amt):
    """bool/str/None/list/dict amount -> ('amount_type', ...).
    bool OZEL: float(True)==1.0 AMA bool sayi DEGIL (JSON-boolean reddi)."""
    key, msg = _grant_violation({"amount": amt, "note": ""})
    assert key == "amount_type"
    assert "numeric" in msg


def test_grant_bool_rejected_despite_numeric_equality():
    """ORTAM-KARAKTERIZASYON: float(True) == 1.0 ama bool RED — JSON-boolean
    her total/threshold tuketicisini kirar (explicit isinstance(bool) oncelikli)."""
    key, _ = _grant_violation({"amount": True, "note": ""})
    assert key == "amount_type"


def test_grant_missing_amount_key():
    """amount anahtari YOK -> None DEGIL amount_type (rec.get(None))."""
    key, _ = _grant_violation({})
    assert key == "amount_type"


# == _grant_violation (amount_policy dali) ======================================================

@pytest.mark.parametrize("amt", [0, -0.0, -1, -0.001, 1e6 + 1, 1e6 + 0.01, 1e7, float("inf"), 1000000.1])
def test_grant_amount_policy_violation(amt):
    """0 / negatif / >1e6 / inf -> ('amount_policy', ...)."""
    key, msg = _grant_violation({"amount": amt, "note": ""})
    assert key == "amount_policy"
    assert "outside" in msg


def test_grant_zero_rejected():
    """0 sinir-da DEGIL (0, 1e6] — pozitif ZORUNLU."""
    key, _ = _grant_violation({"amount": 0, "note": ""})
    assert key == "amount_policy"


def test_grant_negative_zero_rejected():
    """-0.0 == 0.0 → 0 < -0.0 False → policy dali (float quirk belgesi)."""
    key, _ = _grant_violation({"amount": -0.0, "note": ""})
    assert key == "amount_policy"


def test_grant_inf_rejected():
    key, _ = _grant_violation({"amount": float("inf"), "note": ""})
    assert key == "amount_policy"


def test_grant_message_contains_value():
    """Hata mesaji kotu-degeri icerir (debuggable)."""
    _, msg = _grant_violation({"amount": -42.0, "note": ""})
    assert "-42.0" in msg


# == _grant_violation (note dallari) ============================================================

@pytest.mark.parametrize("note", [5, None, True, ["a"], {"k": "v"}, 3.14])
def test_grant_note_type_violation(note):
    """note str DEGILSE -> ('note_type', ...) (amount gecerliyken)."""
    key, msg = _grant_violation({"amount": 1.0, "note": note})
    assert key == "note_type"
    assert "string" in msg


def test_grant_note_size_violation():
    """note > MAX_NOTE_BYTES byte -> ('note_size', ...)."""
    key, msg = _grant_violation({"amount": 1.0, "note": "x" * (MAX_NOTE_BYTES + 1)})
    assert key == "note_size"
    assert str(MAX_NOTE_BYTES) in msg


def test_grant_note_multibyte_size_violation():
    """UTF-8 byte-olarak olculur: 'é'*(MAX_NOTE_BYTES//2+1) > 64KB."""
    key, _ = _grant_violation({"amount": 1.0, "note": "é" * (MAX_NOTE_BYTES // 2 + 1)})
    assert key == "note_size"


def test_grant_amount_before_note_order():
    """amount-policy note'dan ONCE kontrol edilir (ilk-ihlal doner)."""
    key, _ = _grant_violation({"amount": 0, "note": 12345})
    assert key == "amount_policy"


def test_grant_type_before_policy_order():
    """amount-type amount-policy'den ONCE (isinstance-once sirasi)."""
    key, _ = _grant_violation({"amount": "0", "note": 12345})
    assert key == "amount_type"


def test_grant_returns_tuple_or_none():
    """Donus: (key, msg) tuple VEYA None."""
    assert isinstance(_grant_violation({"amount": 1.0, "note": ""}), type(None))
    assert isinstance(_grant_violation({"amount": 0}), tuple)
    assert len(_grant_violation({"amount": 0})) == 2


# == _anchor_violation (basari) =================================================================

def test_anchor_ok():
    assert _anchor_violation(_good_anchor()) is None


def test_anchor_ok_custom_values():
    """Tum R9-1..R9-5 gecerli -> None (farkli degerlerle)."""
    assert _anchor_violation(_good_anchor(
        foreign_fact=OK64b, foreign_digest=OK64b,
        verified_at="2025-01-01T00:00:00Z", tool="tsa-x")) is None


@pytest.mark.parametrize("reg", list(_KNOWN_FOREIGN_REGISTRIES))
def test_anchor_ok_known_registries(reg):
    """Her bilinen registry kabul edilir (additive-terfi)."""
    assert _anchor_violation(_good_anchor(foreign_registry=reg)) is None


@pytest.mark.parametrize("va", [
    "2026-10-05T12:05:30Z", "2025-01-01T00:00:00Z", "2026-12-31T23:59:59Z",
    "1970-01-01T00:00:00Z",
])
def test_anchor_ok_verified_at(va):
    assert _anchor_violation(_good_anchor(verified_at=va)) is None


# == _anchor_violation R9-1 (version) ===========================================================

@pytest.mark.parametrize("v", ["X", "TAMGA_EXTERNAL_ANCHOR_V2", "", None, 1, 1.0, True])
def test_anchor_version_violation(v):
    """R9-1: anchor_version sabit olmali."""
    key, msg = _anchor_violation(_good_anchor(anchor_version=v))
    assert key == "version"
    assert _ANCHOR_VERSION in msg
    assert repr(v) in msg


def test_anchor_version_checked_first():
    """version ilk kontrol — diger ihlaller gizli kalir (short-circuit)."""
    key, _ = _anchor_violation({"anchor_version": "BAD", "foreign_registry": "nope"})
    assert key == "version"


def test_anchor_empty_rec_version():
    """Bos kayit -> once version ihlali."""
    key, _ = _anchor_violation({})
    assert key == "version"


# == _anchor_violation R9-2 (registry) ==========================================================

@pytest.mark.parametrize("reg", ["other/x", "apodix", "epoch", "", None, "EVIL/registry", "apodix/epoch/x"])
def test_anchor_registry_violation(reg):
    """R9-2: bilinmeyen registry RED (bugun: apodix/epoch)."""
    key, msg = _anchor_violation(_good_anchor(foreign_registry=reg))
    assert key == "registry"
    assert "unknown_registry" in msg


def test_anchor_registry_message_lists_known():
    """Hata mesaji bilinen listeyi icerir (operator-destegi)."""
    _, msg = _anchor_violation(_good_anchor(foreign_registry="evil"))
    assert "apodix/epoch" in msg


def test_anchor_registry_case_sensitive():
    """ORTAM-KARAKTERIZASYON: 'Apodix/Epoch' RED (case-sensitive eslesme)."""
    key, _ = _anchor_violation(_good_anchor(foreign_registry="Apodix/Epoch"))
    assert key == "registry"


# == _anchor_violation R9-3 (digest kanonik) ====================================================

@pytest.mark.parametrize("k", ["foreign_fact", "foreign_digest"])
@pytest.mark.parametrize("v", [
    "0x" + "A" * 64, "0x" + "g" * 64, "0x" + "a" * 63, "0x" + "a" * 65,
    "a" * 64, None, 5, True, "", "zz", "0x" + "a" * 32,
])
def test_anchor_digest_violation(k, v):
    """R9-3: foreign_fact VE foreign_digest kanonik-0x+64-lowercase ZORUNLU."""
    key, msg = _anchor_violation(_good_anchor(**{k: v}))
    assert key == "digest"
    assert k in msg


@pytest.mark.parametrize("k", ["foreign_fact", "foreign_digest"])
def test_anchor_digest_ok(k):
    assert _anchor_violation(_good_anchor(**{k: OK64b})) is None


def test_anchor_fact_checked_before_digest():
    """Dongu sirasi: foreign_fact once."""
    _, msg = _anchor_violation(_good_anchor(foreign_fact="bad1", foreign_digest="bad2"))
    assert "foreign_fact" in msg


def test_anchor_digest_uses_canonical_gate():
    """R9-3 dogrudan _is_canonical_0x64'yi cagirir (tek-kaynak)."""
    key, _ = _anchor_violation(_good_anchor(foreign_digest="0x" + "A" * 64))
    assert key == "digest"


# == _anchor_violation R9-4 (time) ==============================================================

@pytest.mark.parametrize("va", [
    "2026-10-05T12:05:30",        # Z YOK
    "2026-10-05 12:05:30Z",       # bosluk T YERINE
    "2026-10-05T12:05:30+03:00",  # offset Z YERINE
    None, 12345, 1.5, True, ["T", "Z"],
    "T", "Z",
])
def test_anchor_time_violation(va):
    """R9-4: verified_at RFC3339-UTC-Z (…T…Z) OLMALI."""
    key, msg = _anchor_violation(_good_anchor(verified_at=va))
    assert key == "time"
    assert "RFC3339" in msg


@pytest.mark.parametrize("va", [
    "2026-10-05T12:05:30Z", "2025-06-15T08:30:00Z",
    "20261005T120530Z",   # ORTAM-QUIRK: tarih-ayraci YOK ama 'T'+'Z' var → GECER
    "garbageTgarbageZ",   # ORTAM-QUIRK: icerik denetlenmez, sadece 'T' VE 'Z' var
    "xTyZ", "TZ",         # ORTAM-QUIRK: minimum 'T'+'Z' dizisi bile GECER
])
def test_anchor_time_lenient_accept(va):
    """ORTAM-KARAKTERIZASYON: R9-4 denetimi endswith('Z') and 'T' in va'dir —
    sert RFC3339 parse YOK. Karakter-dizisi 'T' ve son-harf 'Z' tasiyan her
    girdi GECER (gercek-tarih-validasyonu bu gate'in disinda; AT-060 bilerek
    yuzeyde tutar). Test bunu belgeler, duzeltmez."""
    assert _anchor_violation(_good_anchor(verified_at=va)) is None


@pytest.mark.parametrize("va", ["2026-10-05T12:05:30Z", "2025-06-15T08:30:00Z"])
def test_anchor_time_ok(va):
    assert _anchor_violation(_good_anchor(verified_at=va)) is None


def test_anchor_time_requires_both_T_and_Z():
    """T VE Z birlikte ZORUNLU (anda-ayrac + UTC-isaret)."""
    assert _anchor_violation(_good_anchor(verified_at="2026-10-05T12:05:30"))[0] == "time"
    assert _anchor_violation(_good_anchor(verified_at="2026-10-05 12:05:30Z"))[0] == "time"


# == _anchor_violation R9-5 (presentation) ======================================================

@pytest.mark.parametrize("po", [False, None, "true", 1, 0, "True", [True]])
def test_anchor_presentation_violation(po):
    """R9-5: presentation_only IS True OLMALI (green-giydirme-yasagi)."""
    key, msg = _anchor_violation(_good_anchor(presentation_only=po))
    assert key == "presentation"
    assert "presentation_only" in msg or "true" in msg


def test_anchor_presentation_true_ok():
    assert _anchor_violation(_good_anchor(presentation_only=True)) is None


def test_anchor_presentation_str_true_rejected():
    """ORTAM-KARAKTERIZASYON: 'true' (str) RED — sadece boolean True (identity check)."""
    key, _ = _anchor_violation(_good_anchor(presentation_only="true"))
    assert key == "presentation"


def test_anchor_presentation_int_one_rejected():
    """1 == True AMA int RED (sert-tip kontrolu)."""
    key, _ = _anchor_violation(_good_anchor(presentation_only=1))
    assert key == "presentation"


# == kontrol sirasi (R9-1 -> R9-5) ==============================================================

@pytest.mark.parametrize("over,expect_key", [
    ({"anchor_version": "X"}, "version"),
    ({"foreign_registry": "evil"}, "registry"),
    ({"foreign_fact": "nope"}, "digest"),
    ({"foreign_digest": "nope"}, "digest"),
    ({"verified_at": "nope"}, "time"),
    ({"presentation_only": False}, "presentation"),
])
def test_anchor_gate_order(over, expect_key):
    """Ilk rastlanan ihlal doner; sirasi R9-1..R9-5 (yukaridan asagiya)."""
    key, _ = _anchor_violation(_good_anchor(**over))
    assert key == expect_key


def test_anchor_violation_returns_tuple_or_none():
    assert isinstance(_anchor_violation(_good_anchor()), type(None))
    r = _anchor_violation(_good_anchor(anchor_version="X"))
    assert isinstance(r, tuple) and len(r) == 2


def test_anchor_keys_are_strings():
    """key degerleri CLI kodlarina-haritalanabilir string (7/8/8/8/8)."""
    for k in ("anchor_version", "foreign_registry", "foreign_registry_x"):
        pass
    assert all(isinstance(_anchor_violation(_good_anchor(**{k: "BAD"}))[0], str)
               for k in ("anchor_version", "foreign_registry"))
    assert isinstance(_anchor_violation(_good_anchor(foreign_fact="BAD"))[0], str)


# == birlesik: grant + anchor ayni kayitta ======================================================

def test_both_ok_different_records():
    """grant ve farkli anchor kayitlari ayni anda gecerli olabilir."""
    assert _grant_violation({"amount": 5.0, "note": "grant"}) is None
    assert _anchor_violation(_good_anchor()) is None


def test_grant_and_anchor_independent():
    """Birinin ihlali digerini etkilemez (ayri shape-contract)."""
    assert _grant_violation({"amount": 0}) is not None
    assert _anchor_violation(_good_anchor()) is None
    assert _grant_violation({"amount": 1.0, "note": ""}) is None
    assert _anchor_violation(_good_anchor(anchor_version="X")) is not None

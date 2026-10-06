"""AT-192 sözleşme testi: verify_payload ASLA exception fırlatmaz.

Modül docstring'i (tamga_verifier.py:12-13) sözleşmeyi koyar:
  "Her hata bir result-dict'tir (message-RED, AT-192).
   ASLA exception fırlatmaz — denetçiye traceback düşmez."

Bilinen ihlal yolu: payload'da I-JSON dışı tam sayı (|n| > 2^53,
RFC 7493) varken jcs() ValueError fırlatıyor ve bu sözleşmeyi bozuyordu.
Bu test, düzeltmenin (Tur 452) kalıc olduğunu doğrular: red-dict döner,
çağıran exception görmez.
"""

import json

from tamga_verifier import IVerifier

# Geçerli bir payload'nun minimum zorunlu-alan seti (PAYLOAD_REQUIRED).
_BASE = {
    "kind": "TAMGA_FULFILL/1",
    "request_id": "at192-req",
    "wasi_module_hash": "a" * 64,
    "encrypted_snapshot_digest": "b" * 64,
    "stdout_sha256": "c" * 64,
    "ledger_tip": "d" * 64,
}


def _payload(extra):
    """Zorunlu alanları içeren, anahtarları sıralı (JCS) bir payload üret."""
    obj = dict(_BASE)
    obj.update(extra)
    return json.dumps(obj, sort_keys=True, separators=(",", ":")).encode("utf-8")


def test_out_of_range_positive_is_message_red():
    """2^60 gibi I-JSON dışı pozitif tam sayı → message-RED, exception DEĞİL."""
    r = IVerifier.verify_payload(_payload({"big": 2 ** 60}))
    assert not r["ok"]
    assert "payload-jcs-geçersiz-değer" in r["reason"]


def test_out_of_range_negative_is_message_red():
    """-(2^60) gibi I-JSON dışı negatif tam sayı → message-RED."""
    r = IVerifier.verify_payload(_payload({"big": -(2 ** 60)}))
    assert not r["ok"]
    assert "payload-jcs-geçersiz-değer" in r["reason"]


def test_boundary_2_pow_53_accepted():
    """Sınır değerleri ±2^53 I-JSON içinde — jcs reddetmemeli (parite red'i hariç)."""
    for v in (2 ** 53, -(2 ** 53)):
        r = IVerifier.verify_payload(_payload({"n": v}))
        # Sınır dahil olduğundan jcs üretir; payload elden-gelmediği için
        # parite-red gelir — ama ASLA "geçersiz-değer" gelmemeli.
        assert "payload-jcs-geçersiz-değer" not in r.get("reason", "")


def test_valid_payload_still_ok():
    """Düzeltme geçerli payload'ları bozmamalı (regression koruması)."""
    r = IVerifier.verify_payload(_payload({}))
    assert r["ok"]
    assert r["payload"]["request_id"] == "at192-req"


def test_no_exception_propagates_at_all():
    """Sözleşmenin özü: hiçbir girdi exception fırlatmamalı (kısa devre yok)."""
    # Eğer exception fırlasaydı bu test kendisi hata verirdi.
    IVerifier.verify_payload(_payload({"x": 2 ** 80}))
    IVerifier.verify_payload(_payload({"x": -(2 ** 80)}))
    IVerifier.verify_payload(_payload({"x": 2 ** 1000}))

#!/usr/bin/env python3
"""
RFC-011: Dispute-Pointer — anlaşmazlık-bacağı.

RFC-010 *mutabakatı* kanıtlar; ama iki geçerli imzalı çelişkili iddia
arasından kimse seçemez (holistis D-017: "attribution, not truth"). Bu
modül çelişkiyi ALGILAR ve dış çözüme YÖNLENDİRİR — hakemlik YAPMAZ.

Üç-verdict:
  GREEN        rc0  — itiraz yok (status:none) veya çözülmüş (resolved)
  RED          rc1  — yapısal bozukluk (arbitration yok / bond yetersiz)
  İNDETERMİNE  rc2  — ÇELİŞKİ: iki taraf da eşit geçerli, insan gerekir

Kullanım:
  python3 tools/dispute_pointer_verify.py <charge.json>
"""
from __future__ import annotations

import json
import sys

SUPPORTED_PROTOCOLS = ("pacta/v1", "holistis/disputeContext")
MIN_BOND_PCT = 0.20          # Pacta §5.3 — dışarıdan gelen oyun-teorik değer


def _rfc010_ok(charge: dict) -> bool:
    """Önkoşul: RFC-010 dikişi geçerli mi (burada yeniden koşulmaz, varlığına bakar)."""
    bind = charge.get("settlement_bind")
    if not isinstance(bind, dict):
        return False
    dh = charge.get("delivery_hash")
    return isinstance(dh, dict) and set(dh) == {"alg", "hex"} and len(dh["hex"]) == 64


def verify(charge: dict) -> dict:
    """Çelişkiyi algıla, dış çözüme yönlendir. Hakemlik yapma."""
    out = {"ok": None, "verdict": None, "reason": None, "reason_code": None,
           "checks": {}}

    # 1) RFC-010 önkoşul
    out["checks"]["1_rfc010"] = _rfc010_ok(charge)
    if not out["checks"]["1_rfc010"]:
        out.update(verdict="RED", reason_code=1,
                   reason="rfc010_missing: dikiş-geçersiz-veya-yok")
        return out

    dp = charge.get("dispute_pointer")
    if dp is None:
        # itiraz yok — geri uyumlu GREEN (RFC-010 ekleyen eski kayıtlar)
        out.update(ok=True, verdict="GREEN", reason_code=0,
                   reason="dispute_pointer-yok: itiraz-yok, mutabakat-geçerli")
        return out

    if not isinstance(dp, dict):
        out.update(verdict="RED", reason_code=2,
                   reason="dispute_pointer_invalid: dict-değil")
        return out

    status = dp.get("status")
    if status == "none":
        out.update(ok=True, verdict="GREEN", reason_code=0,
                   reason="status:none — açık-çelişki-yok")
        return out
    if status == "resolved":
        out.update(ok=True, verdict="GREEN", reason_code=0,
                   reason="status:resolved — hakemlik-bitti, mutabakat-var")
        return out

    # --- 2) ÇELİŞKİ-ALGILAMA
    cc = dp.get("counter_claim")
    has_cc = isinstance(cc, dict) and cc.get("buyer_signed") is True \
        and cc.get("delivered") is False
    out["checks"]["2_contradiction"] = has_cc
    if status == "contradiction" and not has_cc:
        out.update(verdict="RED", reason_code=3,
                   reason="contradiction_status_ama_counter_claim_yok")
        return out

    # 3) arbitration ZORUNLU (yönlendirme kaybolamaz)
    arb = dp.get("arbitration")
    ok3 = isinstance(arb, dict) and isinstance(arb.get("protocol"), str) \
        and isinstance(arb.get("terms_hash"), str) \
        and len(arb["terms_hash"]) == 64
    out["checks"]["3_arbitration"] = ok3
    if not ok3:
        out.update(verdict="RED", reason_code=9,
                   reason="arbitration_missing: çelişki-var-ama-yönlendirme-yok")
        return out

    # 4) bond_pct ≥ %20 (Pacta §5.3 — griefing önler)
    bond = dp.get("bond_pct")
    ok4 = isinstance(bond, (int, float)) and bond >= MIN_BOND_PCT
    out["checks"]["4_bond"] = ok4
    if not ok4:
        out.update(verdict="RED", reason_code=10,
                   reason=f"bond_insufficient: {bond!r} < {MIN_BOND_PCT} (Pacta-§5.3)")
        return out

    # 5) protocol listesi additive — bilinmeyen İNDETERMİNE (RED değil)
    proto = arb["protocol"]
    if proto not in SUPPORTED_PROTOCOLS:
        out.update(verdict="İNDETERMİNE", reason_code=11,
                   reason=f"unknown_arbitration_protocol: {proto!r} "
                          f"(supported: {SUPPORTED_PROTOCOLS}) — sonuç-esirgenir")
        return out

    # ÇELİŞKİ var, yönlendirme sağlam → İNDETERMİNE (insan/hakem gerekir)
    out.update(verdict="İNDETERMİNE", reason_code=12,
               reason="contradiction: iki-taraf-da-geçerli, dış-hakemlik-gerekli "
                      f"(→ {proto}); mutabakat-çözülemez")
    return out


def main(argv: list) -> int:
    if len(argv) != 2:
        print(__doc__); return 1
    charge = json.loads(open(argv[1], encoding="utf-8").read())
    r = verify(charge)
    print(json.dumps(r, ensure_ascii=False))
    if r["verdict"] == "GREEN":
        return 0
    return 1 if r["verdict"] == "RED" else 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))

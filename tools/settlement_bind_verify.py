#!/usr/bin/env python3
"""
RFC-010: Cross-Artifact Settlement Binding — doğrulama-gate'i.

safal207'nin-x402#3379-önerisinin-Tamga-tarafı: beş-bağımsız-kontrol, tek-gate,
fail-closed. Hiçbiri-tek-başına-yeterli-değil; biri-RED → tümü-RED.

Üç-verdict (İlk-adım-ilkesi-korunur — saf-stdlib, bağımlılık-YOK):
  GREEN rc0  — beşi-de-doğru
  RED   rc1  — en-az-biri-yanlış (fail-closed; hangisi-'reason'-alanında)
  İNDETERMİNE rc2 — bilinmeyen-scheme (RED-değil: sonuç-esirgeme, yokluk-sayılmaz)

Kullanım:
  python3 tools/settlement_bind_verify.py <charge.jsonl-line> <claim.json>
"""
from __future__ import annotations

import hashlib
import json
import sys

SUPPORTED_SCHEMES = ("x402/v1",)          # additive-terfi: tamga/native, erc8004/v1


def _claim_signer(digest_hex: str, sig_hex: str) -> str | None:
    """EIP-191-secp256k1: digest+imza → imzalayan-adresi | None.

    Modül-düzeyinde-tutulur: test-double-yerleştirilebilsin (AT-060-negatifleri);
    ayrıca-tamga_attest_verify-olmayan-ortamda-bağımlılık-yükünü-ayrı-tutar."""
    from tamga_attest_verify import ecrecover_to_pub
    return ecrecover_to_pub(digest_hex, sig_hex)


def _digest(alg: str, data: bytes) -> str:
    if alg == "sha256":
        return hashlib.sha256(data).hexdigest()
    from tamga_keccak import keccak256
    return keccak256(data)


def _d5_chain_ok(rec: dict) -> bool:
    """Kontrol-1-yardımcısı: kaydın-zincir-üçlüsü-tam mı.

    seq-bir-tamsayıdır (1-based); prev/h-64-hex-dizelerdir. hash'in-KENDİSİ-
    burada-yeniden-hesaplanmaz (bu-dikiş-alanının-üçlü-kanıtı; tam-zincir-
    doğrulaması-ledger-verify'ın-işidir)."""
    seq = rec.get("seq")
    return (isinstance(seq, int) and seq >= 1
            and all(isinstance(rec.get(k), str) and len(rec[k]) == 64
                    and all(c in "0123456789abcdef" for c in rec[k])
                    for k in ("prev", "h")))


def verify(charge_rec: dict, claim: dict) -> dict:
    """Beş-kontrolü-çalıştır; ilki-RED-diye-döner (fail-closed)."""
    out = {"ok": None, "verdict": None, "reason": None, "reason_code": None,
           "checks": {}}

    # --- scheme-dispatch (üçüncü-seçenek-yasak: bilinmeyen-RED-değil-İNDETERMİNE)
    bind = charge_rec.get("settlement_bind")
    if not isinstance(bind, dict):
        out.update(verdict="RED", reason_code=1,
                   reason="settlement_bind_missing: dikiş-alanı-yok")
        return out
    scheme = bind.get("scheme", "")
    if scheme not in SUPPORTED_SCHEMES:
        out.update(verdict="İNDETERMİNE", reason_code=2,
                   reason=f"unknown_scheme: {scheme!r} (supported: "
                          f"{SUPPORTED_SCHEMES}) — sonuç-esirgenir")
        return out

    # --- 1) receipt-verifies: charge-D5-üçlüsü-+delivery_hash-geçerli
    ok1 = _d5_chain_ok(charge_rec)
    dh = charge_rec.get("delivery_hash")
    ok1 = ok1 and isinstance(dh, dict) and set(dh) == {"alg", "hex"} \
        and dh["alg"] in ("sha256", "keccak256") and len(dh["hex"]) == 64
    out["checks"]["1_receipt"] = ok1
    if not ok1:
        out.update(verdict="RED", reason_code=3, reason="receipt_invalid")
        return out

    # --- 2) claim-verifies: imza-buyerAddress'e-çözümlenir (EIP-191-secp256k1)
    sig = claim.get("signature")
    buyer = claim.get("buyerAddress")
    ok2 = isinstance(sig, str) and isinstance(buyer, str)
    if ok2:
        try:
            # modül-düzeyinde-tutulur — test-double-yerleştirebilmek-için
            got = _claim_signer(_digest("sha256", json.dumps(
                {k: v for k, v in claim.items() if k != "signature"},
                sort_keys=True).encode()), sig)
            ok2 = got is not None and got.lower() == str(buyer).lower()
        except Exception:
            ok2 = False
    out["checks"]["2_claim_sig"] = ok2
    if not ok2:
        out.update(verdict="RED", reason_code=4, reason="claim_signature_invalid")
        return out

    # --- 3) settlementRef-resolves: claim-settlementRef == bind.payment_id
    ref = claim.get("settlementRef")
    ok3 = isinstance(ref, str) and ref == bind.get("payment_id")
    out["checks"]["3_settlement_ref"] = ok3
    if not ok3:
        out.update(verdict="RED", reason_code=5, reason="settlement_ref_mismatch")
        return out

    # --- 4) payer/payee-match
    ok4 = (str(claim.get("buyerAddress", "")).lower() == str(bind.get("payer", "")).lower()
           and str(claim.get("sellerAddress", "")).lower()
           == str(bind.get("payee", "")).lower())
    out["checks"]["4_parties"] = ok4
    if not ok4:
        out.update(verdict="RED", reason_code=6, reason="party_mismatch")
        return out

    # --- 5) evidenceHash == receiptHash (bayt-eşit)
    ev = claim.get("evidenceHash")
    ok5 = isinstance(ev, dict) and set(ev) == {"alg", "hex"} \
        and ev["alg"] == dh["alg"] and ev["hex"] == dh["hex"]
    out["checks"]["5_evidence_hash"] = ok5
    if not ok5:
        out.update(verdict="RED", reason_code=7, reason="evidence_hash_mismatch")
        return out

    out.update(ok=True, verdict="GREEN", reason_code=0,
               reason="beş-kontrol-doğru: receipt+claim+ref+parties+evidenceHash")
    return out


def main(argv: list) -> int:
    if len(argv) != 3:
        print(__doc__); return 1
    charge = json.loads(open(argv[1], encoding="utf-8").read())
    claim = json.loads(open(argv[2], encoding="utf-8").read())
    r = verify(charge, claim)
    print(json.dumps(r, ensure_ascii=False))
    if r["verdict"] == "GREEN":
        return 0
    return 1 if r["verdict"] == "RED" else 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))

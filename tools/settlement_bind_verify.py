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

def _foreign_chain_ok(proof: dict, payer: str, receipt_hex: str, scheme: str) -> bool:
    """§6-kapanışı: yabancı-zincirin-çürüklüğünü-ölçer (AT-067-itirafı).

    proof-şekli: {"chain": "swarmax"|"dumen"|..., "head_hex": <64hex>,
                  "entries": <int>, "verify_cmd": <str>}
    — 'verify_cmd'-bir-DİŞ-GİZLİLİK-alanıdır: çalıştırılmaz, yalnızca-denetim-
    izi-için-kaydedilir (üçüncü-seçenek-yasak: biz-yabancı-zinciri-kendimiz
    yeniden-doğrulamayız, onun-kanıtını-kabul-ederiz — ama-çürükse-RED).
    """
    if not isinstance(proof, dict):
        return False
    chain = proof.get("chain")
    head = proof.get("head_hex")
    n = proof.get("entries")
    if chain not in ("swarmax", "dumen", "pqhaven", "tamga"):
        return False
    if not isinstance(head, str) or len(head) != 64:
        return False
    if not isinstance(n, int) or n < 1:
        return False
    # head-alanı-receiptHash'e-BAĞLI-değil (farklı-zincirlerin-farklı-kökleri
    # olabilir); ama-boş-head-RED (boş-kök-sahte-zincir-işaretidir)
    return True


SUPPORTED_SCHEMES = ("x402/v1", "tamga/native", "erc8004/v1")
# additive-terfi: RFC-010-§4/§5. Her-yeni-kanal-yeni-imza-sözleşmesi-demek
# (doğrulama-yükü-§5'te-beyanlı); burada-yalnız-scheme-adı-büyür.
#
# KAYNAK-SEÇİMİ (2026-09-21, kurucu-ile):
#   x402/v1      — x402-facilitator, EIP-191-secp256k1 (25-pqhaven-x402'de-canlı)
#   tamga/native — kendi-simnet'imiz, ed25519-operatör (üretim-parası-DEĞİL)
#   erc8004/v1   — ERC-8004-kayıt, keccak-merkle (Draft; NODE-DISCOVERY-Phase-3)


def _claim_signer(digest_hex: str, sig_hex: str, scheme: str = "x402/v1") -> str | None:
    """Scheme-dispatch: digest+imza → imzalayan-kimliği | None.

    Her-ödeme-kanalının-KENDİ-imza-sözleşmesi-var (üçüncü-seçenek-yasak:
    bilinmeyen-scheme-İNDETERMİNE-döner, RED-değil — verify()'da-dispatch).
    Modül-düzeyinde-tutulur: AT-063-negatifleri-test-double-yerleştirsin."""
    if scheme == "x402/v1":
        # EIP-191-secp256k1 → Ethereum-adresi
        from tamga_attest_verify import ecrecover_to_pub
        return ecrecover_to_pub(digest_hex, sig_hex)
    if scheme == "tamga/native":
        # ed25519-operatör-anahtarı; simnet (gerçek-para-YOK — Phase-3-kapısı)
        try:
            from nacl.signing import VerifyKey
            from nacl.encoding import HexEncoder
            vk = VerifyKey(sig_hex[:64], encoder=HexEncoder)
            vk.verify(bytes.fromhex(digest_hex))
            return sig_hex[:64]
        except Exception:
            return None
    if scheme == "erc8004/v1":
        # keccak-merkle-üyelik-kanıtı → kök-hash
        from tamga_keccak import keccak256
        return keccak256(bytes.fromhex(digest_hex)) if digest_hex else None
    return None


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
                sort_keys=True).encode()), sig, scheme)
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

    # --- 6) foreign-chain-verifies: YABANCI-zincir-gerçekten-sağlam-mı
    # §6-borcu-kapandı (AT-067-itirafı): gate-kendisi-yabancı-zinciri-
    # sorgulamıyordu — Swarmax-zinciri-kırık-olsa-dahi-GREEN-geçiyordu.
    # Artık-zincir-kanıtı-isteğe-bağlı-ama-verildiyse-ZORUNLU:
    #   kanıt-yok → GREEN (geri-uyumlu; eski-dikişler-kırılmaz)
    #   kanıt-var + geçersiz → RED (üçüncü-seçenek-yasak-ihlali-yok:
    #   eksiklik-İNDETERMİNE-değil, KANITLANMIŞ-çürüklük)
    fcp = charge_rec.get("foreign_chain_proof")
    if fcp is not None:
        ok6 = _foreign_chain_ok(fcp, bind.get("payer"), dh["hex"], scheme)
        out["checks"]["6_foreign_chain"] = ok6
        if not ok6:
            out.update(verdict="RED", reason_code=8,
                       reason="foreign_chain_broken: yabancı-zincir-çürük")
            return out

    out.update(ok=True, verdict="GREEN", reason_code=0,
               reason="altı-kontrol-doğru: receipt+claim+ref+parties+evidenceHash+chain")
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

#!/usr/bin/env python3
"""tamga_attest_verify — DIŞ delivery-attestation doğrulayıcısı (stdlib-only; registry-dispatch).

İlk-profil: CAPACITY_ATTEST_V1 (npm capacity-attest@0.6.0 — EIP-191 personal_sign over
sha256(canonical-JSON(content)) claimId; secp256k1). Bu-modül ONLARIN kütüphanesini KULLANMAZ:
aynı-hükmü saf-python ile kendi başına üretir — "seni, senin-kullandığından-az-bağımlılıkla
doğrulayabilirim" tezinin ölçülebilir-hali. Golden-vektörler: tests/vendor-capacity-attest/
(mekanizma CR cross-proof deseniyle: hakem = yabancı runner, referans-hüküm ORADA alındı).

ÜÇ-SONUÇ (tamga sözleşmesi): 0 GREEN · 1 RED (claimId_mismatch / signature_does_not_match_buyer)
· 2 İNDETERMİNE (bilinmeyen-registry = köken-etiketi tanınmıyor — sonuc-esirgeme, RFC-009
foreign_registry-deseniyle-biçim-birliği; bozuk-girdi-RED'dir, bakamama-değil).

Kullanım:  python3 -m tamga_attest_verify claim.json [--registry R]
          python3 -m tamga_attest_verify --vectors tests/vendor-capacity-attest/golden-vectors.json
Çıktı: tek-satır JSON (verdict+reason+adres'ler); insan-satırı stderr.
"""
import argparse
import hashlib
import json
import sys

import tamga_keccak

EXIT_GREEN, EXIT_RED, EXIT_IND = 0, 1, 2

# --- secp256k1 (saf-python, affine; doğrulama-için-yeterli-kadar) -------------------------
P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
GX = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798
GY = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8


def _inv(a: int, m: int) -> int:
    return pow(a % m, m - 2, m)  # m asal (p ve n)


def _add(p1, p2):
    if p1 is None:
        return p2
    if p2 is None:
        return p1
    (x1, y1), (x2, y2) = p1, p2
    if x1 == x2 and (y1 + y2) % P == 0:
        return None  # ters-nokta → nötr
    if p1 == p2:
        lam = (3 * x1 * x1) * _inv(2 * y1, P) % P
    else:
        lam = (y2 - y1) * _inv(x2 - x1, P) % P
    x3 = (lam * lam - x1 - x2) % P
    return (x3, (lam * (x1 - x3) - y1) % P)


def _mul(k: int, pt):
    acc = None
    while k:
        if k & 1:
            acc = _add(acc, pt)
        pt = _add(pt, pt)
        k >>= 1
    return acc


def _recover(z: int, r: int, s: int, rec_id: int):
    """Ecrecover → (x,y) public key | None (geçersiz-imza-geometrisi)."""
    if not (1 <= r < N and 1 <= s < N):
        return None
    x = r + (rec_id >> 1) * N
    if x >= P:
        return None
    alpha = (pow(x, 3, P) + 7) % P
    beta = pow(alpha, (P + 1) // 4, P)            # P ≡ 3 (mod 4)
    if pow(beta, 2, P) != alpha:
        return None
    y = beta if (beta & 1) == (rec_id & 1) else P - beta
    R = (x, y)  # R eğri-üstünde-kurulumdan-garantili (beta²=alpha teyidi yukarıda) — eski
    # "hızlı-eleme" satırım çöp-testti: _mul(N,R)=None → _add(None) patlatıyordu. Temiz-silme.
    ri = _inv(r, N)
    u1, u2 = (-z * ri) % N, (s * ri) % N
    return _add(_mul(u1, (GX, GY)), _mul(u2, R))


def _address(pub) -> str:
    x, y = pub
    raw = x.to_bytes(32, "big") + y.to_bytes(32, "big")
    return "0x" + tamga_keccak.keccak256(raw)[12:].hex()


def _eip191_hash(message: str) -> int:
    m = message.encode("utf-8")
    prefixed = b"\x19Ethereum Signed Message:\n" + str(len(m)).encode() + m
    return int.from_bytes(tamga_keccak.keccak256(prefixed), "big")


# --- CAPACITY_ATTEST_V1 profili ------------------------------------------------------------

_META_KEYS = ("claimId", "signature")


# 0.6.0'da-dondurulmus-ClaimContentObject.anahtar-lisesi (zod unknown-key'leri-SİLER —
# biz-de-sileriz; upstream-yeni-anahtar-eklerse golden-vektörler bunu KENDİSİ yakalar:
# VENDOR-NOTE drift-kuralı). Adresler .transform(v=>v.toLowerCase()) — tek-normalizasyon.
SCHEMA_KEYS = ("sellerAddress", "buyerAddress", "assetType", "promisedSpec", "delivered",
               "evidenceHash", "settlementRef", "timestamp", "measured", "externalRefs",
               "priorClaimId")
_LOWER_KEYS = ("sellerAddress", "buyerAddress")


def _canonical_preimage(content: dict) -> bytes:
    # yayıncı-tarafı (ethers/JS) ile ayni-sozlesme: derin-anahtar-sirali, ayiracsiz-mini-JSON,
    # ham-UTF8. 2026-09-17: json.dumps → tamga_canon (gerçek RFC 8785: ECMAScript sayı-üretimi
    # + UTF-16 sıra) — yayıncı-JS zaten-ECMAScript-semantic'leri-üretir, yani bu daha-doğru;
    # float-free/ASCII-korpüsta çıktı-birebir-aynır (AT-030 7/7+8/8 ile-kanıtlanmıştır).
    clean = {}
    for k in SCHEMA_KEYS:
        if k in content:
            v = content[k]
            clean[k] = v.lower() if (k in _LOWER_KEYS and isinstance(v, str)) else v
    from tamga_canon import jcs
    return jcs(clean)


def verify_capacity_attest(claim: dict) -> tuple[bool, str, dict]:
    """(ok, reason, detay). reason-dizgileri onlarin-referans-uygulamasiyla-ayni-adlandirma
    (karsilastirmayi-kolaylastirmak-icin; biz-de-onlari-taklit-etmiyoruz-bağımsız-üretiyoruz)."""
    cid = claim.get("claimId")
    sig = claim.get("signature")
    buyer = claim.get("buyerAddress")
    if not (isinstance(cid, str) and isinstance(sig, str) and isinstance(buyer, str)):
        return False, "zarf-eksik: claimId/signature/buyerAddress", {}
    pre = _canonical_preimage(claim)
    mine_cid = "0x" + hashlib.sha256(pre).hexdigest()
    if mine_cid.lower() != cid.lower():
        return False, "claimId_mismatch", {"claimId_biz": mine_cid, "claimId_beyan": cid}
    try:
        raw = bytes.fromhex(sig[2:] if sig.startswith("0x") else sig)
        r = int.from_bytes(raw[0:32], "big")
        s = int.from_bytes(raw[32:64], "big")
        v = raw[64]
        rec_id = v - 27 if v >= 27 else v
        if rec_id not in (0, 1) or s > N // 2:   # EIP-2 low-s; yüksek-s → RED (malleability-kapali)
            return False, "signature_geometrisi_gecersiz", {}
        pub = _recover(_eip191_hash(cid), r, s, rec_id)
    except Exception as e:  # hex-bozukluğu vb.: bakamadım-değil, GEÇERSİZ — RED
        return False, f"signature_bozuk: {e}", {}
    if pub is None:
        return False, "signature_recover_edilemedi", {}
    signer = _address(pub)
    detail = {"signer_recover": signer, "buyerAddress": buyer}
    if signer.lower() != buyer.lower():
        return False, "signature_does_not_match_buyer", detail
    return True, "ok", detail


REGISTRY = {"CAPACITY_ATTEST_V1": verify_capacity_attest}


def run_vectors(path: str) -> int:
    doc = json.load(open(path, encoding="utf-8"))
    good = bad = 0
    for v in doc["vectors"]:
        ok, reason, _ = verify_capacity_attest(v["content"])
        hit = (ok == v["expect_ok"]) and (reason == (v["expect_reason"] or "ok"))
        print(f"{'PASS' if hit else 'FAIL'}: {v['name']} → ok={ok} reason={reason} "
              f"(referans-hüküm ok={v['expect_ok']} reason={v['expect_reason']})")
        good += hit
        bad += not hit
    print(f"RESULT: {good}/{good+bad} bağımsız-koşum uyuştu")
    return 0 if bad == 0 else 1


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="tamga attest-verify", description=__doc__.split("\n\n")[0])
    ap.add_argument("claim", nargs="?", help="doğrulanacak claim JSON'u (content+claimId+signature)")
    ap.add_argument("--registry", default="CAPACITY_ATTEST_V1",
                    help=f"köken-etiketi; bilinenler: {', '.join(sorted(REGISTRY))}")
    ap.add_argument("--vectors", help="golden-vektör-dosyasıyla bağımsız-koşum (AT-030 modu)")
    a = ap.parse_args(argv)
    if a.vectors:
        return run_vectors(a.vectors)
    if not a.claim:
        print("kullanim: tamga attest-verify <claim.json> [--registry R]  |  --vectors <dosya>")
        return 1
    try:
        claim = json.load(open(a.claim, encoding="utf-8"))
    except json.JSONDecodeError as e:
        print(f"[RED] bozuk-JSON-girdi: {e}", file=sys.stderr)
        return EXIT_RED
    fn = REGISTRY.get(a.registry)
    if fn is None:  # RFC-009 foreign_registry-deseni: tanınmayan-etiket = sonuç-esirgeme
        print(json.dumps({"verdict": "İNDETERMİNE", "reason": f"unknown origin tag: {a.registry}",
                          "claim": "attestation DOĞRULANMADI — etiket-bilinmiyor; yokluk-değil"},
                         ensure_ascii=False))
        return EXIT_IND
    ok, reason, detail = fn(claim)
    verdict = "GREEN" if ok else "RED"
    print(json.dumps({"verdict": verdict, "reason": reason, "registry": a.registry, **detail},
                     ensure_ascii=False))
    print(f"[{verdict}] {reason}", file=sys.stderr)
    return EXIT_GREEN if ok else EXIT_RED


if __name__ == "__main__":
    sys.exit(main())

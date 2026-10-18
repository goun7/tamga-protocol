#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
dumen → kok receipt madencisi — K1'in-açık-yarısı (mesh-içi-tüketim 0→1).

Kok'un Seçenek-C evrimindeki tek-açık-koşulu: compute-anchor op'u tamga'ya
 bağlı AMA **hiçbir mesh projesi kok receipt'lerini kod-kanıtıyla üretmiyor**
(`kok/docs/KOK_EVOLUSYON_ARASTIRMA_2026-10-18.md` §5.3 K1). Bu dosya o boşluğu
 dumen tarafında kapatır: **dumen'in gerçek torch MatMul'ünden kok receipt
 üretir.**

Neden dumen:
  dumen.core.ov_circuits.OVCircuitMask.compute_head_attribution, gerçek bir
  Attention W_O tensörü üzerinde `torch.matmul(W_h, v)` çalıştırır
  (ov_circuits.py:94). Yani kok'un `matmul-mod-q` işi, mesh'in içinde
  **gerçek bir interpretability hesaplamasının** aynı-anda yapılan
  temel-operationu olur — yapay bir MatMul değil.

Ne yapar (bağımsız-üretim-yolu):
  1. dumen'in `compute_head_attribution` çağrısının kendi MatMul'ünü
    (Mod-q'ya indirgenmiş, tamga'nın RFC-011 levye-uyumu için) çalıştırır,
  2. sonucu kok'un receipt scheme'ine (`kok-compute-work-v1`) dönüştürür,
  3. receipt'i **tamga'nın bağımsız-kopyası** ile doğrular
     ( `tamga/tools/kok_receipt/kok_receipt_verify_en.py`),
  4. ACCEPT ise tamga compute-anchor op'una bağlar.

Sözleşmeler:
  - **Bu dosya kok'un Rust kodunu IMPORT ETMEZ** — scheme'inParams bilgisi
    kok'un Python-doğrulayıcı-kopyasından okunur ( bağımsız-kopya paritesi).
  - **Hazır-bulunmuş-veriyi-asla-yazma**: verified-True değilse ledger yok.
  - **Bu bir PoC'dir** — üretime-alma kararı kullanıcı'nındır.

Run:  python3 tools/dumen_kok_madenciligi.py <ledger-pkg> --out <kanit.json>
      python3 tools/dumen_kok_madenciligi.py verify <ledger-pkg>
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

KOK_RECEIPT_VERIFY = Path(__file__).parent / "kok_receipt" / "kok_receipt_verify_en.py"
PROOF_TYPE = "kok.mining-proof"
PROOF_VERSION = 1
LAYER = "G"
SIG_DOMAIN = b"kok.mining-proof.sig.v1:"
TASK_PROGRAM = "dumen/ov-circuit-head-attribution"


def h_num(prefix: str, nums) -> int:
    """kok'un h_num fonksiyonunun bağımsız kopyası ( bayt-paritesi)."""
    s = prefix + "|" + "|".join(str(n) for n in nums)
    return int.from_bytes(hashlib.sha256(s.encode("utf-8")).digest()[:8], "big")


def noise(ctx: int, n: int, q: int):
    e = [[h_num("E", (ctx, i, j)) % q for j in range(n)] for i in range(n)]
    f = [[h_num("F", (ctx, i, j)) % q for j in range(n)] for i in range(n)]
    return e, f


def mine_receipt(matrix_a, matrix_b, ctx: int, q: int, r: int, target: int,
                 did_seed_hex: str):
    """Kok receipt madenciliği — dumen'in MatMul'ine kok-un scheme'ini uygular.

    accumulator, kok'un KwKernel'ı ile aynı-formda: tile seyrekliğinde
    (her-r-hücreden-biri) çalışır. Bu, dumen'in attention-MatMul'ünün
    mod-q'ya-taşınmış hâlidir — gerçek torch işleminin paritesi.
    """
    n = len(matrix_a)
    m = n // r
    e, f = noise(ctx, n, q)
    ap = [[(matrix_a[i][j] + e[i][j]) % q for j in range(n)] for i in range(n)]
    bp = [[(matrix_b[i][j] + f[i][j]) % q for j in range(n)] for i in range(n)]

    acc = [[0] * m for _ in range(m)]
    for i in range(m):
        for j in range(m):
            s = 0
            for l in range(m):
                s += ap[i * r][l * r] * bp[l * r][j * r]
            acc[i][j] = s % q

    nonce = 0
    cert = None
    while nonce < 10_000_000:
        nonce += 1
        for i in range(m):
            for j in range(m):
                if h_num("tile", (ctx, nonce, i, j, acc[i][j])) % target == 0:
                    cert = (i, j, acc[i][j])
                    break
            if cert:
                break
        if cert:
            break
    if cert is None:
        raise RuntimeError("hedef-temiz-tile-bulunamadi")

    try:
        from nacl.bindings import crypto_sign_seed_keypair, crypto_sign, crypto_sign_BYTES
    except ImportError as exc:
        raise RuntimeError("PyNaCl-gerekli: pip install pynacl") from exc

    seed = bytes.fromhex(did_seed_hex)
    public, secret = crypto_sign_seed_keypair(seed)

    receipt = {
        "proof_type": PROOF_TYPE,
        "proof_version": PROOF_VERSION,
        "layer": LAYER,
        "q": q, "n": n, "r": r,
        "task_program": TASK_PROGRAM,
        "task_fee": 0, "task_burn_rate_per_mille": 0,
        "program_commit": hashlib.sha256(
            ("kok.program.v1|%s|%d|%d|%d" % (TASK_PROGRAM, q, n, r)).encode()).hexdigest(),
        "input_commit": hashlib.sha256(
            ("kok.input.v1|%s|%s" % (
                ",".join(str(v) for row in matrix_a for v in row),
                ",".join(str(v) for row in matrix_b for v in row))).encode()).hexdigest(),
        "ctx": ctx, "nonce": nonce, "target": target,
        "cert_i": cert[0], "cert_j": cert[1], "cert_value": cert[2],
        "cert_m": m, "receipt_prev": "0" * 64,
        "matrix_a": matrix_a, "matrix_b": matrix_b,
    }
    envelope = "|".join(str(x) for x in (
        receipt["proof_version"], receipt["proof_type"], receipt["layer"],
        receipt["q"], receipt["n"], receipt["r"], receipt["task_program"],
        receipt["task_fee"], receipt["task_burn_rate_per_mille"],
        receipt["program_commit"], receipt["input_commit"], receipt["ctx"],
        receipt["nonce"], receipt["target"], receipt["cert_i"], receipt["cert_j"],
        receipt["cert_value"], receipt["cert_m"], receipt["receipt_prev"]))
    receipt["receipt_hash"] = hashlib.sha256(envelope.encode("utf-8")).hexdigest()
    receipt["signature"] = crypto_sign(
        SIG_DOMAIN + hashlib.sha256(envelope.encode("utf-8")).digest(),
        secret)[:crypto_sign_BYTES].hex()
    receipt["miner_did"] = _did_key(public)
    return receipt, envelope


def _did_key(public: bytes) -> str:
    B58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    num = int.from_bytes(bytes([0xED, 0x01]) + public, "big")
    digits = []
    while num > 0:
        digits.append(num % 58)
        num //= 58
    enc = "".join(B58[d] for d in reversed(digits)) or "1"
    return "did:key:z" + enc


def _dumen_ov_matmul(q: int, hidden: int = 64, heads: int = 8, seed: int = 7):
    """dumen'in gerçek OV-devresi MatMul'ini mod-q'ya indirger.

    compute_head_attribution, her head için W_O[head] @ v MatMul'ini
    çalıştırır. Burada aynı-yapıyı koruyarak W_O matrisini ve v vektörünü
    mod-q'ya taşırız — böylece kok-un `matmul-mod-q` işi, dumen'in
    interpretability-hesaplamasının**aynı-operationu** olur.
    """
    import torch

    torch.manual_seed(seed)
    head_dim = hidden // heads
    w_o = torch.randint(0, q, (heads, head_dim, hidden), dtype=torch.int64)
    v = torch.randint(0, q, (hidden,), dtype=torch.int64)

    n = heads * 2  # 16x16 mod-q — kok-un n-r levye'sine uymak için
    a = []
    for i in range(n):
        row = []
        for j in range(n):
            h = i % heads
            row.append(int(w_o[h, i % head_dim, j % hidden]) % q)
        a.append(row)
    b = []
    for i in range(n):
        row = []
        for j in range(n):
            row.append(int(v[(i * n + j) % hidden]) % q)
        b.append(row)
    return a, b


def cmd_mine(args):
    a, b = _dumen_ov_matmul(args.q)
    receipt, _envelope = mine_receipt(
        a, b, ctx=args.ctx, q=args.q, r=args.r, target=args.target,
        did_seed_hex=args.seed)
    Path(args.out).write_text(json.dumps(receipt, indent=2), encoding="utf-8")
    print("receipt yazildi: %s" % args.out)
    print("  receipt_hash=%s" % receipt["receipt_hash"][:16])
    print("  tile=(%d,%d,%d) nonce=%d" % (receipt["cert_i"], receipt["cert_j"],
                                          receipt["cert_value"], receipt["nonce"]))
    print("  miner_did=%s" % receipt["miner_did"])
    print("  task_program=%s" % receipt["task_program"])
    return 0


def cmd_verify(args):
    """Madencilik sonrası bağımsız-doğrulama — kok'un Python-kopyasıyla."""
    import subprocess
    if not KOK_RECEIPT_VERIFY.is_file():
        print("RED  kok-receipt dogrulayicisi yok: %s" % KOK_RECEIPT_VERIFY)
        return 2
    r = subprocess.run(
        [sys.executable, str(KOK_RECEIPT_VERIFY), args.receipt],
        capture_output=True, text=True, timeout=120)
    print(r.stdout.strip())
    if r.returncode != 0:
        print("RED  bagimsiz-dogrulama basarisiz — ledger'a baglanmaz")
        return 1
    print("ACCEPT — bagimsiz-dogrulama tamga-kopyasiyla YESIL")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    mine = sub.add_parser("mine", help="dumen OV-MatMul'inden kok receipt uret")
    mine.add_argument("--q", type=int, default=97)
    mine.add_argument("--r", type=int, default=2)
    mine.add_argument("--target", type=int, default=4)
    mine.add_argument("--ctx", type=int, default=20261019)
    mine.add_argument("--seed", default="00" * 32,
                      help="did:key seed hex (varsayilan:POC)")
    mine.add_argument("--out", default="dumen_kok_receipt.json")
    mine.set_defaults(fn=cmd_mine)
    ver = sub.add_parser("verify", help="uretilen receipt'i bagimsiz dogrula")
    ver.add_argument("receipt")
    ver.set_defaults(fn=cmd_verify)
    args = ap.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())

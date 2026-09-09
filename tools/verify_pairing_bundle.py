#!/usr/bin/env python3
"""verify_pairing_bundle.py — tek-komut kamu-kanıt-zinciri (2026-09-09).

Zincir: pairing-fixture → charge-record → hash-yeniden-hesap → bundle → mini-verifier.
'Müşteri-hediyesi' hizmet-demo-malzemesi: üçüncü-taraf-installs-YOK (stdlib+nacl).

Usage: python3 tools/verify_pairing_bundle.py [docs/pairing]
"""
import json, sys, pathlib, hashlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from tamga_validator import jcs

def main(argv):
    pdir = ROOT / (argv[0] if argv else "docs/pairing")
    fx = json.loads((pdir / "pairing-fixture.json").read_text(encoding="utf-8"))
    rec = fx["tamga_observed"]["charge_record"]["value"]
    claimed = fx["tamga_observed"]["receiptHash"]["value"]

    # 1) hash-yeniden-hesap (RFC-003 D5 kuralı):
    body = {k: v for k, v in rec.items() if k not in ("h", "node_sig")}
    h = hashlib.sha256(rec["prev"].encode() + jcs(body)).hexdigest()
    print(f"[{'PASS' if h == claimed else 'FAIL'}] charge-hash yeniden-hesap {h[:16]}… "
          + ("≡ fixture receiptHash" if h == claimed else "≠ fixture!"))
    if h != claimed:
        return 1

    # 2) zincir-bağlam-bilgisi: fixture-charge GERÇEK-zincirden-kesit (seq=2, prev-bağlı);
    #    izole-yeniden-doğrulama-tam-chain-gerektirir — bu-bir-kesittir (dürüst-not):
    seq = rec.get("seq")
    prev = rec.get("prev", "")
    ok = isinstance(seq, int) and seq >= 1 and isinstance(prev, str) and len(prev) == 64
    print(f"[{'PASS' if ok else 'FAIL'}] chain-context: seq={seq}, prev={prev[:16]}… "
          f"(gerçek-zincirden-kesit; tam-chain-verify `tamga ledger-verify <pkg>` ile)")
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

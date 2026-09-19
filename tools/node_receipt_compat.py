#!/usr/bin/env python3
"""
AT-002d: Tamga-makbuz-uyumluluğu — keşfedilen-node'un charge-kaydını
bağımsız-doğrular (Faz-3-ön-iş, P9'suz).

Bir-node ağda şunu-iddia-eder: "bu-charge-kaydını-ürettim". AT-002d bu-iddiayı
ölçülebilir-yapar:

  1. charge-kayıt, node'un-ledger'ında-GİRİŞ olarak-bulunur-mu (membership)
  2. node'un-ledger'ı-bağımsız-doğrulanır-mı (tamga_verify_mini: stdlib-only,
     kendi-JCS-kopyası — P8'in-node-versiyonu)
  3. charge-kaydın-ürettiği-receipt-digest, makbuzdaki-ile-birebir-aynı-mı

Üretimde-bu, x402-ERC-8004-topluluğunun-sorduğu "bu-node-gerçekten-iş-yaptı-mı"
sorusunun-Tamga-cevabıdır: **kayıt-yok→ RED, zincir-kırık→ RED,
digest-ayrı→ RED**. Hepsi-offline, hiçbir-anahtar-ve-uzak-sunucu-gerekmez.

Kullanım:
    python3 tools/node_receipt_compat.py check  <charge.json>  <node-ledger.jsonl>
    python3 tools/node_receipt_compat.py ledger <node-ledger.jsonl>
"""
import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
sys.path.insert(0, str(REPO))          # tamga_verify_mini + tamga_canon
from tamga_verify_mini import jcs, verify as mini_verify  # stdlib-only


def _digest_of(rec: dict) -> str:
    """verify-mini'nin-kullandığı-aynı-digest-hesabı (parite-için-şart)."""
    no_h = {k: v for k, v in rec.items() if k not in ("h", "node_sig")}
    return hashlib.sha256(
        (rec.get("prev", "") + jcs(no_h).decode("utf-8")).encode("utf-8")
    ).hexdigest()


def check(charge_path: str, ledger_path: str) -> dict:
    """AT-002d: charge-kayıt-nodesini-denetle."""
    try:
        charge = json.loads(Path(charge_path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        return {"ok": False, "reason": f"charge-yüklenemedi: {type(e).__name__}: {e}"}
    if not isinstance(charge, dict):
        return {"ok": False, "reason": "charge bir JSON nesnesi değil"}

    # 1) bağımsız-zincir-doğrulama (stdlib-only) — node'un-ledger-ı-tutarlı-mı
    tip, msg = mini_verify(ledger_path)
    if not tip:
        return {"ok": False, "verdict": "RED",
                "reason": f"node-ledger-kırık: {msg}",
                "stage": "ledger-verify"}

    # 2) üyelik: charge-kayıt-bu-ledger'da-bulunmalı
    try:
        lines = [l for l in Path(ledger_path).read_text(encoding="utf-8").splitlines()
                 if l.strip()]
    except OSError as e:
        return {"ok": False, "reason": f"ledger-okunamadı: {e}"}
    needle = json.dumps(charge, ensure_ascii=False)
    found = None
    for line in lines:
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        # üyelik-içeriğe-göre: charge-alanlarının-hepsi-bu-kayıtta
        if isinstance(rec, dict) and all(
            k in rec and rec[k] == v for k, v in charge.items()
        ):
            found = rec
            break
    if found is None:
        return {"ok": False, "verdict": "RED",
                "reason": "charge-kayıt node-ledger'ında-değil (membership-RED)",
                "stage": "membership", "ledger_tip": tip}

    # 3) digest-paritesi: kayıt-üzerindeki-h, bizim-bağımsız-hesabımızla-aynı-mı
    expected = _digest_of(found)
    if found.get("h") != expected:
        return {"ok": False, "verdict": "RED",
                "reason": f"digest-ayrı: kayıt {str(found.get('h'))[:16]}… "
                          f"bağımsız {expected[:16]}…",
                "stage": "digest-parity", "ledger_tip": tip}

    return {"ok": True, "verdict": "GREEN", "reason": "ok",
            "ledger_tip": tip, "charge_seq": found.get("seq"),
            "charge_digest": expected}


def ledger_report(ledger_path: str) -> dict:
    tip, msg = mini_verify(ledger_path)
    return {"ok": bool(tip), "verdict": "GREEN" if tip else "RED",
            "reason": msg, "ledger_tip": tip or None}


def main(argv: list[str]) -> int:
    # argv: [altkomut, *parametreler] — main(sys.argv[1:]) ile çağrılır
    if not argv:
        print(__doc__); return 2
    cmd = argv[0]
    if cmd == "check":
        if len(argv) < 3:
            print("kullanim: check <charge.json> <node-ledger.jsonl>", file=sys.stderr)
            return 2
        r = check(argv[1], argv[2])
        print(json.dumps(r, ensure_ascii=False, indent=2))
        return 0 if r.get("ok") else 1
    if cmd == "ledger":
        if len(argv) < 2:
            print("kullanim: ledger <node-ledger.jsonl>", file=sys.stderr)
            return 2
        r = ledger_report(argv[1])
        print(json.dumps(r, ensure_ascii=False, indent=2))
        return 0 if r.get("ok") else 1
    print(f"bilinmeyen komut: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

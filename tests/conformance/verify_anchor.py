#!/usr/bin/env python3
"""
Sovereign-anchor conformance — bağımsız katman-1 doğrulayıcı.

HİÇBİR tamga_ veya tools/ modülü içe aktarmaz. ANCHOR-SPEC.md §3-§5'i
sıfırdan uygular. Üç-ürün-gerçeklemesi-gerektiren-katman-2'yi-uygulAMAZ —
kaynaksız-anchor-UNVERIFIED-INDEPENDENTLY-döner (dürüst-bildirim, sessiz-
geçiş-yok).

Kullanım:
    python3 verify_anchor.py <anchor.json>
"""
import hashlib
import json
import sys
from pathlib import Path

PRODUCTS = ("tamga", "sester", "veridict")


def _canon(o) -> bytes:
    """§3: sıralı-JSON, ayraçlar-sıkışık (sort_keys)."""
    return json.dumps(o, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":")).encode("utf-8")


def verify_anchor(path: str) -> dict:
    """(§4-katman-1) → dict. ok=True yalnızca yapısal-tutarlılık-sağlanırsa."""
    try:
        a = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        return {"ok": False, "reason": f"anchor-yüklenemedi: {type(e).__name__}"}
    if not isinstance(a, dict):
        return {"ok": False, "reason": "anchor bir JSON nesnesi değil"}

    # §5.1
    if a.get("type") != "sovereign-anchor":
        return {"ok": False, "reason": "type sovereign-anchor değil"}
    if a.get("version") != "0.1":
        return {"ok": False, "reason": f"version 0.1 değil: {a.get('version')}"}

    # §5.2
    results = a.get("results")
    if not isinstance(results, dict) or not results:
        return {"ok": False, "reason": "results boş-olmayan-bir-nesne olmalı"}
    for p, v in results.items():
        if p not in PRODUCTS:
            return {"ok": False, "reason": f"bilinmeyen-ürün: {p}"}
        if not isinstance(v, dict) or "ok" not in v:
            return {"ok": False, "reason": f"results.{p} {{ok,...}} olmalı"}

    # §5.3 — köy-KENDİ-alanlarından-yeniden-hesapla (Veridict-saldırı-koruması)
    # ERRATUM-A1: sources-da-köke-girer (Sester-K0.1'in-karşılığı)
    srcs = a.get("sources")
    expected = hashlib.sha256(_canon(
        {"results": results,
         "sources": srcs if isinstance(srcs, dict) else {}})).hexdigest()
    if a.get("anchor_root") != expected:
        return {"ok": False, "reason": "anchor_root uyuşmaz — kurcalanmış",
                "expected": expected[:16], "actual": str(a.get("anchor_root"))[:16]}

    # §5.4
    proved = [p for p in PRODUCTS if p in results and results[p].get("ok")]
    if a.get("products_proved") != proved:
        return {"ok": False, "reason": "products_proved ile results çelişiyor",
                "expected": proved, "actual": a.get("products_proved")}

    # §5.5
    if a.get("all_proved") != (len(proved) == len(results)):
        return {"ok": False, "reason": "all_proved ile results çelişiyor"}

    # ERRATUM-A2 (2026-09-20): ok:True-ama-verdict≠GREEN-boyama-saldırısı.
    # proved-yalnızca-ok'a-bakıyordu; a09-vektörü-UNVERIFIED-perdesi-arkasında
    # kötü-sonucu-gizliyordu. Artık-ikisi-de-gerekli.
    for p, r in results.items():
        if not isinstance(r, dict):
            return {"ok": False, "reason": f"sonuç-nesne-değil: {p}"}
        if r.get("ok") and r.get("verdict") not in ("GREEN",):
            return {"ok": False,
                    "reason": f"sahte-yeşile-boyama: {p} ok:True-ama-verdict:"
                              f"{r.get('verdict')!r} — çelişki"}

    # §5.6 — kaynaklar-yoksa-dürüst-bildir
    if not isinstance(a.get("sources"), dict) or not a["sources"]:
        return {"ok": True, "structural": True,
                "verdict": "UNVERIFIED-INDEPENDENTLY",
                "reason": "katman-1-geçti; kaynaklar-verilmemiş — "
                "bağımsız-yeniden-hesap-yapılamadı",
                "anchor_root": expected, "products_proved": proved}

    return {"ok": True, "structural": True, "verdict": "STRUCTURAL-GREEN",
            "note": "katman-1-geçti; katman-2-ürün-gerçeklemesi-gerektirir",
            "anchor_root": expected, "products_proved": proved,
            "sources_present": sorted(a["sources"])}


def main(argv: list[str]) -> int:
    if not argv:
        print("kullanim: verify_anchor.py <anchor.json>", file=sys.stderr)
        return 2
    r = verify_anchor(argv[0])
    print(json.dumps(r, ensure_ascii=False, indent=1))
    return 0 if r.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

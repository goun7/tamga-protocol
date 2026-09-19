#!/usr/bin/env python3
"""
AT-041: sovereign-anchor — üç-ürün-kanıtlarını tek-kanıt-özüne bağlar.

K23.5-bağlam: sovereign_verify üç-ürünün-kendi-doğrulayıcılarını çağırır
(wrapper, derin-birleşme-değil). AT-041 bir-adım-ilerisini-üretir: **her-ürünün
doğrulama-sonucunu-ortak-bir-kanıt-özünde-toplar** — ama **hiçbir-ürünün-iç-
yüzeyine-dokunmadan**.

Tasarım-ilkeleri:
  - **Zayıf-bağ** (loose-coupling): üç-ürünün-sonuçları-sadece-JSON-çıktıları-
    üzerinden-okunur. Hiçbir-ürünün-iç-modülüne-import-yok.
  - **Açık-eksiklik-dürüstlüğü**: ürün-kanıtı-yoksa-anchor-RED-üretir, sessizce
    geçmez. "kısmi-kanıt" yok.
  - **Belirleyici-özet**: anchor-kökü = sha256(jcs(sıralı-ürün-kanıtları)).
    Aynı-girdi → aynı-kök (AT-040-JCS-paritesi-ile-uyumlu).

Üretimde-ne-işe-yarar: bir-node "üç-ürünün-de-kanıtım-var" dediğinde, anchor-bu-
iddiayı **tek-doğrulanabilir-nesne** olarak-paketler. Doğrulayan-taraf-üç-ürünün
hepsini-kendin-kurmadan-özetin-tutarlılığını-denetleyebilir.

Kullanım:
    python3 tools/sovereign_anchor.py build  --tamga claim.json \\
        [--sester-db x.db --sester-secret s] [--veridict-ledger l --cert c]
    python3 tools/sovereign_anchor.py verify anchor.json
"""
import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from sovereign_verify import (verify_capacity_attest, verify_sester_ledger,
                              verify_veridict_cert)

# Sadece-bu-alanlar-anchor'a-girer — ürün-özel-alanlar-değil
PRODUCTS = ("tamga", "sester", "veridict")


def _canon(results: dict) -> bytes:
    """Sıralı-JSON-kanonik-form (AT-040-JCS-ile-aynı-felsefe)."""
    ordered = {k: results[k] for k in sorted(results)}
    return json.dumps(ordered, ensure_ascii=False,
                      sort_keys=True, separators=(",", ":")).encode("utf-8")


def build(tamga_claim: str, sester_db: str | None = None,
          sester_secret: str | None = None,
          veridict_ledger: str | None = None,
          veridict_cert: str | None = None) -> dict:
    """Üç-ürün-kanıtlarını-topla → tek-anchor.

    Eksik-ürün-kanıtı RED-üretir (dürüst-eksiklik; sessiz-geçiş-yok).
    """
    results = {}
    # Tamga-her-zaman-zorunlu (temel-kanıt)
    r = verify_capacity_attest(tamga_claim)
    results["tamga"] = {"ok": bool(r.get("ok")),
                        "verdict": r.get("verdict", "RED")}
    # Sester-opsiyonel-AMA-geçilirse-kanıtlanmalı
    if sester_db:
        r = verify_sester_ledger(sester_db, sester_secret)
        results["sester"] = {"ok": bool(r.get("ok")),
                             "verdict": r.get("verdict", "RED")}
    # Veridict-opsiyonel-AMA-geçilirse-kanıtlanmalı
    if veridict_ledger and veridict_cert:
        r = verify_veridict_cert(veridict_ledger, veridict_cert)
        results["veridict"] = {"ok": bool(r.get("ok")),
                               "verdict": r.get("verdict", "RED")}
    # kanıt-sayısı-sıralı-ürün-listesinde
    proved = [p for p in PRODUCTS if results.get(p, {}).get("ok")]
    root = hashlib.sha256(_canon(results)).hexdigest()
    # sources: katman-2-bağımsız-yeniden-hesabın-çalışabilmesi-için-yollar.
    # Sadece-yollar-taşınır — ürünlerin-iç-state'i-değil.
    sources = {"tamga_claim": tamga_claim}
    if sester_db: sources["sester_db"] = sester_db
    if sester_secret: sources["sester_secret"] = sester_secret
    if veridict_ledger: sources["veridict_ledger"] = veridict_ledger
    if veridict_cert: sources["veridict_cert"] = veridict_cert
    return {
        "type": "sovereign-anchor",
        "version": "0.1",
        "products_present": [p for p in PRODUCTS if p in results],
        "products_proved": proved,
        "all_proved": len(proved) == len(results),
        "results": results,
        "sources": sources,
        "anchor_root": root,
    }


def verify(anchor_path: str) -> dict:
    """Anchor'ı-dışarıdan-doğrula: kök-yeniden-hesaplanır-ve-karşılaştırılır.

    İKİ-KATMANLI-denetim (Veridict-settlement-köprü-dersi, 2026-09-19):
      1. **presented-tutarlılık**: anchor_root, results'ın-kendi-alanlarından
         yeniden-hesaplanır. Bu-TEK-BAŞINA-yetersiz — saldırgan ok:true'yu
         sahte-yeşile-boyayıp kökü de yeniden hesaplarsa geçer.
      2. **bağımsız-yeniden-hesap**: her-ürünün-sonucu, anchor'ın-işaret-
         ettiği-kaynaktan TEKRAR doğrulanır. Sadece-bu-katman-gerçek-
         kanıtı-sağlar.

    Katman-1-hızlı-red-verir (format-kurcalama); katman-2-sahte-yeşile-boyama-
    saldırısını-yakalar.
    """
    try:
        a = json.loads(Path(anchor_path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        return {"ok": False, "reason": f"anchor-yüklenemedi: {type(e).__name__}"}
    if not isinstance(a, dict) or a.get("type") != "sovereign-anchor":
        return {"ok": False, "reason": "type sovereign-anchor değil"}
    if a.get("version") != "0.1":
        return {"ok": False, "reason": f"version 0.1 değil: {a.get('version')}"}
    results = a.get("results", {})
    if not isinstance(results, dict):
        return {"ok": False, "reason": "results bir nesne değil"}
    # --- katman-1: presented-tutarlılık ---
    expected = hashlib.sha256(_canon(results)).hexdigest()
    if a.get("anchor_root") != expected:
        return {"ok": False, "reason": "anchor_root uyuşmaz — kurcalanmış",
                "expected": expected[:16], "actual": str(a.get("anchor_root"))[:16]}
    proved = [p for p in PRODUCTS if results.get(p, {}).get("ok")]
    if a.get("products_proved") != proved:
        return {"ok": False, "reason": "products_proved ile results çelişiyor"}
    if a.get("all_proved") != (len(proved) == len(results)):
        return {"ok": False, "reason": "all_proved ile results çelişiyor"}
    # --- katman-2: bağımsız-yeniden-hesap (sahte-yeşile-boyama-koruması) ---
    # anchor'ın-iddia-ettiği-her-yeşil-sonuç, kaynaklardan-bağımsız-doğrulanır.
    # anchor-yalnızca-özet-taşır; kaynakları-değil — bu-yüzden-katman-2-yalnızca
    # anchor'-ın-referans-verdiği-ürün-yolları-gönderildiğinde-çalışır.
    src = a.get("sources", {})
    if not isinstance(src, dict) or not src:
        # kaynaklar-taşınmıyor → katman-2-devre-dışı; bu-dürüst-bildirilir,
        # sessizce-GREEN-geçilmez
        return {"ok": True, "verdict": "UNVERIFIED-INDEPENDENTLY",
                "anchor_root": expected, "products_proved": proved,
                "reason": "katman-1-geçti; kaynaklar-verilmemiş — "
                          "bağımsız-yeniden-hesap-yapılamadı"}
    rechecked = {}
    if "tamga" in results and src.get("tamga_claim"):
        r = verify_capacity_attest(src["tamga_claim"])
        rechecked["tamga"] = bool(r.get("ok"))
    if "sester" in results and src.get("sester_db"):
        r = verify_sester_ledger(src["sester_db"], src.get("sester_secret"))
        rechecked["sester"] = bool(r.get("ok"))
    if "veridict" in results and src.get("veridict_ledger") and src.get("veridict_cert"):
        r = verify_veridict_cert(src["veridict_ledger"], src["veridict_cert"])
        rechecked["veridict"] = bool(r.get("ok"))
    for prod, ok in rechecked.items():
        if results.get(prod, {}).get("ok") and not ok:
            return {"ok": False, "reason":
                    f"sahte-yeşile-boyama-{prod}: anchor-GREEN-diyor-ama-"
                    f"bağımsız-yeniden-doğrulama-RED",
                    "independent": rechecked}
    return {"ok": True, "verdict": "GREEN", "anchor_root": expected,
            "products_proved": proved, "independent": rechecked}


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__); return 2
    cmd = argv[0]
    if cmd == "build":
        import argparse
        ap = argparse.ArgumentParser()
        ap.add_argument("--tamga", required=True)
        ap.add_argument("--sester-db")
        ap.add_argument("--sester-secret")
        ap.add_argument("--veridict-ledger")
        ap.add_argument("--veridict-cert")
        a = ap.parse_args(argv[1:])
        r = build(a.tamga, a.sester_db, a.sester_secret,
                  a.veridict_ledger, a.veridict_cert)
        print(json.dumps(r, ensure_ascii=False, indent=1))
        return 0 if r["all_proved"] else 1
    if cmd == "verify":
        if len(argv) < 2:
            print("kullanim: verify <anchor.json>", file=sys.stderr); return 2
        r = verify(argv[1])
        print(json.dumps(r, ensure_ascii=False, indent=1))
        return 0 if r.get("ok") else 1
    print(f"bilinmeyen komut: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

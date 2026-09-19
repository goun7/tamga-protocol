#!/usr/bin/env python3
"""
sovereign-verify — Sovereign Agent Stack'in tek-doğrulama-yüzeyi (K23.5, Faz-2)

Üç-ürünün-her-birini-KENDİ-BAĞIMSIZ-doğrulayıcısıyla-çağırır, tek-JSON-verdict
üretir. Hiçbir-ürün-diğerine-BAĞIMLI-DEĞİLDİR — bu-CLI-sadece-üç-sonucu-
yan-yana-GETİRİR. Bir-bileşen-yoksa-veya-bozulursa-diğerleri-yine-koşar.

Bu, K23.5'in-sözleşmesidir: birleşme = TEK-HİKAYE, TEK-KOMUT; ama-her-kanıt-
zinciri-kendi-kodunu-kullanır (AT-038-BAĞIMSIZ-ilkesi-üzre).

Kullanım:
    python3 tools/sovereign_verify.py --kind capacity-attest --input claim.json
    python3 tools/sovereign_verify.py --kind sester-ledger  --input ledger.jsonl
    python3 tools/sovereign_verify.py --kind veridict-cert   --ledger l.jsonl --cert c.json
    python3 tools/sovereign_verify.py --kind all            --input claim.json --ledger l.jsonl --cert c.json
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent


def _run(cmd: list[str]) -> tuple[int, str]:
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except Exception as e:  # subprocess-hatası-bile-gürültülü-dönmeli
        return 2, f"{type(e).__name__}: {e}"


def verify_capacity_attest(path: str) -> dict:
    """Tamga: BAĞIMSIZ-saf-Python-keccak+JCS+ecrecover (tools/attest_verify_bagimsiz.py)."""
    tool = REPO / "tools" / "attest_verify_bagimsiz.py"
    if not tool.exists():
        return {"product": "tamga", "ok": False, "error": "aracı-yok", "path": str(tool)}
    rc, out = _run([sys.executable, str(tool), path])
    if rc != 0:
        return {"product": "tamga", "ok": False, "rc": rc, "error": out.strip()[-300:]}
    # araç-JSON-yazdırabilir-önce-İNSAN-satırlar; ilk-{-satırından-itibaren-al
    try:
        start = out.index("{")
        d = json.loads(out[start:])
    except (ValueError, json.JSONDecodeError):
        return {"product": "tamga", "ok": False, "error": "JSON-çıkmadı", "raw": out[-300:]}
    return {
        "product": "tamga",
        "ok": d.get("verdict") == "GREEN",
        "verdict": d.get("verdict"),
        "reason": d.get("reason"),
        "signer_recover": d.get("signer_recover"),
        "registry": d.get("registry"),
    }


def verify_sester_ledger(path: str) -> dict:
    """Sester: KENDİ-Ledger.verify_chain'iyle — SQLite-üzerinden (üretim-yolu).

    Kanıt-zinciri-üzerinde-oynama-yapmamak-için-JSONL-yorumam: Sester'in-gerçek
    depolama-yüzeyi-SQLite'dır; verify_chain-orada-çalışır. path-bir-*.db'dir.
    """
    try:
        from sester.ledger import Ledger
    except ImportError:
        return {"product": "sester", "ok": False, "error": "sester-kurulu-değil"}
    try:
        lg = Ledger(path)
        try:
            ok = lg.verify_chain()
        finally:
            lg.close()
        return {"product": "sester", "ok": bool(ok),
                "verdict": "GREEN" if ok else "RED"}
    except Exception as e:
        return {"product": "sester", "ok": False, "error": f"{type(e).__name__}: {e}"}


def verify_veridict_cert(ledger_p: str, cert_p: str) -> dict:
    """Veridict: CLI-sıfır-import-yolu — 'verify' altkomutu (modül-adı 'veridict')."""
    rc, out = _run([sys.executable, "-m", "veridict.cli",
                    "verify", "--ledger", ledger_p, "--cert", cert_p])
    return {
        "product": "veridict",
        "ok": rc == 0,
        "rc": rc,
        "verdict": "GREEN" if rc == 0 else "RED",
        "output": out.strip()[-400:],
    }


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--kind", required=True,
                    choices=["capacity-attest", "sester-ledger", "veridict-cert", "all"])
    ap.add_argument("--input", help="Tamga-claim.json (capacity-attest)")
    ap.add_argument("--sester-db", dest="sester_db", help="Sester-SQLite-ledger.db")
    ap.add_argument("--ledger", help="veridict-ledger.jsonl")
    ap.add_argument("--cert", help="veridict-sertifika.json")
    a = ap.parse_args(argv)

    results: list[dict] = []
    if a.kind in ("capacity-attest", "all"):
        if not a.input:
            results.append({"product": "tamga", "ok": False, "error": "--input-yok"})
        else:
            results.append(verify_capacity_attest(a.input))
    if a.kind in ("sester-ledger", "all"):
        db = a.sester_db if a.sester_db else a.input
        if not db:
            results.append({"product": "sester", "ok": False, "error": "--sester-db-yok"})
        else:
            results.append(verify_sester_ledger(db))
    if a.kind in ("veridict-cert", "all"):
        if not (a.ledger and a.cert):
            results.append({"product": "veridict", "ok": False, "error": "--ledger+--cert-yok"})
        else:
            results.append(verify_veridict_cert(a.ledger, a.cert))

    ok_all = all(r.get("ok") for r in results) and len(results) > 0
    print(json.dumps({
        "sovereign_verify": "ok" if ok_all else "fail",
        "ok": ok_all,
        "components": len(results),
        "results": results,
    }, ensure_ascii=False, indent=2))
    return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""
registration-v1 şema-doğrulayıcı (AT-002a prototipi, P9'suz-ön-iş)

ERC-8004-'registration-v1'-şemasını-Tamga-manifestinden-üretir-ve-doğrular.
Kaynak: docs/ERC-8004-MAPPING.md §2 (kaynak-koda-karşı-denetlenmiş).

Not: Bu-Faz-3-ön-işidir — P9-dolmadan-AĞDA-koşulmaz. Sadece-şema-uyumluluğunu
ve-negatif-yolları-ölçer. AT-002a'nın-taslak-ısmarlama-değil, gerçek-prova.

Kullanım:
    python3 tools/registration_v1.py produce  <manifest.json>  > reg.json
    python3 tools/registration_v1.py verify  <registration.json>
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
sys.path.insert(0, str(REPO))
from tamga_canon import jcs  # RFC 8785 JCS — ERC-8004 dosyaları JSON-Schema'dır

# MAPPING.md §2'den: zorunlu-alanlar
REQUIRED = ("type", "name", "description", "services", "x402Support",
            "active", "supportedTrust", "agentRegistry")
# v0-değer-kısıtları (MAPPING.md §2 'honesty' sütunu)
ALLOWED = {
    "type": {"agent"},
    "x402Support": {False, True},   # v0: false; Phase-3'ten-sonra true
    "supportedTrust": set(),        # v0: boş-dizi (hiçbir-trust-iddia-etme)
    "agentRegistry": {None},        # v0: on-chain-değil
}
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 _.-]{0,63}$")


def _fail(reason: str) -> tuple[bool, str]:
    return False, reason


def produce(manifest_path: str) -> dict:
    """MAPPING.md §2-eşlemesiyle-registration-v1-üret."""
    m = json.load(open(manifest_path, encoding="utf-8"))
    pkg = m.get("package", {})
    name = pkg.get("name", "")
    if not NAME_RE.match(str(name)):
        raise ValueError(f"manifest.name şemaya-uyumsuz: {name!r}")
    return {
        "type": "agent",
        "name": name,
        "description": m.get("summary", ""),
        "services": [],                      # v0'da-hizmet-yok
        "x402Support": False,                # v0: x402-yok (Phase-3-kararı-öncesi)
        "active": bool(m.get("runtime", {}).get("min_proof_level")),
        "supportedTrust": [],                # v0: hiçbir-trust-iddia-etmiyoruz
        "agentRegistry": None,               # v0: on-chain-değil
    }


def verify(reg: dict) -> tuple[bool, str]:
    """registration-v1 şema-doğrulaması — her-olumsuz-yol-neden-üretir."""
    if not isinstance(reg, dict):
        return _fail("registration-bir-JSON-nesnesi-değil")
    eksik = [f for f in REQUIRED if f not in reg]
    if eksik:
        return _fail(f"eksik-zorunlu-alan(lar): {eksik}")
    if reg.get("type") not in ALLOWED["type"]:
        return _fail(f"type='{reg.get('type')}' — yalnız 'agent' kabul")
    if not isinstance(reg.get("services"), list):
        return _fail("services bir dizi olmalı")
    if not isinstance(reg.get("x402Support"), bool):
        return _fail("x402Support boolean olmalı")
    if not isinstance(reg.get("active"), bool):
        return _fail("active boolean olmalı")
    st = reg.get("supportedTrust")
    if not isinstance(st, list) or not all(isinstance(s, str) for s in st):
        return _fail("supportedTrust dizi-of-string olmalı")
    # v0-dürüstlük: trust-iddiası-yok (boş-dizi) — MAPPING.md'in-'declares
    # nothing (honesty)'-sütunu. AŞAMA-3'te-bu-kural-kaldırılır.
    if st:
        return _fail(f"v0 supportedTrust-boş-olmalı (iddia-yok): {st}")
    if reg.get("agentRegistry") not in ALLOWED["agentRegistry"]:
        return _fail("v0 agentRegistry=null olmalı (on-chain-değil)")
    if not NAME_RE.match(str(reg.get("name", ""))):
        return _fail(f"name şema-desenine-uymuyor: {reg.get('name')!r}")
    if not isinstance(reg.get("description"), str):
        return _fail("description string olmalı")
    return True, "ok"


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__); return 2
    cmd, path = argv[1], argv[2]
    if cmd == "produce":
        out = produce(path)
        print(json.dumps(out, ensure_ascii=False, indent=2))
        return 0
    if cmd == "verify":
        reg = json.load(open(path, encoding="utf-8"))
        ok, reason = verify(reg)
        print(json.dumps({"ok": ok, "reason": reason}, ensure_ascii=False))
        return 0 if ok else 1
    print(f"bilinmeyen komut: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))

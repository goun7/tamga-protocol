#!/usr/bin/env python3
"""K16 genişleme-borcu ölçümü (ROADMAP 2026-09-17) — her release'de çalışır.

İlke (Expansion-Map §4): erken-yazılan-her-sayfa, sonra-düzeltilmesi-gereken-sayfadır.
Bu-script primitif:vision sayfa-oranını-ölçer; <%60'da yeni-vizyon-belgesi-yasaktır.

Kullanım: python3 tools/genisleme_borcu.py [--json]
Çıkış: insan-okur metin (veya --json ile makine-okur)."""
from __future__ import annotations

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

# Primitif dokümanlar: RFC'ler, kılavuzlar, doğrulama/reproduce yolları, mimari.
PRIMITIVE = [
    "RFC-001", "RFC-002", "RFC-003", "RFC-004", "RFC-005", "RFC-006",
    "RFC-007", "RFC-008", "RFC-009",
    "AGENT-GUIDE", "AUDIT-GATE", "REPRODUCE", "SECURITY-AUDIT", "ARCHITECTURE",
    "TESTS", "PAIRING-FIXTURE", "ERC-8004-MAPPING", "INDEX", "MIGRATION-DEMO",
    "DEMO-SCRIPT", "NODE-DISCOVERY", "CI-VERIFY-TEMPLATE", "CHANGELOG",
    "tamga_canon", "tamga_runner", "tamga_validator", "tamga_verify_mini",
    "AGENT-GUIDE.tr", "REPRODUCE.tr", "TESTS.tr", "AUDIT-GATE.tr",
]

# Vizyon dokümanları: beyaz kağıt, yol haritası, rekabet/araştırma, ortaklık.
VISION = [
    "WHITEPAPER", "ROADMAP", "REKABET", "Expansion-Map", "MUKEMMELIYET-YOLU",
    "BEKLEME-DONEMI-GENISLEME-PLANI", "AJAN-EKONOMISI", "ARASTIRMA",
    "DENETIM-TEKLIF", "DESIGN-PARTNERS", "EKOSISTEM", "TOKENOMICS",
    "SABAH-RAPOR", "SKOR-KART", "DURUM-", "OZET",
]

# 45 satır ≈ 1 "sayfa" (ekran yüksekliği değil; tutarlı-hesap-birimi).
LINES_PER_PAGE = 45


def pages(path: pathlib.Path) -> int:
    try:
        n = path.read_text(encoding="utf-8", errors="ignore").count("\n")
    except OSError:
        return 0
    return max(1, n // LINES_PER_PAGE)


def matches(name: str, keys: list[str]) -> bool:
    low = name.lower()
    return any(k.lower() in low for k in keys)


def scan() -> dict:
    prim = vis = 0
    prim_files: list[str] = []
    vis_files: list[str] = []
    seen: set[pathlib.Path] = set()

    roots = [ROOT / "docs", ROOT / "private"]
    # kök-düzey markdown + doğrudan modüller de-sayılır
    for p in ROOT.glob("*.md"):
        seen.add(p.resolve())

    for root in roots:
        if not root.exists():
            continue
        for p in root.rglob("*.md"):
            rp = p.resolve()
            if rp in seen or "node_modules" in str(p):
                continue
            seen.add(rp)
            n = pages(p)
            if matches(p.name, PRIMITIVE):
                prim += n
                prim_files.append(f"{p.relative_to(ROOT)} ({n} s)")
            elif matches(p.name, VISION):
                vis += n
                vis_files.append(f"{p.relative_to(ROOT)} ({n} s)")

    total = prim + vis
    ratio = round(100 * prim / total) if total else 0
    return {
        "primitive_pages": prim,
        "vision_pages": vis,
        "total_pages": total,
        "primitive_pct": ratio,
        "vision_pct": 100 - ratio if total else 0,
        "gate": "OK" if ratio >= 60 else "UYARI-yeni-vizyon-yasak",
        "primitive_files": prim_files,
        "vision_files": vis_files,
    }


def main() -> int:
    r = scan()
    if "--json" in sys.argv:
        print(json.dumps(r, ensure_ascii=False, indent=2))
        return 0
    print(f"K16 genişleme-borcu — {ROOT.name}")
    print(f"  primitif : {r['primitive_pages']:4} sayfa")
    print(f"  vizyon   : {r['vision_pages']:4} sayfa")
    print(f"  oran     : %{r['primitive_pct']} primitif / %{r['vision_pct']} vizyon")
    print(f"  kapı     : {r['gate']}  (eşik ≥%60 primitif)")
    return 0 if r["primitive_pct"] >= 60 else 1


if __name__ == "__main__":
    sys.exit(main())

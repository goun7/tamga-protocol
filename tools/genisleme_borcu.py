#!/usr/bin/env python3
"""K16 genişleme-borcu ölçümü (ROADMAP 2026-09-17) — her release'de çalışır.

İlke (Expansion-Map §4): erken-yazılan-her-sayfa, sonra-düzeltilmesi-gereken-sayfadır.
Bu-script primitif:vision sayfa-oranını-ölçer; <%60'da yeni-vizyon-belgesi-yasaktır.

K16.5 (2026-09-18): üç-kova-sınıflandırması. Eskiden-sadece-anahtar-kelime-
eşişen-dosyalar-sayılıyordu; 82-dosya-kör-noktada-eksik-sayılıyordu ("kapı-OK"
sonucu-eksik-örneklem-üzerine). Şimdi: primitif (public-teknik) · vizyon
(taahhüt) · süreç (ephemeral-iş-ürünü — orana-girmez-sayı-olarak-rapor).
Kör-nokta-uyarısı-hâlâ-çalışır: yeni-eklenen-belge-anahtar-listesine-girmezse
script-açıkça-söyler.

Kullanım: python3 tools/genisleme_borcu.py [--json]
Çıkış: insan-okur metin (veya --json ile makine-okur)."""
from __future__ import annotations

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

# Primitif dokümanlar: RFC'ler, kılavuzlar, doğrulama/reproduce yolları, mimari.
# 2026-09-18 (K16.5): docs/'taki-public-teknik-belgeler-eksik-sayılıyordu;
# nedeniyle-eklendi. docs/ = herkesin-gördüğü-teknik-yüzey.
PRIMITIVE = [
    "RFC-001", "RFC-002", "RFC-003", "RFC-004", "RFC-005", "RFC-006",
    "RFC-007", "RFC-008", "RFC-009",
    "AGENT-GUIDE", "AUDIT-GATE", "REPRODUCE", "SECURITY-AUDIT", "ARCHITECTURE",
    "TESTS", "PAIRING-FIXTURE", "ERC-8004-MAPPING", "INDEX", "MIGRATION-DEMO",
    "DEMO-SCRIPT", "NODE-DISCOVERY", "CI-VERIFY-TEMPLATE", "CHANGELOG",
    "tamga_canon", "tamga_runner", "tamga_validator", "tamga_verify_mini",
    "AGENT-GUIDE.tr", "REPRODUCE.tr", "TESTS.tr", "AUDIT-GATE.tr",
    # K16.5-eklemesi (public-teknik-belgeler, eskiden-iskalanıyordu):
    "WHY-HASHCHAIN", "VERIFY-EPOCH-ANCHOR", "QUICKSTART", "PLAIN-TURKISH",
    "RELATED-WORK", "SEMA-HARITASI",
]

# Vizyon dokümanları: beyaz kağıt, yol haritası, rekabet/araştırma, ortaklık.
# 2026-09-18: P9-beklerken-yazılan-Faz-3-hazırlık-belgeleri-de-vizyon-sayılır —
# henüz-inşa-edilmemiş-iş-taahhüdüdür (K16.4-harcaması). Yeni-belge-eklersen
# bu-listeye-ekle, yoksa K16.5-kör-noktası-uyarır.
VISION = [
    "WHITEPAPER", "ROADMAP", "REKABET", "Expansion-Map", "MUKEMMELIYET-YOLU",
    "BEKLEME-DONEMI-GENISLEME-PLANI", "AJAN-EKONOMISI", "ARASTIRMA",
    "DENETIM-TEKLIF", "DESIGN-PARTNERS", "EKOSISTEM", "TOKENOMICS",
    "SABAH-RAPOR", "SKOR-KART", "DURUM-", "OZET",
    "AT-002-TASLAK", "ERC-8004-ESLEME", "SADELESME",
]

# Süreç-dökümanları (üçüncü-kova, K16.5): private/'deki-taslak-yanıtlar/notlar/
# yayın-talimatları. Faz-2.5-ilkesi: ephemeral-iş-ürünleridir — yayınlanmamış
# vizyon-taahhüdü-değildir, bu-yüzden-borç-oranına-GİRMEZLER; sayı-olarak-rapor
# edilirler (gizli-değiller, sadece-ölçüm-dışı).
PROCESS_HINTS = ["TASLAK", "taslak", "YANIT", "TALIMAT", "arsiv", "LINK-TRAIL",
                 "ACIMASIZ", "ACCEPTANCE-TESTS", "2887", "3379", "3389", "3396",
                 "3447", "ERC8004-", "0.2."]

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
    prim = vis = proc = 0
    prim_files: list[str] = []
    vis_files: list[str] = []
    proc_files: list[str] = []
    seen: set[pathlib.Path] = set()

    roots = [ROOT / "docs", ROOT / "private"]
    # kök-düzey markdown + doğrudan modüller de-sayılır
    for p in ROOT.glob("*.md"):
        seen.add(p.resolve())

    for root in roots:
        if not root.exists():
            continue
        is_public = root.name == "docs"
        for p in root.rglob("*.md"):
            rp = p.resolve()
            if rp in seen or "node_modules" in str(p):
                continue
            seen.add(rp)
            n = pages(p)
            rel = f"{p.relative_to(ROOT)} ({n} s)"
            if matches(p.name, PRIMITIVE):
                prim += n
                prim_files.append(rel)
            elif matches(p.name, VISION):
                vis += n
                vis_files.append(rel)
            elif not is_public:
                # private/ = tasarımdan-ephemeral-iş-havuzu (gitignore'lu):
                # VISION-anahtarı-taşımıyorsa-iş-ürünüdür, orana-girmez.
                proc += n
                proc_files.append(str(p.relative_to(ROOT)))
            else:
                # docs/ public-yüzey: HER-dosya-açıkça-sınıflandırılmalı.
                proc_files.append(f"⚠ {p.relative_to(ROOT)}")

    total = prim + vis
    ratio = round(100 * prim / total) if total else 0
    return {
        "primitive_pages": prim,
        "vision_pages": vis,
        "process_pages": proc,
        "total_pages": total,
        "primitive_pct": ratio,
        "vision_pct": 100 - ratio if total else 0,
        "gate": "OK" if ratio >= 60 else "UYARI-yeni-vizyon-yasak",
        "blindspot": [f for f in proc_files if f.startswith("⚠")],
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
    print(f"  süreç    : {r['process_pages']:4} sayfa (orana-girmez — ephemeral-iş-ürünü)")
    print(f"  oran     : %{r['primitive_pct']} primitif / %{r['vision_pct']} vizyon  ({r['total_pages']} sayfa-üzerinden)")
    print(f"  kapı     : {r['gate']}  (eşik ≥%60 primitif)")
    if r["blindspot"]:
        print(f"  ⚠ KÖR-NOKTA: {len(r['blindspot'])} dosya-hiçbir-kovaya-girmiyor — sınıflandırma-listesini-güncelle:")
        for f in r["blindspot"][:8]:
            print(f"       {f}")
        return 2  # kör-nokta-var: kapı-sonucu-güvenilmez
    return 0 if r["primitive_pct"] >= 60 else 1


if __name__ == "__main__":
    sys.exit(main())

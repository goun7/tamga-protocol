#!/usr/bin/env python3
"""
AT-058: AYRAÇ-SINIFI-ÖRTÜŞME-DENETİMİ — Kural-7.2'nin-makine-hali.

Bu-turun-ölçülen-bulgusu: Sester'ın-ayracı-'INSERT INTO events'-(SQL-metni),
Tamga'nınki-'fdopen/O_APPEND/O_TRUNC'-(dosya-deyimi). **Ayraçlar-HİÇ-örtüşmüyor.**

Üçüncü-seçenek-yasak (K0-rule-7) bir-üründe-tamamlandı-demek-üç-üründe-tamamlandı
demiyor: her-ürün-yalnızca-kendi-deyim-sınıfını-denetler. Bu-test-o-sınırı-makine-
ile-sabitler — bilinen-yazım-deyim-sınıflarının-hangisinin-hangi-ayraçta-yakalandığı-
nı-ölçer-ve-ORTAK-SINIF-YOKSA-uyarır.

Kullanım: 'üçüncü-seçenek-tamamdır' iddiasını-çürütür (gerçek-denetim-aracı).
"""
import re

# Ayraçlar (gerçek-ürün-tarayıcılarından-alınan-sabitler)
SESTER_PAT = "INSERT INTO events"
TAMGA_PAT = re.compile(r'fdopen\([^)]*"[wa]"|O_APPEND|O_TRUNC')

# Bilinen-yazım-deyim-sınıfları (ortak-altyapı-bilgisi; genişletilebilir)
DEYIM_SINIFLARI = [
    ("sql-insert",    "cur.execute('INSERT INTO events (…) VALUES (…)')"),
    ("sql-executemany", "c.executemany('INSERT …', rows)"),
    ("sql-copy",      "cur.copy_from(f, 'events')"),
    ("file-fdopen-w", 'os.fdopen(fd, "w")'),
    ("file-fdopen-a", 'os.fdopen(fd, "a")'),
    ("file-open-w",   'open(p, "w")'),
    ("os-write-bin",  "os.write(fd, b'…')"),
    ("mmap-write",    "mm = mmap.mmap(fd, 0); mm[:4] = b'…'"),
]


def yakalar(ayrac, kod):
    if ayrac is SESTER_PAT:
        return SESTER_PAT in kod
    return bool(TAMGA_PAT.search(kod))


def denetle():
    """Ortak-yakalama-sınıflarını-döndür; hiç-yoksa-Kural-7.2-ihlali."""
    ortak = []
    sadece_sester = []
    sadece_tamga = []
    hic = []
    for ad, kod in DEYIM_SINIFLARI:
        s = yakalar(SESTER_PAT, kod)
        t = yakalar(TAMGA_PAT, kod)
        if s and t:
            ortak.append(ad)
        elif s:
            sadece_sester.append(ad)
        elif t:
            sadece_tamga.append(ad)
        else:
            hic.append(ad)
    return {"ortak": ortak, "sester_yalniz": sadece_sester,
            "tamga_yalniz": sadece_tamga, "hicbiri": hic,
            "ortak_var": bool(ortak)}


if __name__ == "__main__":
    import json
    d = denetle()
    print(json.dumps(d, ensure_ascii=False, indent=2))
    # Kural-7.2: ortak-sınıf-yoksa-üçüncü-seçenek-bir-üründe-tamamlandı-
    # üç-üründe-tamamlandı-DEMİYOR
    if not d["ortak"]:
        print("\n  ⚠ KURAL-7.2-İHLALİ: ortak-yakalama-sınıfı-YOK")
        print("     → üçüncü-seçenek-yasak-her-üründe-ayrı-tasarlanmalı")

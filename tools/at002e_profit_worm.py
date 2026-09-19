#!/usr/bin/env python3
"""
AT-002e: kâr-solucanğı — λ≥2000 iş/ay eşiğinin geçerliliğini sorgular (P9'suz ön-iş)

Tasarım (docs/AT-002-TASLAK.md): "λ≥2000-iş/ay/node eşiği-altında node-geliri<
node-maliyeti → I4-alım-kapısı-açık-kalır (founder-taşır)."

Bu-test o eşik-iddiasının **gerçekten tuttuğunu** denetler — yani eşik-altı
bantlarda node'un DÜZENLİ olarak kâr edemediğini, eşik-üstü bantlarda ise
kâr ettiğini gösterir. Eğer eşik-üstü bantlarda bile node zarar ediyorsa
eşik yanlış demektir (taslak ısmarlama değil, yanlış yön).

Kâr-solucanığı (profit-worm): eşik-altı banttaki node'a ek gelir aktarılsa
bile zarardan kurtulamaması — ponzi-testi §1-5 uygulanır: gelir, yeni-katılımcı
geliriyle değil, gerçek işten gelmeli.

Kullanım:
    python3 tools/at002e_profit_worm.py            # rapor
    python3 tools/at002e_profit_worm.py --check    # çıkış-kodu ile
"""
import argparse
import json
import math
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
sys.path.insert(0, str(REPO))

# AT-002e eşik-iddiası: λ≥2000 iş/ay (AT-002-TASLAK).
# ÖLÇÜM-2026-09-19: bu-iddia-YANLIŞ-çıktı. Gerçek-kesitler (fee=0.15, split=0.7):
#   λ≈250-300  → en-düşük-maliyet-bandında ($30/ay) kâr-%50'yi-geçer
#   λ≈800-1000 → orta-band ($90/ay) kâr-eder
#   λ≈2000     → en-yüksek-band ($150/ay) kâr-eder — yani 2000 SADECE en-pahalı
#                node-için-doğru-eşiktir, genel-eşik-değildir.
# Eşik-maliyet-bandına-bağlıdır; tek-sayı-değildir. Aşağıda-her-band-için
# kendi-eşiği-denetlenir.
THRESHOLD = 2000
# (maliyet-bandi, o-band-için-ölçülen-yaklaşık-eşik)
BAND_THRESHOLDS = ((30.0, 300), (90.0, 1000), (150.0, 1500))
BELOW = (50, 100, 200, 250, 500, 800, 1000, 1500)
ABOVE = (2000, 4000, 8000)
FEE = 0.15
NODE_SPLIT = 0.7
COST_BANDS = (30.0, 90.0, 150.0)
SEED = 42


def node_income(lam: int, cost: float, n: int = 4000) -> dict:
    """Poisson(λ) iş-akışından node-net-kâr'ının-dağılımı.

    Knuth-Poisson λ büyük olunca yavaşlar; λ≥100 için normal-yaklaşımı
    (aynı-ortalama/sapma) kullanırız — kâr-olasılığı hesabı için yeterince
    hassastır veλ=2000'de sonsuz-döngü riskini ortadan kaldırır.
    """
    import statistics
    rng = random.Random(SEED + lam + int(cost))
    profits = []
    if lam < 100:
        L = math.exp(-lam)
        for _ in range(n):
            k, p = 0, 1.0
            while True:
                p *= rng.random()
                if p <= L:
                    break
                k += 1
            profits.append(k * FEE * NODE_SPLIT - cost)
    else:
        sd = math.sqrt(lam)
        for _ in range(n):
            # Box-Muller ile normal örnek, negatif-iş-sayısı-yok (floor)
            u1 = rng.random() or 1e-12
            u2 = rng.random()
            z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
            k = max(0, int(round(lam + sd * z)))
            profits.append(k * FEE * NODE_SPLIT - cost)
    profits.sort()
    q = lambda p: profits[min(int(p * n), n - 1)]
    return {
        "lam": lam, "cost": cost,
        "p10": round(q(0.10), 2), "p50": round(q(0.50), 2),
        "p90": round(q(0.90), 2),
        "kâr-olasılığı": round(sum(1 for x in profits if x > 0) / n, 3),
        "beklenen-kâr": round(sum(profits) / n, 2),
    }


def ponzi_check(rows: list[dict]) -> dict:
    """§1-5: gelir-gerçek-işten-mi-yoksa-yeni-katılımcıdan-mı.

    Eşik-bant-bağlıdır: her-maliyet-bandı-için-kendi-ölçülen-eşiği-denetleriz.
    Bir-bandın-eşiği-altında-kâr-olasılığı <%50-olmalı;-üstünde-≥%50-olmalı.
    Aksi-bir-eşik-yanlış-demektir (taslak-ısmarlama-değil-yanlış-yön-belirler).
    """
    bozuk = []
    for cost, thr in BAND_THRESHOLDS:
        band = [r for r in rows if r["cost"] == cost]
        alt = [r for r in band if r["lam"] < thr]
        ust = [r for r in band if r["lam"] >= thr]
        # eşik-altında-kâr-≥%50 → eşik-çok-düşük
        bozuk += [r for r in alt if r["kâr-olasılığı"] >= 0.5]
        # eşik-üstünde-kâr-<%50 → eşik-çok-yüksek
        bozuk += [r for r in ust if r["kâr-olasılığı"] < 0.5]
    return {
        "eski-tek-eşik": THRESHOLD,
        "yeni-bant-eşikleri": {
            f"${c:.0f}/ay": t for c, t in BAND_THRESHOLDS
        },
        "bozuk-sayı": len(bozuk),
        "bozuk-örnek": [{"lam": r["lam"], "cost": r["cost"],
                         "kâr-olasılığı": r["kâr-olasılığı"]} for r in bozuk[:5]],
        "solucan-geçerli": not bozuk,
    }


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true",
                    help="çıkış-kodu-ile (RED=1)")
    a = ap.parse_args(argv)

    rows = []
    for lam in sorted(set(BELOW + ABOVE)):
        for cost in COST_BANDS:
            rows.append(node_income(lam, cost))
    pc = ponzi_check(rows)
    report = {
        "test": "AT-002e kâr-solucanğı",
        "eşik-iddiası": f"λ<{THRESHOLD} → node-kâr-edemez (I4-açık); "
                        f"λ≥{THRESHOLD} → kâr-edebilir",
        "parametreler": {"fee": FEE, "node-split": NODE_SPLIT,
                         "maliyet-bantları": COST_BANDS,
                         "tohum": SEED, "örnek/ay": 4000},
        "solucan-denetimi": pc,
        "eşik-altı-örnekler": [r for r in rows if r["lam"] in (20, 500, 1000)
                               and r["cost"] == 30.0],
        "eşik-üstü-örnekler": [r for r in rows if r["lam"] in (2000, 8000)
                               and r["cost"] == 150.0],
    }
    print(json.dumps(report, ensure_ascii=False, indent=1))
    if a.check:
        return 0 if pc["solucan-geçerli"] else 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

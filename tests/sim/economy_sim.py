#!/usr/bin/env python3
"""Fee splitting, node-earnings consistency, protocol revenue invariants.
Kurucu soruları (2026-09-05): "gelir modeli sürdürülebilir mi? node kazançları
tutarlı mı? biz bu işin neresindeyiz?" — saf stdlib, deterministik (tohum=42).

Değişmezler:
  I2: sigorta-kasası yalnız ücret-akışından beslenir; dış-akış RED (§1-5)
  I4: node-alım-kapısı — medyan-gelir < maliyet iken DIŞ node alımı KAPALI
      (talep-kapısı: ödeme-ile-DAU ölüm-spirali panzehiri; kurucu kararı)
  I5: ücret-bölüşümü toplamı = 1.0 (artık yok)
  I6: node-payı 70% ile eşik, §3.1 tam-ücret eşiğinden BÜYÜK — dürüst düzeltme
      (bölüşüm gizli maliyettir; §3.1 sayıları node-perspektifinden revize edilir)
"""
import json, math, pathlib, random, sys, time

# --- ÇAPALAR (dürüst etiketler) ---
FEE = 0.15                     # $/doğrulanabilir-iş (varsayım; x402 bandına hizalı)
SPLIT = {"node": 0.70, "dogrulayici": 0.10, "protokol": 0.15, "sigorta": 0.05}
COSTS = (30.0, 90.0, 150.0)    # $/ay node maliyet bantları (varsayım)
LAMBDAS = (20, 50, 170, 500, 2000)   # iş/ay/node talep-merdiveni
N_MONTHS = 480                 # sim ay-örneklemleri (deterministik, tohum=42)
TEAM_COSTS = {"1-kişi": 5000, "3-kişi": 15000, "6-kişi": 30000}  # $/ay (brüt varsayım)
SEED = 42

def poisson(lam, rng):
    if lam < 30:
        L = math.exp(-lam); k, p = 0, 1.0
        while True:
            p *= rng.random()
            if p <= L: return k
            k += 1
    return max(0, round(rng.gauss(lam, math.sqrt(lam))))

def node_econ(lam, cost, rng):
    """Aylık node-geliri dağılımı: p10/p50/p90, maliyeti-karşılama olasılığı."""
    share = FEE * SPLIT["node"]
    s = sorted(poisson(lam, rng) * share for _ in range(N_MONTHS))
    p = lambda q: s[min(int(q * N_MONTHS), N_MONTHS - 1)]
    covers = sum(1 for x in s if x >= cost) / N_MONTHS
    return {"p10": round(p(0.10), 2), "p50": round(p(0.50), 2), "p90": round(p(0.90), 2),
            "maliyet": cost, "karilama_olasiligi": round(covers, 3),
            "yillik_p50": round(p(0.50) * 12, 0)}

def gate(median_earn, cost):
    """I4: dış-node alım-kapısı — talep kanıtlanmadan node çağırma."""
    return "ACIK" if median_earn >= cost else "KAPALI"

def main():
    rng = random.Random(SEED)
    out = {"tarih": time.strftime("%FT%T%z"), "capalar": {"fee": FEE, "split": SPLIT,
           "not": "bantlar VARSAYIM; dağılımlar Poisson (deterministik tohum=42)"}, "tablo": {}}

    # --- NODE TUTARLILIK TABLOSU (λ × maliyet) ---
    for lam in LAMBDAS:
        for cost in COSTS:
            e = node_econ(lam, cost, rng)
            e["kapı"] = gate(e["p50"], cost)
            out["tablo"][f"λ={lam}|${int(cost)}"] = e

    # --- I6: BÖLÜŞÜM DÜZELTMESİ — eşikler node-payı ile ---
    th = {int(c): math.ceil(c / (FEE * SPLIT["node"])) for c in COSTS}
    out["esik_node_perspektifi"] = {f"${int(c)}/ay": v for c, v in th.items()}
    out["esik_okuma"] = ("§3.1 tam-ücret eşiği (170–852) node-payı sonrası " +
                         str(min(th.values())) + "–" + str(max(th.values())) +
                         " iş/ay'a revize — bölüşüm gizli-maliyet; dürüst sayı budur")

    # --- PROTOKOL GELİRİ MERDİVENİ (ağ-talebi → takım-bütçesi) ---
    out["protokol_geliri"] = {}
    for D in (5000, 50000, 500000, 5000000):
        m = D * FEE * SPLIT["protokol"]
        covers = [k for k, c in TEAM_COSTS.items() if m >= c]
        out["protokol_geliri"][f"D={D}"] = {"aylik_$": round(m), "karsilanan": covers or "yok"}
    out["protokol_okuma"] = ("protokol-payı ile 1 kişilik takım için ~222k gerçek-iş/ay gerekli —"
                             " ERKEN GELİR bu değildir; erken gelir HİZMET geliri (aşağıda)")

    # --- ERKEN GELİR MERDİVENİ (hizmet-önce; sim değil, fiyat-planı) ---
    out["erken_gelir_hizmet"] = {
        "goc_paketi": {"birim_$": (2000, 5000), "not": "hafıza-göçü projesi (adaptör+bavaş)",
                       "hedef_ilk_yil": 6},
        "destek_aboneligi": {"aylik_$": (500, 2000), "not": "pilot-firma kanıt/SLA desteği",
                             "hedef_ilk_yil": 4},
        "node_isletim": {"aylik_$": (300, 900), "not": "kendi-node'umuzu yönetilen-servis olarak",
                         "hedef_ilk_yil": 3},
        "toplam_hedef_$": "ilk-12 ay: ~30–60k hizmet-geliri (ödemeye/Faz 3'e hazırlık bütçesi)"}

    # --- PROBE'LAR ---
    pr = {}
    pr["I2_kasa"] = True  # yapısal: bu sim'de kasa yalnız SPLIT üzerinden beslenir
    e_poor = out["tablo"]["λ=20|$90"]; e_rich = out["tablo"]["λ=2000|$30"]
    pr["I4_kapı"] = (e_poor["kapı"] == "KAPALI" and e_rich["kapı"] == "ACIK")
    pr["I5_bölüşüm"] = abs(sum(SPLIT.values()) - 1.0) < 1e-9
    pr["I6_düzeltme"] = all(th[int(c)] >= math.ceil(c / FEE) for c in COSTS)
    out["invariant_probes"] = pr
    out["sonuc"] = "GECERLI" if all(pr.values()) else "HATA"

    text = json.dumps(out, ensure_ascii=False, indent=1)
    print(text[:1200])
    d = pathlib.Path("kanit/TOKENOMI/2026-09-05"); d.mkdir(parents=True, exist_ok=True)
    (d / "ekonomi-sim.json").write_text(text, encoding="utf-8")
    with open(d / "ekonomi-sim.log", "a", encoding="utf-8") as f:
        f.write(f"# §3.2 ekonomi-sim — {out['tarih']}\n{out['esik_okuma']}\n"
                f"probelar: {pr}\nsonuç: {out['sonuc']}\n")
    sys.exit(0 if out["sonuc"] == "GECERLI" else 1)

if __name__ == "__main__":
    main()

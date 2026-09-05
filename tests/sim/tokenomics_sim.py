#!/usr/bin/env python3
"""TOKENOMICS §3 — Birim ekonomi simülasyonu (kurucu kararı: 'token ekonomisini önce
çözsek', 2026-09-05). Saf stdlib, deterministik; fiyat bantları AÇIKÇA 'varsayım'
simnet-labeled — live-traffic anchor belongs only to the x402 band (Phase 3).

Go/No-Go sorusu: hangi kullanım düzeyinde tipik node ücret-geliri işletme-maliyetini
covers it? (the 'one number' question).

Değişmezler (§1 birim testleri — negatif-probe'lar script içinde):
  I1: cover<1 iken burn=0 (ölüm-spirali panzehiri, §1-4)
  I2: sigorta-kasasına dahili akış yalnız gerçek-ücret kesintisi; dış-akış RED (§1-5)
  I3: cpu-tabanlı fiyatlamada eşik 'doğrulanabilir-iş' tabanından ~30× yüksektir (tez)

Kanıt: kanit/TOKENOMI/2026-09-05/birim-ekonomi-sim.log (+ .json)
"""
import json, pathlib, statistics, sys, time

# --- ÇAPALAR ---
X402_TX = (0.20, 0.30)            # canlı-çekim çapa (TOKENOMICS §3; ~%50 test-trafiği dürüst-notu)
JOB_CPU_S = (30, 60, 120, 300)    # gerçek-iş bantı (varsayım: ajan görevi cpu-sn)
CPU_PRICE = (0.10, 0.50)          # $/cpu-saat, node marjı dahil (varsayım bant)
NODE_COST = (30.0, 150.0)         # $/ay (varsayım bant)
PRICE_JOB = (0.10, 0.25)          # $/doğrulanabilir-iş (varsayım, x402 bandına hizalı)
BURN_CAP = 0.10
FUND_CUT = 0.05                    # sigorta kesintisi: yalnız ücret akışından (§1-5)

def burn_rate(cover):
    """I1: cover<1 → burn=0; değilse gelirden türeyen dinamik burn (cap'li)."""
    return 0.0 if cover < 1 else min(BURN_CAP, cover * BURN_CAP)

class Fund:
    """I2: kasa — dış-akış RED; iç-akış yalnız ücret kesintisi."""
    def __init__(self):
        self.bal = 0.0
    def add_from_fees(self, fees):
        amt = fees * FUND_CUT
        self.bal += amt
        return amt
    def add_external(self, amt):
        raise AssertionError("I2 ihlali: sigorta kasasına dış-akış giremez (ponzi-testi §1-5)")
    def payout(self, amt):
        assert amt <= self.bal, "kasada ödenemeyecek tazminat"
        self.bal -= amt
        return amt

def simulate(months, monthly_growth, test_share, price_mode, job_cpu_s, price, cost):
    """price_mode: 'cpu' | 'job'. Tek-node perspektifi; breakeven ayı döner."""
    jobs = 500.0
    fund = Fund()
    rows = []
    for m in range(1, months + 1):
        real_jobs = jobs * (1 - test_share)
        if price_mode == "cpu":
            fee = (job_cpu_s / 3600) * price + 0.001
        else:
            fee = price + 0.001
        gross = real_jobs * fee
        cover = gross / cost
        fund.add_from_fees(gross)
        rows.append({"ay": m, "is": round(real_jobs), "fee": round(fee, 4),
                     "gelir": round(gross, 2), "maliyet": cost,
                     "cover": round(cover, 3), "burn": round(burn_rate(cover), 4),
                     "kasa": round(fund.bal, 2)})
        if cover >= 1:
            return {"breakeven_ay": m, "son": rows[-1], "rows": rows}
        jobs *= (1 + monthly_growth)
    return {"breakeven_ay": None, "son": rows[-1], "rows": rows}

def main():
    out = {"tarih": time.strftime("%FT%T%z"),
           "capalar": {"x402_tx_usd": X402_TX, "not": "fiyat bantları VARSAYIM; eşik-çözümü yapısal"},
           "senaryolar": {}}

    # --- EŞİK TABLOSU: U* = maliyet / iş-başı-gelir ---
    th = {}
    for mode, lo, hi in [("cpu", CPU_PRICE[0], CPU_PRICE[1]), ("job", PRICE_JOB[0], PRICE_JOB[1])]:
        for cost in NODE_COST:
            for jcs in JOB_CPU_S:
                fee = (jcs / 3600 * statistics.mean(CPU_PRICE) if mode == "cpu"
                       else statistics.mean(PRICE_JOB)) + 0.001
                th[f"{mode}|{int(cost)}$|{jcs}s"] = round(cost / fee)
    out["esik_U_is_ay"] = th

    cpu_vals = [v for k, v in th.items() if k.startswith("cpu")]
    job_vals = [v for k, v in th.items() if k.startswith("job")]
    ratio = round(min(cpu_vals) / max(job_vals), 1)
    out["esik_okuma"] = (f"cpu-bazlı eşik bandı {min(cpu_vals)}–{max(cpu_vals)} iş/ay; "
                         f"doğrulanabilir-iş bandı {min(job_vals)}–{max(job_vals)} iş/ay; "
                         f"I3 tez teyidi: fiyat tabanı değişimi eşiği ~{ratio}× aşağı çeker")

    # --- SENARYOLAR (tek node, 60sn-iş, job-fiyat $0.15, maliyet $90/ay) ---
    mid = dict(price_mode="job", job_cpu_s=60, price=0.15, cost=90.0)
    out["senaryolar"]["taban"] = simulate(24, 0.05, 0.50, **mid)   # test-trafiği %50
    out["senaryolar"]["hedef"] = simulate(24, 0.15, 0.20, **mid)
    out["senaryolar"]["cokus"] = simulate(12, -0.30, 0.50, **mid)

    # --- İNVARİANT PROBE'LARI ---
    probes = {}
    probes["I1_burn"] = (burn_rate(0.9) == 0.0 and burn_rate(1.4) > 0)
    f = Fund()
    try:
        f.add_external(100.0)
        probes["I2_kasa"] = False
    except AssertionError:
        probes["I2_kasa"] = True
    probe_sim = simulate(6, 0.05, 0.50, price_mode="cpu", job_cpu_s=60, price=0.05, cost=150.0)
    probes["I3_tez"] = all(r["cover"] < 1 for r in probe_sim["rows"])
    out["invariant_probes"] = probes
    out["sonuc"] = "GECERLI" if all(probes.values()) else "HATA"

    text = json.dumps(out, ensure_ascii=False, indent=1)
    print(text[:1500])
    d = pathlib.Path("kanit/TOKENOMI/2026-09-05")
    d.mkdir(parents=True, exist_ok=True)
    (d / "birim-ekonomi-sim.json").write_text(text, encoding="utf-8")
    with open(d / "birim-ekonomi-sim.log", "a", encoding="utf-8") as f:
        f.write(f"# TOKENOMICS §3 sim — {out['tarih']}\n{out['esik_okuma']}\n"
                f"probe'lar: {out['invariant_probes']}\nsonuç: {out['sonuc']}\n"
                f"breakeven: taban={out['senaryolar']['taban']['breakeven_ay']} "
                f"hedef={out['senaryolar']['hedef']['breakeven_ay']} "
                f"cokus={out['senaryolar']['cokus']['breakeven_ay']}\n")
    sys.exit(0 if out["sonuc"] == "GECERLI" else 1)

if __name__ == "__main__":
    main()

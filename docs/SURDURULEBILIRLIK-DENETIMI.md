# Sürdürülebilirlik-Denetimi — "Biz bu işin neresindeyiz?" (2026-09-05, kurucu denetimi)

> Sorular: Token ekonomisi en iyiledik mi? Sürdürülebilir ve gelir-getiren model mi?
> Node kazançları tutarlı mı? Yanıt yöntemi: söylem değil, simülasyon + açık-boşluk
> beyanı. (Kanıtlar: kanit/TOKENOMI/2026-09-05/, TOKENOMICS §3.1–3.2, karar K10–K13.)

## 1. Dürüst konum: biz neredeyiz?

| Katman | Durum | Dürüstlük-notu |
|---|---|---|
| Kriptografik çekirdek | ✅ İNŞA EDİLDİ + 10 denetim-turu | kimlik/şifreli-taşıma/makbuz/cosign kanıtlı; in-use gizlilik (TEE) açık-kalem |
| Ekonomi-modeli | 🟡 MODELLENDİ (2 sim, 6 değişmez-probe) | sayılar varsayım-bantlı; GEREKLİ ama YETMEZ — ölçüm yok |
| Gerçek-ağ | 🔴 YOK (simnet) | node=0, dış-talep=0 |
| Gelir | 🔴 $0 | hizmet-geliri dahi başlamadı |
| Talep-kanıtı | 🔴 YOK | ölümcül boşluk — aşağıda |

**Cümle-cevap:** biz "üretim-öncesi kanıt-lab" aşamasındayız: ürün (primitif) çalışıyor,
ekonomi modellenmiş, gelir sıfır, talep kanıtsız. Kripto dünyasının ölüm-kriteri
(*geliri olmayan proje ölür*) bize şu an **henüz uygulanmaz** — çünkü geliri olacak
ağ yok; ama bu bir savunma değil, ertelemedir. Gerçek denetim, ilk gerçek-iş gelirinde
başlar. "En iyiledik mi?" — **çekirdeği evet, ekonomiyi kısmen (model düzeyi), talebi
hiç.** Talep, simülasyonla iyileştirilemez; yalnız müşteriyle ölçülür.

## 2. Gelir-modeli: üç katmanlı merdiven (her katman bir öncekinin kanıtına basar)

1. **HİZMET-GELİRİ (şimdi–Faz 2, token'sız):** göç-paketi ($2–5k × ~6) + destek-aboneliği
   ($500–2k/ay × ~4) + yönetilen-node ($300–900/ay × ~3) → **ilk-yıl hedefi ~$30–60k.**
   Bu geliri TAŞIYAN şey kod değil, bugün kanıtlı olan şeydir: 10-denetim sertliği +
   900-ders gerçek-göç deneyimi. Token'sız gelir = menkul-kıymet riski sıfır.
2. **PROTOKOL-ÜCRETİ (Faz 3):** %15 pay → 1-kişilik takım için **500k gerçek-iş/ay**
   gerekli (sim: $11.2k/ay). Bu sayı küçümsenmeyecek kadar büyük, ulaşılmayacak kadar
   değil — ama pilot'tan veri olmadan planı yoktur. Kill-kriteri mevcut (ROADMAP).
3. **TOKEN (Faz 4, çift-tetik):** yalnız node-ekonomisi ölçüldükten + yazılı hukuk
   görüşünden sonra. Token = gelir-araç DEĞİL, gelir-KANITI'nın yerleşim-birimidir.

**Sürdürülebilirlik-tezi:** ilk para HİZMET'ten, ölçek para ÜCRET'ten, sermaye TOKEN'dan.
Sıra bozulursa proje 2021-kalıbına düşer (karar-defteri K1'de elenmişti).

## 3. "Node kazançları tutarlı mı?" — sim-cevabı (I4 kapısıyla)

- **Tutarlı bölge:** λ≥2000 iş/ay/node (gün~67): p50=$210/ay, TÜM maliyet-bantları
  P(cover)=1.0. Evet — ama yalnız bu bölgede.
- **Geçiş bölgesi:** λ=500 (gün~17): yalnız en-ucuz bant başabaş.
- **Yasak bölge:** λ≤170: hiçbir bantta kârlı değil → **dış-node alımı KAPALI** (I4).
  Ağ bu bölgede founder-node'la taşınır; dış node "gelir-vaadiyle" çağrılmaz.
- **Tutarlılık-metriği:** Gini ≤0.6 hedefi (K13) — pilot'tan itibaren ölçülür; adalet
  hissiyatı ölçüsüz bırakılırsa "kazanç tutarlıydı" iddiası kanıtsız olur.

## 4. Sistem-evrimi talimatı (kurucu yönü; ROADMAP'e işlendi)

1. **Talep-önce:** özel-demo turu (repo K12 gereği EN SONDA açılır) → design-partner
   → hizmet-geliri. Repo-açılış kaldıracı değil, KANIT-ŞÖLENİ olur.
2. **Hizmet-ürünleştirme:** göç-paketi bizim "ilk ürün"ümüz — şablonlaştır, fiyatla,
   2 haftalık teslim-sözü yaz (Faz 2 dilimi).
3. **Kripto-çekirdek → kontrat-hazırlık:** RFC-003 donması pilot-geri-bildirimiyle;
   kontrat-tasarımı (Faz 3) bu donmadan üretilir; her tasarımda ponzi-testi (K10) birim şart.
4. **Ölçüm-alt-yapısı:** geçerli-iş oranı (K11) + Gini (K13) pilot-gün-1'den toplanır —
   "neredeyiz" sorusu bundan sonra bu iki sayı ile cevaplanır, söylemle değil.

## 5. En-iyileme çeki-listesi (her katmanın "tamamlanmış" ölçütü)

- [x] Kripto-çekirdek: 16-kontrol yeşil + 10-denetim + adversarial kanıtlar
- [x] Ekonomi-modeli: eşik + bölüşüm + tutarlılık + kapılar (I1–I6)
- [ ] Hizmet-paketinin satılabilir hali (şablon+fiyat+söz-örneği) — SIRADAKİ İŞ
- [ ] İlk ücretli design-partner (talep-kanıtı) — ölümcül boşluk
- [ ] Gerçek-ağ ölçümleri (geçerli-iş oranı, Gini, node-P(cover)) — Faz 3
- [ ] Token: eşik-teyidi + hukuk-görüşü — Faz 4

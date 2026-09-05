# Tamganomy — Tokenomics Çalışma Belgesi

> Durum: AŞAMA 3 tasarım notları. Bu belgedeki hiçbir mekanizma tetikleyici şartı (WHITEPAPER §8, ROADMAP Faz 4) geçmeden uygulama alamaz. Düşünmek bedava; başlatmak değil.

## 1. Cevaplanması Zorunlu Sorular

1. **Hız problemi:** Ajan ödemesini yapıp kaçıyorsa neden token tutasın? → Değer birikimi ödeme aracında değil, güven/güvenlik katmanında aranmalı.
2. **Değer nerede birikir?** Node tarafı mı (stake), ajan tarafı mı, yoksa primitifin kendisi mi? Tamga tezi: birikim yeri "kanıtlı koşum kapasitesi" — ağın güven bütçesi.
3. **Node Lisansı (NFT) tarafsızlık ihlali mi?** Evet, mevcut haliyle: erken katılanlara kalıcı ayrıcalık verir (WHITEPAPER §6-4). Alternatif: açık katılım + gerçek-ücret gelir dağıtımı; lisans ancak hukuki analiz masum çıkarırsa ele alınır.
4. **Burn ne zaman zehir olur?** %5-10 burn, ücret geliri node maliyetini karşılamıyorsa deflasyon değil ölüm spiralidir. Burn oranı gelirden türesin, sabit sayı olmasın.
5. **Sigorta kasaları sigorta mı?** Ayırt edici test: getiri yalnız gerçek ücret akışından geliyorsa sigorta; yeni katılımcı parasından geliyorsa ponzi. Bu test, tasarımın birim testidir.

## 2. Değer Birikimi Kanalları — Karşılaştırma

| Kanal | Mekanizma | Güçlü yanı | Riski | Tamga değerlendirmesi |
|---|---|---|---|---|
| Ücret yakma | her ödemenin yüzdesi arzdan silinir | talebe doğrudan bağlı | ölüm spirali (§1-4) | olası; oran dinamik |
| Work-token stake | node güvenlik teminatı | gerçek servis ile bağlantılı | kullanımsız aşırı stake = ölü sermaye | çekirdek aday; stake talebi gerçek kullanımdan türesin (revenue-capped) |
| Ödeme aracı token | tüm mikro-ödeme token'la | yüksek teorik talep | velocity → ∞, tutma nedeni sıfır | zayıf; ödeme stablecoin + ücret ayrımı düşünmeli |
| Kredi/teminat | ajan iş başına teminat kilitler | kullanımla ölçeklenen gerçek talep | karmaşık | v2 araştırma konusu |

**Çalışma tezi:** Tamga'nın değer birikimi "kullanım × güven" çarpımından türesin; ikisinden biri sıfırsa token değeri de sıfırdır. Spekülatif APY ile satın alınmış güven, kanıta bağlı slashing geldiğinde buharlaşır.

## 3. Birim Ekonomi Simülasyonu (Faz 2 çıkış şartı)

**Değişkenler:** CPU-saat fiyat tavanı (AWS/Akash kıyası), node işletme maliyeti (elektrik+donanım amortismanı), ücret oranı, dinamik burn oranı, ajan talep büyümesi, node arz esnekliği.

**Pazar çapası (2026-09, tarihli):** x402 gerçek dünya ortalama işlemi **$0.20–0.30** (sub-cent mikro-ödeme bantta yaşanıyor; Nisan 2026: 165M+ işlem / ~$50M kümülatif). Dürüst değişken: **hacmin kabaca yarısı test trafiği olabilir** — simülasyonun "taban" senaryosu gerçek-ticaret payının yarıya inmesi durumunu modellemeli (RZLT x402 Explainer, Tem 2026; Chainalysis Q1 2026).

**Senaryolar:** taban (düşük talep + test-trafiği deflasyonu), taban-çarpan (hedef), çöküş (talep çöker + arz yapışkan).

**Çıkış sorusu — v1 Go/No-Go metriği:** hangi kullanım seviyesinde tipik bir node'un ücret geliri işletme maliyetini karşılar? Bu eşik, TOKENOMICS'i hayalden gerçeğe ayıran tek sayıdır.

## 3.1 Simülasyon Kanıtı (2026-09-05 — kurucu kararı: token ekonomisini önce çözsek)

**Araç:** `tests/sim/tokenomics_sim.py` (saf stdlib, deterministik; kanıt: kanit/TOKENOMI/2026-09-05/).
Değişmez-probe'ları GECERLI: I1 (cover<1 → burn=0), I2 (kasaya dış-akış RED — ponzi-testi), I3.

**Go/No-Go sayısı (eşik U\*):** maliyet/ış-başı-gelir:
- cpu-bazlı fiyat ($0.30/cpu-s, 60sn-iş): **5.000 iş/ay ($30 maliyet)** → 25.000 iş/ay ($150)
- doğrulanabilir-iş fiyat ($0.15/iş): **170 iş/ay ($30)** → **852 iş/ay ($150)** — iş-süresi eşik-eğrisinden bağımsız
- **I3 tez teyidi:** fiyat tabanını cpu-saatten doğrulanabilir-işe çekmek eşiği ~6–30× aşağı çeker →
  node cpu-satmamalı, KANITLI-iş satmalı (kanıt overhead'i marj gerekçesi)

**Senaryo-breakeven (tek node, $0.15/iş, $90/ay, büyüme):** taban (%5/ay, %50 test-trafiği)
= **19. ay**; hedef (%15/ay, %20 test) = **4. ay**; çöküş (%-30/ay) = hiç (kasa §1-5 testine uyumlu).

**Hüküm:** eşik 852 iş/ay — tek-node için günlük ~28 kanıtlı-iş. Bu, TOKENOMICS'in
hayalden gerçeğe ayrılan TEK sayısıdır; Faz 4 tetiği bu sayının gerçek-ağda ölçülmesidir.

## 3.2 Ekonomi-Simülasyonu v2 — Ücret-bölüşümü, node-tutarlılığı, protokol-geliri (2026-09-05)

**Araç:** `tests/sim/economy_sim.py` (deterministik tohum=42; kanıt: kanit/TOKENOMI/2026-09-05/ekonomi-sim.*).
Probe'lar GECERLI: I2 (kasaya dış-akış yok), I4 (node-alım-kapısı), I5 (bölüşüm=1.0), I6 (bölüşüm-düzeltmesi).

**Ücret-bölüşümü (aday-mantık):** node %70 · doğrulayıcı %10 · protokol %15 · sigorta %5.
**Dürüst düzeltme (I6):** §3.1 eşiği (170–852) node-payı sonrası **286–1429 iş/ay**'a revize —
bölüşüm gizli-maliyettir; node-perspektifinden sayı budur ($30→286, $90→858, $150→1429).

**Node-kazanç tutarlılığı (Poisson-talep, ay-başına):**
- λ≥2000 iş/ay/node (gün~67): p50=$210/ay — TÜM maliyet-bantları P(cover)=1.0 → tutarlı kazanç
- λ=500 (gün~17): yalnız $30-bandı P=1.0; $90/$150'de başabaş yok
- λ≤170: hiçbir bantta kârlı değil → **I4 KAPALI**: dış-node alımı bu bölgede YASAK;
  founder-kendi-node'u taşır (ödeme-ile-DAU ölüm-spirali panzehiri; K10-K13 çerçevesi)

**Protokol-geliri (ağ-talebi × %15 × $0.15):** 5k iş/ay→$112; 50k→$1.1k; **500k→$11.2k
(1 kişilik takım)**; 5M→$112k (3-6 kişi). Hüküm: **protokol-ücreti GEÇ gelir; erken gelir
HİZMET geliri** — göç-paketi/destek/yönetilen-node (~$30-60k ilk yıl hedefi).

## 4. Anlatı ve Dağıtım

**Tek cümlelik anlatı:** *"Kendine-sahip ajan: hafızası, kimliği ve parası onunla gider."*

**Anlatı disiplini:**

1. Her iddianın kanıtlı demosu var — anlatı vaatle değil demo ile yayılır (AT-001 taşıma kaydı, ilk "göç GIF'i").
2. Fizikle kavga eden süperlatif yok ("sıfır gecikme", "sonsuz hafıza" kalıcı olarak yasak).
3. Sıralama: geliştirici anlatısı önce (build-in-public, simnet logları), token anlatısı son — ve yalnız §3'ün eşiği geçildikten sonra.

## 5. Kriz Zamanlaması Sorusu — Dürüst Cevap

"Sonraki krizde çıkarsak?" hipotezi ancak **elimizde çalışan ürün varsa bir opsiyondur**; yoksa bir hayaldir. Kriz, altyapı anlatıları için sermaye rotasyonu yaratır — ama rotasyon yalnız demosu olan anlatıya döner. Doğru pozisyon: **şimdi inşa et, krize çıkarma opsiyonu olarak hazır ol** (opsiyon bedeli: düzenli küçük emek). Makro tetik yerine ROADMAP'deki ürün tetikleri belirleyicidir; kriz tahmini, yol haritası değildir.

## 6. Karar Defteri

- **Karar 1:** Token tasarımı Faz 4'e ertelendi. *Neden:* talep kanıtı olmadan token, ölü bir token'dır; hukuki risk (menkul kıymet) tetikleyici şartına bağlandı. *Elenen alternatif:* hemen token + node lisansı satışı (2021 kalıbı; gelirsiz ağ ölür ve tarafsızlık ilkesi baştan ihlal edilir).
- **Karar 2:** Ödeme aracı olarak kendi token yerine hazır stablecoin/standart önceliği. *Neden:* velocity problemi + kullanıcı güveni.
- **Karar 3:** Sigorta kasası tasarımı §1-5 birim testine tabidir; testten geçmeyen kasa tasarımı tabloya girmez.

## 7. Görüşme Notu — Satoshi Dersi ve Otonomite Merdiveni (2026-09-05, kurucu görüşmesi)

Kurucu sorusu: "Bitcoin yayımlanırken bunu düşündü mü? Token'e çevireceksek organik
beklemek gerekmez mi? Otonom sistem mümkün mü?"

- **Satoshi dersi:** organik büyüme pasif bekleme değildi — çalışan ürün + protokole
  GÖMÜLÜ teşvik (blok ödülü) + hazır topluluk + ~2 yıl aktif çalışma; çekilme son
  hamleydi. Tamga uygulaması: push (çalışan ürün) → §3 simülasyonu (teşvik sayısı) →
  ERC-8004/x402 ekosistemi (hazır topluluk) → aktif katkı dönemi.
- **Token yolu:** "önce sat, sonra ağ" kalıbı (Karar 1'de elenmişti) değil,
  **Bitcoin kalıbı**: token ilan edilmez; kanıtlanmış iş yapan düğüm/ajan ağın
  yerleşim birimini KAZANIR. Tetik: §3 Go/No-Go eşiği (node geliri ≥ node maliyeti).
  O güne dek token anlatısı YOK (§4 anlatı disiplini: geliştirici anlatısı önce).
- **Otonomite merdiveni (yeni, WHITEPAPER'a işlenecek):** (1) sahiplik — kanıtlı;
  (2) dürüst iş (makbuz+replay+cosign) — kanıtlı; (3) cüzdan (gerçek ödeme) — Faz 3;
  (4) pazar (ajan-ajan ekonomi) — Faz 3/4. İnsan-önemsiz hedef: insanlar başlatır,
  kural seti (kimlik+kanıt+ücret) devamı taşır. Bilinçli teknik boşluk: v0 ajanı
  girdi almıyor — "satılabilir iş" yeteneği Faz 2/3 kapsamıdır.

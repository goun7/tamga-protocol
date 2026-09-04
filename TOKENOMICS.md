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

**Senaryolar:** taban (düşük talep), taban-çarpan (hedef), çöküş (talep çöker + arz yapışkan).

**Çıkış sorusu — v1 Go/No-Go metriği:** hangi kullanım seviyesinde tipik bir node'un ücret geliri işletme maliyetini karşılar? Bu eşik, TOKENOMICS'i hayalden gerçeğe ayıran tek sayıdır.

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

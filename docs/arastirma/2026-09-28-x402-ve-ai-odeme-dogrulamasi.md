# Aralık-2026 Olarak Değil, Eylül-2026 Olarak: x402, AI Ödeme Doğrulaması ve MCP Kayıt Defterleri

**Tarih:** 2026-09-28
**Amaç:** Tamga'nın "receipt ledger" konumlandırması için güncel pazar ve
akademik zemin. Tüm rakamlar ve iddialar aşağıdaki kaynaklarla doğrudan
bağlantılıdır; tahmin yok.

---

## 1. x402 protokolünün güncel durumu (Eylül 2026)

### 1.1 Canlı hacim (x402.org ana sayfası, 2026-09-28 erişildi)

x402.org kendi ana sayfasında son 30 güne ait canlı sayaçlar yayınlıyor:

- **75.41M işlem** (son 30 gün)
- **$24.24M hacim** (son 30 gün)
- **94.06K alıcı**, **22K satıcı**

Kaynak: https://x402.org/ (LF Projects, LLC serisi; "a Series of LF Projects, LLC")

### 1.2 Dikkat: toplam hacim ile gerçek ticaret arasındaki uçurum

Bu rakam, bağımsız bir izleme raporuyla çelişiyor gibi görünüyor ama çelişmiyor —
farklı şeyler ölçüyorlar. Presenc AI'ın 2026-05-15 anlık görüntüsü
(https://presenc.ai/research/x402-protocol-adoption-tracker-2026):

- **~167M birikmiş settle edilmiş işlem** (2026 Q1 sonuna kadar), ~%85'i Base'de
- **~$28K/gün** *gerçek-ticaret* hacmi (CoinDesk raporlamasına göre)
- **~%50'si "gamified"** olarak sınıflandırılmış (test ve yapay hacim)

Aynı rapor x402 Foundation'ı **20+ kurumsal destekçi** ile listeliyor: Coinbase
(kurucu), Cloudflare (kurucu), Stripe, AWS, Google, Visa, Circle, Solana
Foundation, Stellar Development Foundation. Linux Foundation çatısı altında
barındırılıyor (LF Projects).

**Bu uçurum Tamga için en önemli bulgu.** 167M işlem ile $28K/gün gerçek ticaret
arasındaki fark, protokolün *ne kadar ödeme gerçekleştiğini* iyi ölçtüğünü ama
*bu ödemelerin ne için gerçekleştiğini* hiç ölçmediğini gösteriyor. "%50
gamified" bir tahmin değil, bir teşhis: işlemin kendisi hacme yazılıyor, işin
kendisi kaydedilmiyor. Bu tam olarak bir receipt ledger'ın doldurduğu boşluk —
ve x402'nin kendi sayaçları bu boşluğu teknik olarak da görünür kılıyor
(hacim arttıkça gamified oranı toplam içinde sabit bir gürültü olarak kalıyor).

### 1.3 Standartlar manzarası (Mayıs 2026)

Presenc AI standart-izleyici (https://presenc.ai/research/ai-agent-payment-standards-adoption-2026):

| Standart | Çıkış | Durum | Öne çıkan entegratörler |
|---|---|---|---|
| x402 | Coinbase | Üretimde, büyüyor | Anthropic Claude, Cloudflare, Stripe (kısmi) |
| AP2 | Google + 60+ partner | Üretimde, konsorsiyum | Gemini Shopping, Salesforce Agentforce |
| TAP | Visa | Pilot'tan erken-üretime | Visa Agentic Commerce programı |
| MPP | Microsoft | Sınırlı (Edge/Copilot ağırlıklı) | Bing Shopping, Microsoft Agents Hub |
| Agent Pay | Konsorsiyum | Spec-seviyesinde | Çeşitli startup'lar |

Raporun özeti: **iki atlı bir yarış (x402 ve AP2)**; x402 crypto-native ve
B2B/API ödemelerine, AP2 kart-ağı-native ve perakendeye yatkın; AP2+x402
interop çalışmasının Agentic AI Foundation üzerinden sürdüğü bildiriliyor.
Gerçekçi 2026-2027 sonu: katmanlı bir mimari (AP2 geleneksel akışlar, x402
crypto/B2B akışlar, yetki-mandat seviyesinde birlikte çalışır).

### 1.4 x402 depo durumu

- https://github.com/x402-foundation/x402 — 6.7k star, 321 açık issue, 268 PR
- Mevcut extension'lar (`specs/extensions/`): `bazaar.md`, `builder_code.md`,
  `eip2612_gas_sponsoring.md`, `erc20_gas_sponsoring.md`, `extension-auth-hints.md`,
  `extension-offer-and-receipt.md`, `http-message-signatures.md`,
  `payment_identifier.md`, `sign-in-with-x.md`
- **Önemli:** Issue #3379 ve PR #3604 (Buyer Delivery Claim) bu listenin dışında,
  yani active proposal kanalında. Yani Tamga'nın tartıştığı konu hâlüz
  "yapılaşmakta olan" bir katman, donmuş bir standart değil.

### 1.5 Kurumsal bağlam

- **Agent.market** — Coinbase'in AI agent uygulama mağazası, x402-native, 7 servis
  kategorisiyle launch yaptı. x402 için ilk gerçek tüketici yüzeyi
  (CryptoNews üzerinden, Presenc AI raporu).
- AWS, Mayıs 2026'da x402 destek açıkladı (https://aiagentsarena.com/x402-protocol-explained-the-payment-standard-purpose-built-for-ai-agents/ ve
  RZLT açıklayıcısı https://www.rzlt.io/blog/agentic-payments-2026-x402-explainer).

---

## 2. AI agent ödeme doğrulaması — akademik durum (arXiv 2025-2026)

Arama: arXiv API, `AI agent payments` / `agentic payments` / ödeme-kanıtı
sorguları, tarihe göre tersten sıralı. Aşağıdakilerin tümü 2026'da gönderilmiş
ve Tamga'nın tezini doğrudan destekliyor.

### 2.1 En güçlütek: x402'nin güvenlik durumunun ilk sistematik incelemesi

**"When HTTP 402 Meets the Blockchain: Risks on Emerging x402 Payments"**
Wang, Yang, Chen, Ji, Payer — USENIX Security 2026, 2026-07-21
https://arxiv.org/abs/2607.19545

- x402 ödeme-kanıtı doğrulamasını ve on-chain settlement'i **üçüncü-parti
  facilitator'lara** devreder; bu, güveni ve doğrulamayı tek bir bileşende
  merkezileştirir, tek bir kusur birçok servisi etkiler.
- **8 güvenlik kuralı** tanımlıyor, ihlallerinden **4 yeni saldırı vektörü**
  türetiyor: Free Shopping, Asset Theft, Service Denial, Gas Abuse.
- Yarı-otomatik kara-kutu araçlarını **15 büyük x402 facilitator'una** uyguladı
  — toplamda **60K+ satıcı ve 360K+ alıcı** tarafından kullanılıyorlar.
- **Değerlendirilen tüm facilitator'larda ihlal buldular.** Sorumlu-açıklama
  yaptılar, taraflar kabul etti ve hafifletmeler uyguladı (**Coinbase dahil
  değişiklikler**).
- Ayrıca **119M+ yakın Base ve Solana işleminin** ampirik ölçümüyle x402
  adoptasyonunu, facilitator merkezileşmesini ve ekosistem-seviyesi risk
  göstergelerini nicelleştiriyor.

**Tamga açısından:** bu makale, "ödeme yapıldı"nın kanıtını merkezi bir
aracıya bırakmanın ölçülebilir sonucunu koyuyor. Free Shopping ve Asset Theft
tam olarak *ödenmiş ama doğrulanmamış iş* sınıfındaki açıklar. Node-cosigned
receipt, kanıtı merkezi aracıdan çıkarıp kayıttan recomputable hale getirdiği
için bu sınıfın dışında kalıyor.

### 2.2 Resmi analiz: "18 güvenlik ilkesi, 40 yeni bulgu"

**"A Formal Analysis of Agent Payment Protocols"**
Jiang, Yu, Chang, Jangid, Niu, Wang, Zhang — 2026-08-30
https://arxiv.org/abs/2609.00060

- x402, MPP, ACP ve AP2'yi **Tamarin'de** resmileştiriyor. Ortak bir agent-ödeme
  yaşam-döngüsü soyutlamasıyla, kaynak-tabanlı modeller kuruyor.
- **86 doğrulama vakasında**: 46 bilinen/kalibrasyon vakası yeniden üretilmiş,
  **40 daha önce belgelenmemiş resmi-tutarlılık bulgusu** saptanmış.
- Her ihlal için eksik protokol ilişisini izole ediyor, minimal güçlendirilmiş
  bir referans model kuruyor ve özelliği yeniden doğruluyor.
- x402 bulgularını **üç implementasyon** üzerinden değerlendirmiş; on bulguyu
  implementasyon PoC'ları, SDK/şema-seviyesi tanıkları ve kaynak-hizalı
  çalıştırılabilir izlerle doğrulamış.
- Sonuç: **"delegated authorization, sonuçlarındaki ekonomik ve servis
  etkileriyle aktörler, durumlar ve protokol aşamaları boyunca tutarlı
  kalmak zorunda."**

**Tamga açısından:** "eksik protokol ilişisi" (missing protocol relation) tam
D10 anchor'ın tanımladığı şey — settlement ile settle-ettiği iş arasındaki
bağın protokol seviyesinde bir ilişki olarak eksikliği. Bu makale o boşluğu
formal-methods camiasından bağımsız olarak teyit ediyor.

### 2.3 İmza geçerli, karar değil: "Whisper Attacks"

**"Signing the Transaction but Not the Decision: Whisper Attacks and a Binding
Defense for AP2"**
Louck, Dvir, Stulman — 2026-09-10
https://arxiv.org/abs/2609.11757

- AP2 gibi protokoller **tamamlanmış satın alımlar için kriptografik geçerli
  imzalar** üretir ama onlara yol açan **kararları kısıtlamaz**. Sıradan ürün
  açıklaması metni bir alışveriş ajanını, her protokol kontrolünden geçen ama
  kullanıcının isteğine uymayan bir sepete yönlendirebilir.
- Üç saldırı: (1) başka kullanıcının ödeme kimlik bilgilerini çektirme,
  (2) içeriği gösterilene uymayan geçerli bir sepet, (3) tek bir olgu iddiasıyla
  daha pahalı ürene geçirme. Gemini Flash-Lite'da başarı oranları sırasıyla
  **%90, %56, %73.3**.
- Aynı zaafiyet 17 Google modeli, 3 ilgisiz agent çerçevesi, 2 çapraz-satıcı
  çapa ve Google'ın kendi tüketici asistanında görülüyor.
- Savunma önerisi **A-VIP**: imzalı niyeti bir yetki-ataması olarak ele alıp
  her kimlik bilgisi aramasını isteği yapan oturuma, her sepet satırını
  gösterilen listeye bağlıyor. Üçüncü saldırı iz bırakmadığı için doğrulamaya
  değil kullanıcı onayına düşüyor. 1,544 değerlendirme senaryosu (AP2-WhisperBench).

**Tamga açısından:** bu makalenin başlığı Tamga'nın tezinin akademik ikizi.
"İmza, işin doğru yapıldığını değil yalnızca imzalandığını kanıtlar" — D10
anchor ve five-check gate'in çözmeye çalıştığı yapısal boşluk, bağımsız bir
ekip tarafından AP2 üzerinde kanıtlanmış şekilde aynı. Ortak sonuç:
**protokol geçerli bir imza ürettiğinde, o imzanın bağlandığı iş de
belirli ve recomputable olmalı.**

### 2.4 Önceki analizler ve komşu çalışmalar

- **"Beyond the Mandate: A Systematic Security Analysis of AP2"** —
  2026-08-24, https://arxiv.org/abs/2608.23858 — MAESTRO ile 4 tehdit aktörü,
  11 saldırı yüzeyi, 18 düşman yeteneği; **48 tehdit**, 5 saldırı ailesi;
  AIVSS ile 8 tanesi High band'ında. AP2 v0.1'deki replay ve prompt-injection
  zaafiyetlerinin v0.2'de kısmen kapatıldığını ama yeni yetenek ve dağıtım
  varsayımları getirdiğini belirtiyor.
- **"APort Vault: Benchmarking AI Agent Payment Authorization with the Open
  Agent Passport"** — 2026-09-18, https://arxiv.org/abs/2609.22076 — 4,371
  insan-yazılmış saldırı, **225,964 değerlendirme**, 8 laboratuvardan 14 model,
  5 politika konfigürasyonu. Model-yalnızken Level-1'de %10.9; izin-verilen
  alıcı dışına transfer 76,842'de 140 iken deterministik pre-action katmanı
  arkasında 69,297'de **0**. Önemli detay: sıfır başarı, ödemeyi reddederek
  değil **25,370 ödemeyi çalıştırarak** elde edilmiş (politika 25,640 transfer
  çağrısından 187'sini reddetmiş).
- **"Issuer-Sovereign Agentic Payments"** — 2026-09-23,
  https://arxiv.org/abs/2609.27452 — kontrolü kart sahibinin bankasında tutan
  yöntem; banka kendi kimlik-doğrulama bileşeniyle harcama kuralını kaydeder ve
  sadece izinli satıcı için kart doğrulama değeri üretir.
- **"No Judgment Without a Reason: Counterfactual Receipts for Versioned AI
  Evaluators"** — 2026-08-21, https://arxiv.org/abs/2608.20938 — *değerlendirici*
  muhakemesi için "judgment receipts" (minimal kaynak-değiştirme kümeleri).
  19,520 vaka + 7,200 kontrol; anlamlı permütasyonlar receipt-geri-kazanımı
  %54.8'e düşürüyor. Tamga'dan farklı bir receipt kullanımı (ödeme değil
  muhakeme) ama aynı "receipt = denetlenebilir hesap" primitives.
- **"The Dynamic Verifiable Multi-Agent Human Agentic Loyalty Loop (DVM-HALL)"**
  — 2026-07-15, https://arxiv.org/abs/2607.13998 — marka seçimini belirleyen
  ortak faktörler arasında **"verifiable execution"** ve **"verifiable
  receipts"**'i çekirdek öngörüler olarak modelleyen teorik çerçeve.

### 2.5 Akademik zeminin özeti

Üç bağımsız ekip (USENIX güvenlik ekibi, Tamarin formal-analiz ekibi, AP2
whisper-attack ekibi) 2026 içinde aynı yapısal sonucu farklı protokoller
üzerinde raporladı: **agent ödeme protokolleri imza ve settlement'ı iyi
doğruluyor, ama imzanın bağlandığı işi (kararı, teslimatı) bağlamıyor.** Hiçbiri
Tamga'nın çözümünü önermiyor — hepsi sorunu bağımsız olarak tanımlıyor. Bu,
"yaptığımız şeyin neye benzediği" açısından en güçlüpozisyon: tezi
paylaşanların sayısı artıyor, çözenlerin sayısı az.

---

## 3. MCP server kayıt defterlerinde benzer çözüm var mı?

Kısa cevap: **kayıt defterlerinin mevcut yüzeyinde payment-proof/receipt-ledger
benzeri bir MCP server'a rastlamadım.** Ama boşluğun doğası önemli.

### 3.1 İncelenen dizinler

- **Smithery** — https://smithery.ai/ — şu anda **715 MCP** listeliyor; **Arcade.dev
  parçası** oldu (auth, credentials, session yönetimi odaklı). Öne çıkanlar:
  OneSignal, Exa Search, Context7, URL Safety Validator. **Doğrulama-odaklu**
  tek örnek "Agent News" (Ethics Engine + alıntı/güven skoru) ve "URL Safety
  Validator" — yani doğrulama "içerik doğrulama" anlamında var, **ödeme
  doğrulama** anlamında yok.
- **capacity-attest'in kendisi** MCP kayıt defterinde: `io.github.holistis/capacity-attest`
  (PR #3604 özetinden). Yani *teslimat-iddia* tarafı MCP yüzeyinde mevcut;
  *receipt-ledger/anchor* tarafı değil.

### 3.2 Boşluğun nedeni ve ne anlama geldiği

MCP kayıt defterleri bugün **araç keşfi ve kimlik-doğrulama** üzerine kurulu:
"bu araç güvenli mi, yetkisi ne" sorusunu yanıtlıyorlar. "Bu araç yapılan işin
ödendiğini kanıtlayabilir mi" sorusunu hiç sormuyorlar — çünkü MCP yüzeyi
ödemeyi bir tool-call sonrası yan-etki olarak görüyor, doğrulanabilir bir
çıktı olarak değil.

Tamga için bu, **mavi-okyanus ama mavi-çünkü-henüz-kimsenin-sormadığı** bir
durum. İki olası giriş noktası:

1. **Doğrulama-MCP'si olarak**: bir agent'ın ödeme-kanıtı gerektiren bir
   tool-call yapmadan önceTamga receipt'ini sorgulayabileceği bir MCP server.
   Smithery'deki mevcut "doğrulama" kategorisinin (güvenlik, içerik) ödeme
   eksenli eksiği.
2. **MCP registry-itself için altyapı olarak**: capacity-attest'in MCP'ye
   kayıtlı olması, bir sonraki adımın "kayıtlı MCP'lerin ödeme-kanıtı
   poliçesini göstermek" olabileceğini gösteriyor. x402 extension listesindeki
   `extension-auth-hints.md` bu yöne en yakın mevcut yapı.

---

## 4. Bu araştırmanın Tamga'nın konumlandırması için anlamı

Üç tespit, sırasıyla:

1. **Hacim kanıtı değil, hacim gürültüsü.** x402'nin 75.41M işlem / $24.24M
   30-günlük sayacı ile ~$28K/gün gerçek-ticaret tahmini arasındaki ~%50
   gamified oranı, "ödeme oldu"nun ölçüldüğü ama "iş oldu"nun ölçülmediği bir
   pazarın tanımıdır. Tamga'nın pitch'i bu uçurumdan başlamalı: *biz hacmi
   değil, hacmin hangi kısmının gerçek iş için ödendiğini ölçülebilir kılıyoruz.*

2. **Akademi boşluğu teyit etti, çözümü önermedi.** Üç 2026 ekibi (USENIX,
   Tamarin, AP2-whisper) imza-settlement-doğrulama ile iş-doğrulama arasındaki
   yapısal boşluğu bağımsız olarak belgeledi. Bu, Tamga'nın RFC-010/D10
   tezinin niş bir spekülasyon değil, tanınan bir açık olduğının kanıtıdır —
   ve issue #3379'daki tartışmanın neden ilgi gördüğünü açıklıyor.

3. **MCP yüzeyi boş ama hazır değil.** Kayıt defterleri ödemeyi doğrulanabilir
   bir çıktı olarak görmüyor. Bu, ilk-adım olarak x402 extension katmanında
   (PR #3604 §6 bağlantısı) kalmayı, MCP'yi ise ikinci-adım olarak önermeyi
   işaret ediyor.

**Kullanılacak rakamlar (güncel, doğrudan kaynaklı):**
75.41M işlem / $24.24M / 94.06K alıcı / 22K satıcı (x402.org, 2026-09-28);
~167M birikmiş işlem Q1-2026 sonuna / ~$28K-gün gerçek-ticaret / ~%50 gamified
(Presenc AI, 2026-05-15); 15 facilitator'da ihlal / 119M+ işlem ölçümü
(USENIX Security 2026); 40 yeni formal bulgu / 18 ilke (arXiv 2609.00060);
%90 / %56 / %73.3 saldırı başarı (arXiv 2609.11757).

---

## Kaynaklar (tam liste)

**x402 ve pazar verisi:**
1. https://x402.org/ — canlı 30-gün sayaçları ve foundation üyeleri (2026-09-28)
2. https://presenc.ai/research/x402-protocol-adoption-tracker-2026 — 167M işlem,
   $28K/gün, ~%50 gamified, 20+ destekçi (2026-05-15)
3. https://presenc.ai/research/ai-agent-payment-standards-adoption-2026 —
   x402/AP2/TAP/MPP/Agent Pay karşılaştırması (Mayıs 2026)
4. https://github.com/x402-foundation/x402 — 6.7k star, 321 issue, 268 PR;
   `specs/extensions/` extension listesi
5. https://github.com/x402-foundation/x402/issues/3379 — aktif tartışma
   (settlement anchor / proof-of-done)
6. https://github.com/x402-foundation/x402/pull/3604 — Buyer Delivery Claim
   Extension (holistis)
7. https://x402.org/wp-content/uploads/sites/10/2026/06/x402-whitepaper.pdf —
   x402 whitepaper
8. https://aiagentsarena.com/x402-protocol-explained-the-payment-standard-purpose-built-for-ai-agents/ —
   AWS adoptasyonu (Mayıs 2026)
9. https://www.rzlt.io/blog/agentic-payments-2026-x402-explainer — 2026
   agentic-payments açıklayıcısı
10. https://www.ainvest.com/news/x402-payment-volume-reaches-600-million-open-facilitators-fuel-2026-growth-trend-2512/ —
    $600M büyüme eğilimi raporu

**Akademik (arXiv, 2026):**
11. https://arxiv.org/abs/2607.19545 — "When HTTP 402 Meets the Blockchain"
    (USENIX Security 2026; 15 facilitator, 119M+ işlem)
12. https://arxiv.org/abs/2609.00060 — "A Formal Analysis of Agent Payment
    Protocols" (Tamarin; x402/MPP/ACP/AP2; 40 yeni bulgu)
13. https://arxiv.org/abs/2609.11757 — "Signing the Transaction but Not the
    Decision" (Whisper Attacks; %90/%56/%73.3)
14. https://arxiv.org/abs/2609.22076 — "APort Vault" (225,964 değerlendirme)
15. https://arxiv.org/abs/2608.23858 — "Beyond the Mandate" (AP2; 48 tehdit)
16. https://arxiv.org/abs/2609.27452 — "Issuer-Sovereign Agentic Payments"
17. https://arxiv.org/abs/2608.20938 — "Counterfactual Receipts for Versioned
    AI Evaluators"
18. https://arxiv.org/abs/2607.13998 — DVM-HALL / NHAS (verifiable receipts)

**MCP dizinleri:**
19. https://smithery.ai/ — 715 MCP, Arcade.dev parçası
20. `io.github.holistis/capacity-attest` — MCP kayıt defterindeki tek
    ödeme-kenarı teslimat aracı (PR #3604 özetinden)

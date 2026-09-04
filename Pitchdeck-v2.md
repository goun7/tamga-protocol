# Tamga Protocol — Master Pitch v2

> **v1 → v2 değişiklik günlüğü:** Token ekonomisi (Tamganomy) 3. aşamaya alındı ve hukuki görüş şartına bağlandı. Rakip analizi, tehdit modeli, yönetişim/yükseltme planı, ölçülebilir kilometre taşları ve risk kaydı eklendi. "Sıfır gecikme" ve "sonsuz hafıza" gibi fizikle çelişen iddialar ölçülebilir karşılıklarıyla değiştirildi. Ajanlarla geliştirme operasyon modeli belirtildi. "Erken olma" tezi, çift kullanımlı v0 ile sigortalandı.

## 0. Tek Cümle

Tamga, otonom ajanların **içinde koştuğu makineye güvenmeden** çalışabildiği, hafızasını ve ödemesini yanında taşıyabildiği **taşınabilir güven altyapısıdır**: bugün yazılım (v0), yarın açık node ağı (v1), olgunlaştığında merkeziyetsiz protokol ve token (v2).

## 1. Tez: Neden Erken Oluyoruz?

Hedefimiz, agentic ekonomide henüz tam var olmayan bir sorunu önceden çözmek. Bunun tarihsel riski nettir: **erken olmak, yanlış olmakla aynı yerde ölür ama daha pahalıya mal olur.** Bu riski iki mekanizmayla sigortalıyoruz:

1. **Gözlenebilir eğri:** Ajanlar ekonomik aktörlere dönüşüyor (ödeme yapan, kaynak kiralayan). Bu eğri büyüdükçe şu soru zorunlu hale gelir: *"Bu ajanın içinde koştuğu makineye neden güveniyorum ve hafızası neden host'a bağımlı?"* Tamga bu sorunun cevabını bugünden, küçük ölçekte kurar.
2. **Çift kullanımlı v0:** Talep büyümezse bile v0 tek başına değerli bir yazılımdır — gizlilik duyarlı otomasyonların koştuğu, hafızasını taşıyabilen bir ajan paketleyici. Yani "erken olma" bahsimiz, bugün satılabilen bir ürüne dayanır; havaya değil.

## 2. Sorun

**Bugün var olan çekirdek problem (küçük ama gerçek):**
- Şirketler ve bireyler, ajanlarını çalıştırmak için host'a tam güvenmek zorunda: ajan kodu, bağlam verisi ve API anahtarları host'un eline geçer.
- Bir ajanın hafızası (bağlam grafiği) çalıştığı makineye hapsolmuştur; ajan "taşınmaz".
- Makine-başına CPU kullanımı için makine-native, mikro ölçekli ödeme yolu yoktur.

**Yarın büyüyecek olan:** Ajanlar ajanlarla işlem yaptıkça bu üçlü (güven, taşınabilir hafıza, makine ödemesi) niş değil, altyapı zorunluluğu olur. Tamga, bu üçlüyü **tek pakette** çözmeyi hedefler.

## 3. Ürün: Üç Aşamalı Yol

### v0 — Tamga Runner (yazılım, token'sız, ~0-6 ay)

Tek binary node:

- **Runner:** WASM ajan paketlerini koşturur (Wasmtime tabanlı), süreç + WASM sandbox izolasyonu.
- **Bağlam Grafiği:** Gömülü SQLite + vektör arama; ajan durumu taşınabilir, şifreli snapshot olarak export/import edilir.
- **Muhasebe:** Yerel simüle ledger — CPU-saat / RAM / I/O sayaçları, makine-başına ücretlendirme.
- **Kilit demo (tek seans, kanıt niteliğinde):** Bir ajan, şifreli hafızasıyla birlikte A makinesinden B makinesine taşınır; B üzerinde koşarken kullandığı kaynak için simüle ödeme yapar; host, ajanın **şifreli snapshot'ına erişemez** (at-rest). Kullanım-sırası bellek koruması TEE ister ve v1'in konusudur.

Ne kanıtlıyor: **"taşınabilir ajan + taşınabilir hafıza + kullandıkça-öde" çekirdek döngüsü.** İlk müşteri: kendi ajanlarımız (dogfooding) + gizlilik duyarlı pilotlar.

### v1 — Ağ (~6-18 ay)

- Açık **Tier-2 node'lar**: standart donanımda Docker/WASM runner + bağlam ağı.
- **Ödeme:** hazır standart üstünden (x402 veya hazır bir L1'in state channel'ı) — **kendi zincirimiz yok.**
- **TEE:** bulut enclave'leri (AWS Nitro / Azure SEV-SNP) — kurucu ekibin kendi donanımı gerekmez.
- **Tier-1 fast-path (eBPF/DPDK):** yalnız v0/v1 ölçümleri gecikme darboğazını kanıtlarsa, ayrı uzman işbirliğiyle. Kanıt yoksa ertelenir.

### v2 — Protokol (18 ay+)

- State channel'lar, zkVM yürütüm kanıtı, canlı göç **araştırma** programı.
- Tamganomy token (bkz. §9) — yalnız v0/v1 traction kanıtından sonra.
- Yönetişim ağı.

## 4. Rakip Manzarası ve Ayrışma

| Katman | Rakipler | Tamga ayrımı |
|---|---|---|
| Merkeziyetsiz compute | Akash, io.net, Render | Onlar **kaynak** satar; Tamga "host'a güvenmeyen, hafızasını taşıyan ajan paketi" satar |
| TEE compute | Phala, iExec, Marlin | Onlar enclave kiralar; Tamga enclave + taşınabilir bağlam + ödemeyi tek pakette verir |
| Ajan hafızası | Mem0, Letta, Zep | Onların hafızası host'ta yaşar; Tamga hafızayı ajanla taşır |
| Ajan ödemesi | x402, hazır L1'ler | Standartları yeniden icat etmiyoruz; üstlerine node + muhasebe katmanı ekliyoruz |

İddia "her şeyi yapan protokol" değil, **paketleme** iddiasıdır: entegrasyon bizim ürünümüz.

## 5. Müşteri Segmentleri (gerçekçi sırayla)

1. **Kendi ajanlarımız** — gelir değil, doğrulama aracı (dogfooding).
2. **Gizlilik duyarlı otomasyonlar** — verisi buluta çıkmak istemeyen küçük firmalar / Web3 ekipleri.
3. **Atıl donanım sahipleri** — v1'de arz tarafı.

HFT / arbitraj segmenti v1 hedefi **değildir**: gecikme hassasiyeti colocation ister, termodinamik yönlendirme ile çelişir. (v2'de ayrı ürün olarak değerlendirilir.)

## 6. Mimari (dürüst hali)

- **Katmanlar:** Ajan Paketi (WASM + manifest) → Runner → Bağlam Grafiği → Muhasebe → Keşif/İtibar.
- **Taşıma modeli:** v0-v1 = *snapshot → taşı → soğuk başlat* (ms-sn kesinti). Canlı göç araştırma konusudur, vaat değil.
- **Gecikme hedefi:** "sıfır gecikme" değil, **ölçülmüş ek gecikme** (runner overhead < X ms; ölçülmeyene vaat yok).
- **Hafıza:** "sonsuz" değil; **host-bağımsız ve kişi başı ölçeklenen** bağlam grafiği.
- **Bellek koruması ayrımı:** at-rest koruma (şifreli snapshot) v0'da; kullanım-sırası (in-use) koruma yalnız TEE ile — v1. Kağıt bu ayrımı belirsizleştirmez.
- **Bilinçli olarak yok (v2'ye/araştırmaya ertelenmiş):** kendi L1, canlı göç, zk gözculuk tespiti, µs fast-path.

## 7. Tehdit Modeli (taslak)

- **Varlıklar:** ajan kodu, bağlam verisi, ödeme akışı.
- **Düşmanlar:** meraklı host operatörü, kötücül ajan, kamyoncu node, ajanın kendisi.
- **Kanıt zinciri (v1):** Nitro/SEV attestation → node kimliği; snapshot'lar ajan anahtarıyla şifreli (host okuyamaz); kaynak ölçüm anomalileri izlenir; ceza (slashing) yalnız kanıta bağlı ihlallerde.
- **İnsan kapıları:** (1) tehdit modeli her sürümde gözden geçirilir, (2) ödeme/slashing kontratı dış denetimden geçmeden gerçek değere dokunmaz, (3) güvenlik sınırındaki kod değişiklikleri kurucu onayına takılır.

## 8. Yönetişim ve Yükseltme

- **Arayüzler önce:** ajan paket manifest'i, node API'si ve muhasebe kayıt şemaları; tek "mimar" yazar, kurucu onaylar, sürümlenir ve donar.
- **Otonom kodlama ajanları** insan onaylı kapılarla çalışır; hiçbir değişiklik güvenlik sınırını denetimsiz geçmez (bkz. §12).
- **Yükseltme:** node yazılımı sürümlü; protokol değişiklikleri RFC süreciyle; "değişmez kontrat" yok — değişmez olan yalnız kanıt kurallarıdır.

## 9. Tamganomy (Aşama 3'e Ertelenmiş)

v1 pitch'teki mekanizmalar korunur (Node Lisansı, %5-10 burn, Tier-1 stake, sigorta kasaları, kanıta bağlı slashing) — ancak:

- **Hukuk:** lisans + staking + vault kombinasyonu çoğu yargı bölgesinde menkul kıymet riski taşır. Token çalışması yalnız yazılı hukuki görüş sonrası başlar.
- **Ön şart — birim ekonomi simülasyonu:** 1 CPU-saat fiyatı Akash/AWS'ye karşı modellenir; token hız analizi ("ödeme yapıp kaçan neden token tutasın?"), arz-talep dengesi ve burn'in amortismanı simülasyonla kanıtlanır.
- **Tetikleyici:** §10'daki traction metrikleri. Tetiklenmeden token gündeme gelmez.

## 10. Ölçülebilir Kilometre Taşları

- **T+90 gün:** v0 demo çalışır (taşıma + ödeme döngüsü); runner overhead ölçülü; 3+ kendi ajanı üretimde koşuyor.
- **T+180 gün:** 5+ dış node; gerçek mikro-ödeme entegre; 1 dış pilot müşteri; aylık aktif ajan sayısı hedefi.
- **T+365 gün:** bulut TEE'de izole koşum; ağ ücret geliri > node işletme maliyetinin ölçülü bir yüzdesi; v2 protokol kararı için veri paketi.
- **Başarısızlık kriteri de açıktır:** T+365'te dış talep kanıtlanmazsa "ağ" hedefi terk edilir; v0 ürün olarak yoluna devam eder.

## 11. Risk Kaydı

| Risk | Etki | Mitigasyon |
|---|---|---|
| "Erken olmak" = yanlış zamanlama | Yüksek | Çift kullanımlı v0; tetikleyici metrikler; başarısızlık kriteri |
| Ajanla kodlanan sistemde kalite/güvenlik borcu | Yüksek | Interface-first, test-önce, insan kapıları, dış denetim |
| DePIN'de talep zayıflığı (Akash dersi: arz kolay, talep zor) | Yüksek | Önce yazılım + anlamlı demo; ağ ancak talep kanıtlanınca |
| Hukuki (menkul kıymet) riski | Yüksek | Token'ı aşama 3'e almak + hukuki görüş şartı |
| Kurucunun teknik doğrulama sınırı | Orta | Test-önce kültür; her "çalışıyor" iddiası komut çıktısıyla kanıtlanır |
| TEE maliyet/karmaşıklığı | Orta | Bulut enclave; v1'e erteleme; v0'da süreç+WASM sandbox |

## 12. Ajanlarla Geliştirme Operasyon Modeli

**Rollar:** Kurucu = ürün sahibi ve kapı (kod yazmaz; karar verir, kabul eder, kanıt ister). Ajanlar = mimari öneri, implementasyon, test, dokümantasyon, kırmızı-takım.

**Kurallar:**

1. **Arayüz şemaları önce:** tek "mimar" ajan yazar, kurucu onaylar, donar. Ajanlar yalnız donmuş arayüzlerin arkasına paralel girer.
2. **Dikey dilimler:** her iterasyon uçtan uca çalışan küçük özellik (taşıma, ödeme, sandbox...) — katman-katman ekipler değil.
3. **Test-önce + simnet:** her dilim kabul testiyle açılır; deterministik simnet ortamında koşar. Kırmızı test yoksa iş bitmiş sayılmaz.
4. **İnsan kapıları:** şifreleme, ödeme, izolasyon gibi güvenlik sınırlarındaki değişiklikler ayrı inceleme + kurucu onayı ister.
5. **Kanıt kültürü:** "çalışıyor" iddiası yalnız komut çıktısı / log ile kabul edilir; his, kanıt değildir.

**Beklenti:** v0 demo, yoğun iterasyonla haftalar-aylar mertebesinde. Hedef "sorunsuz" değil, **doğrulanabilir artışlar**dır.

## 13. Açık Sorular (bilinçli olarak cevapsız)

1. x402 mi, hazır L1 state channel mı? → v1 öncesi prototip ölçümüyle karar.
2. Bağlam grafiği: yerel mi, dağıtık mı? → v0 kullanım verisiyle karar.
3. Tier-1 fast-path gerçekten gerekli mi? → Ölçüm olmadan karar yok.
4. Ajan kimliği: anahtar yönetimi kimde? → Tehdit modeliyle birlikte çözülecek.
5. v2'de kendi zincir gerçekten gerekli mi? → Varsayılan: **hayır**, hazır L1.

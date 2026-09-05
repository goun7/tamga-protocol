# Tamga: Kendine-Sahip Ajanlar — Whitepaper (v0.1 TASLAK)

> Durum: TASLAK. Bu belge dondurulmadan (v0.1-final) primitifi gerçekleyen kod yazılmaz.
> Format disiplini: Bitcoin whitepaper'ı gibi kısa primitif tanımı; mimari detaylar SPEC/RFC'lere devredilir.

## 1. Özet

Bu doküman, Tamga'nın tek primitifini tanımlar: **kendine-sahip ajan** (self-owning agent). Kimliği, hafızası, parası ve koşum kanıtı, içinde koştuğu makineye değil **kendi anahtarlarına** bağlı olan ajan. Primitif gerçeklendiğinde ajanın çalıştığı donanım değişebilir; kimlik, hafıza ve değer kayıpsız ajanla birlikte hareket eder.

Bu belge "nasıl" sorusunun şemasını değil, "ne" sorusunun tanımını verir. Gerçekleme aşamalıdır (v0 yazılım → v1 ağ → v2 protokol) ve her aşama ölçülebilir kabul testleriyle geçer.

## 2. Problem: Makine Varsayılanı

Bugün her ajan platformu — çerçeveler, bulut ajan servisleri, ajan hafıza ürünleri — aynı varsayımı yapar: **ajan, koştuğu makineye ve onun operatörüne güvenir.** Kod, bağlam verisi ve erişim anahtarları host'un eline geçer.

Bu varsayım tek-makine yaşamlar için kabul edilebilir; ancak üç gelişme büyüdükçe bozulur:

1. **Çoklu-makine ajan yaşamları** — ajanlar makineden makineye geçerken kimlik ve hafıza kaybı yaşar.
2. **Ajan-ajan ticareti** — iş yapan ajanın, işi alan ajanın makinesine veri ve parasını emanet etmesi gerekir.
3. **Gizlilik gerektiren otomasyon** — operatörün veriye erişebildiği her yerde gizlilik söz konusu değildir.

Bitcoin'in cevabı "fiata veya bankaya güvenme, kriptografiye güven" idi. Tamga'nın cevabı: **"host'a güvenme; anahtarlara ve kanıta güven."**

## 3. Primitif: Kendine-Sahip Ajan

Bir ajan A, dört bileşenin tutarlı bütünüdür:

| Bileşen | Tanım | Kural |
|---|---|---|
| **Kimlik** | ID_A = (pk_A, sk_A) | sk_A yalnız ajan runtime keystore'unda yaşar; host okuyamaz, yedekleyemez |
| **Hafıza** | M_A = Enc(K_A, G_A) | Bağlam grafiği G_A, ajan anahtarından türetilen K_A ile şifreli; host'a at-rest kör |
| **Yürütüm** | E_A = (W_A, F_A, P_A) | Kod W_A + manifest F_A + koşum kanıtı P_A; kanıt gücü sürümlenir: P0 (süreç+WASM sandbox) < P1 (TEE attestation) < P2 (zkVM) |
| **Cüzdan** | C_A | Ajan kendi anahtarıyla makine-native ödeme imzalar |

**Primitif deyimi (taşıma bütünlüğü):** A makinesi m1'den m2'ye taşındığında; ID_A, M_A ve C_A kayıpsızdır; yalnız E_A'nın makine-bağımlı kısmı m2 üzerinde yeniden gerçeklenir.

**Tek cümlelik test:** *Makine değişimi, ajanın kişiliğini değiştirmez.*

## 4. Sistem: Primitifi Gerçekleyen Değiştirilebilir Katmanlar

Primitif sabittir; aşağıdaki katmanlar değiştirilebilir:

- **Runner:** WASM koşumu (Wasmtime tabanlı), süreç+WASM izolasyonu (v0).
- **Bağlam Grafiği:** gömülü depolama + vektör arama; şifreli, taşınabilir snapshot (v0).
- **Muhasebe:** kaynak sayaçları (CPU-saat/RAM/IO) ve makine-başına ücretlendirme kayıt şeması (v0 simüle, v1 gerçek).
- **Taşıma:** snapshot → taşı → soğuk başlat (v0). Canlı göç araştırma konusudur, vaat değildir.
- **Keşif/İtibar ve Ödeme:** açık node katmanı; ödeme hazır standart üstünde (v1).

Katman seçim kuralları: *standart > kendin yaz; ölçüm > varsayım.*

## 5. Güvenlik Modeli

**Varlıklar:** sk_A, K_A, cüzdan bakiyesi, ajan kodu.

**Düşmanlar:** meraklı host operatörü, kötücül ajan, kamyoncu node, hataya düşen ajanın kendisi.

**Dürüst sınırlar:**

- v0 garantisi **at-rest** korumadır: şifreli snapshot'a operatör erişemez. **Kullanım-sırası (in-use) bellek koruması ancak TEE ile mümkündür ve v1'in konusudur** — bu ayrım hiçbir belgede belirsizleştirilmez.
- Koşum kanıtı sürümlüdür; "kanıtsız" koşum işaretlemeden geçmez.
- Cezalandırma (slashing) yalnız kanıta bağlı ihlallerde, v2'de gündeme gelir; öncesi itibar + dışlama mekanizmasıdır.

**Bilinen açık:** v0'da operatör, ajanın kullanım-sırasındaki belleğini görebilir. Bu nedenle v0, in-use gizlilik gerektiren iş yükleri için uygun değildir; ürün bu sınırı açıkça beyan eder.

## 6. Tarafsızlık Tasarımı

1. **Kural nötrlüğü:** primitif kuralları hiçbir node, ajan veya kurucuya ayrıcalık tanımaz.
2. **Veri nötrlüğü:** bağlam grafiği formatı açıktır; ajan verisini başka formata da dışa aktarabilmelidir. Lock-in = ihlal.
3. **Prosedür nötrlüğü:** kabul kuralları (test, kanıt) önceden yazılıdır; istisna yetkisi yoktur.
4. **Zaman nötrlüğü:** erken katılanlara kalıcı ayrıcalık yoktur.

## 7. Yönetişim ve Sahipsizliğe Geçiş

- **İnsan kapıları:** şifreleme, ödeme, izolasyon kodu; insan onayı olmadan canlı ağa dokunamaz.
- **RFC süreci:** protokol değişiklikleri yazılı teklif + kanıt ister; "değişmez kontrat" yerine değişmez olan yalnız kanıt kurallarıdır.
- **Exit to governance:** v0-v1'de kurucu kapıları açıkça ilan edilir; v1→v2'de kabul kuralları RFC'ye bağlanır; v2'de yetkiler zaman-kilitli mekanizmalara devredilir. Ölçülebilir hedef: *kurucunun kapattığı gün bile ağ çalışır.*

## 8. Ekonomik Katman

Primitif hiçbir ekonomik varsayım taşımaz: ödeme standartlar üstünde (x402 / L1 channel), ücret ve token tasarımı yalnız kullanım kanıtı sonrası (bkz. TOKENOMICS.md). Token, primitifin parçası değildir; primitif token'sız çalışmak zorundadır.

**Katman konumu (normatif):** x402 (ödeme taşıması) ve ERC-8004 (kimlik/keşif kaydı) **taşıyıcı standartlardır, çekirdek değildir**; her biri soyutlanmış, değiştirilebilir bir adaptör katmanında yaşar. Tamga'nın fark katmanı — koşum kanıtı, host-kör taşınabilir hafıza, kendi-anahtarlı ajan yaşamı — bugün hiçbir standardın iddia alanı değildir. Standart bağımlılığı sürüm pinlendiği sürece değil, katmanlar karışmadığı sürece risktir.

**Pazar kanıtı (2026-09, tarihli):** x402 Nisan 2026'da 165M+ işlem / ~69k aktif ajan / ~$50M hacime ulaştı; aynı kaynak hacmin kabaca yarısının test trafiği olabileceğini not eder — kategori gerçek, büyüme eğrisi doğrusal değil (RZLT x402 Explainer, Tem 2026; Chainalysis "100M agentic payments on Base", Q1 2026). ERC-8004 (Trustless Agents: Identity/Reputation/Validation kayıtları) 2026-09 itibarıyla Draft aşamasında (EIP-8004); ödeme bu standardın kapsamı dışında ve x402 ile örneklenir. Tamga'nın iddia alanı (kanıtlı koşum + host-kör taşınabilir hafıza + kendi-anahtarlı ajan) her iki standardın da dışında kalır — bu belge 2026-09 pazar verisiyle yazıldığında iddia güncelliğini korur.

## 9. Sınırlar ve Bilinmeyenler

- in-use koruma maliyeti ve TEE ölçeklenebilirliği (ölçüm gerekir)
- canlı göç (araştırma; v0-v1 kapsamı dışı)
- ajan kimliğinin hukuki statüsü (temsil yetkisi, sorumluluk) — hukuk danışmanlığına bağlı
- kendi zincirin gerekliliği — varsayılan: **hayır**

## 10. Yol

v0 (Runner + Bağlam Grafiği + Muhasebe; kabul testi AT-001) → v1 (açık node ağı + gerçek ödeme + TEE) → v2 (protokol + ekonomi + yönetişim). Aşama kapıları ve ölçülebilir metrikler: ROADMAP.md.

## Referanslar

Nakamoto, "Bitcoin: A Peer-to-Peer Electronic Cash System" (2008) · x402: The Payment Protocol for Agentic Commerce (x402.org whitepaper, Haz 2026) · RZLT, "Agentic Payments in 2026: The x402 Explainer" (Tem 2026) · Chainalysis, "Inside x402: 100M Agentic Payments on Base" (2026) · EIP-8004: Trustless Agents (Draft, eips.ethereum.org/EIPS/eip-8004; erişim 2026-09-05) · WASI 0.3.0 (ratifiye; wasi.dev/releases) · Wasmtime v48.0.1 (bytecodealliance, 2026-08-24) · AWS Nitro Enclaves / AMD SEV-SNP · Local-first software (Kleppmann) · Mem0/Letta/Zep (host-bağımlı hafıza çağdaşları; Mem0: 51k+ ★, $24M — preuve.ai, 2026)

*Belge güncellemesi: 2026-09-05 — §8 pazar kanıtı + referanslar Eylül 2026 verileriyle tazelendi (otonom geliştirme turu, goal-f7f9582e).*

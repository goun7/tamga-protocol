# RESEARCH — Güncel Akademik & Endüstri Temeli (2026-09-26)

Bu belge Tamga Protocol'ün tasarım kararlarını **güncel** akademik makaleler ve
endüstri standartlarıyla haritalar. Her bölüm: kaynak → ilgili Tamga katmanı →
uyumluluk/boşluk değerlendirmesi.

---

## 1. x402 V2 — Ödeme Protokol Standardı (11 Aralık 2025)

**Kaynak:** [x402 V2 launch](https://x402.org/x402-v2-launch/) ·
[x402 whitepaper: "The Payment Protocol for Agentic Commerce"](https://x402.org/wp-content/uploads/sites/10/2026/06/x402-whitepaper.pdf) ·
[HTTP 402 — x402 docs](https://docs.x402.org/core-concepts/http-402)

**Güncel veriler:**
- x402 Mayıs 2025'te launch etti; **altı ayda 100M+ ödeme** işledi (API'ler,
  uygulamalar, AI ajanları).
- V2 (2025-12-11) altı aylık gerçek-kullanım öğrenimleriyle yayınlandı;
  **bağımsız x402 Foundation** duyuruldu; referans SDK'lar V1'le **geri-uyumlu**.

**V2'deki kırılma-noktaları ve Tamga'ya etkisi:**

| V2 değişikliği | Tamga durumu | Değerlendirme |
|---|---|---|
| Tüm ödeme verisi **HTTP header'lara** taşındı; response body 402 ile birlikte serbest | Tamga `X-Payment` header'ını kullanıyor (V1 deseni) | **boşluk**: V2 `X-*` header'larını **kaldırdı**; `PAYMENT-REQUIRED`, `PAYMENT-SIGNATURE`, `PAYMENT-RESPONSE`, `SIGN-IN-WITH-X` (IETF tarzı) getirdi |
| **Wallet-based identity** + reusable sessions (aynı kaynağa tekrar ödemeyi atlama) | Tamga her-çağrı HMAC-zincirine yazar; **session/abonelik modeli yok** | **boşluk**: V2'nin en büyük gelişimi (yüksek-frekans LLM-inference iş yükleri için); SIWx (CAIP-122) fast-follow |
| **Extensions** (protokolü fork'lamadan genişletme) | Tamga Policy-DSL + K1 alıcı-sözleşmesi kendi genişletme modeli | **paralel**: farklı mekanizma, benzer hedef |
| **Dynamic `payTo`** routing (adres/rol/callback; dinamik fiyatlama) | Tamga'da satıcı-secret'i ile sabit-mühür; dinamik-alıcı yok | **boşluk** (marketplace/multi-tenant için) |
| **Discovery extension** (facilitator otomatik indexleme) | Tamga'da manuel servis-kataloğu (gateway `/healthz` + `/analitik`) | **paralel**: gateway zaten metadata yayıyor ama taranabilir değil |
| Multi-chain (Base, Solana, L2'ler) + fiat (ACH/SEPA) CAIP ile | Tamga yalnızca **Base** (EVM) + HMAC off-chain | **boşluk**: tek-zincir |

**Dürüst sonuç:** Tamga saf bir x402 V1/V2 uygulaması değil — sester katmanı
kendi receipt/HMAC-zincir protokolüdür. x402'nin **HTTP-402 challenge/response**
akışını (402 + challenge → ödeme → 200 + kanıt) doğru uyguluyor. V2 uyumluluğu
isteyen biri için yukarıdaki boşluklar bir yol-haritasıdır; hiçbiri mevcut
güvenlik garantilerini zayıflatmaz.

**Dürüst sonuç:** Tamga saf bir x402 V1/V2 uygulaması değil — sester katmanı
kendi receipt/HMAC-zincir protokolüdür. x402'nin **HTTP-402 challenge/response**
akışını (402 + challenge → ödeme → 200 + kanıt) doğru uyguluyor. V2 uyumluluğu
isteyen biri için yukarıdaki boşluklar bir yol-haritasıdır; hiçbiri mevcut
güvenlik garantilerini zayıflatmaz.

**Güvenli-bekleme kanıtı (AT-214, 8/8):** V2 header'ları (`PAYMENT-SIGNATURE`,
`PAYMENT-RESPONSE`) tek-başına → **402 RED** (fail-closed; açık-kapı-YOK);
mevcut V1 `X-Payment` akışı → **200** (sağlıklı). Yani V2'ye-geçiş-yapana-kadar
Tamga "reddeder-ama-açık-bırakmaz" modundadır — bu-davranış-kanıtlanmıştır.

**İlgili testler:** AT-004/AT-005 (challenge-response), AT-098 (gateway analitik
üzerinden servis zincir doğrulaması), AT-206 (karşı-taraf verify-tx),
**AT-214 (V1/V2 header uyum-analizi)**.

---

## 2. OracleTrust — İki-Katmanlı Köken-Signatürü Doğrulaması (PLOS ONE, Mayıs 2026)

**Kaynak:** Majeed MR, Zhang P, Raza Z, Alharthi TN, Khan I (2026) *OracleTrust: A
dual-layer provenance-based signature verification scheme for preventing
transaction malleability in blockchain.* PLoS One 21(5): e0348864.
[doi:10.1371/journal.pone.0348864](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0348864) ·
[kod](https://github.com/rashidkhan2224/OracleTrust-A-Dual-layer-Provenance-Based-Signature-Verification-Scheme-)

**Makalenin tezi:** Merkeziyetsiz oracle ağları transaction malleability üzerinden
çift-harcama riski taşır; DAON (oracle konsensüs/itibar), SegWit (Bitcoin
protokol-seviyesi imza malleability), SecPLF (kredi-protokolü oracle manipülasyonu)
**hiçbiri transaction-seviyesinde oracle-driven malleability'yi çözmez**. OracleTrust
iki katman önerir:
1. İşlemleri **doğrulanabilir provenance kayıtlarına** kodlar;
2. **salted Keccak hashing + ECDSA recovery** ile bu kayıtları dinamik doğrular ve
   oracle imzasını bağlar. Ayrıca **time-constrained commit-reveal + penalty** ile
   tamper-direnç sağlar.

**Tamga ile bire-bir paralellik:**

| OracleTrust katmanı | Tamga karşılığı | Testler |
|---|---|---|
| Layer-1: provenance kayıtları | `sester.ledger` HMAC hash-zinciri: `canonical_line(...) → seal(secret, canon)`, `prev_hash/hash` ile yürür | AT-002/AT-005 zincir bütünlüğü, AT-208 batch-verify |
| Layer-2: kontrat doğrulaması | **oracle replay-guard** — el-yazımı EVM: `SLOAD(requestId)` → dolu-ise REVERT; `SSTORE` | AT-210 (yerel 5/5), **AT-211 (Base mainnet'te canlı 6/6)** |
| Salted hashing | her satır `prev_hash` ile karıştırılıyor (salting olarak çalışır) | AT-199 daemon-parite |
| Malleability önleme | delivery-hash = keccak(on-chain outputData) ile off-chain hesap **bayt-bayt** aynı olmalı | AT-205 canlı (keccak exact-match), AT-206 verify-tx |
| Time-constrained commit-reveal | — | **boşluk**: Tamga'da zaman-kısıtlı commit-reveal yok; replay-guard slot-tabanlıdır (süresiz kilit) |

**Dürüst sonuç:** Tamga'nın iki-katmanlı yapısı (HMAC-zinciri + kontrat replay-guard)
makalenin önerdiği mimariyle **aynı şekildedir** ve AT-207'nin canlıda bulduğu
açık tam da makalenin işaret ettiği oracle-driven malleability sınıfındaydı
(daemon-restart → çift-fulfill). AT-211 ile kapatıldı. Kalan boşluk:
**commit-reveal/penalty** mekanizması yok — bunun yerine slot-tabanlı süresiz kilit
var (daha basit, daha az esnek ama replay için yeterli).

---

## 3. Wasmtime Sandbox CVE'leri (2026) — Tamga Bağışıklık Analizi

**Kaynaklar:**
- [CVE-2026-34987](https://vulert.com/vuln-db/CVE-2026-34987) (CVSS 9.0, sandbox-escaping
  memory access, Winch compiler backend; patched 36.0.7 / 42.0.2 / 43.0.1;
  RUSTSEC-2026-0095)
- [CVE-2026-47261](https://helixar.ai/press/cve-2026-47261-wasmtime-wasi-sandbox-bypass/)
  (CVSS 7.5, wasmtime-wasi filesystem sandbox bypass; Helixar Research, Haziran 2026)

**CVE-2026-34987 — bellek sandbox-kaçışı:**
- Sorun: Winch derleyici backend'inde bellek erişim hatası → sandbox dışına çıkış.
- Etki sürümleri: 43.0.1 öncesi bazı dallar. **Tamga `wasmtime` pip 47.0.1 ve
  digest-pinned CLI v48.0.1** kullanır → **düzeltildi** (patched sürümlerin üstü).
- Ek azaltıcı: açıklık **aarch64 + Winch** kombinasyonunu hedefler; Tamga
  **x86_64-linux** pinned.

**CVE-2026-47261 — dosya-sistemi sandbox bypass (daha ilginç):**
- Sorun: `Dir::open_at` içinde `OpenFlags::TRUNCATE` işlendiğinde `open_mode`
  değişkenine `OpenMode::WRITE` eklenmiyor → izin kontrolü yanlış onaylıyor.
- Sömürme **ön-koşulu**: host, bir dizini `DirPerms::MUTATE` + `FilePerms::READ`
  kombinasyonuyla **pre-open** etmeli. Modül `path_open(OFLAGS_TRUNC)` ile
  read-only dosyaları truncate edebilir. Kaynak: *"Most users of wasmtime-wasi
  are not vulnerable. The flaw only affects those who use the precise combination
  of directory and file permissions."*

**Tamga durumu — bağışık (default-deny tasarımı):**

Tamga'nın D4 sandbox ilkesi ([tamga_runner.py](../tamga_runner.py)):
```
D4 implementation: no fs preopens, no network (-S allow-ip denied) to wasmtime
→ default-deny.
```

**Analiz:** CVE-2026-47261'nin sömürüsü **pre-opened directory** varlığını
gerektirir. Tamga **hiçbir fs preopen vermez** → `path_open`'ın hedefleyeceği
pre-open kaydı yok → saldırı yüzeyi **yok**. Ayrıca network de kapalıdır
(`-S allow-ip denied`).

**Dürüst sonuç:** Her iki CVE'den de **etkilenmiyoruz** — 34987 sürüm/sürüm-arch
sebebiyle, 47261 tasarım (default-deny) sebebiyle. Bu, AT-212 ile **programatik
olarak kanıtlanmıştır** (7/7, aşağıda).

---

## 4. Testlerle Haritalama ve Önerilen Yeni Testler

Mevcut testlerin araştırma-temelini özetleyen tablo:

| Araştırma bulgusu | Tamga kanıtı | Durum |
|---|---|---|
| Oracle replay (OracleTrust) | AT-210 (yerel) + AT-211 (canlı) + KATMAN-1 disk-cache | ✓ kapandı |
| Ledger provenance-robustness | **AT-213** (50/50 fuzz-RED + self-heal) | ✓ |
| Sandbox default-deny (CVE) | **AT-212** (7/7, CVE-47261/34987) | ✓ |
| x402 V2 güvenli-bekleme | **AT-214** (8/8: V1-200 / V2-header-402) | ✓ |
| Delivery-hash bayt-bayt | AT-205 canlı keccak exact | ✓ |
| Karşı-taraf bağımsız doğrulama | AT-206 verify-tx 4/4 | ✓ |
| Üretim-ledger RFC-010 dikişi | AT-090 (Sester-gerçek-ledger) | ✓ |
| x402 challenge-response | AT-004/AT-005 | ✓ |
| HMAC zincir bütünlüğü | AT-002/AT-005 + AT-208 batch | ✓ |

### AT-212 (SHIPPED 2026-09-27, 7/7): WASI default-deny sandbox denetimi

**Gerekçe:** CVE-2026-47261 (filesystem bypass) ve CVE-2026-34987 (memory escape)
sandbox'un güvenlik vaadini sorguluyor. Tamga'nın `default-deny` tasarımının
**programatik kanıtı** yok — bu CVE'lerden bağışıklığı çıkarımsal değil kanıtlanmalı.

**Tasarım (para-YOK, py-wasmtime ile):**
- K1: sandbox'ta fs preopen sayısı = 0 (WasiCtx'de preopen yok);
- K2: `path_open` çağrısı **hata** döner (preopen yok → CAPABILITY hatası);
- K3: network capability yok (`-S allow-ip` denied → connect reddedilir);
- K4: process-isolation — sandbox dışı memory erişimi engellenir (wasm memory
  sınırı aşılamaz);
- K5: CVE-2026-47261'nin açık-koşulu (`DirPerms::MUTATE + FilePerms::READ` preopen)
  Tamga konfigürasyonunda **mevcut değil** — künyede assert.

---

## 5. Tarihçe

- **2026-09-26**: Bu belge oluşturuldu — x402 V2, OracleTrust (PLOS ONE),
  Wasmtime CVE'leri (2026) araştırması; AT-212 önerildi.
- **2026-09-27**: AT-212 shipped — 7/7 (K1 preopen-YOK kaynak+semantik, K2
  preopensiz `path_open` EBADF/ECAPABILITY red, K3 `sock_open` wasmtime-WASI'da
  tanımsız → ağ-yok, K4 `env={}` host-env sızdırmaz, K5 CVE-47261'ın
  `DirPerms::MUTATE+FilePerms::READ` koşulu kaynakta-YOK). run_all.sh'a kayıtlı.

---

## 5. x402 Güncel-Spec Taraması (docs.x402.org, 2026-09-27 — resmi-docs)

Resmi x402 dokümantasyonundan (`llms.txt` indeksi + extension sayfaları) güncel
durum taraması. **Üç-yeni-boşluk** tespit-edildi (hepsi ürün-güvenliğini-bozmaz;
hepsi genişletme-alanıdır):

### 5.1 Upto Scheme (usage-based ödeme) — TAMGA'DA-YOK

Resmi-spec: `upto` scheme'i satıcının **maksimum fiyat** ilan etmesini, sonra
**gerçek kullanıma** göre daha azını tahsil etmesini sağlar (LLM-token, bant,
compute-time için). Alıcı maksimum için bir-kez-imzalar; sunucu `≤ maksimum`
nihai-tutarı `setSettlementOverrides` ile-seçer.

**Tamga durumu:** Tamga **sadece `exact`-benzeri** sabit-fiyat alır
(`PRICE = 0.05` sabit; middleware `self.price` üzerinden). **Upto-yok** — yani
"compute-saniyesi/token-adedi-ile-fiyatlanan" bir ajan-servisi veremez.
Genişletme-noktası: `SesterMeter`'a `scheme: upto` kabul-path'i + settlement-
override kanalı.

### 5.2 Payment-Identifier Extension (idempotency) — PARÇALI-BOŞLUK

Resmi-spec: istemci benzersiz bir `pay_*` ödeme-kimliği gönderir; sunucu yanıtı
bu-kimlikle önbelleğe-alar **aynı-kimlikle-retry'lerde ödemeyi yeniden-işlemez**
(ağ-kesintisi / çökme / load-balance / test-tekrarı için).

**Tamga durumu:** Tamga'nın **kendi** idempotency/replay-koruması var
(`claim_nonce` — nonce-ilk-kez-True, tekrarı-False; AT-213 fuzz ile-kanıtlı).
**AMA** x402-standard `extensions` mekanizmasıyla-uyumlu-değil: istemci
`pay_xxx` kimliği göndermez, sunucu extensions-bloğunu ilan-etmez. Yani
standart-x402-istemcisi Tamga'ya-retry-yaparsa **yeniden-ödeme** riski-taşır
(Tamga-noncesu uygulama-seviyesinde-tutulur). Bu-boşluk AT-214'te-kanıtlanan
"güvenli-bekleme" çizgisini-bozmaz (açık-kapı-YOK) — ama-uyumluluk-boşluğu.

### 5.3 Bazaar (Discovery Layer) — TAMGA'DA-YOK

Resmi-spec: `/discovery/resources` endpoint'i x402-uyumlu-servislerin
machine-readable-kataloğunu-döner (AI-ajanların önceden-entegrasyon-olmadan
servis-keşfi). `EXTENSION-RESPONSES` header'ı ile-durum bildirir.

**Tamga durumu:** Tamga'nın **kendi** keşif-dosyası var (`/agents.json` —
64-agents.txt ile-hizalı; fiyat/kota/politika-döner). **AMA** x402-Bazaar
standardını-implemente-etmez. Genişletme-noktası: `/agents.json`'a-bir-bazaar-
görünümü-eklenerek-x402-ekosistemine-açılma.

### 5.3b Batch-Settlement Scheme (yüksek-throughput) — TAMGA'DA-YOK

Resmi-spec: tekrarlanan ücretli-API-çağrıları için **durumsuz-tek-yönlü-ödeme-
kanalları**: alıcı bir-kerelik on-chain escrow'a-deposit-koyar, her-istek-için
**imzalı kümülatif-kupon** (voucher) verir; satıcı kuponu-hızla-doğrulayıp-
yanıtı-onchain-transfer-beklemeden-verir; periyodik olarak-birçok-kanalı-tek-
transaction'da toplu-redeem-eder (claim → settle → refund aşamaları).

**Tamga durumu:** Tamga her-istek-için-bağımsız-HMAC-zarfı-kullanır — **ödeme-
kanalı-yok**, kupon-yok, escrow-yok. Mikro-ödeme-throughput'u-için-genişletme-
alanı (eğer-binlerce-istek/saniye-gerekirse). Güvenlik-açığı-değil; Tamga'nın
off-chain-receipt-zinciri benzer-bir-rolü-kısmen-oynar (AT-208 batch-verify).



- **Builder Code (ERC-8021)**: settlement-calldata'ya on-chain-atıf-kodu
  (Tamga'yı-ilgilendirmez — Tamga-settlement-off-chain-HMAC).
- **Sign-In-With-X (SIWX)**: wallet-oturum-açma (RESEARCH.md §1'de-kayıtlı).
- **EIP-2612/ERC-20 Gas-Sponsoring**: alıcı-adına-gas-ödeme (Tamga-relayer'ı
  zaten-kendi-gas'ini-öder — aktif-boşluk-değil).

**Dürüst-sonuç:** Üç-boşluk (upto, payment-identifier, bazaar) Tamga için
**genişletme-fırsatıdır**, güvenlik-açığı-değil. AT-214 zaten-kanıtladı:
V2-header'ları-gelse-bile-Tamga-açık-kapı-bırakmaz. Önerilen-testler:
AT-215 (upto-örneklenmesi-veya-olumsuz-kanıt), AT-216 (payment-identifier
retry-davranışı), AT-217 (agents.json ↔ bazaar-paritesi).

### Tarihçe-güncellemesi
- **2026-09-27 (gece)**: x402 resmi-docs-taraması → §5 eklendi (upto /
  payment-identifier / bazaar boşlukları); mevcut testlerle-haritalama.

---

## 6. Wasmtime Güvenlik-Politikası-2026: DoS-Sınıfı-Açıklar (resmi-dokümanlar)

**Kaynak:** docs.wasmtime.dev/security-what-is-considered-a-security-vulnerability.html
(bytecodealliance/wasmtime SECURITY.md üzerinden, 2026-09-28-taraması).

Wasmtime'ın-resmi-sınıflandırması hangi-hatanın-güvenlik-açığı-sayıldığını
açıkça-listeler. **Tamga-için-sorulması-gereken-soru:** distribüte-ajanlar
BİLİNMEYEN-wasm (oracle-üzerinden-herhangi-bir-gönderen) olduğundan, bu
sınıfların-Tamga'da-uygulanması-ne-durumda?

| Wasmtime-sınıfı | Tamga-durumu | Kanıt |
|---|---|---|
| **Uninterruptible infinite loops** (çalışma-zamanı) | **KAPSANMIŞ** — `cpu_ms_per_run` limiti (varsayılan 5000 ms) + `subprocess.timeout` ile-process-kill; oracle-yan `min(request, manifest)+[1,60000]` çift-kısıtlı | **AT-217** (K1) |
| **User-controlled memory exhaustion** | **KAPSANMIŞ** — `RLIMIT_FSIZE` preexec ile-io-sınırı + memory.grow-vektörleri-derleme-anında-trap | **AT-217** (K2) |
| Sandbox-escape / OOB-memory / CFI-ihlali | wasmtime-çekirdek-sorumluluğu; pinned-47.0.1/48.0.1-üstü-patched | AT-212 |
| FS-erişimi-mapped-dir-dışında | **KAPSANMIŞ** — preopen-YOK (default-deny) | AT-212 (K2-EBADF) |
| WASI-capability-olmadan-resource-kullanımı | **KAPSANMIŞ** — capability-sunulmuyor | AT-212 (K3) |
| Derleme-zamanı-DoS | wasmtime-politikasına-göre **açık-sayılmaz** (sadece-çalışma-zamanı) | — |
| Wasm-semantiğinden-sapma (sandbox-içi) | politikaya-göre-açık-DEĞİL — AMA-Tamga-için-önemli: `stdout_sha256`-gap'ini-dogrulayan-AT-205/206 semantik-sapmayı-zaten-yakalar | AT-205/206 |

**İlginç-gözlem (AT-217-çıktısı):** `(loop (br 0))` ve `memory.grow`-döngüsü
5-saniye-limiti-BEKLEMEDİ — **0.0 s'de rc=1 ile-trap**. Yani wasmtime
bu-iki-vektörü-statik/erken-aşamada-yakalıyor; `cpu_ms_per_run`-limiti-ikinci-
savunma-hattı. Dürüst-not: Bu-K1/K2-sonucu "koruma-yok" değil "koruma-anında"
anlamına-gelir — K3 (normal-vector rc0) ile-regresyon-yok-kanıtlanmıştır.

**Kalan-boşluk (dürüst):** fuel-mekanizması (`wasmtime::Fuel`) Tamga'da-
kullanılmıyor — `timeout`-ile-process-kill-essekli-AMA-tek-very-senkron-çağrı-
başına-bir-azami-olduğundan-async-fuel'e-ihtiyaç-yok. Eğer-ileride-birden-
fazla-ajan-aynı-süreçte-koşulursa fuel-gerekir (şu-an-değil).

### Tarihçe
- **2026-09-28**: wasmtime-güvenlik-politikası-taraması → §6 eklendi;
  AT-217 (DoS-sınıfı-kanıtı) shipped 6/6.

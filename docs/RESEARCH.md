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

**İlgili testler:** AT-004/AT-005 (challenge-response), AT-098 (gateway analitik
üzerinden servis zincir doğrulaması), AT-206 (karşı-taraf verify-tx).

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
sebebiyle, 47261 tasarım (default-deny) sebebiyle. Bu, AT testiyle **kanıtlanabilir**
(sıradaki adım: AT-212, aşağıda).

---

## 4. Testlerle Haritalama ve Önerilen Yeni Testler

Mevcut testlerin araştırma-temelini özetleyen tablo:

| Araştırma bulgusu | Tamga kanıtı | Durum |
|---|---|---|
| Oracle replay (OracleTrust) | AT-210 (yerel) + AT-211 (canlı) + KATMAN-1 disk-cache | ✓ kapandı |
| Delivery-hash bayt-bayt | AT-205 canlı keccak exact | ✓ |
| Karşı-taraf bağımsız doğrulama | AT-206 verify-tx 4/4 | ✓ |
| Sandbox default-deny | (kanıt yok) | **→ AT-212** |
| x402 challenge-response | AT-004/AT-005 | ✓ |
| HMAC zincir bütünlüğü | AT-002/AT-005 + AT-208 batch | ✓ |

### AT-212 (önerilen): WASI default-deny sandbox denetimi

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

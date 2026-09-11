# RFC-007 — v0.2 Schema Revision (R1–R3 UYGULANDI; R4 aday)

> **Durum: IMPLEMENTED (2026-09-07, kurucu-onaylı; R1 5819be0 · R2 6782614 · R3 19028ca).**
> Bu-başlık-üç-değişimin-HANGİ-SEMADA-yaşadığını-kamu-yüzeyinden-beyan-ediyor; ilke-değişikliği
> YOK: makbuz-içeriği-yine-gizli, hash-bağı-yeni-BAĞ-ekler, donmuş-v0.1-doğrulaması-aynen-kalır.
> R4-(imzalı-RED-kanıtı)-aday-notu-olarak-durur-(§5b); pilot-kapılı-maddeler-açıkça-etiketli.
> Kaynak-taslak: private/RFC-007-v02-sema-revizyonu-TASLAK.md-(kurucu-soru-cevap-turu-2026-09-07).

## 0. Kapsam-özet (üç-değişim, hepsi-additive)

| # | Değişim | v0.1-durumu | v0.2-gerçekleşen | Durum |
|---|---------|-------------|------------------|-------|
| R1 | `runtime.net` manifest-eyleyişi | net.json ara-dosyası | beyan `tamga.json`'a-taşınır; tek-yön-migrasyon-aracı | ✅ UYGULANDI (AT-009) |
| R2 | D10 `delivery_hash {alg,hex}` | YOK (RFC-003 §10-adayı) | charge'a-OPSİYONEL-etiketli-öz | ✅ UYGULANDI (AT-010) |
| R3 | D12-formalizasyonu | koşullu-üç-alan (uygulamada) | şemada-resmi-koşullu-alan-seti | ✅ UYGULANDI (AT-011) |

Çift-okuma-penceresi-(net.json-ve-runtime.net-ikisinin-de-geçerli-olduğu-dönem):
**1-sürüm-döngüsü**-(kurucu-kararı, 2026-09-07; öneri-benimsendi).

## 1. R1 — `runtime.net` (M6-manifest-entegrasyonu) — UYGULANDI

Beyan-`tamga.json`'ın-`runtime`-objesine-taşınır-(net.json-içeriği-aynen):

```json
"runtime": {
  "net": {
    "endpoints": [ {"host": "api.ornek.com", "port": 443, "proto": "https"} ],
    "timeout_s": 30,
    "byte_cap_total_mb": 2,
    "byte_cap_endpoint_mb": 1
  }
}
```

**Gerçekleşen-kararlar-(taslaktan-sapmalar-dahil, dürüst):**
- Saklanan-alt-ağaçta-`format`-anahtarı-YOK-(konum-kendisi-formatı-implied-eder);
  doğrulama-zamanı-setdefault-ile-şema-birliği-sağlanır.
- **D12a-manifest-anlamı** = `sha256(jcs(runtime.net-subtree))` — jcs-canonical-invariant
  (bayt-birebir-değil); v0.1-net.json-paketleri-dosya-bayt-semantiğini-korur.
- Validator-runtime.net'e-ŞEKİL-kapısı-ekler-(additive); DNS-çözümleme-runner'da-fail-closed.
- `migrate-net`: tek-yön; yazar-seed-zorunlu-(pubkey≠signature.key → RED 9); imza-D2
  sig-boş-probe-üzerinden; göç-sonrası-validator-ACCEPT-kapısı; köprü-dosyası-silinir;
  İKİ-kaynak-varlığı → RED 10 `net_decl_ambiguous`-(politika-iki-anlamlılığı).
- Kanıt: AT-009-(kontrol-22; migrate/bağlama/ambiguous/dual-read/şema-RED/kimlik);
  crossval-bozulmadı.

## 2. R2 — D10 `delivery_hash {alg, hex}` — UYGULANDI (safal207-düzeltmesiyle)

- `run --delivery-alg sha256|keccak256` → charge'a-OPSİYONEL: `delivery_hash: {"alg":
  "sha256"|"keccak256", "hex": "<64-hex>"}`; alan-yoksa-D4-sessizlik.
- **Anlam:** satıcının-x402-settlement-zarfındaki-`extensions["durable-evidence"].contentHash`
  değeriyle-AYNI-baytların-etiketli-özeti. Üçüncü-taraf-kenetleme:
  `receiptHash → makbuz → delivery_hash → contentHash (zarf)` zinciri-bağımsız-doğrulanır.
- **Etiket-ZORUNLU**-(safal207, x402-#3379: keccak256 ≠ sha256 — etiketsiz-alan-sahte-uyum
  üretir). Doğrulayıcı: `alg`-bilinmiyorsa-RED `delivery_alg_invalid`-(charge-oluşmadan);
  `hex`-64-değilse-RED; ledger-verify-şekil-kapısı-(savunma-derinliği).
- **Kapsam-cümlesi**-(safal207-önerisi-benimsendi): alan-yalnız-bayt-bütünlüğü-ve-bağlama
  dairdir; icra-kalitesi/settlement-kesinliği/alıcı-kabulü-iddia-ETMEZ.
- holistis-köprüsü: capacity-attest `evidenceHash`→`receiptHash` çapası-bu-alan-üzerinden
  taşınır-(üçlü-kenetleme); v0.2'de-ayrı-alan-AÇILMAZ.
- Kanıt: AT-010-(kontrol-23; 6/6-dahil-pairing-fixture-delivery_hash-kenetlemesi);
  keccak-özet-x402-contentHash-dünyasıyla-birebir-(bağımlılık-yok-tamga_keccak).

## 3. R3 — D12-formalizasyonu (RFC-003 §11'in-şemalaşması) — UYGULANDI

Üç-alan-şema-düzeyinde-**koşullu-birlik**-kuralına-bağlanır:

- `net_decl_sha256` ↔ `net_events_sha256` ↔ `net_mb` — **BİRLİKTE-ya-girer-ya-girmez**
  (`net_trio_incomplete` RED); tetik: pakette-`runtime.net`-(veya-geçiş-penceresinde
  net.json)-varlığı → üçü-de-ZORUNLU; yokluğu → üçü-de-YASAK-(sessiz-D4-koşumu-"harcadı"-
  gösteremez).
- `net_mb`-formalitesi: sayı, MiB-6-hane-(RFC-003 §11-yuvarlama-kuralı-normatif;
  `net_mb_format` RED).
- Validator-bağlaması-AKTİF-kaynağa-göre-(net.json=bayt-hash / runtime.net=jcs-hash):
  post-run-swap → `net_binding_mismatch`; köprü-silme → `net_binding_missing`;
  re-sign-tamper → RED; çift-kaynak → `net_decl_ambiguous`.
- Kanıt: AT-011-(kontrol-24); crossval-runtime.net-şekil-ailesi-8-mutant;
  deletion-detection-eklendi.

## 4. Geçiş-penceresi (çift-okuma) — kurucu-kapanmış

- v0.2-doğrulayıcı: net.json'lu-VE-runtime.net'li-paketleri-kabul-eder; üretim-yönü
  net.json'ı-ARTIK-üretmez-(aracı-tek-yön).
- v0.1-doğrulayıcılar-DEĞİŞMEZ: v0.2-alanlarını-bilinmeyen-alan-olarak-RED-etmez
  (RFC-003 §3-normatif-bölümüyle-uyumlu).
- Süre: **1-sürüm-döngüsü**-(kurucu-kararı-2026-09-07; öneri-benimsendi).

## 5. Şema-terfisi-kanıtı

`specs/manifest-0.2.0.schema.json`-(const-0.2.0;-promoted); 0.3.0-draft-tabani
`["0.2.0","0.3.0"]`; crossval-60/60-AGREE-(v0.2.0-flip-sonrası-rebased).
v0.1-manifest'leri-additive-pencerede-geçerli-kaldı-(kanıtlanmış).

## 5b. R4-aday-notu — imzalı-RED-kanıtı (pilot-kapılı; UYGULANMADI)

- Örnek-(#3379-wildcherrycasa)-çevrimdışı-teyit: COSE_Sign1/Ed25519 + JWKS + 206-satır-
  standart-kütüphane-doğrulayıcı; DENY-kararı-başarısız-olacak-kontrolü-adıyla-taşıyor.
- Tamga-karşılığı: net_denied-olayları-zaten-politika-beyan-hash'iyle-bağlı-(net_decl_sha256-
  deseni: "bu-politika-altında-bu-zamanda-reddedildi").
- Aday-R4 = koşum-DIŞI-bağımsız-imzalı-DENY-artifact'ı-(dış-auditor-için); çapası-politika-
  beyanıdır-(settlement-DEĞİL). v0.2-kapsam-sorusu-olarak-pilot-günüyle-masada.

## 6. Kapılar-(kurucu-normatif; bu-dokümanda-DEĞİŞMEZ)

- R1-R3: uygulanmış-ve-kilitli-(AT-kanıtlarıyla); geri-dönüş-yalnız-YENİ-RFC-ile.
- R4: pilot-kapılı; uygulanmadı.
- 0.3.0-şema-(external_receipt): RFC-008-P8-kapısıyla-bağlı.

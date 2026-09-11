# RFC-008 (TASLAK) — External Receipt Binding (x402 / very-rail evidence köprüsü)

> **Durum: DRAFT — PILOT-PENDING.** Bu-başlık-FAZLA-şey-iddia-etmez: pilot-semantiği
> (ultravioleta-consented-teslimatı: plaintext-payer'a-mühürlü-davranışı)-BELLİ-OLMADAN
> alan-kuralları-SON-hale-GELEMEZ. Aşağıdaki-metin-pilot-gelince-§3'te-işaretlenen-üç-açık
> kapalıyca-rfc-numarası-alır. Derleme-disiplini: hiçbir-bölüm-uygulamaya-girmez ( WHITEPAPER
> §8-paraleli: düşünmek-bedava, kodla-değil).

## 0. Özet (one-paragraph)

Bir-Tamga-charge-kaydına-İKİNCİ-bir-dünyadan-kanıt-bağlanabilir: dış-rail-(x402 gibi)-üzerindeki
ödeme/deliver-kanıtının-ÖZETİ. Bu-RFC-yeni-bir-hash-tanımlamaz; yalnız-VAROLAN-iki-dünyanın
alanlarını-alg+hex-ETİKETLE-bağlar (RFC-003 D5/RFC-007 D10-disiplininin-genişletmesi).

## 1. Motivasyon

- Pilot-gününde-tek-komutla-(--pair-charge)-iki-dünyanın-hash'i-EŞ mi?-kararı-verilebilsin
- Sadece-bizim-zincirimizi-değil, dış-ekibin-receipt'ini-de-doğrulanabilir-kılmak ( B2-Bundle-UYUMLU)
- Rail-bağımsızlığı: x402-bir-ÖRNEK; alan-şeması-'rail'-şeklinde-GENEL (multi-rail-memo-uyumlu)

## 2. Alan-şeması (ADDITIVE, charge-record-içinde)

```json
"external_receipt": {
  "rail": "x402",                          // string, rail-adı (aşağıda-regex)
  "receipt_id": "0x7e7c…87ec",             // rail'in-kendi-paymentId'si-(kanonik-rendering: 0x+64-lowercase)
  "content_hash": {"alg": "keccak256", "hex": "…"},   // rail-üzerinde-declar-EDILEN-hash
  "receipt_uri": "https://…/dx402/receipt/0x7e7c…87ec" // İsteğe-bağlı; alınma-yeri
}
```

**Kurallar (v0-taslak):**
- R8-1: `rail`-∈-[a-z0-9-]{1,24}; `receipt_id`-kanonik-rendering-0x+64-lowercase-(x402-#3377-ile-aynı-disiplin)
- R8-2: `content_hash.alg`-∈-{sha256, keccak256} (mevcut-D10-etiket-listesiyle-aynı)
- R8-3: `external_receipt`-VARSA-chain-verify-shape-gate-(RFC-007-R2-defensive-depth-modeli)
- R8-4: EŞLİK-KURALI (en-önemli): charge.delivery_hash ≠ external_receipt.content_hash
  olabilir — bunlar-FARKLI-byte-popülasyonları-üstünde-iki-bağlamdır ( bizim-delivery-bytes
  vs onların-plaintext). Eşitlik-'ASSUMED-DEĞİL': yalnız-AYNI-baytlar-teslim-edildiğinin
  İKİ-TARAFLI-beyanı-(pilot-günündeki-consented-teslimat)-ile-'DERIVED-EQUAL'-etiketi-alır.
- R8-5: SILINME: dış-rail-retention-dolabilir ( 404-vakamız); bundle-'receipt_uri'-+alim-tarihini
  saklar-'retention_note'-serbest-alanı-EKLER ( makine-okur-reason-#3377-teklifimizle-uyumlu)

## 3. PILOT-PENDING — pilot-gelince-karara-bağlanacak-üç-açık

| # | Açık-soru | Pilot-gününde-çözülecek-kanıt |
|---|---|---|
| P8-1 | `content_hash`-x402'de-plaintext-üstünde; bizim-`delivery_hash`-served-bytes-üstünde — iki-hash-kökü-FARKLI. Pilot-consented-teslimatta-bir-üçüncü-hash (plaintext↔delivered-eşliği)-ihtiyacı-doğar-mı? | ultravioleta-113B-teslimatı: plaintext-verilirse-türetim-yapılır |
| P8-2 | ECR-lerin-retention-gerçek-sınırları ( bizim-404-vakası-öğretti: varsayım-YAPMA) | receipt.retentionUntil-alanı-makbuzla-doğrulanır |
| P8-3 | `receipt_uri`-kamu-URL mi-auth-altında-mı — bundle-KÖPRÜ-değil-yalnız-REFERANS | #3379-kapanış-yorumu-netleştirir |

## 3a. SELF-PILOT-ÖZ-CEVAPLARI (2026-09-11, AT-020) — taslak-cevaplar, kapı-YAŞAR

> AT-020 (kontrol-42, slow) üç-bacaklı-teslimatı-ELDE-KANITLADI: delivered/ran/satisfied
> (`.evidence/SELF-PILOT/2026-09-11/`). Aşağıdaki-ö-cevaplar-VERİYLE-yazıldı — kapı-yine-pilot-günü:
> dış-rail-olmayınca-bu-kanıt-İÇ-kalırdır, x402-tarafı-eklenince-aynı-üç-soru-dış-tarla-yeniden-sorulur.

| # | Soru | Öz-cevap (self-pilot-verisiyle) | Pilot-günü-ne-değişir |
|---|---|---|---|
| P8-1 | Üçüncü-hash (plaintext↔delivered eşliği) gerekir mi? | HAYIR-ilave-alan-gerekmez: `pilot-accept`-doc'u İKİ-hash'i-birden-taşır (`delivery_hash` + `delivered_sha256`) — alıcı-iki-kökü-aynı-beyanda-imzalar; ayrı-alan-EKLENMEZ (şema-satır-içi-çözüm) | x402-`content_hash`-(plaintext-kökü)-üçüncü-kök-olursa-beyana-EKLENİR; eşlik-yine-ASSUMED-DEĞİL-imzalı |
| P8-2 | Retention-gerçek-sınırları | Self-pilot'ta-silinme-YOK (evidence-donuk-diskte); `retention_note`-alanı-opsiyonel-kaldı, İÇ-kanıtta-boş | Dış-rail-404-gelirse-aynı-alan-doluyor (404-vakası-dersimiz) |
| P8-3 | `receipt_uri` kamu URL mi auth-altında mı | Self-pilot'ta-uri-YOK — İÇ-teslimatta-dış-adres-ANLAMSIZ; uri-alanı-OPTIONAL-kalmalı | Dış-pilot-URI'si-gelirse-public/auth-durumu-TEK-SEFERLİK-tespit-edilir |

**Bulgu (ö-cevap-modundaki-tek-yapısal-çıkarım):** İÇ-teslimatta-happy-path "beyan-önce, URI-sonra" —
yani-uri-OPTIONAL + retention_note-OPTIONAL. Dış-rail-katkısı-gelince-bu-üç-üde-TEK-PILOT-GÜNÜ-KAYDI
normalize-edilir. Şema-M6-(v0.3.0-draft)-bu-üç-opsiyonelligi-zaten-yansıtıyor — değişiklik-YOK.

## 4. Pilot-sonrası-yol

1. Pilot-kapanışı→§3-üç-açık-kapalı→bu-taslak-RFC-008-numarasını-ALIR
2. `validator`-schema-(v0.3-draft)-+ `ledger-verify`-shape-gate-(R8-3)-uygulanır
3. `--pair-charge`-tool-uzantısı: external_receipt-varsa-OTOMATİK-köprü-kararı
4. x402-#3377'ye-'external-ledger-binding'-extension-PR-önerisi-(E1-kapısı)

## 5. Neden-ŞİMDİ-yazılıyor (ve-neden-uygulanmıyor)

Pilot-günü-ÇOK-yakın. Taslak-hazırken-iş-başlamıyor: pilot-bilgisi-§3'ü-değiştirebilir
(üç-açık-soru-işi-bağlayabilir). Kurucu-kültürü-uyumu: "düşünmek-bedava, kodla-değil".

## 6. F1 — TAMGA_EXTERNAL_ANCHOR_V1 (2026-09-10, kurucu-ONAYLI-çerçeve)

> Yön-çevrimi: §1-5 x402-dış-receipt'i-BİZİM-zincire-cite ediyor. §6 TERSİ: bizim-zincir-
> başlarının-dış-epoch-fact'lere-bağlanması. İkisi-aynı-RFC'nin-iki-yüzü — V0.2-diliminde-
> birlikte-girer.

- **Tasarım-dosyası**: private/F1-EXTERNAL-ANCHOR-TASARIM.md-(anchor-op-şekli: foreign_registry/
  foreign_fact/foreign_digest/foreign_source + verified_at-iki-alanlı-iddia)
- **Dondurulmuş-matematik**: tests/vectors/anchor-v0-design/anchor-design-vector.json +
  AT-017-(kontrol-39): D5-uyumu-(anchor-kaydı-her-kayıt-gibi-zincir-hash'ine-girer)-
  ve-§4.4-parite-(bilinmeyen-registry→indeterminate, never absent)-kanonik-beyanlı
- **Kanıt-bağlantısı**: .evidence/APODIX-EPOCH-10/2026-09-10/ — ilk-gerçek-dış-anchor-adayı
  (fact-0x0236…36e2, 2-bağımsız-keccak-uygulaması-aynı-merkle-yolunda-eşleşti)
- **Kapı**: const-flip-(verifier-known-tags+runner-op)-pilot-SONRASI; P8-1/2/3 ile-aynı-kapıdan-
  geçer — pilot-günü-4-açık-(P8-1..3 + F1-etiket-uyumu-Vauban'la)-kapalı-olur

## 8. GERIBILDIRIM-YUZEYI (2026-09-10, E1-gitti)

- Kamu-tartismasi: x402-foundation/x402#3447 (DRAFT-proposal-issue; non-binding)
- Bu-taslagin-kaderi orada-kararasir; PR-yalniz P8-1..3 cevaplandiktan-sonra

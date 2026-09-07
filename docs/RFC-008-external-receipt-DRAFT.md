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

## 4. Pilot-sonrası-yol

1. Pilot-kapanışı→§3-üç-açık-kapalı→bu-taslak-RFC-008-numarasını-ALIR
2. `validator`-schema-(v0.3-draft)-+ `ledger-verify`-shape-gate-(R8-3)-uygulanır
3. `--pair-charge`-tool-uzantısı: external_receipt-varsa-OTOMATİK-köprü-kararı
4. x402-#3377'ye-'external-ledger-binding'-extension-PR-önerisi-(E1-kapısı)

## 5. Neden-ŞİMDİ-yazılıyor (ve-neden-uygulanmıyor)

Pilot-günü-ÇOK-yakın. Taslak-hazırken-iş-başlamıyor: pilot-bilgisi-§3'ü-değiştirebilir
(üç-açık-soru-işi-bağlayabilir). Kurucu-kültürü-uyumu: "düşünmek-bedava, kodla-değil".

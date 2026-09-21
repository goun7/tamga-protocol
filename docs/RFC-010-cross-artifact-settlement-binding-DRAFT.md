# RFC-010 (TASLAK) — Cross-Artifact Settlement Binding

> **Durum: DRAFT — pilot-öncesi-tasarım.** Bu-başlık-x402#3379'da-safal207'nin-önerdiği
> "cross-artifact-settlement-binding"-dikişinin-Tamga-tarafıdır. safal207'nin-açık-
> teşhisi: *"wiring those existing artifacts together now would demonstrate the join
> shape, not prove that both artifacts belong to the same purchase."* Bu-RFC-o-dikişin
> **kanıta-dönüşmesi**-içindir.

## 0. Özet (one-paragraph)

Bir-ajan-çalışmasını-x402-ödeyen-bir-işleve-bağlamak-için-beş-bağımsız-kontrolü
**tek-bir-verify-gate'inde**-toplar: receipt-doğrulanır, claim-doğrulanır,
settlementRef-çözümlenir, payer/payee-alanları-buyer/seller-ile-eşleşir, ve
evidenceHash == receiptHash-bayt-eşittir. **Hiçbiri-tek-başına-yeterli-değil** — beşi-birden
kanıtlar; **biri-bile-farklıysa-tümü-RED** (fail-closed). Şema-değişikliği-yok: mevcut
`charge`-delivery_hash-alanı-ve-x402-claim-alanlarını-bağlar.

## 1. Motivasyon — neden-bu-dikiş-şimdi

TRM Labs'in-x402-ödemelerinde-bulguduğu **%0.6–7.5-agentic-oran** bu-dikişin-yokluğundan-doğar:
bir-settled-transaction-değeri-taşır, **modelin-satın-alma-kararı-verdiğini-kanıtlamaz**.
safal207-nin-kesin-listesi:

> `receipt verifies + claim verifies + settlementRef resolves + payer/payee match
> buyer/seller + evidenceHash == receiptHash, with a swapped hash or party as the
> negative control. No schema changes needed on either side.`

Bu-beşi-bugün-bizde-ayrı-ayrı-var-ama **bir-araya-gelmiyor** — bu-dikişin-bulunmaması
"join shape"-gösterir-"proof"-vermez.

## 2. Kayıt-şekli (YENİ-op-YOK — mevcut-alanları-bağlar)

Dikiş-tek-bir-charge-kaydına-bir-`settlement_bind`-alanı-ekler (additive, op-yok):

```json
{"op": "charge", "seq": N, "prev": "<64hex>", "h": "<64hex>",
 "stdout_sha256": "<64hex>",                        // receiptHash-yarısı (Tamga)
 "delivery_hash": {"alg": "sha256", "hex": "<64hex>"},  // iş-teslimi (safal207: etiket-zorunlu)
 "settlement_bind": {                                // YENİ-additive-alan
   "scheme": "x402/v1",
   "payment_id": "<string>",                         // x402-paymentId (claim'ten)
   "claim_evidence_hash": {"alg": "sha256", "hex": "<64hex>"},  // tokenizen-evidenceHash
   "payer": "0x<40hex>",                             // x402-claim-buyerAddress
   "payee": "0x<40hex>",                             // x402-claim-sellerAddress
   "verified_at": "2026-09-21T00:00:00Z"}}           // RFC3339-Z (R9-4-ile-aynı-kural)
```

**Neden-additive-alan-op-değil:** op-yeni-bir-yazım-sınıfı-açar (GATES/EMITTED_OPS-
denetimi); alan-eklemek-sürüm-terfisiyle-yönetilir-ve-D5-zincir-hash'ine-zaten-girer
(kayıt-tamamı-hash'lenir). Bu-aynı-zamanda-`anchor`-op'unun-R9-5-ilkesini-korur:
**dikiş-kanıtı-KAYIT-yapar, dış-claim'i-DOĞRULAMAZ** — doğrulama-aşağıdaki-§3-gate'inde.

## 3. Doğrulama-sözleşmesi (beş-bağımsız-kontrol, tek-gate)

`tools/settlement_bind_verify.py` — saf-stdlib, üç-verdict:

| # | Kontrol | Ne-kanıtlar | Başarısız-verdict |
|---|---|---|---|
| 1 | **receipt-verifies** | charge-kaydının-D5-zinciri-ve-delivery_hash-geçerli | RED `receipt_invalid` |
| 2 | **claim-verifies** | x402-claim'in-imzası-buyerAddress'e-çözümlenir (EIP-191) | RED `claim_signature_invalid` |
| 3 | **settlementRef-resolves** | claim'in-settlementRef'i-payment_id-ile-eşleşir | RED `settlement_ref_mismatch` |
| 4 | **payer/payee-match** | claim-buyerAddress==bind.payer-VE-sellerAddress==bind.payee | RED `party_mismatch` |
| 5 | **evidenceHash == receiptHash** | claim-evidenceHash.bayt-eşit == charge-delivery_hash.hex | RED `evidence_hash_mismatch` |

**Fail-closed-kuralı (safal207'nin-önerisinin-özü):** herhangi-biri-RED → tümü-RED.
Kısmi-GREEN-YOK. Bu, "join shape"-gösterme-tuzağını-kapatır.

**Negatif-kontroller (safal207: "swapped hash or party"):**
- `evidenceHash`-byte'ları-çevrildi → 5-RED (geri-kalan-4-GREEN-olsa-bile)
- `buyerAddress`/`sellerAddress`-yerdeğişti → 4-RED (1,2,3,5-GREEN-olsa-bile)
- `payment_id`-harf-değişti → 3-RED

**Bilinmeyen-scheme:** İNDETERMİNE (RED-değil — safal207'nin-x402'yı-zorlamama-
ilkesiyle-uyumlu; `scheme`-listesi-additive: `x402/v1`, `tamga/native`, `erc8004/v1`).

## 4. NE-ŞİMDİ / NE-SONRA

**ŞİMDİ:** (a) bu-tasarım-notu; (b) `settlement_bind`-alanının-additive-tanımı;
(c) `tools/settlement_bind_verify.py`-beş-kontrollü-üç-verdict; (d) AT-060-testi-beş-
negatif-kontrolle (swap-hash, swap-party, ref-mismatch, sig-invalid, chain-broken).

**SONRA (pilot-günü):** (e) gerçek-x402-claim-fixture'ı-ile-canlı-dikiş;
(f) tokenizen-tarafın-şema-hizalaması (holistis-x402#3379'da-önerdi); (g) `scheme`-
listesine-`tamga/native`-ve-`erc8004/v1`-eklenmesi (R9-2-additive-terfisiyle).

## 5. Riskler (dürüst)

- **Doğrulama-yükü-çoğalıyor:** her-scheme-için-ayrı-claim-doğrulama (§3-kontrol-2).
  Bugün-yalnız-x402/EIP-191; her-yeni-kanal-yeni-imza-doğrulama-kodu-demek. Bu-
  RFC-o-yükü-gizlemiyor-ama `scheme`-dispatch-ile-yerinde-tutuyor.
- **evidenceHash-alanı-tokenizen'ın-inkarı:** biz-evidenceHash'i-claim'den-okuruz;
  tokenizen-onu-silip-ços-mutasyonu-yaparsa-dikiş-kırılır. Çözüm: evidenceHash-
  claim'de-ZORUNLU (yoksa RED — "swap"-negatif-kontrolleri-gibi).
- **Üçüncü-seçenek-yasak-burada-da:** scheme-listesinde-olmayan-bir-kanal-RED-
  VERMEMELİ (İNDETERMİNE) — yoksa-sessizce-işlem-öldürürüz. Bu-§3'te-beyanlı.

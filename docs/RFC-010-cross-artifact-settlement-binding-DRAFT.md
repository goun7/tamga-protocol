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

### 3b. İmza-doğrulama-arayüzü (kanal-başına-giriş-şekli) — AT-077-dersi

Kontrol-2'nin-imza-doğrulaması-**scheme-başına-farklı-giriş-ister**. Bu-yüz-
den-her-üç-kanal-aşağıdaki-tabloda-sabitlenmiştir (AT-077-öncesi-bu-sabitlik-
yoktu-ve-iki-stub-gizli-boşluk-taşıyordu —bkz-§5b):

| scheme | imzalanan-şey | imzalayan-kimliği-nasıl-çözülür |
|---|---|---|
| **x402/v1** | sha256-digest'ın-ham-baytları (`z=raw-sha256`; EIP-191-öneksiz) | `ecrecover_to_pub(digest,sig)` — kayıptan-adres |
| **tamga/native** | sha256-digest'ın-ham-baytları (RFC-8032-mesaj=32-byte-digest) | genel-anahtar-açıktır: `claim.buyerAddress`=pubkey; nacl-ile-doğrulanır,-esleşirse-yine-pubkey |
| **erc8004/v1** | üyelik-kanıtı (imza-yok; kök-hash-kimliktir) | kök-hash → `keccak256(digest)` |

**Neden-digest-üzerine (gövde-metni-değil):** gate-ile-producer-aynı-JSON-
serialization'ı-paylaşmak-zorunda-değildir (gate `sort_keys=True`-varsayılan-
separatorler-ile, Yieldix `separators=(",",":")`-ile-serialize-eder — baytlar-
farklı, nesne-aynı). Ed25519-ham-mesaj-üzerine-imza-atıldığında-her-iki-tarafın-
aynı-baytları-bilmesi-gerekir; digest-üzerine-atıldığında-ise-**sadece-64-hex-
özütün-eşitliği-yeterlidir** — bu-zaten-kontrol-5'in-talep-ettiği-bayt-eşitliğidir.
Yani-imza-kanalı-ile-evidenceHash-kanalı-aynı-bağlamda-birleşir.

**AT-075-ile-paralel-gerçek:** `x402/v1`-de-`z=raw-sha256`-kuralı-aynı-şekilde-
`encode_defunct`-yapılmadan-imzalanmayı-gerekli- kılar; `tamga/native`-de-aynı-
giriş-şekli-digest-baytlarıdır. Üçüncü-seçenek-yasak: bu-sözleşme-dışında-imza
RED-değil-İNDETERMİNE-değil — doğrudan-RED rc4 (kanal-tanımlı-ama-imza-yanlış).

## 4. NE-ŞİMDİ / NE-SONRA

**ŞİMDİ:** (a) bu-tasarım-notu; (b) `settlement_bind`-alanının-additive-tanımı;
(c) `tools/settlement_bind_verify.py`-beş-kontrollü-üç-verdict; (d) AT-063-testi-beş-
negatif-kontrolle (swap-hash, swap-party, ref-mismatch, sig-invalid, chain-broken).

**SONRA (pilot-günü):** (e) gerçek-x402-claim-fixture'ı-ile-canlı-dikiş;
(f) tokenizen-tarafın-şema-hizalaması (holistis-x402#3379'da-önerdi); (g) `scheme`-
listesine-`tamga/native`-ve-`erc8004/v1`-eklenmesi (R9-2-additive-terfisiyle).

## 4b. Çoklu-ödeme-kanalı (B-yönü, 2026-09-21)

`SUPPORTED_SCHEMES`-additive-terfisi: **x402/v1** (EIP-191-secp256k1),
**tamga/native** (ed25519-operatör, simnet), **erc8004/v1** (keccak-merkle).

**Çapraz-kanal-saldırısı-yeni-yüzey:** saldırgan-x402-claim'ini-tamga/native-
scheme'ine-bağlarsa-ed25519-doğrulaması-farklı-pubkey-üretir → party_mismatch-RED.
Bu-saldırı-tek-kanal-dünyasında-mümkün-değildi; dispatch-getirdi, AT-064-kilitledi.

**Doğrulama-yükü-büyür** (§5-tekerrür): her-kanal-kendi-imza-sözleşmesi-demek.
Eklenen-kanallar-mevcut-x402-yolunu-bozmaz (AT-064-kontrol-5-geriye-dönük-uyum).

## 4c. AT-077-stub-gizli-boşluk-kapanışı (2026-09-21)

AT-077 (99-Yieldix-gerçek-Ed25519-dikişi) `_claim_signer`'ın-`tamga/native`-
branch'ında-**iki-gerçek-boşluk**-buldu — ikisi-de-daha-önce-görünmedi-çünkü
AT-063/064/065/070/071/072'nin-tümü-`_claim_signer`'ı-test-double-ile-değiştiriyordu
(AT-075'in-`ecrecover_to_pub`-boşluğuyla-**AYNI-SINIF**: gerçek-yol-hiç-koşmadığı-
için-hata-hiç-patlamadı):

1. **R-noktası=anahtar-sanısı:** `VerifyKey(sig_hex[:64])` — bir-Ed25519-imzasının
   ilk-32-byte'ı-genel-anahtar-değil, imzanın-R-noktasıdır. Sonuç: hiçbir-gerçek-
   imza-doğrulanamıyordu (yanlış-anahtar-her-zaman-Red-edge'de-değildi, None).
2. **Mesaj=gövde-metni-sanısı:** imzayı-`digest_hex`'in-DEĞİL-claim'in-JSON-metni-
   üzerinden-doğruluyordu. Ama-producer (Yieldix) `separators=(",",":")`-ile-
   imzalıyor, gate `(", ",": ")`-ile-serialize-ediyor — **aynı-nesne, farklı-bayt**.
   Ed25519-ham-mesaj-istediği-için-bu-asla-doğrulanamazdı.

**Düzeltme:** §3b'nin-tablosundaki-giriş-şekli-sabitlendi (her-kanal-için-imzalanan-
şey + kimlik-çözümü). Artık-gerçek-Ed25519-doğrulaması-stock-yoldan-koşar ve
AT-077-test-double'sız-6/6-GREEN-verir.

**Süreç-dersi (AT-075-ile-aynı):** her-scheme-başına-en-az-bir-test-**gerçek-
kütüphane-ile-üretim-yapmadan-koşmalı**; test-double'lar-gerçek-imza-yolunu-asla-
gizlememeli. Bu-kural-§3b'ye-de-işlendi.

## 4d. İki-uygulama-kanalı-aynı-scheme-altında-farklı-ön-görüntü (AT-090-dersi)

Sester'ın-X-PAYMENT-dozu-EIP-191-**önekli**-kişisel-imzadır
(`eth_account.encode_defunct("agent|nonce|amount|resource")` — `schemes.py:31`);
oysa-aynı-`x402/v1`-scheme'inin-RFC-010-claim-kanıtı-sha256-digest'ın-**ham-
baytları**-üzerine-atılır (z=raw-sha256, öneksiz — §3b). Yani-aynı-özete-iki-farklı
imza-üretilebilir-ve-her-kanal-yalnızca-kendi-ön-görüntüsünde-geçerlidir.

AT-077'in-canonical-JSON-separator-ayrımıyla-**aynı-sınıf**: kanal-sözleşmesi-
sabit-değilse-GREEN-asla-üretilemez — bu-nedenle-her-entegrasyon-önce-üretici-
tarafının-imza-ön-görüntüsünü-§3b-tablosuna-sabitlemelidir. Tek-anahtar-iki-kanalı-
sözleşme-bağımsız-yapar; RFC-010-yanlızca-kendi-ön-görüntüsünü-doğrular.

## 5. Riskler (dürüst)

- **Doğrulama-yükü-çoğalıyor:** her-scheme-için-ayrı-claim-doğrulama (§3-kontrol-2).
  Bugün-yalnız-x402/EIP-191; her-yeni-kanal-yeni-imza-doğrulama-kodu-demek. Bu-
  RFC-o-yükü-gizlemiyor-ama `scheme`-dispatch-ile-yerinde-tutuyor.
- **evidenceHash-alanı-tokenizen'ın-inkarı:** biz-evidenceHash'i-claim'den-okuruz;
  tokenizen-onu-silip-ços-mutasyonu-yaparsa-dikiş-kırılır. Çözüm: evidenceHash-
  claim'de-ZORUNLU (yoksa RED — "swap"-negatif-kontrolleri-gibi).
- **Üçüncü-seçenek-yasak-burada-da:** scheme-listesinde-olmayan-bir-kanal-RED-
  VERMEMELİ (İNDETERMİNE) — yoksa-sessizce-işlem-öldürürüz. Bu-§3'te-beyanlı.

## 6. Yabancı-zincir-kanıtı ( foreign_chain_proof) — additive ( 2026-09-23)

Bu-bölüm-varolan-davranışı-belgeler ( additive-only; kod-önceden-uyguluyordu,
RFC'de-yazılı-değildi — AT-141..161'in-§6-dikişleri-standardize-edildi).

### 6.1 Şema

`charge_rec.foreign_chain_proof` ( opsiyonel-alan):

```json
{"chain": "swarmax", "head_hex": "<64hex>", "entries": <int>,
 "evidence_link": "equals"|"derived"|"none", "verify_cmd": "<str>"}
```

- **chain**: whitelist — `swarmax | dumen | pqhaven | tamga | fleksa | sester |
  veridict | pacta | pactiva | yieldix | syntropion | tenderix | veridrome`.
  Listede-olmayan-zincir → RED ( bilinmeyen-İÇİN-İNDETERMİNE-DEĞİL: kanıt-
  adı-iddiası-yanlış-OLDUĞU-için-çürüktür). Her-zincir-kendi-adında-sunulmalı
  ( AT-107/134-dersi: önceden-hepsi-"tamga"-adı-altında-gidiyordu).
- **head_hex**: 64-lowercase-hex-ZORUNLU. Boş/farklı-uzunluk → RED
  ( boş-kök-sahte-zincir-işaretidir).
- **entries**: int ≥ 1-ZORUNLU ( sıfır-girişli-zincir-kanıt-değildir).
- **verify_cmd**: DIŞ-GİZLİLİK-alanıdır — **çalıştırılmaz**, yalnızca-denetim-
  izi-için-kaydedilir ( üçüncü-seçenek-yasak: biz-yabancı-zinciri-kendimiz
  yeniden-doğrulamayız, onun-kanıtını-kabul-ederiz — ama-çürükse-RED).
  KAYDETME-YERİNE-ÇALIŞTIRMA ( AT-067-itirafı).

### 6.2 İçerik-bağlantısı ( evidence_link, AT-079)

Eski-kod-yalnızca-BİÇİM-ölçerdi — herhangi-64-hex-geçerliydi ( sahte-head-
GREEN-geçiyordu; §6-borcunun-kalan-yüzü). Link-içerik-BAĞLANTISINI-zorlar:

- **`equals`**: `head_hex == receipt_hash` ( kanıt-teslimat-özütüyle-AYNI).
- **`derived`**: `head_hex == sha256( bytes.fromhex( receipt_hash))` —
  dikkat: türetme-halkası-GERÇEK-olmalıdır ( AT-156-dersi: keccak-Merkle-kökü
  sha256-türevine-EŞİT-OLAMAZ; iki-hash-ailesi → anlamsız-türetme-yerine
  equals-kullan veya İNDETERMİNE-bildir).
- **`none` / yok**: head-receiptHash'e-BAĞLI-değil ( farklı-zincirlerin-farklı
  kökleri-olabilir); ama-boş-head-yine-RED.

### 6.3 Gate-davranışı

- **kanıt-YOKSA → GREEN** ( geri-uyumlu; eski-dikişler-kırılmaz). §6-ZORUNLU-
  DEĞİLDİR — settlement-bind'ın-asıl-kanıtı-claim-imzasıdır (§3-kontrol-2);
  foreign-chain-ek-doğrulamadır.
- **kanıt-VAR + geçersiz → RED** ( rc8 `foreign_chain_broken`). Üçüncü-seçenek-
  yasak-ihlali-yok: eksiklik-İNDETERMİNE-değil, KANITLANMIŞ-çürüklük.

### 6.4 Mesh-uygulama-özetleri ( AT-141..161)

Her-zincir-kendi-kanıt-modelini-korur ( heterojen-federasyon; homojen-blockchain-
değil): Merkle ( veridrome-RFC-6962, fleksa, dumen), Ed25519 ( swarmax, yieldix,
tenderix), ECDSA-P256 ( veridict-Rekor-dış-zincir), Proof-of-Audit ( pactiva),
D5-ledger ( tamga, sester, pacta). Hepsi-§6 üzerinden-ortak-doğrulamaya-bağlanır.

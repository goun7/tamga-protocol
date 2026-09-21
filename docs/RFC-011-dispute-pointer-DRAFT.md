# RFC-011 (TASLAK) — Dispute-Pointer: Anlaşmazlık-Bacağı

> **Durum: DRAFT.** RFC-010 *mutabakatı*-kanıtlar (beş-kontrolun-hepsi-GREEN).
> Ama-holistis'in-D-017'sinin-tespit-ettiği-boşluk-kalıyor: **iki-geçerli-
> imzalı-çelişkili-iddia-arasından-kim-seçecek?** Pacta'nın-§5.3'ü-bu-boşluğu-
> *Schelling-hakemliği*+*%20-itiraz-teminatı* ile-dolduruyor. Bu-RFC-o-iki-
> tarafı-birbirine-bağlar — **kendi-adımıza-hakemlik-yapmadan**.

## 0. Özet

`settlement_bind`'e-additive-bir-`dispute_pointer`-alanı. Bir-iddia-için
sözleşme-çoğulluğu-çözülemezse (RFC-010-GREEN-olsa-bile-alıcı-`delivered:no`-
imzaladıysa), kanıt-**çelişki-işaretler**, RED-değil-İNDETERMİNE: *"bu-iki-
tarafta-da-aynı-kadar-geçerli, insan/hakem-kararı-gerekli."* İşte-o-anda
`dispute_pointer`-dış-sürece-işaret-eder — Pacta-escrow'una, holistis'in
`disputeContext`'ine veya herhangi-bir-tahkim-mekanizmasına.

**Üçüncü-seçenek-yasak-korunur:** biz-hakemlik-YAPMAYIZ. Sadece-çelişkiyi
tespit-eder-ve-dış-çözüme-işaret-ederiz.

## 1. Motivasyon — neden-şimdi

holistis-x402#3379 (D-017): *"record_delivery-yalnızca-alıcı-imzalı-iddia-
kabul-eder, verifyClaim-imzayı-yalnızca-buyerAddress'e-çözer, **satıcı-karşı-
iddia-mekanizması-hiç-yok**"* — *"a-dispute-only-ever-shows-one-side,
structurally"*; *"signature-proves-who-said-it, never-what-actually-happened;
attribution, not-truth."*

Pacta-§5.3-aynı-boşluğu-farklı-tarafdan-doldurur: %20-itiraz-teminatı-+
Schelling-konsensüsü-+-quadratic-slashing. **İkisi-de-tamamlar-birbirini**:
holistis-boşluğu-adlandırır, Pacta-çözüm-mekanizmasını-taşır.

**Tamga'nın-rolü:** hakem-değil, **çelişki-algılayıcı-+-yönlendirici**.

## 2. Kayıt-şekli (additive-alan, op-YOK)

```json
{"op": "charge", "seq": N, ...,
 "settlement_bind": {...},
 "dispute_pointer": {                          // additive, opsiyonel
   "status": "contradiction",                  // "none"|"contradiction"|"resolved"
   "counter_claim": {                          // alıcının-delivered:no-iddiası
     "buyer_signed": true,
     "delivered": false,
     "evidence_hash": {"alg": "sha256", "hex": "<64hex>"}},
   "arbitration": {                            // dış-çözüm-işaretçisi
     "protocol": "pacta/v1"|"holistis/disputeContext"|<bilinmeyen-string>,
     "case_ref": "<string>",                   // bir-kez-açıldığında-doluyor
     "terms_hash": "<64hex>"},                 // anlaşılan-şartların-özü
   "bond_pct": 0.20}}                          // Pacta-§5.3: %20-zorunlu-itiraz-teminatı
```

**Neden-additive:** RFC-010'ın-aynı-ilkesi — op-yeni-yazım-sınıfı-açmaz,
D5-zincir-hash'ine-girer. `status:"none"`-durumunda-dikiş-GREEN-kalır
(geri-uyumlu).

## 3. Doğrulama-sözleşmesi

`tools/dispute_pointer_verify.py` — RFC-010'ın-**6.-kontrolundan-sonra**-çalışır:

| # | Kontrol | Ne-kanıtlar | Başarısız |
|---|---|---|---|
| 1 | RFC-010-GREEN-önkoşul | dikiş-zaten-geçerli | RED-döner |
| 2 | **çelişki-algılama** | iki-geçerli-imzalı-çelişkili-iddia | İNDETERMİNE |
| 3 | status-`contradiction`-ise-`arbitration`-ZORUNLU | yönlendirme-yok-olamaz | RED rc9 |
| 4 | `bond_pct` ≥ 0.20 (Pacta-§5.3) | griefing-önlenir | RED rc10 |
| 5 | `protocol`-listesi-additive | bilinmeyen-RED-değil | İNDETERMİNE |

**Fail-closed-kuralı:** 3-ve-4-RED. Ama-2-ve-5-İNDETERMİNE — **çelişki-
kısmi-GREEN-ile-çözülemez**, insan/hakem-gerekir. Bu-nedenle-6/6-GREEN-
"teslimat-iyi-oldu"-demek-DEĞİLDİR; yalnızca-"kimse-itiraz-etmedi"-demektir.

## 4. NE-ŞİMDİ / NE-SONRA

**ŞİMDİ:** (a) `dispute_pointer`-alanı-tanımı; (b) çelişki-algılayıcı
(iki-imzalı-iddia-karşılaştırma); (c) AT-073-negatif-kontrolle-çelişki,
boş-arbitration, düşük-bond; (d) Pacta-§5.2'deki-`TamgaVerifier.verify()`
atfını-kanıtla (önceden-var-bağ).

**SONRA:** (a) Pacta-hakemlik-simülasyonu-ile-canlı-test; (b) holistis-
`disputeContext`-şema-hizalaması; (c) `protocol`-listesine-`pacta/v1`-ekle.

## 5. Riskler (dürüst)

- **"Yeşil-giydirme"-tehlikesi-BUYÜK:** `6/6-GREEN`-iddiası-tam-burada-
  yanlış-okunabilir. RFC-010-GREEN = *"mutabakat-kanıtı"*, *"teslimat-iyi"*
  DEĞİL. dispute_pointer-bunu-açıkça-yazar-ama-insanlar-badge'i-okur.
- **Hakem-merkeziyetsizliği-şart:** Schelling-konsensüsü-ve-slashing-Pacta'ın-
  işi; biz-sadece-işaret-ederiz. Eğer-Tamga-hakem-seçerse-tek-nokta-oluruz.
- **bond_pct-%20-keyfi:** Pacta-§5.3'ün-sayısı; oyun-teorik-optimizasyonu-bizde-
  değil. Dışarıdan-gelen-değer-olarak-işaretlenir (§3-kontrol-4).

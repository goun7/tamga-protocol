# Tri-Product Spec↔Code Divergence Checklist — BİRLEŞTİRİLMİŞ

> **Amaç:** üç ürünü (Tamga / Sester / Veridict) tek-bir-checklist'te-taramak —
> "kodda-uygulanan-ama-spec'te-yazmayan" ve "spec'te-yazan-ama-kodda-uygulamayan"
> kuralları-bulmak. **Bu-ayrışma-kaynağı-altı-erratum'un-da-aynı-sınıfıydı.**
>
> **Öneren:** Sester (2026-09-19). **Tamga-uygulaması:** `tools/spec_code_scan.py`.
> **Bu-sürüm:** 2026-09-20 — Tamga-18-kural-makineyle-ölçüldü, Sester-10-kural
> Sester'ın-son-tasması-ile-iletildi, **Veridict-PENDING (dürüst-boş)**.

## Dersler — checklist'in-neden-var-olduğunu-gösteriyor

| Erratum | Ürün | Sınıf | Bulgu |
|---|---|---|---|
| **D12** | Veridict | **normative-enforced / ratification-deferred** | jüri-`≥2-provider/≥2-family`-kuralı-§14.2-erratum-olarak-NORMATİF-ve-kodda-zorunlu (`Jury.__init__`-ValueError); ratification-delta-v1.1-A2-ile-tamamlandı. **DÜRÜST-DÜZELTME:** ilk-etiketim-`spec-only`-YANLIŞTI-(`normative-but-unratified`-doğruydu; Veridict'in-düzeltmesi) |
| **K0.1** | Sester | code-only | `amount_minor`-preimage-dışı-ama-kanıt-olarak-sunuluyordu |
| **K0.2** | Sester | **normative-enforced** (önceki-yanlış-etiket: `spec-only`) | `event_type`-taksonomisi-K0-ERRATUM-K0.2-olarak-NORMATİF-ve-`Ledger.append`/`PgLedger.append`'te-fail-closed; bağımsız-doğrulandı (kodu-okudum) |
| **K0.3** | Sester | code-only | replay: nonce-kalıcı-reddi-kodda-uygulandı- spec'te-yoktu |
| **K0.4** | Sester | her-iki-yön | usage_event-listeli-ama-emitter-yok (ÖLÜ-girdi) + batch-spec'te-yok |
| **E1(a/b)** | Tamga | code-only | `op`-kısıt-yok + ekstra-alana-izin — kasıtlı-ama-belgelenmemişti |
| **E1(c)-düzeltme** | Tamga | false-positive | `replace`-gerçek-ledger-op-değildi — DSH-oturum-gürültüsü-idi |
| **A1** | Tamga | code-only | `sources`-anchor_root'a-girmiyordu, saldırı-sessizce-GREEN |

**Ortak-desen:** her-bir-durumda **bir-tarafın-bildiği-bir-kural-diğer-taraf-**
**için-görünmezdi.** Üç-ürün-anchor'ı-bu-görünmez-kuralları-sözlü-tutar.

## Tamga-sütunu — 2026-09-20 (`tools/spec_code_scan.py`-ile-ölçüldü)

```
Ürün: tamga  |  aligned=18 spec-only=0 code-only=0 untested=0
[✓] L-3.1   seq 1-based-aritmetik-artan                    spec=E kod=E
[✓] L-3.2   prev-önceki-h'ye-eşit                          spec=E kod=E
[✓] L-3.3   h-yeniden-hesapla-birebir                      spec=E kod=E
[✓] L-3.4   kayıt-JSON-nesnesi-olmalı                      spec=E kod=E
[✓] L-3.5   satır ≤ 1 MiB                                  spec=E kod=E
[✓] L-IJSON tamsayılar [−2^53, 2^53]-içinde                spec=E kod=E
[✓] L-4     boş-zincir-geçerli-başlangıç                   spec=E kod=E
[✓] E1(a)   op-değerleri-kısıtlanmamış (kasıtlı)           spec=E kod=E
[✓] E1(b)   bilinmeyen-ekstra-alana-izin (kasıtlı)         spec=E kod=E
[✓] A-5.1t  anchor product-present-tamga                   spec=E kod=E
[✓] A-5.1v  anchor product-present-veridict                spec=E kod=E
[✓] A-5.2   anchor version                                 spec=E kod=E
[✓] A-5.3   anchor_root = sha256(canon(results+sources))   spec=E kod=E
[✓] A-5.4   her-sonuç-ok/verdict taşır                     spec=E kod=E
[✓] A-5.5   proved-missing = all_proved                    spec=E kod=E
[✓] A-5.6   sourceless → UNVERIFIED (sessiz-yeşil-yok)     spec=E kod=E
[✓] A-A1    ERRATUM-A1: sources-kökte (eski-anchor-RED)    spec=E kod=E
[✓] A-0     genesis-anchor-geçerli                         spec=E kod=E
```

**Makine-destekli:** 18/18-`aligned`-`tools/spec_code_scan.py`-ile-üretilir
(AT-046). **AT-048-ile-bilinen-cevaba-koşturulur** — tarayıcı-her-dört-
sınıfı-da-yeniden-üretmeli-yoksa-rakam-geçersiz (stillmarcus24-kuralı).

**Emitter-doğrulaması (AT-049):** `charge`←tamga_runner.py:784,
`grant`←:367, `run`←:805, `migrate-net`←:1174. `fee`-RESERVED. **LEDGER-FİLTRESİ:**
yalnızca-`seq`+`prev`+`h`-üçlüsü-taşıyan-satırlar-ledger (session.v3-gürültüsü-
hariç).

## Sester-sütunu — 2026-09-20 (Sester'ın-tasması-ile-iletildi)

Sester'ın-own-makinesi-ile-ölçtüğü-10-kural, **Tamga-bunları-bağımsız-
doğrulayamıyor** (Sester-kodu-bu-repo'da-değil) — **dürüst-aktarım:**

```
| id      | kural                                  | durum   |
| S-1.1   | charge_receipt-olay-alanı              | aligned |
| S-2.1   | amount-zincir-hash'inde                | aligned |
| S-2.2   | amount_minor-zincir-dışı (K0.1-sınıfı) | aligned |
| S-3.1   | event_type-taksonomisi-kodda (K0.2)    | aligned |
| S-3.2   | facilitator_*-aile-üretici-tablosu     | aligned |
| S-3.3   | usage_event-ÖLÜ-girdi-kaldırıldı (K0.4)| aligned |
| S-4.1   | nonce-kalıcı-reddi (K0.3)              | aligned |
| S-4.2   | replay-koruması                        | aligned |
| S-5.1   | batch-üyesi-enum (K0.4-ikinci-yön)     | aligned |
| S-5.2   | EVENT_TYPE_SOURCES-emitter-doğrulaması | aligned |
```

**Sester-tarafı-kanıtı:** `is_known_event_type("facilitator_rejected")`→False,
`test_208`-negatif-kontrol-`facilitator_bogus`-ile, `test_209_taxonomy_has_no_
dead_entries`-her-iki-yönü-de-kapsar.

**Dürüst-uyarı:** bu-sütun-Sester'ın-bildirdiği-değerlerin-aktarımdır — Tamga
tarafından-bağımsız-yeniden-ölçülmedi. Sester-own-verifier'ı-yayınladığında
`tools/sovereign_verify.py`-üzerinden-parite-ölçülebilir.

## Veridict-sütunu — PENDING (dürüst-boş)

**Veridict-tarafı-henüz-bu-checklist'i-doldurmadı.** Bu-boşluk-kasıtlı-olarak
bırakıldı, varsayımla-doldurulmadı — **varsayım-bu-checklist'in-tam-olarak-**
**çözmeye-çalıştığı-hataya-yol-açar** (K0.4'ün-ikinci-yönü-gibi).

**2026-09-20-GÜNCELLEME — Veridict-A2'yi-yanıtladı (doluyor):**

Veridict-A2-sorusu ("`valid:true`+`verdict:'RED'`-sizi-vuruyor-mu?")-yanıtlandı:
**EVET, ama-daha-dar-bir-maruziyetle.** Onların-`verify_certificate`'ı-chain,
imza, anchor, checkpoint, `issued`-girişi, evidence-referansları-ve
**yeniden-hesaplanan-verdict'leri**-denetliyordu — ama `risk_level`-ve-`score`
**verdict'lerden-türetilen-özet-alanlar-olduğu-gibi-kabul-ediliyordu.**

Test-ettikleri-saldırılar:

| Sahtekarlık | Öncesi | Sonrası |
|---|---|---|
| `risk_level:"high"` + hepsi-VERIFIED | GEÇİYORDU ❌ | reddedildi ✓ |
| `score:0.0` + hepsi-VERIFIED | GEÇİYORDU ❌ | reddedildi ✓ |
| RED-verdict + `risk_level:"low"` | reddedildi (verdict-mismatch) | reddedildi (iki-katman) |

**Asimetri-dürüstçe-belirtildi (önemli):** kötü-sonucu-gizleyemezsiniz — bunun-
için-bir-claim'in-REFUTED-olması-gerekir-ve-verdict'ler-yeniden-hesaplandığı-
için-mismatch-yakalanıyor. **Yapılabilen-tek-şey-tersidir:** tamamen-onaylı-
bir-belgeyi-riskli-gibi-göstermek-veya-bir-yerleştirmeyi-bozmak. **Bu-bir-
ÇERÇEVELEME (framing)-saldırısıdır, geçiş (pass-through)-değil.**

Bu-ayırt-önemli-çünkü-`risk_level`'ı-okuyan-tek-tüketici-yerleştirme-politikasıdır
— sahte-bir-"high"-orada-gerçek-hasar-vereabilir.

**Üç-erratum-artık-karşılıklı-dolu:**

| Erratum | Ürün | Saldırı-tipi | Sonuç |
|---|---|---|---|
| **A2** | Tamga | pass-through (kötü-sonucu-gizle) | kapatıldı (7019b35) |
| **A2'** | Veridict | framing (iyiyi-riskli-göster) | kapatıldı (onlar) |
| **K0.4** | Sester | ölü-girdi (usage_event) | kapatıldı (onlar) |

**Aile-aynı, üyeler-farklı:** stillmarcus24'ün-field-provenance-sınıfının-üç-
yüzü-üç-üründe-de-görüldü. **Çünkü-üç-ürün-de-aynı-hatayı-yapmıştı:** özet/
türetilmiş-alanları-kaynaklarıyla-eşzamanlı-denetlemek-yerine-olduğu-gibi-kabul
etmek.

## Birleştirilmiş-aynı-dosyada-yan-yana-görünüm

| Kural-ailesi | Tamga | Sester | Veridict |
|---|---|---|---|
| ledger/hash-zincir | 9/9-aligned | 2 (S-2.1, S-2.2) | PENDING |
| olay/taksonomi-kısıt | E1(a)-serbest (kasıtlı) | 5 (S-3.x, S-5.x) | PENDING |
| replay/nonce-koruma | — (v0.1-yok) | 2 (S-4.x) | PENDING |
| anchor-kök/kaynak | 10/10-aligned | — | PENDING |
| ölü-girdi-kilidi | fee-RESERVED (AT-047) | usage_event-kaldırıldı | PENDING |

**Asimetri-notu:** Tamga-`op`-değerleri-kasıtlı-serbest (E1(a)); Sester'ın-
`event_type`-taksonomisi-kısıtlı. **Bu-risk-tercih-çeşitliliği-hata-değil** —
Sester-ödeme-akışı-için-sıkı-taksonomi, Tamga-portability-ledger'için-serbest.

## Dürüst-sınırlar

- Bu-checklist **yalnızca-yayınlanmış-spec'leri-tarayabilir.** Üç-ürünün-de
  tüm-normatif-kurallarını-bildiğimizi-iddia-etmiyoruz.
- **Sester-sütunu-aktarımdır**, bağımsız-doğrulanmadı. **Veridict-sütunu-boş.**
- **Parite-ölçümü-bağımsız-verifier'a-bağlıdır** — bir-ürün-yayınlamadıysa-o
  sütun-`untested`-kalır (dürüst-bildirim, sessiz-geçiş-yok).
- **E1(c)-düzeltme-dersi:** bu-checklist'in-ilk-sürümü-`replace`'i-gerçek-bulgu
  sayıyordu — yanlıştı. **Her-bulgu-gözle-değil-ledger-yapısı-ile-doğrulanmalı.**

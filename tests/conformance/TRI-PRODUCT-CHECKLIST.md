# Tri-Product Spec↔Code Divergence Checklist

> **Amaç:** üç ürünü (Tamga / Sester / Veridict) tek-bir-checklist'te-taramak —
> "kodda-uygulanan-ama-spec'te-yazmayan" ve "spec'te-yazan-ama-kodda-uygulamayan"
> kuralları-bulmak. **Bu-ayrışma-kaynağı-üç-erratum'un-da-aynı-sınıfıydı.**
>
> **Öneren:** Sester (2026-09-19, üç-taraf-yüzey-kilitlenmesi-sonrası).
> **Tamga-tarafı-uygulaması:** `tools/spec_code_scan.py` + `tests/at046_*.sh`.

## Dersler-bu-checklist'in-neden-var-olduğunu-gösteriyor

| Erratum | Ürün | Sınıf | Bulgu |
|---|---|---|---|
| **D12** | Veridict | spec-only | jüri "≥2-provider/≥2-family"-kuralı-kodda-zorunlu-ama-normative-metinde-yoktu |
| **K0.1** | Sester | code-only | `amount_minor`-preimage-dışı-ama-kanıt-olarak-sunuluyordu |
| **K0.2** | Sester | spec-only | `event_type`-taksonomisi-kodda-uyguluyordu-metinde-yazmıyordu |
| **E1(a/b)** | Tamga | code-only | `op`-kısıt-yok + ekstra-alana-izin — kasıtlı-ama-belgelenmemişti |
| **A1** | Tamga | code-only | `sources`-anchor_root'a-girmiyordu, saldırı-sessizce-GREEN |

**Orak-desen:** her-bir-durumda **bir-tarafın-bildiği-bir-kural-diğer-taraf- |
için-görünmezdi.** Üç-ürün-anchor'ı-bu-görünmez-kuralları-sözlü-tutar-ki-
bağımsız-verifier-gerçekleme-ile-çakışmasın.

## Checklist-metodu (her-ürün-için-aynı)

Her-normatif-kural-için **iki-yönü-de-üretim-üzerinde-ölç** (sadece-iddia-etme):

1. **YÖN-A — kod-coverage:** kuralı-çzen-bir-vektör-üret → **RED-gelmeli**.
   Gelmeyebilir: kısıtlama-yok (kasıtlı-ise-erratum-olarak-belgele).
2. **YÖN-B — spec-coverage:** spec-dosyasında-needle-ara → **belgeli-olmalı**.
3. **Parite:** bağımsız-verifier-aynı-karara-varıyor-mu? (ayrışma-yok)

**Sonuç-sınıfları:** `aligned` (her-iki-yön) / `spec-only` (D12,K0.2-sınıfı) /
`code-only` (K0.1,E1,A1-sınıfı) / `untested`.

## Tamga-sütunu — 2026-09-19 (`tools/spec_code_scan.py`-ile-ölçüldü)

```
Ürün: tamga  |  aligned=9 spec-only=0 code-only=0 untested=0
[✓] L-3.1   seq 1-based-aritmetik-artan              spec=E kod=E
[✓] L-3.2   prev-önceki-h'ye-eşit                    spec=E kod=E
[✓] L-3.3   h-yeniden-hesapla-birebir                spec=E kod=E
[✓] L-3.4   kayıt-JSON-nesnesi-olmalı                spec=E kod=E
[✓] L-3.5   satır ≤ 1 MiB                            spec=E kod=E
[✓] L-IJSON tamsayılar [−2^53, 2^53]-içinde          spec=E kod=E
[✓] L-4     boş-zincir-geçerli-başlangıç             spec=E kod=E
[✓] E1(a)   op-değerleri-kısıtlanmamış (kasıtlı)     spec=E kod=E
[✓] E1(b)   bilinmeyen-ekstra-alana-izin (kasıtlı)   spec=E kod=E
```

**E=evet | ✓=uyumlu | S=sadece-spec'te | C=sadece-kodda | ?=ölçülemedi**

**Not:** E1(a)/E1(b)-için-"kod=E"-kasıtlı-olarak-**kısıtın-yokluğunu**-belirler —
kural-"izin-ver"-şeklinde-uygulandı-ve-erratum-ile-belgelendi.

**Anchor-tarafı (ANCHOR-SPEC.md):** Erratum-A1-ile-`sources`-köke-eklendi;
`a00`–`a08`-vektörleri-ile-kilitli (`tests/conformance/run.sh`).

## Sester/Veridict-sütunları — doldurulması-için-şablon

Her-ürün-kendi-`spec_code_scan.py`-benzeri-bir-tarayıcı-yazabilir-veya-bu-
tabloyu-el-doldurabilir. **Önerilen-ortak-alanlar:**

```
| id | kural | spec_documented (E/-) | code_enforced (E/-) | divergence | kanıt |
```

**Önerim:** üç-ürün-de-aynı-ids-şemasını-kullansın (L-x.x-ledger,
A-x-anchor, S-x-sester, V-x-veridict) — böylece-tek-tabloda-yan-yana-
karşılaştırma-yapılabilir-ve **bir-üründe-bulunan-sınıf-diğerlerinde-de-
aranabilir.**

## Dürüst-sınırlar

- Bu-checklist **yalnızca-yayınlanmış-spec'leri-tarayabilir.** Üç-ürünün-de
  tüm-normatif-kurallarını-bildiğimizi-iddia-etmiyoruz — tarama-yaptığımız-
  spec-derinliğine-sınırlıdır.
- **Parite-ölçümü-bağımsız-verifier'a-bağlıdır** — bir-ürün-bağımsız-verifier
  yayınlamadıysa-o-ürünün-parite-sütunu-`untested`-kalır (dürüst-bildirim,
  sessiz-geçiş-yok).

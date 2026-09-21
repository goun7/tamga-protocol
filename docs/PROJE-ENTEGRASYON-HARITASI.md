# Tamga — Proje-Entegrasyon-Haritası

> **Amaç:** Tamga-blockchain'e-fayda-sağlayan-veya-onlardan-fayda-sağlayan
> tüm-projeleri **tek-başlıkta** toplar. Her-satır **kod-kanıtıyla-ölçülmüş**
> (spec-iddiaları-değil): entegrasyon-yeri-gerçek-bir-dosya-ve-satır-işaret eder.
>
> **Güncelleme-kuralı:** bu-haritaya-satır-eklemek-için-iki-kanıt-gerekir:
> (1) karşı-tarafın-gerçek-kodunun-yol-ve-satırı, (2) Tamga-tarafında-bunu-
> doğrulayan-bir-AT-test-numarası. Spec-only-satırlar-ayrı-bölümde.

## 1. Entegre-EDİLENLER (kod-kanıtı + AT-kilidi)

| Proje | Yol | Entegrasyon-noktası | AT-kanıtı | Durum |
|---|---|---|---|---|
| **Sester** | `01_unicorn/63-Sester` | `ledger.py:183` `NON_GATES` (boş-tüm-yazım-GATES'te) ↔ bizim `EMITTED_OPS`; `K0_SHARED_ENVELOPE_SPEC.md` §7-kural-9 ↔ LEDGER-SPEC §6/§7 | AT-055, AT-056 | **üretici-zorunlu/alıcı-opt-in paritesi-makine-kilitli** |
| **Veridict** | `05_acik_kaynak/Veridict` | `jury.py:265` "jury-requires->=2-providers->=2-families (§5.2)" ↔ RFC-009 R9-5 (kanıt-doğrulamaz) | V-1.1-etiket | **üçüncü-seçenek-yasak-her-iki-tarafta-normatif** |
| **25-pqhaven-x402** | `01_unicorn/25-pqhaven-x402` | `x402_servis.py:82` `merkle_root: str | None` + `:172` "PQ-tarama → CBOM + Merkle-kökü" → RFC-010 `erc8004/v1`-scheme'ine-bağlanır | **AT-065-5/5** | **ilk-gerçek-üçüncü-proje-kanıtla-bağlandı** |

**AT-065'in-önemi:** Sester/Veridict-insan-relay'ı-ile-konuştu; PQHaven **ilk-kez**
bir-başka-projenin-gerçek-çıktı-formatı (rapor+CBOM→Merkle-kökü) Tamga'nın-
fail-closed-gate'inde-doğrulandı. Gerçek-kök-GREEN, sahte-kök-RED.

## 2. Kod-CANLI — entegre-edilebilir (arayüz-gerçek, AT-bekliyor)

| Proje | Kod | Arayüz-gerçek | Önerilen-scheme | Öncelik |
|---|---|---|---|---|
| **24-ajan-borsasi** | 1271-py | `borsa_core.py:70` `receipt_hash: str \| None` ("ChargeReceipt hash, Sester'dan") + `:176` `complete_work(match_id, receipt_hash)` — **Sester'a-bağımlı-değil, kanıtı-okur** | `x402/v1` + `tamga/native` | **yüksek** — dikişin-üçüncü-ürünü |
| **00-gateway** | 904-py | `gateway.py:51` `_match_route()` 6-x402-servis-tek-port | `x402/v1` | orta — pilot-trafiği |
| **58-Mahrem** | 80-rs | Rust-ZK-OS — çekirdek-gizlilik-ekseni | (yeni-scheme) | düşük — farklı-alan |

**Neden-Ajan-Borsası-yüksek:** `receipt_hash`-alanı **RFC-010'ın-beş-kontrolünün-
5'incisi-olan `evidenceHash == receiptHash` denkleşmesinin-doğal-kaynağı**. Kod-yorumu
bunu-söylüyor: *"Sester'ın ChargeIntent/ChargeReceipt'i, Ajan Borsası'nın emir-kanıtı
olur"* (`borsa_core.py:18-19`). Ve-modül-Sester'a-bağımlı-değil — **sadece-okur**,
yani-loose-coupling.

## 3. Spec-ONLY — tasarım-değeri-var, kod-yok (henüz)

Bu-projeler **"100/100 Master"**-dokümanları-taşır-ama-çalışan-kod-satırları-14-63
arasında. Entegrasyon-için **arayüz-sözleşmesi-olarak**-değerliler:

| Proje | Doküman | Tamga'ya-katkı |
|---|---|---|
| **03-Pacta** | `PROJE_KAGIDI.md` | escrow+anlaşmazlık-rayi — RFC-010 **mutabakat**ı-kanıtlar, Pacta **anlaşmazlık**ı-taşır: tamamlayıcı-yüz |
| **68-Kredent/ROBOSEAL** | `ROBOSEAL.md` | ajan-kimlik+itibar — TRM Labs'in-"counterparty-reputation"-önerisinin-alternatifi |
| **73-Veridrome** | `VERIDROME.md` | sertifikasyon-arenası — anti-gaming-benchmark |
| **80-PQHaven** | `PQHAVEN.md` | CBOM-kripto-envanteri (25-x402-servisinin-teorisi) |
| **99-Yieldix** | `YIELDIX.md` | gelir-motoru — kanıtı-tüketen-ilk-istemci |
| **76-Fleksa** | `FLEKSA.md` | (içerik-henüz-okunmadı) |
| **18-Syntropion** | — | (içerik-henüz-okunmadı) |
| **22-37-Pactiva** | `Fikir.md` | dağıtık-istihdam+emanet |
| **64-Tenderix** | `README.md` | imzalı-bağlayıcı-teklif (CSVO) — üçüncü-seçenek-yasak-aynı-sınıf |
| **69-Swarmax / 77-Dumen** | — | (içerik-henüz-okunmadı) |

## 4. Dış-ekosistem (açık-PR'lar-ve-issue'lar)

| Hedef | Bağ | Durum |
|---|---|---|
| **x402#3379** | safal207-nin-`evidenceHash == receiptHash`-önerisi | **RFC-010-olarak-kodda** (AT-063) |
| **x402#2887** | zaman-damgaları-okunmaz (bizim-RFC-009-R9-4'le-aynı-kural) | kapanış-yorumu-yazıldı |
| **holistis/tokenizen PR#7** | D-017 attribution-not-truth | okundu, cevap-bekleniyor |
| **in-toto#592** | — | **MERGED** |

## 5. Topolojik-gerçek (dürüst)

```
                    ┌─────────────────────────────────┐
                    │   SEN (tek-ajan-workspace)       │
                    │   subagent'larla-iletişim-yükü   │
                    └──────────────┬──────────────────┘
                                   │ (send_message: AYNI-oturum-da-çalışır)
        ┌──────────────────────────┼──────────────────────────┐
        │                          │                          │
   Tamga-oturum             Sester-oturum              Veridict-oturum
   (bu-lead)               (ayrı)                     (ayrı)
        │                          │                          │
        └────── DOSYA + İNSAN-RELAY + İSSUE'LAR ──────────────┘
                    (gerçek-kanal-bu-üçü)
```

**Kanıt:** `list_agents` → lead-only. Sester'ın-`tamga-resume`-hedefi-bu-oturumda-
yok (`.dsh-live/`-altında-iz-sıfır; string-yalnız-pano-geçmişinde). **Üç-oturum
arasında-ağ-yok** — iletişim-insan-relay + dosya + x402-issue'ları-üzerinden.

## 6. Sonraki-adımlar (sıralı)

1. **Ajan-Borsası-dikişi** (yüksek-öncelik): `receipt_hash`-RFC-010-5'inci-
   kontrolüne-bağla → AT-066-negatif-kontrolle
2. **00-gateway-pilot-trafiği**: 6-x402-servisinin-gerçek-receipt'larıyla-Sepolia
   anchor-üret (ücretsiz)
3. **Pacta-anlaşmazlık-yüzü**: RFC-010'ın-eksik-bacağı-dispute-taşıma

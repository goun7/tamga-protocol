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

| **69-Swarmax** | `01_unicorn/69-Swarmax` | `src/swarmax/evidence.py:17` `payload_digest` sha256-prev_hash-zinciri (GENESIS-kök) + `ed25519.py:128` `verify` saf-Python-RFC-8032 → `tamga/native`-scheme'inin-imza-doğrulaması | **AT-067-6/6** | **B-sınıfı-bağlandı** |
| **77-Dümen** | `01_unicorn/77-Dumen` | `dumen/reports/evidence_chain.py:76` `_hash_entry` — `rfc8785`-şeması-seçeneği **kodsunda-açıkça-"Tamga AT-036"-atfı-yazar** (önceden-var-bağ); `GENESIS_PREV`=64-sıfır | **AT-068-6/6** | **AT-036-paritesi-önceden-var, ödeme-dikişi-şimdi** |

| **76-Fleksa** | `01_unicorn/76-Fleksa` | `src/fleksa/protocols/attestation.py` W3C-VC-v2.0 (Ed25519-2020) + `audit/ledger.py:27` `compute_merkle_root` → **iki-scheme'de-de** (erc8004/v1 + tamga/native) | **AT-070-6/6** | **B-sınıfı-bağlandı** |
| **64-Tenderix** | `01_unicorn/64-Tenderix` | `src/tenderix/signing.py` Ed25519 PyCA>PyNaCl>pure-RFC-8032-üç-fallback (zero-dependency) → imzalı-CSVO-teklif-ödeme-kanıtı | **AT-071-6/6** | **B-sınıfı-bağlandı** |
| **73-Veridrome** | `01_unicorn/73-Veridrome` | `src/veridrome/core/crypto.py` RFC-6962-CT-log (`generate_proof`-üyelik-kanıtı) + `get_root_hex`='0x'+64hex = **R9-3-kanonik-aynı-biçim** | **AT-072-6/6** | **B-sınıfı-bağlandı (en-güçlü — üyelik-kanıtı)** |

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

## 2b. C-sınıfı-ilk-sonuçlar (2026-09-21)

| Proje | Sonuç | Tür |
|---|---|---|
| **03-Pacta** | §5.2-açıkça-`TamgaVerifier.verify(receiptHash, signature)`-+`TamgaReceipt`-yazar — **önceden-var-bağ**; §5.3-%20-itiraz-teminatı-RFC-011'e-taşındı | **RFC-011-AT-073-ile-bağlandı** |
| **68-Kredent/ROBOSEAL** | EigenTrust-itibar-skoru, **K0-sıralama-yasağıyla-çelişiyor** — D-014-duvarı-ROBOSEAL'de-de-var (soğuk-başlangıç-cezası) | **NEGATİF-sonuç** — İNDETERMİNE (çözüm-değil, reddedilmiş-de-değil) |

## 3. Spec-ONLY — tasarım-değeri-var, kod-yok (henüz)

Bu-projeler **"100/100 Master"**-dokümanları-taşır-ama-çalışan-kod-satırları-14-63
arasında. Entegrasyon-için **arayüz-sözleşmesi-olarak**-değerliler:

| Proje | Doküman | Tamga'ya-katkı |
|---|---|---|
| **03-Pacta** | `PROJE_KAGIDI.md` | escrow+anlaşmazlık-rayi — RFC-010 **mutabakat**ı-kanıtlar, Pacta **anlaşmazlık**ı-taşır: tamamlayıcı-yüz |
| **68-Kredent/ROBOSEAL** | `ROBOSEAL.md` | ajan-kimlik+itibar — TRM Labs'in-"counterparty-reputation"-önerisinin-alternatifi |
| **73-Veridrome** | `VERIDROME.md` | sertifikasyon-arenası — anti-gaming-benchmark |
| **76-Fleksa** | `FLEKSA.md` | (içerik-henüz-okunmadı) |
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

## 5. Topolojik-gerçek (dürüst) — 00_TAMGA-MESH-kuruldu 2026-09-21

**ESKİ-DURUM (§5-v1):** üç-ayrı-oturum, aralarında-ağ-YOK, insan-relay.
**YENİ-DURUM:** `~/projects/00_TAMGA-MESH/` — **14 symlink, hepsi-canlı,
sıfır-kırık** (her-repo-kendi-git'ini-korur; taşıma-yok):

```
                     ┌─────────────────────────────────┐
                     │   00_TAMGA-MESH/ (TEK-BAŞLIK)    │
                     │   14-symlink — ortak-görünüm     │
                     └──────────────┬──────────────────┘
                                    │ tek-oturum-cwd = MESH-kökü
         ┌──────────────────────────┼──────────────────────────┐
         │                          │                          │
    Tamga-çekirdek             Diğer-13-proje            Subagent'lar
    (95/95-AT-kilidi)          (hepsi-aynı-ağaçta)      (hepsini-görür)
         │                          │                          │
         └──── DOSYA + İNSAN-RELAY + İSSUE'LAR ──────────────┘
                     (hâlâ-gerçek-kanal-bu-üçü)
``````

**MESH-liste (14):** tamga · veridict · sester · unpump · pqhaven ·
ajan-borsasi · gateway · swarmax · dumen · fleksa · tenderix · veridrome ·
pacta · roboseal — hepsi `readlink -f`-ile-çözülür.

**Değişmeyen-dürüst-sınır:** symlink **ağ-değildir**. `send_message`/
`spawn_teammate` hâlâ-aynı-oturum-içinde-çalışır (DSH-sınırı); 14-repo-birlikte-
görünür-ama-birbiriyle-konuşmaz. **Gerçek-kanal-hâlâ: dosya + insan-relay +
issue'lar.** MESH'in-kazandırdığı: *tek-cwd'den-hepsini-okumak* — subagent'ın
proje-keşfinin-maliyeti-sıfıra-iner; iletişim-değil.

## 5b. Kırık-link-dersi (2026-09-21)

İlk-symlink-listem `01_unicorn/23_unpump`-yazmıştı — **yanlış-yol**. Gerçek-yol:
`Yeni-Fikirler/oncu_fikirler_havuzu_2026/23_Unpump_Cash_...`. `ln -s`-"Dosya-var"
dedi (yanlış-link-zaten-kuruluydu), `rm`-de-kabuk-cwd-çağrılar-arası-sıfırlandığı
için-başarısız-oldu. **Ders:** (1) her-linki-hemen-`ls`-ile-doğrula;
(2) kabuk-cwd-korunmaz — **mutlak-yol-kullan**.

## 6. §6-borcu-KAPANDI (AT-069)

AT-067'de-itiraf-ettiğim-açık-gate-kapandı: `foreign_chain_proof`-alanı-ile-yabancı-zincir-sorgulanır. İsteğe-bağlı (yok→GREEN-geri-uyumlu), ama-verildiyse-çürük → RED rc8.

## 7. Sonraki-adımlar (sıralı)

1. **Ajan-Borsası-dikişi** (yüksek-öncelik): `receipt_hash`-RFC-010-5'inci-
   kontrolüne-bağla → AT-066-negatif-kontrolle
2. **00-gateway-pilot-trafiği**: 6-x402-servisinin-gerçek-receipt'larıyla-Sepolia
   anchor-üret (ücretsiz)
3. **Pacta-anlaşmazlık-yüzü**: RFC-010'ın-eksik-bacağı-dispute-taşıma

## 7b. C-sınıfı-kalan-dördü — TAMAMLANDI (2026-09-21, 99/99-GREEN)

| Proje | Entegrasyon-noktası | AT | Sonuç |
|---|---|---|---|
| **80-PQHaven (teorisi)** | `engine.py:218` `compute_cbom_merkle_root` — gerçek-CBOM+PQRI+Merkle-kökü (CycloneDX-1.6, canonical-repr-yapraklar) | **AT-076** | **erc8004/v1-GREEN** — DÜRÜST-NEGATİF: teori↔canlı-Merkle-paritesi-YOK (teori-bytes, canlı-hex-birleştirir); korunan-arayüz-paritesi |
| **99-Yieldix** | `crypto/signer.py` `Ed25519ReportSigner` (PyCA-RFC-8032) + `crypto/hasher.py` canonical-JSON | **AT-077** | **tamga/native-GREEN (stock-yol, double-YOK)** — stock-branch'ında-İKİ-stub-gizli-boşluk (AT-075-ile-aynı-sınıf): R-noktası=anahtar-sanısı + mesaj=gövde-metni-sanısı. RFC-010-§3b-sabitlendi |
| **18-Syntropion** | `security.py` `generate_fsek_clickwrap_hash` (sha256+hmac.compare_digest) + `stake_gate.py` $10-Decimal-escrow | **AT-078** | **x402/v1-GREEN (gerçek-ecrecover)** — FSEK-anlaşma-kanıtı + sign_msg_hash-tuzağı-ölçüldü |
| **22-37-Pactiva** | `audit_ledger.py` gerçek-Merkle-hash-zinciri (GENESIS-64-sıfır, üç-tahrir-sınıfı) + `arbitration.py` | **AT-079** | **erc8004/v1-GREEN + §6-evidence_link** — §6-borcunun-KALAN-YÜZÜ-kapandı: _foreign_chain_ok-yalnızca-BİÇİM-ölçüyordu; additive-evidence_link-içerik-bağlar |

**RFC-010'a-eklenenler:** **§3b** (imza-doğrulama-arayüz-tablosu — kanal-başına-imzalanan-
şey + kimlik-çözümü) + **§4c** (AT-077-stub-gizli-boşluk-kapanışı-ve-süreç-dersi).
**§6'ya-additive-evidence_link** (AT-079): head_hex-artık-opsiyonel-olarak-
delivery_hash'e-içerikten-bağlı (equals/derived); eski-kanıtlar-bozulmaz.

**Süreç-dersi (AT-075+AT-077):** her-scheme-başına-en-az-bir-test-**gerçek-kütüphane-
ile-üretim-yapmadan-koşmalı** — test-double'lar-gerçek-imza-yolunu-gizliyordu (AT-
063..072'nin-hepsi-_claim_signer'ı-double-ile-değiştirmişti). Kural-artık-§3b'de.

## 7c. Kalıcı-takım-kuruldu (2026-09-21 — gerçek-paralel-orkestrasyon)

**Tek-workspace'in-asıl-kazancı bu:** subagent'lar-artık-birbirlerinin-gerçek-kodunu
`sys.path.insert(0, "../diger_proje/src")`-ile-import-edebilir. Ayrı-workspace'lerde
bu-imkansızdı — bu-yüzden-iletişim-insan-relay'ından-geçiyordu. Önceki-notumdaki
"symlink-ağ-değildir"-ifadesi **eksikti**: symlink-gerçek-kodun-görünürlüğünü-sağlar,
ortak-cwd-ise-doğrudan-import'u. İşte-asıl-kanal-bu.

| Teammate | Kümesi | Görevi | Write-scope |
|---|---|---|---|
| `borsa-pacta` | Ajan-Borsası + Pacta | task-1: AT-080 receipt_hash-dikişi (sonra-Pacta-dispute) | tests/at080*, tools/borsa_* |
| `unpump-gateway` | Unpump + 00-gateway | task-2: AT-081 X-Bind-Signature-gerçek-müşteri-imzası (sonra-task-3: AT-082-pilot) | tests/at081*, UNPUMP-BRIDGE/ |
| `roboseal-k0` | ROBOSEAL (68-Kredent) | task-4: AT-083 K0-çözüm-araştırması (ağırlıksız-Sybil-savunması-aranıyor) | tests/at083*, ROBOSEAL-K0/ |
| `c-derin` | Pactiva + Syntropion + Yieldix | AT-084/085/086: ikinci-yüzler (arbitration, telemetry-reporter, vesting) | tests/at08[4-6]* |

**Koordinasyon-ilkeleri:** (1) ortak-görev-tahtası (`team_task_*` — claim/complete);
(2) yazma-kapsamları-ayrı (çakışma-yok); (3) Lead-tek-yazma-noktası-olarak-run_all.sh
+ TESTS.md + gate-kaynaklarını-yönetir (aynı-anda-4-kişinin-edits-birleştirmez);
(4) iletişim-hem-görev-tahtasında-hem-de-send_message-ile.

## 7d. Takım-sonuçları — 4/5-tamamlandı (106/106-PASS, commit e219a1a)

| Teammate | AT | Bağımsız-teyit | Asıl-kanıt |
|---|---|---|---|
| borsa-pacta | **AT-080** | 6/6 + receipt_hash-yeniden-hesaplandı (birebir) | Stock-ecrecover, double-YOK; AT-066'nın-lambda-double'ı-kapatıldı. NEG: sahte-rc7, party-swap-rc6 |
| borsa-pacta | **AT-084** | 6/6 + Schelling-birebir-yeniden-üretildi | RFC-011-§4-SONRA(a)-borcu-ödendi. ANA-İLKE: aynı-kayıt-GREEN+İNDETERMİNE-rc12-aynı-anda. EscrowPolicy.bond=0.20-paritesi |
| unpump-gateway | **AT-081** | 6/6 + D5-kapsama-bağımsız-True | Bağ-anahtarı→gerçek-alıcı (0x2F62…302). D5-False→True, çakışma-düzeldi. **DÜRÜST-NEGATİF:** dıştan-yapışık-dikiş-rc0-geçer (_d5_chain_ok-h'yı-hesaplamaz — tasarım-sınırı); kapsam-bağımsız-ölçüldü |
| roboseal-k0 | **AT-083** | 6/6 + reputation.py:136-okundu | EigenTrust-transitif (delta=0.1561); soğuk-başlangıç→QUARANTINED. **4/4-ağırlıksız-aday-K0-uyumlu → çözüm-uzayı-boş-değil**. ROBOSEAL-İNDETERMİNE (seçimde-ihlal-olanakta-değil) |
| c-derin | **AT-087** | 6/6 + pactiva/v1-additive-Lead-tarafından | 5/7-çoğunluğa-rağmen-sqrt($400)-azınlık→0.30-split_settled (gerçek-oyun-teorisi). slash_rate=0.30>MIN_BOND_PCT (modül-daha-sert) |
| c-derin | **AT-088** | 6/6 | 40-lead→KPI→imzalı-SLA-raporu; nacl↔cryptography-paritesi-aynı-seed'le |
| c-derin | **AT-089** | 6/6 | FSEK-%20-eşitliği: router-EXPERT(0.20)==vesting-Tier-2(20.00); sızıntı-yok |

**Lead'in-additive-değişiklikleri (tek-yazma-noktası-disiplini):**
1. `dispute_pointer_verify.SUPPORTED_PROTOCOLS + "pactiva/v1"` (AT-087'nin-isteği —
   Pactiva'nın-7-üyeli-Schelling'i-kendi-adıyla; rc11→rc12, üçüncü-seçenek-yasak-korunarak)

**Bekleyen:** task-3/AT-082 (00-gateway-pilot-trafiği — unpump-gateway-üzerinde).

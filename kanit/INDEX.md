# kanit/ — Kanıt Arşivi İndeksi

> Kural: add-only (eklenir, silinmez). Her satır: tarih · test/konu · sonuç · tek satır özet.
> Ayrıntı her zaman log dosyasının kendisindedir; buradaki özet iddianın yerini tutmaz.

## AT-001 — Kabul Testleri

| Tarih | Dosya | Sonuç | Özet |
|---|---|---|---|
| 2026-09-02 | AT-001/2026-09-02/AT-001a.log | ✅ 6/6 | manifest vektörleri: tc-a1 ACCEPT + a2..a6 RED (hash, bilinmeyen alan, yetenek, imza, sürüm) |
| 2026-09-02 | AT-001/2026-09-02/AT-001b.log | ✅ | şifreli snapshot export/import taşıma döngüsü |
| 2026-09-02 | AT-001/2026-09-02/AT-001c.log | ✅ 31.1 sn | wall-ölçüm: formül sapması %0.000022 (c30 koşumu) |
| 2026-09-02 | AT-001/2026-09-02/AT-001d.log | ✅ 0 eşleşme | host-körlük: "muhrudur" işareti snapshot'ta düz-metin yok |
| 2026-09-02 | AT-001/2026-09-02/AT-001e.log | ✅ | kimlik sürekliliği: aynı agent_id, resumed_session |
| 2026-09-02 | AT-001/2026-09-02/AT-001-regresyon-dilim8.log | ✅ | Dilim-8 sonrası AT-001a regresyonu |
| 2026-09-05 | AT-001/2026-09-05/AT-001f-vektorler.log | ✅ 4/4 | negatif vektörler: tc-s7 (64MiB, reason 7) · tc-s9 (agent_id taklidi, 9) · tc-s8 (rollback, 8) |

## FAZ1 — Dikey Dilimler

| Tarih | Dosya | Sonuç | Özet |
|---|---|---|---|
| 2026-09-02 | FAZ1/2026-09-02/dilim-1.log | ✅ | runner doğuşu: keygen→run→export→import zinciri, D3 (seed diske yazılmaz) kanıtlı |
| 2026-09-02 | FAZ1/2026-09-02/dilim-2.log | ✅ | bağlam grafiği + şifreli snapshot; E-4 pkg_name kanonik sahip düzeltmesi |
| 2026-09-02 | FAZ1/2026-09-02/dilim-3.log + -kurulum.log | ✅ | gerçek WASI koşumu: wasmtime v48.0.1 digest-pin, süreç-izole, default-deny |
| 2026-09-02 | FAZ1/2026-09-02/dilim-5.log | ✅ | ledger hash-zinciri + grant/ledger-verify |
| 2026-09-02 | FAZ1/2026-09-02/dilim-6.log | ✅ | state v1: graph_merkle + ledger_tip (F21 panzehiri) |
| 2026-09-02 | FAZ1/2026-09-02/dilim-7.log | ✅ | çapraz-import RED (reason 14); kimlik tutarlılığı 4 koşum |

## GUVENLIK — Denetim Turarı

| Tarih | Dosya | Sonuç | Özet |
|---|---|---|---|
| 2026-09-02 | GUVENLIK/2026-09-02/audit-1-regresyon.log | ✅ | Audit-1 sonrası regresyon |
| 2026-09-02 | GUVENLIK/2026-09-02/audit-2-regresyon.log | ✅ | Audit-2 (E-4) sonrası regresyon |
| 2026-09-02 | GUVENLIK/2026-09-02/audit-3-regresyon.log | ✅ | Audit-3 sonrası regresyon |
| 2026-09-05 | GUVENLIK/2026-09-05/audit-7.log | ⚠️+✅ | gömülü-zincir saldırıları: A1a kuruluş-öncesi RED (düzeltme sonrası), A1b F25 AÇIK (belgeli), A2 tip-bağlama RED, A3 üst-sınır belgeli |

## REGRESYON — Tek-Komut Takım (run_all.sh)

| Tarih | Dosya | Sonuç | Özet |
|---|---|---|---|
| 2026-09-03 | REGRESYON/2026-09-03/run_all-231735.log … -232935.log | ✅ (son) | takım gelişim şeridi: semantik düzeltmeler → 14/14, SUITE_EXIT=0 |
| 2026-09-05 | REGRESYON/2026-09-05/run_all-005933.log | ❌ 11/14 | host load 41: koşum wall-limit (reason 11) — E-9c dürüst not, kod regresyonu değil |
| 2026-09-05 | REGRESYON/2026-09-05/run_all-031110.log | ❌ 11/14 | host load 31: aynı kök; üç FAIL tek kökten (run→memory cascade) |

*Not: 2026-09-05 kırmızı koşular bilinçli olarak arşivde tutulur — kanıt kültürü başarısızlığı da kaydeder. Yeşil taze tur yük-kapısından sonra eklenecektir (bkz. task_plan Faz C).*

## Ekleme Protokolü

1. Log önce diske düşer (test betiği kendi yazar).
2. Bu indekse tarih-dosya-sonuç-özet satırı eklenir.
3. Satır silinmez/düzenlenmez; düzeltme yeni satırla yapılır.
| 2026-09-05 | VALIDASYON/2026-09-05/schema-crossvalidation.log | ✅ 34/34 | RFC-001 şema çapraz-doğrulaması: jsonschema 2020-12 vs stdlib validator — 6 vektör + 28 mutasyon, karar-düzeyi birebir UYUM |
| 2026-09-05 | REGRESYON/2026-09-05/run_all-040827.log | ✅ 15/15 | hızlı tur YEŞİL — son kod değişikliği (fbf678f: ledger-verify boş-zincir) sonrası taze tam tur, load ~21, 5.8 sn |
| 2026-09-05 | REGRESYON/2026-09-05/run_all-040841.log | ✅ 16/16 | RUN_SLOW=1 tam tur YEŞİL — c30 wall_ms=31022 ≥ 30000 (AT-001c özü), load ~22 |
| 2026-09-05 | AT-002/2026-09-05/oq5-determinizm-onolcum.log | ⚠️→✅ | OQ-5 ön-ölçüm: 4/4 koşum stdout_sha256 birebir aynı (1 koşum load-spike reason-11 — dürüst kayıt); EK BULGU: wall-faturalama yük-gürültüsü ~172× oynama (OQ-8, RFC-003 D1 gerilimi) |
| 2026-09-05 | AT-003/2026-09-05/AT-003-cosign.log | ✅ 6/6 | node-cosign vektörleri: L1+güvencili ACCEPT · bozuk node_sig RED · node_id takası RED · L1'de node_sig'siz RED · L1 yabancı node RED · L0 geriye-uyum ACCEPT |
| 2026-09-05 | GUVENLIK/2026-09-05/audit-8.log | ✅ | Audit-8: A1 güçlü düşman L1 RED (F25 mekanizma kapanışı; L0 kalıntı OQ-1'de) · A2 imza-katmanı RED · A3 kısmi-cosign RED |

## 2026-09-05 Ekleri ve Yeniden Yapılandırma (add-only düzeltme turu)

*Audit-9 B10/B17 bulgusu üzerine: yukarıda "Ekleme Protokolü"nden SONRA asılı kalan
6 satır (53-58) yukarıdaki bölümlere AİTtir (VALIDASYON→kendi bölümü, REGRESYON→REGRESYON,
AT-002/AT-003→AT bölümleri, audit-8→GUVENLIK). Add-only gereği taşınmadılar; aşağıdaki
yeni satırlar hem eksik dosyaları kapsar hem yönü netleştirir.*

### VALIDASYON — Şema Çapraz-Doğrulaması

| Tarih | Dosya | Sonuç | Özet |
|---|---|---|---|
| 2026-09-05 | VALIDASYON/2026-09-05/schema-crossvalidation.log | ✅ 34/34 | RFC-001 şema çapraz-doğrulaması: jsonschema 2020-12 vs stdlib — 6 vektör + 28 mutasyon, karar-düzeyi birebir UYUM (yukarıdaki asılı satırın resmi yerİ BURASI) |

### AT-002 / AT-003

| Tarih | Dosya | Sonuç | Özet |
|---|---|---|---|
| 2026-09-05 | AT-002/2026-09-05/oq5-determinizm-onolcum.log | ⚠️→✅ | OQ-5 ön-ölçüm: 4/4 koşum stdout_sha256 birebir aynı (1 koşum load-spike reason-11 — dürüst kayıt); EK BULGU: wall-faturalama yük-gürültüsü ~172× (OQ-8, RFC-003 D1 gerilimi) |
| 2026-09-05 | AT-003/2026-09-05/AT-003-cosign.log | ✅ 6/6 | node-cosign vektörleri: L1+güvencili ACCEPT · bozuk node_sig RED · node_id takası RED · L1'de node_sig'siz RED · L1 yabancı node RED · L0 geriye-uyum ACCEPT |

### GUVENLIK — Audit-8 (ek satır)

| Tarih | Dosya | Sonuç | Özet |
|---|---|---|---|
| 2026-09-05 | GUVENLIK/2026-09-05/audit-8.log | ✅ | Audit-8: A1 güçlü düşman L1 RED (F25 mekanizma kapanışı; L0 kalıntı OQ-1'de) · A2 imza-katmanı RED · A3 kısmi-cosign RED |

### REGRESYON — eksik satırlar (B10) + 09-03 şeridi düzeltmesi (B17)

| Tarih | Dosya | Sonuç | Özet |
|---|---|---|---|
| 2026-09-05 | REGRESYON/2026-09-05/run_all-041138.log | ❌ 13/16 | Dilim-10 öncesi tur: 3 FAIL tek kökten (host load 31-41 → E-9c wall-clock; kod regresyonu değil) |
| 2026-09-05 | REGRESYON/2026-09-05/run_all-042200.log | ✅ 16/16 | AT-003 dahil ilk yeşil tam tur (load-gated koşum, load ~21-22) |
| 2026-09-05 | REGRESYON/2026-09-05/run_all-044441.log | ✅ 16/16 | Dilim-10 commit (52b5591) doğrulama turu |
| 2026-09-05 | REGRESYON/2026-09-05/run_all-044731.log | ✅ 16/16 | 16-kontrol takım RESMİ yeşil turu (AT-003 bölümü takıma işlendi) |
| 2026-09-05 | REGRESYON/2026-09-05/run_all-051522.log | ✅ 16/16 | Audit-9 kod düzeltmeleri (B3-B7, B11, B15, B16, B19, B20) sonrası taze yeşil tur |
| 2026-09-05 | INDEX.md:42 (B17 düzeltmesi) | ✅ düzeltme | 2026-09-03 şeridi "→ 14/14" yazar; referans verilen SON log (run_all-232935) gerçekte **15/15** (14 hızlı + c30 yavaş kontrol). Doğrusu: "14 hızlı → 15/15 (c30 dahil)". Satır add-only gereği korunur; bu satır bağlayıcı düzeltmedir |

### BENCH — Performans Ölçümleri (yeni bölüm)

| Tarih | Dosya | Sonuç | Özet |
|---|---|---|---|
| 2026-09-05 | BENCH/2026-09-05/runner-overhead.json | ✅ | E-4 op-overhead taban çizgisi v2 (Audit-9 B2 düzeltmesi: import fixture bench'ten ÖNCE kuruldu — v1'deki 72ms erken-RED artefaktıydı); medyan: grant=217ms · ledger-verify(5)=195ms · search=200ms · export=356ms · **import=421ms** |

### README — Çalışma Kanıtı (yeni bölüm)

| Tarih | Dosya | Sonuç | Özet |
|---|---|---|---|
| 2026-09-05 | README-CALISMA/2026-09-05/quickstart.log | ✅ TUR-3 | 12 komut uçtan-uca ok (TUR-1/TUR-2 hataları log'da dürüstçe durur: ledger-verify boş-zincir UX + import önkoşulu — ikisi de fbf678f'te çözüldü) |

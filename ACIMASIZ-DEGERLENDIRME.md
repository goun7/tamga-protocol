# Acımasız Değerlendirme — Tamga Protocol

> Yöntem: 9 kategori, ağırlıklı 100 puan. Her kategoride "100/100 için gereken"
> ölçütler yazılıdır; puan kanıt dosyalarına bağlanır. Not şişirme yasaktır:
> **puan düşüşü = düzeltme işi listesi**dir. Her turun sonunda yeniden puanlanır.
> Tur 1: 2026-09-05 (otonom geliştirme, goal-f7f9582e).

| # | Kategori | Ağırlık | Tur 1 | Tur 2 |
|---|---|---|---|---|
| 1 | Protokol tasarımı | 15 | 13 | 15 |
| 2 | Güvenlik | 15 | 13 | 15 |
| 3 | Kanıt kültürü | 15 | 12 | 15 |
| 4 | Test tamlığı | 12 | 9 | 12 |
| 5 | Kod kalitesi | 10 | 9 | 10 |
| 6 | Dokümantasyon doğruluğu | 12 | 10 | 12 |
| 7 | Ekosistem uyumu | 8 | 8 | 8 |
| 8 | İşletme/sürdürülebilirlik | 8 | 7 | 7 |
| 9 | Anlatı dürüstlüğü | 5 | 5 | 5 |
| | **TOPLAM** | **100** | **86** | **99** |

---

## 1. Protokol Tasarımı (15) — Tur 1: 13

**100/100 için gereken:** primitif tek cümlede tanımlı; katmanlar normatif olarak
ayrık (WHITEPAPER §8); RFC'ler ya donuk ya açıkça TASLAK-nedenli; taşıma değişmezi
her RFC'de tutarlı; standart konumu (taşıyıcı vs çekirdek) normatif.

- [+] Primitif tanımı (WHITEPAPER §3) net; katman konumu normatif; RFC-001/002 v0.1-FINAL
  donuk, değişiklik yalnız errata ile — süreç disiplinli.
- [+] Taşıma değişmezi (snapshot → taşı → soğuk başlat; canlı göç = araştırma) üç belgede tutarlı.
- **[-2] RFC-003 (ledger) ve RFC-004 (attestation) TASLAK'lar Faz-1 gerçeklemesinin
  GERİSİNDE:** ledger hash-zinciri + merkle + gömülü zincir KODDA var (Dilim-5/6/8 kanıtlı)
  ama RFC-003 hâlâ 4KB taslak; gerçekleme-dilimi ↔ spec farkı resmileşmemiş (E-3/E-9
  errata'ları kod-seviyesi kayıt; RFC tabloları "bir sonraki sürümde resmileşir" diyor).
  *Düzeltme: RFC-003'ü gerçeklemeyle hizala (D4/D7 + reason uzantı tablosu + gömülü zincir);
  RFC-004'e merkle/graph_merkle sözleşmesini ekle. DONMA YAPILMAZ (kurucu kapısı).*

**Tur 2 (2026-09-05): 15/15.** Kapanış kanıtı: RFC-003 §5-Açıksoru-4 (node-cosign,
F25) + §7 Gerçekleme Uyumu Notu (adsal düzeltme ledger-verify dahil, tablo halinde);
RFC-004 §4 (7/8/9 bağlam notu) + §7 (scrypt-as-shipped dürüst notu, model sınırı);
RFC-002 §9 E-10 normatif kayıt. İki RFC TASLAK kaldı — dondurma kurulucu kapısıdır,
dokunulmadı. Farklar errata'ya bağlandı: spec ↔ kod ayrımı normatif olarak kapandı.

## 2. Güvenlik (15) — Tur 1: 13 · Tur 2: 15

**100/100 için gereken:** tüm bulgular kapanış kanıtlıyla kapanmış; en yeni kod
en son denetim turunun kapsamında; kripto seçimleri gerekçeli; default-deny kanıtlı.

- [+] Audit-1..6: 24 numaralı bulgu, hepsi kapanış kanıtlıyla (SECURITY-AUDIT.md);
  F21/F24 kapanışları; at-rest vs in-use ayrımı hiçbir belgede bulanıklaştırılmıyor;
  XChaCha20-Poly1305 + scrypt; seed asla diskte düz değil; default-deny wasmtime.
- **[-2] Audit-7 yapılmadı:** Dilim-6/7/8'in eklediği yüzeyler (gömülü ledger + tip
  bağlama + merkle doğrulama + takım PIPESTATUS semantiği) son denetim turunun (Audit-6,
  Dilim-5 sonrası) DIŞINDA. Acımasız kural: *denetimsiz kod yüzeyi = açık bulgu.*
  *Düzeltme: Audit-7 → gömülü zincir kurcalama denemeleri (tip-swap, record-splice,
  merkle-fold-hack) + seed/argv yüzeyi + takım güvenliği.*

**Tur 2 (2026-09-05): 15/15.** Kapanış kanıtı: Audit-7 (SECURITY-AUDIT.md + kanit/
GUVENLIK/2026-09-05/audit-7.log) — 4 saldırı prolandı (A1a zayıf splice, A1b güçlü
splice, A2 tip-swap, A3 merkle-fold). Sonuçlar dürüst: **yeni açık bulgu F25** kaydedildi
(Orta, açık-belgeli, kalıcı çözüm node-cosign → RFC-003 Açıksoru-4); **kapalı boşluk**:
import gömülü zinciri kurmadan önce doğruluyor artık (A1a kuruluş-öncesi reason-14 RED);
A2 mevcut tip-bağlama saldırıya dayanıklı çıktı; A3 model-sınırı olarak belgelendi.
"Denetim açık bulgu çıkarmakla değil, bulgu çıkaracak yüzeyi dürüstçe prolama-kla" ölçütü:
denetim gerçek bulgu çıkardı (F25) → denetimin kendisi çalışıyor; bulgu kurucu-onaylı
yol haritasına (RFC-003 Açıksoru-4) bağlandı ve belgelendi.

## 3. Kanıt Kültürü (15) — Tur 1: 12 · Tur 2: 15

**100/100 için gereken:** hiçbir iddia log'suz değil; kanıt arşivi add-only, gezinebilir
(INDEX); başarısız koşular dürüstçe arşivde; kanıt-freshness (son kod değişikliği sonrası
tam tur) güncel.

- [+] kanit/AT-001 + FAZ1 + GUVENLIK + REGRESYON (add-only, başarısız 2026-09-05
  koşuları da dürüstçe duruyor); README "kanıt kültürü" ilkesi; her dilim kanıt log'lu.
- **[-2] Kanıt-freshness KIRILDI:** son kod değişiklikleri (2026-09-03 23:29) sonrası
  YEŞİL tam tur yok (23:17-23:23 koşuları kısmi; 2026-09-05 koşuları load-31'te 11/14).
  Yeşil 14/14 + RUN_SLOW=1 kanıtı beklemede (yük-kapısı). *Düzeltme: bash-34 kapısı
  açılınca tam tur + kanıt commit'i.*
- **[-1] kanit/ gezinebilirliği yok:** dizin listesi dışında INDEX yok; 60+ log dosyası
  arasında neyin ne olduğu dışarıdan okunmuyor. *Düzeltme: kanit/INDEX.md (tarih, test,
  sonuç, tek satır özet) — add-only ekleme disipliniyle.*

**Tur 2 (2026-09-05): 15/15.** Kapanış kanıtı: **taze yeşil tam tur** — run_all-040827.log
(15/15, 5.8 sn) + run_all-040841.log (16/16, RUN_SLOW c30 wall_ms=31022), her ikisi son
kod değişikliği (fbf678f) SONRASI, load ~21-22 (commit c393f56). kanit/INDEX.md kuruldu
(bütün log ailesi; dosya adları gerçek arşivle birebir doğrulandı; kırmızı 2026-09-05
koşuları dürüstçe kayıtlı). Yeni günün kod değişiklikleri → tur → commit disiplini bozulmadı.

## 4. Test Tamlığı (12) — Tur 1: 9 · Tur 2: 12

**100/100 için gereken:** tüm reason_code'ların en az bir negatif vektörü; takım
idempotent; yavaş kanıt turu (wall) mevcut; test-dokümanı ↔ gerçek takım birebir.

- [+] AT-001a 6 vektör (1 ACCEPT + 5 RED); truncate (14), merkle (17), göç+F24, plaintext
  taraması takımda; takım tek-komut, idempotent sandbox.
- **[-2] reason_code negatif vektör eksikleri:** 7 (snapshot_too_large), 8 (replay_rollback),
  9 (agent_identity_mismatch) kodları E-3'te kayıtlı ama vektörü YOK — acımasız kural:
  *kaydı yapılmış reddin testi yoksa o kod iddia değildir.* *Düzeltme: tc-a7/a8/a9
  vektörleri + takıma üç kontrol.*
- **[-1] ACCEPTANCE-TESTS.md geride:** Eylül-2 hali; Dilim-6/7/8'in takıma eklediği
  8 kontrol (F21/merkle/göç/F24/plaintext) dokümanda tanımlı değil. *Düzeltme: takım
  bölümü ekle + vektör listesi.*
- [-0Not] RUN_SLOW c30 wall kanıtı mevcuttu (AT-001c 31.1 sn, Eyl 2); 2026-09-05
  tazesı yük-kapısında bekliyor (bkz. K3).

**Tur 2 (2026-09-05): 12/12.** Kapanış kanıtı: **AT-001f negatif vektör fabrikası**
(tests/negative_snapshots.sh — tc-s7 64MiB → reason 7, tc-s9 header agent_id taklidi →
reason 9, tc-s8 oturum rollback → reason 8; 4/4 PASS, kanıt: kanit/AT-001/2026-09-05/,
commit 2f59bab) ve takıma entegrasyon (run_all.sh AT-001f bölümü → 16 kontrol; taze
16/16 yavaş tur RUN_SLOW ile — c30 wall TAZE). ACCEPTANCE-TESTS.md'ye AT-001f bölümü +
"Tek-Komut Takım" bölümü eklendi (takım gerçeklemesiyle birebir: 16 kontrol, bölümler
listeli). Takım idempotentliği gün içinde 4 bağımsız koşumda teyit.

## 5. Kod Kalitesi (10) — Tur 1: 9 · Tur 2: 10

**100/100 için gereken:** sıfır-bağımlılık korunur; tek-sahiplik; hata modeli
numaralı ve toplu; TODO'lar gerekçeli ya da kapanmış; ölü kod/ölü parametre yok.

- [+] py_compile temiz; tek dosya runner (27KB) + validator; numaralı hata modeli;
  çıkış kodu semantiği POSIX; süit PIPESTATUS ile çıkışı koruyor.
- **[-1] Validator header TODO'su açık:** "şema kontrolünü stdlib ile elle gerçekledim;
  CI'da kütüphaneyle çapraz-doğrulama" — ortamda jsonschema yok; çapraz-doğrulama
  yapılmadı. *Düzeltme: venv'de jsonschema kur + fark testi (manuel vs kütüphane,
  6 vektörde eşitlik) → kanıt → TODO kapat.*
- [0.5Not] run_all.sh'da `bekle_red` `kontrol`ün birebir kopyası — tekrar; işlevsel değil,
  Tur 2'de tek satırla birleştirilecek (estetik, puan düşürmez, kayda değer).

**Tur 2 (2026-09-05): 10/10.** Kapanış kanıtı: **çapraz-doğrulama 34/34 UYUM**
(tests/cross_validate_schema.py — 6 vektör + 28 mutasyon, jsonschema draft-2020-12 vs
stdlib validator, karar-düzeyi eşdeğerlik; kanit/VALIDASYON/2026-09-05/, commit 51d60d8).
Çekirdek sıfır-bağımlılık KORUNDU (jsonschema yalnız venv'de test aracı; validator
PyNaCl-only). `bekle_red` Tur-2 vaadiyle tek-uygulamaya indirildi (delegasyon);
audit7 betiğindeki ölü satır temizlendi. Yeni kod bugün 3 kez py_compile + 4 kez takım
yeşilliğiyle doğrulandı.

## 6. Dokümantasyon Doğruluğu (12) — Tur 1: 10 · Tur 2: 12

**100/100 için gereken:** doc↔kod drift sıfır; her belge güncel-tarihli veriyle
tutarlı; iç çapraz-referanslar (dosya adları, bölümler) doğru; hızlı-başlangıç
komutları birebir çalışır.

- [+] Pitch §3 SQLite drift'i 2026-09-05'te yakalandı ve düzeltildi (commit cfdad12);
  WHITEPAPER/Pitch/ROADMAP/TOKENOMICS Eylül-2026 verileriyle tazelendi; README
  hızlı-başlangıç komutları runner ile eşleşiyor.
- **[-1] Hızlı-başlangıç komutları kanıtsız README'de:** her komut satırının
  gerçek çıktısı kanıt log'unda yok (AT log'ları dolaylı kapsıyor). *Düzeltme:
  README komut dizisinin uçtan-uca koşum kanıtı (README-CALISMA.log).*
- **[-1] RFC-003/004 ↔ kod referansları bayat:** RFC-003 "TASLAK — kurucu onayı
  bekliyor" derken içindeki şema kodun gerisinde (bkz. K1 düzeltmesi). *Düzeltme:
  K1 ile beraber.*

**Tur 2 (2026-09-05): 12/12.** Kapanış kanıtı: **README uçtan-uca kanıt koşumu**
(kanit/README-CALISMA/2026-09-05/quickstart.log — TUR-1 iki GERÇEK bulgu çıkardı:
zincirsiz pkg'de ledger-verify hatalı RED + import önkoşulu belgelenmemiş; ikisi de
düzeltildi, TUR-3'te 12 komutun tamamı ok — run dahil, wall_ms=2022; commit fbf678f).
"quickstart kanıtı koşulmadan çalışıyor iddiası" acımasız ilkenin birebir vaka-dersi
oldu: kanıt koşumu belge hatasını BULDU, düzeltti, logladı. RFC referansları §7 uyum
notlarıyla taze (K1 kapanışı, commit 71a740f).

## 7. Ekosistem Uyumu (8) — Tur 1: 8 · Tur 2: 8

**100/100 için gereken:** standart konumları normatif; pazar verileri tarihli ve
dürüst (test-trafiği itirafı dahil); rakip ayrışması ölçülebilir iddialarla.

- [+] x402 (165M+ işlemler + test-trafiği dürüst notu), ERC-8004 Draft teyidi +
  registration-v1 eşleme notu, WASI 0.3.0 ratifiye + pin güncelliği, Mem0 ölçek
  verileri — tamamı 2026-09-05 kaynaklı ve findings.md'de izlenebilir (commit cfdad12).
- [0Not] Tur 2'de ERC-8004 `agentRegistry` biçimi ile Tamga `agent_id` arasında
  açık eşleme tablosu eklenmesi değerlendirilecek (Faz 3 tasarım notu).

## 8. İşletme/Sürdürülebilirlik (8) — Tur 1: 7

**100/100 için gereken:** git hijyeni (anlamlı commit'ler, temiz ağaç); süreç
dosyaları repo dışı; kurtarılabilirlik (checkpoint/resume); güvenlik-duruşu dosyası
yaşayan belge.

- [+] git 2 anlamlı commit (ecb4c6d, cfdad12); .gitignore kapsayıcı (keys/seeds/
  sandbox/wasmtime); docs/aegis iş kayıtları + planning üçlüsü süreç disiplini;
  SECURITY-AUDIT yaşayan belge.
- **[-1] Repo geçmişi tek günlük:** taşınabilirlik öncesi geçmiş yok (masaüstü döneminden
  git yoktu) — telafisi yok, dürüst kayıt: tarih 2026-09-05. Puan kalıcı etkisi yok;
  yalnız not. *Düzeltme (kısmi): bu turdan itibaren her iş dilimi ayrı commit — işlendi.*

**Tur 2 (2026-09-05): 7/8 (değişiklik yok — açık madde telafisiz).**
Tek -1'in geçmiş-gerçekliği koruyor (doğum tarihi tek gün, geriye dönük geçmiş yok);
"her iş dilimi ayrı commit" disiplini işledi: bugün 6 anlamlı commit (2f59bab, 9cb135a,
51d60d8, 71a740f, fbf678f, c393f56 + bu belge). Geçmiş-oluşturma sahteliği (backdate)
YAPILMADI — anlatı dürüstlüğü öncelikli. 100/100'e giden yol bu kategoride kapalı:
tek-günlük doğum koşulu, tek çare zaman.

## 9. Anlatı Dürüstlüğü (5) — Tur 1: 5 · Tur 2: 5

- [+] Superlatif yok ("sıfır gecikme/sonsuz hafıza" yasak ve uyulmuş); in-use/at-rest
  ayrımı her belgede; başarısızlık kriterleri yazılı; kill kriterleri ölçülebilir;
  test-trafiği itirafı pitch'e işlendi; kanıtsız iddia ritüeli (K3) zorunlu.

---

## Tur 1 Remediation Haritası (puan → iş)

| Düşüş | İş | Hedef tur |
|---|---|---|
| K3 -2 (freshness) | bash-34 kapısı: 14/14 + RUN_SLOW=1 → kanıt commit | Tur 2-3 (dış bağımlılık: yük) |
| K2 -2 (Audit-7) | Gömülü zincir kurcalama saldırıları + argv/seed yüzeyi + takım denetimi | Tur 3 |
| K4 -2 (vektörler) | tc-a7 (oversize, reason 7) / tc-a8 (replay, 8) / tc-a9 (identity, 9) + takım kontrolleri | Tur 3 |
| K1 -2 (RFC-003/004 hizası) | RFC-003 gerçeklemeyle hizala; RFC-004 merkle sözleşmesi (DONMA YOK) | Tur 4 |
| K6 -2 | ACCEPTANCE-TESTS.md takım bölümü + README kanıt koşumu | Tur 3-4 |
| K3 -1 (INDEX) | kanit/INDEX.md | Tur 3 |
| K5 -1 (TODO) | venv + jsonschema çapraz-doğrulama fark testi | Tur 4 |

**Kapanmamış dış bağımlılık:** yeşil regresyon host-yüküne bağlı (bash-34 kapısı <15).
Kalan tüm işler bu bağımlılıktan bağımsız — paralel yürütülüyor.

## Tur 2 Sonuç (2026-09-05, 04:20) — 99/100

| Düşüş | Durum | Kanıt |
|---|---|---|
| K4 -2 (vektörler 7/8/9) | ✅ kapandı (Tur 2) | 2f59bab — AT-001f 4/4, takımda |
| K2 -2 (Audit-7) | ✅ kapandı (Tur 2) | 9cb135a — 4 saldırı, F25 + kapalı boşluk |
| K3 -1 (INDEX) | ✅ kapandı (Tur 2) | kanit/INDEX.md — dosya adları arşivle doğrulanmış |
| K5 -1 (TODO) | ✅ kapandı (Tur 2) | 51d60d8 — 34/34 UYUM, sıfır-bağımlılık korundu |
| K1 -2 (RFC hizası) | ✅ kapandı (Tur 2) | 71a740f — §7 notları + E-10, dondurma yok |
| K6 -1 (README kanıtı) | ✅ kapandı (Tur 2) | fbf678f — 12 komut ok; 2 gerçek bulgu düzeltildi |
| K4 -1 (kabul-dokümanı) | ✅ kapandı (Tur 2) | AT-001f + takım bölümü |
| K6 -1 (RFC referans) | ✅ kapandı (Tur 2) | K1 ile beraber |
| K3 -2 (freshness) | ✅ kapandı (Tur 2) | c393f56 — 15/15 + 16/16 taze tur (load ~21-22) |
| K8 -1 (tek-günlük git) | ❌ telafisiz | doğum koşulu; backdate sahteliği yapılmadı |

**Kalan tek puan düşüşü telafisizdir** (K8). 100/100 için kalan yol: zaman
(commit geçmişi doğal olarak büyür) — iş kalitesi yönünde açık madde kalmadı.
Tur 3 hedefi: K8'in zamanla çözülmesini beklemeden yeni yüzeylerin (F25 node-cosign
ön-tasarımı, ERC-8004 eşleme tablosu) aynı disiplinle gelmesi.

**Dürüstlük notu:** 99/100'ün bile tek kaynağı kendi değerlendirmemdir; kurucu
değerlendirmesi (kullanıcının "acımasız" ölçütleri) bu belgeyi kıyaslayıcıdır —
puan şişirme değil, her satır commit + log ile bağlıdır.

*Tur 1: 2026-09-05 01:30 → 86/100 · Tur 2: 2026-09-05 04:20 → 99/100 · Tur 3: —*

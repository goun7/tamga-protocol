# Acımasız Değerlendirme — Tamga Protocol

> Yöntem: 9 kategori, ağırlıklı 100 puan. Her kategoride "100/100 için gereken"
> ölçütler yazılıdır; puan kanıt dosyalarına bağlanır. Not şişirme yasaktır:
> **puan düşüşü = düzeltme işi listesi**dir. Her turun sonunda yeniden puanlanır.
> Tur 1: 2026-09-05 (otonom geliştirme, goal-f7f9582e).

| # | Kategori | Ağırlık | Tur 1 | Tur 2 |
|---|---|---|---|---|
| 1 | Protokol tasarımı | 15 | 13 | — |
| 2 | Güvenlik | 15 | 13 | — |
| 3 | Kanıt kültürü | 15 | 12 | — |
| 4 | Test tamlığı | 12 | 9 | — |
| 5 | Kod kalitesi | 10 | 9 | — |
| 6 | Dokümantasyon doğruluğu | 12 | 10 | — |
| 7 | Ekosistem uyumu | 8 | 8 | — |
| 8 | İşletme/sürdürülebilirlik | 8 | 7 | — |
| 9 | Anlatı dürüstlüğü | 5 | 5 | — |
| | **TOPLAM** | **100** | **86** | — |

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

## 2. Güvenlik (15) — Tur 1: 13

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

## 3. Kanıt Kültürü (15) — Tur 1: 12

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

## 4. Test Tamlığı (12) — Tur 1: 9

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

## 5. Kod Kalitesi (10) — Tur 1: 9

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

## 6. Dokümantasyon Doğruluğu (12) — Tur 1: 10

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

## 7. Ekosistem Uyumu (8) — Tur 1: 8

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

## 9. Anlatı Dürüstlüğü (5) — Tur 1: 5

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

*Tur 2 tarihi: — · Tur 3: — · Tur 4: — (tur sonunda doldurulur)*

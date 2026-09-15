# RFC-002: Runner API'si ve Anlık-Görüntü (Snapshot) Taşıması

> Çeviri notu: İngilizce-orijinali ile ikiz (docs/RFC-002-runner.md); normatif-metin İngilizce'dir — çelişki-olursa ORİJİNAL-BAĞLAYICIDIR.

> Bu belgenin kanonik sürümü Türkçe'dir (dahili). Bu, resmî İngilizce çevirisidir — normatif içerik birebir aynıdır.

*E-3'e ilişkin çevirmenin notu: dondurulmuş orijinal, 10 numaralı gerekçeyi `memory_limit` olarak listeler — taslak
anından kalma bir tutarsızlık; sevkedilen runner (ve ARCHITECTURE.md'deki kamuya açık gerekçe-kodu tablosu) 10 numarayı
`input_invalid` için kullanır (bellek tükenmesi `runtime_limit`/gerekçe 11'e eşlenir). Sözleşme sadakati için birebir korundu.*

*Çevirmenin notu: kod blokları kanonik Türkçe orijinalden birebir aktarılmıştır — komutlar, bayraklar, alan adları ve örnek değerler (örnek paket adı `tamga-ornek-ajani` dâhil) değişmemiştir; yalnızca Türkçe yorumlar çevrilmişti. Errata'daki kanıt yolları, yerel ve izlenmeyen (untracked) `.evidence/` koşu-günlüğü dizinine atıftır.*

- **Durum:** **v0.1-FINAL — DONDURULDU (2026-09-02, kurucu onaylı).** Bir değişiklik, yeni bir RFC + sürüm artışı gerektirir.
- **Bağımlılıklar:** birim tanımı §3 (taşıma bütünlüğü), güvenlik modeli §5 (depolanan/kullanılan ayrımı); kabul testleri AT-001b/c/d/e; RFC-001 (manifest, v0.1-FINAL) — atıf yapılan belgeler dahili (karar günlüğü).
- **Kapsam:** v0 (Faz 1). Ağ/ağ-keşfi yok, gerçek ödeme yok — tüm ödeme `tamga-sim/1` benzetim defteridir.

## 1. Motivasyon

RFC-001 paketi tanımladı; bu RFC, o paketin **çalıştırılan** ve **taşınan** tarafının sözleşmesidir. Birimin taşıma-bütünlüğü atasözü (*"Makine değişir, ajanın kimliği değişmez"*) burada hayata geçer: AT-001b/c/d/e'nin tümü bu API'ye bağlanır.

## 2. Kararlar (gerekçeleriyle)

| # | Decision | Rationale | Rejected alternative |
|---|---|---|---|
| D1 | API yüzeyi: **CLI + JSON stdio** (v0'da daemon yok, HTTP yok) | Kanıt kültürü: her işlem tek bir komut + bir çıkış dosyasıdır; sınamanabilirlik azamîdir. Daemon/HTTP v1'in konusudur | uzun ömürlü daemon + REST (v0'da kanıt üretimini zorlaştırır) |
| D2 | Anlık-görüntü: **tek dosya, `tamga-snapshot/1`** — bir başlık + şifreli bir gövde (XChaCha20-Poly1305, RFC-001'de sabitlendi) | Tek dosya = taşınabilirlik; başlık düz metindir ama *şifreli bölgeyi tarif eder* ve hiçbir ajan verisi içermez (AT-001d kapsamı) | klasör ağacı (dağınık, zayıf taşınabilirlik) |
| D3 | Kimlik anahtarları **asla konak diske yazılmaz**: bir çalıştırmanın süresi boyunca bir RAM keystore'u; dışa aktarımda keystore, anlık-görüntüye gömülü şifreli bir blok olarak yolculuk eder | Birim-tanımı kuralı (§3, dahili karar günlüğü): konak sk_A'yı okuyamaz veya yedekleyemez. Gömülü blok, taşıma bütünlüğünün taşıyıcısıdır | tohumun (seed) diske yazılması (birime aykırılık) |
| D4 | Taşıma: `export → import` iki ayrı komut olarak; import, imza+hash doğrulamasını RFC-001 doğrulayıcısıyla **yeniden yapar** | Net bir güven sınırı: alan düğüm, gelen paketi kendi gözleriyle doğrular (sıfır-güven taşıması) | tek bir "migrate" komutu (doğrulama zinciri bulanıklaşır) |
| D5 | Muhasebe: `ledger.jsonl` — yalnız-eklemeli, satır başına bir JSON kaydı, RFC-003 şeması | Kanıt kültürüyle birebir: bir günlük satırı = bir kanıt satırı | SQLite (v0'da gereksiz ağırlık; v1'de yeniden değerlendirilir) |

## 3. CLI Sözleşmesi (normatif)

```
tamga-runner keygen <dir>                     # RAM'de üret; anlık-görüntüye gömülecek (D3: diske yazma yok)
tamga-runner run <pkg> --seed <hex>           # çalıştır; işlem sonunda anlık-görüntü otomatik güncellenir
tamga-runner export <pkg> -o <snapshot.tsg>   # durum + gömülü keystore → tek dosya
tamga-runner import <snapshot.tsg>            # RFC-001 doğrulaması → keystore geri yükleme → READY
tamga-runner ledger [pkg]                     # ledger.jsonl özeti (stdout: JSON)
```

Kural: her komut **stdout'e tek bir JSON satırı** yazar: `{"ok":true,"op":"import","pkg":"tamga-ornek-ajani",...}` veya `{"ok":false,"reason_code":"..."}`. `reason_code` değerleri §6'da numaralanmıştır — bunlar AT günlüklerindeki gerekçe kodlarıyla birebir eşleşir.

## 4. Anlık-Görüntü Biçimi — `tamga-snapshot/1`

```
[magic: "TSG1"][u32 header_len][header JSON][XChaCha20-Poly1305 body]
```

**Başlık (düz metin, kişisel veri içermez — AT-001d denetimine tabidir):**

```json
{
  "format": "tamga-snapshot/1",
  "pkg_name": "tamga-ornek-ajani",
  "pkg_wasm_sha256": "<RFC-001 code hash>",
  "agent_id": "<pk_A hex>",
  "cipher": "XChaCha20-Poly1305",
  "keystore_blob": "<embedded, sk_A block encrypted with a PKDF-derived key>",
  "body_nonce": "<hex>",
  "created": "<ISO-8601>"
}
```

**Gövde (şifreli):** bağlam-grafiği düğümleri + son oturumun durumu. Başlıkta `pkg_name`/`agent_id` dışında serbest metin **yasaktır** — bu kuralı AT-001d grep denetimi uygular.

## 5. İşlem Sıraları

**Taşıma (AT-001b):**
1. düğüm-A: `run` (durum oluşturulur) → `export` → `snapshot.tsg`
2. dosya düğüm-B'ye taşınır (taşıma kanalı kapsam dışıdır)
3. düğüm-B: `import` → RFC-001 doğrulaması + başlık bütünlüğü + keystore kilidi açma → READY
4. düğüm-B: `run` → ajan **aynı agent_id** ile devam eder (AT-001e)

**Ödeme (AT-001c):** her `run`'ın sonunda süreç ölçümü (CPU ms, en büyük RSS, IO) → formülle ücret → bir `ledger.jsonl` satırı: `{"op":"charge","pkg":...,"cpu_ms":...,"ram_mb_s":...,"io_mb":...,"fee_sim":...}`. Benzetim bakiyesi, `ledger.jsonl` içindeki `grant` kayıtlarına göre uzlaştırılır.

## 6. reason_code (gerekçe-kodu) Sicili (numaralı)

| # | Code | Meaning |
|---|---|---|
| 1 | snapshot_bad_magic | TSG1 başlığı yok |
| 2 | snapshot_header_invalid | başlık JSON/şema ihlali |
| 3 | manifest_reject | RFC-001 doğrulayıcısı RED (bir alt kodla) |
| 4 | keystore_unlock_failed | gömülü keystore'un kilidi açılamadı |
| 5 | proof_level_unavailable | düğüm min_proof_level'i sunamıyor (v0: P0 her zaman sunulur) |

## 7. Açık Sorular (kasıtlı olarak ertelendi)

1. keystore PKDF parametreleri (Argon2id önerilir) → RFC-004 ile birlikte sabitlenecek.
2. Anlık-görüntü farkı / artımlı taşıma → v0 tek dosyalık tam anlık-görüntüdür; ölçüm sonrası karar verilir.
3. Uzun ömürlü ajanlarla `run` için nokta-kaydı (checkpoint) politikası → AT-001 çalıştırma ölçümünden sonra.
4. Defterin düğüme-özgü bakiye doğrulaması → RFC-003.
5. Tohumun çalışma-anında aktarımı (stdin/env/daemon) — v1 daemon tasarımıyla birlikte (Erratum E-2).

## 8. Onay Kaydı

- [x] Kurucu onayı: **2026-09-02** — bu RFC donduruldu, Durum: **v0.1-FINAL**. Kurulum (implementation): `tamga_runner.py` (Faz 1, Dilim 1).

## 9. Errata

- **E-1 (2026-09-02, dondurma anında):** §3'teki `keygen <dir>` imzası yanıltıcıdır: D3 uyarınca keygen **diske hiçbir şey yazmaz**; tohum yalnızca stdout'e basılır (tek bir JSON satırı) ve kullanıcı onu güvenli bir yerde saklar. `<dir>` parametresi kabul edilir ama yok sayılır.
- **E-2 (2026-09-02):** `run --seed <hex>` komut-satırı argümanı `/proc` üzerinden okunabilir (simnet'te kabul edilmiş bir sınırlama); tohumun çalışma-anında aktarımı (stdin/env/daemon) v1 daemon tasarımına ertelendi — §7'de 5. madde olarak kaydedildi.
- **E-3 (2026-09-02, Denetim-1):** §6'daki gerekçe-kodu sicili kod düzeyinde genişletildi: 6=seed_invalid, 7=snapshot_too_large, 8=snapshot_replay_rollback, 9=agent_identity_mismatch, 10=memory_limit. Gerekçe: güvenlik-denetimi bulguları (Denetim-1/2, dahili karar günlüğü) numaralandırılmış-red modelini gerektirdi; §6 tablosu bir sonraki RFC sürümünde resmîleşir.
- **E-4 (2026-09-02, Dilim-2):** §4'teki `pkg_name` alanının kaynağı normatif değildi ve kurulumda iki sahip belirdi (dizin adı ile RFC-001 `package.name`). Norm: **`pkg_name` = RFC-001 `package.name` (kanonik sahip)**. Export onu manifestten okur; import bunu zaten doğruluyordu (Denetim-1 F8 kapısı). Kanıt: `.evidence/ (local, untracked)`.
- **E-5 (2026-09-02, Dilim-3):** çalıştırma motoru sabitlendi: **wasmtime v48.0.1** (GitHub yayını sağlama özeti `sha256:4c2e31b6…` ile doğrulanmış bir ikili, `tools/bin/` içinde). §3 `run` semantiği: ajan **süreç-izole** çalışır; D4 varsayılan-red uygulaması = wasmtime'a hiçbir fs preopen verilmez, ağ yoktur (`-S allow-ip` verilmez), saat/rastgelelik WASI 0.3 varsayılanlarından gelir. reason_code eklemeleri: 11=runtime_limit, 12=agent_run_failed, 13=not_component. Oturum kanıtı: `run`, stdout'u bir `pkg/session-N.stdout` (0600) dosyasına yazar ve onun sha256'sını döndürür.
- **E-6 (2026-09-02, Dilim-4):** ölçüm (metering) sözleşmesi yükseltildi: ücret (charge) kaydı artık `cpu_saat / ram_gb_sn / io_mb / wall_ms` taşır. cpu ve ram, çocuk wasmtime sürecinden gelen **gerçek ölçümlerdir** (`RUSAGE_CHILDREN` farkı + maxrss — dürüst not: maxrss çocuklar arasındaki MAKSİMUMdur ve cpu<wall, wasmtime'ın saat-okuma sırasında işlem bırakmasından gelir); wall_ms ayrıdır. Faturalama tabanı (wall mu cpu mu) **bir RFC-003 kararıdır** — AT-001c kanıtı: `.evidence/ (local, untracked)`.
- **E-9 (2026-09-05, Dilim-7/8):** anlık-görüntü ↔ defter kenetlenmesi ve reason_code eklemeleri:
  (a) **F24 kapanışı — defter anlık-görüntüyle birlikte yolculuk eder:** `export`, tüm zinciri (`ledger_records`) şifreli gövdenin içindeki duruma gömer; `import`, `ledger_tip` bağlamını gömülü zincir üzerinden yeniden doğrular. §4 gövde tanımı: "bağlam-grafiği düğümleri + son oturumun durumu **+ gömülü defter**".
  (b) kod düzeyinde reason_code eklemeleri (E-3/E-5 emsalini izleyerek): **14=ledger_broken** (dosya eksik / bozuk uç bağlamı / truncate sonrası import — F21 kapanışı), **17=state_invalid** (`graph_merkle` uyuşmazlığı / Yalnız-ADD ihlali).
  (c) **Sınır-semantiğine dair dürüst not:** `cpu_ms_per_run` sınırı, **duvar-saati** (wall-clock) tabanlı bir süreç zaman aşımıdır (CPU süresi değil). Ağır konak yükü altında (yük ≥ ~40, eşzamanlı rustc derlemeleri) basit bir ajan bile gerekçe 11 (runtime_limit) ile RED olabilir — bu bir **zamanlama** meselesidir, ölçüm (metering) meselesi değil; sınırın anlamı değişmemiştir. Adı, RFC-001 dondurulmuş olduğu için korundu. Kanıt: `.evidence/ (local, untracked)` (yük 41 altında bir gerekçe-11 gözlemi).
- **E-10 (2026-09-05, Denetim-7 / Dilim-9):** gömülü zincirin saldırı yüzeyinin sağlamlaştırılması ve dürüst bir sınır beyanı:
  (a) **Kurulum-öncesi doğrulama (kapatıldı):** `import`, gömülü `ledger_records` zincirinin iç hash-zincirini (`_records_head`), hedef düğüme yazmadan ÖNCE doğrular; bozuk gövde → import RED (gerekçe 14, "embedded chain broken@N"). Bu, E-9a'nın yarım kalan sıfır-güven kısmını kapatır: kurulum artık "bir sonraki doğrulamada yakalanmaya" bırakılmaz. Kanıt: `.evidence/ (local, untracked)` (A1a, düzeltme sonrası koşu).
  (b) **F25 açık bulgu (belgelendi):** bir tohum-sahibi saldırgan, zinciri baştan yeniden hash'leyip taze bir düğümde öz-tutarlı **sahte bir tarihçe** kurabilir (A1b saldırısı import + ledger-verify'den geçer). Mevcut önlemler: D4 yalnız-eklemeli kuralı (zaten zinciri olan bir hedefte `ledger_tip` bağlama RED — A2) + tohum gizliliği. Kalıcı çözüm **düğüm-birlikte-imzalaması (node-cosign)** — düğümün anahtarı kaydın hash girdisine girer → RFC-003 Açık Soru 4'e eklendi. Simnet tek-yazarlı bir ortam olduğundan önem derecesi Orta'dır; bir ağda Yüksek olurdu.
  (c) **Tutarlı-tahrif üst sınırı (belgelendi):** bir tohum-sahibi `graph_merkle`'i yeniden hesaplayıp tutarlı bir durum üretebilir (A3) — merkle için saldırgan modeli, tohumu olmayan bir konaktır; bu sınır gizlenmiş bir açık değil, bir model tanımıdır.
- **E-11 (2026-09-05, Dilim-9 / öğrenim):** ölçüm sınırı yavaş turda da doğrulandı: 16/16 geçen bir koşuda `c30 wall_ms=31022` (AT-001c formülü sapması %0,000022; `.evidence/ (local, untracked)`). Pratik not: yavaş turda c30 koşusu, konak yükü ~22–29 bandında wall-30000 sınırını ancak ~%3 marjla geçer — gerekçe-11 riski ~40 yük bandında yavaş turda da vardır; kanıt koşuları düşük yüklü bir pencerede planlanır (bu tur: ~21 yükte satır-içi bir koşu). Aşım-yükü (overhead) taban çizgisi: `.evidence/ (local, untracked)` (E-4).

## §9 Errata — Devamı

- **E-12 (2026-09-05, Denetim-9 B12/B3/B7):** §3'ün normatif CLI imzaları gerçek yüzeye sabitlendi:
  (i) `export <pkg> -o <snapshot.tsg> --seed <hex>` — `--seed` **zorunludur** (eksikse → RED 6);
  (ii) `import <snapshot.tsg> <pkg>` — ikinci argüman, hedef pkg, **zorunludur** (§3'te unutulmuş);
  (iii) `run` çalıştırma sonunda bir anlık-görüntü **oluşturmaz** — yalnızca state.json + ledger.jsonl'i günceller;
  anlık-görüntü yalnızca `export` üzerinden üretilir (§3'teki "otomatik güncellenir" yorumu düşürüldü).
  (iv) **Yeni RED kodu 18 = `agent_ownership_mismatch` (Denetim-9 B7):** state.json artık
  `agent_id` taşır; çalıştırma anında başka bir ajanın tohumu farklı bir ajana ait bir durum üzerinde çalıştırılamaz ve import'ta
  hedefteki yaşayan ajanın durumu başka bir ajanın anlık-görüntüsüyle ezilemez (taşıma = boş bir düğüme export/import;
  bir sahiplik değişimi belgelenmiş akıştan geçer — kurucu kararı gerektirir). `agent_id` içermeyen eski fikstür
  durumlarında bağlama İLK çalıştırmada kurulur (geriye dönük uyumlu). Kayıt: 18,
  §4 gerekçe tablosuna eklenir; RFC-001 şeması, durumda `agent_id`'yi isteğe bağlı bir alan olarak kazanır (v0.1.1).
  (v) **B5:** io sınırı (`io_mb_per_run`) artık koşu SIRASINDA `RLIMIT_FSIZE` ile
  uygulanır (tamamlandıktan sonra denetlenmez); taşma → süreç SIGXFSZ ile ölür → io gerekçesiyle RED 11 olarak kaydedilir.
  (vi) **B6:** tüm "0600" beyanları atomiktir (os.open O_CREAT|mode; yazma-sonrası chmod yok).
- **E-11 düzeltmesi (Denetim-9 B2):** E-11'in atıf yaptığı aşım-yükü taban çizgisi v1'de YANLIŞTI
  (import 72 ms = bir erkenden-RED artefaktı; fikstür benç koşusundan sonra yakalanmıştı).
  Bağlayıcı taban çizgisi v2'dir: `.evidence/ (local, untracked)` — import (derin doğrulama)
  = 421 ms medyan (en ağır işlem); yol haritası güncellendi (dahili karar günlüğü).

## §9 Errata — E-13 (2026-09-05, kurucu onaylı)

**E-13 — taslak-anı errata düzeltmesi (normatif anlam yeniden ifade edildi):**

1. **Gerekçe 10 = `input_invalid`.** Dondurulmuş metnin E-3'ü gerekçe 10'u
   `memory_limit` olarak listeler — taslak anından kalma bir tutarsızlık. Sevkedilen runner (ve
   ARCHITECTURE.md §7'deki kamuya açık gerekçe-kodu tablosu) gerekçe 10'u
   `input_invalid` için kullanır (taşın büyük/bozuk `--input`); bellek tükenmesi
   `runtime_limit`/gerekçe 11'e eşlenir. Bu düzeltme normatiftir; yukarıdaki E-3 ifadesi
   sözleşme sadakati için korunur ve bu kayıtla geçersiz kılınır (superseded).
2. **Manifest kod özet alanı = `wasm_sha256`.** D5'in düz metni `code.sha256` der;
   normatif alan adı — gerek `specs/manifest-0.1.0.schema.json`'da gerek her
   imzalı manifestte — `package.code.wasm_sha256`'dır. D5'in düz metni şema tarafından
   geçersiz kılınır.

(E-13, çeviri anında eklenen çevirmen notlarıyla önceden duyurulmuştu;
kanonik Türkçe belge aynı düzeltmeyi karar günlüğünde taşır.)

## §9 Errata — E-14 (2026-09-15, taze-kullanıcı denetim matrisi)

**E-14 — çökme ailesi + içi-boş-yeşil (vacuous-green) kapanışı; yeni RED kodu 19 = `pkg_dizin_degil`:**

Tüm-komutlar boş-argüman matrisi (canlı 0.2.6 wheel'ına karşı koşuldu, 2026-09-15),
olumlu-yol testlerinin hiçbirisinin göremediği iki doktrinel kusuru yakaladı:

1. **Traceback ailesi.** `grant`, `run`, `export`, `memory`, `keygen-node`, arity
   denetimi yapmadan `a[0]`/`a[1]` indeksliyordu → sıfır argümanda ham IndexError. Düzeltme: runner'da tek bir
   `usage_guard` dar-boğazı, her iki dağıtım (dispatch) yolu tarafından ortaklaşa paylaşılır (konsol
   `tamga` → `tamga_bootstrap`; depo-scripti `tamga_runner.__main__`); eksik argümanlar
   artık mesaj-RED'idir (rc 1, `"ok": false`, tam kullanım dizgisi) — asla
   traceback değildir (AT-016 kuralı, `explain`'dan tüm CLI yüzeyine genişletildi). Bekçi (guard),
   motor çözümleyicisinden ÖNCE çalışır: bir kullanım hatası asla tek-seferlik wasmtime
   indirmesini tetiklememelidir.
2. **İçi-boş yeşil.** `ledger`/`ledger-verify` sıfır argümanla sessizce `"."` varsaydı ve
   VAR OLMAYAN bir yol `ok=true, head="0×64"` olarak doğrulanıyordu — meşru genesis-öncesi
   durumu (zincirsiz paket; AGENT-GUIDE'daki "boş zincir meşrudur" notu GERÇEK dizinler için
   hâlâ geçerlidir) "bakılamadı" ile birbirine karıştırıyordu.
   epoch-verify INDETERMINE kuralı artık kendi zincir yüzeyimize de uygulanır: bir paket
   yolu dizin değilse RED gerekçe-kodu 19 (`pkg_dizin_degil`). `tamga <cmd>`
   (çıplak) kullanım-rc1 olarak kalır; `import`/`migrate-net` arity hatalarını zaten
   mesajla yanıtlıyordu ve olduğu gibi bırakıldı.

Olumsuz (negative) aile AT-021'e sabitlendi (tek bir toplanmış kontrol; taban çizgisi
48 hızlı / 52 yavaş kalır): 8 komut × sıfır argüman → rc1 + traceback yok + `"ok": true` yok, artı eksik-dizin → 19 vakası. USAGE çıkış-kodu satırı güncellendi (reason_code 1–19).

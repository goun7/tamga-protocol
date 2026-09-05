# RFC-002: Runner API ve Snapshot Taşıma

- **Durum:** **v0.1-FINAL — DONDURULDU (2026-09-02, kurucu onayı).** Değişiklik yeni RFC + sürüm artışı ister.
- **Bağlılık:** WHITEPAPER.md §3 (primitif: taşıma bütünlüğü), §5 (güvenlik modeli: at-rest/in-use ayrımı) · ACCEPTANCE-TESTS.md AT-001b/c/d/e · RFC-001 (manifest, v0.1-FINAL)
- **Kapsam:** v0 (Faz 1). Ağ/keşif yok, gerçek ödeme yok — tüm ödeme `tamga-sim/1` simüle ledger'dır.

## 1. Motivasyon

RFC-001 paketi tanımladı; bu RFC paketi **çalıştıranın** ve **taşıyanın** sözleşmesidir. Primitifin taşıma bütünlüğü deyimi (*"Makine değişimi, ajanın kişiliğini değiştirmez"*) burada gerçeklenir: AT-001b/c/d/e'nin tamamı bu API'ye bağlıdır.

## 2. Kararlar (gerekçeleriyle)

| # | Karar | Gerekçe | Elenen alternatif |
|---|---|---|---|
| D1 | API yüzeyi: **CLI + JSON stdio** (daemon yok, HTTP yok v0'da) | Kanıt kültürü: her işlem tek komut + çıktı dosyası; test edilebilirlik maksimum. Daemon/HTTP v1'in konusu | uzun süreli daemon + REST (v0'da kanıt üretmeyi zorlaştırır) |
| D2 | Snapshot: **tek dosya,`tamga-snapshot/1`** — başlık (header) + şifreli gövde (XChaCha20-Poly1305, RFC-001'de pinli) | Tek dosya = taşınabilirlik; header şifresiz ama *şifreli bölgeyi tanımlar*, ajan verisi içermez (AT-001d kapsamı) | klasör-dizini (dağınık, taşınabilirlik zayıf) |
| D3 | Kimlik anahtarları host diskine **hiç yazılmaz**: koşum süresince RAM keystore; export snapshot'ın içine gömülü şifreli blok olarak taşınır | WHITEPAPER §3 kuralı: sk_A host okuyamaz/yedekleyemez. Gömülü blok, taşıma bütünlüğünün taşıyıcısıdır | seed dosyasını diske yaz (primitif ihlali) |
| D4 | Taşıma: `export → import` iki ayrı komut; import, imza+hash doğrulamasını RFC-001 doğrulayıcısıyla **yeniden** yapar | Güven sınırı net: import eden node, gelen paketi kendi gözüyle doğrular (zero-trust taşima) | tek "migrate" komutu (doğrulama zinciri bulanıklaşır) |
| D5 | Muhasebe: `ledger.jsonl` — append-only, satır başına tek JSON kayıt, RFC-003 şeması | Kanıt kültürüyle birebir: log satırı = kanıt satırı | SQLite (v0'da gereksiz ağırlık; v1'de yeniden değerlendirilir) |

## 3. CLI Sözleşmesi (normatif)

```
tamga-runner keygen <dir>                     # RAM'de üret, snapshot'a gömülecek (D3: disk yazımı yok)
tamga-runner run <pkg> --seed <hex>           # koşum; işlem sonunda snapshot otomatik güncellenir
tamga-runner export <pkg> -o <snapshot.tsg>   # durum + gömülü keystore → tek dosya
tamga-runner import <snapshot.tsg>            # RFC-001 doğrulaması → keystore geri yükleme → READY
tamga-runner ledger [pkg]                     # ledger.jsonl özeti (stdout: JSON)
```

Kural: her komut **stdout'a tek satır JSON** yazar: `{"ok":true,"op":"import","pkg":"tamga-ornek-ajani",...}` veya `{"ok":false,"reason_code":"..."}`. `reason_code` değerleri §6'da numaralıdır — bu, AT loglarındaki sebep kodlarıyla birebir eşleşir.

## 4. Snapshot Biçimi — `tamga-snapshot/1`

```
[magic: "TSG1"][u32 header_len][header JSON][XChaCha20-Poly1305 gövde]
```

**Header (şifresiz, kişisel veri içermez — AT-001d denetimine tabi):**

```json
{
  "format": "tamga-snapshot/1",
  "pkg_name": "tamga-ornek-ajani",
  "pkg_wasm_sha256": "<RFC-001 code hash>",
  "agent_id": "<pk_A hex>",
  "cipher": "XChaCha20-Poly1305",
  "keystore_blob": "<gömülü, PKDF ile türetilmiş anahtarla şifreli sk_A bloğu>",
  "body_nonce": "<hex>",
  "created": "<ISO-8601>"
}
```

**Gövde (şifreli):** bağlam grafiği düğümleri + son oturum durumu. Header'da `pkg_name`/`agent_id` dışında serbest metin **yasaktır** — AT-001d grep denetimi bu kuralı kontrol eder.

## 5. İşlem Sıraları

**Taşıma (AT-001b):**
1. node-A: `run` (durum oluşur) → `export` → `snapshot.tsg`
2. dosya node-B'ye taşınır (kanal kapsamı dışı)
3. node-B: `import` → RFC-001 doğrulaması + header bütünlük + keystore açma → READY
4. node-B: `run` → ajan **aynı agent_id** ile devam eder (AT-001e)

**Ödeme (AT-001c):** her `run` sonunda süreç ölçümü (CPU ms, max RSS, IO) → formülle ücret → `ledger.jsonl` satırı: `{"op":"charge","pkg":...,"cpu_ms":...,"ram_mb_s":...,"io_mb":...,"fee_sim":...}`. Simüle bakiye `ledger.jsonl` içindeki `grant` kayıtlarıyla dengeye oturur.

## 6. reason_code Kaydı (numaralı)

| # | Kod | Anlam |
|---|---|---|
| 1 | snapshot_bad_magic | TSG1 başlığı yok |
| 2 | snapshot_header_invalid | header JSON/şema ihlali |
| 3 | manifest_reject | RFC-001 doğrulayıcısı RED (alt kodla) |
| 4 | keystore_unlock_failed | gömülü keystore açılamadı |
| 5 | proof_level_unavailable | node, min_proof_level'ı sunamıyor (v0: her zaman P0 sunulur) |

## 7. Açık Sorular (bilinçli ertelenmiş)

1. keystore PKDF parametreleri (Argon2id önerilir) → RFC-004 ile birlikte pinlenir.
2. Snapshot diff/Artımlı (incremental) taşıma → v0 tek-dosya tam snapshot; ölçüm sonrası karar.
3. `run` uzun ömürlü (long-lived) ajanlar için checkpoint politikası → AT-001 koşum ölçümünden sonra.
4. Ledger'ın node-özel denge kontrolü → RFC-003.
5. Seed'in çalışma-zamanı aktarımı (stdin/env/daemon) — v1 daemon tasarımıyla (Errata E-2).

## 8. Onay Kütüğü

- [x] Kurucu onayı: **2026-09-02** — bu RFC donduruldu, Durum: **v0.1-FINAL**. Gerçekleme: `tamga_runner.py` (Faz 1 Dilim-1).

## 9. Errata

- **E-1 (2026-09-02, dondurma anı):** §3'teki `keygen <dir>` imzası yanıltıcıdır: D3 gereği keygen **diske hiçbir şey yazmaz**; seed yalnız stdout'a (tek satır JSON) basılır ve kullanıcı güvenli ortamda saklar. `<dir>` parametresi kabul edilir ama yok sayılır.
- **E-2 (2026-09-02):** `run --seed <hex>` komut satırı argümanı `/proc` üzerinden okunabilir (simnet'te kabul edilmiş sınırdır); seed'in çalışma-zamanı aktarımı (stdin/env/daemon) v1 daemon tasarımına ertelendi — §7'ye madde 5 olarak işlenmiştir.
- **E-3 (2026-09-02, Audit-1):** §6'daki reason_code kaydı kod-seviyesinde genişletildi: 6=seed_invalid, 7=snapshot_too_large, 8=snapshot_replay_rollback, 9=agent_identity_mismatch, 10=memory_limit. Neden: güvenlik denetimi bulguları (SECURITY-AUDIT.md Audit-1/2) numaralı reddetme modelini gerektirdi; §6 tablosu bir sonraki RFC sürümünde resmileşir.
- **E-4 (2026-09-02, Audit-2):** §4'teki `pkg_name` alanının kaynağı normatif değildi ve gerçeklemede iki sahip doğdu (dizin adı vs RFC-001 `package.name`). Norm: **`pkg_name` = RFC-001 `package.name` (kanonik sahip)**. Export bunu manifest'ten okur; import zaten bunu doğruluyordu (Audit-1 F8 kapısı). Kanıt: kanit/FAZ1/2026-09-02/dilim-2.log.
- **E-5 (2026-09-02, Dilim-3):** Koşum motoru pinlendi: **wasmtime v48.0.1** (GitHub release digest `sha256:4c2e31b6…` ile doğrulanmış ikili, `tools/bin/`). §3 `run` semantiği: ajan **süreç-izole** çalışır; D4 default-deny gerçeklemesi = wasmtime'a fs preopen verilmez, ağ (`-S allow-ip`) verilmez, saat/rastgelelik WASI 0.3 default'undan gelir. reason_code uzantıları: 11=runtime_limit, 12=agent_run_failed, 13=not_component. Oturum kanıtı: `run`, stdout'u `pkg/session-N.stdout` (0600) dosyasına yazar ve sha256'sını döner.
- **E-6 (2026-09-02, Dilim-4):** Ölçüm sözleşmesi yükseltildi: charge kaydı artık `cpu_saat / ram_gb_sn / io_mb / wall_ms` taşır. cpu ve ram, child wasmtime sürecinden **gerçek ölçümdür** (`RUSAGE_CHILDREN` delta + maxrss — dürüst not: maxrss çocuklar arası MAX, cpu<wall wasmtime saat-okuma yield'lerinden); wall_ms ayrıdır. Faturalama tabanı (wall vs cpu) **RFC-003 kararıdır** — AT-001c kanıtı: kanit/AT-001/2026-09-02/AT-001c.log.
- **E-9 (2026-09-05, Dilim-7/8):** Snapshot ↔ ledger bağlamı ve reason_code uzantıları:
  (a) **F24 kapanışı — ledger snapshot'la seyahat eder:** `export`, zincirin tamamını (`ledger_records`) şifreli gövdedeki state'e gömer; `import` gömülü zincir üzerinde `ledger_tip` bağlamını yeniden doğrular. §4 gövde tanımı: "bağlam grafiği düğümleri + son oturum durumu **+ gömülü ledger**".
  (b) reason_code kod-seviyesi uzantıları (E-3/E-5 emsaliyle): **14=ledger_broken** (dosya yok / tip bağlamı kopuk / truncate-sonrası import — F21 kapanışı), **17=state_invalid** (`graph_merkle` uyuşmazlığı / ADD-only ihlali).
  (c) **Limit-semantiği dürüst notu:** `cpu_ms_per_run` sınırı **wall-clock** süreç timeout'udur (ad CPU değil). Ağır host yükü altında (load ≥ ~40, paralel rustc derlemeleri) önemsiz bir ajan bile reason 11 (runtime_limit) ile RED olabilir — ölçüm değil **zamanlama** konusudur, sınır anlamı bozulmaz. Ad RFC-001 donmuş olduğu için isim korunmuştur. Kanıt: kanit/REGRESYON/2026-09-05 (yük-41 altında reason-11 gözlemi).
- **E-10 (2026-09-05, Audit-7 / Dilim-9):** Gömülü zincir saldırı yüzeyi sertleştirmesi ve dürüst sınır kaydı:
  (a) **Kuruluş-öncesi doğrulama (kapandı):** `import`, gömülü `ledger_records` zincirini hedef node'a yazmadan ÖNCE içsel hash-zincirini doğrular (`_records_head`); bozuk gövde → import RED (reason 14, "gömülü zincir kırık@N"). E-9a'nın yarım kalan zero-trust kapanışı: kuruluş artık "sonraki verify'da yakalanma"ya bırakılmıyor. Kanıt: kanit/GUVENLIK/2026-09-05/audit-7.log (A1a, düzeltme sonrası koşum).
  (b) **F25 açık bulgu (belgeli):** seed-sahibi düşman, zinciri baştan yeniden hash'leyerek taze node'a kendi-tutarlı **sahte tarih** kurabiliyor (A1b saldırısı import + ledger-verify geçiyor). Mevcut panzehirler: D4 append-only (zincirli hedefte `ledger_tip` bağlaması RED — A2) + seed gizliliği. Kalıcı çözüm **node-cosign**'dir (kaydın hash girdisine node anahtarı girer) → RFC-003 Açık Soru 4'e eklendi. Simnet'te tek-yazar ortam olduğu için şiddet Orta; ağda Yüksek.
  (c) **Tutarlı-kurcalama üst sınırı (belgelendi):** seed-sahibi, `graph_merkle`'ı yeniden hesaplayıp tutarlı state üretebilir (A3) — merkle'in düşman modeli seed'siz host'tur; bu sınır açık-değil, model-tanımlamasıdır.
- **E-11 (2026-09-05, Dilim-9/öğrenme):** Ölçüm-limiti yavaş turda da teyit edildi: 16/16 geçen koşumda `c30 wall_ms=31022` (AT-001c formül sapması %0.000022; kanit/REGRESYON/2026-09-05/run_all-040841.log). Pratik not: yavaş tur c30 koşumu wall-30000 sınırını host load ~22-29 bandında ancak ~%3 marjla geçer — yük ~40 bandında reason-11 riski yavaş turda da vardır; kanıt-koşumları düşük-yük penceresiyle planlanır (bu tur: inline koşum load ~21'de). Overhead taban çizgisi: kanit/BENCH/2026-09-05/runner-overhead.json (E-4).

## §9 Errata — Devam

- **E-12 (2026-09-05, Audit-9 B12/B3/B7):** §3 normatif CLI imzaları gerçek yüzeye sabitlenir:
  (i) `export <pkg> -o <snapshot.tsg> --seed <hex>` — `--seed` **zorunludur** (eksikse RED 6);
  (ii) `import <snapshot.tsg> <pkg>` — ikinci argüman hedef pkg **zorunludur** (§3'te unutulmuştu);
  (iii) `run` koşum sonunda **snapshot OLUŞTURMAZ** — yalnız state.json + ledger.jsonl günceller;
  snapshot yalnız `export` ile üretilir (§3'teki "otomatik güncellenir" yorumu düşer).
  (iv) **Yeni RED kodu 18 = `agent_ownership_mismatch` (Audit-9 B7):** state.json artık
  `agent_id` taşır; run'da başka ajanın seed'i sahipli state'e koşamaz, import'ta hedefteki
  yaşayan ajanın state'i başka ajanın snapshot'ıyla ezilemez (taşıma = boş node'a export/import;
  sahip-değişimi belgeli akışla — kurucu kararı gerektirir). Eski fixture state'lerinde
  `agent_id` yoksa bağlama İLK koşumda kurulur (geriye-uyum). Kayıt: §4 reason tablosuna 18
  eklenir; RFC-001 şeması state'e `agent_id` opsiyonel alanı olarak eklenir (v0.1.1).
  (v) **B5:** io sınırı (`io_mb_per_run`) artık koşum SIRASINDA `RLIMIT_FSIZE` ile uygulanır
  (bitti-sonra kontrol değil); aşım → süreç SIGXFSZ ile ölür → RED 11 io gerekçesiyle kayıtlı.
  (vi) **B6:** tüm "0600" iddiaları atomiktir (os.open O_CREAT|mode; yazma-sonrası chmod yok).
- **E-11 düzeltme (Audit-9 B2):** E-11'in referans verdiği overhead taban çizgisi v1'de
  HATALIYDI (import 72ms = erken-RED artefaktı; fixture bench'ten sonra kuruluyordu).
  Bağlayıcı taban v2: kanit/BENCH/2026-09-05/runner-overhead.json — import(derin-doğrulama)
  = 421ms medyan (en ağır op); ROADMAP.md güncel.

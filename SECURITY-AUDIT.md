# Tamga Protocol — Güvenlik Denetimi (canlı doküman)

> Metot: statik inceleme (kendi kodum) + canlı negatif testler (kanıt logları). Sınırlar: dış bağımsız denetim henüz yok (Faz 2 planı); kripto primitifleri PyNaCl/libsodium üstünde, kendi kriptomuz sıfır.

## Audit-1 — 2026-09-02 (Faz 1 Dilim-1 öncesi/sonrası kod: tamga_validator.py, tamga_runner.py)

| # | Bulgu | Şiddet | Durum |
|---|---|---|---|
| F1 | import: snapshot boyut sınırı yok → 10GB dosya RAM'e alınır (DoS) | Orta | **DÜZELTİLDİ** (64MB cap, okuma ÖNCE kontrol) |
| F2 | import: bozuk header'da KeyError/TypeError yakalanmıyor → traceback (temiz RED yerine) | Orta | **DÜZELTİLDİ** (reason 2) |
| F3 | run: bozuk --seed hex → yakalanmayan istisna | Düşük | **DÜZELTİLDİ** (reason_code 6) |
| F4 | ledger.jsonl 0644 doğar → ücret kayıtları world-readable | Düşük | **DÜZELTİLDİ** (0600) |
| F5 | validator keygen seed.hex 0644 doğar | Düşük | **DÜZELTİLDİ** (0600) |
| F6 | Snapshot rollback/replay: eski snapshot yeniden import edilebilir (durum geri sarılır) | Orta | **DÜZELTİLDİ** (sessions monotonluk guard'ı, reason_code 8) |
| F7 | Boş parola → kdf(b"") zayıf türetme | Orta | **DÜZELTİLDİ** (fail-fast, reason 4) |
| F8 | import: header agent_id ↔ açılan seed ve pkg_name eşleşmesi doğrulanmıyordu | Orta | **DÜZELTİLDİ** |
| F9 | In-use bellek host'a açık; --seed argv'de; parola entropisi kullanıcıya bağlı | Bilinçli-açık | KABUL (WHITEPAPER §5 + E-2; RFC-004 kapanış şartı) |
| F10 | cpu_ms ölçümü süreç-kümülatif modulo — metrik kırılgan (ücret atlatma riski düşük, CLI başına yeni süreç) | Düşük | KABUL-AÇIK (Dilim-3: WASM seviyesi sayaçlar) |
| F11 | agent.wasm/tamga.json boyut sınırı yok (DoS) | Orta | **DÜZELTİLDİ** (64MB / 256KB cap) |

## Audit-2 — 2026-09-02 (Dilim-2: bağlam grafiği)

Kanıt: kanit/FAZ1/2026-09-02/dilim-2.log + kanit/GUVENLIK/2026-09-02/audit-2-regresyon.log

| # | Bulgu | Şiddet | Durum |
|---|---|---|---|
| F12 | `--note` boyut sınırı yok → snapshot şişirme DoS | Orta | **DÜZELTİLDİ** (64KB cap, reason 10; negatif test kanıtlı) |
| F13 | Düğüm sayısı sınırı yok | Düşük | **DÜZELTİLDİ** (10000 cap, reason 10; F12 ile aynı kod yolu — 10k stres testi yapılmadı, inceleme-düzeyi) |
| F14 | state format geçişi (tamga-state/0→/1) veri kaybı riski | Düşük | **DOĞRULANDI** (migration yolu koşuda kanıtlı: 2 eski probe → 2 düğüm) |
| E-4 | **spec boşluğu:** §4 pkg_name kaynağı normatif değildi → export dizin adı, import manifest adı kullanıyordu (çift sahip). F8 kapısı ilk temasta yakaladı | Orta | **DÜZELTİLDİ** (kanonik sahip = RFC-001 package.name; RFC-002 Errata E-4) |
| F5b | Düzeltme öncesi üretilmiş anahtar dosyaları 0644 kalıntısı | Düşük | **KAPATILDI** (chmod 600 + stat kanıtı) |
| — | F6 rollback guard'ı artık özel negatif testle kanıtlı (sessions 3 > 2 → reason 8) | — | KANIT ✔ |
| — | AT-001d ön-grep gerçek hafıza içeriğiyle yeniden doğrulandı (0 düz metin eşleşme) | — | KANIT ✔ |
| — | AT-001a regresyonu: 6/6 bozulmadan | — | KANIT ✔ |

**Audit-2 notu:** F8 kapısının ilk gerçek yakalaması, denetim-döngüsünün çalıştığının bağımsız kanıtıdır: kapı eklenirken bilinen bir hata yoktu; kapı, export sahibindeki gizli tutarsızlığı surfaced etti.

## Audit-3 — 2026-09-02 (Dilim-3: gerçek WASI 0.3 koşumu)

Kanıt: kanit/FAZ1/2026-09-02/dilim-3.log + dilim-3-wasmtime-kurulum.log + kanit/GUVENLIK/2026-09-02/audit-3-regresyon.log

| # | Bulgu | Şiddet | Durum |
|---|---|---|---|
| F10 | cpu_ms ölçümü süreç-kümülatif modulo idi | Orta | **KAPANDI (Dilim-4 güçlendirildi)** — child sürecin gerçek CPU/RAM ölçümü (`RUSAGE_CHILDREN` delta/maxrss) + wall_ms ayrı kaydedilir; cpu<wall wasmtime yield gerçeği E-6'ya dürüst notla işlendi |
| F15 | subprocess capture_output stdout'u sınırsız belleğe alır; io_mb kontrolü okuma SONRASI → çok büyük çıktı OOM riski | Orta | **KAPANDI (Dilim-4)** — stdout artık diske yönlendirilir (pkg/session-N.stdout), io sınırı dosya boyutundan, timeout'ta unlink; kanıt: AT-001c.log |
| F16 | subprocess'a host env'in tamamı geçiyordu (motor sürecine sızıntı) | Düşük | **KAPANDI** (env={}; kanıt: audit-3-regresyon koşusu) |
| F17 | RFC-001 target const `wasi-0.3/component`; mevcut derleme wasm32-wasip2 (0.2.x world) — 0.3.0 world'e geçiş bekliyor | Bilgi | **AÇIK-DÜRÜST** — wasmtime 48 component-model çalıştırır; 0.3.0 world geçişi Dilim-4 konusu; konst ileri-pin olarak duruyor |
| — | **Tedarik zinciri:** wasmtime v48.0.1 ikilisi GitHub API asset digest ile doğrulandı (`sha256:4c2e31b6…`); sürümün SHA256SUMS asset'i yayınlanmıyor — dürüst not log'da | — | KANIT ✔ |
| — | **D4 default-deny gerçeklemesi:** wasmtime'a fs preopen verilmez, `-S allow-ip` verilmez → ajan engine düzeyinde fs/ağ erişemez; manifest capabilities (clock/random) WASI default'uyla uyumlu | — | KANIT ✔ |
| — | **Determinizm kanıtı:** aynı ajan, 3 oturum, aynı stdout sha256 (`c06fc1df…`) | — | KANIT ✔ |
| — | reason 13 (not_component) negatif testi: placeholder wasm'lı geçerli paket RED | — | KANIT ✔ |
| — | AT-001a regresyonu 6/6 bozulmadı; oturum kanıt dosyaları 0600 | — | KANIT ✔ |

## Audit-4 — 2026-09-02 (Dilim-5: ledger hash-zinciri)

Kanıt: kanit/FAZ1/2026-09-02/dilim-5.log

| # | Bulgu | Şiddet | Durum |
|---|---|---|---|
| F18 | `grant` tutar doğrulaması yoktu (negatif/sıfır/absürt tutar) | Orta | **KAPANDI** (0 < amount ≤ 1e6; negatif test kanıtlı) |
| F19 | `ledger-verify` tam-dosya yüklemesi DoS riski | Düşük | **KAPANDI** (streaming okuma, tasarımda) |
| F20 | Hash girdisi utf-8 JCS — platform bağımlılığı kontrolü | Bilgi | Sorun yok (Python json deterministik; `ensure_ascii=False` iki tarafta aynı) |
| F21 | **Truncate saldırısı:** son N satır silinirse zincir yine "doğru" görünür (head geri kayar) | Orta | **AÇIK (bilinçli)** — panzehir: RFC-004 D6 `ledger_tip` (snapshot gövdesinde son-hash çapraz-bağı) + RFC-003 §5-2; simnet'te tek-yazar olduğundan risk kabul |
| — | Kurcalama testi: satır-1 amount değişimi → `broken_at: 1` RED | — | KANIT ✔ |
| — | AT-001a regresyonu 6/6 | — | KANIT ✔ |

## Audit-5 — 2026-09-03 (Dilim-6: state v1 — graph_merkle + ledger_tip)

Kanıt: kanit/FAZ1/2026-09-02/dilim-6.log (v3 blokları; önceki iki hatalı koşu — /tmp kaybı ve şablon kaçışı SyntaxError — dürüstlük gereği log'da bırakıldı)

| # | Bulgu | Şiddet | Durum |
|---|---|---|---|
| F21 | Truncate saldırısı (Audit-4'ten açık) — son N satır silınırsa zincir "doğru" görünürdü | Orta | **KAPANDI** — panzehir kanıtlı: state'e gömülü `ledger_tip`, truncate sonrası import → `reason 14 ledger_tip yerel zincirde yok` RED (dilim-6.log F21 v3) |
| F22 | `memory --import-json` id'siz dış düğümlerde dedup yoktu — aynı MERGEN dersi her import'ta çoğalıyordu | Orta | **KAPANDI** — içerik-parmakizi (`kind,text,valid_from,valid_to,supersedes` hash'i); ikinci import `added:0 skipped:5` kanıtlı |
| F23 | Taze node'da yerel ledger yoksa `ledger_tip` kontrolü erteleniyor (import ACCEPT, kontrol yeni zincir kurulunca anlamlı) | Düşük | **AÇIK (bilinçli, kabul)** — v1 panzehiri: snapshot header'a son-N hash penceresi gömülmesi (RFC-003 §5-2); simnet'te tek-yazar risk kabul |
| — | Merkle kurcalama: state'te not değiştirildi → import → `reason 17 graph_merkle uyuşmuyor` RED | — | KANIT ✔ |
| — | `supersedes` olmayan hedef → `reason 17` RED | — | KANIT ✔ |
| — | AT-001a regresyonu 6/6 (dilim-6 sonrası) | — | KANIT ✔ |

## Audit-6 — 2026-09-03 (Dilim-7/8: çoklu-ajan simnet + göçte zincir)

Kanıt: kanit/FAZ1/2026-09-02/dilim-7.log (errata dahil)

| # | Bulgu | Şiddet | Durum |
|---|---|---|---|
| F24 | Göçte ledger seyahat etmiyordu — node-D import ACCEPT ama zincir hedefte yoktu (`ledger_broken: dosya yok`) | **Yüksek** | **KAPANDI (Dilim-8)** — snapshot gövdesine `ledger_records` gömüldü; taze node-E'ye göçte zincir kuruldu: `ledger-verify lines:5 ok` + bakiye seyahat kanıtlı |
| — | Çapraz-import kilidi doğrulandı: C'nin snapshot'ı K'ye → `reason 14 ledger_tip yerel zincirde yok` (tahminden güçlü: pkg dizisi zincire bağlanıyor) | — | KANIT ✔ |
| — | Kimlik tutarlılığı 4 koşum: agent_id sabit (`02f77b55…`) | — | KANIT ✔ |
| — | AT-001a regresyonu 6/6 (dilim-7/8 sonrası) | — | KANIT ✔ |
| — | Dürüstlük notu: dilim-7'de "reason 9 beklenir" tahmini yanlış çıktı (reason 14 ile reddedildi) — errata log'da | — | ŞEFFAFLIK ✔ |

## Audit-7 — 2026-09-05 (Dilim-9: gömülü-zincir saldırı yüzeyi, otonom tur)

Kapsam: Dilim-8'in yeni yüzeyi (snapshot gövdesindeki `ledger_records` + tip bağlama)
adversary-simülasyonu ile prolandı. Yöntem: `tests/audit7_embedded_chain.py` —
runner'ın kendi kripto primitifleriyle (simnet parolası + seed) gövde çözülür,
mutate edilir, yeniden şifrelenir. Dürüst sınır: bu "seed'i bilen güçlü düşman"dır;
seed'siz host düşmanı üst sınır ölçümünden zayıftır. Kanıt: kanit/GUVENLIK/2026-09-05/audit-7.log.

| # | Bulgu | Şiddet | Durum |
|---|---|---|---|
| F25 | **Güçlü düşman (seed-sahibi) taze node'a kendi-tutarlı sahte tarih kurabiliyor:** zinciri baştan yeniden hash'leyip (A1b) gömülü `ledger_records`'ı değiştirmek import + ledger-verify'ı geçiyor. Mevcut panzehirler: D4 append-only (zincirli hedefte `ledger_tip` bağlaması RED — A2 kanıtlı) + seed'in gizliliği (düşmanın seed'i olmalı). Kalıcı çözüm: **node-cosign** (her kaydın hash'ine node'un imzası girer) → RFC-003 kapsamı | **Orta** (simnet'te düşük; ağda Yüksek) | **AÇIK (belgeli)** — v1 kapsamı: RFC-003 node-cosign maddesi; provenance kuralı: gömülü zincir tek-y Origins=node-A, çapraz doğrulama v1 |
| — | A1a zayıf splice (hash eski kalır): import, zinciri KURMADAN ÖNCE içsel bütünlüğü doğrulamıyordu; bozuk zincir hedefe yazılıyor, yakalama sonraki ledger-verify'a sarkıyordu — D4 zero-trust'a aykırı | — | **KAPANDI (Audit-7, aynı gün)** — `_records_head()` ile gömülü zincir kuruluş-öncesi doğrulanıyor; bozuk gövde → import RED (reason 14, "gömülü zincir kırık@N"). Kanıt: A1a import ok=False reason=14 |
| — | A2 tip-swap (uydurma `ledger_tip`): zincirli hedefte RED (reason 14) — tip bağlaması saldırıya dayanıklı; taze hedefte erteleme (F23'ün kapsamı) | — | KANIT ✔ (mevcut mekanizma teyit edildi) |
| — | A3 merkle-fold (seed-sahibi tutarlı state üretimi): import ACCEPT — beklenen üst-sınır; merkle'in amacı seed'siz host kurcalaması (F24 öncesi dilim-6 kanıtı) | — | BELGELENDİ (sınır, açık değil) |

**Düzeltme kodu (aynı gün, kanıtlı):** `tamga_runner.py::_records_head()` + import
kuruluş-öncesi doğrulama — pozitif akış (grant→export→import→verify) ve AT-001f
vektörleri (4/4) bozulmadığı ayrıca koşularla teyit edildi (bkz. audit-7.log son bloğu).

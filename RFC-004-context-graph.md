# RFC-004: Bağlam Grafiği ve Şifreli Snapshot Sözleşmesi (tamga-snapshot/1 v1)

- **Durum:** TASLAK v0.1 — kurucu onayı bekliyor. Onaylanınca **donar**.
- **Bağlılık:** RFC-001 §9-1 (açık soru: seed/context-graph şeması), RFC-002 §4 (snapshot biçimi), MERGEN-ENTEGRASYON-NOTU.md L1, ROADMAP Faz 1 (2. dilim kanıtı: dilim-2.log)
- **Kapsam:** v0 (Faz 1). Snapshot taşıma biçimi değişmez; gövdedeki **bağlam grafiği şeması** pinlenir.

## 1. Motivasyon

RFC-001 §9-1: "Bağlam grafiği şeması — dilim-2'de pinlenecek" (açık soru). Dilim-2/3/4 kanıtları şemanın çalışan
halini gösterdi; bu RFC onu normatif yapar ve MERGEN derslerini (L1) içine işler. Argon2id keystore parametreleri de
burada pinlenir (RFC-002 §7-1 açık sorusu).

## 2. Kararlar (gerekçeleriyle)

| # | Karar | Gerekçe | Elenen alternatif |
|---|---|---|---|
| D1 | **Düğüm şeması:** `{id, kind, text, ts, valid_from?, valid_to?, supersedes?}` | MERGEN G13 dersi (bi-temporal); "bu bilgi o tarihte geçerli miydi?" sorusu ileride sorulabilir | düz not listesi |
| D2 | **ADD-only:** düğüm asla silinmez/değişmez; düzeltme yeni düğüm + `supersedes: <id>` | MERGEN G17 (memory_revisions); kanıt kültürüyle birebir | overwrite |
| D3 | **Kenar şeması:** `[from_id, to_id, kind, ts?]`; kind: ref/derived/contradicts | Dilim-2 gerçeklemesi normatifleşir; `contradicts` MERGEN'in hakemlik-bekleyen çelişki-taraması için hazır | only-ref |
| D4 | **Arama:** v0 substring (`memory --search`) sabit kalır; FTS+grafik-sinyal hibriti **v1 spec konusu** | dilim-2/3 kanıtı substring ile yeterli; ek bağımlılık v0'da yasak (sıfır-dep ilkesi) | şimdi FTS5 |
| D5 | **Keystore KDF = Argon2id** (m=64MiB, t=3, p=4) — PyNaCl yoksa scrypt fallback (n=2^15, r=8, p=1, maxmem=64MiB) ve kayıt `kdf` alanıyla beyan edilir | RFC-002 §7-1 pinlemesi; OpenSSL scrypt bellek sınırı gerçeği dilim-1'den biliniyor | scrypt-only |
| D6 | **state format v1:** `{"format": "tamga-state/1", "sessions", "memory": {next_id, nodes[], edges[]}, "ledger_tip": "<64hex>", "graph_merkle": "<64hex>"}` | Dilim-2 migration'ı (F14) normatifleşir; `graph_merkle` = düğüm+kenarların sıralı hash'i (tamper-evident hafıza); `ledger_tip` = snapshot ile ledger'ı çapraz-bağlar | mevcut düz state |
| D7 | `memory --export-json` / `--import-json`: dış sistemler (ilk sıra: **MERGEN**) dersleri Tamga düğümlerine getirir/getirir | MERGEN-ENTEGRASYON-NOTU L2 adaptörünün taşıyıcısı; yönde yine tek yön: dış → tamga | direkt DB erişimi (yasak) |

## 3. Düğüm türleri (v0)

`note` (serbest metin), `fact` (iddia — L2 adaptöründe MERGEN dersleri bu türle gelir), `session_marker` (oturum başlangıç işareti, `run` otomatik yazar). v1 adayları: `goal`, `tool_result`.

## 4. reason_code uzantısı (E-8)

16=node_limit (nodes >= 10000 — mevcut), 17=state_invalid (state.json şema ihlali — import'ta derin doğrulama; gerçeklemede `graph_merkle` uyuşmazlığı bu kodla RED olur).

İlgili reason_code'lar (normatif kayıt RFC-002 §9'dadır): 7=snapshot_too_large (SAFE_SNAP_MAX 64MiB), 8=snapshot_replay_rollback (hedef `sessions` sayacı snapshot'tan ileriyse import RED — hafıza sürekliliği savunması), 9=agent_identity_mismatch (header kimliği keystore'dan türeyen pubkey ile uyuşmaz). Negatif-vektör kanıtı: kanit/AT-001/2026-09-05/AT-001f-vektorler.log.

## 5. Açık Sorular

1. `contradicts` kenarlarının otomatik tespiti (MERGEN contradiction_scan dersi) → v1.
2. `graph_merkle`'ün ajan tarafından doğrulanması (kendi hafızasının bütünlüğünü kendisi kanıtlar) → Faz 2.
3. L2 adaptörünün alan eşlemesi (MERGEN ders ↔ `fact` düğümü) → adaptör gerçekleme RFC'si (Faz 2 ilk iş).

## 6. Onay Kütüğü

- [ ] Kurucu onayı (tarih) — onay anında bu RFC donar, Durum: v0.1-FINAL olur.

## 7. Gerçekleme Uyumu Notu (2026-09-05, Dilim-9 — dondurma değildir)

| RFC-004 hükmü | Gerçekleme | Not |
|---|---|---|
| D5 Keystore KDF = Argon2id (öncelik), scrypt fallback (n=2^15, r=8, p=1) | **Gönderilen = scrypt (n=2^15, r=8, p=1)**, `kdf` alanı beyanlı | **dürüst not:** PyNaCl Argon2id içermez; D5'in fallback parametreleri v0'ın gerçeklemesidir. Argon2id v1 yükseltmesi olarak kalır (`kdf` beyanı sayesinde geçiş uyumlu). Kanıt: dilim-1/dilim-2 logları |
| D6 state v1 (`format`, `sessions`, `memory`, `ledger_tip`, `graph_merkle`) | birebir (F14 göç dahil) | kanıt: dilim-6.log |
| §3 düğüm türleri note/fact/session_marker | birebir; MERGEN dersleri `fact` olarak akıyor (`memory --import-json`) | kanıt: dilim-4.log + audit-7.log önkoşul |
| §4 E-8 kodları 16/17 | birebir | ayrıca yukarıdaki 7/8/9 bağlam notu |
| — (RFC'de yok) | snapshot gövdesi gömülü `ledger_records` taşır | normatif kaynak: RFC-002 E-9a |

Model sınırı (Audit-7 A3): seed-sahibi `graph_merkle`'ı yeniden hesaplayıp tutarlı state üretebilir; merkle'in düşman modeli **seed'siz host** kurcalamasıdır — tasarımdaki yerini belgeler, açık bulgu değildir.

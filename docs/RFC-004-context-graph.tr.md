# RFC-004: Bağlam Grafiği (Context Graph) ve Şifreli Anlık-Görüntü Sözleşmesi (tamga-snapshot/1 v1)

> Çeviri notu: İngilizce-orijinali (docs/RFC-004-context-graph.md) ile ikizdir; normatif-metin İngilizce'dir — çelişki-olursa ORİJİNAL-BAĞLAYICIDIR.

> **Dil durum notu (dürüstlük düzeltmesi, 2026-09-16):** bu İngilizce metin, belgenin YAŞAYAN ve BAĞLAYICI sürümüdür. Repodaki Türkçe ikizi (`.tr.md`) bir çeviridir — sapma olması hâlinde İngilizce esas alınır. (Nihai-öncesi taslaklar Türkçe olarak özel dolaşımda yayılmıştı; bu metin burada hiç yayımlanmadığı için kasıtlı olarak kanonik diye anılmaz: doğrulanamayan kanonik, kanonik değildir.)

*Çevirmenin notu: alan adları, durum-formatı anahtarları ve örnek değerler, nihai-öncesi Türkçe taslaktan birebir aktarılmıştır. Kanıt-günlüğü atıfları, yerel ve izlenmeyen `.evidence/` koşu-günlüğü dizinine yöneliktir; dahili belgeler tanımlayıcı biçimde anılır (dahili karar günlüğü). "Önceleyen prototip" (predecessor prototype), Tamga'dan önceki dahili bir sistemi karşılar; onun dersleri (G13, G17, L1, L2, çelişki taraması) dahili belgelerde (karar günlüğü) kayıtlıdır.*

- **Durum:** **v0.1-FINAL — DONDURULDU (2026-09-05, kurucu onaylı).** Bir değişiklik, yeni bir RFC + sürüm artışı gerektirir.
- **Bağımlılıklar:** RFC-001 §9-1 (açık soru: tohum/bağlam-grafiği şeması), RFC-002 §4 (anlık-görüntü formatı), önceleyen-prototip entegrasyon notları L1, yol haritası Faz 1 (Dilim-2 kanıtı: `.evidence/ (local, untracked)`) — atıf yapılan belgeler dahili (karar günlüğü).
- **Kapsam:** v0 (Faz 1). Anlık-görüntü taşıma formatı değişmemiştir; gövdedeki **bağlam-grafiği şeması** burada sabitlenir.

## 1. Motivasyon

RFC-001 §9-1: "bağlam-grafiği şeması — Dilim-2'de sabitlenecek" (bir açık soru). Dilim-2/3/4 kanıtı
şemayı çalışan biçimiyle gösterdi; bu RFC onu normatif hâle getiriyor ve önceleyen-prototip derslerini (L1)
içine işliyor. Argon2id keystore parametreleri de burada sabitlenir (RFC-002 §7-1'in açık sorusu).

## 2. Kararlar (gerekçeleriyle)

| # | Decision | Rationale | Rejected alternative |
|---|---|---|---|
| D1 | **Düğüm şeması:** `{id, kind, text, ts, valid_from?, valid_to?, supersedes?}` | Önceleyen prototipin G13 dersi (çift-zamanlı / bi-temporal); "bu bilgi şu tarihte geçerli miydi?" sorusu ileride sorulabilir | düz bir not listesi |
| D2 | **Yalnız-ADD (ADD-only):** bir düğüm asla silinmez/değiştirilmez; bir düzeltme, yeni bir düğüm + `supersedes: <id>` anlamına gelir | Önceleyen-prototip dersi G17 (memory_revisions); kanıt kültürüyle birebir örtüşür | üzerine yazma |
| D3 | **Kenar şeması:** `[from_id, to_id, kind, ts?]`; kind: ref/derived/contradicts | Dilim-2 uygulaması normatif hâle geliyor; `contradicts`, önceleyen prototipin hakem-bekleyen çelişki taramasına hazır duruyor | yalnız-ref |
| D4 | **Arama:** v0 alt-dize araması (`memory --search`) kalıyor; FTS + graf-sinyali hibridi bir **v1 tasarım konusudur** | Dilim-2/3 kanıtı alt-dize aramasının yeterli olduğunu gösteriyor; v0'da ek bağımlılık yasak (sıfır-bağımlılık ilkesi) | şimdi FTS5 |
| D5 | **Keystore KDF = Argon2id** (m=64MiB, t=3, p=4) — PyNaCl yoksa scrypt yedeği (n=2^15, r=8, p=1, maxmem=64MiB), `kdf` alanıyla beyan edilir | RFC-002 §7-1 sabitlemesi; OpenSSL scrypt bellek-limiti gerçekliği Dilim-1'den biliniyor | yalnız-scrypt |
| D6 | **state format v1:** `{"format": "tamga-state/1", "sessions", "memory": {next_id, nodes[], edges[]}, "ledger_tip": "<64hex>", "graph_merkle": "<64hex>"}` | Dilim-2 göçü (F14) normatif hâle geliyor; `graph_merkle` = düğümler+kenarların sıralı hash'i (karıştırmaya-karşı-kanıtlı bir bellek); `ledger_tip` = anlık-görüntüyü defterle (ledger) çapraz bağlıyor | mevcut düz state |
| D7 | `memory --export-json` / `--import-json`: dış sistemler (sırada ilk: önceleyen prototip) dersleri Tamga düğümlerine taşır | Önceleyen-entegrasyon-notları L2 adaptörünün taşıyıcısı; yön tek-yönlü kalır: dış → tamga | doğrudan DB erişimi (yasak) |

## 3. Düğüm Türleri (v0)

`note` (serbest metin), `fact` (bir iddia — L2 adaptöründe önceleyen dersler bu tür olarak gelir), `session_marker` (oturum-başlangıcı işaretçisi, `run` tarafından otomatik olarak yazılır). v1 adayları: `goal`, `tool_result`.

## 4. reason_code genişletmesi (E-8)

16=node_limit (düğümler ≥ 10000) — **Denetim-9 B9'un dürüst notu: kodda bu sınır bugün fiilen gerekçe 10 (memory_limit) ile birlikte üretiliyor; 16 bugün hiç üretilmiyor** (bir rezerv; onayda ya metin koda hizalanır ya kod metne). 17=state_invalid (içe-aktarımda derin doğrulama; uygulamada bir `graph_merkle` uyuşmazlığı bu kodla RED verir).

İlgili reason_code'lar (normatif sicil RFC-002 §9'dadır): 7=snapshot_too_large (SAFE_SNAP_MAX 64MiB), 8=snapshot_replay_rollback (hedefin `sessions` sayacı anlık-görüntünün önündeyse içe-aktarım RED'dir — bir bellek-sürekliliği savunması), 9=agent_identity_mismatch (başlıktaki kimlik, keystore'dan türetilen pubkey ile eşleşmiyor). Negatif-vektör kanıtı: `.evidence/ (local, untracked)`.

## 5. Açık Sorular

1. `contradicts` kenarlarının otomatik tespiti (önceleyen `contradiction_scan` dersi) → v1.
2. `graph_merkle`'in ajan tarafından doğrulanması (ajan kendi belleğinin bütünlüğünü kendi ispatlar) → Faz 2.
3. L2 adaptörünün alan eşlemesi (önceleyen dersi ↔ `fact` düğümü) → adaptör uygulaması RFC'si (ilk Faz-2 maddesi).

## 6. Onay Kaydı

- [x] Kurucu onayı (2026-09-05) — RFC donduruldu; Durum v0.1-FINAL.

## 7. Uygulama-Uyumu Notu (2026-09-05, Dilim-9 — dondurma değil)

| RFC-004 provision | Implementation | Note |
|---|---|---|
| D5 Keystore KDF = Argon2id (öncelik), scrypt yedeği (n=2^15, r=8, p=1) | **Sevk edilen = scrypt (n=2^15, r=8, p=1)**, `kdf` alanıyla beyan edilir | **dürüst not:** PyNaCl, Argon2id içermez; D5'in yedek parametreleri v0'ın uygulamasıdır. Argon2id bir v1 yükseltmesi olarak duruyor (`kdf` beyanı geçişi uyumlu tutuyor). Kanıt: `.evidence/ (local, untracked)` (Dilimler 1–2) |
| D6 state v1 (`format`, `sessions`, `memory`, `ledger_tip`, `graph_merkle`) | birebir (F14 göçü dâhil) | kanıt: `.evidence/ (local, untracked)` (Dilim-6) |
| §3 düğüm türleri note/fact/session_marker | birebir; önceleyen-prototip dersleri `fact` olarak içeri akar (`memory --import-json`) | kanıt: `.evidence/ (local, untracked)` (Dilim-4) + Denetim-7 ön-koşulu |
| §4 E-8 kodları 17 (16: bugün gerekçe 10 üzerinden üretiliyor — B9 notu) | 17 birebir | üstteki 7/8/9 bağlam notu ile birlikte |
| — (RFC'de yok) | anlık-görüntü gövdesi, gömülü `ledger_records` taşır | normatif kaynak: RFC-002 E-9a |

Model sınırı (Denetim-7 A3): bir tohum-sahibi `graph_merkle`'i yeniden hesaplayıp tutarlı bir durum üretebilir; merkle için saldırgan modeli, **tohumu olmayan bir konağın** karıştırmasıdır — bu, onun tasarımdaki yerini belgeler; açık bir bulgu değildir.

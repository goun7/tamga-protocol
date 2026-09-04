# MERGEN ↔ Tamga Entegrasyon Notu

- **Tarih:** 2026-09-02 · **Durum:** teknik not (vision değil) · **Kayıt:** ROADMAP Faz 2 adaptör listesine işlendi
- **Tetik:** kurucu sorusu — "MERGEN'in memory bileşeni Mem0 deyince aklıma geldi; ilham alınabilir mi, entegre edilebilir mi?"

## 1. Dosyadan tespit (iddia değil, okuma)

MERGEN memory (`/MERGEN/mergen_tools/mergen_memory`, v1.6.1): SQLite WAL + FTS5 + vektör + Cypher; bi-temporal
valid_from/valid_to + `--at <ts>`; hibrit arama (semantik+BM25+grafik sinyal); `mergen_crdt.py`;
append-only `memory_revisions` (ADD-only, `mergen history <id>`); tamper-evident olay günlüğü (ÖZ);
hash-zincirli kanıt (MÜHÜR); LLM'siz deterministik çalışma; sıfır dış bağımlılık (MIT).

## 2. Felsefi hizalama (çarpıcı)

| MERGEN | Tamga |
|---|---|
| "ajanın KENDİ yaşam döngüsüne gömülü, kanıtlanabilir bellek" | "kendine-sahip ajan: hafızası, kimliği ve parası onunla gider" |
| MÜHÜR — hash-zincirli kanıt | tamga — mühür (Orhun abecesi) |
| ÖZ — tamper-evident olay günlüğü | ledger.jsonl append-only (RFC-003'te hash-zincir eklenecek) |
| sıfır dış bağımlılık | stdlib + pynacl (RFC'lerde pinli) |

İki sistem aynı sorunun iki katmanı: MERGEN **tek makinede ajanın hafıza yaşam döngüsünü**,
Tamga **hafızanın makine-ötesi taşınabilirliğini ve sahipliğini** çözer.

## 3. Entegrasyon katmanları (3 seviye)

### L1 — İlham (spec düzeyi, şimdi)
Tamga bağlam-grafik RFC'si (RFC-001 §9-1 açık sorusu, yazılacak) MERGEN şemasından 4 ders alır:
1. **Bi-temporal pencere** — hafıza düğümlerine valid_from/valid_to; "bu bilgi geçerli miydi?" sorusu
   (Zep'in liderliği MERGEN'e G13 ile işlenmişti; Tamga bunu doğrudan alır).
2. **ADD-only + revisions** — düğüm asla üzerine yazılmaz, superseded_by_id zinciri; kanıt kültürüyle birebir.
3. **Varlık-kenarları** — mevcut `edges` yapımızı entity-link modeliyle genişlet.
4. **Hibrit arama** — `memory --search` v0 substring; FTS + grafik-sinyal hibriti MERGEN deseninden.

### L2 — Adaptör (somut, Faz 2 ilk iş)
`mergen → tamga-snapshot/1` içe-aktarma adaptörü: MERGEN DB'sindeki dersler → Tamga bağlam düğümleri
(bi-temporal alanlarla) → şifreli snapshot. Sonuç: **"MERGEN derslerin mührüyle gider."** Test maliyeti en
düşük adaptör — iki sistemin sahibi aynı insan.

### L3 — Araştırma memo (Faz 3, expansion-debt kademesi)
`mergen_crdt.py` — CRDT, RFC-002 §7-2'deki "artımlı snapshot taşıma" açık sorusunun doğal cevabıdır:
iki node'un hafızası tam-snapshot yerine **merge** edilir (merkezi otorite olmadan). Önce ölçüm, sonra spec.

## 4. Sınır — ne YAPILMAZ (primitif koruması)

MERGEN memory **host-okunabilir SQLite**'tır; Tamga hafızası **şifreli + anahtar ajanın** (RFC-002 D3).
MERGEN'i Tamga'nın bellek motoru yapmak = D3'ün ölümü = primitifin sonu. Yön daima tek yön:
**MERGEN dersleri → Tamga formatına EXPORT.** Tamga, MERGEN ajanlarının (ve herhangi bir ajanın)
taşınabilir kimlik+hafıza+cüzdan katmanıdır; MERGEN bağımsız gelişmeye devam eder.

## 5. Karar kütüğü

- ROADMAP Faz 2 adaptör sırası: MERGEN birincili (bu not).
- Bağlam-grafik RFC'si yazılırken MERGEN şeması birincil kaynak (L1).
- L3 CRDT köprüsü araştırma-memo kademesinde — expansion-debt kuralı gereği şimdi spec açılmaz.
- MERGEN DB'sine ders yazımı (MCP add_memory) ajan kararı değil kurucu kararıdır — bu notta tetiklenmedi.

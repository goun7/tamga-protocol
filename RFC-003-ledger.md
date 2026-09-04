# RFC-003: Ledger Kaydı ve Ölçüm Sözleşmesi (tamga-sim/1)

- **Durum:** TASLAK v0.1 — kurucu onayı bekliyor. Onaylanınca **donar**.
- **Bağlılık:** RFC-002 (E-5/E-6: koşum ve ölçüm), ACCEPTANCE-TESTS.md AT-001c, TOKENOMICS.md (birim ekonomi), ROADMAP Faz 1 (4. dilim)
- **Kapsam:** v0 (Faz 1). Tüm tutarlar `*_sim`; gerçek değer taşıma Faz 4'ün konusudur (ikili tetik: çekim + yazılı hukuki görüş).

## 1. Motivasyon

RFC-002 koşumu ve ölçümü kanıtladı (E-6: cpu_saat/ram_gb_sn/io_mb/wall_ms gerçek ölçüm).
Bu RFC muhasebe kaydını pinler: kanıt kültürünün finansal hali — **her ücret satırı, doğrulanabilir bir sayaç dizisiyle**.

## 2. Kararlar (gerekçeleriyle)

| # | Karar | Gerekçe | Elenen alternatif |
|---|---|---|---|
| D1 | **Faturalama tabanı = wall_ms** (duvar-saati). cpu_saat/ram_gb_sn/io_mb kayıtta ayrı "kanıtsayı" kalır | Wasmtime saat-okuma yield'i cpu'yu wall'ın ~⅔'üne düşürür (kanıt: AT-001c.log); node'un kapasite sattığı şey duvar-saati kaynak dilimidir. cpu tabanı = host waktu ayarıyla oynanabilir | cpu-only (host ile kolayca oyunlanır; ajan saati vs host saati uyuşmazlığı) |
| D2 | **Formül:** `ucret = wall_sn * fiyat + ram_gb_sn * fiyat + io_mb * fiyat`. `cpu_saat` faturalamaya girmez, kanıt alanıdır | D1'in doğal sonucu; AT-001c formülüyle uyum (wall dönüşümü) | cpu tabanlı karma formül |
| D3 | **Ledger = append-only JSONL** (`ledger.jsonl`), 0600; satır = kanıt | RFC-002 D5 devamı; hash-zinciriyle D4 birleşir | SQLite (v1'de yeniden değerlendirilir) |
| D4 | **Hash-zinciri:** her kayıt `prev` (önceki kaydın 64-hex zincir-hash'i) + `h` (kendi hash'i) taşır. Genesis `prev` = 64×'0'. Zincir-hash = sha256(prev_hex | jcs(kayıt-prev-h-olmadan)) | MERGEN ÖZ/MÜHÜR dersinin Tamga karşılığı; kurcalama tek satırla zinciri kırar; `ledger --verify` ile ucuca kontrol | düz JSONL (sonradan düzenlenebilir) |
| D5 | **Kayıt tipleri:** `grant` (hibe), `charge` (koşum ücreti), `pay` (v1, ajan→ajan; şimdi rezerve) | AT-001c şartı + v1 ödeme halkasının yeri hazır | sadece charge |
| D6 | **Kanıt sayı alanları:** cpu_saat, ram_gb_sn, io_mb, wall_ms + `stdout_sha256`, `stdout_file` | AT-001c ±%5 şartının denetlenebilir verisi; sayılar bilimsel gösterimde olsa da değerler JCS-uyumlu JSON | yuvarlamasız float (JSON şeması karmaşıklaşır) |
| D7 | `ledger --verify` alt-komutu: zinciri baştan sona doğrular, `ok/broken_at` döner | Kanıt kültürü: zincir iddiası da kanıtlanabilmeli | elle script |
| D8 | `grant` kayıtları simnet'te operatör eliyle yazılır ve kayıtta `note` ile işaretlenir; RFC-003 sonrası `grant` yalnız runner alt-komutuyla yazılır | simnet gerçekliği + sahtecilik yüzeyini küçültme | keyfi düzenleme |

## 3. Kayıt Şeması (normatif)

```json
{"op": "charge", "seq": 3, "prev": "<64hex>", "h": "<64hex>",
 "pkg": "tamga-ornek-ajani", "session": 2, "engine": "wasmtime-v48.0.1",
 "wall_ms": 31081, "cpu_saat": 0.006119096, "ram_gb_sn": 0.644635761,
 "io_mb": 3.8e-05, "stdout_sha256": "<64hex>", "fee_sim": 0.000334594, "ts": "<ISO-8601>"}
```
Ortak alanlar: `op, seq, prev, h, ts`. `seq` 1'den başlar, +1 artar (eksik/atlama = zincir kırık). `grant`: `{op, seq, prev, h, pkg, amount, note, ts}`. Zincir-hash girdisi kaydın `h` ve `prev` dışındaki tüm alanlarıdır (JCS sıralı).

## 4. reason_code uzantısı (E-7)

14=ledger_broken (zincir doğrulaması kırık satırda başarısız), 15=ledger_empty (grant'sız koşum — faz 1'de uyarı, RED değil; koşum yine ücret kaydını yazar ve bakiye negatife düşebilir).

## 5. Açık Sorular

1. `pay` kayıt şeması + ajan cüzdanı denge kaydı → Faz 3 ağ RFC'si.
2. Zincirin snapshot'a gömülü son-hash özeti (cross-check) → Faz 2 sertleşmesi.
3. Multi-node ortak ledger → Faz 3 (tek makinede simnet değil, ağ).

## 6. Onay Kütüğü

- [ ] Kurucu onayı (tarih) — onay anında bu RFC donar, Durum: v0.1-FINAL olur.

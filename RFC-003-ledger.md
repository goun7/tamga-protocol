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
| D4 | **Hash-zinciri:** her kayıt `prev` (önceki kaydın 64-hex zincir-hash'i) + `h` (kendi hash'i) taşır. Genesis `prev` = 64×'0'. **Zincir-hash = sha256(prev_hex + jcs(kayıt-h-dışında))** — prev hem ÖNEK hem jcs girdisi İÇİNDE (Audit-9 B8: metin-kod tutarlılığı; node-cosign'da node_sig hash-girdisi dışında, node_id içindedir — bkz. §8 D8) | MERGEN ÖZ/MÜHÜR dersinin Tamga karşılığı; kurcalama tek satırla zinciri kırar; `ledger --verify` ile ucuca kontrol | düz JSONL (sonradan düzenlenebilir) |
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
Ortak alanlar: `op, seq, prev, h, ts`. `seq` 1'den başlar, +1 artar (eksik/atlama = zincir kırık). `grant`: `{op, seq, prev, h, pkg, amount, note, ts}`. **Zincir-hash girdisi = `prev` + jcs(`h` ve `node_sig` dışındaki tüm alanlar)** (JCS sıralı; Audit-9 B8).

## 4. reason_code uzantısı (E-7)

14=ledger_broken (zincir doğrulaması kırık satırda başarısız; Audit-9 B9 dürüst notu: **15=ledger_empty bugün HİÇ üretilmiyor** — grant'sız koşum sessizce bakiyeyi düşürür; 15 tasarım-rezervi olarak kalır, onayda üretilip üretilmeyeceği netleştirilir).

**Uyum notu (2026-09-05, quickstart bulgusu):** `ledger-verify`'ın zincirsiz pkg davranışı — boş/olmayan `ledger.jsonl` bozuk-değildir; `ok=true, lines=0, head=64×'0'` (genesis ucu) döner. D7'nin "doğru zincir" tanımıyla uyumludur; reason 14 yalnız **var olan** zincirin doğrulaması kırılırsa atılır.

## 5. Açık Sorular

1. `pay` kayıt şeması + ajan cüzdanı denge kaydı → Faz 3 ağ RFC'si.
2. ~~Zincirin snapshot'a gömülü son-hash özeti (cross-check) → Faz 2 sertleşmesi.~~ **SUPERSADED (2026-09-05):** sertleşme Faz 2'de beklemek yerine Dilim-8'de daha güçlü haliyle ships edildi — tam zincir gömülüyor (`ledger_records`) + `ledger_tip` çapraz-bağlama (F21/F24, RFC-002 E-9a).
3. Multi-node ortak ledger → Faz 3 (tek makinede simnet değil, ağ).
4. **node-cosign (2026-09-05, Audit-7 F25):** gömülü zincir taze node'da ajan-iddiasıdır; seed-sahibi tutarlı sahte tarih kurabilir (kanıt: kanit/GUVENLIK/2026-09-05/audit-7.log A1b). Kaydın hash girdisine node anahtarı girecek (kayıt node-sertifikalı olur) → Faz 2/3 revizyonu. Simnet v0'da kabul edilen sınır (tek-yazar).

## 6. Onay Kütüğü

- [ ] Kurucu onayı (tarih) — onay anında bu RFC donar, Durum: v0.1-FINAL olur.

## 7. Gerçekleme Uyumu Notu (2026-09-05, Dilim-9 — dondurma değildir)

TASLAK'tan normatif sapma yok; gerçekleme bu RFC'yi izliyor, iki adsal/erdamsal fark errata'ya bağlanıyor:

| RFC-003 hükmü | Gerçekleme | Not |
|---|---|---|
| D3 append-only JSONL 0600 | `ledger.jsonl` 0600 (`_ledger_append`) | birebir |
| D4 hash-zinciri `sha256(prev + jcs(kayıt-h-node_sig-dışında))`, genesis 64×'0', seq 1-bazlı | `_ledger_head` + `ledger-verify` | birebir (B8 formül-tutarlılığı); kanıt: kanit/FAZ1/2026-09-02/dilim-5.log |
| D7 doğrulama alt-komutu `ledger --verify` | **`ledger-verify`** (tek kelime, tireli) | **adsal düzeltme**: CLI yüzeyi budur; `--verify` bayrağı yoktur. Onay öncesi metin güncellenecek |
| §4 reason 14 (15: bugün üretilmiyor — B9 notu) | 14=zincir kırık (kırık@N/node_sig_geçersiz@N), ayrıca cosign-L1 RED'leri | birebir; ek: 14 artık **gömülü zincir** için de import'ta atılır (RFC-002 E-10a) |
| — (RFC'de yok) | `ledger_tip` state'te; import'ta zincir-üyeliği doğrulanır (F21) | normatif kaynak: RFC-002 E-9a |
| — (RFC'de yok) | gömülü `ledger_records` kuruluş-öncesi doğrulanır | normatif kaynak: RFC-002 E-10a |

Kural: bu not RFC'yi değiştirmez; farklar RFC-002 §9 errata'larında normatiftir. Kurucu onayı anında "adsal düzeltme" ve Açık Soru 4 ana metne alınır, sonra RFC donar.


## 9 — D9 (Dilim-11): Girdi-bağlama ve çıktı-kanıt-satırı (2026-09-05)

**charge makbuzu yeni opsiyonel alanı:** `input_sha256` = sha256(--input dosya-baytları).
Sözleşme: alan yalnız koşumda `--input <dosya>` verildiyse vardır; yokluğu "girdisiz iş"
anlamına gelir (eski makbuzlarla uyumlu). Sınır: girdi ≤ 1 MiB (D11) — aşımı koşum-öncesi
RED 10 `input_invalid` (ücret/zincir yazılmadan).

**Çıktı-kanıt-satırı (`--require-proof`):** ajan stdout'unun son satırı `TAMGA:<hex16>`
biçiminde stdout'un kalan baytlarının FNV-1a-64 parmakizini verir; runner koşum-anında
yeniden hesaplar, uyuşmazlık → RED 12 `output_proof_mismatch` (makbuz yazılmaz).

**Replay-contract:** (wasm_sha256, input_sha256) → stdout_sha256 determinizmi artık
*girdili* işler için testli (AT-004). Sınırlar: FNV kripto-değil (kanıt-satırı yardımcı;
kurcalama-direnci ledger-hash'lerinden gelir); LLM non-deterministik işler bu sözleşme
DIŞINDA — sınıf-tanımlı kapsam RFC-004 Faz-2 bölümünde (Tur-4 telafi-3'e bağlantı).
## 8. v0.2 Revizyon Adayı — D8: node-cosign (2026-09-05, Audit-8; KURUCU ONAYI BEKLİYOR)

Audit-7 F25'ün (gömülü zincir taze node'da ajan-iddiasıdır) kalıcı çözümü önceden
gerçeklendi (L0 default, davranış değişmedi; L1 opt-in pilot hazır):

- **D8:** Her kayıt opsiyonel `node_id` (64-hex, node operatör anahtarının verify-key'i)
  + `node_sig` (ed25519 imza, girdi = kaydın `h`'si) taşıyabilir. `node_id` **hash-girdisi
  içindedir** (zincir node kimliğini bağlar); `node_sig` hash-girdisi DIŞINDADIR (h'yi
  imzalar; kurcalama imza kontrolünde yakalanır). İki katman birbirini kapatır.
- **Politika merdiveni:** L0 (bugünkü davranış — node_sig'siz zincir meşru; node_sig'li
  kayıtta imza yine doğrulanır) / L1 (import'ta her kayıt node_sig'li VE node_id güvencili
  listede olmalı; aksi RED reason 14) / L2 (Faz 3: ERC-8004 itibar bağlaması).
- **Node anahtarı:** operatör kimliği; 0600 dosyada durabilir (D3 yalnız ajan seed'ini
  diske yasaklar). `keygen-node <dir>` ayrı komuttur.
- **Kanıt:** AT-003 6/6 (tests/negative_cosign.sh) + Audit-8 (A1 güçlü düşman L1 RED /
  L0 bilinen-kalıntı; A2 imza-katmanı RED; A3 kısmi-cosign RED) — kanit/GUVENLIK/2026-09-05/.
- **Kurucuya sorular:** OQ-1 (L1 pilot'ta default mu?) — specs/DESIGN-node-cosign.md §6.

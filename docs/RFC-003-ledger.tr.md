# RFC-003: Defter Kaydı ve Ölçüm (Metering) Sözleşmesi (tamga-sim/1)

> Çeviri notu: İngilizce-orijinali ile ikiz (docs/RFC-003-ledger.md); normatif-metin İngilizce'dir — çelişki-olursa ORİJİNAL-BAĞLAYICIDIR.

> Bu belgenin kanonik sürümü Türkçe'dir (dahili). Bu, resmî İngilizce çevirisidir — normatif içerik birebir aynıdır.

*Çevirmenin notu: kod blokları, JSON anahtarları, alan adları, formüller ve örnek değerler (örnek paket adı `tamga-ornek-ajani` ve ücret-formülü değişmezleri `ucret`/`fiyat` dâhil) kanonik Türkçe orijinalden birebir aktarılmıştır. Kanıt-günlüğü atıfları, yerel ve izlenmeyen `.evidence/` koşu-günlüğü dizinine yöneliktir; dahili belgeler tanımlayıcı biçimde anılır (dahili karar günlüğü). "Önceleyen prototip" (Tamga'dan önceki dahili bir sistem), bu sözleşmenin kendisinden ders kaydettiği sistemi karşılar.*

- **Durum:** **v0.1-FINAL — DONDURULDU (2026-09-05, kurucu onaylı).** Bir değişiklik, yeni bir RFC + sürüm artışı gerektirir.
- **Bağımlılıklar:** RFC-002 (E-5/E-6: çalıştırma ve ölçüm), kabul testi AT-001c, tokenomics (birim ekonomisi), yol haritası Faz 1 (Dilim 4) — atıf yapılan belgeler dahili (karar günlüğü).
- **Kapsam:** v0 (Faz 1). Tüm tutarlar `*_sim`dir; gerçek değer taşımak Faz 4'ün konusudur (çift tetik: para çekme + yazılı hukuki mütalaa).

## 1. Motivasyon

RFC-002 çalıştırmayı ve ölçümü kanıtladı (E-6: cpu_saat/ram_gb_sn/io_mb/wall_ms gerçek ölçümlerdir).
Bu RFC muhasebe kaydını sabitler: kanıt kültürünün finansal biçimi — **her ücret satırının doğrulanabilir bir ölçer dizisiyle desteklenmesi**.

## 2. Kararlar (gerekçeleriyle)

| # | Decision | Rationale | Rejected alternative |
|---|---|---|---|
| D1 | **Faturalama tabanı = wall_ms** (duvar saati). cpu_saat/ram_gb_sn/io_mb kayıtta ayrı "kanıt ölçerleri" olarak kalır | Wasmtime'ın saat-okuma sırasında işlem bırakmaları cpu'yu wall'ın ~⅔'üne indirir (kanıt: AT-001c, `.evidence/ (local, untracked)`); düğümün kapasite olarak sattığı, duvar-saati kaynak dilimidir. Bir cpu tabanı, konak saat ayarıyla istismar edilebilir | yalnız-ca cpu (konağa karşı kolay istismar; ajan-saati ile konak-saati uyuşmazlığı) |
| D2 | **Formül:** `ucret = wall_sn * fiyat + ram_gb_sn * fiyat + io_mb * fiyat`. `cpu_saat` faturalamaya girmez; bir kanıt alanıdır | D1'in doğal sonucu; AT-001c formülüyle (duvar dönüşümü) tutarlı | cpu tabanlı karma formül |
| D3 | **Defter = yalnız-eklemeli JSONL** (`ledger.jsonl`), 0600; bir satır = bir kanıt satırı | RFC-002 D5'in devamı; D4'teki hash zinciriyle birleşir | SQLite (v1'de yeniden değerlendirilir) |
| D4 | **Hash zinciri:** her kayıt `prev` (önceki kaydın 64-hex zincir hash'i) + `h` (kendi hash'i) taşır. Genesis `prev` = 64×'0'. **Zincir hash'i = sha256(prev_hex + jcs(record-except-h))** — prev hem ÖNEK hem de jcs girdisinin İÇİNDEDİR (Denetim-9 B8: metin–kod tutarlılığı; düğüm-birlikte-imzalamasında (node-cosign) node_sig hash girdisinin dışındadır, node_id içindedir — bkz. §8 D8) | Önceleyen prototipin çekirdek/mühür dersinin Tamga karşılığı; tahrif zinciri tek bir satırla kırar; `ledger --verify` ile uçtan uca denetim | düz JSONL (sonradan düzenlenebilir) |
| D5 | **Kayıt türleri:** `grant` (bir kredi), `charge` (bir çalıştırma ücreti), `pay` (v1, ajan→ajan; şimdilik ayrılmış) | AT-001c gereksinimi + v1 ödeme döngüsünün yuvası hazır | yalnız-ca charge |
| D6 | **Kanıt ölçer alanları:** cpu_saat, ram_gb_sn, io_mb, wall_ms + `stdout_sha256`, `stdout_file` | AT-001c ±%5 gereksiniminin ardındaki denetlenebilir veri; sayılar bilimsel gösterimde olsa bile değerler JCS-uyumlu JSON'dur | yuvarlanmamış float (JSON şeması karmaşıklaşırdı) |
| D7 | `ledger --verify` alt-komutu: zinciri baştan sona doğrular, `ok/broken_at` döndürür | Kanıt kültürü: zincir iddiası da ispatlanabilir olmalı | elle koşulan script |
| D8 | `grant` kayıtları simnet'te operatörün eliyle yazılır ve kayıtta `note` ile işaretlenir; RFC-003 sonrası `grant` yalnızca runner alt-komutuyla yazılır | simnet gerçeği + sahtecilik yüzeyinin küçültülmesi | keyfi düzenleme |

## 3. Kayıt Şeması (normatif)

```json
{"op": "charge", "seq": 3, "prev": "<64hex>", "h": "<64hex>",
 "pkg": "tamga-ornek-ajani", "session": 2, "engine": "wasmtime-v48.0.1",
 "wall_ms": 31081, "cpu_saat": 0.006119096, "ram_gb_sn": 0.644635761,
 "io_mb": 3.8e-05, "stdout_sha256": "<64hex>", "fee_sim": 0.000334594, "ts": "<ISO-8601>"}
```
Ortak alanlar: `op, seq, prev, h, ts`. `seq` 1'den başlar ve +1 artar (eksik/atlanmış değer = kırık zincir). `grant`: `{op, seq, prev, h, pkg, amount, note, ts}`. **Zincir-hash girdisi = `prev` + jcs(`h` ve `node_sig` dışındaki tüm alanlar)** (JCS sıralı; Denetim-9 B8).

## 4. reason_code genişletmesi (E-7)

14=ledger_broken (zincir doğrulaması kırık satırda başarısız olur; Denetim-9 B9'un dürüst notu: **15=ledger_empty bugün hiç üretilmez** — grantsiz bir çalıştırma bakiyeyi sessizce düşürür; 15 bir tasarım ayrımı olarak kalır ve üretilip üretilmeyeceği onayda netleşecektir).

**Uyumluluk notu (2026-09-05, bir quickstart bulgusu):** zinciri olmayan bir pkg için `ledger-verify` davranışı — boş/eksik `ledger.jsonl` bozuk sayılmaz; `ok=true, lines=0, head=64×'0'` döndürür (genesis ucu). Bu, D7'nin "doğru zincir" tanımıyla tutarlıdır; gerekçe 14 yalnızca **var olan** bir zincirin doğrulanması kırıldığında atılır.

## 5. Açık Sorular

1. `pay` kayıt şeması + ajan cüzdan bakiye kaydı → Faz 3 ağ RFC'si.
2. ~~Anlık-görüntüye (snapshot) gömülü bir zincir-uçu özeti (çapraz kontrol) → Faz 2 sağlamlaştırma.~~ **GEÇERSİZ KILINDI (2026-09-05):** Faz 2'nin beklenmesi yerine sağlamlaştırma, Dilim-8'de daha güçlü bir biçimle sevkedildi — tüm zincir gömülür (`ledger_records`) + `ledger_tip` çapraz-bağlama (F21/F24, RFC-002 E-9a).
3. Çok-düğümlü paylaşılan defter → Faz 3 (bir ağ, tek-makineli simnet değil).
4. **Düğüm-birlikte-imzalaması (node-cosign) (2026-09-05, Denetim-7 F25):** gömülü bir zincir, taze bir düğümde yalnızca bir ajan iddiasıdır; tohum-sahibi öz-tutarlı sahte bir tarihçe kurabilir (kanıt: Denetim-7 A1b, `.evidence/ (local, untracked)`). Düğüm anahtarı kaydın hash girdisine girecek (kayıt düğüm-onaylı hâle gelir) → bir Faz 2/3 revizyonu. Simnet v0'da kabul edilmiş sınır (tek-yazarlı).

## 6. Onay Kaydı

- [x] Kurucu onayı (2026-09-05) — RFC donduruldu; Durum v0.1-FINAL. §7 uyumluluk notundaki "adlandırma düzeltmesi" (`ledger-verify`) ve Açık Soru 4, dondurma anında ana metne işlendi.

## 7. Kurulum-Uyumluluk Notu (2026-09-05, Dilim-9 — dondurma değil)

Bu belge TASLAK aşamasındayken hiçbir normatif sapma bulunmadı; kurulum bu RFC'yi izliyor ve iki adlandırma/errata sınıfı fark RFC-002 §9 erratalarına bağlanıyor (adlandırma düzeltmesi dondurma anında işlendi).

| RFC-003 provision | Implementation | Note |
|---|---|---|
| D3 yalnız-eklemeli JSONL 0600 | `ledger.jsonl` 0600 (`_ledger_append`) | birebir |
| D4 hash zinciri `sha256(prev + jcs(record-except-h-node_sig))`, genesis 64×'0', seq 1 tabanlı | `_ledger_head` + `ledger-verify` | birebir (B8 formül tutarlılığı); kanıt: `.evidence/ (local, untracked)` (Dilim-5) |
| D7 doğrulama alt-komutu `ledger --verify` | **`ledger-verify`** (tek sözcük, tireli) | **adlandırma düzeltmesi**: CLI yüzeyi budur; `--verify` bayrağı yoktur. Metin onaydan önce güncellenecek |
| §4 gerekçe 14 (15: bugün üretilmiyor — B9 notu) | 14=chain broken (broken@N / node_sig_invalid@N), artı cosign-L1 RED'leri | birebir; ek: 14 artık import sırasında **gömülü zincir** için de atılır (RFC-002 E-10a) |
| — (RFC'de yok) | durumda `ledger_tip`; zincir üyeliği import'ta doğrulanır (F21) | normatif kaynak: RFC-002 E-9a |
| — (RFC'de yok) | gömülü `ledger_records` kurulumdan önce doğrulanır | normatif kaynak: RFC-002 E-10a |
| D2 `fiyat` (formül RFC'de sembolik kalır) | `tamga_runner.py` içinde `SIM_PRICE = {"cpu_saati": 0.002, "ram_gb_sn": 0.0005, "io_mb": 0.001}` (simnet sabitleri, Dilim-4 E-6) | **simnet-fiyatlı, normatif değil**: gerçek fiyatlar pilotun Faz-2 konusudur; sabitler kodda, bu not onların sabitlenmiş başvurusu olarak durur — fiyatlama bir kapı olduğu, bir özellik (spec property) olmadığı için D2'nin `fiyat`'ı burada kasten sembolik bırakılmıştır |

Kural: bu not RFC'yi değiştirmez; farklar RFC-002 §9 erratalarında normatiftir. Kurucu onayında "adlandırma düzeltmesi" ve Açık Soru 4 ana metne işlenir, ardından RFC donar.

### 7a. Fiyat-okuma tablosu (2026-09-13, önerge-3 — maliyet-faktörü belgelenmesi, hâlâ bir kapı)

D2'nin konumu değişmedi: fiyatlama bir pilot kapısıdır, bir özellik değil — aşağıdaki sabitler simnet sembolleridir.
Bu tablonun eklediği, bir *okuma* sözleşmesidir; öyle ki ilk gerçek pilot verisi
(sorun #3379 parkı) yorumsalama tartışması olmadan ona bırakılabilsin. Üç kalem:

| Reading item | What it says | Where the truth lives |
|---|---|---|
| **Kaynak-taraflı ücret algısı** | Kaynak sahibinin dürüst çerçevesi: `fee = cpu_h·0.002 + ram_gb·s·0.0005 + io_mb·0.001` *sembolik*tir; gerçek bir maliyet iddiası edilmez. Ölçülmüş-iş birimleri (cpu-saatleri / GB·s / io-MB), kapalı-enum kapasite-tasdik eksenine (`gpu-hours\|storage\|api-credits\|bandwidth`, #3379) çarpışmadan komşudur. | `tamga_runner.py` içinde `SIM_PRICE` (Dilim-4 E-6), yukarıdaki D2 satırıyla sabitlenmiş |
| **Karşı-taraf tutarlılığı** | Her charge kaydında iki ücret değeri yaşar: `fee_birebir` = ham, formül-birebir ücret; `fee_sim` = son `FEE_MEDIAN_N = 5` charge'ın medyanı — müşterinin faturası medyanı taşır, böylece tek bir işin duvar-yükü gürültüsü (~172× salınım, OQ-8) asla faturaya vurmaz. İki-göz dürüstlüğü: ham değer fişten hiç gizlenmez. | `fee_birebir` / `fee_sim` alanları, `charge` kayıtları; medyan penceresi `OQ-8` (kurucu kararı 2026-09-05) |
| **Birim ölçeği** | `cpu_saati` = CPU-saatleri (ölçülmüş), `ram_gb_sn` = GB·saniye, `io_mb` = MB G/Ç. Karşılaştırmanın iki tarafında da aynı sabit ölçek — bu tabloya yapıştırılan pilot verisi birim dönüşümü gerektirmez. | fiş alanları `cpu_saat` / `ram_gb_sn` / `io_mb` (§4 ölçüm) |

Gerçek pilot fiyatları geldiğinde §7 uyumluluk tablosuna *yeni* bir satır olarak
konarlar (kurulum tarafı), asla sessizce `SIM_PRICE`'a değil — sabitler yalnızca bir kurucu
kararıyla değişir ve simnet satırı, o an neye inanıldığının sabitlenmiş başvurusu olarak durur.


## 9 — D9 (Dilim-11): Girdi bağlama ve çıktı ispat satırı (2026-09-05)

**`charge` fişinin yeni isteğe bağlı alanı:** `input_sha256` = sha256(`--input` dosya baytları).
Sözleşme: alan yalnızca çalıştırma anında `--input <file>` verildiyse vardır; yokluğu
"girdisiz bir iş" demektir (eski fişlerle uyumlu). Sınır: girdi ≤ 1 MiB (D11) — aşımı, çalıştırma-öncesi
RED 10 `input_invalid`'dir (ücret/zincir yazılmadan).

**Çıktı ispat satırı (`--require-proof`):** ajanın stdout'unun son satırı `TAMGA:<hex16>`
biçimindedir ve kalan stdout baytlarının FNV-1a-64 parmak izini verir; runner bunu çalıştırma anında
yeniden hesaplar, uyuşmazlık → RED 12 `output_proof_mismatch` (fiş yazılmaz).

**Yineleme (replay) sözleşmesi:** (wasm_sha256, input_sha256) → stdout_sha256 determinizmi artık
*girdili* işler için test edilmektedir (AT-004). Sınırlar: FNV kriptografik değildir (ispat satırı bir
yardımcıdır; tahrifa direnç defter hash'lerinden gelir); deterministik olmayan LLM işleri bu sözleşmenin
DIŞINDADIR — sınıf-tanımlı kapsam RFC-004'ün Faz-2 bölümündedir (Tur-4 düzeltme-3'e bağlı).
## 8. v0.2 Revizyon Adayı — D8: düğüm-birlikte-imzalaması (node-cosign) (2026-09-05, Denetim-8; KURUCU ONAYI BEKLİYOR)

Denetim-7 F25'in kalıcı çözümü (gömülü zincir, taze bir düğümde bir ajan iddiasıdır)
vaktinden önce kuruldu (L0 varsayılan, davranış değişmedi; L1 seçmeli (opt-in) pilotu hazır):

- **D8:** Her kayıt isteğe bağlı bir `node_id` (64-hex, düğüm operatörü anahtarının doğrulama-anahtarı)
  + `node_sig` (bir ed25519 imzası, girdi = kaydın `h`'si) taşıyabilir. `node_id` **hash girdisinin içindedir**
  (zincir düğüm kimliğini bağlar); `node_sig` hash girdisinin DIŞINDADIR (`h`'yi imzalar; tahrif
  imza denetimiyle yakalanır). İki katman birbirini örter.
- **Politika merdiveni:** L0 (bugünkü davranış — node_sig'siz bir zincir meşrudur; node_sig taşıyan
  kaydın imzası yine doğrulanır) / L1 (import'ta her kayıt node_sig taşımak ZORUNDADIR ve node_id'si
  güvenli-listede (safelist) olmalıdır; aksi hâlde RED gerekçe 14) / L2 (Faz 3: ERC-8004 itibar bağlama).
- **Düğüm anahtarı:** operatör kimliği; bir 0600 dosyasında durabilir (D3 yalnızca ajan tohumunu diske yasaklar).
  `keygen-node <dir>` ayrı bir komuttur.
- **Kanıt:** AT-003 6/6 (`tests/negative_cosign.sh`) + Denetim-8 (A1 güçlü bir saldırgan → L1 RED /
  L0 bilinen kalıntı; A2 imza-katmanı RED; A3 kısmi-birlikte-imzalama RED) — `.evidence/ (local, untracked)`.
- **Kurucuya sorular:** OQ-1 (pilotda L1 varsayılan olmalı mı?) — düğüm-birlikte-imzalama tasarım belgesi §6 (dahili karar günlüğü).

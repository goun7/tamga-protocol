# EN/TR İkiz-Doküman Tutarsızlık Raporu

**Tarih:** 2026-10-11
**Kapsam:** `docs/ARCHITECTURE.md` ↔ `docs/ARCHITECTURE.tr.md`, `README.md` ↔ `README.tr.md`
**Kısıt:** Yalnızca inceleme. Bu rapor yazıldı; hiçbir kaynak doküman DEĞİŞTİRİLMEDİ.

---

## 0. Yönetici özeti

| | Sonuç |
|---|---|
| **Toplam uyumsuzluk** | **24** |
| 🔴 Kritik (yanlış/yanıltıcı bilgi) | 5 |
| 🟠 Orta (eski rakam, eksik bölüm, yapısal bozulma) | 12 |
| 🟡 Düşük (kelime, bağlantı, nüans) | 7 |
| `ARCHITECTURE.md` ↔ `.tr.md` | **0 içerik uyumsuzluğu** (Bölüm 1) |
| `README.md` ↔ `.tr.md` | **24 uyumsuzluğun tamamı burada** (Bölüm 2-3) |

En ağır iki sonuç:

1. **TR README, EN README'de belgelenmiş DURDURULAMIYOR (fail-open) bir güvenlik
   kusurunu hiç içermiyor** (K1). TR ayrıca "aynı kapsamı taşır" diye iddia ediyor (K2).
2. **EN README "docs are English" diyor ve kendi içinde 77 satır Türkçe taşıyor** (K3).

---

## 1. ARCHITECTURE çifti: uyumsuzluk BULUNMADI

İki dosya 15 dakika boyunca kelime-kelime değil, **teknik-yüzey** düzeyinde karşılaştırıldı.
Yöntem ve kanıt:

| Denetim | EN | TR | Sonuç |
|---|---|---|---|
| Sayı/hex/dosya-adı token kümesi (regex çıkarımı, sıralı diff) | 233 satır | 235 satır | **birebir aynı** (`diff` boş) |
| §7 reason-code tablo satır sayısı | 15 | 15 | aynı |
| §7 kod listesi | `1 2 3 4 6 7 8 9 10 11 12 13 14 17 18` | aynı | aynı |
| Paragraf bloğu sayısı (boş-satır bölmesi) | 34 | 35 | +1 = TR başlığındaki çeviri-notu |
| Mermaid blokları | 4 | 4 | aynı (çevirilmemiş, EN kalmış) |
| §8 overhead rakamları | 103/102/121/107/161/253/490/421 ms | aynı | aynı |
| §3 limitleri | `[16,4096]`, `[1,60000]`, `[0,1024]` | aynı | aynı |
| §5 epoch/batch | `epoch-10, 57 facts` | aynı | aynı |

**Tek yapısal fark:** `docs/ARCHITECTURE.tr.md:1` satırında bir çeviri-notu var
("İngilizce-orijinali ile ikizdir… kaynak değişirse bu ikiz güncellenmeli");
`docs/ARCHITECTURE.md`'de karşılığı yok. Bu bir uyumsuzluk değil, ikiz-protokolü etiketidir.

**Tarih anomalisi (not, bulgu değil):** `git log`'a göre EN 2026-09-12 (`cd88652`),
TR 2026-09-16 (`7bfa8d6`) tarihinde dokunulmuş — yani TR ikizi orijinalinden DAHA GEÇ
güncellenmiş. İçerik yine de aynı: TR o turda EN'e taşınmış bir düzeltmeyi değil,
yalnızca oran/dürüstlük notlarını senkronlamış.

> Yine de ARCHITECTURE'ın kendi içinde bir çelişkisi var ve **her iki ikizde de** duruyor:
> bkz. O5.

---

## 2. Kritik bulgular (🔴 yanlış veya yanıltıcı bilgi)

### K1 — Fail-open güvenlik kusuru TR'de YOK
- **EN:** `README.md:220-231` — "One fail-open path in state loading (found 2026-10-02,
  **not yet fixed**)" maddesi. `state.json` okunamazsa / `graph_merkle` yanlışsa /
  yanlış-tipse **fail-closed** (AT-227 kanıtlı); ANCAK `memory` alanı hiç dict değilse
  doğrulanmadan Merkle yeniden-hesabına giriyor, yakalanmamış `AttributeError` atıyor ve
  süreç **exit 0 = yeşil** çıkıyor. Ayrıca `memory` silinirse bütünlük kontrolü sessizce atlanıyor.
- **TR:** `README.tr.md:92-102` "Dürüst sınırlar" bölümünde bu madde **tamamen yok**.
  `graph_merkle`, `AT-227`, `fail-open`, `memory field` kelimeleri TR dosyasında **0 kez** geçiyor.
- **Neden kritik:** Bu, düzeltilmemiş bir bütünlük-kontrolü atlanma yoludur. Türkçe okuyucu
  — ki RFC'lerin kanonik dili Türkçe'dir (README.md:489) — bu uyarıya hiç ulaşamıyor.

### K2 — TR README asılsız "eş-kapsam" iddiası taşıyor
- **TR:** `README.tr.md:19-22` — "İngilizce README.md'nin Türkçe karşılığıdır…
  İngilizce garantiler ve dürüst sınırların kanıt-tablolarıyla **aynı kapsamı taşır**".
- **EN:** `README.md`'de TR'de hiç karşılığı olmayan **5 büyük bölüm** var:
  31-44 (ölçülmüş-boşluk), 79-116 (BrandStrike/zaman-ekseni), 134-141 (kurulum-suz doğrulama),
  145-212 (akademik-temeller), 518-607 (akademik kaynaklar), toplam ~200 satır / dosyanın %33'ü.
- **Neden kritik:** Doğrudan yanlış bir öz-tanım. Bu iddia olmasa eksik bölümler
  "özet" sayılabilirdi; iddia onları taahhüde çeviriyor ve taahhüt tutmuyor.

### K3 — EN README dili kendiyle çelişiyor
- **EN:** `README.md:233-237` "Language surface: core code comments, suite output and
  **docs are English**".
- **EN (aynı dosya):** `README.md:280-318` arası **Türkçe** "Hızlı Başlangıç (Quick Start — 5 adım)"
  bölümü + `README.md:518-607` arası **Türkçe** "Akademik Kaynaklar (2024-2026)" bölümü.
  Ölçüm: `README.md` içinde Türkçe-karakter içeren **77 satır / 607 satır (%12,7)**.
- **Neden kritik:** Belgelenmiş iddia, iddiayı taşıyan dosyanın kendisi tarafından ihlal ediliyor.
  `git log` sırası da bunu destekliyor: EN README en son 2026-10-05 (`9dd7455`),
  TR README 2026-10-02 (`4305261`) — yani EN güncel, Türkçe içerik EN'e sonradan girmiş.

### K4 — "Academic & technical foundations" bölümünün tamamı TR'de yok
- **EN:** `README.md:145-212`, dört alt-başlık:
  tamper-evident logging + RFC 6962 (145-163), x402 + issue **#2332** alıntısı (165-180),
  **EU AI Act Article 12 / Reg. (EU) 2024/1689, 2 December 2027** + düzeltme-notu (182-199),
  MCP/WASI oracle kalıpları + AT-212/AT-217 (201-212).
- **TR:** `AI Act`, `2024/1689`, `December 2027`, `2332`, `6962` anahtar-kelimeleri **0 kez**.
- **Neden kritik:** Yalnızca "eksik anlatım" değil — 191-199. satırlar bir **uyum tarihi
  düzeltmesini** barındırıyor (eski taslak 2 Ağu 2026 diyordu, düzeltme 2 Ara 2027). Türkçe
  okuyucu hem iddiayı hem düzeltmeyi göremiyor; dolayısıyla düzeltilmiş değeri aktaramıyor.

### K5 — BrandStrike zaman-ekseni + TSA bağı TR'de yok
- **EN:** `README.md:79-116` — "The time axis — BrandStrike" paragrafı (81-87) ve
  "The code bond" bloğu (89-116): `tools/brandstrike_tsa.py` RFC 3161 doğrulayıcısı,
  query/response tarafı, `sha256(chain_tip)` imprint bağı, **31 unit test**
  (`tests/test_brandstrike_tsa.py`), kabul kontrolü **AT-229**, "Zero new dependencies",
  dürüst-limit notu (113-116).
- **TR:** `BrandStrike`, `brandstrike_tsa`, `AT-229` **0 kez**. TR'nin "Temel güvenceler"
  listesi (`README.tr.md:46-52`) 6 madde ve bunların hiçbiri zaman-kanıtı eksenini içermiyor.
- **Neden kritik:** EN bunu **Core guarantees** başlığı altında bir garanti olarak konumlandırıyor;
  TR'de aynı konumda karşılığı yok → iki dosya farklı garanti-kümeleri ilan ediyor.

---

## 3. Orta bulgular (🟠 eski rakam / eksik bölüm / yapısal bozulma)

### Sayı uyumsuzlukları

| # | Konu | EN ne diyor | TR ne diyor | Doğru değer (repo ölçümü) |
|---|---|---|---|---|
| **O1** | Test rozeti | `README.md:9` — `tests-241/242 PASS` | `README.tr.md:9` — `tests-240/241 PASS` | `run_all.sh`'te **242** kontrol çağrısı → EN doğru, TR 1 kontrol geride |
| **O2** | Aynı sayı metinde | `README.md:263` ve `README.md:346` — "241/242 controls — 1 SKIP, 0 FAIL" | `README.tr.md:59`, `:115`, `:264` — "240/241 — 1 SKIP, 0 FAIL" | 241 PASS + 1 SKIP = 242 → EN tutarlı, TR toplamda 1 eksik |
| **O3** | Live/default dökümü | `README.md:263,346` — "**230 default / +4 live**" (toplam 234) | `README.tr.md:59,264` — "TAMGA_LIVE=1 ile **237**" | `run_all.sh`'te **5** `kontrol_live` çağrısı. EN kendi 241/242'siyle de çelişiyor (234≠241); TR 237 üçüncü bir değer |
| **O4** | Üçüncü dosya çatışması | `docs/TESTS.md:6` — "**240/240** AT suites — 240 PASS, 1 SKIP … TAMGA_LIVE=1 → **244**" | — | Dört dosya, dört farklı toplam: 242 / 241 / 237 / 240-244 |

> O1-O4'ün ortak kökü: suite büyüklüğü her bulgu turunda güncelleniyor, ama
> EN↔TR senkronu elle ve gecikmeli yapılıyor. TR'nin son dokunuşu 2026-10-02, EN'inki
> 2026-10-05 → TR 3 günlük suite-değişikliğini almadı.

### O5 — ARCHITECTURE'ın iç çelişkisi (her iki ikizde de)
- `docs/ARCHITECTURE.md:4` / `docs/ARCHITECTURE.tr.md:7` — "`tests/run_all.sh` (**21 controls**, CI-green)"
- `docs/ARCHITECTURE.md:226` / `docs/ARCHITECTURE.tr.md:228` — depo-ağacı bloğunda
  "`tests/run_all.sh  ` **19-control** acceptance suite (CI)`"
- Aynı dosyanın girişi 21 diyor, sonu 19 diyor, README 241/242 diyor, repo 242.
- **EN↔TR uyumsuzluğu değil** — ikizler birbiriyle **uyumlu** ve birlikte bayat.
  Yine de rapora dahil, çünkü denetimin konusu olan "eski sayı/rakam" sınıfının en net örneği.

### Eksik bölüm (EN → TR)

**O6 — Reproduce rozeti ve suite-koşum tarihi**
- EN `README.md:12`: `[Reproduce](docs/REPRODUCE.md) — last full suite run: **2026-09-17 (58/58 slow)**`
- TR `README.tr.md:7-11`: rozet satırı **yok** (PyPI/CI/Tests/Lisans/Durum var, Reproduce yok).
- Ek sorun: EN'in kendi 2026-10-05'te güncellenmiş; "last full suite run 2026-09-17" ve
  "58/58 slow" rakamı 242-krollük suite ile bağdaşmıyor → EN'de de bayat.

**O7 — EN'de madde-işareti bozulması (determinizm maddesi ortadan kesik)**
- EN `README.md:219` — `- **Determinism scope is class-defined:** deterministic wasm jobs are replay-proven;`
  satırı **noktalı-virgülle bitiyor ve cümle yarım**. Maddelerin devamı 232. satırda:
  `LLM-class jobs use a different evidence contract (see ARCHITECTURE §Determinism)`
  — ama bu satır 220-231'deki fail-open maddesinin **alt-satırı** olarak duruyor, yani
  fail-open bloğu determinizm maddesinin **ORTASINA sokulmuş**.
- TR `README.tr.md:97-98` — aynı madde **bir bütün** olarak doğru yazılmış:
  "Determinizm sınıf-tanımlı: deterministik wasm işleri yeniden-koşum-kanıtlı; LLM-sınıfı
  işlerde farklı kanıt-kontratı".
- Sonuç: ikizler aynı garantiyi **farklı yapıda** taşıyor; EN sürümü okunamaz/yanlış anlaşılır.

**O8 — EN'de code-fence (``` ) hatalı eşleme — Türkçe bölüm bash bloğunun içine gömülü**
- `grep -c '^```' README.md` = **16** (düşünce 8 blok, ama eşleme bozuk).
- `README.md:254` ` ```bash ` açılıyor ve **kapanmadan** `README.md:286` ikinci bir ` ```bash ` geliyor.
  CommonMark'da info-string'li fence kapatıcı sayılmaz → 280-318 arası (Türkçe Hızlı Başlangıç
  başlığı + düz-yazı paragrafları + CLI-notu) **bir bash kod bloğunun içinde** kalıyor
  (`README.md:305`'teki ` ``` ` 254'ü kapatıyor).
- Bunun sonucunda `README.md:320-341` "PRODUCTION (AT-208/AT-209)" komut bloğunun
  **açılış fence'i yok** → 320-340 arası komut metin olarak değil düz-yazı olarak render ediliyor.
- TR'de karşılığı yok: `grep -c '^```' README.tr.md` = **8**, dengeli 4 blok.

**O9 — RELEASE sürüm listesi TR'de eksik kuyruk**
- EN `README.md:472`: v0.2.10 → **v0.2.0** (11 sürüm: 0.2.10, .9, .8, .7, .6, .5, .4, .3, .2, .1, .0)
- TR `README.tr.md:141`: 0.2.10 → **0.2.4** (7 sürüm) — **0.2.3, 0.2.2, 0.2.1, 0.2.0 satırları yok**.
  Özellikle TR'nin atladığı 0.2.0 = "FINAL const flip", 0.2.1 = "license fix".
- Ters yönlü fark: TR satır 141'de `CHANGELOG.md` bağı veriyor, EN'de bu bağ **yok** (EN=0, TR=1).

**O10 — Ters yön: TR'nin garanti+kanıt tablosu EN'de YOK**
- TR `README.tr.md:56-69` — "Derin teknik özet — güvenceler (kanıtlarıyla)" başlıklı
  6 satırlık **Güvence | Ne kanıtlar | Kanıt-yeri** tablosu. Kanıt-yeri sütununda
  EN'de hiç geçmeyen izler var: **Audit-17** bayt-kurcalama negatifleri, **Audit-18**
  unicode-fuzz (**NFC/NFD ayrımı**), AT-022 üreteç-determinizmi (çift-koşum bayt-birebir),
  iptal-yolu negatifleri, sahte-damga RED, "1000-event'lik zincir" ölçek notu.
- Ölçüm: `Audit-17` EN=0/TR=1, `Audit-18` EN=0/TR=1, `NFC` EN=0/TR=1.
- EN okuyucusu bu denetim-izlerine ve NFC/NFD gibi gerçek bir saldırı-sınıfına ulaşamıyor.
- TR bu tabloyu README.md:21'in "kanıt-tablolarıyla aynı kapsam" iddiasının dayanağı yapıyor;
  yani iddia tek yönlü işliyor.

**O11 — "The gap is measured, not assumed" (TRM Labs ölçümü) TR'de YOK**
- EN `README.md:31-44` — alt-başlık + **$52.7M** x402 settlement hacmi, yalnız
  **%0,6–7,5**'inin "plausibly agentic" olduğu, aylık **$5.000–$11.000** gerçek ajan-harcaması,
  TRM Labs yapay-alıntı bloğu (38-40) ve "Three independent audits reached the same
  conclusion" (42).
- TR `README.tr.md:24-29` — "Neden var?" bölümü 3 satıra indirgenmiş tek paragraf;
  `TRM`, `52.7` **0 kez** geçiyor (EN'de sırasıyla 2 ve 1 kez).
- Not: EN'nin 8-alt-maddelik pazar-tezi kanıtı TR'de yok; TR yalnız "Mem0/Letta/Zep ·
  ERC-8004 · x402" şemasını koruyor.

**O12 — Kurulum-suz yabancı-doğrulama yolu TR'de YOK**
- EN `README.md:134-141` — "Verify a claim without installing anything":
  `tools/attest_verify_bagimsiz.py` tek-dosya stdlib-Python (keccak256 + RFC 8785 +
  secp256k1 recovery), `curl -sO https://raw.githubusercontent.com/...` satırı ve
  "GREEN rc0 / RED rc1".
- TR: `attest_verify_bagimsiz` **0 kez**. TR'nin 38-41 satırları EN'de olmayan
  `project-head`/`pugio_receiver`/`pugio_ingest`/`epoch-verify` komutlarını içeriyor,
  ama bu "bize güvenmek zorunda değilsin" kanalı yok.

---

## 4. Düşük bulgular (🟡 kelime / bağlantı / nüans)

| # | Konu | EN | TR | Fark |
|---|---|---|---|---|
| **D1** | default-deny garanti detayı | `README.md:76-77`: "no network, no filesystem, no host env; wasmtime v48 on ratified WASI 0.3" | `README.tr.md:51-52`: aynı + "**ağ YETENEK olarak beyan edilirse vekil-tek-kenarından çıkar (RFC-005 beyanlı-egress; her istek kanıt-log'unda)**" | TR daha bilgili; EN'de RFC-005 egress istisnası bu garantide anılmıyor |
| **D2** | QUICKSTART yönlendirmesi | `README.md:132`: "New here? → `docs/QUICKSTART.md` (5-minute setup, `pip install tamga-protocol`)" | yok | TR okuyucusu 5-dakikalık kurulum rehberine README'den ulaşamıyor (`QUICKSTART` EN=1/TR=0) |
| **D3** | Belge tablosu satırları | `README.md:460-485` — 24 satır: DESIGN-PARTNERS (463), VERIFY-EPOCH-ANCHOR (470), AUDIT-GATE (480), DEMO-SCRIPT (481), ERC-8004-MAPPING (482), REPRODUCE… | `README.tr.md:130-145` — 15 satır; bu 5 satır tablo olarak **yok** (TR VERIFY-EPOCH-ANCHOR'u 90, DEMO-SCRIPT'i 113/120, AUDIT-GATE'i 308 düz-metinde veriyor; DESIGN-PARTNERS ve ERC-8004-MAPPING **hiç yok**) | Tablo-kapsamı EN 24 / TR 15; 2 doküman TR'de hiçbir yerde bağlı değil |
| **D4** | TR-rehber bağı | `README.md:478` yalnız `docs/AGENT-GUIDE.md` | `README.tr.md:126` ve `:143` **`docs/AGENT-GUIDE.tr.md`** | Türkçe okuyucu TR-rehbere ulaşıyor; EN README'de TR-rehber bağı yok (tek-yönlü erişim) |
| **D5** | Lisans açıklaması | `README.md:513-514`: "contributors' patents extend to users; anyone filing a patent claim loses the license" | `README.tr.md:319`: sadece `[Apache-2.0](LICENSE)` | Patent-hükmü gerekçesi TR'de yok |
| **D6** | Yol haritası Faz 2 içerik listesi | `README.md:502`: "memory-store adapters, **overhead statement**, design-partner pilot" | `README.tr.md:314`: "adaptörler, tasarım-partner pilotu" | "overhead statement" (Faz-2 çıkış ölçütü, ARCHITECTURE §8 ile bağlı) TR'de düşmüş |
| **D7** | Yol haritası Faz 4 kapı sayımı | `README.md:504`: "zkVM proof layer, governance **(double-gated)**" | `README.tr.md:315`: "protokol v2 (zkVM) — **kapılı**" | TR'de (a) "governance" düşmüş, (b) çift-kapı → tek-kapıya indirgenmiş |

---

## 5. Öncelik sırası (işlem önerisi)

| Sıra | Bulgu | Neden önce | Eylem yönü |
|---|---|---|---|
| 1 | **K1** | Düzeltilememiş güvenlik-kusuru uyarısı Türkçe okuyucuya hiç ulaşmıyor; RFC'lerin kanonik dili Türkçe | TR'ye ekle |
| 2 | **K2** | Yanlış öz-tanım; diğer tüm eksikleri "kasıtlı özet" gibi gösteriyor | TR iddiasını düzelt **veya** K4/K5/O11'i taşı |
| 3 | **K5** | "Guarantee" statüsünde bir yetenek tek dilde ilan ediliyor | TR'ye ekle |
| 4 | **K4** | Uyum-ilgisi (AI Act) + tarihi düzeltme tek dilde | TR'ye ekle |
| 5 | **K3** | EN README kendi dil-kuralını ihlal ediyor | EN: Türkçe blokları `.tr.md`'ye taşı **veya** EN 233 ifadesini dürüstleştir |
| 6 | **O7 / O8** | Render bozukluğunu okuyucu görüyor (madde ortada kesik; ~40 satır yanlış kod-bloğunda) | EN fence eşlemesi + madde sırası |
| 7 | **O1-O5** | Rakamler dört dosyada dört değer; doğrulanabilir tek kaynak `run_all.sh` (242) | Kaynaktan üret, elle yazma |
| 8 | **O10** | EN okuyucusu Audit-17/18 + NFC/NFD kanıt-izlerini göremiyor | EN'ye ekle (ters yön) |
| 9 | **O6, O9, O12** | Eksik bölüm/rozet/sürüm-kuyruğu | İçerik senkronu |
| 10 | **D1-D7** | Bağlantı ve nüans kaybı | İkinci tur |

---

## 6. Doğrulama komutları (rapordaki her sayı üretilmiştir)

```bash
cd "$(git rev-parse --show-toplevel)"

# ARCHITECTURE token-paritesi (boş çıktı = içerik aynı)
grep -oE '[0-9]+([.,][0-9]+)?[ ]?(ms|MiB|%|v[0-9.]+)|v[0-9]+\.[0-9]+\.[0-9]+|[0-9]+-|[a-z_]+\.(py|sh|md|json|tsg|wasm|schema)|[0-9a-f]{8,}' docs/ARCHITECTURE.md | sort > /tmp/en.txt
grep -oE '[0-9]+([.,][0-9]+)?[ ]?(ms|MiB|%|v[0-9.]+)|v[0-9]+\.[0-9]+\.[0-9]+|[0-9]+-|[a-z_]+\.(py|sh|md|json|tsg|wasm|schema)|[0-9a-f]{8,}' docs/ARCHITECTURE.tr.md | sort > /tmp/tr.txt
diff /tmp/en.txt /tmp/tr.txt          # -> boş

# reason-code tablosu
grep -oE '^\| [0-9]+ ' docs/ARCHITECTURE.md  | tr -d '| ' | tr '\n' ' '   # 15 kod
grep -oE '^\| [0-9]+ ' docs/ARCHITECTURE.tr.md | tr -d '| ' | tr '\n' ' ' # aynı 15

# gercek kontrol sayilari (O1-O4'un kaynagi)
grep -cE '^\s*(kontrol|kontrol_skip|kontrol_live|kontrol_req|bekle_red)\b' tests/run_all.sh   # 242
grep -cE '^\s*kontrol_live\b' tests/run_all.sh                                               # 5

# EN->TR eksik bolumler (0 = TR'de hic yok)
for k in TRM "52.7" BrandStrike brandstrike_tsa AT-229 attest_verify_bagimsiz \
         AT-227 fail-open "AI Act" "2024/1689" "December 2027" arXiv QUICKSTART DESIGN-PARTNERS 6962 2332; do
  printf "%-24s EN=%-3s TR=%-3s\n" "$k" "$(grep -ci -- "$k" README.md)" "$(grep -ci -- "$k" README.tr.md)"
done

# TR->EN eksikler
for k in Audit-17 Audit-18 NFC CHANGELOG verify-mini "tamga explain" "good first issue" Apodix; do
  printf "%-20s EN=%-3s TR=%-3s\n" "$k" "$(grep -ci -- "$k" README.md)" "$(grep -ci -- "$k" README.tr.md)"
done

# README.md fence haritasi (O8)
grep -n '^```' README.md      # 254 acik, 286 info-string ile tekrar aciliyor, 305 kapaniyor
grep -c '^```' README.md      # 16  |  grep -c '^```' README.tr.md  -> 8 (dengeli)

# EN icerisindeki Turkce yogunluk (K3)
grep -c '[ışğüöç]' README.md  # 77 / 607 satir

# bayatlik yonu
for f in README.md README.tr.md docs/ARCHITECTURE.md docs/ARCHITECTURE.tr.md; do
  printf "%-26s " "$f"; git log -1 --format='%ad %h' --date=short -- "$f"; done
# README.md 2026-10-05 | README.tr.md 2026-10-02 | ARCHITECTURE.md 2026-09-12 | ARCHITECTURE.tr.md 2026-09-16
```

---

## 7. Kapsam dışı / bilinçli olarak rapor edilmeyenler

- **Başlık ve paragraf yapısı** karşılaştırılmadı; istenen **içerik** uyumsuzluğuydu.
  (ARCHITECTURE'de başlık sayısı EN 12 / TR 11 görünüyor; fark yalnız TR başlığındaki
  çeviri-notundan, içerik başlıkları birebir aynı: 1, 2, 3, 3b, 4, 5, 6, 7, 8, 9, 10.)
- Mermaid diyagramları her iki dilde de **çevrilmemiş** (EN etiketler). Bu bir tutarsızlık
  değil, `ARCHITECTURE.tr.md:1`'deki "teknik-kanıt-dili İngilizce kalır" kuralının gereği.
- `docs/` altındaki diğer ~15 EN/TR ikizi (`TESTS`, `RELATED-WORK`, `REPRODUCE`,
  `RFC-001..009`, `AGENT-GUIDE`, `WHY-HASHCHAIN`, `NODE-DISCOVERY`, …) görev kapsamı
  dışında; yalnızca `TESTS.md:6` O4 için çapraz-kanıt olarak okundu.
- Hiçbir kaynak doküman değiştirilmedi; bu rapor `docs/arastirma/` altına yazılan tek dosyadır.

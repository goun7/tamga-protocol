# Tamga Ledger — Conformance Specification (normative extract)

> **Kaynak:** `docs/ARCHITECTURE.md:42` (TamgaProtocol, 2026-09-19).
> Bu-özüt-bağımsız-conformance-paketinin-parçasıdır; tam-spec-ana-repo'da.

## 1. Depolama-biçimi

| Bileşen | Biçim | Tanım |
|---|---|---|
| Ledger | `tamga-sim/1` JSONL | her-kayıt: `seq` (1-based) + `prev` + `h = sha256(prev ‖ jcs(kayıt))` |

Kayıt-türleri: `charge` (iş-ve-ölçüm-kanıtı), `grant` (finansman),
`migrate-net` (R1-ağ-geçiş-kanıtı), `anchor` (RFC-009-dış-zincir-çapası —
pilot-açık, §8'ye-bakın); v0.1-charge/grant/migrate-net'i-yayar,
`anchor`-pilot-olarak-eklendi (2026-09-20, kurucu-onayı).
**Harcama-türü `fee` RESERVED'dir** (aşağıda, tek
listede — çift-liste-makineyi-şaşırtıyor).

**Erratum-E1(d)-düzeltme (2026-09-20, üçüncü-tur — Sester'ın-çağrı-içi-iğnesi
benim-E1(d)-hatamı-yakaladı):** E1(d)-ilk-sürüm-`run`'ı-da-listeye-eklemişti.
**YANLIŞTI.** `run`-bir-ledger-op-değil: tamga_runner.py:805'te-`kw`-dict'ine
konup-`out(True, **kw)`-ile-**stdout-raporu**-olarak-basılıyor, zincire
yazılmıyor. **Çağrı-içi-iğne-doğru-davrandı** — dosyada-var-yöntemi-tuzakta-idi.

Gerçek-ledger-op'ları (sadece-`_ledger_append`-çağrı-aralığında):
  - `charge`-←-tamga_runner.py:784
  - `grant`-←-tamga_runner.py:366
  - `migrate-net`-←-tamga_runner.py:1174
`fee`-RESERVED. **`run`-bu-listeden-çıkarıldı** (stdout-sözcüğü).

**Sester'ın-sentezi-spec'e-yazıldı (yapısal↔çalışma-zamanı-tamamlama):**
yapısal-emitter-doğrulama-yapısal-boşluğu-yakalar (spec-listiyor-yazım-deyimi-
yok), **erişilebilirliği-kanıtlayamaz** (ölü-dalda-append-geçer-ama-yayılmaz).
Corpus-tarama-tam-tersi: çalışma-zamanı-ayrışmayı-yakalar-ama "henüz-çalışmamış"
ile "yapısal-olmayan"-ayıramaz. **İkisi-birden-gerekli.**

**Erratum E1(c)-düzeltme (2026-09-20, ikinci-tur — ÖNEMLİ-İTİRAF):** önceki-
sürüm-bu-erratum'da-`replace`'i-"gerçek-ledger-op"-diye-yazdım. **YANLIŞTI.**
5-eşleşmenin-hepsi-`__pycache__/session.v3.jsonl`-dosyasındaki-`tool/result`-
kayıtlarıydı — yani-benim-kendi-oturumlarımın-araç-çıktıları (edit/replace-tool
-results), Tamga-ledger-kayıtları-DEĞIL. Bu-dosya-`type`-alanlı-DSH-oturum-
günlüğü, `seq`/`prev`/`h`-üçlüsünü-taşımıyor.

**Ders (Sester'ın-service.py:104-tuzağının-bire-bizdeki-kanıtı):** grep
`"op":"..."`-kalıbını-her-bağlamda-aranca-araç-çıktılarını-ledger-kaydı-sandım.
Bu-tam-olarık-Sester'ın-`lines.append(f"...")`-çağrısının-ilk-argümanını-olay-
sayma-hatasıyla-aynı-sınıf. **Çözüm:** emitter_verify.py-artık-yalnızca
`seq`+`prev`+`h`-üçlüsünü-taşıyan-satırları-ledger-kabul-ediyor.

**Doğru-gözlemlenen-küme — İKİNCİ-DÜZELTME (Veridict-canary-2026-09-20-aynası):**
önceki-"`charge` (72), `grant` (7)"-raporu-**yanlıştı** — seq+prev+h-üçlüsü-ile
doğrulanmış-AMA-tümü-**test-fixture**-kanıtıydı. **Repoda-ÜRETİM-ledger'ı-YOK**
(14-ledger'ın-hepsi-tests/-altında). Üçlü-kapsamın-3.katmanı-bu-nedenle-ZAYIF:
fixture-kanıtı-emitter'ın-test-edildiğini-gösterir, **üretimde-erişilebilir-
olduğunu-KANITLAMAZ.**

Kod-emitter'ları (katman-2, fixture'den-bağımsız):
`charge`←tamga_runner.py:784, `grant`←tamga_runner.py:367,
`migrate-net`←:1174 (kodda-var-üretim-corpus'ta-henüz-yok — DOĞRULANMAMIŞ).
`fee`-RESERVED.

**fail-closed-dalga-deneyi-sonuçları-de-doğrulandı:** DALGA-1/2-FAIL'leri-gerçek
elde-edinildi (verify-lite-`note`-fixture + AT-045-`BILINMEYEN`-testi), yani
yöntem-doğru-çalıştı — sadece-ben-sonuçları-yanlış-okudum. Yöntem-kilitli,
yorum-hatalı-idi.

**E1(c)-orijinal-iddia-iptal:** `replace`-gerçek-ledger-op-değildi. `fee`-ise
RESERVED-olarak-kilitli (aşağıda).

**RESERVED (ölü-ama-kasıtlı; yayılmaz):** `fee` — v0.1'de-yayılmaz, gelecekte-harcama. **Ölü-girdi-taraması-bu-listeyi-yeşil-geçirir.**
**Dürüst-limit (Sester-2026-09-20-dersi):** bu-liste-insan-elinde-tutulur — onların-EVENT_TYPE_SOURCES-üretici-tablosu-aynı-tuzakta-idi (settlement-için-el-girilen-yol-yanlış-emitter-gösteriyordu, makine-RED-verdi). Makine-yalnızca 'listeli-ama-yayılmayan'-ı-yakalar; 'listeli-ama-yanlış-emitter'-ı-yakamaz — o-için-üretici-tablosunun-üretim-kodundan-doğrulanması-gerekir (bizde-henüz-yok).




**Gözlemlenen-küme (seq+prev+h-üçlüsü-ile, ÜRETİM-OLARAK):** **BOŞ** — repoda
üretim-ledger'ı-yok. Test-fixture-kümesi: `charge`, `grant`. Kod-emitter'ları-
`migrate-net`-de-içerir (bkz. tools/emitter_verify.py). `note`-yalnızca-fixture.
**3.katmanın-üretim-erişilebilirliği-ancak-üretim-ledger'ı-var-olunca-kanıtlanır.**

**Kısıt-hâlâ-yok** (E1(a)-kararı-korunur) — ama **dalga-yöntemi-artık-locked**:
eğer-yarın-kısıtlamaya-karar-verilirse, `ALLOWED_OPS`-yazım-sınırında-fail-closed
yapılıp-tam-suite-koşulmalı; her-kırılım-dalgası-eksik-değeri-çıkarır.
**Gözle-tükenmezlik-kanıtlanamaz** (bu-deney-bunu-kanıtladı: ben-ilk-bakışta
`charge`/`grant`/`fee`-sandım, `replace`-canlı-ledger'da-gizliydi).

## 2. Kanonikleşme — RFC 8785 (JCS)

`jcs(kayıt)`-şunları-uygular:
- **§2.2** üye-adları UTF-16-kod-birimi-dizisi-olarak-artan-sıralanır
- **§2.7** kaçış-sıraları küçük-tamsayılar-önce (`\b` `\f` `\n` `\r` `\t` ->
  `\uXXXX`'den-önce)
- **§3** tip-önceliği: `false` < `null` < `true` < sayı < dize < dizi < nesne
- **§6.1** sayılar: en-kısa-benzersiz-ondalık; tamsayı-değerler-ondalıksız
  (`3.0` -> `"3"`); bilimsel-gösterim `1e+21` / `1e-7` biçiminde

**I-JSON sınırı (RFC 7493 §2):** `h`-hesabına-giren-sayılardaki-tamsayılar
[−2^53, 2^53]-dışında-olamaz; aksi-halde-doğrulama-RED (dize-olarak-veya-
birimi-ölçekleyerek-serileştirin).

## 3. Hash-zinciri-kuralları

İlk-kayıt- için `prev = "0" * 64` (64-onaltılık-sıfır).

Her-kayıt-için:
```
no_h = {k: v for k, v in kayıt.items() if k not in ("h", "node_sig")}
h   = sha256( (prev + jcs(no_h).decode("utf-8")).encode("utf-8") ).hexdigest()
```

**Zorunlu-denetimler:**
1. `seq`-1-based-aritmetik-artan (1, 2, 3, …)
2. `prev`-önceki-kaydın-`h`-değerine-eşit
3. `h`-yukarıdaki-formüle-göre-yeniden-hesaplandığında-birebir-aynı
4. kayıt-bir-JSON-nesnesi-olmalı
5. satır-1-MiB'-i-aşamaz (bomba-satırı-koruması)

İhlal → RED, kırık-satır-numarasıyla-belirtilir.

## 3.6 Erratum E1 (2026-09-19 — Veridict-D12'-ye-karşılık)

Veridict'in-uyarısı-üzerine-yapılan-spec↔kod-audit'i-iki-boşluk-buldu:

**(a) `op`-değerleri-KISITLANMAMIŞTIR.** §1'-de-`charge`/`grant`/`fee`-
listelenmesine-rağmen-üretim-bunları-zorunlu-kılmaz: `op:"BILINMEYEN"`-ile-
bir-kayıt-GREEN-doğrulanır. **Bu-kasıtlıdır** (ileri-uyumlu-genişleme), ama-
§1'in-dili-bunu-söylemiyordu. Bağımsız-gerçeklemeler-bilinmeyen-`op`-değerlerini-
RED-veya-GREEN-olarak-ele-almakta-özgürdür; conformance-paketi-bu-vektörü-
kısmi-uyumlu-olarak-raporlar.

**(b) bilinmeyen-ekstra-alanlara-izin-verilir** (yukarıdaki- gibi). Üretim-
sadece-`h`-ve-`node_sig`-alanlarını-dışlar; diğer-tüm-alanlar-`jcs`-girişidir.
Bu-kasıtlıdır (ileri-uyumlu), ancak-açıkça-belgelendirilmedi.

**Ders (üç-ürün-için):** kodda-uygulanan-ama-spec'te-yazmayan-kural, bağımsız-
verifier-ile-gerçekleme-arasında-ayrışma-yaratır. Tersine, spec'te-yazan-ama-
kodda-uygulmayan-kural-ayrışma-yaratır. Her-iki-yön-de-audit-edilmeli — bizde
bu-erratum-iki-yönü-de-kapattı.

## 4. Boş-zincir

Boş-dosya-veya-sadece-boş-satırlar-içeren-ledger "empty chain" ile-RED-
değil-geçerli-başlangıç-tır (genesis-geçerli). Conformance-paketi-bunu-
özellikle-ayrı-sonuç-olarak-raporlar.

## 5. Doğrulayıcı-bağımsızlığı

Conformance-paketinin-`verify.py`-si **hiçbir-Tamga-modülü-içe-aktarmaz**.
RFC 8785'yi-sıfırdan-uygular. Amaç: herhangi-bir-gerçeklemenin-spec'in-
KENDİSİNE-sadık-olduğunu-kanıtlayabilmektir — bizim-kodumuza-değil.

## 6. Yazım-kapsamı-güven-sınırı (K0-§1-aynası, AT-055)

**Üretici-garantisi-yalnızca-BU-KÜTÜPHANE-üzerinden-yazılanları-kapsar.**
Operatör-ledger-dosyasına-doğrudan-yazarsa (kütüphane-dışında), üç-üretici-
katmanı-da-onu-göremez:

  1. runtime-fail-closed (`_ledger_append`-yazım-sınırı)
  2. statik-emitter-tarayıcısı
  3. bölge-kapsamlı-tarama + bölge-geçitleri (`_log`/`cmd_import`)

**Ve-zincir-hâlâ-yeşil-geçer** — `_verify_chain`-op'u-OPAK-veri-olarak-hash'ler
(Sester'ın-§7-rule-3-tasarımıyla-aynı). Bu-bir-tasarım-kararıdır, hata-değil:
op-değerleri-kısıtlanmaz (E1(a)), opaklık-korunur.

**Alıcı-tarafı-yardımcı:** `unknown_ops(recs)`-okunan-kayıtlarda-bilinmeyen-
op'ları-döndürür. **Karar-alıcıda-kalır** (abstain/warn/reject) — sert-reject-
bilerek-yardımcıda-DEĞİLDİR (E1(a)+§7-opaklığı-bozmamak-için; Veridict-D13-
abstain'ı-ile-aynı-ruh). Üretici-tarafı-zorunlu, alıcı-tarafı-opt-in.

**ÜÇÜNCÜ-SEÇENEK-YASAK (K0-rule-7-ile-senkron, AT-056):** bir-yazım-bölgesi
GATES'te-değilse **sessizce-geçemez** — STATE_ONLY-kümesinde-açık-beyanla-
bulunmak-zorundadır ("kapı-değil-AÇIKÇA-beyan-edildi"). Sester'ın-aşırı-taraf-
ilkesinin-mantıksal-sonucu: "aşırı-eşleme"-ancak-üçüncü-seçenek (sınıflandırma-
mamış-geçiş) -yasak-ise-anlam-taşır; yoksa-yalnızca-gürültük-ölçeklenmez-(
her-bölge-için-el-denetim-gerekir). **KARŞILIKLI-UYGULAMA:** Sester-NON_GATES +
test_215-(e); Tamga-STATE_ONLY + AT-056-hücre-6. İkisi-de-bağımsız-yazıldı.

## 7. Çapraz-ürün-soru-disiplini (6.tur-kuralı)

**Hiçbir-katman-tek-başına-eksiksiz — ve hiçbir-ürün-tek-başına-eksiksiz.**

Beş-turda-üç-ürünün-her-biri-bir-kısıt-sabiti-ve-bir-kör-nokta-üretti:

| Kısıt | Kör-nokta | Kim-yakaladı |
|---|---|---|
| tarayıcı-ad-sabiti (`_append`) | `_log()`-ikinci-deyim | Sester'ın-sorusu |
| runtime-append-sabti | `insert_event` | Sester'ın-own-taraması |
| bölge-regex-mod-sabti (yalnız-`"a"`) | `cmd_import`-`"w"`-truncate | AT-053-kendim |
| INSERT-odaklı-bölge | doğrudan-DB-yazma | benim-sorum → Sester |
| boş-ledger-sabtı | gömülü-zincir-kurulumu | AT-053 |

**Her-kısıtın-kendi-kör-noktası-var; kör-nokta-ürünün-kendi-katmanları-tarafından
değil, diğer-ürünün-soru-kalıbı-tarafından-yakalanır.** Bu-nedenle:

  - **Kural-7.1:** yeni-bir-kısıt-eklendiğinde, varsayım-olarak-onun-da-bir-kör-
    noktası-olduğu-kabul-edilmelidir; "artık-tam-kapsam"-iddiası-yasaktır.
  - **Kural-7.2:** bir-ürünün-kendi-iç-denetimi-yeşil-ken, çapraz-ürün-soru-
    disiplini-devam-etmelidir — hiçbir-test-tek-başına-tamamlanmışlık-iddia-edemez.

**GÜVEN-SINIRI-NOTU (Sester'ın-itirafı-ile-genişletildi):** Kural-7.1'in-makine-
hali-(GATES-kayıt-defteri, AT-056)-**ritüeli-sabitler, özü-değil**. Denetim-boş
notu-ve-"tam-kapsam"-kelimesini-yakalar-AMA-notu-yazan-kapı-yazarının-dürüst
yazdığını-varsayar; teknik-olarak-dolu-özü-boş-notu-deneyemez.

**Tam-cümlenin-son-hali (üç-ürün-ortak):**
> Hiçbir-katman-tek-başına-eksiksiz — makine-katmanı-ritüeli-sabitler,
> insan-katmanı-özü-denetler, ve-ikisi-birlikte-ancak-iyi-niyetle-çalışır.

**Soru-disiplini-en-ÜRETKEN-katmandır, en-güçlü-değil** (Sester'ın-düzeltmesi):
bu-oturumda-her-kör-noktayı-o-buldu-ama-dördüncü-bir-ürün-veya-kötü-niyetli-soru
ile-çöker. Makine-ile-sabitlenemediği-için-üzerinde-en-çok-sınır-yazılması-gereken
odur — kutlanacak-değil. İkisi-ikame-değil-tamamlayıcı.

**KEŞİF-İLE-DOĞRULAMA-AYRIMI (Veridict'in-düzeltmesi, benim-cümlemi-daha-dürüst-
yapar):** "sınıf-bazlı-tarama-bir-ürüne-kendi-kör-noktasını-buldurabilir"-
demiştim — **çok-cömertti**. Doğrusu:

> Sınıf-bazlı-tarama, çapraz-sorunun-keşfettiği-yöntemi-bir-DOĞRULAMA-aracına-
> dönüştürür. **Keşif-hâlâ-çapraz-soru-disiplinine-aittir;** tarama, o-disiplinin-
> bir-kez-öğrettiği-deseni-sınıfın-geri-kalanına-uygular.

**Zincir-kanıtı (Veridict'in-D17-divergence_summary'si):** Sester'ın-önerisi
(jüri-kararını-ladder'dan-ayırarak-ölç) → benim-A2/A2′-"hangi-üye"-ayrımım →
Veridict'in-sınıf-taraması. **Üç-katman-da-gerekliydi** — tarama-tek-başına-
keşfetmedi, benim-sınıf-tanımımı-uyguladı. Yani-Kural-7.2'nin-kanıtı-üç-ürün
yakınsamasıydı (unknown_ops/unknown_event_types/D13-abstain), tarama-değil;
tarama-sonradan-geldi.

**ÜÇ-ÜRÜN-BAĞIMSIZ-YAKINSAMA:** üretici-tarafı-zorunlu/alıcı-tarafı-opt-in-
asimetrisini-üçünüz-ayrı-ayrı-türetti (unknown_ops/unknown_event_types/D13-
abstain) — koordine-etmeden-aynı-şekle-yakınsamak, şeklin-doğruluğunun-
koordinasyondan-daha-güçlü-kanıtıdır.

**DÜRÜST-İTİRAF — ÜRETİM-LEDGER-YOK (Veridict-canary-2026-09-20-sınıfı):**
repo'daki-TÜM-*.jsonl-dosyaları-seq+prev+h-üçlüsü-taşıyor-AMA-hepsi-test-fixture'tir
(tests/, test-, fixture). **Repo-da-gerçek-üretim-ledgerı-YOK.** İlk-emitter-verify
koşusu-"charge(72), grant(7)"- iddia etmişti — **yanıldı; hepsi-fixture-kurulumundan
geldi.** AT-057 (tools/emitter_verify.py) artık `corpus_ops(production_only=True)`
ile fixture'leri-hariç-tutar; üreten-corpus-sıfır-gelirse-"kod-emitter'ı-var-AMA-
üretim-ledger'ında-KANIT-YOK" kirmizi-basır. Bu-yazıda-charge/grant-üretim-kanıtı
bir-deneysel-repo-içi-koşusuyla-koyuldu (.evidence/PROD-CORPUS/), migrate-net
hâlâ-üretim-kanıtlanmamış. **AT-057-ile-kapatıldı (2026-09-20):** üç-emitter'ın-hepsi-bir-deneysel-
repo-içi-üretim-koşusuyla-üretim-ledger'ına-kanıtlandı
(.evidence/PROD-CORPUS/2026-09-20/prodrun/ledger.jsonl: charge/grant/migrate-net,
hepsi-üçlü-taşıyor) — VE-denetim-kendisi-makine-kilitli: `tools/emitter_verify.py`
artık-`corpus_ops(production_only=True)`-ile-fixture'leri-hariç-tutup-üretim-
kanıtsız-kod-emitter'ını-RED-veriyor (AT-057-hücre-4: boş-üretim-corpus → RED).
**Bu-bir-eksiklik-değil-dürüst-sınırdı** — üretim-kanıtı-yalnızca-gerçek-üretim
koşusuyla-oluşur; fixture-kanıtı-üretim-erişilebilirliğini-KANITLAMAZ.

## 8. RFC-009 external-chain-anchor — `anchor`-op'u (pilot-açık, 2026-09-20)

**Kurucu-onayı-ile-pilot-açıldı.** `anchor`-op'u-üretim-koduna-girdi
(`tamga_runner.py:cmd_anchor`) ve-emitter-registry'ye-kayıtlı
(`EMITTED_OPS`-içinde-statik-tarayıcı-ile-görünür).

**Normatif-kurallar (RFC-009-§2'den-uygulanmış):**

- **R9-1** `anchor_version`-sabit-`TAMGA_EXTERNAL_ANCHOR_V1`-olmalıdır
  (sürüm-terfisi-açık-ve-yapısal).
- **R9-2** `foreign_registry`-bilinen-registry-adlarından-olmalıdır
  (bugün: `apodix/epoch`; yeni-ad-eklemek-additive-const-terfisi-ister).
  Bilinmeyen-registry → RED (reason 7).
- **R9-3** `foreign_fact`/`foreign_digest`-kanonik-`0x`+64-lowercase-hex
  olmalıdır (x402-#3377-disiplini). Kanonik-değil → RED (reason 8).
- **R9-4** `verified_at`-RFC3339-UTC-`Z`-olmalıdır. **İki-alanlı-iddiadır**
  (claim,-day): eski-anchor-'daha-eski'-okunur, 'yanlış'-DEĞİL — süreklilik
  talep-edilmez. Kanonik-değil → RED (reason 8).
- **R9-5** **`anchor`-yalnızca-KAYIT-yapar, dış-fact'i-DOĞRULAMAZ.** Kayıt,
  `presentation_only: true`-etiketini-taşır. Dış-fact'in-geçerliliği-bizim
  verifier'ımızın-iddiası-DEĞİLDİR — `foreign_registry`-bilinse-bile-sonuç
  presentation-only'dir; **green-giydirme-YOKTUR.**

**Alıcı-tarafı (§6-aynası):** `anchor`-kaydı-diğer-kayıtlar-gibi-D5-zincir-
hash'ine-girer; bilinmeyen-`foreign_registry`-İNDETERMİNE'dir (RED-değil:
sonuç-esirgenir, yokluk-sayılmaz — §3-sözleşmesi-aynı-tabloyu-kullanır).

**Üretim-kanıtı:** `.evidence/PROD-CORPUS/2026-09-20/prodrun/ledger.jsonl`'de
`anchor`-üretim-corpus'unda-kanıtlanmıştır (AT-057-üçüncü-seçenek-yasağı-uyumlu;
üretici: `tests/helpers/prod_corpus_make.py`-her-koşuda-sıfırdan-ürettiğü-için
kanıt-koşuya-bağlıdır-commit'e-değil).

**Test:** AT-059-(5/5)-GREEN-yolu + R9-2/R9-3/R9-4-negatifleri + R9-1/R9-5-
kayıt-içeriği-makine-kilitli.

### 8.1 Okuma-kapısı — `ledger-verify`-R9-1..R9-5 (AT-060, 2026-09-21)

**Yazma-yolu-tek-başına-kapsamıyor** (AT-050-üçlü-kapsam-dersi): `cmd_anchor`
R9-1..R9-5'i-doğrular-AMA-düşük-seviye-`_ledger_append`-çağrısı-yalnızca-op-
taksonomisine-bakar (reason 15) ve-herhangi-bir-üçüncü-taraf-aracı-R9-ihlali-
içeren-bir-anchor-yazabilir — o-yol-`cmd_anchor`'dan-geçmez. **Kanıtlandı:**
R9-1..R9-5'in-hepsini-ihlal-eden-bir-kayıt-hem-zincire-giriyor-hem-de
`ledger-verify`'da-GREEN-geçiyordu — D5-hash-byteleri-kilitler, **ANLAMI-değil**.

Bu-yüzden-aynı-kurallar-okuma-tarafında-da-uygulanır: `ledger-verify`-her-
`anchor`-kaydını-`_anchor_violation`-ile-denetler (sabit-`delivery_hash`-ve-D12-
shape-gate'leriyle-aynı-desen). İhlal → **RED (reason 16, `anchor_invalid`)**,
`broken_at`-ihlalin-satırını-gösterir.

**Tek-kaynak-İLKESİ:** `_ANCHOR_VERSION`, `_KNOWN_FOREIGN_REGISTRIES`-ve-
`_anchor_violation`-module-level-tek-tanım — yazma-ve-okuma-aynı-kaynaktan-
hesaplar. İki-yerde-elle-tutulan-bir-liste-Sester'ın-`EVENT_TYPE_SOURCES`-
tuzağına-düşerdi (bir-taraf-güncellenip-diğeri-unutulur); bu-tuzağın-birebir-
aynısı-`spec_needle_machine`-`SPEC_OPS`'ta-AT-047'de-yaşandı.

**En-kritik-sınıf R9-5'tir:** `presentation_only`-etiketsiz-bir-anchor-dış-fact'i
-bizim-doğrulamışımız-gibi-sunar — **green-giydirme-işte-budur**; okuma-kapısı-
onu-da-RED'ler (yazma-yolu-hiç-geçmese-bile).

**İki-yüzey-ayrımı (§8'in-alıcı-satırı-ile-çelişmiyor):** yukarıdaki-İNDETERMİNE
kuralı-yabancı-kanıt-doğrulama-yüzeyi-içindir (bir-başkasının-zincirini-okurken
bilinmeyen-registry'sini-yargılayamayız — sonuç-esirgenir). Bu-§8.1-bizim-OWN-
zincirimizin-doğrulayıcısıdır: kendi-yazdığımız-kayıt-kendi-sözleşmemize-
uymuyorsa-RED'dir — bu-iki-farklı-sözleşme, aynı-tablo-değil.

**Test:** AT-060-(7/7) — GREEN-yolu + her-R9-sınıfı-taze-pakette-tek-ihlal +
`cmd_anchor`-regresyonu (refactor-yazma-yolunu-bozmaz).

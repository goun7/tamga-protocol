# Tamga Ledger — Conformance Specification (normative extract)

> **Kaynak:** `docs/ARCHITECTURE.md:42` (TamgaProtocol, 2026-09-19).
> Bu-özüt-bağımsız-conformance-paketinin-parçasıdır; tam-spec-ana-repo'da.

## 1. Depolama-biçimi

| Bileşen | Biçim | Tanım |
|---|---|---|
| Ledger | `tamga-sim/1` JSONL | her-kayıt: `seq` (1-based) + `prev` + `h = sha256(prev ‖ jcs(kayıt))` |

Kayıt-türleri: `charge` (iş-ve-ölçüm-kanıtı), `grant` (finansman),
`migrate-net` (R1-ağ-geçiş-kanıtı); v0.1-bunları-yayar.
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

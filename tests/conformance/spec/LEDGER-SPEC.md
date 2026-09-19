# Tamga Ledger — Conformance Specification (normative extract)

> **Kaynak:** `docs/ARCHITECTURE.md:42` (TamgaProtocol, 2026-09-19).
> Bu-özüt-bağımsız-conformance-paketinin-parçasıdır; tam-spec-ana-repo'da.

## 1. Depolama-biçimi

| Bileşen | Biçim | Tanım |
|---|---|---|
| Ledger | `tamga-sim/1` JSONL | her-kayıt: `seq` (1-based) + `prev` + `h = sha256(prev ‖ jcs(kayıt))` |

Kayıt-türleri: `charge` (iş-ve-ölçüm-kanıtı), `grant` (finansman), `fee`
(harcama — ayrılmış; v0.1 yalnız `charge` ve `grant` yayar).

**Erratum E1(c) (2026-09-20 — Sester-K0.2-yöntemi-ile-bulundu):** §1'in
listesi-yanlıştı. **fail-closed-dalga-deneyi** (kısıt-ekle → tam-suite-koş →
kırılım-eksik-değeri-yüzeye-vur) iki-eksik-değer-çıkardı:

- **`replace`-GERÇEK-LEDGER-OP'dur** — `__pycache__/session.v3.jsonl`-canlı-
  oturum-ledger'ında-5-kayıtta-var; spec'te-listeli-değildi. **Tam-Sester-K0.2
  sınıfı:** meşru-üretim-olayı-spec-dışı-ilan-ediliyordu.
- **`fee`-listeli-ama-hiç-kullanılmıyor** (corpus'ta-0-kayıt) — either-way-
  tutarsızlık.

**Gözlemlenen-küme (empirik, kod+jsonl+fixture-taraması):** `charge`, `grant`,
`replace` — artı `note` (yalnızca `tools/verify_lite.py`-fixture'ında).

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

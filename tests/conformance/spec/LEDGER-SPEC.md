# Tamga Ledger — Conformance Specification (normative extract)

> **Kaynak:** `docs/ARCHITECTURE.md:42` (TamgaProtocol, 2026-09-19).
> Bu-özüt-bağımsız-conformance-paketinin-parçasıdır; tam-spec-ana-repo'da.

## 1. Depolama-biçimi

| Bileşen | Biçim | Tanım |
|---|---|---|
| Ledger | `tamga-sim/1` JSONL | her-kayıt: `seq` (1-based) + `prev` + `h = sha256(prev ‖ jcs(kayıt))` |

Kayıt-türleri: `charge` (iş-ve-ölçüm-kanıtı), `grant` (finansman), `fee`
(harcama — ayrılmış; v0.1 yalnız `charge` ve `grant` yayar).

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

## 4. Boş-zincir

Boş-dosya-veya-sadece-boş-satırlar-içeren-ledger "empty chain" ile-RED-
değil-geçerli-başlangıç-tır (genesis-geçerli). Conformance-paketi-bunu-
özellikle-ayrı-sonuç-olarak-raporlar.

## 5. Doğrulayıcı-bağımsızlığı

Conformance-paketinin-`verify.py`-si **hiçbir-Tamga-modülü-içe-aktarmaz**.
RFC 8785'yi-sıfırdan-uygular. Amaç: herhangi-bir-gerçeklemenin-spec'in-
KENDİSİNE-sadık-olduğunu-kanıtlayabilmektir — bizim-kodumuza-değil.

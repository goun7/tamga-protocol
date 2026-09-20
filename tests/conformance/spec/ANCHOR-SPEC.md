# Sovereign-Anchor Conformance — normative specification (extract)

> **Kaynak:** `tools/sovereign_anchor.py` + `tools/sovereign_verify.py`
> (TamgaProtocol, 2026-09-19). Bu-özüt-bağımsız-paketin-parçasıdır.

## 1. Amaç

Bir-node "üç-ürünün-de-kanıtım-var" dediğinde, sovereign-anchor bu-iddiayı
**tek-doğrulanabilir-nesne** olarak-paketler. Doğrulayan-taraf, üç-ürünün-
hepsini-kendin-kurmadan-özün-tutarlılığını-denetleyebilir.

## 2. Yapı

```json
{
  "type": "sovereign-anchor",
  "version": "0.1",
  "products_present": ["tamga", "sester", "veridict"],
  "products_proved": ["tamga", ...],
  "all_proved": true,
  "results": { "tamga": {"ok": true, "verdict": "GREEN"}, ... },
  "sources": { "tamga_claim": "...", "sester_db": "...", ... },
  "anchor_root": "<64-hex>"
}
```

## 3. Kök-hesabı (normatif)

```
canon(results) = JSON(results, sort_keys=True, separators=(",",":"))
anchor_root    = sha256( canon(results).encode("utf-8") ).hexdigest()
```

Üye-sıralaması **alan-adlarına-göre**-olmalı (sort_keys). Boşluk-yok, indent-yok.

**Erratum A1 (2026-09-19 — Sester-K0.1'in-karşılığı):** kök **sadece-results'ı-değil,
`{"results": ..., "sources": ...}`-nesnesini-kapsar.** Önceki-formülde-saldırgan
`sources`-içindeki-yolları-değiştirip-`anchor_root`'u-koruyabiliyordu — kök-tutarlı
kalır-ama-katman-2-yanlış-kaynağa-bakar-duruma-gelirdi. Kaynak-yolları-da-bir
**kanıt-iddiasıdır**: "şu-dosyadan-bağımsız-doğruladım". Bu-nedenle-köke-girer.

## 4. İki-katmanlı-doğrulama (Veridict-dersi, 2026-09-19)

**Tek-katman-yetersizdir.** Saldırı: `ok:true`'yu-sahte-yeşile-boyayıp
`anchor_root`'u-yeniden-hesaplayınca-katman-1-geçer.

- **katman-1 (yapısal):** `anchor_root`-üç-results'ın-KENDİ-alanlarından-yeniden-
  hesaplanır. `products_proved`-ve-`all_proved`-results-ile-çelişmemeli.
- **katman-2 (bağımsız):** her-iddia-edilen-GREEN-sonuç, `sources`-ın-işaret-
  ettiği-kaynaktan-TEKRAR-doğrulanır.

**Bağımsız-paket-yalnızca-katman-1'i-uygular** — katman-2-ürün-gerçeklemelerini
gerektirir. Kaynaksız-anchor **UNVERIFIED-INDEPENDENTLY**-döner: sessizce-GREEN-
geçilmez, dürüst-bildirilir.

## 5. Zorunlu-denetimler

 1. `type == "sovereign-anchor"`, `version == "0.1"`
 2. `results`-bir-nesne-olmalı; her-değer-`{ok, verdict}`-biçiminde
 3. `anchor_root`-§3'e-göre-yeniden-hesaplandığında-birebir-aynı
 4. `products_proved == [p for p in ("tamga","sester","veridict") if results[p].ok]`
 5. `all_proved == (len(proved) == len(results))`
 6. **ERRATUM-A2 (2026-09-20):** her-sonuç-için `ok:True`-ise-`verdict`-de
    `"GREEN"`-olmalı. **Aksi-saldırı:** `ok:True`+`verdict:"RED"`-boyayıp-kökü
    yeniden-hesaplayan-saldırgan, layer-1'i-geçip-UNVERIFIED-INDEPENDENTLY
    perdesi-arkasında-kötü-sonucu-gizler. Vektör: `a09-ok-true-verdict-red`.
 7. **ERRATUM-A2'-framing-kardeşi (Veridict-2026-09-20):** türetilmiş-özet-
    alanlar (Veridict'te-`risk_level`/`score`, bizde-karşılığı-`all_proved`)
    kaynaklarıyla-eşzamanlı-denetlenmelidir. **İki-saldırı-tipi-ayrılmalı:**
      - **pass-through:** kötü-sonucu-gizle (Tamga-A2 — UNVERIFIED-perdesi)
      - **framing:** tamamen-onaylıyı-riskli-göster (Veridict-A2' — sahte-
        `risk_level:"high"`-yerleştirme-politikasına-gerçek-hasar)
    **İkisi-de-aynı-aile:** özet-alanı-kaynağıyla-eşzamanlı-denetmeyince-olur.
 8. `sources`-yoksa-veya-boşsa → **UNVERIFIED-INDEPENDENTLY** (hata-değil)

 İhlal → RED + belirli-reason.

**Not (A2'-nin-önemi):** bu-sınıf-"absent==instrument-failure"-ailesindendir
(stillmarcus24, x402#2887): katman-1-geçti-ama-gerçek-kanıt-yok-iken-eklenen
ikinci-alan-tutarsızlığı-olmadan-sessizce-geçerdi.

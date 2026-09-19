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

Üye-sıralaması **alan-adlarına-gre**-olmalı (sort_keys). Boşluk-yok, indent-yok.

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
6. `sources`-yoksa-veya-boşsa → **UNVERIFIED-INDEPENDENTLY** (hata-değil)

İhlal → RED + belirli-reason.

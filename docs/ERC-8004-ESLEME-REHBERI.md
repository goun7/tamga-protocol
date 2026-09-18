# ERC-8004 ↔ Tamga eşleme-rehberi (arayüz-dokümanı)

Durum: **arayüz-rehberi** — kod-değil. P9-beklerken-yazıldı (hazırlık).
**K17.3-doğrulama:** ERC-8004-şema-adları burada `docs/ERC-8004-MAPPING.md`'den
ve-yol-haritası-Faz-3-notundan-alınır; hepsi-2026-09-05-veya-öncesi-tarihli-
kaynaklar. **ERC-8004 hâlâ-Draft'tir** — bu-rehber-bir-taahhüt-değil, eşlemedir.

## Amaç

Faz-3-node-ağı-kurulurken Tamga-manifest'i **ERC-8004-kayıt-sözleşmeleriyle**
nasıl-eşlenir — somut-alan-alan, hangi-alanın-ne-zaman-dolduğu-ile.

## Eşleme-tablosu

| ERC-8004-kayıt-alanı | Tamga-kaynağı | Ne-zaman-dolar |
|---|---|---|
| `type: #registration-v1` | `tamga.json`-manifest-package.name | v0'dan-beri |
| `x402Support` | `false` (v0) | **Faz-3-x402-kararı-sonrası** → `true` |
| `supportedTrust: crypto-economic` | node-cosign (L0/L1-merdiven) | v0.2.11'den-beri |
| `supportedTrust: tee-attestation` | — | **Faz-3-TEE-pilot** (Nitro/SEV-SNP) |
| `supportedTrust: reputation` | ERC-8004-Reputation-Registry | **Faz-3** |

## Tasarım-ilkeleri

**1. Bildirimsel-uyumluluk (honesty-first):** v0-yalnızca-L0'i-destekler-ve
`supportedTrust`-alanı **boş-bırakır** (desteklemediği-şeyi-beyan-etmez). Bu,
ERC-8004'nin-opsiyonel-alan-felsefesiyle-aynı: **boşluk-bir-iddia-değil, bir
eksiklik-beyanıdır.**

**2. Tek-yönlü-bağlama:** Tamga-manifest → ERC-8004-kayıt yönünde-akar.
Geri-yön (kayıttan-manifest'e-türetme) **yok** — çünkü-kayıt-herkese-açık-ken,
manifest-protokol-kanıtı-taşır; geri-türetme-kanıtı-üretmez.

**3. Şema-donukluğu:** `registration-v1`-sürümü-sabittir; Tamga-tarafında
RFC-001-manifest-sürümü-ayrı-sürümlenir. İkisi-arasında **çeviri-katmanı**
(Faz-3-iş) — bu-rehber-onun-spec'ıdır.

## K17.3-doğrulama-notu

- `registration-v1`/`x402Support`/`supportedTrust`-adları: `docs/ERC-8004-
  MAPPING.md`-satır-11/45/47 (2026-09-05-öncesi-kaynak)
- ERC-8004'nin-Draft-durumu: yol-haritası-Faz-3-notu (2026-09-05-teyidi)
- **Dış-davranış-iddia-sıfır** — bu-bizim-tasarımımızın-ERC-8004'ün-
  opsiyonel-alanlarına-eşlemesidir

## Ne-zaman-kodlanır

Faz-3-başlangıcı (P9-sonrası). O-ana-kadar-bu-rehber-bir-arayüz-taahhüdü-
değil; **ERC-8004-Draft-değişirse-bu-rehber-de-değişir** — sessiz-değil,
buradan-izlenir.

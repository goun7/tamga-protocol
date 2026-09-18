# AT-002 — node-keşif test-ailesi: tasarım-taslağı (Faz-3-ön-iş)

Durum: **TASLAK** — P9-dolmadan-koşulamaz (Faz-3-ailesi). Bu-belge P9-
beklerken-yazıldı; **çöp-riski-açıkça-kabul** (K20-seçenek-3-değil, bekleme-
sırası-hazırlık). K17.3-gereği: burada-ERC-8004-şemaları-haricinde-dış-iddia-
yoktur; hepsi-bizim-tasarımımız.

## Amaç

Faz-3'ün-ilk-test-ailesi: bir-yabancı-node'un **keşif-ve-doğrulama**
yolçapını-ölçer. P9-dolduğunda "node-ağı-çalışıyor"-iddiası-ölçülebilir-kanıtla-
sunulmuş-olsun.

## Test-ailesi (6-denek)

**AT-002a — manifest-keşif:** node, `registration-v1`-şemasındaki
`x402Support`+`supportedTrust`-alanlarını-okuyor; yanlış-şema-RED (reason-code-
ile). Kanıt: geçerli/eksik/bozuk-şema-üçlüsü.

**AT-002b — kimlik-çapası:** ERC-721-Identity-Registry-token'ı-ile-node-kimliği
bağlanıyor; token-sahibi-olmayan-node-kimliği-RED. Kanıt: sahte-token-red.

**AT-002c — itibar-bağlama:** Reputation-Registry-kaydı-node-kimliğine-bağlı;
başka-node'un-itibarı-RED (identity-mismatch). Kanıt: cross-node-karışma.

**AT-002d — Tamga-makbuz-uyumluluğu:** keşfedilen-node'un-charge-kaydı
Tamga-verify-mini-ile-bağımsız-doğrulanıyor (stdlib-only). **Bu-bizim-
primitif'imizin-ağdaki-yeridir** — P8'in-node-versiyonu.

**AT-002e — kâr-solucanğı (K10):** simülasyon, λ≥2000-iş/ay/node-eşiği-altında
node-geliri<node-maliyeti → **I4-alım-kapısı-açık-kalır** (founder-taşır).
Kanıt: ekonomi-simülasyonu, ponzi-testi-§1-5-uygulandı.

**AT-002f — kill-kontrol:** K20-karar-noktası-çalıştığında-bu-aile-otomatik-
devre-dışı-kalır-mı (sadeleşme-seçilirse). Kanıt: aile-çekme-provası.

## K17.3-doğrulama-notu

Bu-belgede **dış-iddia-yok** — ERC-8004-şema-adları (registration-v1,
x402Support, supportedTrust) haricinde-hepsi-bizim-tasarımımız. ERC-8004-
adlarının-doğrulaması: `docs/ERC-8004-MAPPING.md`-ve-`docs/ERC-8004-EŞLEME-
REHBERI.md`-içinde (orada-kaynak-koda-karşı-denetlenmiş).

## Ne-zaman-koşulur

P9-dolduğunda-ve-Faz-3-başladığında. **O-ana-kadar-bu-taslak-kanıt-değil.**
Taslak-ölçütü: P9-dolduğunda AT-002a-f-6/6-yeşil-olmalı; değilse-taslak-
yanlış-demektir (taslak-ısmarlama-değil, yanlış-yön-beliert).

# Vendored test vectors — capacity-attest@0.6.0

Alındı: 2026-09-15, npm-global kurulumundan `dist/discovery-fixture.js` ÇALIŞTIRILARAK
(fixture-çıktıları + ethers-tabanlı `verifyClaim` referans-hükmü bu makinede üretildi;
vektörlerin-kendisi fixture'ın SABİT-açık-anahtarlarından-türetilir — deterministik, ağ-yok).

Neden-vendored: AT-030 bağımsız-koşum-kuralı — hakem, yarışan-tarafların-ikisi-de olmamalı;
onların-kütüphanesi referans-hükmü verir, BİZİM doğrulayıcımız (stdlib-only, ethers YOK)
aynı-hükmü-kendi-başına-üretmek-zorundadır. CR cross-proof (tests/vendor-cr) deseni.

Lisans: MIT (paketteki LICENSE). Sabit-özeti (sha256): golden-vectors.json = 1f88e843545e6be640eadea4df8b470fe5d04dd1b47a32c4cc753341e22a8ddd

Ek: production-claim.jsonl = holistis/tokenizen data-selftest/claims.jsonl BİREBİR kopyası
(gerçek üretim claim'i; GitHub raw 2026-09-15; sha256 2c6292a296a5d9feef4ea2f301968523488f0a95621fc4a94ce770b66f38cf5c). AT-030 bunu referans-hükmü-OLMADAN
kendi-doğrulayıcımızla doğrular (GREEN + recovered-signer==buyer).

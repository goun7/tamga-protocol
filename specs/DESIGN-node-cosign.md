# TASARIM NOTU — node-cosign: Gömülü Zincirde Node Sertifikasyonu

- **Durum:** ÖN-TASARIM (Faz 2 ilk işi adayı). Bu belge RFC-003'ü DEĞİŞTİRMEZ; RFC-003
  Açık Soru 4'ün (Audit-7 F25) tasarım materyalidir. Karar RFC-003 v0.2 revizyonunda
  normatifleşir ve **kurucu onayı ister** (donma kapısı).
- **Yazar/kaynak:** otonom tur, Audit-7 (SECURITY-AUDIT.md F25; kanit/GUVENLIK/2026-09-05/audit-7.log).
- **Tarih:** 2026-09-05

## 1. Sorun (F25'in kısa formülü)

Snapshot gövdesindeki zincir taze node'a kuruluşta **ajan-iddiasıdır**: seed'i bilen
düşman zinciri baştan hash'leyip kendi-tutarlı sahte tarih kurabilir (A1b — import +
ledger-verify geçer). Mevcut panzehirler: D4 append-only (zincirli hedef ezilemez — A2)
+ seed gizliliği. Simnet tek-yazar ortamında kabul edilebilir; ağda (Faz 3) kabul edilemez.

## 2. Amaç ve olmayan amaç

- **Amaç:** taze node'daki gömülü zincirin her kaydına **node'un sertifikası**nı eklemek;
  doğrulayan tarafın kaydı sahteleyememesi.
- **Olmayan amaç:** gizlilik (zaten AEAD), merkle değişimi (state katmanı ayrı), gerçek
  ödeme (Faz 4).

## 3. Önerilen mekanizma (minimum-sürükleme tasarımı)

**Kilit fikir: zincir-hash formatı DEĞİŞMEZ.** D4'ün `h = sha256(prev | jcs(kayıt))`
tanımı bozulmaz; node sertifikası kaydın İÇİNE yeni alan olarak girer. Gerçeklemede
kesin kural (Audit-9 B13 ile netleştirildi): `node_id` **hash-girdisinin İÇİNDE**
(kimlik zincire bağlanır), `node_sig` **hash-girdisinin DIŞINDA** — çünkü node_sig
h'yi imzalar; h, node_sig'i içeren kaydın hash'i olsaydı döngüsel olurdu:

```jsonc
// charge kaydı (v0.2 adayı):
{"op":"charge","seq":3,"prev":"<64hex>","h":"<64hex>",
 "node_sig":"<128hex>",            // YENİ: ed25519(node_key, h)
 "node_id":"<64hex>",              // YENİ: node verify-key
 ...ölçüm ve ücret alanları...}
```

- `node_sig = ed25519_sign(node_private, h)` — zincir bütünlüğü zaten `h`'de olduğu için
  imza tekil kaydı mühürler; alan eklenmesi jcs sıralamasıyla hash'e doğal girer
  (geriye-uyumlu hash hesabı: alan yoksa imzasız zincir birebir aynı doğrulanır).
- Node anahtarı **ajan seed'inden ayrıdır**: node operatör anahtarıdır, 0600 dosyada
  durabilir (D3 yalnız AGAN seed'ini diske yasaklar). Faz 3'te HSM/TEE seçeneği.

## 4. Doğrulama politikası (import tarafı)

Taze node'da gömülü zincir kuruluşu üç seviyeye ayrılır (politika manifest'te değil,
node konfigürasyonunda — ajan kendi denetçisini seçemez):

| Seviye | Davranış | Kullanım |
|---|---|---|
| L0 (bugünkü) | node_sig'siz zincir kurulur, provenance notu düşer | simnet v0 |
| L1 | zincirdeki her kayıt node_sig taşımali ve `node_id` bilinen güvencili listede olmalı; yoksa import RED (reason 14 alt-kodu). **Audit-9 B14 kapsam notu:** L1 bugün yalnız GÖMÜLÜ zinciri denetler; hedefte zaten var olan yerel zincir hash+imza katmanıyla doğrulanır ama güven-listesinden geçirilmez (yerel zincir operatörün kendi donanım kontrolündedir) — tam-kapsam L1 Faz 2 adayı | Faz 2 pilot |
| L2 | L1 + kayıt node'ları arası itibar sorgusu (ERC-8004 Validation/Reputation) | Faz 3 ağ |

Güvencili-liste bootstrap sorusu bilinçli açık bırakılır (aşağıda OQ-2).

## 5. Değişim listesi (Faz 2 ilk dilimi olarak)

1. `tamga_runner.py keygen-node <dir>` (0600; ayrı komut — ajan keygen'i ile karışmaz).
2. `_ledger_append` opsiyonel `node_key` parametresi: varsa `node_sig`/`node_id` ekler.
3. `_records_head` + `_ledger_head`: L1 politikasında node_sig doğrulaması
   (PyNaCl VerifyKey; ek bağımlılık yok).
4. RFC-003 v0.2 revizyonu: §3 şemaya iki alan + §2'ye D8 kararı (gerekçe: F25).
5. Negatif vektörler: sahte node_sig (yanlış anahtar), eksik node_sig (L1'de),
   node_id listenin dışında — üç RED kanıtı.

## 6. Açık sorular (karar için kurucuya)

- **OQ-1:** L1 politikası Faz 2 pilotunda default mu, opt-in mi? (Öneri: opt-in; pilot
  müşteri kendi node anahtarını doğrular.)
- **OQ-2:** Güvencili node listesi bootstrap'ı: statik dosya / ERC-8004 Identity Registry
  sorgusu / ikisi kademeli? (Öneri: Faz 2'de statik + out-of-band doğrulama; Faz 3'te
  ERC-8004 — bkz. docs/ERC-8004-ESLEME.md.)
- **OQ-3:** Node anahtarı rotasyonu: eski anahtarla imzalanmış kayıtlar geçerliliğini
  ne kadar korur? (Öneri: zincir-başına pinning; rotasyon yeni zincir segmenti açar.)
- **OQ-4:** TEE imzası (Faz 3 TEE pilotu) node_sig'le aynı alanda mı, ayrı mı? (Öneri:
  ayrı `attestation` alanı; karıştırmayalım.)

## 7. Kabul testi taslağı (AT-003 adayı)

1. L0→L1 geçişte eski zincirler doğrulanmaya devam eder (geriye-uyum).
2. Sahte node_sig'li snapshot → import RED; gerçek node anahtarıyla imzalı → ACCEPT.
3. Zincir-ortası kayıt kurcalanırsa hem zincir-hash hem node_sig RED verir (iki katman).
4. node_id listesi dışı zincir → L1'de RED, L0'da provenance-notlu ACCEPT.

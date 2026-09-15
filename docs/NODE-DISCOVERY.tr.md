> Çeviri notu: İngilizce-orijinali (docs/NODE-DISCOVERY.md) ile ikizdir; normatif-metin İngilizce'dir — çelişki-olursa ORİJİNAL-BAĞLAYICIDIR.

# Node Discovery — Faz-3 Tasarım Notu (ERC-8004-uyumlu)

> Durum: TASARIM NOTU — kod ya da RFC değişikliği yok. Faz-3 TETİK-KAPILI'dır
> (dış node sayısı, pilot geliri, simülasyon eşikleri — ROADMAP); bu not, node
> keşfinin *şeklini* dondurur ki tetik ateşlendiğinde düşünceyi bitmiş bulsun
> (RFC-009 disiplini: matematik/tasarım şimdi, sabit/kod kapıda).
> Kaynaklar 2026-09-11'de yeniden doğrulandı: ERC-8004'ün yetkili front-matter'ı
> (ethereum/ERCs `ERCS/erc-8004.md`) — hâlâ **Draft**; aşağıdaki eşleme
> `registration-v1`ı izler.

## 0. Bugün ne var (dürüst taban)

- **Node kimliği**: `keygen-node` — operatör sertifika-anahtarı, 0600, node_id (ARCHITECTURE §5)
- **Node-birlikte-imzalama (node-cosign) L1**: node-onaylı makbuzlar, opsiyonel (OQ-1); `--node-trust` = basit-dosya
  güven listesi (OQ-2: ERC-8004 Final'e dek elle-bakım; sonra zincir-üstü geçiş)
- **İptal (revocation)**: `--node-revoked` — listelenen node'ların imzaları, hâlâ güvenilir
  olsalar bile içe-aktarımda reddedilir (OQ-3, Audit-16); bağımsız `ledger-verify` politika-bağımsız kalır
- **Bunların hiçbiri keşif (discovery) değil.** Bugün bir istemci, node'ları band-dışı (out-of-band) öğrenir.

## 1. Faz-3'ün kapattığı boşluk

| Question | Today (Phase 2) | Phase-3 target |
|---|---|---|
| Bir node'u nasıl bulurum? | band-dışı | ERC-8004 Identity Registry (zincir-üstü tutamaç → kayıt dosyası) |
| Bir node'a nasıl güvenirim? | `--node-trust` dosyası | + makbuz-zinciri kanıtıyla beslenen Reputation Registry sinyalleri |
| İş nasıl denetlenir? | yalnızca bizim hash-zincirimiz | + Validation Registry kancaları (staker yeniden-koşumu / TEE oracle / zkML — takılabilir) |
| Bir node ne beyan eder? | düz-nesir | `x402Support`/`supportedTrust` alanlı `registration-v1` dosyası |

## 2. Önerilen eşleme (manifest ↔ registration-v1)

Tamga'nın manifest'i, bir kayıt-dosyasının ihtiyaç duyduğu alanları zaten
taşıyor; köprü şema-cerrahisi değil, alan-yansıtmasıdır:

| registration-v1 field | Tamga source | Notes |
|---|---|---|
| ajan kimliği/tutamaç | manifest `agent_id` (ed25519 doğrulama anahtarı) | basılabilir (ERC-721-mintable) tutamaç, kayıt-dosyasına çözülür |
| yetenekler (capabilities) | manifest `caps` + `runtime` (ağ-çıkışı, bayt-tavanları) | yetenek beyanları, yazar-anahtarıyla imzalı kalır |
| `x402Support` | RFC-008 `external_receipt` varlığı (ray: x402) + RFC-007 `delivery_hash` | ödeme-desteği beyan edilir, asla *söz verilmez* (kapsam cümlesi) |
| `supportedTrust` katmanları | bugün birlikte-imzalama (cosign) politikası L0/L1; TEE ayrı alan (OQ-4, Faz 3) | katmanlar, ERC-8004'ün takılabilir güven-modellerine eşlenir |
| kanıt (evidence) | makbuz-zinciri demeti (`tamga bundle`) | zincir-dışı kanıt, zincir-üstü sinyal — Reputation/Validation okuma API'leri (`getResponseCount`, `getResponseByIndex`) bunu şema-değişikliği olmadan tüketir |

RFC-008'den devralınan temel dürüstlük kuralı: **kayıt-dosyası bir BEYANDIR,
makbuz-zinciri ise KANITTIR** — kayıt-defteri (registry), bir node'un ne
yaptığının gerçek-kaynağı asla olmaz; node'un ne dediğini indeksler ve
doğrulanabilir kanıtı işaret eder.

## 3. İptal geçişi (OQ-2'nin ikinci yarısı)

- Bugün: `--node-trust` + `--node-revoked` dosyaları (elle, denetlenebilir, sıfır-altyapı).
- ERC-8004 Final'de: güven listesi Identity Registry'ye taşınır; iptal
  semantiği **içe-aktarım-anı-politikası** olarak kalır (Audit-16'nın mimari
  notu: zincir matematiği politika-bağımsızdır; iptal bir politika kararıdır, zincir özelliği değil).
- Geçiş tek-yönlü ve eklemeli (additive): dosya-yolu, hava-boşluklu (air-gapped)
  sunucular için yedek olarak kalır (D12 çift-okuma deseni, güvene uygulanmış hali).

## 4. Kapıda kalanlar (işlem-sırası borcu yok)

- **Zincir-üstü her şey**: ERC-8004'ün Final'e ulaşmasına kapılı (bugün
  Draft; eşlemedeki sallantılı noktalar ERC-8004-MAPPING.md'de işaretlidir).
- **TEE güven-katmanı**: ayrı alan, imza-alanına asla karıştırılmaz (OQ-4);
  bulut-enclave pilotu (Nitro/SEV-SNP, Intel TDX izleniyor) — Faz-3 maddesi.
- **Gerçek mikro-ödemeler**: x402 mı L1-kanalı mı kararı prototip-ölçümüyle;
  ROADMAP'ten dürüst not: x402 hacminin kabaca yarısı test-trafiği —
  gerçek-ticaret payı v1'den önce ölçülmeli.
- **Node-alım-kapısı (I4)**: dış-node çağrı eşiği = node medyan-geliri ≥
  node maliyeti (economy_sim: λ ≥ 2000 iş/ay/node bölgesi); altında, kurucu-node taşır.

## 5. Test ailesi ön-izleimi (AT-022 adayı, tetikte)

Faz-3 ateşlendiğinde, kabul-ailesi bu notu yansıtır: kayıt-dosyası
yansıtmasının determinizmi (aynı manifest → aynı registration-v1 dosya
baytları), güven-listesi geçişinin tek-yönlülüğü, iptalin-hâlâ-içe-aktarım-anı
olması ve itibar-kanıtı gidiş-dönüşü (demet → registry okuma API şekli).
Şimdi hiçbir test yazılmaz — kararı kapı verir ve bu not, test edeceği tasarımdır.

# ERC-8004 ↔ Tamga Eşleme Notu (Faz 3 tasarım materyali)

- **Durum:** TASARIM NOTU — hiçbir kod/RFC değişikliği değildir. Faz 3 tetikleyiciliği
  (dış talep sinyali) gelirse RFC-003 v0.2 ile beraber ele alınır.
- **Veri kaynağı ve tazelik:** findings.md (2026-09-05 çekimi) — ERC-8004 **hâlâ Draft**;
  üç hafif kayıt (Identity / Reputation / Validation); registration-v1 kayıt dosyası;
  agentRegistry biçimi `eip155:{chainId}:{identityRegistry}` + agentId. Dürüst not:
  ERC Draft'tan Final'e geçebilir veya değişebilir; bu tablo oynak noktaları işaretler.

## 1. İki protokolün farkı (önce bunu netleştirelim)

| | ERC-8004 | Tamga |
|---|---|---|
| Ne satıyor | **keşif + güven çapası** (on-chain kimlik/itibar/doğrulama kayıtları) | **taşınabilir durum** (kimlik+hafıza+defter şifreli snapshot) |
| Durum modeli | on-chain minimal (tokenId, URI), dosya off-chain | off-chain şifreli snapshot + hash-zincirli defter |
| Ödeme | dışında (x402 ile kompoze) | v0 simnet; Faz 3 x402/L1 channel |

İkisi rakip değil: ERC-8004 kaydı Tamga manifest'ine/snapshot'ına **işaret eden** bir
güven çapası olur; Tamga zinciri ise ERC-8004 Validation kancalarına (stake'li
yeniden-koşum, TEE oracle) doğrulanabilir kanıt besler.

## 2. registration-v1 ↔ Tamga eşleme tablosu

| registration-v1 alanı | Tamga kaynağı | Not |
|---|---|---|
| `type` | `"agent"` | sabit |
| `name` | RFC-001 `package.name` (kanonik sahip — E-4) | pattern uyumlu `[a-z0-9-]` |
| `description` | WHITEPAPER §3 primitif cümlesinin kısa hali | — |
| `services[]` | Faz 3'te A2A/MCP uçları; v0'da yok | boş dizi geçerli |
| `x402Support` | `false` (v0) → `true` (Faz 3 x402 kararı sonrası) | x402: 165M+ işlem / dürüst not: ~yarısı test trafiği olabilir |
| `active` | snapshot varlığı + ledger-verify ok | "aktif" = doğrulanabilir zincir ucu |
| `supportedTrust` | `["crypto-economic"]` (node-cosign L1/L2 — specs/DESIGN-node-cosign.md) · `["tee-attestation"]` (Faz 3 TEE pilotu) · `["reputation"]` (ERC-8004 Reputation) | Tamga v0: yalnız L0 → destek beyanı YOK (dürüstlük) |
| `agentRegistry` | yok (v0 on-chain değil) | Faz 3'te `eip155:{chainId}:{registry}` + tokenId |
| *(önerilen ek alan)* `tamgaProofLevel` | RFC-001 `runtime.min_proof_level` (P0/P1/P2) | kayıt dosyasına Tamga uzantısı — oynak nokta: şemada bu alan yok, uzantı tartışması Faz 3 |
| *(önerilen ek alan)* `tamgaLedgerHead` | son `h` (64-hex) | itibar sorguları zincir ucuna bağlanabilir; her koşumda güncellenmez (Snapshot-değişmez etiketiyle on-chain yazımı pahalı — off-chain URI üzerinden) |

## 3. Yön-2: Tamga'nın ERC-8004 Validation kancalarına verdiği kanıt

- **stake'li yeniden-koşum:** aynı `agent.wasm` + limits → aynı `stdout_sha256`
  deterministikse, doğrulayıcı koşumu charge kaydındaki ölçüm kanıtlarıyla çaprazlar.
  **Ön-ölçüm (2026-09-05, kanit/AT-002/2026-09-05/oq5-determinizm-onolcum.log):**
  aynı wasm+girdi 4/4 başarılı koşumda stdout_sha256 birebir aynı (c06fc1df…; 1 koşum
  load-spike'tan reason-11 — E-9c'nin canlı örneği). Determinizm güçlü sinyal; tam
  ölçüm (farklı girdiler) AT-002.
- **OQ-8 (yeni, ön-ölçümden doğdu): wall-faturalama gerilimi.** Aynı işin ücreti
  koşum-zamanı yüküne göre ~172× oynayabilir (quickstart wall_ms=2022 @load~24 vs
  ön-ölçüm 7..9ms @load~21). RFC-003 D1 (wall tabanı) ağır-yük host'ta kullanıcıyı
  gürültüyle faturalandırır. Faz 2 önerisi: medyan-of-N pencere faturalama ya da
  düşük-yük doğrulama penceresi; ücret-adaleti maddesi node-cosign tasarımına bağlı.
- **TEE oracle:** node-cosign `attestation` alanı (DESIGN-node-cosign.md OQ-4).
- **Reputation:** charge geçmişi (hash-zincirli) itibar sinyalinin doğrulanabilir
  alt-tabanıdır — kayıt sahteleme ancak F25'ün kapsadığı seed-sahibi düşmanla mümkün;
  node-cosign L1/L2 bunu kapatır. İki tasarım birbirinin ön-koşulu: **ERC-8004 itibarı
  ancak node-cosign'li zincirde kurcalamaya dayanıklıdır.**

## 4. Açık sorular (Faz 3'e)

- **OQ-5:** WASI koşum determinizmi — ön-ölçüm güçlü sinyal verdi (üstte); tam ölçüm
  (farklı girdi setleri, sınır durumları) AT-002 ailesinde.
- **OQ-6:** agentURI hangi saklamayı işaret eder (IPFS/Arweave/HTTPS)? Değişmezlik vs
  güncellenebilirlik gerilimi — snapshot per-oturum değişir; kayıt dosyası sabit kalmalı.
- **OQ-7:** ERC-8004 Final geçerse alan değişimleri bu tabloya errata işlenir (o tarihe dek
  Draft olduğu için burada sürüm kilidi tutulmaz — bilinçli karar).
- **OQ-8:** wall-faturalama gerilimi (yukarıda) — medyan-of-N mi, düşük-yük pencere mi,
  yoksa faturalama tabanı gözden geçirmesi mi? RFC-003 kurucu onayıyla bağlantılı.

# RFC-001: Ajan Paket Manifest Şeması

- **Durum:** **v0.1-FINAL — DONDURULDU (2026-09-02, kurucu onayı).** Değişiklik yeni RFC + sürüm artışı ister.
- **Bağlılık:** WHITEPAPER.md §3 (primitif), §6 (tarafsızlık) · ACCEPTANCE-TESTS.md AT-001a · ROADMAP Faz 0
- **İlgili RFC'ler:** RFC-002 (runner API, snapshot export/import) · RFC-003 (ledger kayıt) · RFC-004 (attestation)

## 1. Motivasyon

Primitifin dört bileşeninden üçü (Kimlik, Hafıza, Cüzdan) çalışma-zamanı varlıklardır; manifest, dördüncüsü **Yürütüm'ün** (E_A = W_A + F_A + P_A) taşıyıcısıdır: kodun ne olduğu, neleri istediği, hangi koruma seviyesini gerektirdiği. Manifest aynı zamanda **ilk dondurulan arayüzdür** — ajanlar, node'lar ve test araçları bu şema üzerinden birbirine paralel inşa edilir. Bu yüzden şema küçük, katı ve denetlenebilir yazılır.

## 2. Kapsam ve Kararlar (gerekçeleriyle)

| # | Karar | Gerekçe | Elenen alternatif |
|---|---|---|---|
| D1 | Tek dosya: `tamga.json`, JSON Schema (draft 2020-12) ile doğrulanır | İmza için **kanonik serileştirme** gerekir; JSON'un bunun için standardı var (RFC 8785). YAML'da kanonik form yoktur; TOML'un araç desteği zayıftır | YAML (kanonikleşemez → imza belirsizliği), TOML |
| D2 | İmza: ed25519, RFC 8785 kanonik form üzerinde; `signature` alanı boşaltılarak hesaplanır | Kısa anahtarlar, ekosistemde yaygın; kurallar basit | ECDSA zinciri (gereksiz karmaşıklık, v0'da zincir yok) |
| D3 | Bilinmeyen alan politikası: **katı reddet** (v0.1) | Erken fazda sessiz uyumsuzluk en büyük hata kaynağı; gevşetmek ileride kolay, sıkılaştırmak kırıcıdır | ignore-unknown (yaygın ama sessiz hata üretir) |
| D4 | Yetenekler (capabilities) **varsayılan reddet**: fs, net, clock, env, random | Host-körlük ilkesinin kod karşılığı: beyan edilmeyen erişim yoktur. Güvenlik-sınırı bölümü → insan kapısı uygulanır | varsayılan izin-ver (primitifle çelişir) |
| D5 | Kod bütünlüğü zorunlu: `code.sha256` — hash'siz paket geçersiz | AT-001d'nin (host-körlük) ve gelecekteki koşum kanıtının önkoşulu | imzasız/hash'siz "geliştirme modu" (arka kapı yasağı) |
| D6 | Kod hedefi sabit: **WASI 0.3 (component model)** | Eylül 2026 itibarıyla WASI üçüncü milestone (0.3) yayımlandı; component model, izin modeli + taşınabilir bileşenler için ekosistem standardı. Eski core-module hedefine derleyen paket RED | `core module` hedefi (izin modeli ve bileşen standardı dışı) |

## 3. Paket Biçimi

```
paket/
├── tamga.json      # bu RFC'nin konusu
├── agent.wasm    # code.sha256 ile eşleşen WASM modülü
└── seed/         # (opsiyonel) ilk bağlam grafiği, tamga-snapshot/1 biçiminde
```

## 4. Şema (JSON Schema, normatif)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "tamga://rfc-001/manifest-0.1.0",
  "title": "Tamga Ajan Paket Manifesti",
  "type": "object",
  "additionalProperties": false,
  "required": ["spec_version", "package", "runtime", "memory", "capabilities", "signature"],
  "properties": {
    "spec_version": { "const": "0.1.0" },
    "package": {
      "type": "object",
      "additionalProperties": false,
      "required": ["name", "version", "code"],
      "properties": {
        "name": { "type": "string", "pattern": "^[a-z0-9][a-z0-9-]{2,31}$" },
        "version": { "type": "string", "pattern": "^(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)$" },
        "code": {
          "type": "object",
          "additionalProperties": false,
          "required": ["wasm_sha256", "hash_algo", "target"],
          "properties": {
            "wasm_sha256": { "type": "string", "pattern": "^[a-f0-9]{64}$" },
            "hash_algo": { "const": "sha256" },
            "target": { "const": "wasi-0.3/component" }
          }
        }
      }
    },
    "runtime": {
      "type": "object",
      "additionalProperties": false,
      "required": ["min_proof_level", "limits"],
      "properties": {
        "min_proof_level": { "enum": ["P0", "P1", "P2"] },
        "limits": {
          "type": "object",
          "additionalProperties": false,
          "required": ["memory_mb", "cpu_ms_per_run", "io_mb_per_run"],
          "properties": {
            "memory_mb":       { "type": "integer", "minimum": 16, "maximum": 4096 },
            "cpu_ms_per_run":  { "type": "integer", "minimum": 1,  "maximum": 60000 },
            "io_mb_per_run":   { "type": "integer", "minimum": 0,  "maximum": 1024 }
          }
        }
      }
    },
    "memory": {
      "type": "object",
      "additionalProperties": false,
      "required": ["snapshot_format", "crypto_suite"],
      "properties": {
        "snapshot_format": { "const": "tamga-snapshot/1" },
        "crypto_suite": { "const": "XChaCha20-Poly1305" }
      }
    },
    "capabilities": {
      "type": "array",
      "uniqueItems": true,
      "items": { "enum": ["fs", "net", "clock", "env", "random"] },
      "maxItems": 5
    },
    "payment": {
      "type": "object",
      "additionalProperties": false,
      "required": ["schemes"],
      "properties": {
        "schemes": { "type": "array", "minItems": 1, "items": { "const": "tamga-sim/1" } }
      }
    },
    "signature": {
      "type": "object",
      "additionalProperties": false,
      "required": ["algo", "key", "sig"],
      "properties": {
        "algo": { "const": "ed25519" },
        "key":  { "type": "string", "pattern": "^[a-f0-9]{64}$" },
        "sig":  { "type": "string", "pattern": "^[a-f0-9]{128}$" }
      }
    }
  }
}
```

Notlar: `payment` v0'da yalnız `tamga-sim/1` (simüle ledger, RFC-003) kabul eder; v1'de enum genişler (x402 vb.) — bu bir **minor** sürüm artışıdır. `runtime.min_proof_level` ajanın *istediği* alt sınırdır; node'un *sunabildiği* seviye RFC-004'te node manifest'ine yazılır ve eşleşme koşum öncesi kontrol edilir.

## 5. Doğrulama Kuralları (runner sırasıyla uygular)

1. JSON ayrıştırma → şema doğrulama (§4, katı).
2. `agent.wasm` dosyasının sha256'sı = `package.code.wasm_sha256`.
3. `signature` doğrulaması: alanı boşalt, RFC 8785 kanonikleştir, `signature.key` ile doğrula.
4. Yetenek kontrolü: beyan edilmeyen syscall/WASM import'u koşum anında engellenir (beyan/gerçek tutarsızlığı = hata, sessiz izin değil).
5. `min_proof_level` node sunumuyla eşleşmezse RED (AT-001a kapsamı dışı, koşum kontrolü).

## 6. Test Vektörleri (AT-001a'ya bağlanır)

| ID | Varyant | Beklenen |
|---|---|---|
| TC-a1 | Geçerli manifest + eşleşen wasm + geçerli imza | ACCEPT |
| TC-a2 | `code.wasm_sha256` dosyayla uyuşmuyor | RED: "code hash mismatch" |
| TC-a3 | Bilinmeyen üst alan (`"admin_backdoor": true`) | RED: "unknown field" (D3) |
| TC-a4 | `capabilities` içinde `"root"` | RED: "unknown capability" (D4) |
| TC-a5 | İmza alanı bozulmuş (tek hex karakter değişimi) | RED: "signature invalid" |
| TC-a6 | `spec_version` farklı (`"0.2.0"`) | RED: "unsupported spec_version" |

## 7. Örnek Manifest

```json
{
  "spec_version": "0.1.0",
  "package": {
    "name": "tamga-ornek-ajani",
    "version": "0.1.0",
    "code": { "wasm_sha256": "3a7b…64-hex…", "hash_algo": "sha256", "target": "wasi-0.3/component" }
  },
  "runtime": {
    "min_proof_level": "P0",
    "limits": { "memory_mb": 128, "cpu_ms_per_run": 5000, "io_mb_per_run": 10 }
  },
  "memory": { "snapshot_format": "tamga-snapshot/1", "crypto_suite": "XChaCha20-Poly1305" },
  "capabilities": ["clock", "random"],
  "payment": { "schemes": ["tamga-sim/1"] },
  "signature": { "algo": "ed25519", "key": "ab…64-hex…", "sig": "cd…128-hex…" }
}
```

## 8. Güvenlik Değerlendirmeleri

- Manifest imzalıdır ama **imzalayan ≠ ajan kimliğidir** (pk_A koşumda keystore'da doğar — WHITEPAPER §3). Manifest imzası paket kökenini kanıtlar; ajan kişiliğini değil. Bu ayrım bilinçli ve normatiftir.
- D4 (varsayılan reddet) ve D5 (hash zorunlu) insan kapısı kapsamındadır: gevşetme değişiklikleri tek başına merge edilemez.
- Hash agility: v0.1'de tek algoritma (sha256); değişiklik ihtiyacı doğarsa yeni RFC — mevcut paketler geriye dönük doğrulanmaya devam eder.

## 9. Açık Sorular (bilinçli ertelenmiş)

1. `seed/` grafiğinin tam şeması → RFC-002 (snapshot export/import ile birlikte).
2. Çoklu imzalayıcı (yayıncı + denetçi) desteği → v0.1'de tek imza; talep doğarsa RFC.
3. `payment.schemes` enum'unun v1 genişlemesi → TOKENOMICS §3 simülasyonuna bağlı.
4. **İmzalayan güven çapası (allowlist/pinning) v0.1'de yoktur** — kanıt koşusunda keşfedildi (2026-09-02): "yanlış imzalayan" senaryosu manifest seviyesinde test edilemez; her geçerli anahtar kendi manifestini imzalayabilir. Paket dağıtımı/registry tasarımı ayrı RFC konusudur.

## 10. Onay Kütüğü

- [x] Kurucu onayı: **2026-09-02** — bu RFC donduruldu, Durum: **v0.1-FINAL**. Şema: `specs/manifest-0.1.0.schema.json`; doğrulayıcı: `tamga_validator.py`.

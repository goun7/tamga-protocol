# RFC-001: Ajan Paket Manifesti Şeması

> Çeviri notu: İngilizce-orijinali ile ikiz (docs/RFC-001-manifest.md); normatif-metin İngilizce'dir — çelişki-olursa ORİJİNAL-BAĞLAYICIDIR.

> Bu belgenin kanonik sürümü Türkçe'dir (dahili). Bu, resmî İngilizce çevirisidir — normatif içerik birebir aynıdır.

*Çevirmenin notu: "Tamga", birimin (primitive) projedeki adıdır. Kod blokları kanonik Türkçe orijinalden birebir aktarılmıştır — tanımlayıcılar, alan adları, desenler ve örnek değerler (örnek paket adı `tamga-ornek-ajani`, "example agent" ifadesinin Türkçesi) değiştirilmemiştir.*

- **Durum:** **v0.1-FINAL — DONDURULDU (2026-09-02, kurucu onaylı).** Bir değişiklik, yeni bir RFC + sürüm artışı gerektirir.
- **Bağımlılıklar:** birim tanımı §3, tarafsızlık §6; kabul-testi takımı, AT-001a; yol haritası Faz 0 — atıf yapılan belgeler dahili (karar günlüğü).
- **İlgili RFC'ler:** RFC-002 (runner API'si, anlık-görüntü (snapshot) dışa/içe aktarımı) · RFC-003 (defter kayıtları) · RFC-004 (tasdik/attestation)

## 1. Motivasyon

Birim'in dört bileşeninden üçü (Kimlik, Bellek, Cüzdan) çalışma-zamanı varlıklarıdır; manifest, dördüncü bileşen olan **Yürütme**'nin taşıyıcısıdır (E_A = W_A + F_A + P_A): kodun ne olduğunu, neyi talep ettiğini ve hangi koruma düzeyini gerektirdiğini taşır. Manifest aynı zamanda **dondurulan ilk arayüzdür** — ajanlar, düğümler ve test araçları, bu şemaya karşılıklı olarak eşzamanlı biçimde inşa edilir. Bu nedenle şema küçük, katı ve denetlenebilir yazılmıştır.

## 2. Kapsam ve Kararlar (gerekçeleriyle)

| # | Decision | Rationale | Rejected alternative |
|---|---|---|---|
| D1 | Tek dosya: `tamga.json`, JSON Şeması (draft 2020-12) ile doğrulanır | İmzalama **kanonik serileştirme** gerektirir; JSON'da bunun için bir standart var (RFC 8785). YAML'ın kanonik biçimi yok; TOML'un araç desteği zayıf | YAML (kanonikleştirilemez → imza belirsizliği), TOML |
| D2 | İmza: ed25519, RFC 8785 kanonik biçimi üzerinden; `signature` alanı boşaltılarak hesaplanır | Kısa anahtarlar, ekosistemde yaygın; basit kurallar | Bir ECDSA zinciri (gereksiz karmaşıklık; v0'da zincir yok) |
| D3 | Bilinmeyen-alan politikası: **katı red** (v0.1) | Erken aşamada sessiz sapma, hataların en büyük kaynağıdır; sonra gevşetmek kolay, sonra sıklaştırmak kırıcıdır | ignore-unknown (yaygındır, ama sessiz hatalar üretir) |
| D4 | Yetkinlikler **varsayılan-red** (default-deny) şeklindedir: fs, net, clock, env, random | Konak-körlüğü (host-blindness) ilkesinin kod-düzeyindeki karşılığı: bildirilmemiş erişim yoktur. Güvenlik-sınırı bölümü → insan kapısı geçerlidir | default-allow (birimle çelişir) |
| D5 | Kod bütünlüğü zorunludur: `code.sha256` — hash'siz paket geçersizdir | AT-001d (konak-körlüğü) ve gelecekteki yürütme-kanıtı (proof-of-execution) için ön koşuldur | imzasız/hash'siz "geliştirme modu" (arka kapı yasağı) |
| D6 | Kod hedefi sabittir: **WASI 0.3 (component model / bileşen modeli)** | Eylül 2026 itibarıyla WASI'nin üçüncü kilometre taşı (0.3) yayımlandı; bileşen modeli, izin modeli + taşınabilir bileşenler için ekosistem standardıdır. Eski core-module hedefine derlenen bir paket RED'dir | `core module` hedefi (izin modelinin ve bileşen standardının dışında) |

## 3. Paket Biçimi

```
package/
├── tamga.json      # bu RFC'nin konusu
├── agent.wasm    # code.sha256 ile eşleşen WASM modülü
└── seed/         # (isteğe bağlı) başlangıç bağlam grafiği, tamga-snapshot/1 biçiminde
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

Notlar: v0'da `payment` yalnızca `tamga-sim/1`'i (benzetim defteri, RFC-003) kabul eder; v1'de enum genişler (x402 vb.) — bu bir **minor** sürüm artışudur. `runtime.min_proof_level`, ajanın *talep ettiği* alt sınırdır; düğümün *sunabildiği* düzey RFC-004'teki düğüm manifestine yazılır ve eşleşme bir çalıştırmadan önce denetlenir.

## 5. Doğrulama Kuralları (runner tarafından uygulanan, bu sırayla)

1. JSON ayrıştırma → şema doğrulaması (§4, katı).
2. `agent.wasm` dosyasının sha256 değeri = `package.code.wasm_sha256`.
3. İmza doğrulaması: alanı boşalt, RFC 8785'e göre kanonikleştir, `signature.key` ile doğrula.
4. Yetkinlik denetimi: bildirilmemiş bir syscall/WASM import'u çalışma anında engellenir (bildirilen/fiilî tutarsızlık sessiz izin değil, hatadır).
5. `min_proof_level` düğümün sunduğuyla eşleşmezse → RED (AT-001a'nın kapsamı dışında; çalışma-anı denetimi).

## 6. Test Vektörleri (AT-001a'ya bağlı)

| ID | Variant | Expected |
|---|---|---|
| TC-a1 | Geçerli manifest + eşleşen wasm + geçerli imza | ACCEPT |
| TC-a2 | `code.wasm_sha256` dosyayla eşleşmiyor | RED: "code hash mismatch" |
| TC-a3 | Bilinmeyen üst-düzey alanı (`"admin_backdoor": true`) | RED: "unknown field" (D3) |
| TC-a4 | `capabilities` içinde `"root"` | RED: "unknown capability" (D4) |
| TC-a5 | İmza alanı bozulmuş (tek bir hex karakter değiştirilmiş) | RED: "signature invalid" |
| TC-a6 | Farklı `spec_version` (`"0.2.0"`) | RED: "unsupported spec_version" |

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

- Manifest imzalidir, ancak **imzalayan ≠ ajanın kimliği**dir (pk_A, bir çalıştırma sırasında keystore'da doğar — birim tanımı §3, dahili karar günlüğü). Manifest imzası paketin kökenini kanıtlar; ajanın kimliğini kanıtlamaz. Bu ayrım kasıtlı ve normatiftir.
- D4 (varsayılan-red) ve D5 (zorunlu hash) insan kapısı kapsamındadır: bunları gevşeten değişiklikler tek başına birleştirilemez (merge edilemez).
- Hash agility (algoritma çevikliği): v0.1'de tek algoritma (sha256); değiştirme ihtiyacı hiç doğarsa yeni bir RFC gerekir — mevcut paketler olduğu gibi doğrulanmaya devam eder.

## 9. Açık Sorular (kasıtlı olarak ertelendi)

1. `seed/` grafiğinin tam şeması → RFC-002 (anlık-görüntü dışa/içe aktarımıyla birlikte).
2. Çok-imzalayan desteği (yayıncı + denetçi) → v0.1'de tek imza; talep doğarsa bir RFC.
3. `payment.schemes` enum'ının v1'de genişletilmesi → tokenomics §3 benzetimine bağlı (dahili karar günlüğü).
4. **v0.1'de imzalayan için bir güven çıpası (allowlist/pinning) yoktur** — bir kanıt koşusu sırasında keşfedildi (2026-09-02): "yanlış imzalayan" senaryosu manifest düzeyinde test edilemez; her geçerli anahtar kendi manifestini imzalayabilir. Paket dağıtımı/kayıt (registry) tasarımı ayrı bir RFC'nin konusudur.

## 10. Onay Kaydı

- [x] Kurucu onayı: **2026-09-02** — bu RFC donduruldu, Durum: **v0.1-FINAL**. Şema: `specs/manifest-0.1.0.schema.json`; doğrulayıcı: `tamga_validator.py`.

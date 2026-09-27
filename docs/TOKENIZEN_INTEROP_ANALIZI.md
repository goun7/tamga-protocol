# TOKENIZEN ↔ TAMGA — INTEROPERABILITE ANALIZI

**Tarih:** 2026-09-28
**Kapsam:** **ARAŞTIRMA, entegrasyon DEĞİL.** Sadece public GitHub okuma (holistis/tokenizen). Tokenizen ekibiyle **İLETİŞİM YASAK** — hiçbir istek/DM gönderilmedi.
**Amaç:** holistis'in `tokenizen` `capacity-attest` paketinin `DeliveryClaim` formatı ile Tamga'nın `charge` receipt formatı arasında **alan-bazında** bir karşılaştırma ve interop maliyet değerlendirmesi.

---

## 0. İki sistemin konumlanması

| | **Tamga** | **Tokenizen** |
|---|---|---|
| Nesne | `charge` (ledger receipt) | `DeliveryClaim` (signed receipt) |
| Dil | Python stdlib-only (pip yok) | TypeScript (zod v4, ethers) |
| Ledger zincir | D5: `h = sha256(prev \|\| jcs(record))`, **node-operator cosign** (D8 `node_sig`) | `priorClaimId`: **buyer'ın** aynı-seller önceki claim'ine singly-link; node yok |
| İmza | `node_sig` = EIP-191 over `h` (node operatörü) | `signature` = EIP-191 over `claimId` (**buyer**) |
| Kanonikleştirme | RFC 8785 JCS (`tamga_canon.jcs`) | `canonicalize()` = recursive key-sort + JSON.stringify (JCS-benzeri, kendi impl.) |
| Ödeme tarafı | x402/v1 `settlement_bind` (RFC-010) | `settlementRef` (x402 payment ref, "never resolved on-chain") |
| Felsefe | "node-certified receipt" | "verify yourself, we assert facts, never authority" |

**En dergin ortak nokta:** her ikisi de **"asserted link → recomputable link"** dönüşümünü amaçlar. Tokenizen'in kendi sözleriyle (`schema.ts`): `evidenceHash` *"a hash of evidence that is never itself checked"* ve `settlementRef` *"a payment reference that is never itself resolved on-chain"* — **tıpkı Tamga'nın D10 öncesi `settlement_ref`'inin "asserted but not resolved" olması gibi**. Tamga bunu D10 ile anchor = `h`'ye çevirdi. Tokenizen bilinçli olarak çözülmemiş bırakıyor (kendi tasarım sınırı).

---

## 1. Alan-bazında karşılaştırma tablosu

### 1a. Birebir / yakından eşleşen alanlar

| Tamga | Tokenizen | Eşleşme |
|---|---|---|
| `stdout_sha256` (64-hex, teslim edilen bayt) | `evidenceHash` (64-hex, "evidence for this claim") | **Aynı anlama yakın** — ikisi de "teslimin özüti". Ama Tamga `stdout_sha256` **mutlaka** mevcut (receipt'in kanıtı); Tokenizen `evidenceHash` **"a hash of evidence that is never itself checked"** ("the evidence itself is not stored here") |
| `prev` (64-hex, D5 zincir) | `priorClaimId` (`0x`+64-hex) | **Yapısal-aynı-link, farklı-imzalayan.** Tamga: node zinciri. Tokenizen: buyer'ın **aynı-seller** önceki claim'i. İkisi de singly-linked-chain |
| `h` / `receiptHash` (64-hex) | `claimId` (`0x`+64-hex, sha256 over canonical JSON) | **Aynı yapı: content-addressed ledger hash.** Hesap farklı (aşağıda) |
| `settlement_bind.payer` (0x40) | `buyerAddress` (0x40) | **Birebir** — EIP-191 imzasının çözüldüğü adres |
| `settlement_bind.payee` (0x40) | `sellerAddress` (0x40) | **Birebir** |
| `delivery_hash.hex` (sha256/keccak256) | — | Karşılığı yok (Tokenizen'da delivery özeti yok) |
| — | `assetType` (enum: gpu-hours/storage/api-credits/bandwidth) | Tamga'da yok — Tamga mesafe-agnostik |
| — | `delivered` (enum: yes/no/partial) | Tamga'da yok — **bu en büyük semantic fark** (aşağıda) |
| — | `promisedSpec` | Tamga'da yok |

### 1b. Dönüşüm gerektiren alanlar (mapping)

| Tamga → Tokenizen | Dönüşüm | Zorluk |
|---|---|---|
| `stdout_sha256` → `evidenceHash` | direkt kopya (64-hex → 64-hex) | **0 iş** |
| `h` → `claimId` | **yeniden hesap** — `claimId` Tamga'nın `h`'sinden **tamamen farklı preimage** (aşağıda §2) | **medium** |
| `prev` → `priorClaimId` | **yeniden kur** — Tamga zinciri global (seq artan), Tokenizen zinciri **buyer×seller** ikilisi başına | **medium-hard** |
| `settlement_bind.payer` → `buyerAddress` | kopya | **0 iş** |
| `settlement_bind.payee` → `sellerAddress` | kopya | **0 iş** |
| `ts` (RFC3339, `+0300` offsetli) → `timestamp` | **CINST/CDEC kural setine uydur** — Tokenizen timestamp'da **kesin-format** (0.2'de `[0-9]{3}Z` ms zorunlu); Tamga offsetli `+03:00` taşır | **kolay-ama-kırılgan** |
| `seq` (int) → — | Tokenizen'da seq yok; sıra `priorClaimId`'den gelir | **kayıp** ( Tamga-side bilgi) |
| `op` (`"charge"`) → — | Tokenizen'da op yok | **kayıp** |
| — → `delivered` enum | **Tamga'da karşılığı yok** — Tamga "teslim-edildi" der (receipt = kanıt), "kısmen-teslim" semantic'i taşımaz. **En büyük uyuşmazlık** | **hard (semantic)** |
| — → `assetType` enum (zorunlu) | Tamga generic — **zorunlu bir enum değeri seçmek gerekir** (api-credits en yakını olabilir) | **kolay-ama-keyfi** |
| `node_sig` → — | **Tokenizen'da node yok** — Tamga'nın D8 cosign'i **karşılıksız**. Tokenizen sadece buyer imzası ister | **kayıp (Tamga'nın güvenlik modeli)** |
| `input_sha256`, `pkg`, `engine`, `cpu_saat`, `ram_gb_sn`, `io_mb`, `wall_ms`, `fee_*`, `session` → — | Tamga'ya-özgü resource-metreleme; Tokenizen `measured` bloğu var **ama yapısı tamamen farklı** (`unit` enum + `deliveredAmount` CDEC) | **kolay-ama-keyfi** |

### 1c. Hiç karşılığı olmayanlar

- **Tamga-only:** `node_sig` + `node_id` (D8 — **bu Tamga'nın güvenlik modelidir**), `foreign_chain_proof` (§6), `op`, `seq`
- **Tokenizen-only:** `delivered` (yes/no/partial), `assetType`, `promisedSpec`, `measured` (quantitative), `externalRefs` (DID/mandate pointers), `DisputeContext`

---

## 2. Hash imza ve kanonikleştirme — teknik derin karşılaştırma

**Tamga (RFC-003 D5):**
```
h = sha256( prev_string || jcs(record_minus_{h,node_sig}) )
node_sig = EIP-191_sign(node_key, h)          # node operator imzalar
```

**Tokenizen (schema.ts `computeClaimId`):**
```
claimPreimage = canonicalize(ClaimContentSchema.parse(content))   # parse = lower-case adresler + strip unknown
claimId = "0x" + sha256(claimPreimage)
signature = EIP-191_sign(buyer_key, claimId)   # BUYER imzalar (ethers signMessage)
```

**Farklar:**
1. **İmzalayan:** Tamga **node operatörü**, Tokenizen **buyer**. En temel fark. Tamga'nın D8'i (node_id hash girdisinde, node_sig h'yi imzalar) **Tokenizen'de yok** — Tokenizen'de "buyer'ın kendi iddiası + özet" var, node-beyanı yok.
2. **Preimage:** Tamga `prev`'i **hash girdisinin başına ekler** (zincir-membership), Tokenizen `priorClaimId`'yi **content'in içine** koyar (keyfi-link). İkisi de zincir ama farklı yerde.
3. **Kanonikleştirme:** Tamga **RFC 8785 JCS** (sayı/Unicode kuralları, Node ile 17/17 parite kanıtı AT-036). Tokenizen **kendi `sortKeysDeep`** — sadece key-sort + JSON.stringify, sayı-normalizasyonu YOK (CDEC ile **input seviyesinde** zorlar). İkisi de deterministik ama **byte-bayt aynı değil** — JCS `1.0`→`1`, `e`-notasyonunu normalize eder; Tokenizen input'ta izin vermez.
4. **Imza formatı:** ikisi de EIP-191 personal-sign, 65-byte (r++s++v), `0x`-prefix. **Birebir uyumlu** (Tamga AT-196/AT-199 ile aynı ethers ailesi).

**Imza kanalı uyumu (RFC-010 §3b açısından):** Tamga'nın `x402/v1` scheme'i `z = raw-sha256` (EIP-191 öneksiz) imzalar. Tokenizen `signMessage` = EIP-191 **öneksiz** personal-sign. **Aynı kanal** — karşılıklı verify teknik olarak mümkün.

**Preimage örtüşmesinin teknik-temeli (bu-araştırma-sırasında-gösterildi):** her iki sistem de aynı temel preimage kullanır — sha256 over key-sorted canonical JSON:

```
Tokenizen:  claimId = "0x" + sha256(canonicalize(content))     # canonicalize = sortKeysDeep
Tamga §3b:  digest   =         sha256(canonical(content))      # RFC-8785 JCS
```

Aynı 64-hex özütün üzerine Tokenizen `0x`-prefix koyar (id olarak), Tamga ham-hex'i imzalar (digest olarak). **Fark: yalnızca prefix-tabanlı.** İmza biçimi her ikisinde 65-byte ECDSA `r++s++v`, `0x`-prefix.

**Bu bir çapraz-verify kanıtı DEĞİL, bir preimage-uyumluluğu-gösterimidir** — gerçek bir signature'ın iki tarafça da doğrulanması test edilmedi. Ama örtüşme tamdır: **preimage-algoritmaları paylaşılabilir, sadece kanonikleştirme kuralları farklı** (JCS sayı-normalizasyonu yapar, Tokenizen input-tarafında CDEC ile yasaklar).

---

## 3. Gerçekçi değerlendirme — interop ne kadar iş?

**Bu bir ARALIK tahminidir, kanıt değil.** Okuma-based; hiçbir prototype yazılmadı, hiçbir test koşturulmadı.

| Senaryo | İş tahmini (arı) | Neden |
|---|---|---|
| **A. Sadece-okuma bridge** (Tamga receipt'i Tokenizen'a import: 4 ortak alanı map'le) | **4-8 saat** | 4 alan kopya (0 iş) + `timestamp` CINST-uyarlama + `assetType`/`delivered` için **keyfi zorunlu değerler seç** + `claimId`'yi Tamga-kaynaktan **yeniden hesapla** (Tokenizen preimage'ı ile) |
| **B. Çift-yön read-verify** (her iki taraf diğerinin receipt'ini verify-etsin) | **1-2 gün** | A + iki kanonikleştirme yolunu da impl. etme (JCS ↔ sortKeysDeep) + iki hash-preimage'ı ayrı sürdürme + **cross-verification test'leri** |
| **C. Anchor paylaşımı** (D10 anchor = Tokenizen `evidenceHash` olarak Tamga `h`'yi kullan) | **2-4 saat** | En doğal köprü: Tokenizen `evidenceHash` zaten "asla-doğrulanmaz" diyor; D10 anchor onu **recomputable** yapabilir. Sadece 64-hex geçişi + bir verify-araç. **Ama** Tokenizen preimage'ından `claimId` bağımsızdır — anchor sadece `evidenceHash` alanına konabilir |
| **D. Tam semantic interop** (delivered:partial, measured, externalRefs'in tamamı) | **3-5+ gün** | Tamga'da **yeni semantic** gerekir: `delivered` enum, `measured` bloğu — bu RFC-003 freeze-kuralı gereği **yeni RFC demektir**, kod-değişikliği değil |

**En ucuz ve en anlamlı: Senaryo-C (anchor paylaşımı).** Neden: Tokenizen'in kendi `settlementRef`'i *"never resolved"* iken, D10 anchor'ı `evidenceHash`'e **recomputable** bir kanıt getirir. Bu, RFC-010'ın D10 ile kapattığı gap'in **aynı nesnede** Tokenizen tarafına da açılmasıdır — karşılıklı fayda, tek-taraflı değil.

---

## 4. Dürüst sınırlar — bu analizin NE OLDUĞU ve ne OLMADIĞI

**OLDU:**
- **Public schema okuma** — `schema.ts`'den alan adları, tipler, imza formatı, hash preimage'ı **kaynaktan** çıkarıldı
- **Yapısal karşılaştırma** — 3 tablo: birebir / dönüşüm / karşılıksız
- **İş tahmini aralığı** — 4 senaryo, saat-gün arası

**OLMADI:**
- **Entegrasyon DEĞİL** — hiçbir kod yazılmadı, hiçbir prototype kurulmadı
- **Test EDİLMEDİ** — "birebir EIP-191 uyumlu" iddiası **teknik akıl-ürütmecesidir**, çapraz-imza-verify koşturulmadı
- **İletişim YASAK-korundu** — tokenizen ekibine **hiçbir istek/DM/issue gönderilmedi**. Sadece public repo okundu
- **Tokenizen'in niyeti BİLİNMİYOR** — bu analiz onların interop istediğini **söylemez**. Sadece onların public kodundaki yapısal-örtüşmeyi gösterir
- **`delivered`/`measured` uyuşmazlığı çözülmedi** — bu bir **semantic** fark, mapping-değil; çözüm bir RFC-değerlendirmesi ister
- **Öncelik belirtmedi** — Senaryo-C "en ucuz ve en anlamlı" dedi, ama bu **bir öneri-değil**, sadece maliyet-analizi sonucudur. Öncelik lead'indir

**Erişilebilirlik notu:** repo **public ve erişilebilir** (117 dosya, `main` dalı). "ERİŞİLEMEZ" durumu söz-konusu-değil.

---

## 5. Referanslar (public GitHub)

- `holistis/tokenizen` — `packages/capacity-attest/src/schema.ts` (DeliveryClaim şeması, `computeClaimId`, `canonicalize`, `claimPreimage`, imza/alan regex'leri)
- `holistis/tokenizen` — `packages/capacity-attest/src/ledger.ts` (ledger-append + duplicate-rejection via claimId)
- Tamga tarafı: `docs/RFC-003-ledger.md` §5 (D5 zincir formülü), §8 (D8 node-cosign), §10 (D10 anchor), `docs/PAIRING-FIXTURE.md` (h-yeniden-hesaplama), `docs/RFC-010-cross-artifact-settlement-binding-DRAFT.md` §3b (imza kanalı)
- `docs/pairing/pairing-fixture.json` — Tamga charge'ın tam alan listesi (kaynak için okundu)

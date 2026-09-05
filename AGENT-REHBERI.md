# Tamga Ajan Geliştirici Rehberi (v0, Faz 1)

> Kime: Tamga ajanı geliştirecek ilk geliştiriciye. Her komut bu repoda **kanıt log'lu**
> koşulmuştur (kanit/README-CALISMA/2026-09-05/quickstart.log — 12 komut, tamamı ok).
> İddia yok, kanıt var: gördüğün her komut birebir koşulabilir.

## 0. On dakikalık zihinsel model

Bir Tamga ajanı üç şeydir:

1. **Kimlik** — ed25519 anahtar çifti. Seed **asla diskte düz durmaz** (D3); snapshot
   taşıırken şifreli keystore blob'u ile seyahat eder.
2. **Hafıza** — ADD-only bağlam grafiği (`state.json`: `memory.nodes/edges`,
   `graph_merkle` bütünlük mührü, `ledger_tip` zincir-bağlantısı).
3. **Defter** — hash-zincirli JSONL (`ledger.jsonl`); her koşum bir `charge` (ücret +
   ölçüm kanıtı), hibe/gider `grant`/`fee` kayıtlarıdır.

Kod (agent.wasm) bu üçünden **ayrı** seyahat eder: snapshot kimlik+hafıza+defter taşır,
kod her node'a ayrıca kurulur. Bu ayrım taşıma değişmezinin ta kendisidir.

## 1. Önkoşullar

```bash
python3 --version      # 3.14 ile kanıtlandı; 3.11+ beklenir
pip install pynacl     # tek bağımlılık (ed25519 + XChaCha20-Poly1305)
```

- Koşum motoru: wasmtime v48.0.1 (pinli ikili `tools/bin/wasmtime`, RFC-002 E-5).
- WASI hedefi: **WASI 0.3 / component** (`package.code.target = "wasi-0.3/component"`).
  (Bağlam: WASI 0.3.0 Eylül 2026'da ratifiye edildi — bkz. README Referanslar.)

## 2. Beş dakikada ilk ajan

```bash
# 1) kod: minimal bir WASI component (örnek: tests/agent-src/, Rust)
cargo build --release --target wasm32-wasip2          # örnek ajan bu hedefle derlenir

# 2) manifest: RFC-001 v0.1-FINAL şeması (bkz. specs/manifest-0.1.0.schema.json)
#    en düşük iş: tests/vectors/tc-a1/tamga.json'ı kopyala, package.name'i değiştir

# 3) imzala ve doğrula
python3 tamga_validator.py keygen tests/keys/alici
python3 tamga_validator.py sign  <pkg>/tamga.json <pkg>/agent.wasm tests/keys/alici/seed.hex
python3 tamga_validator.py validate <pkg>             # ACCEPT görene dek

# 4) koşum: agent_id stdout'tan alınır (diske yazılmaz — D3)
AGENT_SEED=$(python3 tamga_runner.py keygen | python3 -c 'import sys,json;print(json.load(sys.stdin)["seed_hex"])')
export TAMGA_KS_PASSPHRASE="..."                       # sizin seçiminiz; simnet'te sabit
python3 tamga_runner.py run <pkg> --seed "$AGENT_SEED" --note "ilk koşum"
```

`run` çıktısında: `session`, `wall_ms`, `cpu_saat`, `ram_gb_sn`, `io_mb`, `fee_sim`,
`stdout_sha256` — hepsi charge kaydına zincirli yazılır (RFC-003 D1/D2).

## 3. Manifest alanları — hızlı kılavuz

| Alan | Kural | Sınır |
|---|---|---|
| `spec_version` | `"0.1.0"` sabit | başka sürüm = RED |
| `package.name` | `[a-z0-9][a-z0-9-]{2,31}` | kanonik sahip; snapshot `pkg_name`'i buradan |
| `package.version` | semver `x.y.z` | — |
| `package.code.wasm_sha256` | 64-hex | dosyayla birebir; sapma = RED |
| `package.code.target` | `"wasi-0.3/component"` sabit | D6 |
| `runtime.min_proof_level` | P0/P1/P2 | — |
| `runtime.limits` | `memory_mb [16,4096]`, `cpu_ms_per_run [1,60000]`, `io_mb_per_run [0,1024]` | tamsayı; bool/string = RED |
| `memory` | snapshot/şifre sabitleri | değiştirilemez |
| `capabilities` | ⊆ {fs, net, clock, env, random}, ≤5, unique | fs/net default-deny (D4) |
| `payment.schemes` | `["tamga-sim/1"]` | simnet; gerçek değer Faz 4 |
| `signature` | ed25519, `sig` boşaltılarak JCS | 128-hex |

Şema tartışması görmek istemiyorsan: `jsonschema` ile cross-check testi birebir
aynı kararları veriyor (34/34 — kanit/VALIDASYON/2026-09-05/).

## 4. Hafıza: ADD-only graf

- Düğüm türleri: `note` (serbest), `fact` (iddia), `session_marker` (runner otomatik).
- Yazım **runner-side**'dır (v0); ajan wasm'ı yalnız stdout üretir. MERGEN köprüsü ile
  ders aktarımı:

```bash
python3 tamga_runner.py memory <pkg> --import-json dersler.json  # ADD-only birleştirme
python3 tamga_runner.py memory <pkg> --search "anahtar-kelime"
```

- ADD-only: mevcut düğüm/kenar **yazılamaz/silinemez**; aynı kaynak tekrar import edilirse
  atlanır (idempotent — quickstart kanıtında `added 1 skipped 4`).
- `graph_merkle`: düğüm+kenarların sıralı hash'i. Import'ta mühür uyuşmazsa RED (17).
  Sınır (Audit-7 A3): seed'i bilen biri tutarlı mühür üretebilir; savunma seed'siz
  host'a karşıdır.

## 5. Muhasebe: charge + zincir

```bash
python3 tamga_runner.py grant <pkg> 0.01 "geliştirme-hibesi"    # test bakiyesi
python3 tamga_runner.py ledger <pkg>                            # bakiye özeti
python3 tamga_runner.py ledger-verify <pkg>                     # zincir doğrulaması
```

- Zincirsiz pkg'de `ledger-verify` `ok=true, lines=0` döner (boş zincir meşrudur);
  kırık zincir `reason 14` verir.
- Zincir: her kayıt `seq` (1-bazlı) + `prev` + `h = sha256(prev | jcs(kayıt))`.
  Bir alan değişse zincir kırılır. Gömülü zincir import'ta **kuruluş-öncesi** doğrulanır
  (Audit-7 takviyesi).

## 6. Taşıma (projenin kalbi)

```bash
python3 tamga_runner.py export <pkg> -o snapshot.tsg --seed "$AGENT_SEED"
# hedef node: kod önceden kurulmalı (kod ayrı seyahat eder!)
python3 tamga_runner.py import snapshot.tsg <yeni-pkg>
```

- Snapshot ~1.8KB (örnek ajan); şifreli: parolayı bilmeyen host gövdeyi okuyamaz
  (AT-001d: 0 düz-metin sızıntısı).
- Import RED kodları seni korur: 7 (64MiB üstü), 8 (oturum-rollback/replay), 9
  (kimlik taklidi), 14 (kırık gömülü zincir), 17 (merkle uyuşmaz) — hepsi negatif
  vektörle testli (AT-001f).

## 7. Geliştirici kontrol listesi (PR'dan önce)

- [ ] `tamga_validator.py validate <pkg>` → ACCEPT
- [ ] `run` → ACCEPT; `fee_sim` makul; `stdout_sha256` üretildi
- [ ] `ledger-verify` → ok
- [ ] export → yeni dizin → import → `agent_id` birebir aynı, oturum devam ediyor
- [ ] limits senaryona uygun (aşırı cömert limit = ajanın kendi parası)
- [ ] capabilities en küçük küme (fs/net istemiyorsan hiç isteme — default-deny zaten keser)

## 8. Dürüst sınırlar (v0, Faz 1)

- **simnet:** tutarlar `*_sim` — gerçek değer taşıma Faz 4'tür (çift tetikleyici).
- **tek makine:** node-cosign yok; gömülü zincir taze node'da ajan-iddiasıdır
  (Audit-7 F25 — açık, belgeli, kalıcı çözüm RFC-003 Açıksoru-4).
- **`cpu_ms_per_run` = wall-clock** timeout (E-9c): ağır host yükünde önemsiz ajan da
  reason-11 olabilir — bu ölçüm değil zamanlama konusudur.
- İkinci örnek ajan (MERGEN-köprülü davranış) Faz 2'de derlenir; bugün akış kanıtlı:
  `memory --import-json` (quickstart.log) + audit-7.log önkoşul koşumları.

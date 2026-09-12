# Ajan Geliştirici Rehberi (v0) — Türkçe

> Aşağıdaki her komut bu deponun kanıt-günlüklerinde kanıtlanır ve bugün çalışır.
> Derin-tasarım belgeleri İngilizce'dir; bu dosya Türkçe geliştirici-yüzeyidir.
> İngilizce ayrıntı-sürümü: [AGENT-GUIDE.md](AGENT-GUIDE.md).

## 1. Zihin-modeli (2 dakika)

Bir Tamga-ajan üç-şeydir:

1. **Kimlik** — ed25519 anahtar-çifti. Seed **asla diskte düz-metin durmaz**; yalnız
   anlık-görüntünün şifreli keystore-blob'u içinde yolculuk eder.
2. **Hafıza** — YALNIZ-EKLEME bağlam-grafiği (düğümler asla yeniden-yazılmaz/silinmez).
3. **Defter** — hash-zincirli makbuz-günlüğü; her koşum bir `charge` (ücret+ölçüm).

Kod (`agent.wasm`) bu üçünden **ayrı** taşınır. Anlık-görüntü kimlik+hafıza+defter
taşır; kod her-node'da kurulu olur. Bu-ayrım taşınabilirlik-değişmevidir — alıcı-node
koşmak-üzere-olduğunu-doğrulayabildiği-için.

## 2. Önkoşullar

```bash
python3 --version      # 3.14'te kanıtlı; 3.11+ beklenir
pip install tamga-protocol   # PyPI'dan (tek bağımlılık pynacl; wheel'de hazır)
# motor: wasmtime v48.0.1 (pinli) — ilk kurulum: tamga doctor / tests/setup.sh
```

## 3. İlk-ajanınız (komik-kolay yol)

```bash
tamga quickstart ilk-ajanim      # şablon-ajan + taze-anahtar + imza + İLK KOŞUM + doğrulama
```

Elle-yol:

```bash
# 1) kod — minimal WASI bileşeni (örnek: tests/agent-src/, Rust)
cargo build --release --target wasm32-wasip2

# 2) manifest — tests/vectors/tc-a1/tamga.json kopyala, package.name değiştir
#    şema: specs/manifest-0.2.0.schema.json (RFC-001 v0.1-FINAL + RFC-007 v0.2)

# 3) imzala ve doğrula
python3 tamga_validator.py keygen tests/keys/alice
python3 tamga_validator.py sign  <pkg>/tamga.json <pkg>/agent.wasm tests/keys/alice/seed.hex
python3 tamga_validator.py validate <pkg>            # ACCEPT'a-kadar

# 4) koş — ajan-kimliği yalnız stdout'tan (asla diske-yazılmaz)
AGENT_SEED=$(python3 tamga_runner.py keygen | python3 -c 'import sys,json;print(json.load(sys.stdin)["seed_hex"])')
export TAMGA_KS_PASSPHRASE="..."                      # kendi-seçimin
python3 tamga_runner.py run <pkg> --seed "$AGENT_SEED" --note "ilk koşum"
```

`run` çıktısında `session`, `wall_ms`, `cpu_saat`, `ram_gb_sn`, `io_mb`, `fee_sim`,
`stdout_sha256` — hepsi makbuza zincirlenir.

## 4. Manifest-alanları — hızlı-başvuru

| Alan | Kural | Sınır |
|---|---|---|
| `spec_version` | `"0.2.0"` pinli (0.2.0-flip 2026-09-11; 0.1.0 → RED) | başkası → RED |
| `package.name` | `[a-z0-9][a-z0-9-]{2,31}` | kanonik-sahip |
| `package.code.wasm_sha256` | 64-hex | dosyayla-birebir-eşleşmeli |
| `runtime.min_proof_level` | P0/P1/P2 | — |
| `runtime.limits` | memory_mb [16,4096] · cpu_ms_per_run [1,60000] · io_mb_per_run [0,1024] | tamsayı; bool/dize → RED |
| `capabilities` | ⊆ {fs, net, clock, env, random}, ≤5 | fs/net v0'da default-deny |
| `payment.schemes` | `["tamga-sim/1"]` | simnet; gerçek-değer Faz-4 |
| `signature` | JCS üzerinde ed25519 (`sig` boşaltılarak) | 128-hex |

## 5. Girdi-bağlı iş (anlam-taşıyan makbuzlar)

```bash
python3 tamga_runner.py run <pkg> --seed "$AGENT_SEED" \
    --input job.json --require-proof
```

- `--input` (≤1 MiB): girdi-hash'i makbuza girer → aynı-iş yeniden-koşulabilir ve
  kanıtlanabilir; aşım → yürütmeden-önce-red.
- `--require-proof`: ajan-stdout'u kendi-çıktısı-üzerinde `TAMGA:<fnv1a64>` damgasıyla
  bitmeli. Koşucu makbuzu-imzalamadan-doğrular. (Örnek-ajan `tests/agent-src`'de-Rust.)

## 6. Muhasebe

```bash
python3 tamga_runner.py grant <pkg> 0.01 "dev-funding"   # test-bakiyesi
python3 tamga_runner.py ledger <pkg>                     # bakiye-özeti
python3 tamga_runner.py ledger-verify <pkg>              # zincir-doğrulaması
python3 tamga_bootstrap.py project-head <pkg>            # zincirbaşı → batch-yaprak izdüşümü
```

Zincirsiz-paket `ok=true, lines=0` ile-geçer (boş-zincir-yasal); kırık-zincir → neden 14.
Her-kayıt `seq` + `prev` + `h = sha256(prev | jcs(record))` — tek-bayt-değişiklik-zinciri-kırar.
`project-head` (AT-023) aynı-zinciri-yeniden-oynar-ve-ucu-RFC-009-batch-yaprak-şemasıyla
kodlar — sunum-paritesi: çıktı-izdüşüm-matematiğini-iddia-eder,-yabancı-registry-geçerliliğini ASLA.

## 7. Göç (projenin-kalbi)

```bash
python3 tamga_runner.py export <pkg> -o snapshot.tsg --seed "$AGENT_SEED"
# hedef-node'da: kod önceden-kurulu-olmalı (kod-ayrı-taşınır!)
python3 tamga_runner.py import snapshot.tsg <new-pkg>
```

- Anlık-görüntü şifrelidir: parola-yolayan-host gövdeyi-okuyamaz.
- İthalat-redleri-sizi-korar: 7 (çok-büyük), 8 (oturum-geri-sarma), 9 (kimlik-sahteciliği),
  14 (gömülü-zincir-kırık), 17 (merkle-uyumsuzluğu), 18 (sahiplik-uyumsuzluğu).
- Node-işletiyorsanız ve zincir-iddiaları-cosign-istiyorsanız: `import --cosign-policy L1
  --node-trust <dosya>` (node-anahtarı: `keygen-node <dizin>`; varsayılan-politika L0).

## 8. Dış-çapalar — yabancı-raylardan-alma (RFC-009 alıcı-tarafı)

İki-bağımsız-doğrulayıcı;-ikisi-de-stdlib-saf;-ikisi-de-fail-loud:

```bash
python3 tamga_pugio_receiver.py <external_anchor.jsonl>
# PUGIO-köprüsü-çıpa-satırlarını-doğrular: anchor_id = SHA256(head|merkle_root|event_count)[:32]
# tek-RED-satırı-tüm-dosyayı-RED-ler (fail-loud); bilinmeyen-bridge_version → RED

python3 tamga_pugio_ingest.py <bundle.json> > receipt.jsonl
# alıcı-adım-2: K0-bundle tam-gövde-doğrulaması (zincir-bağı + olay-başı-kanıt +
# merkle-kökü + başlık + olay-sayı-çaprazı) → deterministik-Tamga-doğrulama-makbuzu
# (doğrulayıcı: 81-mergen-ingest/v1; karar-SAĞLAM-ya-da-RED); RED-bundle MAKBUZ ÜRETMEZ.
```

Sınır-kararın-içinde-taşınır: bunlar sunum-paritesini-doğrular (çıpa-matematiği-ve
bundle-gövdesi), yabancı-registry-geçerliliğini ASLA — o-origin'in-sözleşmesine-ait.
Kanıt-ailesi: AT-024 (alıcı) / AT-025 (ingest); yavaş-süitte-47-48.-kontroller.

## 9. Hafıza-köprüsü

### tamga-memory/1 ithalat-formatı (--import-json)

Düğüm/kenar-şeması normatiftir: [RFC-004](RFC-004-context-graph.md).

```json
{
  "format": "tamga-memory/1",
  "nodes": [
    {"id": "m1", "kind": "note", "text": "her-ne-ise", "ts": "2026-09-05T12:00:00Z"}
  ],
  "edges": []
}
```
`edges` girdileri `{"src": "m1", "dst": "m2", "kind": "rel"}`. İD'ler ithalatta
deterministik `x<sha256[:12]>` hash'ine-dönüşür — aynı-dosyayı-yeniden-ithal-etmek
hiçbir-şey-eklemez (0-eklendi, N-atlandı). Yabancı-ihraçlardan bu-dosyayı-üretmek-için:
`tools/memory_import.py` (mem0/Letta/Zep/JSONL/genel) — bkz. README.

```bash
python3 tamga_runner.py memory <pkg> --import-json dersler.json   # YALNIZ-EKLEME birleşim
python3 tamga_runner.py memory <pkg> --search "anahtar-kelime"
```

Aynı-kaynağı-yeniden-ithal-etmek-ıdempotent (varsa-atlanır).

Başka-hafıza-deposundan-mı-geliyorsunuz? Önce-çevirin — Mem0/Letta/Zep ihraçları ve
düz-JSON-satırları otomatik-tanınır:

```bash
python3 tools/memory_import.py --from export.json --format auto -o cevrilmis.json
python3 tamga_runner.py memory <pkg> --import-json cevrilmis.json
```

## 10. Bir-şey-çalışmadığında

- `validate` RED verirse: hata-mesajındaki-neden-kodu [RFC-002](RFC-002-runner.md)'deki
  RED-taksonomisidir — kuru-tahmin-değil, çıktıyla-yasal-rehber.
- `import` RED verirse: yukarıdaki-koruma-redleri-masasında-eşleştirin.
- Zincir-iddiasını-bağımsız-doğrulamak-isterseniz: `tamga verify-mini` (standart-
  kütüphane-yalnız; [REPRODUCE.tr.md](REPRODUCE.tr.md) §0).

## 11. Ağ-yetenekleri (beyanlı-egress)

Ağ-varsayılan-değil, **YETENEKTİR**: manifest/net.json'da-beyan-edilirse-vekil-tek-kenarından
çıkar (her-istek-kanıt-günlüğünde); beyansız-paketler-eski-düz-metin-davranışta-kalır.
Protokol-detayı: [RFC-005](RFC-005-declared-egress.md) (vekil) · [RFC-006](RFC-006-agent-net-shim.md) (ajan-tarafı-şim).

# Tamga Kabul Testleri — AT-001: Taşıma ve Ödeme Döngüsü

> Kural: Kırmızı test yoksa iş bitmiş sayılmaz. Kanıt = komut çıktısı + log dosyası; "çalışıyor gibi" kanıt değildir.
> Bu test T+90 kilometre taşının kapıdır. Ağ/ödeme testleri (AT-002+) v1 fazına aittir, burada tanımlanmaz.

## Ortam (simnet)

Tek fiziksel makinede iki Runner süreci:

- `node-A` — ayrı dizin + liman
- `node-B` — ayrı dizin + liman; "operatör kabuğu" B üzerinde, node-A'nın anahtarlarına erişimi olmayan ikinci kullanıcı gibi davranır.

Ajan paketi: minimal bağlam grafiği (≥3 düğüm) + manifest + WASM kodu.

## Alt Testler

### AT-001a — Manifest Doğrulama
- **Given:** geçerli paket + bilinçli bozuk varyantlar (eksik alan, hatalı sürüm, imza uyumsuz)
- **Then:** geçerli paket kabul; her bozuk varyant açık hata mesajıyla RED.
- **Kanıt:** CLI çıktısı, reddedilen her varyant için satır.

### AT-001b — Şifreli Snapshot Export/Import
- **Given:** node-A'da durumu dolu çalışan ajan
- **Then:** stop → export tek şifreli dosya üretir → node-B import eder → ajan **aynı ID** ile kaldığı yerden devam eder.
- **Kanıt:** dosya hash'i, import log'u, ajanın kendisinden alınan durum özeti.

### AT-001c — Kaynak Ölçüm + Simüle Ödeme
- **Given:** node-B'de ≥30 sn koşum
- **Then:** CPU-saat/RAM/IO sayaçları ledger kaydına düşer; tutar formülden hesaplanır (`ucret = cpu_saat * fiyat + ram_gb_sn * fiyat + io * fiyat`) ve simüle ödeme kaydı oluşur.
- **Kanıt:** ledger JSONL kaydı; formül + çıktı eşleşmesi.

### AT-001d — Host-Körlük (at-rest)
- **Given:** node-B üzerindeki operatör kabuğu
- **Then:** snapshot dosyasında düz metin bağlam içeriği aranamaz (grep negatif); anahtarsız decrypt başarısız.
- **Kanıt:** grep çıktısı (0 eşleşme), decrypt hata çıktısı.

### AT-001e — Kimlik ve Hafıza Sürekliliği
- **Given:** taşıma öncesi/sonrası oturumlar
- **Then:** ID_A aynı; ajan kendi belleğine dayanarak taşıma öncesi sorulan 3 bilgiyi taşıma sonrası da doğru yanıtlar.
- **Kanıt:** iki oturumun yanıt logları yan yana.

### AT-001f — Snapshot-Import Negatif Vektörleri (2026-09-05, Dilim-9)
- **Kapsam:** E-3'te kayıtlı reason_code'ların (7/8/9) beklenmedik-KABUL kapanışı —
  *kaydı yapılmış reddin testi yoksa o kod iddia değildir.*
- **tc-s7 (reason 7):** SAFE_SNAP_MAX (64MiB, Audit-1 F1) aşan snapshot import'ta RED.
- **tc-s9 (reason 9):** header `agent_id` alanı geçerli-biçimli ama sahte kimlikle
  değiştirilir; keystore gerçek seed'i çözümler, pubkey≠header → RED (kimlik taklidi
  yalnız header düzeyinde mümkün değil).
- **tc-s8 (reason 8):** hedef node'un `sessions` sayacı snapshot'tan ileriye çekilir;
  aynı snapshot'ın yeniden import'u rollback sayılır → RED (replay/geri-sarma engeli).
- **Kanıt:** `bash tests/negative_snapshots.sh` → `kanit/AT-001/<tarih>/AT-001f-vektorler.log`
  (4 kontrol: 3 RED beklentisi + s8 önkoşulu ACCEPT). Takıma entegre: run_all.sh
  AT-001f bölümü (tek toplu kontrol, 17 kontrol toplam).

### AT-003 — Node-Cosign Vektörleri (2026-09-05, Dilim-10)
- **Kapsam:** F25 çözümünün (gömülü zincir node-sertifikasyonu) reddetme davranışı —
  iki katman: `node_id` zincir-hash'inin İÇİNDE (kimlik bağlanır), `node_sig` h'yi imzalar
  (hash-girdisi dışında — kurcalama imza kontrolünde yakalanır).
- **tc-n1 (pozitif):** L1 + güvencili node → import ACCEPT.
- **tc-n2:** bozuk `node_sig` → ledger-verify RED (14).
- **tc-n3:** `node_id` takası → zincir-hash kırığı (RED; kimlik hash'te bağlı).
- **tc-n4:** node_sig'siz zincir + L1 → RED (node_sig_eksik) — kademeli düşürme kapalı.
- **tc-n5:** L1 + yabancı node listesi → RED (node_id_güvenilmeyen) — F25'ün L1 kapanışı.
- **tc-n6:** node_sig'siz zincir + L0 → ACCEPT (geriye-uyum; default davranış değişmedi).
- **Kanıt:** `bash tests/negative_cosign.sh` → `kanit/AT-003/<tarih>/AT-003-cosign.log`
  (6/6) + Audit-8 adversarial (kanit/GUVENLIK/2026-09-05/audit-8.log: A1 güçlü düşman
  L1 RED / L0 bilinen-kalıntı OQ-1'de; A2 imza-katmanı RED; A3 kısmi-cosign RED).
  Takıma entegre: run_all.sh AT-003 bölümü (17 kontrol).

## Kabul Kriterleri

| Test | Kırmızı şartı | Geçme şartı |
|---|---|---|
| 001a | testler KODDAN ÖNCE yazılır ve ilk koşuda kırmızıdır | tüm varyant davranışı doğru |
| 001b | — | taşıma kayıpsız, ID aynı |
| 001c | — | sayaçlar ±%5 doğrulukla ölçülür |
| 001d | — | hiçbir düz-metin sızıntısı yok |
| 001e | — | 3/3 bilgi doğru |
| 001f | negatif vektörler KODDAN ÖNCE yazılır | 7/8/9 reddetme davranışı doğru |
| 003 | cosign vektörleri çözümle BİRLİKTE yazılır | L1 reddetme + L0 geriye-uyum doğru |

## Tek-Komut Takım (2026-09-05 gerçeklemesi)

`tests/run_all.sh` — 17 kontrol, idempotent sandbox, POSIX çıkış-semantiği,
PIPESTATUS boru-koruma. Bölümler: AT-001a (6 vektör) · AT-001f (3 negatif vektör,
toplu) · grant/koşum/zincir-ucu · F21 truncate (14) · merkle kurcalama (17) ·
göç+gömülü zincir (F24 kapanışı) · AT-001d özü (düz-metin taraması) ·
RUN_SLOW=1: c30 wall-ölçümü (AT-001c özü). Kanıt: kanit/REGRESYON/.

## Kanıt Kayıt Formatı

`kanit/AT-001/<tarih>/<test-id>.log` — timestamp + komut + çıktı. Faz kapısı (ROADMAP Faz 1) bu dosyaların varlığına bakar.


## AT-004 — Girdi-bağlama (Dilim-11, 2026-09-05)

**Amaç:** ajan-işine girdi girebilsin; girdi makbuza kriptografik bağlansın (Tur-4 telafi-2).

| # | Kontrol | Kanıt |
|---|---|---|
| 1 | `--input is.json --require-proof` → makbuzda `input_sha256` = sha256(kaynak-dosya) | run_all D11 bölümü |
| 2 | Aynı girdi ×2 koşum → birebir aynı `stdout_sha256` (deterministik replay) | run_all D11 bölümü |
| 3 | Farklı girdi → farklı `stdout_sha256` (ayırt-edicilik) | e2e batarya kanit/ |
| 4 | `--input > 1MiB` → RED reason-10 `input_invalid` (koşum/ücret yazılmadan) | e2e batarya |
| 5 | `--require-proof` + bozuk `TAMGA:` satırı → RED 12 `output_proof_mismatch` | runner D11; FNV çift-gerçekleme (rust↔python) uyumlu |

**Sözleşme (RFC-003 D9):** ajan stdout'un son satırı `TAMGA:<fnv1a64(stdout[:-len])]`; runner
koşum-anında doğrular. `input_sha256` yalnız `--input` verildiğinde makbuza girer.
**Ajan tarafı:** `tests/agent-src/src/main.rs` (stdin okur; FNV-1a 64 parmakizi).

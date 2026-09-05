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
  AT-001f bölümü (tek toplu kontrol, 15 kontrol toplam).

## Kabul Kriterleri

| Test | Kırmızı şartı | Geçme şartı |
|---|---|---|
| 001a | testler KODDAN ÖNCE yazılır ve ilk koşuda kırmızıdır | tüm varyant davranışı doğru |
| 001b | — | taşıma kayıpsız, ID aynı |
| 001c | — | sayaçlar ±%5 doğrulukla ölçülür |
| 001d | — | hiçbir düz-metin sızıntısı yok |
| 001e | — | 3/3 bilgi doğru |
| 001f | negatif vektörler KODDAN ÖNCE yazılır | 7/8/9 reddetme davranışı doğru |

## Tek-Komut Takım (2026-09-05 gerçeklemesi)

`tests/run_all.sh` — 15 kontrol, idempotent sandbox, POSIX çıkış-semantiği,
PIPESTATUS boru-koruma. Bölümler: AT-001a (6 vektör) · AT-001f (3 negatif vektör,
toplu) · grant/koşum/zincir-ucu · F21 truncate (14) · merkle kurcalama (17) ·
göç+gömülü zincir (F24 kapanışı) · AT-001d özü (düz-metin taraması) ·
RUN_SLOW=1: c30 wall-ölçümü (AT-001c özü). Kanıt: kanit/REGRESYON/.

## Kanıt Kayıt Formatı

`kanit/AT-001/<tarih>/<test-id>.log` — timestamp + komut + çıktı. Faz kapısı (ROADMAP Faz 1) bu dosyaların varlığına bakar.

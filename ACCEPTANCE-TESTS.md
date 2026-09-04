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

## Kabul Kriterleri

| Test | Kırmızı şartı | Geçme şartı |
|---|---|---|
| 001a | testler KODDAN ÖNCE yazılır ve ilk koşuda kırmızıdır | tüm varyant davranışı doğru |
| 001b | — | taşıma kayıpsız, ID aynı |
| 001c | — | sayaçlar ±%5 doğrulukla ölçülür |
| 001d | — | hiçbir düz-metin sızıntısı yok |
| 001e | — | 3/3 bilgi doğru |

## Kanıt Kayıt Formatı

`kanit/AT-001/<tarih>/<test-id>.log` — timestamp + komut + çıktı. Faz kapısı (ROADMAP Faz 1) bu dosyaların varlığına bakar.

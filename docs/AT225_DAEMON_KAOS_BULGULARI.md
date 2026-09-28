# AT-225 — Daemon Kaos-Testi: Bulgular

**Test:** `tests/at225_daemon_kaos_dikis.sh` (5 senaryo, py-evm lokal — para YOK)
**Görev-kaynağı:** Lead 2026-09-28 — araştırmanın bulduğu 3. boşluk: "daemon loop'unun
ardışık-başarısızlık durumunda ne yapacağı (backoff, alarm) dokümante edilmemiş."

## Senaryolar ve sonuçlar

| Senaryo | Kaos | Beklenti | Sonuç |
|---|---|---|---|
| **K4** | yok (normal) | tek-doğru-tx | **PASS** — status=1, gasUsed 45379, replay-cache yazıldı |
| **K1** | 400 ms yapay-RPC-gecikmesi | gecikmeye-rağmen doğru-tx | **PASS** — status=1; elapsed ≥ gecikme; gecikme çalışmayı bozmuyor |
| **K2a** | 3× ardışık `TamgaRelayerError` | loop-durmaz, sonra toparlanır | **PASS** — 3 hata-logu + toparlanma |
| **K2b** | sürekli `OSError` (gerçek-RPC-hata) | fail-closed (yanlış-tx yok) | **PASS** — yanlış-tx GÖNDERİLMEDİ, ama **loop CRASH eder** (bulgu) |
| **K3** | gaz-spike (gas=21000, intrinsic-altı) | fail-closed RC_TX_FAILED | **PASS** — `RED 28 fulfill-tx-hata: Insufficient gas`, fulfilled boş |

## Bulgular (test-çıktısından-okunan-gerçekler)

### BULGU-1: `fetch_requests`'in `get_logs` çağrısı SARILMAMIŞ

`tamga_oracle_relayer.py`'de:
- `submit_fulfillment` **tüm** exception'ları `TamgaRelayerError(RC_TX_FAILED)`'a
  sarar (satır ~745, AT-203) → daemon crash-ETMEZ, fail-closed.
- **`fetch_requests`'in `get_logs` çağrısı sarılmamış** (satır ~673). Gerçek bir
  RPC/network hatası (`OSError`, `TimeoutError`, web3 exception) doğrudan yayar.

`daemon_loop` (satır ~829) `for req in transport.fetch_requests(cursor)`'u bir
`try` içine almış, ama **sadece `except TamgaRelayerError`** yakalar (satır ~857).
Sonuç: **genel-RPC-hatası daemon_loop'u CRASH eder.**

K2b bu gerçeği kanıtlar: daemon öldü, ama **hiçbir yanlış tx göndermedi**
(fail-closed İlkesi sağlanır — crash en güvenli fail-closed'dur, systemd
`Restart=always` ile çift-katman). Yine de bu, dokümante edilen "döngü DURMAZ"
iddiasıyla **çelişir**: genel-ağ-hatasında döngü durur.

**Öneri (değişiklik-yapılmadı):** `fetch_requests`'in `get_logs` çağrısını
`try/except Exception → TamgaRelayerError(RC_RPC)` ile sarmak, `submit_fulfillment`
ile aynı desende. Maliyet: ~6 satır.

### BULGU-2: cursor cycle-sonunda İLERLER — hata-sırasındaki request kaçar

`daemon_loop` cursor'u her cycle'ın-sonunda `block_number`'a yükseltir (satır ~861,
AT-205 için-eklendi). Bu, hata-sırasında-gelen bir request'in **kaçırılmasına** yol
açabilir: hata döngüsü sırasında cursor ilerler, hata kesildiğinde eski request
cursor'ın-arkasında-kalır → `fromBlock: cursor` onu bulamaz.

Test-bunu-açıkça-kanıtlar (ilk-tasarımda K2a başarısız-oldu): toparlanmayı
test-etmek-için hata-sırasında yeni-request-tetiklemek-gerekti.

**Bu bir güvenlik-açığı DEĞİL** — request sadece gecikir (bir-sonraki-tarama veya
backfill ile-yakalanır). Ama **davranış dokümante-edilmemişti**, ki-araştırmacının
tam-sorduğu-buydu.

### BULGU-3: backoff YOK — sabit `interval_s`

`daemon_loop` hata-sonrası **sabit** `time.sleep(interval_s)` yapar (15 sn varsayılan).
Üstel-backoff YOK, alarm YOK. Hata-logları message-RED olarak-yazılır (`[relayer]
poll-hatası (devam)`), ki bu systemd-journal'da görülebilir — ama programatik
bir alarm-kanalı YOK.

Araştırmacının sorusunun-cevabı: **backoff yok, alarm log-bazlı.** Tasarım-
kararı: "döngü DURMAZ" (docstring) + systemd `Restart=always` çift-katmanı.

### BULGU-4: dead-code `except OSError` (küçük)

`daemon_loop`'un cursor-güncelleme-bloğu (satır ~860-865):
```python
try:
    cursor = int(transport._w3.eth.block_number)
except Exception:
    pass
except OSError as e:          # ← ÖLÜ-KOD: üstteki Exception hepsini-yakalar
    log(f"[relayer] ağ-hatası (devam): {e}")
```
`except Exception` `OSError`'ı-da-içerdiği-için ikinci-blok asla-çalışmaz. Zararsız
ama yanıltıcı (birisi burada-ağ-hatası-loglaması-olduğunu-düşünebilir).

## Sınırlar (dürüst)

- **K2b crash'i "fail-closed" sayıldı** — bu bir yorumdur, gerçek bir tx-güvenliği
  ölçümü değil. Crash-sırasında-yanlış-tx-yok doğrudur, ama daemon-ölmesi üretimde
  systemd-restart-güdümlü-duraklama demektir.
- **K3 gaz-spike'ı py-evm'de-simüle-edildi** — gerçek-şebeke gaz-pazarı-dinamiği
  yok. `gas=21000` intrinsic-altı seçimi gerçekçi bir spike-benzeşimi ama birebir
  değil.
- **K1 gecikmesi 400 ms** — gerçek RPC-gecikmesi saniyeler-olabilir; test sadece
  "gecikme-çalışmayı-bozmaz"ı-kanıtlar, gecikme-altında-zaman-aşımı davranışını değil
  (zaman-aşımı-yolu-da-test-edilemedi — daemon_loop'ta-zaman-aşımı-yok).
- **canlı-zincir-YOK** (Para-YASAK kısıtı): tüm-senaryalar lokal py-evm'dir.
  Canlı-Base-mainnet'te RPC-kesintisi farklı-davranabilir.

## KANIT

```
bash tests/at225_daemon_kaos_dikis.sh → PASS (3× ardışık-yeşil)
K4 status=1 gasUsed=45379; K1 gecikme-altında-aynı; K2a 3-hata+toparlanma;
K2b crash-ama-yanlış-tx-yok; K3 "RED 28 fulfill-tx-hata: Insufficient gas"
```

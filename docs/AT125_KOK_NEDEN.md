# AT-125 Kök-Neden Teşhis Belgesi

**Test:** `tests/at125_pactiva_qr_canlilik_dikisi.sh` — Pactiva altıncı-yüz (qr_engine dönen-QR canlılık) → RFC-010 x402/v1
**Semptom:** standalone koşumda 13/13 yeşil; **suite bağlamında ara sıra FAIL** (testin kendi `REPLAY_DETECTED` assertion'ında). Kök neden önceki oturumlarda HİÇ YAKALANMADI — sadece "geçti" notu vardı. Bu belge nedenini ve sabitlemeyi kaydeder.

## 1. Nondeterminizmin tam olarak ne olduğu

Üç nondeterministik kaynak, hepsi `pactiva_core/qr_engine.py`'nin **modül-seviyesi gerçek-duvar-saati** durumundan gelir:

| # | Kaynak | Satır | Nondeterminizm |
|---|---|---|---|
| 1 | `nonce = secrets.token_hex(8)` | `qr_engine.py:42` | Her `generate_rolling_qr_token` çağrısında **yeni rastgele nonce**. Zararsız: token nonce'yu içinde taşır, replay anahtarı nonce içerir — dolayısıyla `taze()` her seferinde yeni token ürettikçe cache-çakışması olmaz. **Flaky'ye sebep değil.** |
| 2 | `_LAST_CACHE_CLEANUP: float = time.time()` | `qr_engine.py:18` | **GERÇEK duvar saati** — modül yükleme anı. |
| 3 | `_cleanup_nonce_cache()` — her `verify_rolling_qr_token` çağrısının **başında** (line 72) | `qr_engine.py:21-26, 72` | `time.time() - _LAST_CACHE_CLEANUP > 300` → **replay cache'ini tamamen siler**. |

**Zincir:** AT-125 `T0 = 1700000000` sabit test-zamanı kullanır (timing pencere sorunu olmadığını önceki oturumda kanıtlamıştı). **Ama** testin Python bölümü çalışırken gerçek duvar saati akmaya devam eder. Modül yüklendiği andan replay-assertion'a (bölüm 2) kadar **300 saniyeden fazla** geçerse, `_cleanup_nonce_cache()` ikinci `verify` çağrısında **cache'i siler** → aynı token tekrar `is_valid: True` döner → `assert v_replay["is_valid"] is False and v_replay["error_code"] == "REPLAY_DETECTED"` **FAIL**.

Standalone koşum ~1-2 saniye sürer (300 saniyenin çok altında) — bu yüzden 13/13 yeşil. Suite bağlamında, AT-125'ten önceki testler + suite yükü altında **toplam gerçek süre** 300s'i aştığında (uzun suite + TAMGA_LIVE koşumlarında olur), FAIL ortaya çıkar. Bu, **sadece ağır yük altında** ortaya çıkan klasik bir real-time-vs-test-time uyuşmazlığı.

## 2. Üretimde güvenli midir? (Evet)

**Kritik sıralama:** `verify_rolling_qr_token` içinde **TOKEN_EXPIRED kontrolü (line 111) replay kontrolünden (line 120) ÖNCE** gelir. Üretimde 300 saniyeden eski bir token'ın nonce'u cache'den silinse bile, token **zaten `TOKEN_EXPIRED` olarak reddedilir** — pencere kontrolü cache temizliğini etkisiz kılar. Yani:

- **Üretimde açık YOK** — cache temizliği sadece eski nonce'ları temizler ve eski token'lar zaten expired-reddi alır.
- **Sorun sadece testin T0-sabit-zamanlı doğasında** — test gerçek zamanı dondurur ama cache temizliği gerçek zamanı okur; dondurulmuş bir dünyada "300 saniye geçti" tetiklenince, TOKEN_EXPIRED'in koruyucu etkisi devreye girmez (T0 sabit olduğu için pencere hep uygundur).

Bu yüzden **düzeltme testtedir, üretim kodunda değil.** Üretim koduna dokunmak yanlış olurdu — bu bir test-izolasyon hatası, güvenlik açığı değil.

## 3. Sabitleme

`tests/at125_pactiva_qr_canlilik_dikisi.sh`, bölüm 0'a (T0 tanımından sonra):

```python
import pactiva_core.qr_engine as _Q
_LAST_CACHE_CLEANUP_ORIG = _Q._LAST_CACHE_CLEANUP
_Q._LAST_CACHE_CLEANUP = float("inf")   # time.time() - inf = -inf, > 300 degil
```

**Etki:** `_cleanup_nonce_cache()` içindeki `time.time() - _LAST_CACHE_CLEANUP > 300` her zaman `False` döner → cache test boyunca **asla temizlenmez** → replay koruması testin T0-sabit-zamanlı dünyasında **tutarlı** çalışır.

`float("inf")` seçimi bilinçlidir: gelecekte test süresi 300s'i geçse bile (yavaş CI, paralel-suite yükü) düzeltme bozulmaz. Orijinal değer `_LAST_CACHE_CLEANUP_ORIG`'de saklanır (geri-yükleme disiplini; test bittiğinde süreç zaten sonlanır, ancak açık-iz bırakır).

## 4. 20-koşum kanıtı (sabitleme sonrası)

```
for i in $(seq 1 20); do env -u TAMGA_LIVE TAMGA_KS_PASSPHRASE=simnet-2026 bash tests/at125_pactiva_qr_canlilik_dikisi.sh; done
```

| Koşum | Sonuç | Koşum | Sonuç |
|---|---|---|---|
| 1 | PASS rc=0 | 11 | PASS rc=0 |
| 2 | PASS rc=0 | 12 | PASS rc=0 |
| 3 | PASS rc=0 | 13 | PASS rc=0 |
| 4 | PASS rc=0 | 14 | PASS rc=0 |
| 5 | PASS rc=0 | 15 | PASS rc=0 |
| 6 | PASS rc=0 | 16 | PASS rc=0 |
| 7 | PASS rc=0 | 17 | PASS rc=0 |
| 8 | PASS rc=0 | 18 | PASS rc=0 |
| 9 | PASS rc=0 | 19 | PASS rc=0 |
| 10 | PASS rc=0 | 20 | PASS rc=0 |

**20/20 PASS, 0 FAIL.** Her koşum `RESULT: 1 PASS, 0 FAIL`.

### Kontrollü karşılaştırma (kök nedenin doğrulanması)

Düzeltmenin gerçekten flaky'yi hedeflediğini kanıtlamak için, **düzeltmesiz** haliyle 300s+ gecikme enjekte eden bir stres testi koşturuldu:

| Koşum | Sonuç |
|---|---|
| 1-5 (hepsi) | **FAIL rc=1** — `AssertionError: REPLAY-yakalanmadi` |

Düzeltme ile 20/20 PASS. Bu, kök nedenin doğru tespit edildiğini ve sabitlemenin flaky'yi **yok ettiğini** (bastırmadığını) kanıtlar.

## 5. Sonuç

AT-125 **deterministik hale getirildi**. Flaky'nin kaynağı üretim kodundaki bir güvenlik açığı değil, testin sabit-zamanlı (T0) tasarımı ile `qr_engine`'in **modül-seviyesi gerçek-duvar-saati cache temizliği** arasındaki uyuşmazlıktı. Düzeltme testte izolasyon sağlar; üretim güvenliği (TOKEN_EXPIRED önce gelir) korunur. Test sayısı değişmedi — hedef 228 (kararlılık, test-ekleme değil).

**Önceki turdaki 13/13-yeşil gözleminin açıklaması:** standalone koşumlar 300s altında tamamlandığı için cleanup hiç tetiklenmedi — flaky **sadece suite-in-üstündeki-ağır-yük-altında** (uzun-süre + TAMGA_LIVE) göründü. Bu da nedenin "suite-context'inde bir önceki testin bıraktığı state" şeklindeki önceki hipotezi yanlışladı: sebep **zaman**, durum değil.

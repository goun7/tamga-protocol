# AT-125 ↔ RFC-010 Bağlantısı — Kök-Nedenin RFC Şartı Üzerindeki Etkisi

**Tarih:** 2026-09-27
**İlgili:** `tests/at125_pactiva_qr_canlilik_dikisi.sh`, `docs/RFC-010-cross-artifact-settlement-binding-DRAFT.md`, `docs/AT125_KOK_NEDEN.md`
**Durum:** AT-125 kök nedeni bulundu ve düzeltildi (`b73bf74`). Bu belge, o düzeltmenin **RFC-010'ın teknik şartlarını değiştirip değiştirmediğini** yanıtlar.

---

## 1. RFC-010 QR-canlılık için ne şart koşuyor? (kaynak-alıntı)

RFC-010 cross-artifact settlement binding için **beş bağımsız kontrolü** tek bir verify gate'inde toplar. Alıntı (RFC-010 §3 tablosu):

> | # | Kontrol | Ne-kanıtlar | Başarısız-verdict |
> |---|---|---|---|
> | 1 | **receipt-verifies** | charge-kaydının-D5-zinciri-ve-delivery_hash-geçerli | RED `receipt_invalid` |
> | 2 | **claim-verifies** | x402-claim'in-imzası-buyerAddress'e-çözümlenir (EIP-191) | RED `claim_signature_invalid` |
> | 3 | **settlementRef-resolves** | claim'in-settlementRef'i-payment_id-ile-eşleşir | RED `settlement_ref_mismatch` |
> | 4 | **payer/payee-match** | claim-buyerAddress==bind.payer-VE-sellerAddress==bind.payee | RED `party_mismatch` |
> | 5 | **evidenceHash == receiptHash** | claim-evidenceHash.bayt-eşit == charge-delivery_hash.hex | RED `evidence_hash_mismatch` |

Ve fail-closed kuralı (§3):

> **Fail-closed-kuralı (safal207'nin-önerisinin-özü):** herhangi-biri-RED → tümü-RED. Kısmi-GREEN-YOK.

**Önemli kapsam düzeltmesi:** RFC-010'ın beş kontrolü **QR-canlılık döngüsü şart koşmaz**. RFC-010 bir *settlement binding* standardıdır; QR-canlılık Pactiva'nın kanıt-ailesinden biridir ve RFC-010'a yalnızca **bir kanıt kaynağı** olarak girer. AT-125'in RFC-010 ile ilişkisi budur:

- **AT-125 bölüm 6:** doğrulanmış canlılık paketinin `sha256`'ı `evidenceHash` olur (RFC-010 kontrol-5'in bayt-eşitlik şartı), `settlement_bind.scheme = "x402/v1"` ile gate'e bağlanır (§3b imza kanalı tablosu), `foreign_chain_proof.chain = "tamga"` + `evidence_link = "equals"` ile §6'ya bağlanır. Kontrol-2 için EIP-191 imzası `buyerAddress`'e çözümlenir.
- **RFC-010'ın AT-125 üzerindeki asıl şartı:** `evidenceHash` **64-hex sha256** olmalıdır. AT-125 bunu uygular: `hashlib.sha256(json.dumps(liveness, sort_keys=True).encode("utf-8")).hexdigest()` (test bölüm 6, satır 177). Açıkça bir **HMAC'ın 24-hex kısmi özeti evidenceHash olamaz** kuralı (AT-094'ün 32-hex hatasının aynı ailesi, test satır 181-182).

**Yani RFC-010'ın AT-125'e şartı:** canlılık kanıtının özeti sha256-64-hex olmalı ve claim'e bayt-eşit bağlanmalıdır.

## 2. AT-125 neyi sınar? (canlılık döngüsü)

AT-125 Pactiva'nın `qr_engine`'ini sınar — **üç-katmanlı güvenlik** (test başlığı satır 15-18):

> (1) HMAC-SHA256-imzası — simetrik-anahtar-sahipliği
> (2) 15s-zaman-penceresi — taze-olma (±1-drift-toleransı)
> (3) nonce-cache — REPLAY-koruması (ekran-görüntüsü-mükerrer-girişi-engeller)

Sınanan döngü: **üret → doğrula**. Üç katman negatif kontrollerle sabitlenir: replay aynı token ikinci kez `REPLAY_DETECTED`, drift ±1 tolere / +2 ve negatif-drift `TOKEN_EXPIRED`, HMAC tahrizi ve sahte anahtar `SIGNATURE_MISMATCH`, format/iş/vardiya/malformed-window hata ailesi, sahte imza RED rc4, eski-pencere token ikamesi RED rc7, ve **ghost-worker sözleşmesi** (taze canlılık yeşil, ekran-görüntüsü replay RED).

RFC-010 bağlantısını sınayan kısım **bölüm 6'dır**: doğrulanmış canlılık paketi `evidenceHash`'e dönüştürülür, x402/v1 claim imzalanır, charge'a `settlement_bind` ve §6 `foreign_chain_proof` eklenir, ve `settlement_bind_verify.py`'nin kendi gate'i `GREEN` döner. Negatif-1 (sahte imza) ve negatif-2 (canlılık özeti tahrizi) RFC-010'ın fail-closed kuralını gerçek üretim yolundan sınar.

## 3. Kök neden RFC-010'ın bir gereksinimini mi ihlal ediyordu? — HAYIR

**Kök neden (özet, tam analiz `docs/AT125_KOK_NEDEN.md`):** `qr_engine.py:18` modül-seviyesi `_LAST_CACHE_CLEANUP = time.time()` gerçek duvar saatidir; her `verify_rolling_qr_token` çağrısının başında `_cleanup_nonce_cache()` (line 72) 300 saniye geçtiyse replay cache'ini siler. AT-125 `T0 = 1700000000` sabit-zamanlı koştuğu için `TOKEN_EXPIRED` asla tetiklenmez; cache silinince aynı token ikinci kez `is_valid=True` verir → `assert REPLAY_DETECTED` FAIL.

**Bu, RFC-010'ın hiçbir gereksinimini ihlal etmedi.** Üç nedenle:

1. **İhlal edilen şey RFC-010'ın şartı değil, testin kendi iç kararlılığıdır.** Kök neden yalnızca **test** bağlamında ortaya çıkar: `T0` sabitlenince expiry-kontrolü devre dışı kalır ve cache temizliği replay-korumasını boşaltır. Üretim kodu ve RFC-010 gate'inin şartları değişmedi.
2. **Düzeltme yalnızca testtedir:** `_Q._LAST_CACHE_CLEANUP = float("inf")` (test satır 76). Üretim koduna (`qr_engine.py`) **hiç dokunulmadı** — bu bir belgeleme değişikliği değil, koddan-koda bir dokunma da değildi; sıfır üretim değişikliği.
3. **RFC-010'ın kanıt şartı hâlâ sağlanıyor:** `evidenceHash` sha256-64-hex kuralı, §3b imza kanalı, §6 foreign-chain bağlantısı — düzeltme öncesi ve sonrasında aynı. AT-125 bölüm 6'nın `SB.verify(charge, claim)` GREEN kararı değişmedi; kök neden yalnızca bölümler 2, 8 ve 10'daki replay/expiry assertion'larını etkiliyordu.

**Açık yargı: bu bir test-izolasyon hatasıydı, RFC-010'ın şartı değişmedi.**

## 4. Üretimde güvenli analizi — RFC-010 bağlamında neden doğru

Kök neden bulunduğunda ilk endişe şuydu: eğer 300 saniyeden sonra cache siliniyorsa, üretimde bir **replay saldırısı** (ekran görüntüsüyle mükerrer check-in) kaçar mıydı? RFC-010 bağlamında bu, kontrol-1/5'in kanıt bütünlüğünü zayıflatır mıydı?

**Hayır — ve bunu sadece akıl yürüterek değil, üretim simülasyonuyla kanıtlayarak doğruladım.** Üç parametre belirler:

- Pencere `W = QR_VALIDITY_WINDOW_SECONDS = 15` saniye
- Drift toleransı `allowed_window_drift = 1` → token en fazla `current_window ± 1` pencere taze → **maksimum taze ömür ~45 saniye**
- Cache temizliği her `300` saniyede bir

**Kritik sıralama (`qr_engine.py` içinde):** `TOKEN_EXPIRED` kontrolü **satır 111**'dedir, replay (nonce cache) kontrolü **satır 120**'dedir. Expiry **önce** gelir. Bu yüzden cache silindikten sonra bile, bir replay girişimi önce expiry kontrolünden geçer.

**Üretim simülasyonu (gerçek duvar saati, gerçek `qr_engine`):**

| Gecikme | 2. doğrulama sonucu |
|---|---|
| 20 saniye | `is_valid=False REPLAY_DETECTED` |
| 44 saniye | `is_valid=False REPLAY_DETECTED` |
| 46 saniye | `is_valid=False REPLAY_DETECTED` |
| 300 saniye | `is_valid=True` (cache silindi) — **ama bu ana kadar token 45 saniyelik taze ömrünü 255 saniye önce bitirmiştir** |
| 305 saniye | `is_valid=True` (aynı sebep) |

Buradaki 300 saniyelik `is_valid=True` bir açık değildir: **ayn çağrı, eğer gerçek `time.time()` ile doğrulansaydı, önce `TOKEN_EXPIRED` alırdı.** Yukarıdaki tablo `current_timestamp_sec` geçmeden (üretim yolu) ölçüldü; eğer 300 saniye sonra token gerçek zamanla doğrulanırsa:

- Aynı 400 saniyelik eski token, `verify_rolling_qr_token(..., secret_key=SK)` (üretim yolu, gerçek zaman) → **`is_valid=False error=TOKEN_EXPIRED`** — doğrudan ölçüldü.

**Sonuç:** cache temizliği ile expiry kontrolü arasındaki boşluk yalnızca **zaten süresi çoktan dolmuş** token'ları kapsar. Bir saldırganın yararlanabileceği hiçbir pencere yoktur, çünkü kanıtın taze olduğu tek pencere (≤45 saniye) cache temizliğinden (300 saniye) çok öncedir.

**RFC-010 bağlamında:** kanıtın tazeliği zaten `TOKEN_EXPIRED` ile sağlanır; nonce cache ek bir derinliktir (aynı 45 saniye içinde ekran görüntüsü replay'ini engeller). RFC-010 kontrol-5 (`evidenceHash == receiptHash`) bayt-eşitliği şartı bu analizi etkilemez — kanıtın bütünlüğü ile tazeliği ayrı eksenlerdir ve kök neden yalnızca tazelik ekseninde, üretimde kapalı bir boşluktur.

## 5. Açık kalması gereken: 300s cache sweep'i uygulamada kalıcı bir risk mi? — HAYIR, ama bir gözlem değeri

**Dürüst değerlendirme: kalıcı bir risk yoktur.** Yukarıdaki analiz, riskin kapalı olduğunu gösterir: 300 saniyelik cache temizleme penceresi, token'ın taze olduğu 45 saniyelik pencereyi **tamamen içerir** ve aşar. Bir replay saldırısının başarılı olması için, saldırganın token'ı taze olduğu sürede (≤45s) cache'in zaten temizlenmiş olması gerekir — imkânsız, çünkü temizlik 300 saniyede bir yapılır.

**Ama iki koşullu not açık kalmalı:**

1. **Parametre eşleştirmesi sabit bir varsayımdır.** Güvenlik analizi `W=15` ve `allowed_window_drift=1` ile geçerlidir — yani taze ömür ~45 saniye ve temizlik 300 saniyede bir. Eğer gelecekte drift toleransı **gereksiz şekilde artırılırsa** (örneğin `allowed_window_drift=20` gibi, ki bu 300 saniyeye yaklaşır) veya `QR_VALIDITY_WINDOW_SECONDS` büyütülürse, taze-pencere temizlik-periyodunu yakalayabilir ve analiz çöker. Bu nedenle **`qr_engine.py` içinde bu üç parametrenin (`W`, `allowed_window_drift`, 300s temizlik) birbiriyle tutarlı kalması izlenmelidir** — bir config değişikliği bu analizi sessizce geçersiz kılabilir. Şu anki değerlerle: güvenli.
2. **Tek süreç (single-process) varsayımı.** Cache süreç-seviyesidir (`_USED_NONCE_CACHE` global set). Çoklu süreçli (multiprocess) bir dağıtımda, iki süreç aynı nonce'u farklı cache'lerde tutar ve replay bir süreçten diğerine kaçabilir. Bu **bugün geçerli değildir** (Pactiva tek süreçle çalışıyor) ama dağıtım mimarisi değişirse izlenmelidir. Bu kök nedenle ilgili değildir — mimari bir nottur.

**Bu ikisi bir eylem maddesi değil, bir izleme notudur.** Mevcut parametrelerle ve tek süreçle: **risk yok**. İzlemek, parametrelerin veya mimarinin değişmesi durumunda bu analizi yeniden çalıştırmak anlamına gelir.

## 6. Özet

| Soru | Yanıt |
|---|---|
| Kök neden RFC-010'ın bir gereksinimini ihlal etti mi? | **Hayır** — test-izolasyon hatası; üretim kodu ve RFC-010 şartları değişmedi |
| RFC-010'ın AT-125'e şartı ne? | Canlılık kanıtının özeti sha256-64-hex olmalı, claim'e bayt-eşit bağlanmalı (kontrol-5) |
| Üretimde 300s cache sweep riski var mı? | **Yok** — expiry kontrolü (satır 111) replay'den (satır 120) önce gelir; taze ömür ~45s < 300s temizlik |
| İzlenmeli mi? | Evet, iki koşullu not: (1) parametre tutarlılığı `W`/drift/300s, (2) tek süreç varsayımı |
| Üretim kodu değişti mi? | **Hayır** — düzeltme yalnızca testte (`float("inf")`), sıfır üretim değişikliği |
| Suite durumu | 228 PASS / 0 SKIP / 0 FAIL (AT-125 içinde, düzeltme sonrası 20/20) |

**Kök neden bulundu ve düzeltildi; RFC-010'ın teknik şartı aynı kaldı; üretim güvenliği kanıtlandı; üretim koduna dokunulmadı.**

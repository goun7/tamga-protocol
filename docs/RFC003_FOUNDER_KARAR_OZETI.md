# RFC-003 D10 — FOUNDER KARAR ÖZETİ

**Konu:** RFC-003 `docs/RFC-003-ledger.md` §10 — **D10: Settlement anchor** (2026-09-27, #3379)
**Durum:** **v0.2 Revision Candidate — AWAITING FOUNDER APPROVAL** (RFC-003 line 137/146-147)
**Bu belgenin amacı:** kararı verecek kişi için **sadece seçenekler ve sonuçları**. **Kararın kendisi bu belgede DEĞİL** — bu bir bilgi-belgesidir, tavsiye değildir.

---

## 0. Neyin kararı bu?

RFC-003'ün ana gövdesi **v0.1-FINAL — FROZEN** (founder-approved 2026-09-05, RFC-003 line 7). Freeze kuralı (RFC-003'ün kendi disiplini): **değişiklik yeni bir RFC + sürüm bump gerektirir.**

§10 (D10) ve §8 (D8) bu kuralın istisnası olarak **v0.2 Revision Candidate** olarak işaretlendi: yeni RFC açmadan, mevcut RFC'ye **aday bölüm** olarak eklendi ve **founder onayıyla normatifleşecek**. Onay gelene dek "bir teklif ki uygulaması zaten mevcut" (RFC-003 line 146-147).

**Kod zaten shipped:** D10'nun üç-durumlu doğrulama sözleşmesi `tools/verify_pairing_fixture.py` ve `tools/settlement_bind_verify.py`'de uygulandı; iki negatif kontrol AT-007i/AT-007j'de; YEŞİL durum verifier check 7'de. **Bu nedenle onay bir kod-kararı değil, bir RFC-sözleşmesi-kararıdır.**

---

## 1. D10 ne diyor (tek paragrafta)

Bir ödeme/settlement belgesi Tamga receipt'ini düzenlerken `settlement_ref` = receipt'in `h`'sini (= `receiptHash`) **taşımak zorundadır**. Anchor ödeme-tarafı bir kimlik DEĞİL, ledger hash'idir; zincir şudur:

```
settlement → settlement_ref → h → (prev, jcs(record)) → stdout_sha256 → teslim-edilen-baytlar
```

**Neden `h`:** `h` node-certified'dır (D8 — `node_id` hash girdisinin içindedir, `node_sig` `h`'yi imzalar), yani anchor node operatörünün beyanını taşır, bir agent iddiasını değil. Ödeme-tarafı kimlik "payer hakkında payer'in iddiası" olurdu; ledger hash'i ise **herkes sadece kayıttan yeniden hesaplayabilir**.

**Doğrulama sözleşmesi (normatif, üç durum):**

| Durum | Sonuç | Testi |
|---|---|---|
| `settlement_ref` yok | RED `missing settlement reference` | AT-007i |
| `settlement_ref` ≠ `h` | RED `unanchored settlement` | AT-007j |
| `settlement_ref` == `h` | GREEN; D4 (zincir-üyeliği) + D8 (node-cosign) miras | verifier check 7 |

**Labeling:** `source` etiketi `observed` veya `derived` OLMALIDIR, **asla `simulated`**.

---

## 2. Founder'ın seçenekleri ve sonuçları

### Seçenek-A: ONAYLA (§10'u v0.2 için normatif-dondur)

**Sonuçları:**
- RFC-003 §10 **normatif** olur; D10 v0.2'nin parçasıdır. Bundan sonra değişiklik yine yeni-RFC + bump gerektirir.
- **Hard-RED-geçiş** yürürlüğe girer: `settlement_ref` olmayan öncesi-pairing belgesi **RED** döner, **GRANDFATHERED değil**. Bunu §10 bilinçli seçti (line 169-175): degradation-ladder "sadece varsayımsal-eski-belgeleri korurken her tüketiciye 'eksik anchor tolere-edilebilir' öğretirdi."
- Anchor'u x402 thread'inde (@doteyeso-ops/@holistis) tartışılan gap'in kapanışı olarak **resmi pozisyon** haline getirir; #3379'ya gönderilen followup zaten bu sözleşmeyi anlattı.
- **Geri-uyumluluk riski:** `settlement_ref` taşımayan mevcut pairing üreticisi YOK (alan yenidir, "every pairing producer is new with it" — line 171-172). Yani hard-geçişin pratik bir maliyeti bugün yoktur; sadece gelecekteki üreticiler için bir standart kurar.
- **RFC-010 bağlantısı:** RFC-010'ın "settlementRef resolves" kontrolü D10'un anchor'ını resolve eder. Onay, beş-kontrolun pilot-günü-reconcile'ının da zeminini kurar (ama RFC-010'ın kendisini dondurMAZ — o hâlâ DRAFT/pilot-bekliyor).

### Seçenek-B: ONAYLAMA-AMA back-compat flag'le (§10'un önerdiği açık-nokta (a))

RFC-003 line 174-175'ün önerdiği: **`settlement_ref: null`-izinli açık bir policy flag**. Varsayılan RED kalır, ama flag açıldığında null-anchor tolere edilir.

**Sonuçları:**
- **Maliyet:** L0-style soft-mode'a benzer bir kapı açılır. §10 bunu "the honest form" diye nitelendirir — eğer founder geri-uyumluluk isterse sessiz-degrade yerine AÇIK flag. Ama §10'un kendi gerekçesi (line 172-173) degradation-ladder'ın her-tüketiciye-yanlış-ders-verdiğini söyler; flag o dersin **isimlendirilmiş** halidir, yok-edilmiş hali değildir.
- **Denetim yükü:** flag'in durumunu pairing belgelerinin yorumlanmasında taşımak gerekir (bir okuyucu "bu-profil-RED-mu-FLAG'lı-mı" sorusunu yanıtlamalı).
- **Pratik-tetikleyici YOK:** bugün `settlement_ref`'siz üretici olmadığı için (yukarıda) bu flag'ı açmayı gerektiren **gerçek bir geri-uyumluluk talebi yoktur.**

### Seçenek-C: ONAYLAMA — Phase-3 açık-noktalarıyla birlikte (§10 (b) ve (c))

Açık-nokta (b): `settlement_ref` ek olarak **chain-tip'i (seq + h)** sabitleyebilir — böylece bir settlement "receipt'in o-andaki-head'ine anchor-olduğunu" ispatlar, "içinde bir-kayıt" değil. Açık-nokta (c): **multi-settlement** (bir receipt, birkaç kısmi-ödeme) şu-an tanımlı DEĞİL.

**Sonuçları:**
- (b) **Phase-3'e ertelendi olarak kalması önerilir** (§10'ın kendi ifadesi): chain-tip-pin ek bir doğrulama-derinliği katar ama bugün pilot talebi yoktur; şimdi dondurmak spekülasyonu-normatif-leştirir (RFC-010'ın DRAFT-kalma-gerekçesiyle aynı disiplin).
- (c) multi-settlement **ödeme katmanının concern'i** olarak bırakılmaya uygundur: pilot gerçek-kısmi-ödeme isteyene kadar tanımlanmaz.
- **Risk:** (b) ve (c)'yi ŞİMDİ dondurmak, gelecekte pilot-gerçekliği-uyumsuz çıkarsa **v0.3-RFC gerektirir** (freeze kuralı). ertelemek bedelsüzdür; erken-dondurmak bedelli olabilir.

### Seçenek-D: REDDET / ERTELE (§10'ı aday olarak bırak)

**Sonuçları:**
- §10 "uygulaması-var-ama-normatif-değil" durumunda kalır. Kod shipped olduğu için **hiçbir test veya davranış değişmez** — suite 228/0/0 korunur, D10 negatifleri AT-007i/j'de koşmaya devam eder.
- **Ama:** x402 #3379'ya gönderilen followup "awaiting founder approval" dedi; reddetmek veya sessiz-ertelemek **thread'deki sözle tutarsız** olur — "teklif ama karar vermedik" mesajı verir.
- **Ertelenecek bir şey yok:** bu bir zaman-kaynak-kararı değildir; **normatif-leşme-bekleyen-kod** durumunu süresiz-uzatır, ki bu RFC-003'ün freeze-disipliniyle zayıf-uyumlu bir ara-durumdur.

---

## 3. Karar-verici için asıl iki soru

1. **Hard-RED-geçişini mi, yoksa flag'lı-yumuşak-yolu mu istiyorsun?** (Seçenek-A vs B). Pratik-tetikleyici-sıfır olduğu için bu bugün bir **standart-seçimi**dir, bir geri-uyumluluk-kurtarması değil.
2. **Phase-3 açık-noktalarını (chain-tip-pin, multi-settlement) ŞİMDİ mi, sonra mı?** (Seçenek-C'nin (b)/(c) ayraçları). Ertelemek bedelsüzdür; erken-dondurmak v0.3-maliyeti taşır.

---

## 4. Dürüst-sınırlar (karar-vericiye)

- **D10 bir receipt'i bağlar, ödeme-finality'sini veya alıcı-kabulünü DEĞİL** (RFC-003 line 185-191). "Teslim-edildi ve zincirli-kayıt-var" der; ödeme katmanının o gerçekle ne-yapacağı ödeme katmanının kararıdır.
- **Execution-quality ekseni D10'un dışındadır:** doğru-teslim-edilmiş-yanlış-yanıt için receipt yine GREEN döner (line 189-191); o eksen caller'a aittir, ledger'a değil.
- **Public fixture'ün x402 tarafı `simulated`'dır** (line 187) — gerçek-pilot-talebi gelene kadar anchor'un x402-tarafı gerçek-ödeme-semantiği görmedi. Bu, §10'un "implementation-leads-the-RFC" itirafının nedenidir.
- **Seçenek-A'nın hard-geçişi "bugün-maliyet-sıfır" ifadesi bir varsayımdır**, bir kanıt değil: `settlement_ref`'siz üretici bugün yoktur, ama bu "yarın da olmayacak" anlamına gelmez — yine de standartı erken-koymak, gelecekteki üreticilerin ilk-günden-uyumlu-olmasını sağlar (bu, hard-geçişin bilinçli seçiminin gerekçesidir).

---

## 5. Bu belge DEĞİLDİR

- **Karar değil** — yukarıdaki seçenekler arasında bir tercih içermez.
- **Tavsiye değil** — "önereceğim" ifadesi yoktur; sadece seçenekler ve sonuçları listeler.
- **RFC değişikliği değil** — RFC-003 §10'ya dokunulmadı; bu sadece bir bilgi-belgesidir.
- **Push-ready bir karar-kaydı değil** — founder kararını bekleyen açık-noktalar RFC-003 §10 line 192-197'de zaten listeli; bu belge onları dışarıdan-okunabilir kılar.

---

## 6. Referanslar

- `docs/RFC-003-ledger.md` §10 (line 137-202) — D10 adayı, AWAITING FOUNDER APPROVAL
- `docs/RFC-003-ledger.md` line 7 — v0.1-FINAL-FROZEN durumu
- `docs/RFC-010-cross-artifact-settlement-binding-DRAFT.md` — beş-kontrol DRAFT'ı, D10'ın anchor'ını resolve-eden "settlementRef resolves" kontrolü (pilot-günü-reconcile)
- `tools/verify_pairing_fixture.py` (check 7) + `tools/settlement_bind_verify.py` — D10'nun shipped-uygulaması
- `tests/at007_pairing_fixture.sh` (AT-007i/AT-007j) — iki negatif kontrol
- x402-foundation/x402#3379 — thread; @doteyeso-ops/@holistis gap-tartışması + goun7 followup (comment 5860132317, 2026-09-27)

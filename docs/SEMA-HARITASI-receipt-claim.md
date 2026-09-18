# ŞEMA-HARİTASI — receipt ↔ claim (kompozisyon-seam'i-görünür-yapar)

Tarih: 2026-09-18 · Amaç: holistis'in #3379-teklifine-somut-yanıt ("two-column map
of which field proves what, and which fields in each are asserted rather than
derived"). **Birleşik-format-değil** — seam'leri-gösteren-harita.

## Etiket-anlamları

- **derived**: değer-başka-verilerden-hesaplanır; yabancı-taraf-aynı-girdilerle
  **yeniden-üretebilir** (hash, imza-kurtarma, aritmetik).
- **asserted**: değer-üreticinin-beyanıdır; **yeniden-üretilemez**, ancak
  imza/zincir-ile-kimliğe-bağlanır. Doğrulayıcı-bunu-beyan-olarak-okumak-zorunda.
- **pinned**: değer-bir-çapaya-sabitlenir (kod-sürümü, limit); değişirse-digest-değişir.

---

## Tamga-receipt-sütunu (charge-kaydı, RFC-002/003)

| Alan | Etiket | Ne-kanıtlar | Yabancı-nasıl-kontrol-eder |
|---|---|---|---|
| `h` | derived | kayıt-bütünlüğü (sha256-over-prev+jcs) | aynı-girdilerle-yeniden-hesaplar |
| `prev` | derived | zincir-bağı (sıralama-kurcalamaya-karşı) | zinciri-baştan-yeniden-üretir |
| `seq` | derived | monoton-sıra | zincirden-türetir |
| `stdout_sha256` | derived | çıktı-baytlarının-özü | çıktıyı-görürse-yeniden-hesaplar |
| `wall_ms`/`cpu_saat` | asserted | çalışma-süresi-beyanı | **yeniden-üretilemez** (donanım-yükü) |
| `ram_gb_sn`/`io_mb` | asserted | kaynak-kullanım-beyanı | **yeniden-üretilemez** |
| `fee_birebir` | derived | ham-ücret-formülü-verbatim | aritmetik-yeniden-hesaplar |
| `fee_sim` | derived | son-5-ücretin-ortalaması | zincirden-yeniden-hesaplar |
| `engine`/`session` | pinned | hangi-motor-hangi-oturum | manifest-ile-çapalar |
| `ts` | asserted | zaman-beyanı | **yeniden-üretilemez** (saat-kaynağı) |
| `pkg` | pinned | paket-kimliği | manifest-package.name |
| `op` | pinned | işlem-sınıfı | komut-satırı |

**Kök-pinned (receipt-dışında,-digest-girişi):** `agent.wasm`-sha256 + declared
resource-limits (manifest) → **bunlar-olmadan-hiçbir-derived-alan-anlamlı**.
Biz-buna "deterministic-replay-contract" diyoruz.

**Kritik-derived-değil-asserted (kendi-zayıflığımız):** `wall_ms`-ve-kaynak-
alanları **asserted**-dir. Üstü-kapatılmamalı: "receipt-the-same-code-ran-the-
same-way" iddiası `stdout_sha256`-için-geçerlidir, `wall_ms`-için-değil. Aynı
kod-farklı-yükte-farklı-wall_ms-verir; bu-bir-hata-değil-**bildirilmiş-sınırdır**.

---

## capacity-attest-claim-sütunu (koddan-okunmuş, safal207-denetimi-ile-düzeltilmiş)

> **Düzeltme-notu (2026-09-18):** bu-sütun-başlangıçta-holistis'in-issue-yorumlarındaki
> *prose*-açıklamasından-taslaklandı. **safal207 bunu-gerçek-koda-karşı-denetti**
> (commit `3ae036eb1e`, `packages/capacity-attest/src/{schema,signing,tools,completeness}.ts`)
> ve-6-düzeltme-verdi; hepsi-aşağıda-uygulandı. Önceki-sürümün-hataları:
> (1) `#401`-referansı-yanlıştı — o-PR Algorand-AVM'dir, capacity-attest-değildir;
> (2) computeClaimId **tüm-normalize-ClaimContent**'i-hash'ler, adres-altkümesini-değil;
> (3) priorClaimId **asserted**'dir (alıcı-sağlar-ve-imzalar), derived-değil;
> (4) disputeContext **doğrulanmamış-atıf**'tır, pinned-değil;
> (5) evidenceHash **imzalı-hash-bağı**'dır, bağımsız-kanıt-doğrulaması-değil;
> (6) stdout_sha256/delivered **mantıksal-çelişmez** — farklı-sorular-sorarlar.
>
> **İkinci-düzeltme-dalgası (2026-09-18, holistis'in-FIELD-PROVENANCE.md'sine-);
> (7) evidenceHash-etiketi "derived (sınırlı)"-dan **asserted**'e-düştü.** Holistis'in
> tablosu-bunu-kanıtlıyor: kanıtın-kendisi-asla-saklanmaz-veya-doğrulanmaz, yalnızca-
> hash'in-imzaya-bağlığı-kaydedilir. Kendi-derived-tanımımıza-göre-yabancı-bir-taraf
> claim'in-baytlarından-hash'i-yeniden-üremez (kanıt-baytları-dışarıda) — o-halde-
> derived-değildir. Bu, K17.3-kuralının-bizim-tarafımızda-uygulanması: dış-denetim-
> sonrası-düzeltme-inline-yazıldı, sessiz-değil. (Kod-doğrulaması:
> `packages/capacity-attest/docs/FIELD-PROVENANCE.md` @ `3ae036eb1e`.)

| Alan | Etiket | Ne-kanıtlar (koddan-okunmuş) |
|---|---|---|
| `buyerAddress`-imzası | derived | **attribution** — kim-imzaladı (ecrecover) |
| `delivered` (yes/no/partial) | asserted | **alıcının-iddiası** — ne-olduğunu-kanıtlamaz |
| `evidenceHash` | **asserted** (imzalı-bağ) | alıcının-sağladığı-hash; **kanıtın-kendisi-hiç-saklanmaz-veya-doğrulanmaz** — yalnızca-hash'in-varlığı-imzaya-bağlı. İmza-alıcının-bu-hash'e-gönüllü-olduğunu-kanıtlar; baytların-varolduğunu-veya-doğru-yorumlandığını-kanıtlamaz. (İlk-sürüm-bunu "derived (sınırlı)"-etiketlemişti; holistis'in FIELD-PROVENANCE-düzeltmesi-ile **asserted**'e-düştü — kendi-derived-tanımımıza-göre-yabancı-bir-taraf-claim'in-baytlarından-onu-yeniden-üremez, bu-yüzden-derived-değildir. K17.3-in-uygulaması.) |
| `computeClaimId`-girdisi | derived | `sha256(canonicalize(ClaimContentSchema.parse(content)))` — **tüm-normalize-ClaimContent**: sellerAddress+buyerAddress+assetType+promisedSpec+delivered+evidenceHash+settlementRef+timestamp + opsiyonel measured/externalRefs/priorClaimId |
| `priorClaimId` | **asserted** | alıcı-sağlar-ve-claim'e-imzalar; **derived-değil**. Derived-olan-sonraki `analyzeCompleteness()`-sonucudur (dangling/fork, imzalı-işaretçilerden-yeniden-hesaplanır) |
| `completeness` | derived-fakat-host-tarafından | **aynı-hostta-hesaplanır** — imzalı-prior-bağdan-güçlü-değil, tek-başına-kanıt-sunulamaz |
| `externalRefs.disputeContext` | asserted (doğrulanmamış-atıf) | `termsHash`-dış-koşulları-sabitler; capacity-attest **süreci-veya-sonucu-çözmez/doğrulamaz** |
| *yok* | — | **wasm-hash / resource-limits / replay-contract YOK** (holistis'in-itirafı) |

---

## Seam'ler — kompozisyon-yapılırsa-nereyi-görmek-lazım

1. **receipt.stdout_sha256 (derived) ↔ claim.delivered (asserted):** **mantıksal-
   olarak-çelişmezler** — farklı-sorular-sorarlar (safal207'nin-düzeltmesi). Birinci
   "bu-baytlar-üretildi"-der; ikinci "alıcı-teslimi-bu-şekilde-yargıladı"-der.
   İkisi-de-dahili-olarak-geçerliyken-uyumsuz olabilir: çıktı-doğru-ama-yanlış-
   alıcıya-gitti-veya-alıcı-doğru-teslime-"kısmi"-dedi. **Çelişki-değil,
   önerme-sınırı** — hiçbir-alan-diğerini-tutmaz, hiçbir-kompozisyon-bunu-düzeltmez.
2. **receipt.wall_ms (asserted) ↔ claim.evidenceHash:** ikisi-de-beyan; çifte-
   beyan-doğrulama-değildir.
3. **completeness (host-derived) ↔ zincir (derived):** completeness-aynı-hostta-
   hesaplandığı-için-zayıf; holistis'in-kendi-uyarısı-gereği-tek-başına-sunulmaz.
4. **zaman-ekseni:** receipt-post-hoc (run-oldu), claim-de-post-hoc (settlement-
   sonrası). **Hiçbiri-pre-action-değildir** — önleyemez, sadece-tespit-eder.

**Çıktı-bu-haritadır; birleşik-format-değil.** Bir-kompozisyon-tasarlayan-bu
seam'leri-görmek-zorunda-ve-her-seam-için "hangi-taraf-hangi-alanı-sunuyor"
sorusu-yanıtlanmış-olmalı.

## Derived-etiketleri-gerçek-doğrulaması (2026-09-18)

Etiketler-iddia-değildir; her-derived-alanı-yeniden-hesaplayarak-doğruladım.

**fee_sim — 5/5 ✓:** algoritma-tam-taklit-edilebilir. Önemli-nüans:
`round(...,9)`-çıkışını **birikimde-tutmak**-şart (ham-medyanı-değil).
Taklit: `merged = sorted(prev[-4:] + [fee_birebir])` → medyan →
`round(medyan, 9)` → birikim. 5-kayıtlık-benzetimde-kayıt-ile-birebir.

**h/prev/seq — derived ✓** (AT-001f-ve-verify-mini-bağımsız-doğrulaması-zaten).
**stdout_sha256 — derived ✓** (AT-007-6/6-pairing-fixture).
**wall_ms/cpu_saat/ram_gb_sn/io_mb — asserted**: aynı-kod-farklı-yükte-farklı;
bu-bir-bug-değil, bildirilmiş-sınırdır (OQ-8'nin-172×-salınımı-bunu-kanıtlar:
aynı-iş-farklı-wall-zamanı-verir, deterministic-değil).

**Dürüst-sonuç:** haritadaki-her-derived-etiketi-yeniden-üretilebilir-kanıtla-
doğrulandı; her-asserted-etiketi-neden-yeniden-üretilemediği-ile-açıklandı.

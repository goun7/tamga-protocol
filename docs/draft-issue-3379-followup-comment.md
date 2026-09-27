# #3379 follow-up — TASLAK (GÖNDERİLMEDİ, lead-doğrulaması-bekler)

**Hedef:** https://github.com/x402-foundation/x402/issues/3379
**Konum:** D10 yorumundan (comment ID 5851437844) sonraki ilk takip — **yanıt
beklenirken-değerli-içerik**, spam-değil. **SADECE-lead-onayı-ile-gönderilir.**

---

## Yorum-metni (İngilizce, thread-dili)

Following up on the settlement-anchor clause above with where it landed in the spec,
since the anchor question was the one this thread opened with.

The clause is now a normative candidate in our ledger RFC (§10, D10), with a concrete
verification contract rather than prose: given a pairing document, a missing
`settlement_ref` is a RED (`missing settlement reference`), a reference to a different
receipt is the same RED (`unanchored settlement`), and only an exact match to the
receipt's ledger hash verifies, at which point the anchor inherits the chain-membership
and node-cosign checks that already bind that hash. Both negatives are tamper controls
in our fixture suite (10 checks, 8 tamper negatives; the two anchor controls are the
newest). Replayable from a clean clone with stdlib Python only, no pip install.

Two things worth saying plainly, because they are limits rather than features:

1. The anchor binds a settlement to a *receipt*, not to payment finality or buyer
   acceptance. It says a chained record exists for exactly this delivered work,
   node-signed, and those other axes stay separate, which is why our public fixture
   marks its own x402 side as `simulated`.
2. The anchor is one of the five checks in the binding shape this thread proposed
   (receipt + claim + settlementRef + payer/payee + evidenceHash). We deliberately did
   **not** freeze the wider five-check gate yet: without a pilot's real payment
   semantics, freezing it would demonstrate the join shape rather than prove it, the
   trap this thread named. The other four stay in a pilot-pending draft; this one was
   separable, so it shipped first.

We are not claiming this is the only defensible way to bind a settlement to work. We
are claiming that a settlement which names no receipt at all should fail loudly rather
than be downgraded to a warning, and that the anchor belongs to the ledger, not the
payment side, because the ledger hash is what a node operator co-signs.

One note on the evidence itself, since the replay claim above depends on the fixture
suite actually being reproducible. We chased two intermittent suite failures to root
cause rather than retrying them away, and both turned out to be real:

1. A replay-protection check could accept a token a second time if more than five
   minutes of wall-clock time had passed since the module loaded, because a periodic
   single-use-nonce cache sweep runs on real time while the test pins its own logical
   clock. In production the expiry check runs before the replay check, so an aged
   token is already rejected before the sweep matters; the fix pins the sweep for the
   duration of the test and production code was left untouched. This is a test
   isolation defect, not a payment security hole, and we say so rather than bury it.
2. An index file the suite verifies against was written by truncating in place, so a
   concurrent reader could observe a half-written line and report a stale index as a
   failure. The write now goes to a temporary file and is swapped in with an atomic
   rename, so no reader can ever see a partial file. The same pass closed a second
   defect nearby: the test reported success regardless of its own check result, which
   meant the failure had been silently hidden rather than missed.

Neither failure was suppressed or retried until it passed. Both were reproduced under
deliberate stress before the change, and confirmed gone after, twenty consecutive runs
for the first and ten plus a concurrent-writer stress for the second. We mention them
because a suite that hides its own failures is worse than no suite, and the anchor
claim above is only as good as the checks backing it.

---

## Neden-şimdi-değerli (lead-notu)

- **D10-yorumu-sonrası-net-gelişme:** anchor artık sözde-değil, 3-durumlu-verification-
  contract + 2-tamper-negatifi-ile-normatif-aday. Thread'in-açtığı-sorunun-yanıtı-
  olgunlaştı.
- **safal207'nin-5-kontrol-listesine-yol-haritası:** 1/5-separable-olarak-shipped,
  4/5-pilot-bekliyor-ve-nedeni-açık ("join-shape-tuzağı"). Thread'in-kendi-teshisine
  (wiring ≠ proof) saygı-duyan-bir-konum.
- **İki-flaky-kök-nedeni-eklendi (2026-09-27, AT-125 + AT-033):** "test-geçti"-
  yalanını-yakalayan-dürüstlük-göstergesi olarak-eklendi — bastırılmadı, kök-nedeni-
  yakalandı-ve-düzeltildi. Kanıt-sayısı-açık (20x + 10x + paralel-yazıcı-stresi).
  Ayrıca-AT-033'ün-gizli-rc-sızıntısı-açıklandı (kendi-FAIL'ini-gizleyen-test).
- **Spam-değil:** D10-yorumu-bilgi-verdi, bu-yorum-sınırı-ve-yol-haritasını-veriyor.
  Tek-takip-yorumu; yanıtlar-gelene-kadar-başka-ekleme-yapılmayacak.

## Gönderme-öncesi-lead-kontrol-listesi

- [x] İngilizce-metin-temiz (emdash-YOK — 4-tane-vardı, virgül-ile-değiştirildi; github-düz-metin-kuralı)
- [x] "claim" / "settlement" terminolojisi thread-ile-tutarlı
- [x] Alçakgönüllü-kapanış-korundu ("not the only defensible way")
- [x] Dürüst-sınırlar-açık (receipt ≠ finality; 4/5-pilot-bekliyor)
- [x] Dosya-yolu-YOK (tools/, docs/, tests/, .py, .md — gate-2 TEMİZ)
- [x] Türkçe-karakter-YOK, markdown-başlığı-YOK (comment-tek-paragraf-akış)
- [x] **İki-flaky-düzeltmesi-eklendi** (AT-125-zaman + AT-033-yarış + rc-sızıntısı; kök-nedenleri-ile, mekanizma-seviyesinde-yol-vermeden)
- [x] **Flaky-bastırılmadı-vurgusu** ("Neither failure was suppressed or retried until it passed")

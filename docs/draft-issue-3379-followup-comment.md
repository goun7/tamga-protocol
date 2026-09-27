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
receipt's ledger hash verifies — at which point the anchor inherits the chain-membership
and node-cosign checks that already bind that hash. Both negatives are tamper controls
in our fixture suite (10 checks, 8 tamper negatives; the two anchor controls are the
newest). Replayable from a clean clone with stdlib Python only, no pip install.

Two things worth saying plainly, because they are limits rather than features:

1. The anchor binds a settlement to a *receipt* — it says a chained record exists for
   exactly this delivered work, node-signed. It does not claim payment finality or
   buyer acceptance; those stay separate axes, and our public fixture marks its own
   x402 side as `simulated` for exactly that reason.
2. The anchor is one of the five checks in the binding shape this thread proposed
   (receipt + claim + settlementRef + payer/payee + evidenceHash). We deliberately did
   **not** freeze the wider five-check gate yet: without a pilot's real payment
   semantics, freezing it would demonstrate the join shape rather than prove it — the
   trap this thread named. The other four stay in a pilot-pending draft; this one was
   separable, so it shipped first.

We are not claiming this is the only defensible way to bind a settlement to work. We
are claiming that a settlement which names no receipt at all should fail loudly rather
than be downgraded to a warning — and that the anchor belongs to the ledger, not the
payment side, because the ledger hash is what a node operator co-signs.

---

## Neden-şimdi-değerli (lead-notu)

- **D10-yorumu-sonrası-net-gelişme:** anchor artık sözde-değil, 3-durumlu-verification-
  contract + 2-tamper-negatifi-ile-normatif-aday. Thread'in-açtığı-sorunun-yanıtı-
  olgunlaştı.
- **safal207'nin-5-kontrol-listesine-yol-haritası:** 1/5-separable-olarak-shipped,
  4/5-pilot-bekliyor-ve-nedeni-açık ("join-shape-tuzağı"). Thread'in-kendi-teshisine
  (wiring ≠ proof) saygı-duyan-bir-konum.
- **Spam-değil:** D10-yorumu-bilgi-verdi, bu-yorum-sınırı-ve-yol-haritasını-veriyor.
  Tek-takip-yorumu; yanıtlar-gelene-kadar-başka-ekleme-yapılmayacak.

## Gönderme-öncesi-lead-kontrol-listesi

- [ ] İngilizce-metin-temiz (emdash-YOK — kullanıcı-yasak, virgül-kullanıldı)
- [ ] "claim" / "settlement" terminolojisi thread-ile-tutarlı
- [ ] Alçakgönüllü-kapanış-korundu ("not the only defensible way")
- [ ] Dürüst-sınırlar-açık (receipt ≠ finality; 4/5-pilot-bekliyor)
- [ ] Replay-talimatı-D10-yorumundaki-ile-aynı-şekilde-çalışıyor (stdlib-only)

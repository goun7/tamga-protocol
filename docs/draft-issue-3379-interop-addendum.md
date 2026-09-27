# #3379 interop addendum — TASLAK (GÖNDERİLMEDİ, kullanıcı-onayı-bekler)

**Hedef:** https://github.com/x402-foundation/x402/issues/3379
**Konum:** D10 followup comment'inden (5860132317) SONRA ikinci takip. **SADECE-kullanıcı-onayı-ile-gönderilir.**
**Kapsam:** interop analizi (`docs/TOKENIZEN_INTEROP_ANALIZI.md`) — public-kod-okuma, tokenizen-ekibine İLETİŞİM YOK.

---

## Yorum-metni (İngilizce, thread-dili)

A follow-up on the anchor clause, this time from outside our own code, because the
same gap appeared independently in a project neither of ours shares.

We read the public schema of another open agent-commerce project (Tokenizen) to see
how the same problem looks from a different design boundary, and the overlap turned
out to be closer than we expected. Their signed claim object and our ledger receipt
are structurally the same kind of artifact: a content-addressed record with a buyer
and seller address, a payment reference, and a hash of the delivery evidence, signed
with EIP-191 over a canonical JSON preimage. Field by field, some things match
directly (their `buyerAddress`/`sellerAddress` are our bind payer/payee), some are the
same link with a different signer (their per-buyer claim chain is our chain link, but
theirs is buyer-signed where ours is node-co-signed), and some do not map at all.

The interesting part is one deliberate difference. Their `evidenceHash` is documented
as "a hash of evidence that is never itself checked," and their `settlementRef` as "a
payment reference that is never itself resolved on-chain." Both are cited, not
resolved. That is exactly the shape this thread named as the problem: asserted but
not resolved. They keep it open on purpose, as a design boundary, not an oversight.

Our anchor closes that gap on our side. A settlement that names our receipt does not
get to cite it, it has to be it, byte for byte, and the ledger hash it must match is
recomputable by anyone from the record alone. We are not claiming our boundary is
better for their project. They have reasons for theirs, including a deliberate refusal
to police anything they cannot themselves verify, which is a respectable discipline.
We are noting the overlap because two projects reaching the same artifact shape from
opposite design boundaries is a stronger signal that the shape is real than either of
us shipping it alone.

To be clear about what this is not: **we did not build an integration.** We read the
public schema, compared fields, and noted where the two designs agree and disagree.
No code was written against their format, no cross-verification was run, and we have
not contacted them. If an interop ever becomes real it will be because a pilot needs
both artifacts to name the same work, not because the shapes resemble each other.

---

## Neden-şimdi-değerli (lead-notu)

- **Peer-katkısı, satış-DEĞİL:** "aynı-nesne-şekli-opposite-design-boundaries'dan"
  gözlemi, thread'in-kendi-teshisine ("wiring ≠ proof") saygı-duyar-bir-konum.
- **Karşılıklı-fayda-vurgusu:** Tokenizen'in-cite-don't-resolve-disiplini-saygıdeğer
  denir; "bizim-boundary'miz-onların-için-daha-iyi" iddia-EDİLMEZ.
- **Çekince-açık:** "we did not build an integration" + "we have not contacted them" —
  abartma-yok, interop-analiz-only.
- **Spam-değil:** 2.-takip-yorumu; D10-anchor'undan-doğal-devam. Thread'e-teknik-içerik.

## Gönderme-öncesi-lead-kontrol-listesi

- [x] İngilizce-metin-temiz (emdash-YOK)
- [x] Dosya-yolu-YOK (tools/, docs/, tests/, .py, .md, .ts — gate-2 TEMİZ)
- [x] Türkçe-karakter-YOK (İngilizce-yorum-bölümünde)
- [x] Markdown-başlığı-YOK (düz-paragraf-akış)
- [x] **Tok-alçakgönüllü** ("We are not claiming our boundary is better for their
      project"; "a respectable discipline")
- [x] **Çekince-açık** ("we did not build an integration"; "we have not contacted them")
- [x] **Abartma-YOK** — "stronger signal" denir, "proof" veya "kanıtlandı" DENMEZ
- [x] **İletişim-yasakına-uyum** — tokenizen-ekibine-hiçbir-istek-GÖNDERİLMEDİ (sadece
      public-repo-okuma)

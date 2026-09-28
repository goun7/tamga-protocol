# #3379 teşekkür + kompozisyon linki — TASLAK (GÖNDERİLMEDİ, onay-bekler)

**Hedef:** https://github.com/x402-foundation/x402/issues/3379
**Komut (onaydan sonra):**
`gh issue comment 3379 --repo x402-foundation/x402 -f body="$(cat docs/draft-issue-3379-thanks-comment.md)"`

**Önkoşul:** RFC dokümanı repo'ya commit+push edilmiş olmalı (linkin çözülmesi için).

---

## COMMENT BODY (aşağısı gönderilecek metindir)

Both landed the way they needed to. The MUST in §6 is the change that matters; the
decode instructions in §9.1 turn "decodable by anyone" from a claim into something
a cold reader can actually run, which turned out to be the real ask behind my note.

I took the composition seriously instead of leaving it in a comment. Wrote it up as
a design doc on our side:
[RFC-010b, settlementRef as a node-cosigned hash](https://github.com/goun7/tamga-protocol/blob/main/docs/RFC-010-settlementref-cosign-composition.md).

The short version: if settlementRef resolves to a recomputable ledger hash, the §6
check stops depending on where the verifier happens to be able to read the
settlement from, because the payer becomes part of the anchor's preimage instead of
something you fetch from a chain or a facilitator. Still pre-freeze on both ends.
This is a proposal for when the two specs are closer to frozen, not a request to
adopt anything now.

Also left a review on #3604 after checking the spec against capacity-attest's public
fixture output. Seven items, none of them design-level. Three are one-line
canonicalization clarifications that only surface when a second implementation
tries to be byte-compatible, which is exactly the situation this composition
creates.

---

## NOTLAR (gönderilmez)

- holistis'in yaptığı iki değişiklik canlı diff'te doğrulandı:
  - §6: "a verifier MUST confirm that claim.buyerAddress matches the payer"
    (önceden SHOULD önerisi bizimdi, MUST'a yükseltildi)
  - §9.1: "Decoding the on-chain examples, without this project's code" eklendi
    (EAS ABI decode talimatları)
- Teşekkür koşulu sağlandı: "Eğer holistis bizim önerimizi uyguladıysa" → EVET
- Em-dash yok, abartılı maddeleme yok, insani dil
- Linkin çalışması için docs/RFC-010-settlementref-cosign-composition.md'nin
  goun7/tamga-protocol main'e push edilmiş olması gerekir

# PR #3604 review — TASLAK (GÖNDERİLMEDİ, onay-bekler)

**Hedef:** https://github.com/x402-foundation/x402/pull/3604
**Komut (onaydan sonra):**
`gh pr review 3604 --repo x402-foundation/x402 --comment -F -` (stdin'den) veya
`gh pr review 3604 --repo x402-foundation/x402 --comment -f body="$(cat docs/draft-pr3604-review-body.md)"`

---

## REVIEW BODY (aşağısı gönderilecek metindir)

Read the whole spec and checked it against capacity-attest@0.6.0's public fixture
output, which we vendored and cross-verified independently (our stdlib-only
verifier, no ethers, reproduces verifyClaim 7/7 on their golden vectors and 8/8 on
claims freshly produced by their own signing path). Most of this is solid. The
narrow scope is the right call and §3's refusal to rank claims costs real signal
but buys the only layer worth building policy on. Below is what I'd fix before
this leaves draft.

**1. The §9 example addresses are not valid 20-byte addresses.** Both
`sellerAddress` (`0x209693bc...312287`) and `buyerAddress` (`0x857b0651...36b6`) are
39 hex characters, not 40. §4 requires a 20-byte address and §10 step 2 requires
`buyerAddress` to match the recovered signer, so the only worked example in the
spec fails its own verification. The reference implementation's own fixture uses
correct 40-hex addresses (`0x5d5c99EdF529335160FF180fA141Dd4967fc00D2` in their
golden vectors). This matters more than a typo normally would, because §9.1 points
a cold reader at this exact object as the thing to decode by hand.

**2. The canonicalization procedure omits hex-address case normalization.** §5
says keys are sorted recursively and stops there. The fixture's addresses are
EIP-55 checksummed mixed-case, and the reference implementation lowercases both
address fields before hashing (our independent verifier does the same, which is
why it reproduces their verdicts). Without that rule stated, the same claim content
with a checksummed `buyerAddress` versus a lowercased one produces two different
`claimId` values, and two implementations that both think they're compliant recover
different signers from the same bytes. One sentence fixes it: hex string fields
holding an `0x`-prefixed address are lowercased before serialization.

**3. Say what `personal_sign` actually receives.** `claimId` is `"0x" + sha256(...)`,
so the signed message is the 67-character ASCII hex string, `0x` prefix included,
not the 32 raw digest bytes. Both readings are reasonable given §5 as written, and
they produce different signatures from the same key. We hit exactly this class of
ambiguity in our own settlement gate and had to pin the input shape per channel
because the failure mode is a silent verify-fail, not an error. Stating it
explicitly costs one clause and removes the whole class.

**4. §6's MUST depends on a resolution path the spec doesn't define.** The
requirement is conditioned on "where the underlying settlement is inspectable," but
`settlementRef` is typed as either an x402 payment reference or an on-chain
transaction hash, and those resolve differently. The tx-hash branch is
well-defined but has a real edge: for a settlement routed through a sponsor,
paymaster, or router contract, the transaction's `from` is the relayer, not the
buyer, so a naive payer lookup fails a legitimate claim. Suggest giving
`settlementRef` a discriminated form and defining the resolution per branch, or
scoping the MUST to whichever branch actually exposes `payer`, with the other
branch stated as not covered rather than left implicit.

**5. `priorClaimId` is signed but never verified.** It's a content field so it
enters `claimId`, which means the signer commits to it, but §10 has no check behind
that commitment. Two gaps follow. A claim can point at a `priorClaimId` that
doesn't exist or never verified, and nothing flags it. And two claims sharing one
`priorClaimId` are both individually valid, with no rule for how a reader orders or
detects the fork. The completeness fixture already produces a three-claim chain,
so this is implementable now. A reasonable shape: where `priorClaimId` is present,
the referenced claim must exist in the gathered set and verify, otherwise the chain
is reported incomplete rather than invalid, which keeps it consistent with §8's
honesty about completeness being separate from validity.

**6. Timestamps need a pinned format for the chronological list §3 promises.**
`get_delivery_history` returns the raw chronological list, but `timestamp` is
free-form ISO-8601. Mixed precisions and offsets sort inconsistently, which
silently reorders the history the whole signal rests on. Pin to UTC with millisecond
precision and a trailing `Z`, matching the example you already ship.

**7. `measured` and `externalRefs` have no worked example.** Neither appears in any
of the reference implementation's public fixture output (golden vectors,
completeness fixture, or the production claim), so the two most complex structures
in §4 are spec-only today. Either add one worked example each or mark them as
not-yet-implemented in the reference, so "decodable by anyone" stays a testable
claim rather than one that holds for the simple half only.

None of these change the design. Points 1 through 3 are one-line clarifications
each, and 4 through 7 are the kind of gap that only shows up when a second
implementation tries to be byte-compatible. Happy to contribute a worked example
or the address-format test vectors if useful.

---

## NOTLAR (gönderilmez)

- Doğrulamalı kanıtlar: `tests/vendor-capacity-attest/` (golden-vectors.json,
  completeness-claims.jsonl, production-claim.jsonl) + `tools/attest_verify_bagimsiz.py`
- Adres uzunlukları python ile doğrulandı: 39 hex karakter = 19.5 bayt
- `measured`/`externalRefs` vendored fixture'larda grep ile yok (0 occurrence)
- priorClaimId completeness-claims.jsonl'de 5 geçiş (3'lü zincir)
- İmza yüzeyi: `tools/attest_verify_bagimsiz.py:207-210` `_eip191_hash` UTF-8 ASCII hex
  + `:229` adres küçük-harfe indirgeniyor

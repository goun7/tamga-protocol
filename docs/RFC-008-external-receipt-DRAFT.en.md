> English twin of the Turkish-BORN original (docs/RFC-008-external-receipt-DRAFT.md). The Turkish file is the authoritative original; this translation exists for foreign readers. On any divergence, the Turkish governs.

# RFC-008 (DRAFT) — External Receipt Binding (x402 / very-rail evidence bridge)

> **Status: DRAFT — PILOT-PENDING.** This-heading-CLAIMS-NO-excess: until-the-pilot-semantics
> (ultravioleta-consented-delivery: sealed-to-the-plaintext-payer conduct)-are-KNOWN,
> field-rules-CANNOT-be-FINAL. The-text-below-receives-its-rfc-number-once-the-pilot-arrives-closing-the-three-open
> items-flagged-in-§3. Assembly-discipline: no-section-enters-the-implementation ( WHITEPAPER
> §8-parallel: thinking-is-free, not-with-code).

## 0. Summary (one-paragraph)

A-Tamga-charge-record-can-be-bound-to-evidence-from-a-SECOND-world: the-DIGEST-of-the
payment/deliver-evidence-on-the-external-rail-(like-x402). This-RFC-defines-NO-new-hash; it-only-binds
the-fields-of-two-EXISTING-worlds-with-alg+hex-LABELS (extension-of-the-RFC-003 D5/RFC-007 D10 discipline).

## 1. Motivation

- On-pilot-day, a-single-command-(--pair-charge)-can-decide-whether-the-two-worlds'-hashes-are-EQUAL
- Making-verifiable-not-only-our-chain-but-also-the-external-team's-receipt ( B2-Bundle-COMPATIBLE)
- Rail-independence: x402-is-an-EXAMPLE; the-field-schema-is-GENERIC-in-'rail'-shape (multi-rail-memo-compatible)

## 2. Field-schema (ADDITIVE, inside-the-charge-record)

```json
"external_receipt": {
  "rail": "x402",                          // string, rail-adı (aşağıda-regex)
  "receipt_id": "0x7e7c…87ec",             // rail'in-kendi-paymentId'si-(kanonik-rendering: 0x+64-lowercase)
  "content_hash": {"alg": "keccak256", "hex": "…"},   // rail-üzerinde-declar-EDILEN-hash
  "receipt_uri": "https://…/dx402/receipt/0x7e7c…87ec" // İsteğe-bağlı; alınma-yeri
}
```

**Rules (v0-draft):**
- R8-1: `rail`-∈-[a-z0-9-]{1,24}; `receipt_id`-canonical-rendering-0x+64-lowercase-(same-discipline-as-x402-#3377)
- R8-2: `content_hash.alg`-∈-{sha256, keccak256} (same-as-the-existing-D10-label-list)
- R8-3: `external_receipt`-IF-PRESENT-chain-verify-shape-gate-(RFC-007-R2-defensive-depth-model)
- R8-4: PAIRING-RULE (the-most-important): charge.delivery_hash ≠ external_receipt.content_hash
  CAN-be-different — these-are-two-bindings-over-DIFFERENT-byte-populations ( our-delivery-bytes
  vs their-plaintext). Equality-is-'NOT-ASSUMED': only-with-the-TWO-SIDED-declaration-that-the-SAME-bytes
  were-delivered-(the-consented-delivery-on-pilot-day)-does-it-take-the-'DERIVED-EQUAL'-label.
- R8-5: ERASURE: external-rail-retention-may-expire ( our-404-case); the-bundle-stores-'receipt_uri'-+receipt-date-and
  ADDS-the-'retention_note'-free-field ( consistent-with-our-machine-readable-reason-proposal-in-#3377)

## 3. PILOT-PENDING — three-open-items-to-be-resolved-when-the-pilot-arrives

| # | Open-question | Evidence-to-be-resolved-on-pilot-day |
|---|---|---|
| P8-1 | `content_hash`-in-x402-is-over-plaintext; our-`delivery_hash`-is-over-served-bytes — the-two-hash-roots-are-DIFFERENT. Will-the-pilot-consented-delivery-give-rise-to-a-third-hash (plaintext↔delivered-equality)? | ultravioleta-113B-delivery: derivation-is-done-if-plaintext-is-given |
| P8-2 | Real-retention-limits-of-the-ECRs ( our-404-case-taught-us: make-NO-assumption) | receipt.retentionUntil-field-is-verified-with-the-voucher |
| P8-3 | Is-`receipt_uri`-a-public-URL-or-under-auth — the-bundle-is-NOT-a-BRIDGE-only-a-REFERENCE | the-#3379-closing-comment-will-clarify |

## 3a. SELF-PILOT-SELF-ANSWERS (2026-09-11, AT-020) — draft-answers, the-gate-LIVES

> AT-020 (control-42, slow) PROVED-the-three-legged-delivery-with-EVIDENCE-IN-HAND: delivered/ran/satisfied
> (`.evidence/SELF-PILOT/2026-09-11/`). The-self-answers-below-were-written-WITH-DATA — the-gate-is-still-pilot-day:
> without-an-external-rail-this-evidence-REMAINS-INTERNAL; once-the-x402-side-is-added-the-same-three-questions-are-reasked-with-the-external-field.

| # | Question | Self-answer (with-self-pilot-data) | What-changes-on-pilot-day |
|---|---|---|---|
| P8-1 | Is-a-third-hash (plaintext↔delivered-equality) required? | NO-no-additional-field-needed: the-`pilot-accept`-doc-carries-BOTH-hashes-at-once (`delivery_hash` + `delivered_sha256`) — the-receiver-signs-both-roots-in-the-same-declaration; no-separate-field-is-ADDED (schema-inline-solution) | If-x402-`content_hash`-(plaintext-root)-becomes-a-third-root-it-is-ADDED-to-the-declaration; pairing-again-'NOT-ASSUMED'-signed |
| P8-2 | Real-retention-limits | NO-deletion-in-self-pilot (evidence-on-frozen-disk); the-`retention_note`-field-stayed-optional, EMPTY-in-internal-evidence | If-external-rail-404-arrives-the-same-field-fills-up (the-404-case-our-lesson) |
| P8-3 | Is-`receipt_uri`-public-URL-or-under-auth | NO-uri-in-self-pilot — an-external-address-is-MEANINGLESS-in-internal-delivery; the-uri-field-must-stay-OPTIONAL | If-an-external-pilot-URI-arrives-public/auth-status-is-determined-ONE-TIME |

**Finding (the-one-structural-inference-in-self-answer-mode):** the-happy-path-in-internal-delivery-is-"declaration-first,-URI-after" —
i.e.-uri-OPTIONAL + retention_note-OPTIONAL. When-the-external-rail-contribution-arrives-all-three-normalize-into-a
SINGLE-PILOT-DAY-RECORD. Schema-M6-(v0.3.0-draft)-already-reflects-this-three-optionality — NO-change.

## 4. Post-pilot-path

1. Pilot-closeout→§3-three-open-items-closed→this-draft-TAKES-the-RFC-008-number
2. `validator`-schema-(v0.3-draft)-+ `ledger-verify`-shape-gate-(R8-3)-implemented
3. `--pair-charge`-tool-extension: if-external_receipt-present-AUTOMATIC-bridge-decision
4. x402-#3377-'external-ledger-binding'-extension-PR-proposal-(E1-gate)

## 5. Why-being-written-NOW (and-why-not-implemented)

The-pilot-day-is-VERY-near. While-the-draft-is-prepared-no-work-starts: pilot-information-can-change-§3
(the-three-open-questions-can-tie-up-the-work). Founder-culture-compliance: "düşünmek-bedava, kodla-değil" — "thinking-is-free, not-with-code".

## 6. F1 — TAMGA_EXTERNAL_ANCHOR_V1 (2026-09-10, founder-APPROVED-framework)

> Direction-reversal: §1-5 cites-the-x402-external-receipt-INTO-OUR-chain. §6 is-REVERSE: our-chain-
> headers-being-bound-to-external-epoch-facts. The-two-are-the-two-faces-of-the-same-RFC — entering-together
> in-the-V0.2-slice.

- **Design-file**: private/F1-EXTERNAL-ANCHOR-TASARIM.md-(anchor-op-shape: foreign_registry/
  foreign_fact/foreign_digest/foreign_source + verified_at-two-field-claim)
- **Frozen-mathematics**: tests/vectors/anchor-v0-design/anchor-design-vector.json +
  AT-017-(control-39): D5-compliance-(anchor-record-enters-the-chain-hash-like-every-record)-
  and-§4.4-parity-(unknown-registry→indeterminate, never absent)-with-canonical-declaration
- **Evidence-link**: .evidence/APODIX-EPOCH-10/2026-09-10/ — the-first-real-external-anchor-candidate
  (fact-0x0236…36e2, 2-independent-keccak-implementations-matched-on-the-same-merkle-path)
- **Gate**: const-flip-(verifier-known-tags+runner-op)-AFTER-PILOT; passes-the-same-gate-as-P8-1/2/3 —
  pilot-day-4-open-(P8-1..3 + F1-label-compliance-with-Vauban)-become-closed

## 8. FEEDBACK-SURFACE (2026-09-10, E1-gone)

- Public-discussion: x402-foundation/x402#3447 (DRAFT-proposal-issue; non-binding)
- The-fate-of-this-draft-is-decided-there; PR-only-after-P8-1..3-are-answered

> English twin of the Turkish-BORN original (docs/RFC-007-schema-revision-v02.md). The Turkish file is the authoritative original; this translation exists for foreign readers. On any divergence, the Turkish governs.

# RFC-007 — v0.2 Schema Revision (R1–R3 APPLIED; R4 candidate)

> **Status: IMPLEMENTED (2026-09-07, founder-approved; R1 5819be0 · R2 6782614 · R3 19028ca).**
> This-heading-declares-from-the-public-surface-IN-WHICH-SCHEMA-the-three-changes-live; principle-change
> is-NONE: receipt-content-still-secret, the-hash-link-adds-a-new-LINK, frozen-v0.1-verification-stands-unchanged.
> The-R4-(signed-RED-proof)-note-stands-as-a-candidate-(§5b); pilot-gated-items-explicitly-labeled.
> Source-draft: private/RFC-007-v02-sema-revizyonu-TASLAK.md-(founder-Q&A-round-2026-09-07).

## 0. Scope-summary (three-changes, all-additive)

| # | Change | v0.1-status | v0.2-realized | Status |
|---|---------|-------------|------------------|-------|
| R1 | `runtime.net` manifest-operation | net.json intermediate-file | declaration-moves-into-`tamga.json`; one-way-migration-tool | ✅ APPLIED (AT-009) |
| R2 | D10 `delivery_hash {alg,hex}` | NONE (RFC-003 §10-candidate) | OPTIONAL-labeled-digest-in-charge | ✅ APPLIED (AT-010) |
| R3 | D12-formalization | conditional-three-fields (in-practice) | formal-conditional-field-set-in-schema | ✅ APPLIED (AT-011) |

Dual-read-window-(the-period-during-which-both-net.json-and-runtime.net-are-valid):
**1-version-cycle**-(founder-decision, 2026-09-07; proposal-adopted).

## 1. R1 — `runtime.net` (M6-manifest-integration) — APPLIED

The-declaration-moves-into-`tamga.json`'s-`runtime`-object-(net.json-content-verbatim):

```json
"runtime": {
  "net": {
    "endpoints": [ {"host": "api.ornek.com", "port": 443, "proto": "https"} ],
    "timeout_s": 30,
    "byte_cap_total_mb": 2,
    "byte_cap_endpoint_mb": 1
  }
}
```

**Realized-decisions-(deviations-from-the-draft-included, honest):**
- In-the-stored-subtree-NO-`format`-key-(the-location-itself-implied-the-format);
  at-validation-time-setdefault-provides-schema-uniformity.
- **D12a-manifest-meaning** = `sha256(jcs(runtime.net-subtree))` — jcs-canonical-invariant
  (not-byte-identical); v0.1-net.json-packages-preserve-file-byte-semantics.
- The-Validator-adds-a-FORMAT-gate-for-runtime.net-(additive); DNS-resolution-fail-closed-in-the-runner.
- `migrate-net`: one-way; author-seed-mandatory-(pubkey≠signature.key → RED 9); signature-via-the-D2
  sig-empty-probe; post-migration-validator-ACCEPT-gate; the-bridge-file-is-deleted;
  existence-of-TWO-sources → RED 10 `net_decl_ambiguous`-(policy-ambiguity).
- Proof: AT-009-(check-22; migrate/binding/ambiguous/dual-read/schema-RED/identity);
  crossval-not-broken.

## 2. R2 — D10 `delivery_hash {alg, hex}` — APPLIED (with-safal207-correction)

- `run --delivery-alg sha256|keccak256` → OPTIONAL-in-charge: `delivery_hash: {"alg":
  "sha256"|"keccak256", "hex": "<64-hex>"}`; if-the-field-is-absent-D4-silence.
- **Meaning:** labeled-digest-of-the-same-bytes-as-the-value-of-`extensions["durable-evidence"].contentHash`
  inside-the-vendor's-x402-settlement-envelope. Third-party-anchoring:
  the-chain-`receiptHash → receipt → delivery_hash → contentHash (envelope)`-is-verified-independently.
- **Label-MANDATORY**-(safal207, x402-#3379: keccak256 ≠ sha256 — an-unlabeled-field-produces-false-agreement
  ). Verifier: if-`alg`-unknown → RED `delivery_alg_invalid`-(before-charge-forms);
  if-`hex`-is-not-64 → RED; ledger-verify-format-gate-(defense-in-depth).
- **Scope-sentence**-(safal207-proposal-adopted): the-field-concerns-only-byte-integrity-and-binding;
  it-MAKES-NO-CLAIM-of-execution-quality/settlement-finality/buyer-acceptance.
- holistis-bridge: the-capacity-attest-`evidenceHash`→`receiptHash`-anchor-is-carried-over-this-field
  -(triple-anchoring); in-v0.2-no-separate-field-OPENS.
- Proof: AT-010-(check-23; 6/6-including-pairing-fixture-delivery_hash-anchoring);
  keccak-digest-identical-with-the-x402-contentHash-world-(no-dependency-on-tamga_keccak).

## 3. R3 — D12-formalization (RFC-003 §11 becoming-schema) — APPLIED

The-three-fields-are-bound-at-schema-level-to-a-**conditional-togetherness**-rule:

- `net_decl_sha256` ↔ `net_events_sha256` ↔ `net_mb` — enter-or-absent-TOGETHER
  (`net_trio_incomplete` RED); trigger: presence-of-`runtime.net`-in-the-package-(or-net.json
  in-the-transition-window) → all-three-MANDATORY; absence → all-three-FORBIDDEN-(the-silent-D4-path-cannot-
  show-"it-spent").
- `net_mb`-formality: number, MiB-6-digits-(RFC-003 §11-rounding-rule-normative;
  `net_mb_format` RED).
- Validator-binding-per-ACTIVE-source-(net.json=byte-hash / runtime.net=jcs-hash):
  post-run-swap → `net_binding_mismatch`; bridge-file-deletion → `net_binding_missing`;
  re-sign-tamper → RED; dual-source → `net_decl_ambiguous`.
- Proof: AT-011-(check-24); crossval-runtime.net-format-family-8-mutants;
  deletion-detection-added.

## 4. Transition-window (dual-read) — founder-closed

- v0.2-validator: accepts-packages-with-net.json-AND-with-runtime.net; the-production-side
  no-longer-PRODUCES-net.json-(the-tool-is-one-way).
- v0.1-validators-UNCHANGED: they-do-not-RED-v0.2-fields-as-unknown-fields
  (consistent-with-the-RFC-003 §3-normative-section).
- Duration: **1-version-cycle**-(founder-decision-2026-09-07; proposal-adopted).

## 5. Schema-promotion-proof

`specs/manifest-0.2.0.schema.json`-(const-0.2.0;-promoted); the-0.3.0-draft-floor-is
`["0.2.0","0.3.0"]`; crossval-60/60-AGREE-(rebased-after-the-v0.2.0-flip).
v0.1-manifests-stayed-valid-in-the-additive-window-(proven).

## 5b. R4-candidate-note — signed-RED-proof (pilot-gated; NOT-APPLIED)

- Example-(#3379-wildcherrycasa)-offline-verification: COSE_Sign1/Ed25519 + JWKS + 206-line-
  standard-library-verifier; the-DENY-decision-carries-the-will-fail-check-by-name.
- Tamga-counterpart: net_denied-events-are-already-bound-by-the-policy-declaration-hash-(the-net_decl_sha256-
  pattern: "under-this-policy-denied-at-this-time").
- Candidate-R4 = out-of-band-independent-signed-DENY-artifact-(for-the-external-auditor); its-anchor-is-the-policy-
  declaration-(NOT-settlement). On-the-table-with-the-pilot-day-as-a-v0.2-scope-question.

## 6. Gates-(founder-normative; UNCHANGED-in-this-document)

- R1-R3: applied-and-locked-(with-AT-proofs); reversal-only-via-a-NEW-RFC.
- R4: pilot-gated; not-applied.
- 0.3.0-schema-(external_receipt): bound-by-the-RFC-008-P8-gate.

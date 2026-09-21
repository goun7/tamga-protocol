> English twin of the Turkish-BORN original (docs/RFC-009-external-chain-anchor-DRAFT.md). The Turkish file is the authoritative original; this translation exists for foreign readers. On any divergence, the Turkish governs.

# RFC-009 (DRAFT) — External Chain Anchor (foreign-registry anchors: our chain cites an external fact)

> **Status: DRAFT — PILOT-PENDING.** This-title does-NOT-claim that a new `anchor` op enters the
> const: the runner-op (RFC-003 v0.2 slice) and the verifier known-tags promotion pass the pilot-day
> gates (the SAME gate as RFC-008 P8-1..3; founder normative approval required).
> What is frozen here: the MATHEMATICS OF THE RECORD SHAPE and the verification CONTRACT — both
> are proven by evidence today (AT-017, check-39). Thinking is free, coding is not (RFC-008 parallel).

## 0. Summary (one-paragraph)

A Tamga ledger record CAN-CITE the fact of an EXTERNAL registry: "this head of this chain was
marked by this proof of that sealed epoch." No new hash is DEFINED — an anchor record enters the
D5 chain mathematics like every other record; the VALIDITY of the external fact is NEVER our
verifier's claim (presentation parity; root recomputation is the origin registry's contract).

## 1. Motivation

- Epoch-10 proof (2026-09-10): we hold a WORKING external proof in hand: 2 independent keccak
  implementations matched on the same merkle path (tamga_keccak + verifier_epoque.py)
- Cross-chain readability: the outside world can cross external checkpoints while reading our chain;
  our chain can likewise carry references to external sealed facts
- Two-field claim culture: an anchor is 'verified that day'; its staleness is not 'wrong'

## 2. Record shape (NEW op in the ledger: "anchor" — v0.2 candidate, NOT FROZEN)

```json
{"seq": N, "op": "anchor", "prev": "<64hex>",
 "anchor_version": "TAMGA_EXTERNAL_ANCHOR_V1",
 "foreign_registry": "apodix/epoch",
 "foreign_fact": "0x0236…36e2",        // cite-edilen-fact (merkle-leaf; 0x+64-lowercase)
 "foreign_digest": "0xabab…abab",      // registry'nin-own-digest'i (sunum-paritesi)
 "foreign_source": "https://…/v1/anchors/proof/0x0236…",  // OPTIONAL (audit URL)
 "verified_at": "2026-09-10T07:32:08Z", // iki-alanlı-iddia: İDDİA-GÜNÜDÜR, süreklilik-DEĞİL
 "tool": "verifier_epoque.py + tamga_keccak (dual-impl)",
 "presentation_only": true}             // R9-5 machine form: NOT our verification claim
```

**Post-pilot shape correction (AT-061, 2026-09-21):** when the pilot opened, two
divergences surfaced — (a) `foreign_source` was in the frozen shape but could not be
written (now writable via the optional `--foreign-source` flag); (b) `presentation_only`
was written but absent from the frozen design vector — i.e. the shape the design taught
was being RED'ed by the read gate. Both were fixed and machine-locked by AT-061: the
design and the writer now teach the same shape; parity is measured not with a hand list
but by FIELD SUBTRACTION (removing each field in turn and observing whether the read gate
RED's it — deriving required/optional, so no stale constant list, the AT-047 SPEC_OPS
lesson).

**D5 compliance (proven by evidence today):** `h = sha256(prev ‖ jcs(record − {h, node_sig}))` —
the op field makes no difference; an anchor record enters the chain hash LIKE EVERY record
(AT-017-1: recomputation = vector-h, check-39).

**Rules (v-draft):**
- R9-1: `anchor_version` is the fixed string `TAMGA_EXTERNAL_ANCHOR_V1` (version promotion EXPLICIT)
- R9-2: `foreign_registry` ∈ registry names (`apodix/epoch` is the only example today; the list GROWS,
  each addition by an additive const promotion)
- R9-3: `foreign_fact`/`foreign_digest` canonical 0x+64-lowercase (x402 #3377 discipline)
- R9-4: `verified_at` RFC3339-UTC-Z; being a **two-field claim** (claim, day), the DEX
  comparison NEVER becomes invalid — an old anchor reads as 'older', not 'wrong'
- R9-5: the external fact's validity is NOT our verifier's claim: even when foreign_registry is
  KNOWN, the verifier LEAVES the root recomputation to the registry's contract (§4.4 parity)

## 3. Verification contract (mini-verifier; proven by evidence today)

| Case | Verdict | Behavior |
|---|---|---|
| the anchor record's D5 hash | chain mathematics | verified like every record |
| `foreign_registry` empty/missing | `indeterminate`-"empty origin tag (§4.3 F1)" | an untagged value is just a number |
| `foreign_registry` unknown | `indeterminate`-`unknown origin tag` | **result withheld, NOT absence** |
| `foreign_registry` known | `indeterminate`-`presentation only (§4.4)` | the crossable point's path is shown; not dressed green |

Recognition list: `KNOWN_FOREIGN_TAGS` (today: `TAMGA_CHAIN_HEAD_V1`, `APODIX_EPOCH_ROOT_V1`;
promotion is additive). This behavior is DECLARED canonical behavior: it is live in tamga_verify_mini and
locked by AT-017-3.

Sibling surface (2026-09-15): `tamga_attest_verify` (AT-030) — off-chain signed foreign record verification;
the unknown-registry → INDETERMINATE pattern was taken from the table IN THIS DOCUMENT (format unity preserved).

**E-15 (2026-09-15) — chain-binding pre-query (epoch-verify CLI, anchor leg):** the verified
chain root belongs to the chain read — the identity binding must be a testable field, not a fixed assumption
(our surface's form of the x402 #2887 #issuecomment-5680705648 class: how is it known that the
caller-supplied `--rpc` is the claimed chain?). `read_onchain_epoch` now asks `eth_chainId` **FIRST**;
on mismatch with `--expect-chainid` (default 11155111 = sepolia — the chain of DEFAULT_CONTRACT):
INDETERMINATE "wrong-chain" (rc2 — red is not green either: it produced no verdict).
`--expect-chainid 0` is a deliberate skip and prints a visible honest note on stdout (the "which chain"
question is not censored; it is left unanswered). Negatives: AT-027 cases 8/9 (fake-chain mock + skip note).

## 4. WHAT-NOW / WHAT-LATER

NOW (this document): (a) public-surface design note (promoted from the private F1 doc; content verbatim);
(b) frozen mathematics and evidence links (below); (c) **receiver side (2026-09-12,
founder-APPROVED): `tamga_pugio_receiver.py`** — takes the `external_anchor` JSONL lines of the
proof-bundle produced by the PUGIO bridge and verifies with sha256 ONLY
(`anchor_id = SHA256(head|merkle_root|event_count)[:32]`, bridge_version 1); a single RED line
makes the entire file RED (fail-loud — silent-pass doctrine). First-step principle: it does not touch
the PUGIO core/schema, adds no dependency. Suite evidence: **AT-024** (selftest +
head-change detached-link + envelope type + single RED line + unknown bridge_version —
6/6). **(c2) `tamga_pugio_ingest.py`** — the receiver's 2nd step: verifies the 81 MERGEN-side K0
proof-bundle (chain-binding + proof + merkle-root + head + count cross, K0-envelope-spec private)
with pure stdlib and, per the Tamga doctrine, produces a deterministic **verification receipt**
(fail-closed: a RED bundle gets NO receipt); suite evidence: **AT-025** (selftest + full-path +
payload-scraping + merkle-root + -event-count forgery + version-gate (6/6). The bridge mathematics
(from this §5's projection direction) is different and complementary to it: the projection carries
the chain tip OUT; the receiver verifies the anchor coming IN from OUTSIDE on the Tamga side;
ingest verifies the ENTIRE body of the incoming bundle and produces a receipt.
LATER (pilot-day gates): (d) `anchor` op in the runner (RFC-003 v0.2 slice); (e) verifier
known-tags + const promotion; (f) label-compliance confirmation with Vauban (of the 4 open pilot-day
gates: P8-1..3 + F1 label compliance).

## 5. Evidence links

- **External-proof (working)**: `.evidence/APODIX-EPOCH-10/2026-09-10/` — epoch-10 manifest
  (root 0x997c…71d, 57-leaf merkle, keccak256/@openzeppelin, L1-chain 11155111-block-11672468,
  tx-0x0d30…cea22) + fact-proof (fact 0x0236…36e2, position 55, 6-step path) +
  independent verifier `verifier_epoque.py`
- **Dual-implementation cross**: tamga_keccak (KAT 3/3: empty/abc/fox) × verifier_epoque.py —
  matched on the same merkle path (night cross-check, 2026-09-10)
- **D5 and field-freeze**: `tests/vectors/anchor-v0-design/anchor-design-vector.json` +
  AT-017 (check-39; 3 runs: D5-recomputation/field-completeness/KNOWN_FOREIGN_TAGS parity)
- **Batch-leaf projection (composition)**: AT-022 (check-46; 2026-09-12): the Tamga chain-head
  (D5 sha256, full 64-hex) was encoded with the Vauban leaf schema (k256(k256(bytes32))) and
  projected onto the fact position of the epoch-10 batch; the whole batch (57 leaves) was folded
  independently with tamga_keccak and matched the manifest root BYTE-for-byte. Lesson recorded:
  the felt252 representation (leading zero not written) is one of the cross-check traps. Vector:
  `tests/vectors/anchor-v0-design/composition-fixture.json`

## 6. Risks (honest)

- If the schema is locked without seeing pilot data, reversal cost → for this reason ONLY the
  mathematics was frozen; the op enters the const AFTER the pilot
- If the external-fact publisher stops, the anchor goes stale → the two-field claim (R9-4) is
  exactly for this: stale ≠ wrong
- The visible verification of anchored chains may appear registry-dependent → the §3 contract
  explicitly bounds this with 'presentation-only'; NO green dressing

## 7. FEEDBACK SURFACE

- Public discussion x402-foundation/x402#3447 (same channel as the RFC-008 E1 draft; DRAFT proposal
  issue is non-binding)
- The fate of this draft lies on the table there; PR only after P8-1..3 and label compliance close

# RFC-011 (DRAFT) — Dispute-Pointer: The Dispute Leg

> **Status: DRAFT.** RFC-010 proves *consensus* (all five checks GREEN).
> But the gap holistis's D-017 identified remains: **who picks between two
> validly signed contradictory claims?** Pacta's §5.3 fills that gap with
> *Schelling arbitration* + *20% dispute bond*. This RFC binds those two
> sides together — **without adjudicating on our behalf**.

## 0. Summary

An additive `dispute_pointer` field on `settlement_bind`. When the
contract plurality of a claim cannot be resolved (even with RFC-010 GREEN,
if the buyer signed `delivered:no`), the proof **marks a contradiction**,
not RED but İNDETERMİNE: *"these two sides are equally valid; a human or
arbitrator decision is required."* At that moment `dispute_pointer` points
to an external process — Pacta escrow, holistis's `disputeContext`, or any
arbitration mechanism.

**The third-option prohibition holds:** we do NOT adjudicate. We only
detect the contradiction and point to external resolution.

## 1. Motivation — why now

holistis-x402#3379 (D-017): *"record_delivery only accepts a buyer-signed
claim, verifyClaim resolves the signature only to buyerAddress, **there is
no seller-counter-claim mechanism at all**"* — *"a dispute only ever shows
one side, structurally"*; *"signature proves who said it, never what
actually happened; attribution, not truth."*

Pacta-§5.3 fills the same gap from the other side: 20% dispute bond +
Schelling consensus + quadratic slashing. **The two complete each other:**
holistis names the gap, Pacta carries the resolution mechanism.

**Tamga's role:** not arbitrator, but **contradiction detector + router**.

## 2. Record shape (additive field, no op)

```json
{"op": "charge", "seq": N, ...,
 "settlement_bind": {...},
 "dispute_pointer": {                          // additive, optional
   "status": "contradiction",                  // "none"|"contradiction"|"resolved"
   "counter_claim": {                          // buyer's delivered:no claim
     "buyer_signed": true,
     "delivered": false,
     "evidence_hash": {"alg": "sha256", "hex": "<64hex>"}},
   "arbitration": {                            // external-resolution pointer
     "protocol": "pacta/v1"|"holistis/disputeContext"|<unknown-string>,
     "case_ref": "<string>",                   // filled once a case is opened
     "terms_hash": "<64hex>"},                 // essence of the agreed terms
   "bond_pct": 0.20}}                          // Pacta-§5.3: mandatory 20% bond
```

**Why additive:** the same principle as RFC-010 — no new op write class,
it enters the D5 chain hash. With `status:"none"` the stitch stays GREEN
(backward compatible).

## 3. Verification contract

`../tools/dispute_pointer_verify.py` — runs **after RFC-010's 6th check**:

| # | Check | What it proves | On failure |
|---|---|---|---|
| 1 | RFC-010-GREEN precondition | stitch already valid | returns RED |
| 2 | **contradiction detection** | two validly signed contradictory claims | İNDETERMİNE |
| 3 | if status-`contradiction` then `arbitration` MANDATORY | routing cannot vanish | RED rc9 |
| 4 | `bond_pct` ≥ 0.20 (Pacta-§5.3) | griefing prevented | RED rc10 |
| 5 | `protocol` list is additive | unknown is not RED | İNDETERMİNE |

**Fail-closed rule:** 3 and 4 are RED. But 2 and 5 are İNDETERMİNE — **the
contradiction cannot be resolved with partial GREEN**; a human or arbitrator
is required. This is why 6/6-GREEN does NOT mean "delivery was good"; it
means only "nobody objected."

## 4. WHAT-NOW / WHAT-NEXT

**NOW:** (a) `dispute_pointer` field definition; (b) contradiction detector
(comparing two signed claims); (c) AT-073 negative controls for
contradiction, empty arbitration, low bond; (d) prove the
`TamgaVerifier.verify()` reference in Pacta-§5.2 (pre-existing link).

**NEXT:** (a) live test with the Pacta arbitration simulation; (b) holistis
`disputeContext` schema alignment; (c) add `pacta/v1` to the `protocol` list.

## 5. Risks (honest)

- **"Greenwashing" danger is LARGE:** the `6/6-GREEN` claim can be
  misread exactly here. RFC-010-GREEN = *"proof of consensus"*, NOT
  *"delivery was good"*. dispute_pointer writes this explicitly but people
  read the badge.
- **Arbitrator decentralization is mandatory:** Schelling consensus and
  slashing are Pacta's job; we only point. If Tamga chose the arbitrator we
  would become a single point of failure.
- **bond_pct-20% is arbitrary:** it is Pacta-§5.3's number; the
  game-theoretic optimization is not ours. It is marked as an externally
  sourced value (§3-check-4).

# Why a hash chain, and where Merkle fits

> Design-note — no spec change. Answers the most common technical question we get:
> "why a linear chain for the ledger instead of a Merkle tree?" and its twin:
> "so where DO you use Merkle?" Both answers are load-bearing; neither is an accident.

## 1. The ledger is a chain (RFC-003 D5)

`h = sha256(prev ‖ jcs(record − {h, node_sig}))` — each record commits to its
predecessor. Three properties follow that a tree does not give, and that matter
more for a work-receipt ledger than fast membership proofs:

**Append-order is semantic.** A receipt chain is a *narrative*: grant → charge →
charge → … Each record's meaning depends on what came before (sessions, fee
accumulation, D12 net-binding against the LATEST charge). A Merkle tree
commits to a *set*; sets have no "what came before." To recover order you must
anyway serialize the sequence — at which point the chain is the cheaper
serialization.

**Truncation is detectable without a trusted anchor.** With a chain, handing
someone records 1..k of an n-record ledger exposes the cut: the receiver asks
for `ledger_tip` (F21, reason 14) and any chain that stops early fails the tip
cross-bind. A Merkle tree, given only the root, cannot tell "element 3 was
removed" from "the ledger always had 3 elements" without a witness structure
that re-introduces the ordering the tree was meant to avoid.

**Partial verification is inherent, not bolted on.** The mini-verifier
(`tamga_verify_mini.py`, stdlib-only) replays the chain from any prefix and
recomputes every head. There is one verification algorithm and it is 90 lines.
A Merkle proof system needs per-leaf witnesses plus a canonical way to hold
"the rest of the ledger" — more artifacts, more to explain, more to get wrong.

Costs we accept, honestly:
- **O(n) verification.** Fine at our scale (memory-scale sanity test: the full
  suite runs in ~20 s; per-op medians 60–130 ms at load~7). If receipt volume
  ever makes O(n) real, the fix is checkpointing (an anchored intermediate
  head), not re-rooting history.
- **Single tip.** Whoever holds the seed can rewrite a tail they own (A3 —
  documented upper bound, not an undisclosed gap). The answer to that adversary
  is external anchoring, which is exactly:

## 2. Where Merkle appears anyway

- **Snapshot integrity (D6):** `graph_merkle` = ordered hash over nodes+edges —
  a tamper-evident *seal* on an unordered set (memory). That is the right tool
  for a set. Reason 17 REDs a mismatch at import; the documented limit (seed
  holder can re-mint a consistent seal) is the same A3 boundary.
- **External anchoring profiles (RFC-003 §8, the v0.1 profile work):** epoch
  anchoring of receipt heads into batch roots is Merkle-structured — inclusion
  of a head in a sealed epoch is a membership claim, and membership claims are
  what trees are for. The §4.4 rule (unknown label → indeterminate, never
  absent) came from exactly this interface.
- **What we refuse:** replacing the ledger with a tree "for performance."
  Performance is a Faz-2 measurement question (overhead baselines exist), not a
  data-structure question.

## 3. The one-sentence rule

Sets get seals (merkle); sequences get chains; membership-in-a-sealed-batch gets
proofs. Each structure appears where its cost model matches the claim it carries.

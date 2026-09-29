# RFC-010b — settlementRef as a Node-Cosigned Hash (Composition with the Buyer Delivery Claim Extension)

**Status: DRAFT — pre-pilot design, companion to the five-check gate.**
This is the "worth exploring properly" composition from
[x402 issue #3379](https://github.com/x402-foundation/x402/issues/3379),
written as a design document rather than a comment. It is a proposal from the
Tamga side, directed at the join point
[PR #3604](https://github.com/x402-foundation/x402/pull/3604) §6 leaves open. It
assumes nothing about x402 adopting it. Both specifications it touches are
pre-freeze; this one is too.

**Relationship to the other RFC-010 document.**
`RFC-010-cross-artifact-settlement-binding-DRAFT.en.md` defines the five-check
gate and its fail-closed rule. This document defines what it *means* for check 3
(`settlementRef resolves`) to succeed without trusting a facilitator, a chain
index, or a directory, and what that buys check 4 (`payer/payee match`). The gate
is the policy; this is the resolution semantics for one of its inputs.

**Reference implementations it builds on (both shipped, both pre-freeze).**
Tamga D10 (`docs/RFC-003-ledger.md` §10, `AWAITING FOUNDER APPROVAL`) and the
verifier `tools/settlement_bind_verify.py`, with negative controls in
`tests/at007_pairing_fixture.sh` and AT-063. The public fixture is
`docs/pairing/pairing-fixture.json` (pinned receiptHash
`fe6f230c…323641c`).

---

## 1. The gap in PR #3604 §6, stated precisely

The Buyer Delivery Claim Extension strengthens the claim-to-settlement join with a
normative requirement: *where the underlying settlement is inspectable, a verifier
MUST confirm `claim.buyerAddress` matches the `payer` of the settlement named by
`settlementRef`.* That is the right join point and the right strength. The
conditional is the problem, because the spec does not define what makes a
settlement inspectable.

`settlementRef` is typed as *the x402 payment reference or on-chain transaction
hash*. Those are two different lookups with two different failure modes:

- **Transaction hash branch.** Well-defined in principle. In practice, for a
  settlement routed through a gas sponsor, a paymaster, or an ERC-4337 bundler, the
  transaction's `from` is the relayer, not the buyer. A verifier reading `from` as
  `payer` fails a legitimate claim. A verifier that understands account abstraction
  must reconstruct the UserOperation to find the actual sender. Neither behavior is
  specified, so two compliant implementations disagree on the same claim.
- **Payment reference branch.** There is no defined lookup at all. No facilitator
  endpoint, no grammar, no directory. The check is normative and unresolvable at the
  same time.

So the MUST in §6 is only as strong as a resolution path nobody has pinned. This is
not a defect in the extension's design. It is the exact seam that appears when a
buyer-side credential tries to name something on the settlement side without a
shared notion of what a settlement identifier *resolves to*.

**The attribution rule that governs this seam (x402 #2887).** Whichever branch a
verifier takes, the three addresses of the settlement stay distinct, and
[issue #2887](https://github.com/x402-foundation/x402/issues/2887) fixes which one
carries facilitator attribution: `payTo` is the merchant, the facilitator is
`tx.from` (the submitter), and the merchant's payee address can never be the
facilitator address. A record that answers *"which facilitator settled this"* must
key on the **submitter**, never on the payee — keying on the payee makes every
merchant attribution-less, because `payTo` identifies the merchant and never the
facilitator. RFC-010 §3c encodes this normatively as the optional `bind.submitter`
field with a fail-closed guard against `submitter == payee`. The same rule binds
this composition: `declared_parties.payer`/`payee` below are always buyer/seller,
and neither may be read as facilitator identity.

## 2. The proposal in one paragraph

Let `settlementRef` resolve to a **content-addressed, node-cosigned ledger hash**
rather than to a payment-side identifier. Concretely, the value it carries is the
receipt's ledger hash `h`, and `h` is **recomputable by anyone from the record
alone** — no facilitator query, no chain index, no directory. The chain of custody
runs `claim.settlementRef` → `charge.h` → (`prev`, `jcs(record)`) →
`delivery_hash` → the delivered bytes. Because the anchor is recomputable, check 3
becomes a hash equality you can perform offline with the record in hand. Because the
record is node-cosigned (`node_id` inside the hash input, `node_sig` over `h`), the
anchor carries an operator declaration rather than a bare buyer or seller claim.

The consequence for §6 is the part worth exploring: **if the anchored record also
carries a declared `payer` inside the hashed input, the "where inspectable"
conditional disappears.** The payer is not something you fetch from a settlement
anymore; it is part of the anchor's preimage, tamper-evident and attributable. The
buyer's signature over the claim then binds the claim to that payer, and a mismatch
is a single comparison between two values both already in the verifier's hands.

## 3. Record shapes (no schema change on either side of the seam)

The receipt side is an existing Tamga charge record. From the public fixture:

```json
{"op": "charge", "seq": 2,
 "prev": "d034e3199877455cb46b6ba82b8d1b33815203c9463123477cff3b20a371050b",
 "h": "fe6f230cd7d435e092c0835ee8ccc009cfce8c215899b1c968f112635323641c",
 "pkg": "<name>", "session": "<id>", "ts": "<iso8601>",
 "delivery_hash": {"alg": "keccak256", "hex": "8494d3b5…f4cd"},
 "input_sha256": "<64hex>", "stdout_sha256": "<64hex>",
 "cpu_saat": 2.983e-06, "ram_gb_sn": 0.0, "io_mb": 0.0,
 "wall_ms": 0, "engine": "wasmtime-v48.0.1",
 "fee_birebir": 2.0, "fee_sim": 2.0}
```

At the L1 cosign layer (RFC-003 D8, opt-in), the record additionally carries
`node_id` inside the hash input and `node_sig` over `h`. Neither `h` nor
`node_sig` is part of `h`'s own preimage.

The claim side is PR #3604 §4 unchanged, except for one thing: the `settlementRef`
**string** gets a discriminated form so the extension's string type is preserved
and existing parsers keep working.

```text
settlementRef := "tamga:ledger-v1/" <64 lowercase hex>      # this composition
              |  "0x" <64 lowercase hex>                     # on-chain transaction hash
              |  <any other string>                         # unresolvable, see §6
```

A verifier dispatches on the prefix. `0x`-prefixed 64-hex keeps its existing
meaning. Everything else stays exactly as the extension defines it, including its
documented limitations.

## 4. The two bindings this replaces §6's conditional with

**Binding A — settlementRef resolves (recomputable, offline).**

Given the charge record from any substrate (the fixture, a local ledger, an
attestation, a peer's mirror — the record is content-addressed, so provenance does
not matter), recompute the anchor and compare:

```python
from tamga_canon import jcs  # RFC 8785 JCS — same serializer as the claim side

def recompute_h(record: dict) -> str:
    pre = {k: v for k, v in record.items()
           if k not in ("h", "node_sig")}     # h and node_sig are not preimage
    return sha256(record["prev"].encode("utf-8") + jcs(pre)).hexdigest()

# check 3 — settlementRef resolves
assert settlement_ref_value(record) == recompute_h(record)
```

`prev` enters the hash twice by design: once as the ASCII-hex prefix, and once
inside the jcs input as the record's own `prev` field. This is the same formula
`tools/verify_pairing_fixture.py` runs as its membership check, and it reproduces
the public fixture's pinned `h` (`fe6f230c…323641c`) byte-for-byte from the record
above with no dependency on this repository's runtime, only the JCS contract.

`jcs` is RFC 8785 canonical JSON (ES6 number serialization, sorted keys, no
whitespace) — the same canonicalization the claim side already uses, which keeps
the two sides byte-compatible without sharing a serializer implementation. This is
a pure function. It runs against the public fixture today; the pinned value above
is what it reproduces.

**Binding B — payer is inside the anchor, not behind a lookup.**

Extend the anchored record's hashed content with a declared party pair. This is an
additive field on the receipt side, the same way `settlement_bind` is additive in
the five-check gate, so it enters `h` without changing any op:

```json
"declared_parties": {"payer": "0x<40hex>", "payee": "0x<40hex>"}
```

Then §6's requirement becomes a comparison between two values the verifier already
holds, and both are tamper-evident because both are inside `h`'s preimage:

```python
# check 4 — payer/payee match, now without any "where inspectable" conditional
assert claim["buyerAddress"].lower()  == record["declared_parties"]["payer"].lower()
assert claim["sellerAddress"].lower() == record["declared_parties"]["payee"].lower()
```

The case normalization matters here and is not optional: the claim side checksums
addresses (EIP-55 mixed case in the reference implementation's own fixture) while
the receipt side stores lowercase hex. Both sides must lowercase before comparison,
exactly as both sides must lowercase before canonicalization. Without that rule the
same pair of addresses verifies under one implementation and fails under another.

**Check 5 — evidenceHash byte-equality.** Already specified in the five-check gate
as `claim.evidenceHash == receipt.delivery_hash.hex`. One alignment point it
surfaces: the claim's `evidenceHash` is defined as sha256, while the fixture's
`delivery_hash.alg` is keccak256. Byte-equality is only well-defined when the two
sides agree on the algorithm, so an x402-paired receipt either pins
`delivery_hash.alg` to `sha256`, or the claim carries the alg alongside the digest.
Pinning is simpler and is what I would propose; carrying it is more permissive. This
is a real decision, not a detail, and it should be made before either side claims
check 5 works cross-implementation.

## 5. What the two trust roots do and do not cover

The whole point is that the two roots stay separate and neither impersonates the
other.

| | Work side (receipt) | Claim side (delivery claim) |
|---|---|---|
| Trust root | node operator signature over `h` | buyer signature over `claimId` |
| What it proves | a chained, node-certified record exists for this work, and the work's delivery digest is inside it | the paying party asserts an outcome |
| What it cannot prove | execution quality, payment finality, buyer acceptance | that the outcome is true (§8, no cost to a false claim) |

The composition does not close the claim side's open problem. A buyer can still
sign a false `delivered: no` at zero cost, and this document does not change that.
What it changes is the settlement side: the claim is now bound to a *specific,
recomputable* settlement with a *declared, attributable* payer, instead of to an
identifier that may or may not resolve depending on where the verifier is standing.

The honest residual limit on the receipt side is that a node operator who is also
the seed owner can mint consistent state on a fresh node (documented in RFC-003
§4.4, the simnet-v0 upper-bound adversary). And a node can declare a false payer.
But `node_id` is inside `h` and `node_sig` signs `h`, so a false declaration is
attributable to a named operator and non-repudiable. That is a strictly better
failure mode than an undefined resolution path, which fails silently and names
nobody.

## 6. Compatibility and the unresolvable case

This is an additive overlay, and it degrades honestly.

- A claim whose `settlementRef` carries `tamga:ledger-v1/…` gets the recomputable
  anchor and the anchor-internal payer check.
- A claim carrying a bare transaction hash keeps PR #3604's §6 exactly as written,
  conditional and all. Nothing is taken away.
- A claim carrying free text the verifier does not recognize is not RED and not
  GREEN. It is **unresolvable**, which is the third verdict the five-check gate
  already defines (`INDETERMINATE`, deliberately not RED, so the gate does not force
  x402). The claim still verifies on its own signature. The settlement join is
  simply not established, and a policy layer above decides whether that is
  acceptable.

The failure mode is deliberately asymmetric, and it is the same asymmetry D10
chose: on the receipt side, a settlement that names no work is RED, hard, because a
payment claim on unbound work is no result. On the claim side, an unresolvable
reference is INDETERMINATE, because the extension is optional by design and forcing
it would make the check skippable in the exact way §3 refuses.

## 7. Concrete next steps, in order

1. **Pin the canonicalization contract on the claim side.** Address lowercasing and
   the ASCII-hex signing surface (the `0x`-prefixed 67-character string, not the 32
   raw bytes). These are the prerequisites for any cross-implementation byte
   equality, including this one. Tracked as review points on PR #3604.
2. **Decide the `evidenceHash` / `delivery_hash` algorithm alignment** (§4, check 5).
3. **Add `declared_parties` to the anchored record** as an additive hashed field,
   with a negative control where the declared payer differs from the claim's
   `buyerAddress` and the gate goes RED.
4. **Wire the `tamga:ledger-v1/` dispatch** into `tools/settlement_bind_verify.py`
   alongside the existing `x402/v1` channel, reusing the three-verdict structure.
5. **Ship a joint fixture** — one pairing document plus one buyer claim — where all
   five checks pass, plus the five negative controls (swapped hash, swapped parties,
   ref mismatch, invalid signature, broken chain). The pairing fixture already
   carries the first three; the claim half is the new artifact.

Steps 1 and 2 are on the claim side and are decisions, not implementations. Steps 3
through 5 are on the receipt side and can proceed independently, since the anchor
and its negative controls already exist and only the party pair and the dispatch
prefix are new.

## 8. What would falsify this

If the anchor cannot be recomputed from the public fixture bytes by an independent
implementation, the resolution claim is false. That is checkable now, against
`docs/pairing/pairing-fixture.json`, by anyone, with no dependency on this
repository. **The check was run while writing this document**: the `recompute_h`
function in §4, using only RFC 8785 JCS and the record's own fields, reproduces the
fixture's pinned `h` (`fe6f230cd7d435e092c0835ee8ccc009cfce8c215899b1c968f112635323641c`)
exactly. That is the load-bearing claim of this document, and it holds today rather
than at some future pilot.

The second test is softer but more important. If the claimed payer binding turns out
to require trusting the node for the payer's *identity* rather than merely for the
*declaration*, the composition has not removed the §6 conditional, only relocated
it. §5 states the honest form of this already: a node can declare a false payer, and
the mitigation is attribution (node_id inside `h`, node_sig over `h`), not
infallibility. That is a real limit and it is stated rather than smoothed over.

# RFC-010 (DRAFT) — Cross-Artifact Settlement Binding

> **Status: DRAFT — pre-pilot design.** This heading is the Tamga side of
> the "cross-artifact-settlement-binding" stitch proposed by safal207 in
> x402#3379. safal207's clear diagnosis: *"wiring those existing artifacts
> together now would demonstrate the join shape, not prove that both
> artifacts belong to the same purchase."* This RFC turns that stitch
> **into proof**.

## 0. Summary (one paragraph)

It gathers the five independent checks needed to bind an agent run to the
x402-paying transaction into **one verify gate**: receipt verifies, claim
verifies, settlementRef resolves, payer/payee fields match buyer/seller,
and evidenceHash == receiptHash byte-equal. **None alone is sufficient** —
all five together prove; **if even one differs, all are RED** (fail-closed).
No schema change: it binds the existing `charge` delivery_hash field and
the x402 claim fields.

## 1. Motivation — why this stitch now

The **0.6–7.5% agentic rate** TRM Labs found in x402 payments arises from
the absence of this stitch: a settled transaction carries value but **does
not prove the model made the purchase decision**. safal207's precise list:

> `receipt verifies + claim verifies + settlementRef resolves + payer/payee
> match buyer/seller + evidenceHash == receiptHash, with a swapped hash or
> party as the negative control. No schema changes needed on either side.`

All five exist separately today but **do not come together** — the missing
stitch shows "join shape," does not give "proof."

## 2. Record shape (NO NEW op — binds existing fields)

The stitch adds a `settlement_bind` field to a single charge record
(additive, no op):

```json
{"op": "charge", "seq": N, "prev": "<64hex>", "h": "<64hex>",
 "stdout_sha256": "<64hex>",                        // receiptHash half (Tamga)
 "delivery_hash": {"alg": "sha256", "hex": "<64hex>"},  // work delivery (safal207: label required)
 "settlement_bind": {                                // NEW additive field
   "scheme": "x402/v1",
   "payment_id": "<string>",                         // x402 paymentId (from claim)
   "claim_evidence_hash": {"alg": "sha256", "hex": "<64hex>"},  // tokenizen evidenceHash
   "payer": "0x<40hex>",                             // x402 claim buyerAddress
   "payee": "0x<40hex>",                             // x402 claim sellerAddress
   "submitter": "0x<40hex>",                         // OPTIONAL: settlement tx.from = FACILITATOR (§3c, #2887)
   "verified_at": "2026-09-21T00:00:00Z"}}           // RFC3339-Z (same rule as R9-4)
```

**Why an additive field and not an op:** an op opens a new write class
(GATES/EMITTED_OPS audit); adding a field is governed by version bump and
already enters the D5 chain hash (the whole record is hashed). This also
preserves the R9-5 principle of the `anchor` op: **the stitch proof
RECORDS, it does not VERIFY the external claim** — verification is the
§3 gate below.

## 3. Verification contract (five core checks + two additive, one gate)

`../tools/settlement_bind_verify.py` — pure stdlib, three verdicts:

| # | Check | What it proves | Failure verdict |
|---|---|---|---|
| 1 | **receipt-verifies** | the charge record's D5 chain and delivery_hash are valid | RED `receipt_invalid` |
| 2 | **claim-verifies** | the x402 claim's signature resolves to buyerAddress (EIP-191) | RED `claim_signature_invalid` |
| 3 | **settlementRef-resolves** | the claim's settlementRef matches payment_id | RED `settlement_ref_mismatch` |
| 4 | **payer/payee-match** | claim buyerAddress == bind.payer AND sellerAddress == bind.payee | RED `party_mismatch` |
| 5 | **evidenceHash == receiptHash** | claim evidenceHash byte-equal == charge delivery_hash.hex | RED `evidence_hash_mismatch` |
| 6 | **foreign-chain-verifies** (additive, optional) | the declared foreign-chain proof is not rotten (§6) | RED `foreign_chain_broken` |
| 7 | **submitter/payee-distinct** (additive, optional) | `bind.submitter` (facilitator) ≠ `bind.payee` (merchant) (§3c) | RED `submitter_payee_conflation` |

Checks 1–5 are the safal207 core and are mandatory. Checks 6–7 are
**additive and optional — absent → old GREEN** (R9-2 promotion rule; the
gate must never break a stitch it can already prove).

**Fail-closed rule (the core of safal207's proposal):** any one RED → all
RED. No partial GREEN. This closes the "show join shape" trap.

**Negative controls (safal207: "swapped hash or party"):**
- `evidenceHash` bytes swapped → 5-RED (even if the other 4 are GREEN)
- `buyerAddress`/`sellerAddress` swapped → 4-RED (even if 1,2,3,5 GREEN)
- `payment_id` one letter changed → 3-RED

**Unknown scheme:** İNDETERMİNE (not RED — consistent with safal207's
principle of not forcing x402; the `scheme` list is additive: `x402/v1`,
`tamga/native`, `erc8004/v1`).

### 3b. Signature-verification interface (per-channel input shape) — AT-077 lesson

Check-2's signature verification **requires a different input per scheme**.
So all three channels are pinned in the table below (before AT-077 this
pinning did not exist and two stubs carried a hidden gap — see §5b):

| scheme | what is signed | how signer identity resolves |
|---|---|---|
| **x402/v1** | raw bytes of the sha256 digest (`z=raw-sha256`; EIP-191 unprefixed) | `ecrecover_to_pub(digest,sig)` — address from recovery |
| **tamga/native** | raw bytes of the sha256 digest (RFC-8032 message = 32-byte digest) | public key is public: `claim.buyerAddress` = pubkey; verified with nacl, again pubkey if it matches |
| **erc8004/v1** | membership proof (no signature; root hash is identity) | root hash → `keccak256(digest)` |

**Why over the digest (not the body text):** the gate and the producer do
not have to share the same JSON serialization (gate serializes with
`sort_keys=True` default separators, Yieldix with `separators=(",",":")` —
different bytes, same object). When Ed25519 signs the raw message, both
sides must know the same bytes; when it signs the digest, **only the
64-hex digest equality matters** — which is exactly the byte equality
check-5 demands. So the signature channel and the evidenceHash channel
merge in the same context.

**Parallel truth with AT-075:** the `z=raw-sha256` rule in `x402/v1` likewise
requires signing without `encode_defunct`; `tamga/native` has the same input
shape, digest bytes. Third-option prohibition: a signature outside this
contract is not RED and not İNDETERMİNE — it is direct RED rc4 (channel
defined but signature wrong).

### 3c. Submitter/payee distinction — facilitator attribution keys on `tx.from`, never on `payee` (x402 #2887)

babyblueviper1's diagnosis in [x402 issue #2887](https://github.com/x402-foundation/x402/issues/2887)
is a claim about **which field a settlement record may key facilitator
attribution on**. Stated precisely:

> `payTo` is the merchant; the facilitator is `tx.from` (the submitter). The
> merchant's payee address can never be the facilitator address. If a record
> shape wants to key on "which facilitator settled", it must key on the
> SUBMITTER address, not the payee — otherwise every merchant appears
> attribution-less.

The three addresses of an x402 settlement are therefore **mutually distinct
roles, not three names for one party**:

| field | source | role |
|---|---|---|
| `payer` | `claim.buyerAddress` (EIP-3009 authorization `from`) | the party that authorizes/owes the payment |
| `payee` | `claim.sellerAddress` = merchant's `payTo` | the merchant that receives the funds |
| `submitter` | the settlement transaction's `from` | the **facilitator** that executes the settlement |

**Why the pre-existing payer/payee keying is already correct.** `bind.payer`
is sourced from `claim.buyerAddress` — the claim's signed buyer — and check-4
compares exactly those two values. It is never sourced from the settlement
transaction's `from`. So the record never mistakes the facilitator for the
payer, and never mistakes the merchant for the facilitator. The #2887 trap is
only reachable if a producer copies `tx.from` into `payer` or into `payee`;
both of those are already caught — check-4 RED `party_mismatch` (a swapped or
mis-keyed party is one of safal207's named negative controls).

**What was genuinely missing, and is now closed by check-7.** The record had
no field that answers *"which facilitator settled this"* at all. A consumer
needing that attribution had one wrong place to look — `payee` — and that is
exactly the #2887 failure mode: keying facilitator attribution on `payee`
makes every merchant attribution-less, because `payTo` identifies the
merchant, never the facilitator. The fix is additive, not a rekey: an
**optional `bind.submitter`** is introduced as the facilitator attribution
key, and its single rule is #2887's own claim:

- **absent** → old behavior, GREEN (backward compatible; nothing is forced —
  third-option-prohibition preserved).
- **present** → it is the facilitator (`tx.from`) and it **must not equal
  `payee`**: `submitter == payee` → RED rc9 `submitter_payee_conflation`.
  The merchant's payee address can never be the facilitator address; a record
  asserting otherwise is either collapsing the two roles or hiding the
  facilitator behind the merchant, and the gate refuses it.

This is the same fail-closed class as AT-223 (self-facilitate must close, not
open): a settlement whose facilitator and merchant are the same address is
refused rather than attributed silently.

**Producer contract (normative).** A Tamga stitch that wants facilitator
attribution MUST record the submitter as `bind.submitter` (settlement tx
`from`), MUST NOT record the facilitator in `payer` or `payee`, and MUST NOT
key any facilitator-side index, registry, or aggregate on `payee`.

## 4. WHAT-NOW / WHAT-NEXT

**NOW:** (a) this design note; (b) the additive definition of the
`settlement_bind` field; (c) `../tools/settlement_bind_verify.py` with five core
+ two additive checks and three verdicts; (d) the AT-063 test with five negative controls
(swap-hash, swap-party, ref-mismatch, sig-invalid, chain-broken), plus the AT-226
three-case closure of the #2887 submitter/payee distinction (§3c).

**NEXT (pilot day):** (e) live stitching with a real x402 claim fixture;
(f) schema alignment on the tokenizen side (proposed in holistis-x402#3379);
(g) adding `tamga/native` and `erc8004/v1` to the `scheme` list (R9-2
additive promotion).

## 4b. Multi-payment-channel (B-direction, 2026-09-21)

`SUPPORTED_SCHEMES` additive promotion: **x402/v1** (EIP-191 secp256k1),
**tamga/native** (ed25519 operator, simnet), **erc8004/v1** (keccak-merkle).

**Cross-channel attack new surface:** if an attacker binds an x402 claim
under the tamga/native scheme, ed25519 verification produces a different
pubkey → party_mismatch-RED. This attack was impossible in a single-channel
world; dispatch introduced it, AT-064 locked it.

**Verification payload grows** (recurring §5): each channel means its own
signature contract. Added channels do not break the existing x402 path
(AT-064 check-5 backward compatible).

## 4c. AT-077 stub hidden-gap closure (2026-09-21)

AT-077 (the 99-Yieldix real Ed25519 stitch) found **two real gaps** in the
`tamga/native` branch of `_claim_signer` — both previously invisible
because AT-063/064/065/070/071/072 were all replacing `_claim_signer` with
a test-double (**SAME CLASS as AT-075's `ecrecover_to_pub` gap**: the real
path never ran, so the bug never fired):

1. **R-point = key assumption:** `VerifyKey(sig_hex[:64])` — the first 32
   bytes of an Ed25519 signature are the R-point, not the public key.
   Result: no real signature ever verified (wrong key not always on the
   Red edge, but None).
2. **Message = body-text assumption:** the signature was verified over the
   claim's JSON text, not over `digest_hex`. But the producer (Yieldix)
   signs with `separators=(",",":")`, the gate serializes with
   `(", ",": ")` — **same object, different bytes**. Since Ed25519 wants
   the raw message, this could never verify.

**Fix:** the input shape of the §3b table was pinned (what is signed +
identity resolution, per channel). Real Ed25519 verification now runs from
the stock path and AT-077 gives 6/6-GREEN without a test-double.

**Process lesson (same as AT-075):** per scheme, at least one test must run
**real library + real production path**; test-doubles must never hide the
real signature path. This rule is now carved into §3b.

## 4d. Two implementation channels under the same scheme, different preimage (AT-090 lesson)

Sester's X-PAYMENT dose is an EIP-191 **prefixed** personal signature
(`eth_account.encode_defunct("agent|nonce|amount|resource")` —
`schemes.py:31`); whereas the RFC-010 claim proof of the same `x402/v1`
scheme is cast over the **raw bytes** of the sha256 digest (z=raw-sha256,
unprefixed — §3b). So two different signatures can be produced over the
same digest, and each channel is only valid on its own preimage.

**Same class as AT-077's canonical-JSON separator distinction:** if the
channel contract is not pinned, GREEN can never be produced — this is why
every integration must first pin the producer's signature preimage in the
§3b table. One key, two channels makes it contract-independent; RFC-010
verifies only its own preimage.

## 5. Risks (honest)

- **Verification payload multiplies:** separate claim verification per
  scheme (§3 check-2). Today only x402/EIP-191; each new channel means new
  signature-verification code. This RFC does not hide that payload but
  keeps it in place with `scheme` dispatch.
- **evidenceHash field denial by the tokenizen:** we read evidenceHash from
  the claim; if the tokenizen deletes it and mutates the payload, the
  stitch breaks. Fix: evidenceHash MANDATORY in the claim (else RED — like
  the "swap" negative controls).
- **The third-option prohibition applies here too:** a channel not on the
  scheme list must NOT return RED (İNDETERMİNE) — otherwise we silently
  kill transactions. This is declared in §3.

## 6. Foreign-chain proof ( foreign_chain_proof) — additive ( 2026-09-23)

This section documents existing behavior (additive-only; the code already
implemented it, it was not written in the RFC — the §6 stitches of
AT-141..161 were standardized).

### 6.1 Schema

`charge_rec.foreign_chain_proof` (optional field):

```json
{"chain": "swarmax", "head_hex": "<64hex>", "entries": <int>,
 "evidence_link": "equals"|"derived"|"none", "verify_cmd": "<str>"}
```

- **chain**: whitelist — `swarmax | dumen | pqhaven | tamga | fleksa |
  sester | veridict | pacta | pactiva | yieldix | syntropion | tenderix |
  veridrome`. A chain not on the list → RED (not İNDETERMİNE for the
  unknown: because the claim of the proof's NAME is ROTTEN). Each chain
  must be presented under its own name (lesson of AT-107/134: previously
  they all went under the name "tamga").
- **head_hex**: 64 lowercase hex MANDATORY. Empty or different length → RED
  (an empty root is the sign of a fake chain).
- **entries**: int ≥ 1 MANDATORY (a zero-entry chain is not a proof).
- **verify_cmd**: this is an EXTERNAL-CONFIDENTIALITY field — it is
  **NOT executed**, only recorded for the audit trail (third-option
  prohibition: we do not re-verify the foreign chain ourselves, we accept
  its proof — but if it is rotten, RED). RECORD, DO NOT RUN (the AT-067
  confession).

### 6.2 Content link ( evidence_link, AT-079)

The old code only measured SHAPE — any 64-hex was valid (a fake head
passed GREEN; the remaining face of the §6 debt). The link forces a
CONTENT connection:

- **`equals`**: `head_hex == receipt_hash` (the proof is the SAME as the
  delivery digest).
- **`derived`**: `head_hex == sha256( bytes.fromhex( receipt_hash))` —
  note: the derivation ring must be REAL (lesson of AT-156: a keccak
  Merkle root CANNOT equal a sha256 derivation; two hash families →
  instead of a meaningless derivation, use equals or declare İNDETERMİNE).
- **`none` / absent**: the head is NOT bound to receiptHash (different
  chains may have different roots); but an empty head is still RED.

### 6.3 Gate behavior

- **NO proof → GREEN** (backward compatible; old stitches do not break).
  §6 is NOT MANDATORY — the primary proof of the settlement bind is the
  claim signature (§3 check-2); foreign-chain is additional verification.
- **proof PRESENT + invalid → RED** (rc8 `foreign_chain_broken`). No
  third-option-prohibition violation: absence is not İNDETERMİNE, it is
  PROVEN rottenness.

### 6.4 Mesh implementation summaries ( AT-141..161)

Each chain keeps its own proof model (heterogeneous federation; not a
homogeneous blockchain): Merkle (veridrome-RFC-6962, fleksa, dumen),
Ed25519 (swarmax, yieldix, tenderix), ECDSA-P256 (veridict-Rekor external
chain), Proof-of-Audit (pactiva), D5-ledger (tamga, sester, pacta). All
bind to the common verification over §6.

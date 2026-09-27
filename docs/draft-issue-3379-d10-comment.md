# TASLAK — issue #3379 ek yorum (GÖNDERİLMEDİ; lead doğrulayıp gönderir)

**Hedef:** https://github.com/x402-foundation/x402/issues/3379
**Bağlam:** önceki yorum (ID 5850361409) shipped settlement_anchor kodunu duyurdu;
bu yorum onun **spec clause** halini ve **replay talimatını** verir.
**Ses:** doteyeso-ops / holistis'in settlementRef/anchor sorusuna doğrudan cevap.

---

## The settlement anchor is now a spec clause, not just code

Following up on the shipped verifier check: the anchor is now written into the
protocol spec itself as **RFC-003 §10, D10 (settlement anchor)** — a v0.2
revision candidate, awaiting founder approval. The code led the paperwork; this
is the paperwork.

The clause, in short:

- A settlement document that pairs with a Tamga receipt carries
  `settlement_ref` = the receipt's `h` (`receiptHash`). The anchor is the
  **ledger hash, not a payment-side identifier** — the chain of custody runs
  settlement → `settlement_ref` → `h` → (`prev`, `jcs(record)`) →
  `stdout_sha256` → the delivered bytes. An id chosen by the payer says nothing
  about the work; the ledger hash is recomputable by anyone from the record
  alone.
- **Failing closed.** A settlement with no reference to a receipt is a RED, not
  a silent omission — and a reference to a *different* receipt is the same RED.
  Both are negative controls in the suite (`AT-007i` / `AT-007j`).

**Why the ledger hash and not a payment id:** `h` is node-certified — the node
identity is inside the hash input and the node signature signs the hash
(RFC-003 §8 D8). So the anchor carries the node operator's declaration, not a
bare agent claim. This deliberately mirrors the finding that motivated node
cosigning: an embedded chain with no node declaration was an agent claim on a
fresh node; a settlement with no anchored receipt is a payment claim on unbound
work. In both cases the answer is the same — a claim that names no accountable
counterparty is not a partial result, it is no result.

**Honest limit, stated plainly:** the anchor binds a settlement to a *receipt* —
what was delivered, and that a chained record exists for it. It does not claim
payment finality, execution quality, or buyer acceptance. Those stay separate
axes, and the public fixture's settlement side is explicitly `simulated`.

## Replay it yourself

This is a fixture, not a claim. It verifies with stdlib Python — no
`pip install` needed beyond the Python 3 you already have.

```bash
git clone https://github.com/goun7/tamga-protocol.git
cd tamga-protocol
python3 tools/verify_pairing_fixture.py docs/pairing
```

That prints `ok: true` with seven checks — labeling, membership, delivery
sha256, delivery keccak256, input commitment, delivery-hash chain, and the
settlement anchor itself.

The more interesting half is breaking it. Delete the anchor and watch the
verifier refuse:

```bash
cp -r docs/pairing /tmp/fx-copy
python3 - <<'PY'
import json
p = "/tmp/fx-copy/pairing-fixture.json"
fx = json.load(open(p))
del fx["x402_settlement"]["settlement_ref"]
json.dump(fx, open(p, "w"))
PY
python3 tools/verify_pairing_fixture.py /tmp/fx-copy
# -> {"ok": false, "where": "settlement_anchor",
#     "error": "missing settlement reference — ... fails closed: a settlement
#               must name the work it pays for"}
```

Eight tamper shapes behave the same way (flipped delivery byte, swapped
receiptHash, missing source label, swapped input, doctored record, stale
`charge.h`, re-committed input, and the two anchor cases above) — change
anything the fixture claims is bound, and the verifier names the broken check
instead of passing.

If you want a fixture whose receipt is *yours* — fresh seed, fresh timestamps,
your own receipt hash — `tools/make_pairing_fixture.py` regenerates one from a
real run (needs the wasmtime engine; costs nothing on-chain).

## Where this leaves the settlementRef question

To state our position plainly for the thread: we think the answer to "what ties
a settlement to the work it pays for" should be **the strongest evidence the
system already has** — in our case the ledger hash — and that a settlement
which cannot name that evidence should be refused outright rather than accepted
with a warning. We would rather lose a payment than pay for unbound work, and
the fail-closed verifier is that preference expressed as code. We're sharing
the spec clause and the replay path in case that position is useful to the
discussion, not because we think it is the only defensible one — the honest
limits above are the boundary of what we claim.

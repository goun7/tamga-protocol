# Pairing Fixture — x402 settlement ↔ Tamga receipt

This is a public, self-verifiable example of how an x402 settlement binds to a Tamga
work receipt. It was created for the discussion in
[x402 issue #3379](https://github.com/x402-foundation/x402/issues/3379) (request by
@safal207: a transparent sample showing exactly which fields come from where).

**No real payment happened.** The settlement side is explicitly `simulated`. The
Tamga side is a **real run** of the example agent (reproducible with one command),
and every field states its origin via the labeling discipline:

| label | meaning |
|---|---|
| `simulated` | x402-side placeholder; no chain, no money |
| `observed` | taken verbatim from a real Tamga run (reproducible in CI) |
| `derived` | computed from observed bytes (e.g. the Keccak-256 rendering) |

## Files

| file | content |
|---|---|
| [`pairing-fixture.json`](pairing/pairing-fixture.json) | the pairing document (labeled fields) |
| [`pairing/delivery.stdout`](pairing/delivery.stdout) | the exact bytes the run delivered (the "what was delivered") |
| [`pairing/input.json`](pairing/input.json) | the exact input bytes (D11 input commitment) |

## What the fixture proves

1. **Membership** — `receiptHash` is the `h` of a charge record; `h = sha256(prev + jcs(record))`
   recomputes from the shipped record alone. Full chain membership is `python3 tamga_runner.py
   ledger-verify <pkg>` (see AT-001 in `TESTS.md`).
2. **Delivery binding** — `sha256(delivery.stdout)` equals the charge record's
   `stdout_sha256`: the bytes you can hold in this directory are the bytes the receipt
   commits to. This is the "proof-of-done" axis: the work ran in the wasmtime box and
   produced exactly these bytes.
3. **Algorithm-labeled digests** — the same bytes are given under both SHA-256 (Tamga's
   ledger digest) and **Keccak-256** (legacy padding; what x402 durable-evidence
   `contentHash` uses). They are NOT the same algorithm and never compared loosely —
   the fixture carries both, labeled (`sha256` = observed, `keccak256` = derived).
4. **Input commitment** — `sha256(input.json)` equals the receipt's `input_sha256` (D11):
   the run's input is bound as well as its output.
5. **Settlement anchor** — `x402_settlement.settlement_ref` names the exact receipt the
   (simulated) settlement settles against, and it must equal `receiptHash` == `charge.h`.
   This is the [#3379 settlementRef/anchor question](https://github.com/x402-foundation/x402/issues/3379)
   (raised by @doteyeso-ops/@holistis): *what ties a settlement to the work it pays for.*
   The answer here is the ledger hash — and it is **failing closed**: a fixture whose
   settlement carries no reference to the receipt is a RED, not a silent omission
   (the check is item 7 of the verifier, see *Negative controls* below). The anchor is
   not a bare agent claim either: it is `h`, which is node-certified — `node_id` is
   inside the hash input and `node_sig` signs `h` (RFC-003 §8 D8, the F25 closure) —
   so the anchor carries the node operator's declaration.

## Negative controls (failing closed)

The verifier is not a positive-only check. `../tests/at007_pairing_fixture.sh` feeds it
deliberately broken fixtures and asserts each one yields `"ok": false`:

| control | tamper | expected RED |
|---|---|---|
| AT-007c | one flipped `delivery.stdout` byte | `delivery_bytes` (observed sha256 mismatch) |
| AT-007d | `receiptHash` swapped | `membership` (recomputed `h` != `receiptHash`) |
| AT-007e | a field's `source` label deleted | `labeling` (safal207 discipline) |
| AT-007f | `input.json` swapped | `input_commitment` |
| AT-007g | record doctored, `receiptHash` re-signed, stale `charge.h` | `membership` |
| AT-007h | input re-committed, stale `charge.input_sha256` | `input_commitment` |
| **AT-007i** | **`settlement_ref` removed** | **`settlement_anchor` — missing settlement reference** |
| **AT-007j** | **`settlement_ref` pointed at a different receipt** | **`settlement_anchor` — unanchored settlement** |

AT-007i is the answer to *“can a settlement float free of the work?”* — no. Without a
bound reference the verifier rejects the whole fixture, exactly as an import under
`--cosign-policy L1` rejects an unlisted node key (RED reason 14,
`node_id_untrusted@<seq>`): both are the same discipline at different layers — a claim
that names no accountable counterparty is not a partial result, it is no result.

## Verify it yourself

```bash
python3 tools/verify_pairing_fixture.py docs/pairing
# {"ok": true, "checks": ["labeling", "membership", "delivery_sha256",
#                         "delivery_keccak256", "input_sha256",
#                         "delivery_hash_chain", "settlement_anchor"]}
```

The verifier enforces the labeling discipline too: a value-field without a `source`
label is a RED, as is any tampered byte (tested by AT-007 in `../tests/run_all.sh`,
the suite's tail line reports the live count, CI-green on every push).

## Replay it yourself (for a reader of issue #3379)

This is a fixture, not a claim — the point is that you can hold it in your own
hands. Three things to try, in order. None of them needs `pip install` anything
beyond the Python 3 you already have: the verifier is stdlib-only (`hashlib`,
`json`) plus two small modules that ship in this repo (`keccak256`, `tamga_canon`).

```bash
git clone https://github.com/goun7/tamga-protocol.git
cd tamga-protocol
python3 tools/verify_pairing_fixture.py docs/pairing        # ~1 second
```

That prints `{"ok": true, ...}` with the seven check names — the committed bytes
verifying themselves. If you want to *break* it, which is the more interesting
half, delete the settlement anchor and watch the verifier refuse:

```bash
cp -r docs/pairing /tmp/fx-copy
python3 - <<'PY'
import json
p = "/tmp/fx-copy/pairing-fixture.json"
fx = json.load(open(p))
del fx["x402_settlement"]["settlement_ref"]          # un-anchor the settlement
json.dump(fx, open(p, "w"))
PY
python3 tools/verify_pairing_fixture.py /tmp/fx-copy   # -> "missing settlement reference"
```

The eight tamper shapes in the *Negative controls* table above all behave the
same way — pick any field the fixture claims is bound, change it, and the verifier
names the broken check instead of passing. Then, if you want a fixture whose
receipt is *yours* (fresh seed, fresh timestamps, your own receipt hash), see
*Regenerate* below — it needs the wasmtime engine and costs nothing.

## Honest limits (mirroring the issue discussion)

- Integrity + binding evidence only: this fixture says *what was delivered and that a
  receipt for it is chained*. It does not claim execution quality, payment finality,
  or buyer acceptance — those are separate axes (see RFC-003 §10, D10 candidate).
- The settlement side is simulated; wiring a real x402 payment is future integration
  work, not a schema claim.

## Regenerate

```bash
export TAMGA_KS_PASSPHRASE=simnet-2026
python3 tools/make_pairing_fixture.py /tmp/tamga-fixture docs/pairing
```

Each regeneration is a fresh run (fresh seed, fresh timestamps), so `receiptHash`
changes every time — the *pairing structure* is what is stable.

## Reproduce the charge hash yourself (added 2026-09-09)

The `tamga_observed.receiptHash` is not a number to trust — re-derive it:

**Canonicalization note (2026-09-17):** the fixture's pinned `receiptHash` was re-derived —
until 2026-09-17 our `jcs` was `json.dumps(sort_keys=True)` (Python-specific: `1.0` stayed
`"1.0"`, `2.93e-07` stayed `"2.93e-07"`, key order was code-point not UTF-16). It is now true
RFC 8785 (`tamga_canon`, byte-identical to a Node/ECMAScript reference — `../tools/jcs_parity.sh`,
control AT-036). The fixture's floats (`fee_sim`, `fee_birebir`, `cpu_saat`) serialize
differently, so the pinned hash moved (`6c0cab5f…` → `fe6f230c…`); the record itself is
unchanged. Old hash was Python-only-recomputable; the new one is recomputable by anyone in
any language — which is the entire point of a receipt.

```python
import json, hashlib, sys
sys.path.insert(0, ".")
from tamga_validator import jcs          # canonical JSON (RFC 8785)
fx = json.load(open("docs/pairing/pairing-fixture.json"))
rec = fx["tamga_observed"]["charge_record"]["value"]
body = {k: v for k, v in rec.items() if k not in ("h", "node_sig")}
h = hashlib.sha256(rec["prev"].encode() + jcs(body)).hexdigest()
assert h == fx["tamga_observed"]["receiptHash"]["value"]
print("receipt hash reproduces:", h[:24], "…")
```

Rule recap (RFC-003 D5): `h = sha256(prev || jcs(record-minus-{h, node_sig}))` —
`node_sig` signs the hash and stays outside it; the chain head recomputes the
same way over `ledger.jsonl`.

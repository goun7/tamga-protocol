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
   ledger-verify <pkg>` (see AT-001 in `docs/TESTS.md`).
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

## Verify it yourself

```bash
python3 tools/verify_pairing_fixture.py docs/pairing
# {"ok": true, "checks": ["labeling", "membership", "delivery_sha256",
#                         "delivery_keccak256", "input_sha256"]}
```

The verifier enforces the labeling discipline too: a value-field without a `source`
label is a RED, as is any tampered byte (tested by AT-007 in `tests/run_all.sh`,
20/20 controls, CI-green on every push).

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

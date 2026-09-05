# Release notes — v0.1.0-alpha

Release date: 2026-09-05 · Tag: `v0.1.0-alpha` · Branch: `main` (fresh public history)

## What is in this release

Tamga Protocol is a self-owning agent primitive: an agent holds an ed25519
identity derived from a user passphrase (the seed itself is never at rest),
accumulates memory and a hash-chained work ledger, and migrates between hosts as
a single encrypted snapshot. This alpha ships the v0.1 frozen contracts
(RFC-001 manifest schema, RFC-002 runner/snapshot transport) plus the working
runner, validator and acceptance suite.

## Highlights

- **Runner** (`tamga_runner.py`): keygen / grant / run (wasmtime v48.0.1, WASI 0.3
  components) / export / import / ledger-verify / memory / keygen-node, with usage
  text on `--help`. Every rejection carries a machine-readable `reason_code` (1-18).
- **Input binding (slice-11)**: `--input` files are fingerprinted into the receipt
  (`input_sha256`); same input + same binary → same output (determinism class A).
- **Node-cosign (AT-003)**: optional L1 policy where every ledger record is signed
  by a separate node key and the node_id is bound inside the record hash — closes
  the F25 forged-history finding; L0 stays the back-compat default.
- **Memory import (AT-005)**: `tools/memory_import.py` converts mem0 / Letta / Zep /
  JSONL exports into the ADD-only context graph; deterministic ids make re-import
  idempotent (0 added, N skipped).
- **Adversarial evidence**: embedded-chain attacks (Audit-7), node-cosign layer
  tests (Audit-8) and the runner-overhead benchmark run in CI, not just locally.
- **Docs**: public English surface with dated ecosystem scan (ERC-8004 draft status,
  x402 dashboard figures, memory-framework versions); frozen Turkish canonicals are
  translated in `docs/RFC-001-manifest.md` and `docs/RFC-002-runner.md`.

## Verification

- 18-control acceptance suite, CI-green on every push; slow suite (RUN_SLOW=1)
  adds the c30 cross-host control → 19/19.
- Negative families: AT-003 node-cosign 6/6, AT-001f snapshot attacks 4/4.
- Adversarial audits exit 0; cross-validation 34/34; markdown link integrity 0 broken.

## Honest limits (read before using)

- simnet/experimental: do not use with real value.
- A passphrase-knowledgeable adversary can mint internally consistent state
  (F25, documented in RFC-002 E-10/F25) — merkle and chain protect seed-less hosts.
- Absolute runner-overhead targets await a quiet-host measurement round; current
  numbers are loaded-host ratios.
- Frozen Turkish JSON field names (`cpu_saat`, `ram_gb_sn`, `fee_birebir`) change
  only through a versioned RFC.

## Known gaps / next

- reason 5/15/16 reserved, not emitted in v0.1 (RFC-planned layers).
- Node revocation list (OQ-3) is designed; the trust-file surface ships, the
  revocation UX is next.
- Pilot/partnership tracks are founder-gated and intentionally not started.

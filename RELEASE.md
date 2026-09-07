# Release notes — v0.2.0-rc.1

Release date: 2026-09-07 · Tag: `v0.2.0-rc.1` · Branch: `main`

## What is in this release

First release candidate of the v0.2 line: **declared egress** (RFC-007) — the
agent's network surface stops being implicit and becomes a signed, chained,
per-run-verified declaration. Three founder-approved slices landed as
implemented, plus the §5 draft schema.

## Highlights (RFC-007)

- **R1 — `runtime.net` in the manifest** (5819be0): the net declaration moves
  from a side-file (`net.json`) into the signed manifest under `runtime.net`.
  `migrate-net` performs the one-way, author-seed-gated migration; the bridge
  is deleted and the identity is preserved. The migration writes an on-chain
  evidence record (`op=migrate-net`, old/new declaration hashes) so plain CLI
  `validate` resolves pre-migration bindings with no flags (b9aa59f).
- **R2 — labeled delivery digest** (6782614): `run --delivery-alg sha256|keccak256`
  adds an OPTIONAL `delivery_hash {"alg","hex"}` to the charge — the digest of
  the exact stdout bytes delivered to the counterparty, carried under its own
  name (D10, safal207 binding-discipline). Pure-python keccak (`tools/keccak256.py`),
  known-vector self-test.
- **R3 — D12 conditional unity** (19028ca): the receipt trio
  `net_decl_sha256` / `net_events_sha256` / `net_mb` enters the charge together
  or not at all; `net_mb` is normative to 6 decimal places; the validator binds
  the latest charge to whichever declaration source is active — swap, deletion
  and both-sources states all RED (`net_binding_mismatch` / `net_binding_missing`
  / `net_decl_ambiguous`).
- **§5 — v0.2 draft schema** (b708622): `specs/manifest-0.2.0-draft.schema.json`
  is ADDITIVE — every 0.1.0 manifest stays valid under it. The frozen 0.1.0
  schema and the validator's 0.1.0 const are untouched; the release flip is a
  separate founder gate.

## Verification

- 24-control acceptance suite, CI-green (smoke bench; claim evidence stays
  local quiet-host). Schema cross-validation 51/51 (incl. the 9-probe draft
  additive contract). Docs link integrity 0 broken. Pairing fixture 6/6 checks.
- Bug sweep (founder-requested, 2026-09-07): one real defect found and fixed —
  `migrate-net` on packages with pre-migration net runs (D12a
  content-equivalence); AT-011 extended to 6 controls (f: migration of a
  ran-under-net.json package). No other open defect found.

## Honest limits (read before using)

- Everything in v0.1.0-alpha's limits still applies (simnet/experimental;
  passphrase-knowledgeable adversary F25).
- `spec_version` remains `0.1.0` in validator-accepted manifests; the draft
  schema documents the v0.2 shape but the const flip is not part of rc.1.
- Declared egress is enforced by the runner at the WASI boundary; it is NOT a
  sandbox guarantee against a malicious host (RFC-005A is the vektor line).
- The c30 slow control still requires RUN_SLOW=1 and is not part of CI.

## Known gaps / next

- RFC-007 R4 (signed refusal/RED evidence artifact) is an ADOPTED candidate
  note, parked pending the pilot decision.
- Reason codes 5/15/16 remain reserved.
- Pilot/partnership track open (docs/DESIGN-PARTNERS.md); the x402 #3379
  pairing offer (consented 113-byte delivery) is with the counterparties.
- Post-rc.1 hardening (2026-09-07/08, all CI-proven): AT-012 dx402 pairing
  family, Audit-11 ledger-bomb defense, AT-013 pip sanity (engine-free verify
  path), AT-014 standalone mini-verifier (B2), AT-015 evidence bundle (B4),
  Audit-15 state hardening, Audit-16 node-revocation closure — suite now
  31/31 (+32 slow); RFC-008 external-receipt binding drafted (pilot-pending).

---

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
- Negative families: AT-003 node-cosign 6/6, AT-001f snapshot attacks 3 expected-RED + 1 precondition control.
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
- Node revocation: the `--node-revoked <file>` flag ships (JSON array of node_ids;
  their signatures are rejected under L1 even if still trusted); management UX is next.
- Pilot/partnership track is now open (docs/DESIGN-PARTNERS.md): free migration
  for the first three partners, founder-approved 2026-09-05. Personal outreach
  is the founder's channel.

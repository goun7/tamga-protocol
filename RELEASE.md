# Release notes — v0.2.1

Release date: 2026-09-11 · Tag: `v0.2.1` · Branch: `main`

## What is in this release

**v0.2.1 — license-metadata fix + quickstart wizard release.** Two changes, one
already shipped in code and one that is metadata-only:

- **License metadata corrected: MIT → Apache-2.0.** The repository `LICENSE` file
  has been Apache-2.0 since the first public release; `pyproject.toml` carried a
  stale `MIT` string, and PyPI 0.2.0 inherited it. The mismatch was caught by
  smartflowproai-lang in the x402 conformance-corpus thread
  ([#3396, 2026-09-11](https://github.com/x402-foundation/x402/issues/3396#issuecomment-5635445291))
  — fixed forward-only in 0.2.1; the 0.2.0 artifacts keep their historical
  metadata (we don't rewrite history).
- **Quickstart wizard on PyPI** (code shipped in 0.2.0, surfaced here as the
  user-facing path): `pip install tamga-protocol && tamga quickstart <dir>` —
  one command produces the first package end-to-end: embedded tc-a1 template
  agent → fresh ed25519 key (D3 seed) → sign → validate → grant → FIRST RUN →
  ledger-verify. Verified end-to-end from a clean venv against live PyPI
  (5 steps green, `spec_version` 0.2.0, engine auto-fetched).

Verification: fast suite 42/42, slow suite 45/45 (RUN_SLOW), CI green; live
PyPI E2E re-run on the published 0.2.1 wheel before tagging.

---

# Release notes — v0.2.0 (FINAL)

Release date: 2026-09-11 · Tag: `v0.2.0` · Branch: `main`

## What is in this release

**v0.2.0 FINAL — the founder-approved `spec_version` const flip.** The validator now
pins `spec_version: "0.2.0"` (0.1.0 manifests become legacy → `RED unsupported_spec_version`).
The flip was executed per the pre-written `FAZ-KAPISI-FLIP-RUNBOOK`: with external pilot
counterparties silent, the runbook's own fallback clause ("pilot gelmezse kurucu kararı
pilot'suz-flip masaya") was invoked with fresh-green gates: AT-020 self-pilot three-leg
proof, crossval 60/60, suite 41 fast + 44 slow, CI green.

### Flip mechanics (all reversible via git; none normative beyond the const)

- `tamga_validator.py` const `0.1.0` → `0.2.0` (single line, dated comment)
- All 20 repo fixtures migrated 0.1.0 → 0.2.0 and re-signed with the operator key
  (`tools/migrate_v020_flip.py`); adversarial vectors keep their DESIGNED RED reasons
  (tc-a2 forged signature → `code_hash_mismatch`, tc-a4 `root` capability, tc-a3
  `admin_backdoor`, tc-a5 forged signature → `signature_invalid`)
- New vector **tc-a7**: the 0.1.0 downgrade probe (post-flip upper-bound RED)
- Schema promotion: `specs/manifest-0.2.0.schema.json` (const `"0.2.0"`, additive
  runtime.net over v0.1); `manifest-0.2.0-draft.schema.json` retired to history;
  0.3.0-draft enum re-based to `["0.2.0","0.3.0"]`
- Cross-validation re-based on the promoted schema: **60/60 AGREE** (m02 mutation
  reversed to a downgrade probe; tc-a6 exception closed — upper bound now open)
- Suite: fast 41/41 (AT-001a now expects 2 ACCEPT + 5 RED) · slow 44/44
  (RUN_SLOW: c30 + AT-019 + AT-020)

---

# Release notes — v0.2.0-rc.2

Release date: 2026-09-11 · Tag: `v0.2.0-rc.2` · Branch: `main`

## What is in this release

Release candidate 2 of the v0.2 line. rc.1 (published to PyPI 2026-09-10) is now
superseded by a hardening + verification-surface release. **No normative change:
`spec_version` stays `0.1.0` in accepted manifests** — the v0.2.0 const flip remains
a separate founder gate, as with rc.1.

## Highlights

- **M6 — manifest v0.3.0 DRAFT schema** (`specs/manifest-0.3.0-draft.schema.json`):
  the RFC-008 external-receipt slice (`external_receipt` block: rail / receipt_id /
  content_hash{alg,hex} / receipt_uri / retention_note) as a written, additive
  contract. AT-018 proves additivity — every 0.1.0/0.2.0 manifest stays valid, and
  adversarial vectors (tc-a3 `admin_backdoor`, tc-a4 bogus capability) stay RED.
  Cross-validation matrix extended to the v0.3.0-draft transition rows (59/59 AGREE).
- **Audit-17 snapshot fuzz** (6 tamper classes fail-closed + ciphertext-region
  privacy proof) · **Audit-18 unicode hash separation** (NFC/NFD / homoglyph / null
  all separate identity, JCS-subset divergence documented) · **Audit-19 timing**
  (unlock-RED-as-success band 0.92; scrypt full path).
- **AT-015 version-pinned export vectors** (mem0 2.0.20 / letta 0.16.8 / zep 3.28.0
  shape fixtures) · **AT-016 explain CLI** (full bilingual TR/EN charge rendering,
  tamper-detected chain-integrity line, receipt canonical check) · **AT-017 anchor
  design vector** (F1 external-anchor shape, D5-math frozen, const deferred).
- **AT-019 (slow) — restriction-hardening proof:** the published wheel installs
  `--no-deps` and `tamga_verify_mini` performs REAL chain verification in a
  nacl-blocked environment — a counterparty on a minimal host (no pynacl, no engine)
  can still verify receipts from `pip install tamga-protocol`.
- **Docs:** QUICKSTART library-usage section (four engine-free modules import from
  the wheel, zero deps) + air-gapped engine install note (two accepted pre-place
  locations). REPRODUCE §0 — verify a chain without cloning.
- **keccak256** (`tools/keccak256.py`) — dependency-free reference implementation,
  3 known-answer self-tests, cross-checked against OpenZeppelin in the epoch-10
  dual-impl proof; now documented for copy-in reuse.

## Verification

- Acceptance suite **40 fast controls + 2 slow = 42/42 PASS** (CI-green on every push).
- Schema cross-validation **59/59 AGREE** (frozen 0.1.0 + 0.2.0-draft + 0.3.0-draft
  transition matrix).
- Links 56/0 · suite badge tests-40/40 · HEAD `40cbeb0`.
- External-anchor evidence (epoch-10, fact 0x0236…36e2) remains VERIFIED against the
  OpenZeppelin StandardMerkleTree root, dual keccak impl (epoch manifest frozen in
  `.evidence/APODIX-EPOCH-10/2026-09-10/`).

## Honest limits (unchanged from rc.1, plus)

- `spec_version` still `0.1.0` in accepted manifests — the v0.2.0 const flip is
  NOT part of this release (founder-normative gate).
- `external_receipt` is a **DRAFT** manifest field: three open questions (P8-1
  plaintext↔delivered hash roots, P8-2 retention limits, P8-3 receipt_uri auth)
  are pilot-pending — see RFC-008 §§3,6,8 and x402 #3447.
- The epoch-10 anchor is EXTERNAL evidence (a third registry's seal), not a Tamga
  chain property; F1 (TAMGA_EXTERNAL_ANCHOR_V1 ledger op) remains design-only,
  const deferred.

## Known gaps / next

- RFC-007 R4 (signed refusal artifact) still parked pending founder decision.
- v0.2.0-final const flip and JCS strict-mode remain founder-normative gates.
- A self-driven end-to-end consented-delivery proof (seller/runner/buyer all on our
  own machinery) is the next internal milestone — see private self-pilot plan.
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

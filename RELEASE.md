# Release notes — v0.2.13

Release date: 2026-10-19 · Tag: v0.2.13 · Branch: `main`

**v0.2.13 — the compute-anchor + independent-verification release.** 320 commits
since v0.2.12 (95 feat / 47 test / 49 docs), suite **242 PASS / 1 SKIP / 0 FAIL**
(`tests/run_all.sh`, measured 2026-10-19, two consecutive runs identical).
The two headline features both close a "producer-verified-by-producer" gap:

1. **`compute-anchor` (RFC-011, K1)** — a work-proof receipt mined by an
   *external* producer (Dümen's OV-MatMul KOK miner) can now be bound into the
   Tamga ledger as a first-class record. `tools/compute_anchor.py` verifies the
   receipt with an **independent** copy of the verifier before writing
   (RED receipts cannot enter — no green-dressing), and the record carries
   `presentation_only: true` because work-done ≠ paid. The op is spec'd in
   LEDGER-SPEC §9 (C-1..C-7) and is proven in the production corpus
   (AT-057 — the third-option ban: an emitter with no production evidence
   fails the gate, it does not silently pass).
2. **Tamga MCP server (independent verification surface)** — stdio JSON-RPC,
   5 tools (anchor / verify / history …), 8 tests. A third party can verify a
   receipt without installing Tamga.

## What is in this release

- **RFC-010 closures** — submitter/payee separation (x402 #2887, AT-226),
  x402-response-provenance stitching (AT-215), and the §6 standardization
  ladder AT-145..AT-167: zkTLS gap, consensus scan, Sybil scan, Rekor external
  anchor, crypto-gateway audit — every "İNDETERMİNE" result is reported as
  rc2 (never silently green).
- **Operational surface** — `ledger-verify-batch` (AT-208, N packages in one
  call), registry backup/restore (AT-209, survives registry loss),
  relayer-balance watcher (Base mainnet ETH-balance alert), relayer daemon
  chaos-stitch fail-closed in every scenario (AT-225, RC_NETWORK-27:
  network interruption no longer kills the loop).
- **BrandStrike TSA code-bond (AT-229)** — RFC 3161 timestamp authority
  stitched to the Tamga hash-chain on the time axis.
- **False-proof gates hardened (fail-closed)** — DISP-1/SOV-1/EMIT-1/NRC-1:
  a *vacuous* corpus (no production evidence at all) can no longer score
  "all emitters proven". The emitter-verify machine now REDs an op that has a
  code emitter but no production-corpus evidence — this is exactly what
  caught the `compute-anchor` gap at release-prep time and forced the corpus
  + spec fix (G26) rather than letting it ship.
- **Portability + CI** — ecrecover no longer depends on user-site
  `eth_utils` (HOME-change breakage); cross-project/optional-dep controls SKIP
  honestly in CI (#338); AT-225 guarded with a mesh precondition (#339).

## Compatibility

No published fixture, receipt, or finding hash changes. `spec_version` stays
`0.2.0`. The new `compute-anchor` op is additive (append-only ledger taxonomy,
LEDGER-SPEC §9). The relayer's network-interrupt fix changes only the daemon's
error path, not the wire format.

## Verification

- `bash tests/run_all.sh` → **242 PASS, 1 SKIP, 0 FAIL** (2026-10-19, runs at
  20:13 and 20:21 — identical).
- `python3 tools/emitter_verify.py` → 6 ops, 0 problems, production corpus
  `{anchor, charge, compute-anchor, grant, migrate-net}`.
- AT-047 5/5, AT-049 6/6, AT-057 4/4 (the three gates that caught the
  compute-anchor gap).
- Wheel build dry-run clean (`python -m build`, no engine, per AT-019).

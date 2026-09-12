# Changelog

All notable changes to the Tamga Protocol are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning: [SemVer](https://semver.org/spec/v2.0.0.html) — pre-1.0, minor = feature, patch = fix.

## [Unreleased]

Nothing unreleased; next planned: see the roadmap gates in README.

## [0.2.4] — 2026-09-13

### Fixed
- **`tamga_pugio_ingest` ships in the wheel** — 0.2.3 shipped the module in the repo
  but left it out of `py-modules`, so a PyPI user could not import the AT-025 surface
  (install-break). Found by the new AT-026 while writing it; fixed before release.

### Added
- **AT-026 — wheel tam-modül** (slow control 50): packaging-completeness contract —
  repo-root ↔ `py-modules` ↔ wheel contents three-way equality, clean-dist build, and a
  full-install import gate for every module. Negative-proof verified: re-simulating the
  0.2.3 omission REDs the control.

## [0.2.3] — 2026-09-12

### Added
- **`tamga project-head <pkg>` (AT-023)** — chain-head → batch-leaf projection on the
  user surface: replays a REAL ledger with the canonical D5 (byte-identical to
  `tamga_runner._verify_chain`: prev-in-record, node_sig outside the hash, 1-based seq,
  `"0"*64` sentinel) and encodes the tip with the RFC-009 batch-leaf scheme
  (`keccak256(keccak256(bytes32(digest)))`) into a `TAMGA_PROJECT_HEAD_V1` JSON; the
  presentation-only boundary is inside the output itself; broken chain → RED
  (reason-14 family). Engine-free, stdlib-only.
- **`tamga_pugio_receiver.py` (AT-024)** — the inbound half of the anchor surface
  (RFC-009 receiver-side): verifies `external_anchor` JSONL lines from the PUGIO bridge
  with pure sha256 (`anchor_id = SHA256(head|merkle_root|event_count)[:32]`,
  bridge_version 1); one red line fails the whole file (fail-loud); unknown
  bridge_version REDs (version gate closed). Zero dependencies.
- RFC-009 §4: receiver-side clause — projection carries the tip OUT, the receiver
  verifies anchors coming IN (complementary halves).
- TESTS.md: AT-023 + AT-024 family rows; Vauban JCS cross-proof row (5/5 byte-exact,
  pin frozen); upstream-contribution row (Vauban PR #2).

### Changed
- Acceptance suite: 43 → 45 fast controls (48 with `RUN_SLOW=1`) — AT-023 (control 47)
  and AT-024 (control 48) wired in; counts synced across TESTS/README{,.tr}/REPRODUCE{,.tr}.
- Audit-19 timing band 0.7–1.4 → 0.6–1.6 (founder-approved): the claim is same-work
  measurement, not absolute ms; under full-suite load ±20% drift is normal (measurement
  evidence stays in the log).
- ARCHITECTURE.md: four Mermaid diagrams (runtime model, work receipts, migration,
  external anchor) — text unchanged, diagrams restate what the sections prove.
- WHY-HASHCHAIN.md: third axis — the chain narrates daily, the batch compresses
  membership to one root per epoch; we project the tip, never convert the ledger.
- DEMO-SCRIPT.md: step 8 (live composition vector run) + narration frame 6.
- USAGE block, AGENT-GUIDE{,.tr}, README{,.tr}: `project-head` command documented.

### Evidence
- `.evidence/APODIX-EPOCH-10/2026-09-10/` committed: the frozen epoch-10 anchor set the
  AT-022 cross-check folds over — evidence travels with the claim.
- `.evidence/VAUBAN-JCS-CONFORMANCE/2026-09-12/`: RFC-8785 cross-proof pin.

## [0.2.2] — 2026-09-11

### Added
- RFC-009 DRAFT (external chain anchor) public surface: `TAMGA_EXTERNAL_ANCHOR_V1`
  record shape (D5-frozen math), mini-verifier presentation-only contract, two-field
  claim rule R9-4, epoch-10 evidence links; op/const stay pilot-gated.
- RFC-007 public record of the implemented v0.2 schema revision (R1 runtime.net
  migration, R2 labeled delivery_hash, R3 D12 conditional unity); R4 signed-DENY stays
  pilot-gated.
- RFC-005/RFC-006 public records of the net stack (declared-egress proxy, agent-side
  net shim D13).
- NODE-DISCOVERY.md Phase-3 design note (ERC-8004 alignment; trigger-gated, no code).
- INDEX.md reading-order paths; AGENT-GUIDE.tr.md Turkish developer surface.
- REPRODUCE §0 (wheel path, live-verified from PyPI); AT-020 self-pilot evidence.

## [0.2.1] — 2026-09-10

### Added
- AT-021 quickstart wizard (first-package one-command flow).
- keccak256 delivery-alg path (RFC-007 R2); AT-010 labeled delivery-hash controls.
- AT-009 manifest-net (migrate-net one-way, D12a jcs-canonical binding).

## [0.2.0] — 2026-09-08

### Changed
- **spec_version flip** (founder-approved): manifest schema `0.1` → `0.2`;
  v0.1 manifests migrate one-way; reason-code taxonomy frozen (1–18).
- Default-deny WASI 0.3 component runtime; declared-egress net proxy (single edge).

### Added
- Charge-record embedding (metering in the ledger); D12 net-binding.
- Memory adapters: mem0 2.0.20 / letta 0.16.8 / zep 3.28.0 (version-pinned, AT-015).

## [0.1.0-alpha] — 2026-09-05

First public shape: simnet genesis — primitives (keygen/manifest/snapshot/ledger),
10 audit rounds, acceptance suite skeleton.

[Unreleased]: https://github.com/goun7/tamga-protocol/compare/v0.2.4...HEAD
[0.2.4]: https://github.com/goun7/tamga-protocol/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/goun7/tamga-protocol/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/goun7/tamga-protocol/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/goun7/tamga-protocol/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/goun7/tamga-protocol/compare/v0.1.0-alpha...v0.2.0

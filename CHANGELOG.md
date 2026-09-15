# Changelog

All notable changes to the Tamga Protocol are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning: [SemVer](https://semver.org/spec/v2.0.0.html) — pre-1.0, minor = feature, patch = fix.

## [Unreleased]

### Added
- `tamga_attest_verify` / `tamga attest-verify` — FOREIGN delivery-attestation verifier, stdlib-only:
  pure-Python secp256k1 ecrecover + EIP-191 + deep-sorted canonical JSON, registry-dispatch
  (CAPACITY_ATTEST_V1). Reproduces the issuer's own ethers verdict 7/7 on vendored fixture vectors
  incl. both negative verdicts; independently GREENs their real production claim (nested-object
  preimage). Unknown tag → İNDETERMİNE (RFC-009 pattern); AT-030 kontrol-54. Suite 50/54.
- Drift findings folded in the same sweep (sweep-method lesson recorded): INDEX.md had been stuck
  at 48/52 through two sweeps; README:148 / REPRODUCE:54 / AGENT-GUIDE totals at stale 49/52/53.
  Pattern-based inventory (regex over ALL stale pairs) replaced string-pair sweeps for counts.
### Added
- tamga_liveness: machine-readable `evaluated` flag (false = the probe never got to look;
  true-with-İNDETERMİNE = it looked and could not settle). x402 #2887's fifth-day
  NOT_EVALUATED debate (stillmarcus24, 5684885350) met our own doctrine halfway — three
  verdicts stay, the distinction stops living only in free-text reasons; AT-028 pins both
  sides (control now 6 lines).
- Docs parity: AGENT-GUIDE §10 EN+TR list liveness-probe/epoch-verify among engine-free
  surfaces; REPRODUCE verification line moved to 0.2.9-ritual-verified (10/10 incl. console
  dead-port probe).

## [0.2.9] — 2026-09-15

Fourth same-day release — every one traceable to a found class, listed above.

### Added
- tools/fresh_audit.sh + .github/workflows/fresh-audit.yml — the stranger-pass RITUAL as a
  tool: clean venv from live PyPI → doctor → E-14 zero-arg matrix → selftest → E-15 live
  wrong-chain probe → engine-cached quickstart E2E (never forces the 67MB download; skips
  LOUDLY). Three-verdict badge mapping (rc2 İNDETERMİNE = warning, not red). First run
  2026-09-15: 9/9 on 0.2.8 — and it caught two of ITS OWN bugs on pass one, which is the
  point. Monthly cron (day 20) + workflow_dispatch, independent of the suite badge.
- AGENT-GUIDE §14 (EN) / §12 (TR) — re-execution class declaration: receipts are
  pinned-class (profile recorded in-receipt; moved stack = İNDETERMİNE, never lucky green),
  data layer is order-independent by canonical definition (byte-identity referee-graded,
  AT-029). Fulfills the in-toto PR-592 doc commitment (issuecomment-5679421331).

Nothing unreleased; next planned: see the roadmap gates in README.

### Changed
- liveness probe promoted from repo-script to WHEEL SURFACE: `tamga_liveness` module, console
  command `tamga liveness-probe` (defaults to live Sepolia; three verdicts; server timestamps
  still never read). tools/liveness_probe.py removed — single owner, no shim (AT-028 now
  exercises `python3 -m tamga_liveness`; fresh-audit gained a console dead-port check).
- doctor now import-checks the liveness module (visible in `tamga doctor` output).

### Removed
- tools/social_preview.py (retired duplicate card-generator; anti-entropy approval 2026-09-15 —
  sole owner is tools/gen_social_preview.py, reads live counts from TESTS.md/pyproject).

## [0.2.8] — 2026-09-15

Third same-day release — each one a found-and-fixed class, none a padding.

### Added
- E-15 — chain-binding preflight on the `epoch-verify` anchor leg (`eth_chainId` before the
  `epoch(uint64)` call; `--expect-chainid`, default Sepolia, `0` = skip with a printed honesty
  note; wrong-chain mock + skip-note pinned as AT-027 cases 8/9, RFC-009 §3). Born from the
  x402 #2887 testable-binding convergence (issuecomment-5680705648): our own failure mode
  observed live on 2026-09-15 — a mainnet RPC answered the Sepolia contract with `0x`
  (İNDETERMİNE by luck); luck is now policy.
- tools/liveness_probe.py — single-command liveness probe (block-NUMBER span, server clock
  never read) + AT-028 offline five-case decision matrix (kontrol-53). Suite 48→49 fast,
  52→53 slow — 49/49 and 53/53 re-proved 2026-09-15.

Nothing unreleased; next planned: see the roadmap gates in README.

## [0.2.7] — 2026-09-15

### Added
- AT-029 — CR v0.1 canonicalisation cross-proof (in-toto PR-592 exchange, `ea54de7`):
  Tamga's `jcs()` — the epoch-anchor digest function itself — reproduces Anomly's
  published conformance vectors (8/8), graded by their neutral referee vendored
  byte-identical with sha256 pins re-verified inside the control + digest-tamper
  negative. Scope declared honestly: canonicalisation layer only; Tamga is not a CR
  certifier. Suite baseline 47→48 fast, 51→52 slow; tools/cr_crossproof.py +
  tests/vendor-cr/ (Apache-2.0, VENDOR-NOTE provenance).
- E-14 — new RED code **19 `pkg_dizin_degil`** (RFC-002 §9): a package path that is
  not a directory is RED, never a vacuously-valid "empty chain" — the epoch-verify
  INDETERMINE rule applied to our own chain surface. Legal pre-genesis semantics kept
  for existing chain-less directories.

### Fixed
- E-14 crash-family closure (fresh-user matrix on the live 0.2.6 wheel): `grant`, `run`,
  `export`, `memory`, `keygen-node` on zero args printed IndexError tracebacks; `ledger`
  and `ledger-verify` returned VACUOUS `ok=true` (cwd default / nonexistent path). One
  shared `usage_guard` choke point (console + repo-script dispatch; runs BEFORE the
  engine resolver — a usage error never triggers the one-time wasmtime download); bad
  invocations are message-RED rc1 (AT-016 rule extended to the whole CLI). Negative
  family pinned in AT-021 (aggregated; baseline unchanged 48/52); USAGE reason-code
  range now 1–19; AGENT-GUIDE EN/TR wording tightened.


## [0.2.6] — 2026-09-15

Patch on top of 0.2.5, same day — found by using the 0.2.5 wheel as a stranger.

### Fixed
- `tamga explain` crash-class hardening: a directory, missing file, malformed JSON, JSON
  scalar/list root, or out-of-range/malformed `--charge` seq now print an `explain: ` message
  and exit 1 — previously an uncaught Python traceback (AT-025 precedent applied; the
  fresh-user audit's `explain <dir> --charge` misuse exposed it live).

### Tests
- AT-016 carries the 7-case negatives-family as one aggregate control (canonical 47 count
  untouched); the suite total was re-proved 47/47.

## [0.2.5] — 2026-09-15

Wheel = HEAD. No wire contract, no ledger format, no spec_version change.

### Added
- **`tamga epoch-verify` now ships in the wheel** (it existed in 0.2.4's repo and docs but
  not in the installed distribution — found by installing 0.2.4 from PyPI into a bare venv
  and running it as a stranger would; the public surface we demo in x402 #3389 finally works
  for pip users).

### Fixed
- `tamga` help listed 7 of 15 shipped commands and an outdated version line; now the full
  inventory split engine-free vs engine (users can see what runs before any download).
- Quickstart wizard `next_steps` printed `python3 tamga_runner.py …`, which is dead advice
  for pip users (no such file in their cwd); now `tamga …` with the repo-clone form noted.
- README (EN + TR) and QUICKSTART document `epoch-verify` on the command surfaces.
- `İNDETERMİNE` spelling canon restored (self-introduced drift caught by the audit's own grep).

### Infra
- `tests/run_all.sh` carries a flock concurrency guard — parallel suite runs share sandbox
  dirs and produced 4 false FAILs on 2026-09-15; the refused instance now exits 1 with the
  reason. Negative-live-verified.
- docs/TESTS.md gained the AT-016/017/018 rows (controls ran all along; the table drifted).

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

### Outside-world
- **Epoch-13 seal-flip replay: GREEN** (2026-09-13) — the fact `0x0236…36e2` we had honestly
  reported *indeterminate* on 09-09 ("epoch not sealed yet") sealed into Apodix epoch 13
  (Sepolia block 11693440, root `0xaaf21f36…c458e`). Replayed with our own stack (pure-python
  `tools/keccak256.py`, own RPC choice): leaf recompute → root match; `epoch(13).factsRoot`
  on-chain match; factsCount 60 == leaf_count. Public promise kept in x402
  [#3389 (issuecomment-5653083752)](https://github.com/x402-foundation/x402/issues/3389#issuecomment-5653083752).
  Guide: `docs/VERIFY-EPOCH-ANCHOR.md`.

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
- Acceptance suite: 43 → 45 fast controls (48 with `RUN_SLOW=1`) at the TAG moment —
  AT-023 (control 47) and AT-024 (control 48) wired in; counts synced across
  TESTS/README{,.tr}/REPRODUCE{,.tr}. Later the SAME release day, AT-025
  (`tamga_pugio_ingest`, 1681fd8) raised it to **46 fast / 49 slow before the PyPI
  wheel was rebuilt** — RELEASE.md's 46/49 is the day-end truth; this entry records
  the tag-moment truth. (Both are honest; the two numbers froze in place when the
  0.2.3 wheel shipped with ingest missing from py-modules — the 0.2.4 story.)
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

## [0.2.0] — 2026-09-08 (spec flip) / tagged + released 2026-09-11

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

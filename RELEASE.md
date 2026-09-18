# Release notes — v0.2.11

Release date: 2026-09-17 · Tag: v0.2.11 · Branch: `main`

**v0.2.11 — the canonicalization-fix release (release follows a finding).** Until today our
`jcs` was `json.dumps(sort_keys=True)` — Python-specific, not RFC 8785: no ECMAScript number
serialization (`1.0`→`"1.0"` not `"1"`; `2.93e-07`→`"2.93e-07"` not `"2.93e-7"`) and code-point
not UTF-16 member ordering. A receipt digest was recomputable only by Python. Found by a
stranger auditing the sister project (stillmarcus24, Dümen issue #4), not by us. Fixed:
single-center `tamga_canon.py`, 13/13 byte-identical to a Node/ECMAScript reference, new
control AT-036. Published findings stand: EBL 34/34, AT-029 8/8, AT-030 7/7+8/8 — all
re-measured after the fix, byte-identical. The pairing fixture's pinned hash migrated
(`6c0cab5f…`→`fe6f230c…`); the record itself is unchanged.

## What is in this release

1. **`tamga_canon.py`** — RFC 8785 canonical serialization as a single center: ECMAScript
   number-to-string + UTF-16 code-unit member ordering + RFC-8785 escaping. Rewired into all
   9 call sites (validator, runner, mini-verifier kept as a deliberately-duplicated standalone
   audit artifact with machine-checked parity, bundle, attest-verify, pairing tools, audits,
   verify-lite).
2. **AT-036 (kontrol-58)** — canonicalization-parity: 9 RFC-8785 vectors + 3-implementation
   parity + Node cross-language oracle, 13/13 byte-identical. Node absent → İNDETERMİNE (rc2).
3. **Suite 52→53 fast, 57→58 slow** — both green on HEAD.
4. **Documentation:** every "RFC 8785" claim verified and corrected (RELATED-WORK EN+TR,
   PAIRING-FIXTURE "subset"→full + migration note, CHANGELOG). REPRODUCE re-verified.

## Post-release fix (same day, 2026-09-17) — Audit-7 A1a/A2 UNEXPECTED diagnosed

Two audit-7 outcomes reported `UNEXPECTED` at release time; the root cause is now found and
fixed. Both were **test-harness bugs, not protocol bugs** — the chain and the import gate were
correct all along:

- **A1a/A2 silently passing** — the audit's `grant` call passed a *file path* to `--node-key`,
  which expects 64-hex; the grant failed (`node_key_invalid`), so the baseline chain was empty
  and nothing could mismatch. Fixed to pass the hex value; A1a and A2 now report the expected RED.
- **A1b (F25) not closing** — two harness bugs hid the closure: `craft()` serialized the forged
  body with `json.dumps` instead of `jcs` (a mutated float `100.0` round-tripped as `100`,
  silently breaking the chain — a test artifact, not a security control), and the forged record
  set `node_id` *after* computing `h` (the field is inside the hash input). Both fixed.
- **F25 status:** CLOSED under `import --cosign-policy L1 --node-trust` — a strong adversary
  recomputing the whole chain with a fresh, unlisted node key now gets RED reason 14,
  `node_id_untrusted@1`, even with a valid signature. The policy stays opt-in (L0 default,
  back-compat preserved); the residual limit — a seed-owner who is *also* the node-owner —
  remains documented and accepted (RFC-003 §4.4/§8).
- **Suite after the fix: 58/58** (`.evidence/REGRESYON/2026-09-17/run_all-204553.log`).
  No published receipt or finding changed: the fixes are confined to the audit harness and
  the import cosign policy ladder.

## Post-release fix 2 (same day) — UTF-16 member order, issue #2 (Rul1an)

A second real canonicalization bug, also found by a stranger reading the code: sorting keys on
`k.encode("utf-16-le")` compares the **low byte of each code unit first**, which is not the
code-unit ordering RFC 8785 §3.2.3 requires. `a` next to `Ā` (U+0100) sorted `Ā` first; `ÿ`
(U+00FF) next to `Ā` likewise. Fixed in `7474528`: the sort key is now `utf-16-be`, in both
`tamga_canon.py` and the deliberately-duplicated standalone `tamga_verify_mini.py`.

Why our own gate missed it: AT-036 covered the **astral** surrogate boundary (where LE happens
to agree with code-unit order) but not the intra-BMP byte trap. The reporter's exact vectors are
now pinned — they go RED under the old sort:

- selftest: `{a,Ā}`, `{ÿ,Ā}` — 8 → 11 expected outputs
- cross-language oracle: 13 → 16 vectors, `16/16` byte-identical to Node/ECMAScript
- official RFC-8785 corpus (`cyberphone/json-canonicalization` @ `19d51d7f`): `6/6`
  byte-identical, `weird.json` included — `דּ` now sorts last as the published output has it

No published receipt or finding changed (all pinned hashes are ASCII-only;
`fe6f230c…` recomputes unchanged). Suite 58/58.

# Release notes — v0.2.10

Release date: 2026-09-16 · Tag: v0.2.10 · Branch: `main`

**v0.2.10 — the foreign-evidence release: we now ship verifiers for OTHER people's proofs,
and the migration story is demonstrated on code we did not author.**

## What is in this release

- `tamga attest-verify` (`tamga_attest_verify`): validates FOREIGN delivery-attestations
  (`CAPACITY_ATTEST_V1`) with a stdlib-only pure-Python stack — secp256k1 ecrecover, EIP-191,
  deep-sorted canonical JSON with the issuer's exact 11-key/whitespace contract. Reproduces
  capacity-attest@0.6.0's own `verifyClaim` verdict 7/7 on vendored fixture vectors (including
  both negatives), and independently GREENs their real production claim. Unknown registry tag →
  İNDETERMİNE, never absent. Control: AT-030 (kontrol-54).
- `tamga verify-cr` (`tamga_cr_verify`): one-owner successor of the AT-029 cross-proof harness —
  candidate generation (`--candidates`) plus single-document CR-v0.1 canonical-digest checking
  (three-verdict with `--expect`; bare call is measurement, not verdict). Old tool file deleted;
  no shim (single-source-of-truth discipline).
- `evaluated` meta-flag on `tamga liveness-probe` JSON output: `false` = the probe never got to
  look, `true` + İNDETERMİNE = it looked and could not settle — the machine-readable answer to
  x402 #2887's NOT_EVALUATED debate, without renaming the sacred three verdicts (AT-028).
- AT-032 (kontrol-55, slow): builder-determinism control — same-toolchain double build is
  byte-identical; the Sept-11 template drift is classified as rustc patch-version codegen,
  documented as an honest limit in AGENT-GUIDE §3 (EN+TR) + `rust-toolchain.toml` pin.
- Docs: `docs/MIGRATION-DEMO.md` + `scripts/migrate_ext_b3sum.sh` — published third-party CLI
  (b3sum v1.8.7) migrated end-to-end into the envelope with 3 labeled patches, fail-loud
  threadless-sandbox finding, byte parity bare==envelope, overhead table (native 9.7 / bare
  26.0 / envelope-net 37.6 ms, median-15).
- Language honesty: "canonical Turkish (internal)" claims removed from RFC-001…004 — the living
  English text is binding; Turkish twins (docs/*.tr.md) stand beside their originals.
  *(same-day correction: the count grew with the night batch — and RFC-005/006 + VERIFY-EPOCH-ANCHOR
  turned out to be Turkish-BORN originals with no English; an EN translation is the recorded open debt for
  those three. AT-033 twin-hygiene now guards the whole class.)*

Suite at release: 55/55 (RUN_SLOW=1, idle machine) · links 129/0 · fresh-venv audit ritual green.

### Post-release fix 2026-09-16 (same-day, no silent edits)

**Defect:** the v0.2.10 upload shipped the wheel only — 0.2.6–0.2.9 all carry wheel **and** sdist;
0.2.10's sdist was missed. Found by the founder-requested debt sweep reading PyPI's own JSON
(`GET /pypi/tamga-protocol/0.2.10/json` → one `bdist_wheel`, zero `sdist`), NOT by any local check:
`twine upload` succeeded and the fresh-venv ritual is wheel-based, so nothing in the chain could
catch a missing second artifact. **Fix (live):** sdist rebuilt from the tagged tree
(`git worktree v0.2.10` → `python3 -m build --sdist`), `twine check` PASSED, uploaded with
`--skip-existing` (no existing byte touched), sha256 `29747a4bcfe8e5c8a32ec7eeb7948150e034af0a12bfd4d0110c9eb1e7367266`,
now present on PyPI. **Structural:** the release ritual now ends with an external assertion —
after every upload, assert BOTH `bdist_wheel` and `sdist` appear in the live PyPI JSON for the
version (the command that caught this). The ritual gap was that a wheel-only ritual can pass; it
cannot anymore.

### Pending: v0.2.11 — canonicalization fix (founder-gate; release follows a finding)

**Defect (external finding, 2026-09-17):** our `jcs` was `json.dumps(sort_keys=True,
separators=(",",":"))` — Python-specific, not RFC 8785: ECMAScript number serialization missing
(`1.0` serialized as `"1.0"` not `"1"`; `2.93e-07` as `"2.93e-07"` not `"2.93e-7"`; `1e16` as
`"1e+16"` not `"10000000000000000"`) and member ordering was code-point, not UTF-16 code-unit
(diverges when non-BMP mixes with high-BMP). Consequence: a receipt digest was recomputable only
by Python — the exact property a compliance receipt exists to destroy. **Found by a stranger
auditing the sister project** (Dümen issue #4, stillmarcus24 — same class of bug in
`evidence_chain.py:65`), not by us; our own audit had signed off the function as "RFC 8785" for
weeks. **Fix:** single-center `tamga_canon.py` rewired into all 9 call sites; byte-identical to a
Node/ECMAScript reference (13/13, `tools/jcs_parity.sh`); new control AT-036 (kontrol-58) with
rc2-İNDETERMİNE when node is absent. **Measured impact:** EBL 34/34 cross-run finding stands
byte-identical (corpus is float-free ASCII — re-verified against a re-downloaded sha-pinned
corpus); AT-029 8/8 and AT-030 7/7+8/8 unchanged; pairing-fixture pinned hash migrated
(`6c0cab5f…` → `fe6f230c…`, 6/6 checks green). Suite 52→53 fast, 57→58 slow, both green.
**Structural:** this is the second release-following-a-finding (after 0.2.10's sdist gate) — the
pattern that keeps the project honest is that strangers' audits find real defects and we publish
the fix, not the story. Release timing: founder gate.

# Release notes — v0.2.9

Release date: 2026-09-15 · Tag: v0.2.9 · Branch: `main`

## What is in this release

1. **`tamga liveness-probe` is now a console command.** The probe (block-NUMBER span = clock;
   server timestamps never read — #2887's lesson as contract) shipped last release as a repo
   tool; it now lives in the wheel as `tamga_liveness` and is reachable as
   `tamga liveness-probe [--rpc URL] [--max-age-blocks K]`. Defaults to live Sepolia; three
   verdicts (rc0 GREEN / rc1 RED / rc2 İNDETERMİNE). `tamga doctor` import-checks it;
   AT-028 exercises the module form; the monthly fresh-audit ritual gained a console
   dead-port check (offline-deterministic).
2. **The stranger-pass ritual shipped** (tools/fresh_audit.sh + monthly CI loop, day 20;
   rc2 maps to warning-not-red) and **AGENT-GUIDE §14/§12 declared the re-execution class**
   (pinned receipts vs order-independent canonical layer — the in-toto PR-592 doc promise).
3. **Anti-entropy**: retired tools/social_preview.py deleted (duplicate card-generator, zero
   callers, approval 2026-09-15).

Suite: **49/49 fast, 53/53 slow**, links 125/0, wheel inspected (15 modules, no engine).

---

# Release notes — v0.2.8

Release date: 2026-09-15 · Tag: v0.2.8 · Branch: `main`

## What is in this release

1. **E-15 — chain-binding preflight on `epoch-verify`'s anchor leg.** The x402 #2887
   convergence today ("identity/chain binding is checked should be a testable field, not an
   assumption") described a gap we actually had: `--rpc` was trusted to serve the claimed
   chain. Live demo the same evening: a mainnet endpoint answering a Sepolia contract returned
   `0x` — İNDETERMİNE *by luck*. Now `eth_chainId` is asked first (default expectation
   Sepolia = the default contract's chain; `--expect-chainid N`; `0` = explicit skip that
   prints an honesty note). Wrong-chain and skip-mode pinned as AT-027 cases 8/9 (RFC-009 §3).
2. **`tools/liveness_probe.py` + AT-028 (kontrol-53).** Freshness by block-NUMBER span —
   server timestamps are deliberately never read (#2887's clock lesson, encoded as a contract:
   the offline mock answers with a contradictory timestamp and the verdict must ignore it).
   Five-case decision matrix is offline-deterministic; the tool itself was live-green against
   public Sepolia and mainnet today, refused-port İNDETERMİNE.

Suite: **49/49 fast, 53/53 slow**, links 125/0, CI green on the slice commit.

---

# Release notes — v0.2.7

Release date: 2026-09-15 · Tag: v0.2.7 · Branch: `main`

## What is in this release

Two slices, one release, found the same way every previous one was: by using the tool
as a stranger and by keeping a public word.

1. **E-14 — CLI hardening (the 0.2.6 wheel was still crash-prone for zero-arg misuse).**
   The all-commands empty-argument matrix caught 5 commands answering with IndexError
   tracebacks (`grant`, `run`, `export`, `memory`, `keygen-node`) and 2 answering with
   VACUOUS `ok=true` (`ledger`, `ledger-verify` — a nonexistent path even verified as a
   "valid empty chain"). Now: one shared `usage_guard` choke point on both dispatch
   paths, firing BEFORE the engine resolver (a usage error can never trigger the one-time
   wasmtime download); new RED reason_code **19 `pkg_dizin_degil`** — "could not look"
   is never green, the epoch-verify INDETERMINE rule applied to our own chain surface.
   Legal pre-genesis semantics for real chain-less directories are unchanged (documented
   side by side in AGENT-GUIDE EN/TR). Negative family pinned inside AT-021.
2. **AT-029 — CR v0.1 canonicalisation cross-proof** (in-toto PR-592, promise kept the
   same day it was made): Tamga's own canonical function — the very `jcs()` that every
   epoch-anchor digest runs through — reproduces all 8 published canonicalisation-layer
   vectors of Anomly's CR v0.1 spec, graded by the upstream neutral conformance runner
   vendored byte-identical (Apache-2.0; sha256 pins re-verified inside the control, so
   upstream drift turns us RED loudly, never silently). Scope honesty is asserted, not
   implied: canonicalisation layer only — Tamga is not a CR certifier, and the
   receipt/verdict half is neither claimed nor faked. A digest-tamper negative proves
   the referee bites.

Suite: **48/48 fast, 52/52 slow** (AT-029 joined the fast baseline; E-14 pinned as an
aggregated family inside AT-021), links 125/0, CI green on both slices.

## Notes

- The wheel is again byte-built from this tag and re-tested in a clean venv before this
  file claimed anything (see docs/REPRODUCE.md last-verified line, updated same day).
- Honest bookkeeping: the CHANGELOG entry for AT-029 silently no-oped in `ea54de7`
  (a guard condition I wrote wrong); discovered in this tur and restored in full here.

---

# Release notes — v0.2.6

Release date: 2026-09-15 · Tag: v0.2.6 · Branch: `main`

## What is in this release

Same-day patch on v0.2.5, found by using the v0.2.5 wheel as a stranger: `tamga explain`
fed a directory (misused flag order) crashed with a raw traceback. The whole bad-input
family (dir / missing / malformed JSON / scalar-or-list root / out-of-range or non-integer
seq) now answers `explain: <reason>` at rc1 — no tracebacks, the AT-025 rule. AT-016
grows the negatives-family as one aggregate control; canonical suite stays 47/47.

---

# Release notes — v0.2.5

Release date: 2026-09-15 · Tag: v0.2.5 · Branch: `main`

## What is in this release

**v0.2.5 — wheel = HEAD: the fresh-user audit release.** Installed 0.2.4 from PyPI into a
bare venv and used it as a stranger would; everything that finding exposed ships here.
No wire contract, no ledger format, no spec_version change — `epoch-verify` and the audit
fixes were already the repo's reality; this release makes the distribution honest about it.

- **`tamga epoch-verify` ships in the wheel** — 0.2.4's wheel did not contain it (py-modules
  listed the module, the 0.2.4 wheel predated it): a pip user following our public #3389
  demos hit `unknown command`. AT-026's packaging parity control now runs against this build.
- **Help surface completed**: 15 shipped commands listed (was 7), engine-free vs engine
  split, rc2-İNDETERMİNE contract documented, version line corrected.
- **Wizard guidance addressed to pip users** (`tamga …`, clone form noted — the old
  `python3 tamga_runner.py …` advice was dead in a pip user's cwd).
- **README (EN+TR) + QUICKSTART carry epoch-verify** — the outward verifier was shipped
  and publicly demonstrated but invisible on user surfaces.
- **Suite concurrency guard** (flock): two parallel `run_all.sh` instances had produced
  4 false FAILs the morning of this release — refused instance now exits 1 with the reason.
- **docs/TESTS.md**: AT-016/017/018 rows added (controls ran; the table had drifted).

Verification trail: 47/47 fast ×3 runs (one race-incident investigated, not hidden),
51 slow-gated suite pre-tag, links 125/0, CI green per push, wheel re-tested in a bare venv
after upload (`epoch-verify --selftest` rc0).

---

# Release notes — v0.2.4

Release date: 2026-09-13 · Tag: v0.2.4 (0f18024, PyPI 0.2.4 live) · Branch: `main`

## What is in this release

**v0.2.4 — the packaging honesty patch: ingest ships in the wheel.**

- **`tamga_pugio_ingest` ships in the wheel** — 0.2.3 shipped the module in the repo
  but left it out of `py-modules`, so a PyPI user could not import the AT-025 surface
  (install-break class). Found by the new AT-026 while writing it; fixed before release.
- **AT-026 — wheel tam-modül** (slow control 50): packaging-completeness contract —
  repo-root ↔ `py-modules` ↔ wheel contents three-way equality, isolated-dist build
  (never deletes an existing `dist/` — the AT-019 interaction caught by the fresh-eyes
  audit), and a full-install import gate for every module. Negative-proof verified:
  re-simulating the 0.2.3 omission REDs the control.
- **Fresh-clone honesty (audit):** AT-019/AT-026 now declare their prerequisites with a
  message instead of failing silently-red — REPRODUCE{,.tr} documents them (wheel via
  `python3 -m build`; the c30 fixture stays a loud SKIP at 49/49).
- **Fail-loud RED completeness (audit):** `tamga_pugio_ingest` non-dict bundles, huge
  integers, and empty event-sets return RED (no receipt, no traceback); an empty K0
  envelope produces NO receipt; `tamga_project_head` rejects non-object lines as
  reason-14 RED; `tamga_verify_mini` treats non-object records as `broken@N` — now
  byte-identical in DECISION with `tamga_runner._verify_chain` on that edge (audit O5).

Verification: fast suite 46/46, slow suite 50/50 (run_all-024057); fresh-clone
post-setup run: 49 PASS / 0 FAIL / 1 SKIP (c30 fixtures, message-declared);
links 92/0; wheel 0.2.4 contents: 12 modules + templates trio, ingest confirmed.

---

# Release notes — v0.2.3

Release date: 2026-09-12 · Tag: `v0.2.3` · Branch: `main`

## What is in this release

**v0.2.3 — the composition surface reaches the user: project-head CLI + PUGIO
receiver pair + CHANGELOG.**

- **`tamga project-head <pkg>` (AT-023)** — chain-head → batch-leaf projection on the
  user surface: replays a REAL ledger with the canonical D5 (byte-identical to
  `tamga_runner._verify_chain`: prev-in-record, node_sig outside the hash, 1-based seq,
  `"0"*64` sentinel) and encodes the tip with the RFC-009 batch-leaf scheme into a
  `TAMGA_PROJECT_HEAD_V1` JSON; the presentation-only boundary travels INSIDE the
  output; broken chain → RED (reason-14 family). Engine-free, stdlib-only.
- **`tamga_pugio_receiver.py` (AT-024)** — the inbound half of the anchor surface
  (RFC-009 receiver-side): verifies `external_anchor` JSONL lines from the PUGIO
  bridge with pure sha256 (`anchor_id = SHA256(head|merkle_root|event_count)[:32]`);
  one red line fails the whole file (fail-loud); version gate closed.
- **`tamga_pugio_ingest.py` (AT-025)** — receiver step-2 (81-MERGEN-side K0 bundle
  reader): full-body verification (chain-bind + per-event proof + merkle root + head +
  event-count cross), then a deterministic Tamga verification receipt with an audit
  summary; fail-closed — a RED bundle produces NO receipt.
- **`CHANGELOG.md` born** — the public change history (0.1.0-alpha → today) in
  Keep-a-Changelog format; PyPI Changelog URL now points here.
- **Docs surface:** RFC-009 §4 receiver clauses ((c) + (c2)); AT-023/024/025 family
  rows; four Mermaid diagrams in ARCHITECTURE; WHY-HASHCHAIN third axis; demo
  extended to 8 steps (verify-mini/bundle/project-head live) with a regenerated cast;
  suite counts honest everywhere including the shields badges (a drift the sweep
  itself caught post-hoc — badges must sync with the suite, lesson recorded).

Verification: fast suite 46/46, slow suite 49/49 (RUN_SLOW; AT-025's first slow pass);
wheel E2E from a clean venv (doctor SAĞLAM; project-head live; pugio imports);
**live-verified from PyPI**: `pip install tamga-protocol==0.2.3` → quickstart →
project-head → `TAMGA_PROJECT_HEAD_V1`. Upstream the same day: Vauban conformance
PR #2 (external-ledger projection vectors) + stdlib-only runner.py (9th
implementation, row-parity 13/7/0/6).

---

# Release notes — v0.2.2

Release date: 2026-09-11 · Tag: `v0.2.2` · Branch: `main`

## What is in this release

**v0.2.2 — professional surfaces: wheel-side `explain` + keccak fix + PyPI/CI parity.**

- **`tamga explain` ships in the wheel** (root module `tamga_explain`; was repo-only
  `tools/explain.py` — REPRODUCE §0 said so honestly since 0.2.1). Human-language
  receipt/charge summaries, TR/EN, tamper verdicts (EŞLEŞMİYOR/VERIFIED), no
  PyNaCl, no engine. `tamga doctor` now reports the `explain` + `keccak256` surfaces.
- **Wheel-side `--delivery-alg keccak256` fixed** (2026-09-11 finding): `_digest`
  resolved `tools/keccak256.py` by path — `tools/` is not in the wheel, so the
  RFC-007 R2 labeled-digest path crashed on installed copies. Algorithm moved to
  root module `tamga_keccak` (KAT self-test 3/3); `tools/keccak256.py` and
  `tools/explain.py` are now compatibility aliases (single-owner discipline);
  AT-016 gained a root-module-parity check (alias vs root, byte-equal output).
- **PyPI metadata professionalized**: keywords, OS-Independent, Python 3.10–3.13
  classifiers, Documentation/Changelog/Bug-Tracker URLs — and the classifier claim
  is **proven by a CI matrix** (3.10/3.11/3.12/3.13, fail-fast: false), not asserted.
- **Repo meta**: GitHub Releases for v0.2.0/v0.2.1 (Latest was stuck on v0.1.0-alpha
  from 2026-09-05), homepage → PyPI, description carries the PyPI name, discovery
  topics (tamper-evident, hash-chain, agent-memory, receipt-chain).

Verification: fast suite 42/42 (alias+root parity, corpus binder 5/5), wheel E2E
from a clean venv — keccak-KAT via installed runner, `--delivery-alg keccak256`
end-to-end, `tamga explain --charge`, doctor surfaces.

---

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

---

# 0.2.12 — canonicalization boundary enforcement (2026-09-18)

Two behavior changes, both found by tracing a third party's audit taxonomy back
into our own code. Neither is a new feature; both tighten a determinism boundary
that was previously enforced by luck rather than by code.

## What changed

**1. Integers outside `[−2^53, 2^53]` are now rejected.** Previously preserved
exactly, treated as a feature. That was wrong: Python parses `9007199254740993`
as an exact integer and serializes it unchanged, while every ECMAScript runtime
parses it as an IEEE-754 double and prints `9007199254740992`. The same JSON text
in, two different canonical bytes out, and a receipt that stops recomputing
across languages — silently. RFC 8785's I-JSON subset (RFC 7493) excludes these
values, so the boundary is now an explicit refusal. Callers scale the unit or
serialize large identifiers as strings.

**2. `NaN` and `Infinity` are now rejected.** Previously a `TypeError`; the
behavior was correct but the class was mislabeled. The reason it matters:
`JSON.stringify` in ECMAScript emits the literal `"null"` for both — silent value
degradation, not an error. Aligned to the same `ValueError` family as the range
check so the conformance gate asserts both as RED.

## How it was found

SolomonisBlack shipped an instrument derived from our hash-invocation counter
(the `check-hash-count.mjs` shape discussed in x402#2887) and, alongside it, an
audit CLI that classifies canonicalization violations. "Integers past 2^53-1" was
on that list. Reading the classification, we checked our own implementation and
found the divergence above — the audit taxonomy of a third party found a live
defect in our code across the wire. This is the third and last divergence class
we are aware of between our canonicalizer and an ECMAScript one, after the
number-to-string regression (0.2.11, #1) and the UTF-16 code-unit ordering (0.2.11, #2).

## Verification

- Canonicalizer selftest 11 → 16 vectors; 4 now assert a refusal (`ValueError`)
  rather than an output.
- Cross-language parity 16 → 19 vectors: 17/17 byte-identical against the Node
  oracle, plus 2 I-JSON range cases where Python refuses and Node rounds — the
  gate now names that as the expected difference instead of counting it as a
  divergence. NaN/Infinity cannot ride the JSON interchange (Python writes a NaN
  literal that `JSON.parse` rejects), so they are asserted object-level in the
  selftest.
- Official RFC-8785 test corpus: still 6/6. The corpus is I-JSON-clean, so the
  new refusal does not reach it — no published fixture, receipt, or finding hash
  changes. The pinned `pairing-fixture.json` digest (`fe6f230c…9264c`)
  recomputes identically (ASCII-only numeric fields).
- Slow acceptance suite: 58 PASS, 0 FAIL.
- A duplicate-member-name injection was tested and requires no code change:
  both runtimes take the last value, and a tampered amount in a ledger record
  fails `ledger-verify` with reason 14 (`broken@1`) because the signed hash no
  longer matches. The parser layer is not the canonicalizer's problem, and the
  signature layer already catches the tamper.

## Honest limits

- The two refusals are boundary tightenings, not a soundness result. A value
  inside the I-JSON range can still be a lie about what happened; a receipt is
  post-hoc and proves authenticity, not soundness. Nothing here changes that.
- Callers passing large integers (milli-satoshi scale above 2^53, large
  timestamps in non-ISO fields) must move to string fields or a smaller unit.
  The migration is mechanical, but it is a break, so it ships in a minor bump
  rather than a patch.
- The same month found one honest correction of our own: a finding we attributed
  to a live run had actually come from a fixture shape. The fixes stood; the
  mechanism was overstated. Recorded in x402#2887 rather than left in chat.

# RFC-002: Runner API and Snapshot Transport

> Canonical version of this document is Turkish (internal). This is the official English translation — normative content is identical.

*Translator's note on E-3: the frozen original lists reason 10 as `memory_limit` — a drafting-time
inconsistency; the shipped runner (and the public reason-code table in ARCHITECTURE.md) uses reason 10
for `input_invalid` (memory exhaustion maps to `runtime_limit`/reason 11). Preserved verbatim for contract fidelity.*

*Translator's note: code blocks are reproduced verbatim from the canonical Turkish original — commands, flags, field names, and example values (including the example package name `tamga-ornek-ajani`) are unchanged; only Turkish comments were translated. Evidence paths in the Errata refer to the local, untracked `.evidence/` run-log directory.*

- **Status:** **v0.1-FINAL — FROZEN (2026-09-02, founder-approved).** A change requires a new RFC + a version bump.
- **Dependencies:** primitive definition §3 (transport integrity), security model §5 (at-rest/in-use separation); acceptance tests AT-001b/c/d/e; RFC-001 (manifest, v0.1-FINAL) — the referenced documents are internal (decision log).
- **Scope:** v0 (Phase 1). No networking/discovery, no real payments — all payment is the `tamga-sim/1` simulated ledger.

## 1. Motivation

RFC-001 defined the package; this RFC is the contract of the party that **runs** it and **transports** it. The primitive's transport-integrity maxim (*"Changing machines does not change the agent's identity"*) is realized here: AT-001b/c/d/e are all wired to this API.

## 2. Decisions (with rationale)

| # | Decision | Rationale | Rejected alternative |
|---|---|---|---|
| D1 | API surface: **CLI + JSON stdio** (no daemon, no HTTP in v0) | Evidence culture: every operation is a single command + an output file; testability is maximal. Daemon/HTTP is the subject of v1 | a long-lived daemon + REST (makes evidence production harder in v0) |
| D2 | Snapshot: **single file, `tamga-snapshot/1`** — a header + an encrypted body (XChaCha20-Poly1305, pinned in RFC-001) | Single file = portability; the header is plaintext but *describes the encrypted region* and contains no agent data (AT-001d scope) | a folder tree (scattered, weak portability) |
| D3 | Identity keys are **never written to the host disk**: a RAM keystore for the duration of a run; on export, the keystore travels as an encrypted block embedded in the snapshot | The primitive-definition rule (§3, internal decision log): the host cannot read or back up sk_A. The embedded block is the carrier of transport integrity | writing the seed to disk (a violation of the primitive) |
| D4 | Transport: `export → import` as two separate commands; import **re-performs** signature+hash verification with the RFC-001 validator | A clear trust boundary: the importing node verifies the incoming package with its own eyes (zero-trust transport) | a single "migrate" command (the verification chain becomes blurred) |
| D5 | Accounting: `ledger.jsonl` — append-only, one JSON record per line, RFC-003 schema | One-to-one with the evidence culture: a log line = an evidence line | SQLite (needless weight in v0; re-evaluated in v1) |

## 3. CLI Contract (normative)

```
tamga-runner keygen <dir>                     # generate in RAM; to be embedded in the snapshot (D3: no disk writes)
tamga-runner run <pkg> --seed <hex>           # run; the snapshot is updated automatically at the end of the operation
tamga-runner export <pkg> -o <snapshot.tsg>   # state + embedded keystore → a single file
tamga-runner import <snapshot.tsg>            # RFC-001 validation → keystore restore → READY
tamga-runner ledger [pkg]                     # ledger.jsonl summary (stdout: JSON)
```

Rule: every command writes **a single line of JSON to stdout**: `{"ok":true,"op":"import","pkg":"tamga-ornek-ajani",...}` or `{"ok":false,"reason_code":"..."}`. The `reason_code` values are numbered in §6 — these match the reason codes in the AT logs one-to-one.

## 4. Snapshot Format — `tamga-snapshot/1`

```
[magic: "TSG1"][u32 header_len][header JSON][XChaCha20-Poly1305 body]
```

**Header (plaintext, contains no personal data — subject to the AT-001d audit):**

```json
{
  "format": "tamga-snapshot/1",
  "pkg_name": "tamga-ornek-ajani",
  "pkg_wasm_sha256": "<RFC-001 code hash>",
  "agent_id": "<pk_A hex>",
  "cipher": "XChaCha20-Poly1305",
  "keystore_blob": "<embedded, sk_A block encrypted with a PKDF-derived key>",
  "body_nonce": "<hex>",
  "created": "<ISO-8601>"
}
```

**Body (encrypted):** context-graph nodes + the last session state. In the header, free text beyond `pkg_name`/`agent_id` is **forbidden** — the AT-001d grep audit enforces this rule.

## 5. Operation Sequences

**Transport (AT-001b):**
1. node-A: `run` (state is created) → `export` → `snapshot.tsg`
2. the file is moved to node-B (the transport channel is out of scope)
3. node-B: `import` → RFC-001 validation + header integrity + keystore unlock → READY
4. node-B: `run` → the agent continues with **the same agent_id** (AT-001e)

**Payment (AT-001c):** at the end of every `run`, process measurement (CPU ms, max RSS, IO) → fee by formula → a `ledger.jsonl` line: `{"op":"charge","pkg":...,"cpu_ms":...,"ram_mb_s":...,"io_mb":...,"fee_sim":...}`. The simulated balance settles against the `grant` records inside `ledger.jsonl`.

## 6. reason_code Register (numbered)

| # | Code | Meaning |
|---|---|---|
| 1 | snapshot_bad_magic | no TSG1 header |
| 2 | snapshot_header_invalid | header JSON/schema violation |
| 3 | manifest_reject | RFC-001 validator RED (with a sub-code) |
| 4 | keystore_unlock_failed | the embedded keystore could not be unlocked |
| 5 | proof_level_unavailable | the node cannot offer min_proof_level (v0: P0 is always offered) |

## 7. Open Questions (deliberately deferred)

1. keystore PKDF parameters (Argon2id recommended) → pinned together with RFC-004.
2. Snapshot diff / incremental transport → v0 is a single-file full snapshot; a decision after measurement.
3. Checkpoint policy for `run` with long-lived agents → after the AT-001 run measurement.
4. Node-specific balance verification of the ledger → RFC-003.
5. Run-time transfer of the seed (stdin/env/daemon) — with the v1 daemon design (Erratum E-2).

## 8. Approval Record

- [x] Founder approval: **2026-09-02** — this RFC was frozen, Status: **v0.1-FINAL**. Implementation: `tamga_runner.py` (Phase 1, Slice 1).

## 9. Errata

- **E-1 (2026-09-02, at freeze time):** the `keygen <dir>` signature in §3 is misleading: per D3, keygen **writes nothing to disk**; the seed is printed only to stdout (a single JSON line) and the user stores it in a safe place. The `<dir>` parameter is accepted but ignored.
- **E-2 (2026-09-02):** the `run --seed <hex>` command-line argument is readable via `/proc` (an accepted limitation in simnet); run-time transfer of the seed (stdin/env/daemon) was deferred to the v1 daemon design — recorded as item 5 in §7.
- **E-3 (2026-09-02, Audit-1):** the reason_code register in §6 was extended at the code level: 6=seed_invalid, 7=snapshot_too_large, 8=snapshot_replay_rollback, 9=agent_identity_mismatch, 10=memory_limit. Reason: the security-audit findings (Audit-1/2, internal decision log) required a numbered-rejection model; the §6 table is formalized in the next RFC version.
- **E-4 (2026-09-02, Slice-2):** the source of the `pkg_name` field in §4 was not normative, and two owners emerged in the implementation (the directory name vs RFC-001 `package.name`). Norm: **`pkg_name` = RFC-001 `package.name` (canonical owner)**. Export reads it from the manifest; import already verified this (the Audit-1 F8 gate). Evidence: `.evidence/ (local, untracked)`.
- **E-5 (2026-09-02, Slice-3):** the run engine is pinned: **wasmtime v48.0.1** (a binary verified against the GitHub release digest `sha256:4c2e31b6…`, in `tools/bin/`). §3 `run` semantics: the agent runs **process-isolated**; the D4 default-deny implementation = no fs preopen is given to wasmtime, no network (`-S allow-ip` is not given), clock/randomness come from the WASI 0.3 defaults. reason_code extensions: 11=runtime_limit, 12=agent_run_failed, 13=not_component. Session evidence: `run` writes stdout to a `pkg/session-N.stdout` (0600) file and returns its sha256.
- **E-6 (2026-09-02, Slice-4):** the metering contract was upgraded: the charge record now carries `cpu_saat / ram_gb_sn / io_mb / wall_ms`. cpu and ram are **real measurements** from the child wasmtime process (`RUSAGE_CHILDREN` delta + maxrss — honest note: maxrss is the MAX across children, and cpu<wall comes from wasmtime clock-read yields); wall_ms is separate. The billing base (wall vs cpu) **is an RFC-003 decision** — AT-001c evidence: `.evidence/ (local, untracked)`.
- **E-9 (2026-09-05, Slice-7/8):** the snapshot ↔ ledger coupling and reason_code extensions:
  (a) **F24 closure — the ledger travels with the snapshot:** `export` embeds the entire chain (`ledger_records`) into the state inside the encrypted body; `import` re-verifies the `ledger_tip` context over the embedded chain. §4 body definition: "context-graph nodes + the last session state **+ the embedded ledger**".
  (b) reason_code extensions at the code level (following the E-3/E-5 precedent): **14=ledger_broken** (file missing / broken tip context / import after a truncate — F21 closure), **17=state_invalid** (`graph_merkle` mismatch / ADD-only violation).
  (c) **Honest note on limit semantics:** the `cpu_ms_per_run` limit is a **wall-clock** process timeout (not CPU time). Under heavy host load (load ≥ ~40, parallel rustc compilations), even a trivial agent can go RED with reason 11 (runtime_limit) — it is a **timing** matter, not a metering one; the meaning of the limit is unchanged. The name was kept because RFC-001 is frozen. Evidence: `.evidence/ (local, untracked)` (a reason-11 observation under load 41).
- **E-10 (2026-09-05, Audit-7 / Slice-9):** hardening of the embedded chain's attack surface and an honest limit statement:
  (a) **Pre-installation verification (closed):** `import` verifies the internal hash-chain (`_records_head`) of the embedded `ledger_records` chain BEFORE writing it to the target node; a corrupt body → import RED (reason 14, "embedded chain broken@N"). This closes the part of E-9a's zero-trust that was left half-done: installation is no longer left to "being caught at the next verify". Evidence: `.evidence/ (local, untracked)` (A1a, the run after the fix).
  (b) **F25 open finding (documented):** a seed-owner adversary can re-hash the chain from scratch and establish a self-consistent **fake history** on a fresh node (the A1b attack passes import + ledger-verify). Current remedies: the D4 append-only rule (binding `ledger_tip` on a target that already has a chain is RED — A2) + seed confidentiality. The permanent fix is **node-cosign** (the node's key enters the record's hash input) → added to RFC-003 Open Question 4. Because simnet is a single-writer environment, the severity is Medium; on a network it is High.
  (c) **Consistent-tampering upper bound (documented):** a seed-owner can recompute `graph_merkle` and produce consistent state (A3) — the adversary model for merkle is a host without the seed; this limit is not an undisclosed gap, it is a model definition.
- **E-11 (2026-09-05, Slice-9 / learning):** the metering limit was confirmed on the slow round as well: in a 16/16-passing run, `c30 wall_ms=31022` (AT-001c formula deviation 0.000022%; `.evidence/ (local, untracked)`). Practical note: on the slow round, the c30 run clears the wall-30000 limit with only ~3% margin in the host-load ~22–29 band — the reason-11 risk exists on the slow round too in the load ~40 band; evidence runs are planned in a low-load window (this round: an inline run at load ~21). Overhead baseline: `.evidence/ (local, untracked)` (E-4).

## §9 Errata — Continued

- **E-12 (2026-09-05, Audit-9 B12/B3/B7):** the normative CLI signatures in §3 are pinned to the real surface:
  (i) `export <pkg> -o <snapshot.tsg> --seed <hex>` — `--seed` is **mandatory** (missing → RED 6);
  (ii) `import <snapshot.tsg> <pkg>` — the second argument, the target pkg, is **mandatory** (forgotten in §3);
  (iii) `run` does **NOT create a snapshot** at the end of the run — it updates only state.json + ledger.jsonl;
  a snapshot is produced only via `export` (the "updated automatically" comment in §3 is dropped).
  (iv) **New RED code 18 = `agent_ownership_mismatch` (Audit-9 B7):** state.json now carries
  `agent_id`; at run time, another agent's seed cannot be run against state owned by a different agent, and at import, the
  living agent's state on the target cannot be overwritten with another agent's snapshot (transport = export/import onto an empty node;
  an ownership change goes through the documented flow — requires a founder decision). In old fixture states
  that lack `agent_id`, the binding is established on the FIRST run (backward-compatible). Record: 18 is added
  to the §4 reason table; the RFC-001 schema gains `agent_id` in state as an optional field (v0.1.1).
  (v) **B5:** the io limit (`io_mb_per_run`) is now enforced DURING the run with `RLIMIT_FSIZE`
  (not checked after completion); overflow → the process dies with SIGXFSZ → recorded as RED 11 with the io reason.
  (vi) **B6:** all "0600" claims are atomic (os.open O_CREAT|mode; no chmod-after-write).
- **E-11 correction (Audit-9 B2):** the overhead baseline referenced by E-11 was WRONG in v1
  (import 72 ms = an early-RED artifact; it was captured after the fixture bench).
  The binding baseline is v2: `.evidence/ (local, untracked)` — import (deep verification)
  = 421 ms median (the heaviest operation); the roadmap has been updated (internal decision log).

## §9 Errata — E-13 (2026-09-05, founder-approved)

**E-13 — drafting-time errata correction (normative meaning restated):**

1. **Reason 10 = `input_invalid`.** The frozen body's E-3 lists reason 10 as
   `memory_limit` — a drafting-time inconsistency. The shipped runner (and the
   public reason-code table in ARCHITECTURE.md §7) uses reason 10 for
   `input_invalid` (oversize/malformed `--input`); memory exhaustion maps to
   `runtime_limit`/reason 11. This correction is normative; the E-3 wording above
   is preserved for contract fidelity and superseded by this entry.
2. **Manifest code digest field = `wasm_sha256`.** D5's prose says `code.sha256`;
   the normative field name — in `specs/manifest-0.1.0.schema.json` and in every
   signed manifest — is `package.code.wasm_sha256`. D5's prose is superseded by
   the schema.

(E-13 was pre-announced by translator's notes added at translation time; the
canonical Turkish document carries the same correction in its decision log.)

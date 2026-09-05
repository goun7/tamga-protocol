# RFC-004: Context Graph and Encrypted Snapshot Contract (tamga-snapshot/1 v1)

> Canonical version of this document is Turkish (internal). This is the official English translation — normative content is identical.

*Translator's note: field names, state-format keys, and example values are reproduced verbatim from the canonical Turkish original. Evidence log references point to the local, untracked `.evidence/` run-log directory; internal documents are referred to descriptively (internal decision log). the "predecessor prototype" denotes an internal system preceding Tamga; its lessons (G13, G17, L1, L2, the contradiction scan) are recorded in internal documents (decision log).*

- **Status:** **v0.1-FINAL — FROZEN (2026-09-05, founder-approved).** A change requires a new RFC + a version bump.
- **Dependencies:** RFC-001 §9-1 (the open question: the seed/context-graph schema), RFC-002 §4 (the snapshot format), the predecessor-prototype integration notes L1, roadmap Phase 1 (the Slice-2 evidence: `.evidence/ (local, untracked)`) — the referenced documents are internal (decision log).
- **Scope:** v0 (Phase 1). The snapshot transport format is unchanged; the **context-graph schema** in the body is pinned.

## 1. Motivation

RFC-001 §9-1: "the context-graph schema — to be pinned in Slice-2" (an open question). The Slice-2/3/4 evidence showed the schema in
working form; this RFC makes it normative and bakes the predecessor-prototype lessons (L1) into it. The Argon2id keystore parameters are
pinned here too (RFC-002 §7-1's open question).

## 2. Decisions (with rationale)

| # | Decision | Rationale | Rejected alternative |
|---|---|---|---|
| D1 | **Node schema:** `{id, kind, text, ts, valid_from?, valid_to?, supersedes?}` | The predecessor prototype's G13 lesson (bi-temporal); the question "was this information valid on that date?" can be asked later | a plain list of notes |
| D2 | **ADD-only:** a node is never deleted/modified; a correction is a new node + `supersedes: <id>` | Predecessor-prototype lesson G17 (memory_revisions); one-to-one with the evidence culture | overwrite |
| D3 | **Edge schema:** `[from_id, to_id, kind, ts?]`; kind: ref/derived/contradicts | The Slice-2 implementation becomes normative; `contradicts` is ready for the predecessor prototype's contradiction scan awaiting adjudication | only-ref |
| D4 | **Search:** the v0 substring search (`memory --search`) stays; an FTS + graph-signal hybrid is a **v1 spec subject** | The Slice-2/3 evidence shows substring is sufficient; extra dependencies are banned in v0 (the zero-dep principle) | FTS5 now |
| D5 | **Keystore KDF = Argon2id** (m=64MiB, t=3, p=4) — if PyNaCl is absent, an scrypt fallback (n=2^15, r=8, p=1, maxmem=64MiB), declared via the `kdf` field | The RFC-002 §7-1 pinning; the OpenSSL scrypt memory-limit reality is known from Slice-1 | scrypt-only |
| D6 | **state format v1:** `{"format": "tamga-state/1", "sessions", "memory": {next_id, nodes[], edges[]}, "ledger_tip": "<64hex>", "graph_merkle": "<64hex>"}` | The Slice-2 migration (F14) becomes normative; `graph_merkle` = the ordered hash of the nodes+edges (a tamper-evident memory); `ledger_tip` = cross-binds the snapshot with the ledger | the current plain state |
| D7 | `memory --export-json` / `--import-json`: external systems (first in line: the predecessor prototype) bring the lessons into Tamga nodes | The carrier of the predecessor-integration-notes L2 adapter; the direction remains one-way: external → tamga | direct DB access (banned) |

## 3. Node Types (v0)

`note` (free text), `fact` (a claim — in the L2 adapter the predecessor lessons arrive as this type), `session_marker` (a session-start marker, written automatically by `run`). v1 candidates: `goal`, `tool_result`.

## 4. reason_code extension (E-8)

16=node_limit (nodes ≥ 10000) — **Audit-9 B9's honest note: in the code this limit is currently produced together with reason 10 (memory_limit); 16 is not produced at all today** (a reserve; at approval either the text is aligned to the code or the code to the text). 17=state_invalid (deep validation at import; in the implementation a `graph_merkle` mismatch is RED with this code).

Related reason_codes (the normative register is in RFC-002 §9): 7=snapshot_too_large (SAFE_SNAP_MAX 64MiB), 8=snapshot_replay_rollback (if the target's `sessions` counter is ahead of the snapshot, import is RED — a memory-continuity defense), 9=agent_identity_mismatch (the header identity does not match the pubkey derived from the keystore). Negative-vector evidence: `.evidence/ (local, untracked)`.

## 5. Open Questions

1. Automatic detection of `contradicts` edges (the predecessor contradiction_scan lesson) → v1.
2. Verification of `graph_merkle` by the agent (it proves the integrity of its own memory itself) → Phase 2.
3. The field mapping of the L2 adapter (a predecessor lesson ↔ a `fact` node) → the adapter implementation RFC (the first Phase-2 item).

## 6. Approval Record

- [x] Founder approval (2026-09-05) — RFC frozen; Status is v0.1-FINAL.

## 7. Implementation-Conformance Note (2026-09-05, Slice-9 — not a freeze)

| RFC-004 provision | Implementation | Note |
|---|---|---|
| D5 Keystore KDF = Argon2id (priority), scrypt fallback (n=2^15, r=8, p=1) | **Shipped = scrypt (n=2^15, r=8, p=1)**, declared via the `kdf` field | **honest note:** PyNaCl does not include Argon2id; D5's fallback parameters are v0's implementation. Argon2id remains a v1 upgrade (the `kdf` declaration keeps the transition compatible). Evidence: `.evidence/ (local, untracked)` (Slices 1–2) |
| D6 state v1 (`format`, `sessions`, `memory`, `ledger_tip`, `graph_merkle`) | one-to-one (including the F14 migration) | evidence: `.evidence/ (local, untracked)` (Slice-6) |
| §3 node types note/fact/session_marker | one-to-one; the predecessor-prototype lessons flow in as `fact` (`memory --import-json`) | evidence: `.evidence/ (local, untracked)` (Slice-4) + the Audit-7 precondition |
| §4 E-8 codes 17 (16: today produced via reason 10 — the B9 note) | 17 one-to-one | plus the 7/8/9 context note above |
| — (not in the RFC) | the snapshot body carries the embedded `ledger_records` | normative source: RFC-002 E-9a |

Model limit (Audit-7 A3): a seed-owner can recompute `graph_merkle` and produce a consistent state; the adversary model for the merkle is tampering by a **seed-less host** — this documents its place in the design; it is not an open finding.

# RFC-003: Ledger Record and Metering Contract (tamga-sim/1)

> Canonical version of this document is Turkish (internal). This is the official English translation — normative content is identical.

*Translator's note: code blocks, JSON keys, field names, formulas, and example values (including the example package name `tamga-ornek-ajani` and the fee-formula literals `ucret`/`fiyat`) are reproduced verbatim from the canonical Turkish original. Evidence log references point to the local, untracked `.evidence/` run-log directory; internal documents are referred to descriptively (internal decision log). the "predecessor prototype" (an internal system preceding Tamga) denotes the system whose recorded lessons this contract absorbs.*

- **Status:** **v0.1-FINAL — FROZEN (2026-09-05, founder-approved).** A change requires a new RFC + a version bump.
- **Dependencies:** RFC-002 (E-5/E-6: the run and the metering), acceptance test AT-001c, tokenomics (unit economics), roadmap Phase 1 (Slice 4) — the referenced documents are internal (decision log).
- **Scope:** v0 (Phase 1). All amounts are `*_sim`; carrying real value is the subject of Phase 4 (a dual trigger: withdrawal + a written legal opinion).

## 1. Motivation

RFC-002 proved the run and the metering (E-6: cpu_saat/ram_gb_sn/io_mb/wall_ms are real measurements).
This RFC pins the accounting record: the financial form of the evidence culture — **every fee line backed by a verifiable meter sequence**.

## 2. Decisions (with rationale)

| # | Decision | Rationale | Rejected alternative |
|---|---|---|---|
| D1 | **Billing base = wall_ms** (wall clock). cpu_saat/ram_gb_sn/io_mb remain separate "evidence meters" in the record | Wasmtime's clock-read yields drive cpu down to ~⅔ of wall (evidence: AT-001c, `.evidence/ (local, untracked)`); what the node sells as capacity is the wall-clock resource slice. A cpu base can be gamed via a host time setting | cpu-only (easily gamed against the host; agent-clock vs host-clock disagreement) |
| D2 | **Formula:** `ucret = wall_sn * fiyat + ram_gb_sn * fiyat + io_mb * fiyat`. `cpu_saat` does not enter billing; it is an evidence field | The natural consequence of D1; consistent with the AT-001c formula (the wall conversion) | a cpu-based mixed formula |
| D3 | **Ledger = append-only JSONL** (`ledger.jsonl`), 0600; a line = an evidence line | A continuation of RFC-002 D5; combined with the hash chain in D4 | SQLite (re-evaluated in v1) |
| D4 | **Hash chain:** every record carries `prev` (the 64-hex chain hash of the previous record) + `h` (its own hash). Genesis `prev` = 64×'0'. **Chain hash = sha256(prev_hex + jcs(record-except-h))** — prev is both the PREFIX and INSIDE the jcs input (Audit-9 B8: text–code consistency; in node-cosign, node_sig is outside the hash input and node_id is inside it — see §8 D8) | The Tamga counterpart of the predecessor prototype's core/seal lesson; tampering breaks the chain with a single line; end-to-end checking via `ledger --verify` | plain JSONL (editable after the fact) |
| D5 | **Record types:** `grant` (a credit), `charge` (a run fee), `pay` (v1, agent→agent; reserved for now) | The AT-001c requirement + the slot for the v1 payment loop is ready | charge only |
| D6 | **Evidence meter fields:** cpu_saat, ram_gb_sn, io_mb, wall_ms + `stdout_sha256`, `stdout_file` | The auditable data behind the AT-001c ±5% requirement; even when the numbers are in scientific notation, the values are JCS-compliant JSON | unrounded float (the JSON schema would get complicated) |
| D7 | The `ledger --verify` sub-command: verifies the chain from start to end, returns `ok/broken_at` | Evidence culture: the chain claim must be provable too | a hand-run script |
| D8 | `grant` records are written by the operator's hand in simnet and marked in the record via `note`; after RFC-003, `grant` is written only via the runner sub-command | The simnet reality + shrinking the forgery surface | arbitrary editing |

## 3. Record Schema (normative)

```json
{"op": "charge", "seq": 3, "prev": "<64hex>", "h": "<64hex>",
 "pkg": "tamga-ornek-ajani", "session": 2, "engine": "wasmtime-v48.0.1",
 "wall_ms": 31081, "cpu_saat": 0.006119096, "ram_gb_sn": 0.644635761,
 "io_mb": 3.8e-05, "stdout_sha256": "<64hex>", "fee_sim": 0.000334594, "ts": "<ISO-8601>"}
```
Common fields: `op, seq, prev, h, ts`. `seq` starts at 1 and increments by +1 (a missing/skipped value = a broken chain). `grant`: `{op, seq, prev, h, pkg, amount, note, ts}`. **The chain-hash input = `prev` + jcs(all fields except `h` and `node_sig`)** (JCS-ordered; Audit-9 B8).

## 4. reason_code extension (E-7)

14=ledger_broken (chain verification fails at the broken line; Audit-9 B9's honest note: **15=ledger_empty is not produced at all today** — a grant-less run silently lowers the balance; 15 remains a design reserve, and whether it is produced will be clarified at approval).

**Conformance note (2026-09-05, a quickstart finding):** `ledger-verify`'s behavior for a pkg without a chain — an empty/missing `ledger.jsonl` is not broken; it returns `ok=true, lines=0, head=64×'0'` (the genesis end). This is consistent with D7's definition of a "correct chain"; reason 14 is thrown only if the verification of an **existing** chain breaks.

## 5. Open Questions

1. The `pay` record schema + the agent wallet balance record → the Phase 3 network RFC.
2. ~~A chain-tip summary embedded in the snapshot (cross-check) → Phase 2 hardening.~~ **SUPERSEDED (2026-09-05):** instead of waiting for Phase 2, the hardening shipped in Slice-8 in a stronger form — the full chain is embedded (`ledger_records`) + the `ledger_tip` cross-binding (F21/F24, RFC-002 E-9a).
3. A multi-node shared ledger → Phase 3 (a network, not single-machine simnet).
4. **node-cosign (2026-09-05, Audit-7 F25):** an embedded chain is an agent claim on a fresh node; the seed-owner can set up a consistent fake history (evidence: Audit-7 A1b, `.evidence/ (local, untracked)`). The node key will enter the record's hash input (the record becomes node-certified) → a Phase 2/3 revision. The accepted limit in simnet v0 (single-writer).

## 6. Approval Record

- [x] Founder approval (2026-09-05) — RFC frozen; Status is v0.1-FINAL. The §7 conformance note's "naming correction" (`ledger-verify`) and Open Question 4 are folded into the main text at freeze.

## 7. Implementation-Conformance Note (2026-09-05, Slice-9 — not a freeze)

No normative divergence from the DRAFT; the implementation follows this RFC, and two naming/errata-class differences are tied to the errata:

| RFC-003 provision | Implementation | Note |
|---|---|---|
| D3 append-only JSONL 0600 | `ledger.jsonl` 0600 (`_ledger_append`) | one-to-one |
| D4 hash chain `sha256(prev + jcs(record-except-h-node_sig))`, genesis 64×'0', seq 1-based | `_ledger_head` + `ledger-verify` | one-to-one (the B8 formula consistency); evidence: `.evidence/ (local, untracked)` (Slice-5) |
| D7 verification sub-command `ledger --verify` | **`ledger-verify`** (single word, hyphenated) | **naming correction**: this is the CLI surface; there is no `--verify` flag. The text will be updated before approval |
| §4 reason 14 (15: not produced today — the B9 note) | 14=chain broken (broken@N / node_sig_invalid@N), plus the cosign-L1 REDs | one-to-one; addition: 14 is now also thrown at import for the **embedded chain** (RFC-002 E-10a) |
| — (not in the RFC) | `ledger_tip` in the state; chain membership verified at import (F21) | normative source: RFC-002 E-9a |
| — (not in the RFC) | the embedded `ledger_records` is verified before installation | normative source: RFC-002 E-10a |

Rule: this note does not modify the RFC; the differences are normative in the RFC-002 §9 errata. At founder approval the "naming correction" and Open Question 4 are folded into the main text, then the RFC freezes.


## 9 — D9 (Slice-11): Input binding and the output proof line (2026-09-05)

**New optional field of the `charge` receipt:** `input_sha256` = sha256(the `--input` file bytes).
Contract: the field exists only when `--input <file>` is given at run time; its absence means
"a job without input" (compatible with older receipts). Limit: input ≤ 1 MiB (D11) — exceeding it is a pre-run
RED 10 `input_invalid` (with no fee/chain written).

**Output proof line (`--require-proof`):** the last line of the agent's stdout is in the `TAMGA:<hex16>`
form and gives the FNV-1a-64 fingerprint of the remaining stdout bytes; the runner re-computes it at run time,
a mismatch → RED 12 `output_proof_mismatch` (no receipt is written).

**Replay contract:** the (wasm_sha256, input_sha256) → stdout_sha256 determinism is now
tested for jobs *with input* (AT-004). Limits: FNV is not cryptographic (the proof line is an aid;
tamper resistance comes from the ledger hashes); non-deterministic LLM jobs are OUTSIDE this contract —
the class-defined scope is in RFC-004's Phase-2 section (tied to Round-4 remediation-3).
## 8. v0.2 Revision Candidate — D8: node-cosign (2026-09-05, Audit-8; AWAITING FOUNDER APPROVAL)

The permanent fix for Audit-7 F25 (an embedded chain is an agent claim on a fresh node) was implemented
ahead of time (L0 default, behavior unchanged; the L1 opt-in pilot is ready):

- **D8:** Every record may carry an optional `node_id` (64-hex, the verify-key of the node operator's key)
  + `node_sig` (an ed25519 signature, input = the record's `h`). `node_id` **is inside the hash input**
  (the chain binds the node identity); `node_sig` is OUTSIDE the hash input (it signs `h`; tampering
  is caught by the signature check). The two layers cover each other.
- **Policy ladder:** L0 (today's behavior — a chain without node_sig is legitimate; a record carrying node_sig
  still gets its signature verified) / L1 (at import, every record must carry node_sig AND its node_id must be safelisted;
  otherwise RED reason 14) / L2 (Phase 3: ERC-8004 reputation binding).
- **Node key:** the operator identity; it may sit in a 0600 file (D3 bans only the agent seed from disk).
  `keygen-node <dir>` is a separate command.
- **Evidence:** AT-003 6/6 (`tests/negative_cosign.sh`) + Audit-8 (A1 a strong adversary → L1 RED /
  L0 known residue; A2 signature-layer RED; A3 partial-cosign RED) — `.evidence/ (local, untracked)`.
- **Questions for the founder:** OQ-1 (should L1 be the default in the pilot?) — the node-cosign design document §6 (internal decision log).

# 30-Second Demo — Expected Flow

> Script: `tools/demo.sh` · Record: `asciinema rec -c "bash tools/demo.sh" demo.cast`
> (A recorded session ships at [docs/assets/demo.cast](assets/demo.cast).)
> Hashes/IDs change every run — the *shape* below is the invariant.

## Expected flow (verified 2026-09-13; 9 steps — the bridge is now two-sided)

| Step | What happens | Expected output |
|---|---|---|
| 1 | `keygen` | agent identity minted; the run-seed stays in the shell only (the demo's throwaway sign-key is written inside its sandbox dir) |
| 2 | `run --input job.json --require-proof` | `run ok: True \| fee: ~1e-4..1e-3` |
| 3 | `export` | `snapshot: ~2.2KB \| plaintext body scan: 0` |
| 4 | `import` on a different node directory | `import ok: True \| agent: <id16>… \| memory nodes: 4 \| resumed session: 1` |
| 5 | `ledger-verify` + `memory --search "node1"` | `ledger-verify ok: True` · `memory recall: born on node1` |
| 6 | `python3 tamga_verify_mini.py <pkg>/ledger.jsonl` | `{"ok": true, ...}` — stdlib-only, no install (B2) |
| 7 | `python3 tamga_bundle.py <pkg> -o /tmp/ev` | `/tmp/ev/<pkg>-bundle.json + .md` — hand-to-counterparty (B4) |
| 8 | `python3 tamga_bootstrap.py project-head <pkg>` | chain head minted (D5) → encoded as a batch leaf (`TAMGA_PROJECT_HEAD_V1`); composition root printed (AT-022/023) |
| 9 | `python3 tamga_pugio_receiver.py foreign_anchor.jsonl` | a synthetic foreign anchor line verifies on OUR side — `SONUÇ: SAĞLAM` (AT-024, the receiver half of RFC-009; the demo's bridge story becomes two-sided) |

## Narration frame (if you're presenting)

1. "The agent is born and does **input-bound work** — the input hash is bound into the receipt."
2. "The machine dies; the agent travels in an **encrypted** package — the host cannot read the body."
3. "On a new host it **resumes where it left off** — identity and memory come with it."
4. "The receipt chain verifies on the destination — the claim 'this work happened' is now auditable."
5. "And the counterparty doesn't even need our code — a 200-line stdlib script, or a one-command evidence bundle."
6. "Step 8 is the bridge outward: the same chain head that `verify-mini` checked becomes a
   **leaf of someone else's batch** — a Starknet-anchored Merkle root. We prove the *shape*
   composes; what the foreign registry says about itself stays its own claim — presentation
   only, never borrowed trust. And the trap on the way there — felt notation dropping the
   leading zero — is pinned as a FAIL vector for everyone (upstream conformance PR #2)."

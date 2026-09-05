# 30-Second Demo — Expected Flow

> Script: `tools/demo.sh` · Record: `asciinema rec -c "bash tools/demo.sh" demo.cast`
> (A recorded session ships at [docs/assets/demo.cast](assets/demo.cast).)
> Hashes/IDs change every run — the *shape* below is the invariant.

## Expected flow (verified 2026-09-05)

| Step | What happens | Expected output |
|---|---|---|
| 1 | `keygen` | agent identity minted; seed goes to stdout only, never to disk |
| 2 | `run --input job.json --require-proof` | `run ok: True \| fee: ~1e-4..1e-3` |
| 3 | `export` | `snapshot: ~2.2KB \| plaintext body scan: 0` |
| 4 | `import` on a different node directory | `import ok: True \| agent: <id16>… \| memory nodes: 4 \| resumed session: 1` |
| 5 | `ledger-verify` + `memory --search "node1"` | `ledger-verify ok: True` · `memory recall: born on node1` |

## Narration frame (if you're presenting)

1. "The agent is born and does **input-bound work** — the input hash is bound into the receipt."
2. "The machine dies; the agent travels in an **encrypted** package — the host cannot read the body."
3. "On a new host it **resumes where it left off** — identity and memory come with it."
4. "The receipt chain verifies on the destination — the claim 'this work happened' is now auditable."

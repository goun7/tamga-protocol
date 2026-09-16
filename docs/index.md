<meta property="og:title" content="tamga-protocol — execution receipts for AI-agent outputs">
<meta property="og:description" content="Zero-protocol-tax verifier layer: deterministic re-execution, declared egress, three-verdict contract. No funding, no token, ever.">
<meta property="og:image" content="https://goun7.github.io/tamga-protocol/assets/social-preview.png">
<meta property="og:url" content="https://goun7.github.io/tamga-protocol/">

# tamga-protocol

**Execution receipts for AI-agent outputs — a zero-protocol-tax verifier layer.**
A receipt binds what an agent *did*, not what it *claims*: deterministic re-execution under a
WASI sandbox, declared egress, and a three-verdict contract (`rc0` GREEN / `rc1` RED /
`rc2` İNDETERMİNE — a check that never ran must never read as passed).

> Navigation page only — no claims live here; the binding documents are below.
> Single-language by design (like `PLAIN-TURKISH.md` is deliberately Turkish-first): this file
> is a pointer, not a document with a binding original.

- **Start here:** [README.md](https://github.com/goun7/tamga-protocol/blob/main/README.md) ·
  [Turkish README](https://github.com/goun7/tamga-protocol/blob/main/README.tr.md)
- **Reproduce everything:** [REPRODUCE.md](REPRODUCE.md) — one command:
  `bash tests/run_all.sh` (current control counts live in REPRODUCE.md and the READMEs —
  this page carries no numbers by design, so nothing here can go stale)
- **Architecture & why:** [ARCHITECTURE.md](ARCHITECTURE.md) ·
  [WHY-HASHCHAIN.md](WHY-HASHCHAIN.md) · [AGENT-GUIDE.md](AGENT-GUIDE.md)
- **Verify other people's proofs:** [capacity-attest](https://www.npmjs.com/package/capacity-attest)
  `tamga attest-verify` (AT-030) · epoch anchors `tamga epoch-verify` · delivery receipts
  `tamga verify-cr`
- **Specs:** RFC-001 (manifest) · RFC-002 (runner) · RFC-003 (ledger) · RFC-004 (context graph) ·
  RFC-005 (declared egress) · RFC-006 (agent net shim) · RFC-007 (schema rev. v0.2) ·
  RFC-008/009 (external receipt / external chain anchor — DRAFT)
- **Full document + language map:** [INDEX.md](INDEX.md) — every original, every twin, both
  directions, machine-generated.
- **Related work & differentiation:** [RELATED-WORK.md](RELATED-WORK.md)

Install: `pip install tamga-protocol` · PyPI [tamga-protocol](https://pypi.org/project/tamga-protocol/)
· License: MIT · No funding, no token, no paid infrastructure — ever.

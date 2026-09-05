# Tests

Run everything with one command:

```bash
bash tests/run_all.sh     # 18/18 controls, ~10 s on a laptop; CI runs it on every push
```

## Adversarial audits and benchmark (CI-hosted)

- `tests/audit7_embedded_chain.py` — embedded-chain attacks (A1 splice weak/strong,
  A2 tip-swap, A3 merkle-fold): simnet, no wasmtime; F25/F24 documented limits.
- `tests/audit8_node_cosign.py` — node-cosign layer tests (L1 closes F25).
- `tests/bench_runner_overhead.py` — runner-side overhead medians (evidence-only,
  no pass/fail).
- `tools/check_links.py` — markdown relative-target integrity (0 broken).
## Control families

| Family | What it proves |
|---|---|
| AT-001 — snapshot lifecycle + adversarial negatives | export → import → resume works; **intentionally-broken** fixtures (bad magic, tampered manifest, forged identity, rolled-back sessions, oversized snapshot) are all rejected with the expected reason codes |
| AT-002 — determinism / replay | same wasm + same input → byte-identical `stdout_sha256` across runs |
| AT-003 — ledger attack vectors | truncated and spliced chains → RED 14 (`ledger_broken`) |
| AT-004 — input-bound receipts | `input_sha256` lands in the receipt; distinct inputs → distinct fingerprints; >1 MiB → RED 10; `--require-proof` stamp verified runner-side; replay determinism |
| AT-005 — multi-format memory import | mem0/letta/zep/jsonl exports convert to `tamga-memory/1`; end-to-end import is idempotent (re-import adds 0); ADD-only merge across sources; >64 MiB and malformed sources → RED |
| Schema cross-validation | runner decisions ≡ `jsonschema` validation (34/34 fixtures) |
| Cosign / snapshot negatives | L1 policy enforcement, revocation-list rejections |
| Tokenomics + economy invariants | fee curve, threshold and fairness invariants hold under the deterministic simulator |

Negative fixtures: manifest attacks live in `tests/vectors/tc-a2…a6` (RFC-001 §7); snapshot attacks are built in-script by `tests/negative_snapshots.sh` (AT-001f).
a "fix" that makes them pass is itself a regression and fails the suite.

## CI

`.github/workflows/ci.yml` runs the full 18-control suite on `ubuntu-latest` with
wasmtime v48.0.1 (downloaded from the pinned release tarball) on every push to `main`.
The badge in the README links to the workflow.

## Evidence culture

Claims are bound to run logs (hashes + numbers, no loose "it works"). Failed and
adversarial runs are archived too. Vulnerabilities are **not** tested via public
issues — see [SECURITY.md](../SECURITY.md) for private disclosure.

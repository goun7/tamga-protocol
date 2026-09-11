# QUICKSTART — Tamga Protocol in 5 minutes

> Self-custodial, hash-chained work-receipt ledger for autonomous AI agents.
> Every claim below was executed on a clean venv before being written here.

## 0. Install

```bash
pip install tamga-protocol        # Python 3.10+, single dependency: PyNaCl
tamga --help                      # command overview (no engine needed)
```

The 67 MB wasmtime engine is **not** in the wheel. It is downloaded once,
SHA256-pinned, on your first `tamga run` — verification commands never need it.

Air-gapped host? Pre-place the pinned binary at either of the two accepted
locations and the downloader is skipped entirely (code path: `tamga_bootstrap`):
`~/.cache/tamga/bin/wasmtime` or `<site-packages>/tools/bin/wasmtime`.

## 1. Generate an agent seed (printed once, never stored)

```bash
tamga keygen
```

```json
{"ok": true, "op": "keygen", "agent_id": "4f83f2ac…", "seed_hex": "c4717ab8…",
 "note": "D3: seed not written to disk; store it safely"}
```

Keep `seed_hex` for the next step. Losing it means losing the agent identity.

## 2. Run a job (fee charged, receipt appended)

```bash
export TAMGA_KS_PASSPHRASE=quickstart-2026   # keystore passphrase (your choice)
tamga run ./my-pkg --seed <seed_hex>
```

```json
{"ok": true, "op": "run", "pkg": "my-pkg", "session": 1, "nodes": 3,
 "engine": "wasmtime-v48.0.1", "wall_ms": 115, "fee_sim": 2.279e-06,
 "stdout_sha256": "aa8a2cd1…"}
```

No package yet? Copy the demo: `cp -r tests/vectors/tc-net-demo ./my-pkg`
(from the repo) — it contains `tamga.json` + a tiny WASI-0.3 agent.

## 3. Verify the chain (no engine, no trust in the runner)

```bash
tamga ledger-verify ./my-pkg
```

```json
{"ok": true, "op": "ledger-verify", "lines": 1,
 "head": "9314bcdf…", "note": "chain tip verified (RFC-003 D7 draft)"}
```

Anyone with this JSON output can re-verify your chain independently.

## 4. Migrate the agent (sealed snapshot travels, key never on disk)

```bash
tamga export ./my-pkg -o snapshot.tsg --seed <seed_hex>
```

On the new host, prepare the package dir FIRST (same code: `tamga.json` +
`agent.wasm`) - import fails closed with `manifest_reject` if it is missing
(this is the A1 ownership boundary, verified 2026-09-10 on the published wheel):

```bash
mkdir -p ./my-pkg-restored && cp my-pkg/tamga.json my-pkg/agent.wasm ./my-pkg-restored/
tamga import snapshot.tsg ./my-pkg-restored
tamga ledger-verify ./my-pkg-restored       # chain resumed: lines=1, same head
```

```json
{"ok": true, "op": "import", "resumed_session": 1, "memory_nodes": 3,
 "note": "AT-001e: identity from keystore, memory from body — restored"}
```

## 5. If something misbehaves

```bash
tamga doctor          # install health: python / pynacl / wasmtime / verify-mini / bundle
tamga --version
```

## 6. Let someone verify you without installing anything

```bash
tamga verify-mini ./my-pkg/ledger.jsonl   # stdlib-only, no engine, no Tamga install
tamga bundle ./my-pkg -o evidence/        # one-file proof package (JSON + human summary)
```

The bundle carries the chain records, the manifest re-hash, and per-job
digests — the counterparty re-derives every claim offline. Full flow:
[docs/AGENT-GUIDE.md §8b](AGENT-GUIDE.md).

## 6b. Use it as a library (no CLI, no engine)

The four engine-free modules import directly from the published wheel:

```python
import tamga_verify_mini          # stdlib-only chain verification (verify(...))
import tamga_bundle               # evidence-bundle builder (build(...))
import tamga_validator            # manifest + record canonicalization (jcs(...))
import tamga_bootstrap            # pinned wasmtime fetch for tamga run
```

Verified 2026-09-11 against the published wheel (**0.2.0**, re-verified on **0.2.1**:
install → quickstart → ledger-verify → verify-mini → bundle all green on a clean venv).

## What just happened

- The job ran inside a **denied-by-default WASI sandbox** (no filesystem preopens, no network).
- Its **fee, stdout hash, and memory delta** were appended to a hash-chained ledger.
- The **agent identity + memory** traveled in one encrypted snapshot you can hold.
- Verification is **offline and third-party** — `ledger-verify` recomputes the chain.

## Next steps

- Threat model & architecture: [docs/ARCHITECTURE.md](ARCHITECTURE.md)
- Ledger spec: [RFC-003](RFC-003-ledger.md) · Runner spec: [RFC-002](RFC-002-runner.md)
- Full test evidence: [docs/TESTS.md](TESTS.md)
- Plain-language intro (Türkçe): [docs/PLAIN-TURKISH.md](PLAIN-TURKISH.md)

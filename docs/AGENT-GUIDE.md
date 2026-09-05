# Agent Developer Guide (v0)

> Every command below is proven in this repo's evidence logs and runs today.
> A Turkish deep guide exists internally; this is the English developer-facing version.

## 1. Mental model (2 minutes)

A Tamga agent is three things:

1. **Identity** — an ed25519 keypair. The seed **never rests on disk in plaintext**;
   it travels inside the encrypted keystore blob of a snapshot.
2. **Memory** — an ADD-only context graph (nodes are never rewritten or deleted).
3. **Ledger** — a hash-chained receipt log; every run is a `charge` (fee + metering).

The code (`agent.wasm`) travels **separately** from these three. A snapshot carries
identity + memory + ledger; code is installed on each node. This separation is the
portability invariant — it is why a receiving node can verify what it is about to run.

## 2. Prerequisites

```bash
python3 --version      # proven on 3.14; 3.11+ expected
pip install pynacl     # the only runtime dependency
# runner engine: wasmtime v48.0.1 (pinned, tools/bin/wasmtime)
# agent target:  WASI 0.3 / component  (Rust: wasm32-wasip2)
```

## 3. Your first agent (5 minutes)

```bash
# 1) code — minimal WASI component (example: tests/agent-src/, Rust)
cargo build --release --target wasm32-wasip2

# 2) manifest — copy tests/vectors/tc-a1/tamga.json, change package.name
#    schema: specs/manifest-0.1.0.schema.json (RFC-001 v0.1-FINAL)

# 3) sign and validate
python3 tamga_validator.py keygen tests/keys/alice
python3 tamga_validator.py sign  <pkg>/tamga.json <pkg>/agent.wasm tests/keys/alice/seed.hex
python3 tamga_validator.py validate <pkg>            # until ACCEPT

# 4) run — agent identity from stdout only (never written to disk)
AGENT_SEED=$(python3 tamga_runner.py keygen | python3 -c 'import sys,json;print(json.load(sys.stdin)["seed_hex"])')
export TAMGA_KS_PASSPHRASE="..."                      # your choice
python3 tamga_runner.py run <pkg> --seed "$AGENT_SEED" --note "first run"
```

The `run` output includes `session`, `wall_ms`, `cpu_saat`, `ram_gb_sn`, `io_mb`,
`fee_sim`, `stdout_sha256` — all chained into the receipt.

## 4. Manifest fields — quick reference

| Field | Rule | Limit |
|---|---|---|
| `spec_version` | `"0.1.0"` pinned | anything else → RED |
| `package.name` | `[a-z0-9][a-z0-9-]{2,31}` | canonical owner |
| `package.code.wasm_sha256` | 64-hex | must match the file exactly |
| `package.code.target` | `"wasi-0.3/component"` pinned | — |
| `runtime.min_proof_level` | P0/P1/P2 | — |
| `runtime.limits` | memory_mb [16,4096] · cpu_ms_per_run [1,60000] · io_mb_per_run [0,1024] | integers; bool/string → RED |
| `capabilities` | ⊆ {fs, net, clock, env, random}, ≤5 | fs/net default-deny in v0 |
| `payment.schemes` | `["tamga-sim/1"]` | simnet; real value is Phase 4 |
| `signature` | ed25519 over JCS with `sig` emptied | 128-hex |

## 5. Input-bound work (receipts that mean something)

```bash
python3 tamga_runner.py run <pkg> --seed "$AGENT_SEED" \
    --input job.json --require-proof
```

- `--input` (≤1 MiB): the input hash goes into the receipt → the same job is
  re-runnable and provable; oversize → rejected before execution.
- `--require-proof`: your agent's stdout must end with a `TAMGA:<fnv1a64>` stamp over
  its own output. The runner verifies it before signing the receipt.
  (The example agent in `tests/agent-src` implements this in Rust.)

## 6. Accounting

```bash
python3 tamga_runner.py grant <pkg> 0.01 "dev-funding"   # test balance
python3 tamga_runner.py ledger <pkg>                     # balance summary
python3 tamga_runner.py ledger-verify <pkg>              # chain verification
```

A chain-less package verifies as `ok=true, lines=0` (an empty chain is legal); a broken
chain → reason 14. Every record is `seq` + `prev` + `h = sha256(prev | jcs(record))` —
changing any byte breaks the chain.

## 7. Migration (the heart of the project)

```bash
python3 tamga_runner.py export <pkg> -o snapshot.tsg --seed "$AGENT_SEED"
# target node: code must be pre-installed (code travels separately!)
python3 tamga_runner.py import snapshot.tsg <new-pkg>
```

- The snapshot is encrypted: a host without the passphrase cannot read the body.
- Import rejections protect you: 7 (too large), 8 (session rollback), 9 (identity
  forgery), 14 (broken embedded chain), 17 (merkle mismatch), 18 (ownership mismatch).
- If you operate a node and want chain claims cosigned: `import --cosign-policy L1
  --node-trust <file>` (node key: `keygen-node <dir>`; default policy is L0).

## 8. Memory bridge

```bash
python3 tamga_runner.py memory <pkg> --import-json lessons.json   # ADD-only merge
python3 tamga_runner.py memory <pkg> --search "keyword"
```

Re-importing the same source is idempotent (existing entries are skipped).

## 9. Pre-PR checklist

- [ ] `tamga_validator.py validate <pkg>` → ACCEPT
- [ ] `run` → ok; `fee_sim` sane; `stdout_sha256` produced
- [ ] `ledger-verify` → ok
- [ ] export → fresh directory → import → same `agent_id`, session resumed
- [ ] limits fit your scenario (over-generous limits spend the agent's own budget)
- [ ] capabilities = smallest set (if you don't need fs/net, don't declare them)

## 10. Honest limits (v0)

- **simnet:** amounts are `*_sim`; real-value movement is Phase 4 (double-gated).
- **Single machine:** without cosign, an embedded chain on a fresh node is agent-attested.
- **`cpu_ms_per_run` is a wall-clock timeout:** on a heavily loaded host even a trivial
  agent can hit reason 11 — that is scheduling noise, not metering.

> English twin of the Turkish-BORN original (docs/MIGRATION-DEMO.md). The Turkish file is the authoritative original; this translation exists for foreign readers. On any divergence, the Turkish governs.

# MIGRATION-DEMO — migrating a foreign source-code into the envelope (2026-09-15 overnight)

**Subject:** `b3sum` v1.8.7 — the BLAKE3 team's **published, not-ours, real** CLI
(MIT OR Apache-2.0, github.com/BLAKE3-team/BLAKE3). The aim: prove RFC-008's "göç kalptir"
("migration is the heart") claim **outside** our-own-template: until 2026-09-15 this sentence
was built only on our own `templates/agent.wasm`.

## Three-honest-steps (the scenario itself = `scripts/migrate_ext_b3sum.sh`)

1. **Build-truth.** `cargo build --release --target wasm32-wasip2` produces the **component
   directly** (header `0d 00 01 00`) — `wasm-tools component new`/adapter not even needed. Note:
   the runner's component-sniff (`tamga run`, rc13 gate) accepts foreign compiler-output as-is;
   template-dependency NONE.
2. **Sandbox-truth (the most-teaching part).** Stock b3sum **does not run**: the instant it
   tries to set up a thread-pool, wasmtime returns `ENOTSUP (os error 58)` and the process drops
   **fail-loud**. Not a deficiency — a **contract**: no-running-at-all over half-silent-degradation.
   Patch inventory falls to 3 points, all standing in source tagged `[tamga-migration-patch]`:
   (a) `mmap+rayon` feature-coupling untied, (b) thread-pool setup removed (same body runs inline),
   (c) fast-path descends to plain reader. **Not-one-line-touched in the hash-logic.**
3. **Envelope-truth.** Manifest (pinned `wasm_sha256`) → `keygen` → `sign` → `validate` →
   `run --input` → `ledger-verify` → `export`. Three-way parity: bare-wasm stdout == envelope
   stdout == reference-value. The sentence: **the envelope does not change the engine's result — it only adds proof.**

## Measurements (1 MB input, median-of-15, this-machine; raw: `.evidence/MIGRATION-DEMO/2026-09-15/METS.txt`)

| layer | time | what-it-measures |
|---|---|---|
| native x86 `b3sum` | 9.7 ms (min 3.0) | baseline |
| bare wasmtime v48.0.1 | 26.0 ms (min 20.8) | wasm-tax ≈ 2.7× native |
| tamga envelope-net | 37.6 ms | +11.6 ms **protocol-tax** = manifest-validate + ledger-append + receipt-seal + stdout-disk + state-IO (Python-startup 108.5 ms subtracted) |

`fee_sim` = `cpu_saat×0.002 + ram_gb_sn×0.0005 + io_mb×0.001` (simnet constants, pinned in RFC-003 §7; real prices are the Phase-2 pilot gate) — 2026-09-16 reproduction run: **1.5552e-05** (wall_ms 428; the dominant term is ram_gb_sn, which moves with every run's timing). Stale-note: the document's prior figure (2.39e-07) was a single snapshot transcribed from a since-deleted original run and could not be re-derived — replaced by formula + fresh value, per house rule.

## What-It-Proves / What-It-Cannot-Prove

**Proves:** (i) the migration-pipeline runs end-to-end on third-party code; (ii) the sandbox's
constraints appear as audible-errors (the engine-side form of the E-14 principle); (iii) result
parity — envelope-immutability at the byte level.
**Cannot prove:** pilot. Migration-over-foreign-code is not a foreign **user choosing us**; the
10-point pilot-gap does not melt with this document — it will not be written as if it melted.
Also, build-reproducibility depends on the toolchain pin (AT-032's rustc-patch-drift class holds
for foreign code too; therefore the PARITY claim is between bare/envelope stdout,
not "byte-for-byte-same-wasm on every-machine").

## Do-it-yourself (two-commands)

```bash
bash scripts/migrate_ext_b3sum.sh          # klon→yama→build→zarf→parite (cargo şart, bağıra-bağıra çıkar)
# ya da sadece doğrula:
sha256sum <(echo -n abc) ; # b3sum("abc") = 6437b3ac38465133ffb63b75273a8db5... (wasm==native teyitli)
```

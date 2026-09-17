# Reproduce everything yourself

Every claim on this repository is backed by a command you can run. No trust in
our CI required — clone, run, compare.

## 0. No clone? Install the wheel and run the same checks

```bash
pip install tamga-protocol        # published: pypi.org/project/tamga-protocol
tamga --version && tamga doctor   # engine-free paths report SAĞLIKLI
```

Verification commands (`ledger-verify`, `verify-mini`, `bundle`, `explain`) work
without the 67 MB engine; it downloads once, SHA256-pinned, on first `tamga run`.
Last verified from the published wheel (**0.2.11**, live PyPI): **2026-09-17** —
quickstart E2E + `epoch-verify --selftest` + synthetic-keccak-leaf proof + live E-15
wrong-chain preflight (rc2, never reads green) + `liveness-probe` dead-port probe + the
whole-CLI zero-argument matrix (8 commands — now including `attest-verify` and `verify-cr`:
message-RED, no traceback, no vacuous green) + USAGE version string == installed version,
10/10 from a clean venv installed by version from the live index (`bash tools/fresh_audit.sh
--version 0.2.11`).
(0.2.4→0.2.5 shipped `epoch-verify` in the wheel; 0.2.5→0.2.6 hardened `explain` bad-input to
message-RED; 0.2.6→0.2.7 extended that rule to the whole CLI (E-14, reason_code 19) and shipped
the CR v0.1 cross-proof control; 0.2.7→0.2.8 turned chain-identity from luck into policy (E-15
eth_chainId preflight — the wheel itself was caught reading a mainnet endpoint for a Sepolia contract, INDETERMINE by accident, now by design) and added the liveness probe — which 0.2.9 then promoted to the console (`tamga liveness-probe`, verified on the index-installed wheel by the monthly fresh-audit ritual itself, 10/10) — all three found by installing the live wheel and using it as a stranger would.)

## 0b. The monthly stranger ritual (2026-09-15+)

`bash tools/fresh_audit.sh` — installs the LIVE PyPI wheel into a throwaway venv and uses
it as a stranger would (doctor, zero-arg matrix, selftests, the E-15 wrong-chain probe, E2E
when the engine is cached). CI runs it on the 20th of each month
(`.github/workflows/fresh-audit.yml`, own badge, İNDETERMİNE-aware). First pass: 9/9 on 0.2.8.

## 1. The full acceptance suite (52 controls, ~20 s)

```bash
git clone https://github.com/goun7/tamga-protocol && cd tamga-protocol
bash tests/setup.sh && pip install -r requirements.txt   # once: pinned wasmtime + pynacl
bash tests/run_all.sh
```

Expected tail: `RESULT: 53 PASS, 0 FAIL` (58 with `RUN_SLOW=1`). Last verified here: **2026-09-17** on **0.2.11**: full suite re-proved on HEAD (58/58 slow, idle machine), and the published wheel was
installed from live PyPI by the stranger ritual (`bash tools/fresh_audit.sh`) — 10/10 including the console
`tamga liveness-probe` dead-port check. The evidence log lands in
`.evidence/REGRESYON/<date>/run_all-*.log`).

Slow extra controls (cross-host c30 + AT-019 wheel + AT-020 self-pilot + AT-026 wheel-completeness — not in CI):

```bash
RUN_SLOW=1 bash tests/run_all.sh     # → 56 controls (57/57 on this host)
```

Prerequisites the slow controls declare honestly (a fresh clone is NOT a bug — it is a missing
precondition and each one says so):
- c30 (the 31 s cross-host wall control) needs the gitignored local simnet fixtures
  (`tests/simnet/node-C/` + `seedC.hex`) — without them it prints `[SKIP]` and the run reads 52/52.
- AT-019 builds/uses the wheel from `dist/` (gitignored) — if no wheel exists and the `build`
  package is importable it builds one on the spot; if neither, it prints `[SKIP]`.
- AT-026 needs `python3 -m build` (`pip install build`); it builds into an isolated temp dir
  (never deletes an existing `dist/`).

## 2. Verify a chain without installing anything (stdlib-only)

```bash
# the chain is produced first (one grant), then verified with no engine, no network:
python3 tamga_runner.py grant tests/vectors/tc-net-demo 0.01 tgs >/dev/null
python3 tamga_verify_mini.py tests/vectors/tc-net-demo/ledger.jsonl
# → {"ok": true, ...}  — no wasmtime, no network, no pynacl needed
```

`tamga_verify_mini.py` imports nothing outside the stdlib — block `nacl` before import
and it still loads and still verifies the chain. Verified 2026-09-18 from a fresh clone
in a throwaway venv, as a stranger would.

## 3. Build a third-party evidence bundle

```bash
python3 tamga_bundle.py tests/vectors/tc-net-demo -o /tmp/evidence
# → /tmp/evidence/tc-net-demo-bundle.json + .md (records copied byte-equal)
```

## 3b. The stdlib-only subset, with PyNaCl deliberately blocked

```bash
python3 tools/verify_lite.py
```

Four checks (mini-verifier, pairing hash, explain chain-integrity, nacl-blocker
proof) run with `import nacl` actively forbidden — the counterparty path really
is stdlib-only, and this command is the proof.

## 4. Cross-validate the schema (60/60)

```bash
python3 -m venv .venv-jsonschema && . .venv-jsonschema/bin/activate
pip install jsonschema && bash tests/crossval.sh && deactivate
```

## 5. Explain a receipt in plain language

```bash
python3 tools/explain.py receipt.json            # dx402 receipt → labeled human summary
python3 tools/explain.py --charge ledger.jsonl 2 # chain record N → same
```

Derived relations are recomputed, never assumed; the chain-integrity line re-derives
the record hash (RFC-003 D5) and prints DOĞRULANDI / EŞLEŞMİYOR.

## 5b. Verify the public pairing fixture in one command

```bash
python3 tools/verify_pairing_bundle.py    # charge-hash re-derivation + chain-context
```

## 6. The adversarial families

| Family | Command | What it proves |
|---|---|---|
| Audit-11 ledger-bomb | `bash tests/audit11_ledger_bomb.sh` | 50 MB-line + grant-cap RED, bounded RSS |
| Audit-15 state hardening | `bash tests/audit15_state_hardening.sh` | corrupt state → fail-closed, tamper-inert chain |
| Audit-16 node revocation | `bash tests/audit16_revocation_gap.sh` | revoked-node import RED (key-theft closure) |
| DX402 pairing | `bash tests/at012_dx402_pairing.sh` | canlive vector: paymentId/EIP-712/CID roundtrip |

Each script exits 0 on success and prints `RESULT: N PASS, 0 FAIL`.

## What we cannot hand you (honest limits)

- **Pilot evidence is private**: the #3379 consented-delivery artifacts involve a
  counterparty's data; the *procedure* is public, the payload is not.
- **CI proves our host**: your machine is the stronger test. If any command above
  fails on a clean clone, that is a bug — open an issue with the log tail.

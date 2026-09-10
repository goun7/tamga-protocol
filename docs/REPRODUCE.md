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
Last verified from the published wheel: **2026-09-10** (end-to-end log:
`.evidence/QUICKSTART-PYPI/2026-09-10/`).

## 1. The full acceptance suite (40 controls, ~20 s)

```bash
git clone https://github.com/goun7/tamga-protocol && cd tamga-protocol
bash tests/setup.sh && pip install -r requirements.txt   # once: pinned wasmtime + pynacl
bash tests/run_all.sh
```

Expected tail: `RESULT: 40 PASS, 0 FAIL`. Last verified here: **2026-09-10** (40/40). The evidence log lands in
`.evidence/REGRESYON/<date>/run_all-*.log`.

Slow extra control (cross-host, simnet fixtures — not in CI):

```bash
RUN_SLOW=1 bash tests/run_all.sh     # → 41 controls
```

## 2. Verify a chain without installing anything (stdlib-only)

```bash
python3 tamga_verify_mini.py tests/vectors/tc-net-demo/ledger.jsonl
# → {"ok": true, ...}  — no wasmtime, no network, no pynacl needed
```

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

## 4. Cross-validate the schema (55/55)

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

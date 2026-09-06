# Audit Gate — the 8 steps every change passes

No commit lands without passing the gate; if the gate is red, there is no commit —
fix, re-run, repeat:

1. `python3 -m py_compile` — every touched `.py`
2. `bash tests/run_all.sh` → 19/19
3. Negative vectors: AT-001f (3 expected-RED + 1 precondition control) + AT-003 (6/6) — expected-RED fixtures stay red
4. Schema cross-validation: 34/34
5. New code → at least one negative vector (unexpected-ACCEPT test)
6. Evidence log: hashed run logs with numbers only; no unnecessary content
7. Security self-review lines: injection, read-only sources, privacy scan, back-compat
8. Privacy: no personal data enters the repo (gitignore + plaintext scan)

## Why a gate

The project's rule is: an autonomous step may not *claim* "correct, complete,
vulnerability-free" without runnable evidence. The gate converts that claim into
commands whose output is archived.

## Disclosure

Found a vulnerability? Do **not** open a public issue — see [SECURITY.md](../SECURITY.md).

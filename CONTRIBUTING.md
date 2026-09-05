# Contributing

Thanks for your interest in Tamga Protocol. The rules are short and strict:

## 1. Every change = tests + evidence

A pull request must pass the [audit gate](docs/AUDIT-GATE.md): 18/18 controls, negative
fixtures stay red, and any new behavior ships with at least one adversarial test.
"We tested it manually" is not evidence — the suite is one command and ~10 s.

## 2. Scope and gates

The roadmap is gate-based: Phase 2 (hardening) is open; Phases 3–4 (network, real
value) are human-gated and out of scope for drive-by PRs. If your change touches
formats (manifest/ledger/snapshot), open an issue first — those schemas are frozen
pending a written RFC errata.

## 3. Code style

- Python stdlib + PyNaCl only for the core runner/validator (zero-dependency principle);
  any new dependency needs an RFC + rationale.
- Comments/docstrings: English for new code (legacy Turkish comments are being
  internationalized — help welcome).

## 4. Security

Do **not** open public issues for vulnerabilities. Follow [SECURITY.md](SECURITY.md)
for private disclosure.

## 5. Licensing

Apache-2.0. By contributing you agree your contributions are licensed under it
(patent grant included).

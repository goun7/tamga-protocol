# Contributing

Thanks for your interest in Tamga Protocol. The rules are short and strict:

## 1. Every change = tests + evidence

## Code conventions (what reviewers check)

- Every rejection returns a one-line JSON receipt with a `reason_code` from the
  taxonomy in `docs/ARCHITECTURE.md §7` (code-extracted); argument errors are
  `parse_error` (1), never chain-integrity codes.
- Chain verification has exactly one implementation (`_verify_chain` in
  `tamga_runner.py`); do not inline the hash loop elsewhere.
- Key material is created atomically 0600 (`_secure_open` pattern); the agent
  seed never touches disk (D3).
- User-facing strings are English; frozen Turkish JSON field names stay until a
  versioned RFC changes them.
- Every behavioral change updates: the suite (a control or a negative vector),
  `docs/TESTS.md`, and — if a documented limit moves — the honest-limits notes.

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

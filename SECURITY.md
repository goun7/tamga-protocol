# Security Policy — Tamga Protocol

## Supported versions

| Version | Supported |
|---|---|
| v0.1.0-alpha | ✅ (simnet — experimental, do not use with real value) |

## Reporting a vulnerability

**Do NOT open a public issue for security problems.**

Email: use the GitHub Security Advisories feature ("Report a vulnerability" on the
Security tab) — private by default.

Include: affected component (runner/validator/format), a minimal reproduction, and
(when possible) a negative test showing the expected-RED that currently passes.

## Scope notes (honest envelope)

- This is **simnet** software: all amounts are `*_sim`; nothing here moves real value.
- Known, documented limits (in-use privacy / seed in host RAM, single-node ledger,
  64 MiB snapshot envelope) are design limitations, not vulnerabilities — but if you
  find a way to break them *earlier* than the documented phase, that IS a vulnerability.
- Findings are tracked as an audit ledger with numbered rounds; fixes require an
  evidence log (hashes, numbers) — same culture as the public test suite.

## Hardening promises

- Secrets (agent seed, keystore) never rest on disk in plaintext.
- Inputs are size- and type-checked before execution; run artifacts are cleaned up.
- The runtime is default-deny: no sockets, no filesystem preopens, no host env.

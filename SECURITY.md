# Security Policy — Tamga Protocol

## Threat model in one paragraph

Tamga protects an agent's identity and history against the operator of the machine
it runs on, under one assumption spelled out in the docs: the user passphrase is
never stored on the host. Scope notes: only the AGENT seed derived from that
passphrase is guaranteed to never rest on disk; operator/node keys written by
`keygen-node` and the validator's keygen are 0600 plaintext files by design, and
the node-side memory file (`state.json`) intentionally keeps memory TEXT in
plaintext at rest — confidentiality of memory at rest comes from snapshot
encryption, not from the state file. Data at
rest is sealed with scrypt + XChaCha20-Poly1305; history is a hash-chained ledger
(optionally counter-signed by a separate node key under L1 policy). What Tamga
explicitly does NOT defend against: an adversary who knows the user passphrase
(they can mint internally-consistent state — see the F25 analysis in
docs/RFC-002-runner.md), a compromised wasmtime engine, or the host exfiltrating
secrets during an active run. These limits are design-enforced, tested
(18-control suite + adversarial audits in CI), and documented rather than hidden.

## Supported versions

| Version | Supported |
|---|---|
| v0.1.0-alpha | ✅ (simnet — experimental, do not use with real value) |

## Reporting a vulnerability

**Do NOT open a public issue for security problems.**

Use the GitHub Security Advisories feature ("Report a vulnerability" on the
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

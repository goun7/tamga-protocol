# Design-partner program (v0.1.0-alpha)

Tamga Protocol gives AI agents a portable, encrypted, tamper-evident memory +
work-receipt package: the machine dies, the agent resumes on another node, and
its ledger proves the work actually happened.

We are looking for **2–3 design partners** for the v0.1 → v0.2 cycle.

## What a partner gets (free, first three)

- **Migration to Tamga, done by us** — we analyze your current agent-memory
  source (PostgreSQL/SQLite dump, Mem0 / Letta / Zep export-JSON, or plain
  JSON-lines), build the schema mapping, and deliver an encrypted Tamga snapshot
  with a restore-verification report (node/edge counts, hash check, 0 plaintext
  leaks in the snapshot body). Target: 10 business days from kick-off.
- **A seat in the freeze loop** — 30 minutes per week for four weeks; your
  feedback feeds RFC v0.2 decisions (node-cosign policy, declared egress,
  billing fields) *before* they freeze.
- **"First production user" status** — plus a lifetime 20% discount on future
  support/managed-node services.

## What we ask

- One weekly feedback call during the four weeks.
- Permission to describe the engagement as a case study — **your data stays
  yours**: only counts and architecture are described, never content.
- Tolerance for alpha-quality edges: this is simnet-grade software, honestly
  labeled.

## Honest limits (read before applying)

- The agent seed never touches disk; **your passphrase is yours** — we cannot
  store it, and a lost passphrase means an unrestorable snapshot (stated
  up-front, accepted in writing).
- v0.1 has no real payments and no network egress inside the sandbox; memory
  import and export, the hash-chained ledger, and the migration path are the
  production surface.
- Node-side `state.json` keeps memory text in plaintext (it is a working copy);
  confidentiality at rest is the snapshot's job. See SECURITY.md for the full
  threat model.

## How to apply

Open a GitHub issue titled `[pilot] <your project>` describing: what your agent
does, what memory store it uses today, and roughly how many records. We reply
with the migration-scope questionnaire. (Security issues are NOT this channel —
see SECURITY.md.)

## Why Tamga (the one-line positioning)

Mem0/Letta/Zep hold memory but don't make it portable — the vendor holds the
key and there is no audit trail. ERC-8004 pins trust but doesn't carry state —
when the agent dies, the memory evaporates. x402 moves payment but doesn't
prove the work happened. Tamga is the missing piece: identity + memory +
receipts, sealed, owned by the user, movable.

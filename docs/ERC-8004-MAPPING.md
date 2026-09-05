# ERC-8004 ↔ Tamga Mapping (Phase-3 design note)

> Status: DESIGN NOTE — no code or RFC change. Taken up together with RFC-003 v0.2 when
> the Phase-3 trigger (external demand signal) fires. Source: ERC-8004 draft as of
> 2026-09; the ERC may change before Final — wobbly points are marked.

Ecosystem scan (accessed 2026-09-05):
- ERC-8004 is still **Draft** (created 2025-08-13); the registration-file schema in
  this mapping matches the draft's `type: ...#registration-v1` structure, including
  the optional `x402Support` flag.
- x402 is now a Linux Foundation project (x402 Foundation, operational launch
  announced 2026); its public dashboard reports 75.41M transactions, $24.24M volume,
  94.06K buyers and 22K sellers over the last 30 days.
- Sources: <https://eips.ethereum.org/EIPS/eip-8004> · <https://x402.org> ·
  wasmtime v48.0.1 confirmed as the upstream latest release (GitHub API, 2026-09-05) —
  the RFC-002 pin is current, not stale
- Memory frameworks the AT-005 importer targets (PyPI, accessed 2026-09-05):
  mem0ai 2.0.20 · letta 0.16.8 · zep-cloud 3.28.0 — the importer is format-based
  (not version-pinned) and is regression-tested against these export shapes.

## 1. How the two protocols differ

| | ERC-8004 | Tamga |
|---|---|---|
| What it sells | **discovery + trust anchor** (on-chain identity/reputation/validation records) | **portable state** (identity+memory+ledger in one encrypted snapshot) |
| State model | on-chain minimal (tokenId, URI); files off-chain | off-chain encrypted snapshot + hash-chained ledger |
| Payments | out of scope (compose with x402) | v0 simnet; Phase 3 x402/L1 channels |

They are not competitors: an ERC-8004 registration is a **trust anchor pointing into**
Tamga manifests/snapshots; Tamga's receipt chain feeds verifiable evidence into
ERC-8004 Validation hooks (stake-backed re-execution, TEE oracles).

## 2. registration-v1 ↔ Tamga mapping

| registration-v1 field | Tamga source | Note |
|---|---|---|
| `type` | `"agent"` | fixed |
| `name` | manifest `package.name` | pattern-compatible |
| `description` | one-line primitive summary | — |
| `services[]` | none in v0; A2A/MCP endpoints in Phase 3 | empty array is valid |
| `x402Support` | `false` (v0) → `true` after the Phase-3 x402 decision | x402 ecosystem momentum (dashboard, 2026-09-05): 75.4M tx / $24.2M volume / 94K buyers in the last 30 days — network-level, not Tamga's |
| `active` | snapshot exists + ledger-verify ok | "active" = verifiable chain endpoint |
| `supportedTrust` | `crypto-economic` (node-cosign) · `tee-attestation` (Phase 3) · `reputation` (ERC-8004) | v0 supports L0 only → declares nothing (honesty) |
| `agentRegistry` | none (v0 is not on-chain) | Phase 3: `eip155:{chainId}:{registry}` + tokenId |
| *(proposed extension)* `tamgaProofLevel` | manifest `runtime.min_proof_level` | schema extension discussion belongs to Phase 3 |
| *(proposed extension)* `tamgaLedgerHead` | latest `h` (64-hex) | off-chain URI preferred — per-run on-chain writes are wasteful |

## 3. Direction 2: evidence Tamga feeds into ERC-8004 Validation

- **Stake-backed re-execution:** same `agent.wasm` + limits → same `stdout_sha256`
  (deterministic class) lets a validator cross-check a run against the receipt's
  metering evidence.
- **Billing-fairness tension (OQ-8):** wall-clock metering under host load can swing
  the same job's fee by orders of magnitude; median-of-N window billing is the Phase-2
  proposal.
- **TEE oracle:** node-cosign attestation field (Phase 3).
- **Reputation:** the hash-chained charge history is the verifiable substrate under any
  reputation signal; forging it requires seed ownership (closed by cosign L1/L2).

## 4. Sector notes (ordered by proximity to today's shape)

1. **Enterprise agent-service SLA receipts** — metered, evidence-backed charge records; closest fit.
2. **GDPR art.-20 data portability** — the encrypted snapshot export is the technical counterpart; art.-32 at-rest encryption already holds.
3. **RWA** — primitives transfer genuinely (custodian counter-signature ↔ possession ledger; deterministic replay ↔ auditor replication) but requires regulatory identity + a public-chain anchor — beyond current gates, no reference customer. Decision: no pivot; kept on the Phase-4+ horizontal-expansion ledger.
4. **Robotics/edge anti-fraud** (deterministic replay) — secondary, watchlist.

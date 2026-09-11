# Node Discovery — Phase-3 Design Note (ERC-8004-aligned)

> Status: DESIGN NOTE — no code or RFC change. Phase-3 is TRIGGER-GATED (external
> node count, pilot revenue, simulation thresholds — ROADMAP); this note freezes the
> *shape* of node discovery so the trigger, when it fires, finds the thinking done
> (the RFC-009 discipline: math/design now, const/code at the gate).
> Sources re-verified 2026-09-11: ERC-8004 authoritative front-matter (ethereum/ERCs
> `ERCS/erc-8004.md`) — still **Draft**; mapping below follows `registration-v1`.

## 0. What exists today (the honest baseline)

- **Node identity**: `keygen-node` — operator certificate key, 0600, node_id (ARCHITECTURE §5)
- **Node-cosign L1**: node-certified receipts, opt-in (OQ-1); `--node-trust` = simple-file
  trust list (OQ-2: hand-maintained until ERC-8004 Final; then on-chain migration)
- **Revocation**: `--node-revoked` — signatures of listed nodes rejected at import even
  if still trusted (OQ-3, Audit-16); standalone `ledger-verify` stays policy-agnostic
- **None of this is discovery.** Today a client learns about nodes out-of-band.

## 1. The gap Phase-3 closes

| Question | Today (Phase 2) | Phase-3 target |
|---|---|---|
| How do I find a node? | out-of-band | ERC-8004 Identity Registry (on-chain handle → registration file) |
| How do I trust one? | `--node-trust` file | + Reputation Registry signals fed by receipt-chain evidence |
| How is work checked? | our hash-chain alone | + Validation Registry hooks (staker re-run / TEE oracle / zkML — pluggable) |
| What does a node claim? | prose | `registration-v1` file with `x402Support`/`supportedTrust` fields |

## 2. Proposed mapping (manifest ↔ registration-v1)

Tamga's manifest already carries the fields a registration file needs; the bridge is
field-projection, not schema surgery:

| registration-v1 field | Tamga source | Notes |
|---|---|---|
| agent identity/handle | manifest `agent_id` (ed25519 verify key) | ERC-721-mintable handle resolves to the registration file |
| capabilities | manifest `caps` + `runtime` (net egress, byte caps) | capability claims stay signed by the author key |
| `x402Support` | presence of RFC-008 `external_receipt` (rail: x402) + RFC-007 `delivery_hash` | payment support declared, never *promised* (scope sentence) |
| `supportedTrust` tiers | cosign-policy L0/L1 today; TEE separate field (OQ-4, Phase 3) | tiers map to ERC-8004's pluggable trust models |
| evidence | receipt chain bundle (`tamga bundle`) | off-chain evidence, on-chain signal — Reputation/Validation read APIs (`getResponseCount`, `getResponseByIndex`) consume it without schema changes |

Key honesty rule carried over from RFC-008: **the registration file is a CLAIM, the
receipt chain is the EVIDENCE** — the registry never becomes the source of truth for
what a node did; it indexes what a node says and points at verifiable proof.

## 3. Revocation migration (OQ-2's second half)

- Today: `--node-trust` + `--node-revoked` files (manual, auditable, zero-infra).
- At ERC-8004 Final: the trust list migrates to the Identity Registry; revocation
  semantics stay **import-time policy** (Audit-16's architecture note: chain math is
  policy-agnostic; revocation is a policy decision, not a chain property).
- Migration is one-way and additive: the file path remains as the fallback for
  air-gapped hosts (the D12 dual-read pattern, applied to trust).

## 4. What stays gated (no order-of-operations debt)

- **On-chain anything**: gated on ERC-8004 reaching Final (Draft today; wobbly points
  in the mapping are marked in ERC-8004-MAPPING.md).
- **TEE trust tier**: separate field, never mixed into the signature field (OQ-4);
  cloud enclave pilot (Nitro/SEV-SNP, watch Intel TDX) — Phase-3 item.
- **Real micropayments**: x402 vs L1-channel decision by prototype measurement;
  honest caveat from the ROADMAP: x402 volume is roughly half test traffic —
  real-commerce share must be measured before v1.
- **Node-alım-kapısı (I4)**: external-node call threshold = median node revenue ≥
  node cost (economy_sim: λ ≥ 2000 jobs/month/node region); below it, founder node carries.

## 5. Test family preview (AT-022 candidate, at the trigger)

When Phase-3 fires, the acceptance family mirrors this note: registration-projection
determinism (same manifest → same registration file bytes), trust-list migration
one-wayness, revocation-still-import-time, and reputation-evidence round-trip
(bundle → registry read API shape). No test is written now — the gate decides, and
this note is the design it will test against.

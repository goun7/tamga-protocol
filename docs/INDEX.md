# docs/ — Reading Order & Index

27 documents, one design culture: **every claim is backed by a command**. This index
gives the intended reading paths — pick by role; within each path, order matters
(each document assumes the ones above it).

## The five-minute path (deciders)

1. [README.md](../README.md) — the gap between Memory/Trust/Payment layers; what Tamga is
2. [WHY-HASHCHAIN.md](WHY-HASHCHAIN.md) — why a hash chain and where a Merkle tree is the right tool
3. [REPRODUCE.md](REPRODUCE.md) §0 — install the wheel, run the same verifications we do (no clone needed)

## The implementer path (agent authors)

1. [QUICKSTART.md](QUICKSTART.md) — `tamga quickstart` to a signed first run
2. [AGENT-GUIDE.md](AGENT-GUIDE.md) — command set, packaging, lifecycle
3. [RFC-001-manifest.md](RFC-001-manifest.md) → [RFC-002-runner.md](RFC-002-runner.md) → [RFC-003-ledger.md](RFC-003-ledger.md) — the frozen v0.1 core: what a package is, how it runs, how the ledger math binds
4. [RFC-005-declared-egress.md](RFC-005-declared-egress.md) + [RFC-006-agent-net-shim.md](RFC-006-agent-net-shim.md) — networking as a *declared capability* (the default-deny vs real-agent resolution)
5. [PLAIN-TURKISH.md](PLAIN-TURKISH.md) / [README.tr.md](../README.tr.md) — Türkçe özet yüzeyler

## The verifier path (auditors, skeptics)

1. [REPRODUCE.md](REPRODUCE.md) — full acceptance suite + `tamga_verify_mini.py` (stdlib-only: trust nothing, run everything)
2. [TESTS.md](TESTS.md) — the 46-control family table (49 with `RUN_SLOW=1`), what each proves
3. [AUDIT-GATE.md](AUDIT-GATE.md) — audit-round discipline
4. [RFC-007-schema-revision-v02.md](RFC-007-schema-revision-v02.md) — the implemented v0.2 deltas (R1–R3) with their AT evidence
5. [PAIRING-FIXTURE.md](PAIRING-FIXTURE.md) — the cross-ledger evidence chain, every field labeled `simulated|observed|derived`

## The integrator path (x402 / ERC-8004 / external rails)

1. [ERC-8004-MAPPING.md](ERC-8004-MAPPING.md) — where on-chain discovery meets portable state (Draft-status caveat inside)
2. [RFC-008-external-receipt-DRAFT.md](RFC-008-external-receipt-DRAFT.md) — binding a payment rail's receipt into a charge (pilot-gated)
3. [RFC-009-external-chain-anchor-DRAFT.md](RFC-009-external-chain-anchor-DRAFT.md) — our ledger citing foreign-registry facts (epoch-10 evidence; pilot-gated)
4. [NODE-DISCOVERY.md](NODE-DISCOVERY.md) — Phase-3 design note, trigger-gated
5. [CI-VERIFY-TEMPLATE.md](CI-VERIFY-TEMPLATE.md) — embed `verify-my-claim` in your own CI

## Status vocabulary (used across all documents)

| Label | Meaning |
|---|---|
| FINAL / IMPLEMENTED | shipped at a pinned tag; acceptance-tested; changes need a new RFC |
| DRAFT (pilot-pending) | math/design frozen now; const/code waits on the pilot gate |
| DESIGN NOTE | thinking frozen, no code, gate decides timing |

**Dürüstlük notu:** hiçbir belge "çalışır" iddiasını komutsuz yapmaz; bir iddiayı
çelişkiye düşüren tek bir komut çıktısı, o iddiayı geri almaya yeter.

# docs/ — Reading Order & Index

28 documents, one design culture: **every claim is backed by a command**. This index
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
   Dil-durumu (KÜM disk-türer — dosya-ekle/çıkar→satır-bayatlar→AT-033 K5 süiti-kırmızıya-çevirir; içerik-iç-düzenlemeler-kapsam-dışı; elle-bakım YOK, üretici: `python3 tools/gen_lang_index.py`): bağlayıcı-orijinal BELGE-BAŞINA tek; İngilizce-doğmuşlar TR-ikizleriyle, Türkçe-doğmuşlar EN-kardeşleriyle. Türkçe-doğmuş aile: [MIGRATION-DEMO.md](https://github.com/goun7/tamga-protocol/blob/main/docs/MIGRATION-DEMO.md) · [PLAIN-TURKISH.md](https://github.com/goun7/tamga-protocol/blob/main/docs/PLAIN-TURKISH.md) · [RFC-005-declared-egress.md](https://github.com/goun7/tamga-protocol/blob/main/docs/RFC-005-declared-egress.md) · [RFC-006-agent-net-shim.md](https://github.com/goun7/tamga-protocol/blob/main/docs/RFC-006-agent-net-shim.md) · [RFC-007-schema-revision-v02.md](https://github.com/goun7/tamga-protocol/blob/main/docs/RFC-007-schema-revision-v02.md) · [RFC-008-external-receipt-DRAFT.md](https://github.com/goun7/tamga-protocol/blob/main/docs/RFC-008-external-receipt-DRAFT.md) · [RFC-009-external-chain-anchor-DRAFT.md](https://github.com/goun7/tamga-protocol/blob/main/docs/RFC-009-external-chain-anchor-DRAFT.md) · [VERIFY-EPOCH-ANCHOR.md](https://github.com/goun7/tamga-protocol/blob/main/docs/VERIFY-EPOCH-ANCHOR.md) (ayrışmada TR bağlar; EN-kardeşleri: [MIGRATION-DEMO.en.md](https://github.com/goun7/tamga-protocol/blob/main/docs/MIGRATION-DEMO.en.md) · [RFC-005-declared-egress.en.md](https://github.com/goun7/tamga-protocol/blob/main/docs/RFC-005-declared-egress.en.md) · [RFC-006-agent-net-shim.en.md](https://github.com/goun7/tamga-protocol/blob/main/docs/RFC-006-agent-net-shim.en.md) · [RFC-007-schema-revision-v02.en.md](https://github.com/goun7/tamga-protocol/blob/main/docs/RFC-007-schema-revision-v02.en.md) · [RFC-008-external-receipt-DRAFT.en.md](https://github.com/goun7/tamga-protocol/blob/main/docs/RFC-008-external-receipt-DRAFT.en.md) · [RFC-009-external-chain-anchor-DRAFT.en.md](https://github.com/goun7/tamga-protocol/blob/main/docs/RFC-009-external-chain-anchor-DRAFT.en.md) · [VERIFY-EPOCH-ANCHOR.en.md](https://github.com/goun7/tamga-protocol/blob/main/docs/VERIFY-EPOCH-ANCHOR.en.md)) — İngilizce-doğmuş belgelerin TR-ikizleri: [AGENT-GUIDE.tr.md](https://github.com/goun7/tamga-protocol/blob/main/docs/AGENT-GUIDE.tr.md) · [ARCHITECTURE.tr.md](https://github.com/goun7/tamga-protocol/blob/main/docs/ARCHITECTURE.tr.md) · [AUDIT-GATE.tr.md](https://github.com/goun7/tamga-protocol/blob/main/docs/AUDIT-GATE.tr.md) · [DEMO-SCRIPT.tr.md](https://github.com/goun7/tamga-protocol/blob/main/docs/DEMO-SCRIPT.tr.md) · [DESIGN-PARTNERS.tr.md](https://github.com/goun7/tamga-protocol/blob/main/docs/DESIGN-PARTNERS.tr.md) · [NODE-DISCOVERY.tr.md](https://github.com/goun7/tamga-protocol/blob/main/docs/NODE-DISCOVERY.tr.md) · [RELATED-WORK.tr.md](https://github.com/goun7/tamga-protocol/blob/main/docs/RELATED-WORK.tr.md) · [REPRODUCE.tr.md](https://github.com/goun7/tamga-protocol/blob/main/docs/REPRODUCE.tr.md) · [RFC-001-manifest.tr.md](https://github.com/goun7/tamga-protocol/blob/main/docs/RFC-001-manifest.tr.md) · [RFC-002-runner.tr.md](https://github.com/goun7/tamga-protocol/blob/main/docs/RFC-002-runner.tr.md) · [RFC-003-ledger.tr.md](https://github.com/goun7/tamga-protocol/blob/main/docs/RFC-003-ledger.tr.md) · [RFC-004-context-graph.tr.md](https://github.com/goun7/tamga-protocol/blob/main/docs/RFC-004-context-graph.tr.md) · [TESTS.tr.md](https://github.com/goun7/tamga-protocol/blob/main/docs/TESTS.tr.md) · [WHY-HASHCHAIN.tr.md](https://github.com/goun7/tamga-protocol/blob/main/docs/WHY-HASHCHAIN.tr.md)

## The verifier path (auditors, skeptics)

1. [REPRODUCE.md](REPRODUCE.md) — full acceptance suite + `tamga_verify_mini.py` (stdlib-only: trust nothing, run everything)
2. [TESTS.md](TESTS.md) — the 52-control family table (57 with `RUN_SLOW=1`), what each proves
3. [AUDIT-GATE.md](AUDIT-GATE.md) — audit-round discipline
4. [RFC-007-schema-revision-v02.md](RFC-007-schema-revision-v02.md) — the implemented v0.2 deltas (R1–R3) with their AT evidence
5. [PAIRING-FIXTURE.md](PAIRING-FIXTURE.md) — the cross-ledger evidence chain, every field labeled `simulated|observed|derived`
6. [VERIFY-EPOCH-ANCHOR.md](VERIFY-EPOCH-ANCHOR.md) — verify a foreign epoch seal yourself (inclusion + on-chain root; the epoch-13 replay recipe)
7. [RELATED-WORK.md](RELATED-WORK.md) — the 2026 landscape: neighboring papers (arXiv, click-checkable) and builders (capacity-attest, delivery-receipt cluster), with the independent runs we performed and the honest remainder we lack
8. [MIGRATION-DEMO.md](MIGRATION-DEMO.md) — a stranger publisher's real CLI (b3sum v1.8.7) migrated into the envelope: three honest steps, measured overhead table, reproducible recipe (`scripts/migrate_ext_b3sum.sh`)

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

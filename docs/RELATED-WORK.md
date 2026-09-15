# Related Work — where Tamga sits in the 2026 literature and ecosystem

> Purpose: every claim in this file is click-checkable. If a characterization here is
> wrong, the fix is a pull request, not a debate. Last sweep: **2026-09-15**
> (arXiv API, descending by submission date; npm registry; public GitHub threads).

## 1. Verifiable / governed agent memory (academic)

| Work | What it actually is | Honest relation to Tamga |
|---|---|---|
| **SuperLocalMemory 4.0** — [arXiv 2608.08253v2](https://arxiv.org/abs/2608.08253) | Local-first governed memory OS: hash-chained audit trail, verified erasure, fault-injection suite (2,199/2,200 properties). v2 **retracts its own v1 overhead number** ("the two paths it differenced are not comparable") and states our rule almost verbatim: *implemented, reachable and effective are three different questions, and the third requires an oracle independent of the mechanism under test.* | The closest academic neighbor. Its retraction is the strongest recent argument for two of our doctrines: publish only comparable measurements, and have foreign code grade your claims (our AT-029 cross-proof exists for exactly this). We do not run a governed-write benchmark comparable to theirs and say so. |
| **VerMem** — [arXiv 2608.03137](https://arxiv.org/abs/2608.03137) | "Verifiable Memory" meaning: RL credit-assignment via local+global verifiers **during training**; verifiers are not used at inference. | Naming collision we acknowledge: our "verifiable" is cryptographic/audit-path (post-hoc, third-party-checkable), not gradient-path. The term is now contested; our docs always disambiguate by showing the verifier CLI surface, not the adjective. |
| **Portable Agent Memory** — [arXiv 2605.11032](https://arxiv.org/abs/2605.11032) | Apache-2.0 protocol for cross-runtime memory transfer: Merkle-DAG provenance, capability-scoped disclosure, injection-resistant rehydration; 54 tests, no chain. | Same problem space as our memory-import + K0 bundles, different trust anchor: it verifies the payload's internal DAG; we additionally bind to an external hash-chain ledger + optional foreign-seal leg with three verdicts, stdlib-only verifier. Neither subsumes the other; a converter between the two formats would be a legitimate external contribution (not on our roadmap today — zero-capital discipline). |
| **Chat-of-Thoughts monitoring evasion** — [arXiv 2609.15989](https://arxiv.org/abs/2609.15989) | Shows CoT-monitoring can be evaded; self-reported traces are not evidence. | Cited in our x402 correspondence as the academic grounding for "receipt ≠ transcript": the record that matters is the one a third party can re-execute, not the model's account. |

## 2. The x402-adjacent builder cluster (industry, live threads)

| Actor | Artifact (as of 2026-09-15) | Independent check we performed |
|---|---|---|
| **holistis / tokenizen** — `capacity-attest@0.6.0` (npm, MCP registry) | Buyer-side delivery claims post-settlement (delivered yes/no/partial + evidenceHash), EAS + ERC-8004 `giveFeedback` on Base mainnet, no score/no escrow by design | Installed from npm and ran their fixture's control harness on this machine: **8/8 controls pass, including two negative controls** (forged signer rejected; tampered byte → claimId mismatch). Their `docs/SECURITY-REVIEW-2026-09-11.md` is linked from the README but the npm tarball ships only `dist/` — the review is checkable on GitHub, not offline from the package. |
| **StelarDigital** | RFC-6962 batched receipts + EAS anchoring, stdlib-only verifier stance; ran THREE foreign vector sets publicly (12/12, 9/9 with an honest "no live evidence verified" line); cited our 0.7% overhead figure by name in #2887 | Their "someone other than the author runs the vectors" posture is the same doctrine as our AT-029 vendored-referee design, arrived at independently. |
| **giskard09** | `delivery-receipt-anchor`: JCS preimages (`action_ref`), raised the pinned-vs-order-independent key-ordering question publicly | Our data point back (AT-029): two independent JCS implementations agree byte-for-byte; and our AGENT-GUIDE §14 now declares which class each of our layers belongs to. |
| **babyblueviper1 / stillmarcus24** | Pre-action verdict gate (261 signed verdicts); four-state vocabulary proposal (AGREE/DISAGREE/INDETERMINATE/**NOT_EVALUATED** + independence class) | Met our own doctrine halfway; our probe now carries a machine-readable `evaluated` field so "never got to look" is distinguishable from "looked, unsettled" without free-text parsing (AT-028 pins both sides). |

## 3. What Tamga claims that none of the above provides

1. **Execution, not delivery**: WASI re-execution receipts with a pinned execution profile
   (a CR-v0.1-class computation receipt), not payment/delivery logs. All neighboring work
   above attests *that something was delivered or observed*; none re-executes *what the
   computation did*.
2. **Stdlib-only, engine-free verification path**: `tamga verify-mini`, `epoch-verify`,
   `liveness-probe` all run with zero third-party dependencies — contrast capacity-attest's
   ethers/MCP-SDK tree (fine for their design, different trust surface).
3. **Three-verdict contract applied inward**: GREEN/RED/İNDETERMİNE with `evaluated`
   meta-flag, pinned-class/order-independent declarations, and a monthly stranger-pass CI
   ritual that has caught its own bugs on first runs.

## 4. What we do NOT have (the honest remainder)

- No pilots in production (the 10-point gap in our internal scorecard; nothing above fixes this for us).
- No hosted discovery API (by design — reader, not provider; §4.x-gated liveness work is the only chain surface we are waiting on).
- No ERC-8004 / registry integration (deliberate: we cite, they resolve).
- One verifier-family, one language (Python stdlib); capacity-attest covers Node/MCP lands we do not.

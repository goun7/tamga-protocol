> English twin of the Turkish-BORN original (docs/RFC-005-declared-egress.md). The Turkish file is the authoritative original; this translation exists for foreign readers. On any divergence, the Turkish governs.

# RFC-005 — Declared Egress (proxy model: declared network egress)

> **Status: IMPLEMENTED (Slice-1/2, 2026-09-06; AT-006 20-check, check-19; M6-migration
> completed in RFC-007-R1).** Design source: K15-founder-decision (2026-09-05) +
> private/RFC-005-yetenek-modeli-TASLAK.md + RFC-005A implementation schema. This document
> is the public record: WHAT was done, WHY this way, WITH WHICH EVIDENCE — honest findings included.
> Still-gated items explicitly labeled (§6).

## 0. The resolved contradiction (summary)

The v0 run-box has **no network** (D4: no fs-preopen, no network, zero env) — right for work that
wants protection; but real agents' work is largely LLM calls, and the LLM wants network.
Two bad solutions were REJECTED: "let there be network, we'll trust" (breaks the default-deny
invariant; unsellable) and "run LLM work outside the box" (the evidence chain falls outside the real work).
Solution: **network is not a default but a CAPABILITY** — declared in the manifest/declaration,
the runner enforces it as a constraint; an in-box socket NEVER opens.

## 1. Architecture (M1-M6; all implemented)

```
in-box agent → [single edge: stdin/stdout] → runner → 127.0.0.1 proxy (ephemeral)
                                          proxy: match against the declared list
   ├─ endpoint on list → CONNECT tunnel; RW byte counters flow; timeout starts
   ├─ endpoint NOT on list → box gets a "nope"; net_denied to run-log (run continues — op-based)
   ├─ DNS answer pinholes to off-list IP → deny + net_denied (SSRF antidote)
   ├─ byte ceiling exceeded → active connection killed + run RED 11 (session-capped, NO charge)
   └─ timeout exceeded → connection killed + net_denied (not a run-RED — one endpoint dies)
```

- **M1** net.json reader (strict: format/egress-≤8/timeout-1-120s/byte-ceiling-1KiB-8MiB/
  unknown-key RED) → **M2** loopback HTTP CONNECT proxy (re-ported on every run)
  → **M3** policy engine (net_denied: not_listed|dns_fail|upstream_fail|bad_request|
  byte_cap) → **M4** RW byte counter (net_mb summary) → **M5** events log 0600 + hashed →
  **M6** manifest migration (RFC-007-R1: `runtime.net`; migrate-net one-way).

## 2. wasmtime-outbound-socket — HONEST FINDING (Slice-2)

`/tmp/netprobe` (Rust, wasm32-wasip2) ran the flag matrix:
- outbound connect on every primitive flag, `-S tcp` INCLUDED → `Permission denied (os error 2)`
- `-S inherit-network` opens the monopoly syscall BUT gives the guest process the ENTIRE
  host network → bypasses the allow-list completely → **rejected** (breaks the single-edge rule)
- **Conclusion:** no primitive-level outbound in wasmtime-v48.0.1 CLI; the Box stays socketless
  (D4 preserved). Agent-side egress solved with the D13 shim (RFC-006); run-level
  enforcement + receipt binding proven with a real run.

## 3. D12 — declaration binding (three fields, conditional unity)

Into the charge record (in net-declared packages): `net_decl_sha256` (declaration hash: net.json file
bytes / runtime.net JCS subtree — RFC-007-R3 formalization) + `net_events_sha256`
(events-log 0600 hash) + `net_mb` (MiB, 6 digits). The **trio TOGETHER** (AT-011:
`net_trio_incomplete` RED); in undeclared packages all three are FORBIDDEN (D4 silence cannot show
"spent"). Post-run declaration change → `net_binding_mismatch`; deletion → `net_binding_missing`.

## 4. Security measures (all proven)

1. Declaration inside the signature (v0.2: manifest signature; v0.1 bridge: into the pre-run hash receipt)
2. **DNS-rebinding antidote:** every FQDN resolved at load time and its IP pinned (no DNS path at
   CONNECT time); unresolvable endpoint → RED at load (fail-closed); SNI/Host preserved — the client
   keeps talking under the name it talks to
3. Response-size + duration ceilings into the RLIMIT family (F15 discipline); byte-cap overflow = run
   RED-11 + capped marker (partial log stays 0600 + hashed)
4. NO TLS inspection (proxy = blind tunnel: sees endpoint + bytes, blind to content) — content-level
   policy in Phase 3 with TEE (conscious deferral, §6)
5. Packages without net.json: byte-for-byte the old path (D4 hermeneutic invariant, AT-006a)

## 5. Acceptance evidence

AT-006 (check-19; 20 runs): 8-endpoint overflow RED; off-list endpoint soft-denial; byte ceiling
in a REAL run (tc-net-slow sleeps 3 s, 8 KiB stream cut, no charge); an endpoint listed via fake DNS
reaches the real server (rebinding model: only name lookups are poisoned); post-run tamper
verification RED; D12 fields in the charge. TDD lessons kept openly separate (test-client
bare-port CONNECT — net_mb rounding tolerance — missing fixture; all real findings).
AT-009 (migrate-net)/AT-011 (trio unity) in the RFC-007 record.

## 6. Still-gated items (conscious; with gate labels)

- **TLS content policy** → Phase 3 TEE (OQ-4)
- **Multi-protocol declaration** (some endpoints HTTP/some gRPC) → deferred to v0.2+ (single list
  FQDN:port is enough)
- **R4 signed-DENY artifact** → pilot-gated candidate note (RFC-007 §5b)

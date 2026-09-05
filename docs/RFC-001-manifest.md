# RFC-001: Agent Package Manifest Schema

> Canonical version of this document is Turkish (internal). This is the official English translation — normative content is identical.

*Translator's note: "Tamga" is the project's name for the primitive. Code blocks are reproduced verbatim from the canonical Turkish original — identifiers, field names, patterns, and example values (including the example package name `tamga-ornek-ajani`, Turkish for "example agent") are unchanged.*

- **Status:** **v0.1-FINAL — FROZEN (2026-09-02, founder-approved).** A change requires a new RFC + a version bump.
- **Dependencies:** primitive definition §3, neutrality §6; acceptance-test suite, AT-001a; roadmap Phase 0 — the referenced documents are internal (decision log).
- **Related RFCs:** RFC-002 (runner API, snapshot export/import) · RFC-003 (ledger records) · RFC-004 (attestation)

## 1. Motivation

Three of the primitive's four components (Identity, Memory, Wallet) are runtime entities; the manifest is the carrier of the fourth, **Execution** (E_A = W_A + F_A + P_A): what the code is, what it requests, and which protection level it requires. The manifest is also **the first interface to be frozen** — agents, nodes, and test tooling are built against this schema in parallel with one another. For that reason the schema is written small, strict, and auditable.

## 2. Scope and Decisions (with rationale)

| # | Decision | Rationale | Rejected alternative |
|---|---|---|---|
| D1 | Single file: `tamga.json`, validated against JSON Schema (draft 2020-12) | Signing requires **canonical serialization**; JSON has a standard for it (RFC 8785). YAML has no canonical form; TOML's tooling support is weak | YAML (cannot be canonicalized → signature ambiguity), TOML |
| D2 | Signature: ed25519, over the RFC 8785 canonical form; computed with the `signature` field emptied | Short keys, widespread in the ecosystem; simple rules | An ECDSA chain (needless complexity; no chain in v0) |
| D3 | Unknown-field policy: **strict reject** (v0.1) | In an early phase, silent divergence is the largest source of errors; loosening later is easy, tightening later is breaking | ignore-unknown (common, but produces silent errors) |
| D4 | Capabilities are **default-deny**: fs, net, clock, env, random | The code-level counterpart of the host-blindness principle: no undeclared access exists. Security-boundary section → the human gate applies | default-allow (contradicts the primitive) |
| D5 | Code integrity is mandatory: `code.sha256` — a package without a hash is invalid | A precondition for AT-001d (host-blindness) and for future proof-of-execution | an unsigned/hashless "development mode" (backdoor ban) |
| D6 | The code target is fixed: **WASI 0.3 (component model)** | As of September 2026, WASI's third milestone (0.3) has been released; the component model is the ecosystem standard for the permission model + portable components. A package that compiles to the legacy core-module target is RED | the `core module` target (outside the permission model and the component standard) |

## 3. Package Format

```
package/
├── tamga.json      # the subject of this RFC
├── agent.wasm    # the WASM module matching code.sha256
└── seed/         # (optional) initial context graph, in tamga-snapshot/1 form
```

## 4. Schema (JSON Schema, normative)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "tamga://rfc-001/manifest-0.1.0",
  "title": "Tamga Ajan Paket Manifesti",
  "type": "object",
  "additionalProperties": false,
  "required": ["spec_version", "package", "runtime", "memory", "capabilities", "signature"],
  "properties": {
    "spec_version": { "const": "0.1.0" },
    "package": {
      "type": "object",
      "additionalProperties": false,
      "required": ["name", "version", "code"],
      "properties": {
        "name": { "type": "string", "pattern": "^[a-z0-9][a-z0-9-]{2,31}$" },
        "version": { "type": "string", "pattern": "^(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)$" },
        "code": {
          "type": "object",
          "additionalProperties": false,
          "required": ["wasm_sha256", "hash_algo", "target"],
          "properties": {
            "wasm_sha256": { "type": "string", "pattern": "^[a-f0-9]{64}$" },
            "hash_algo": { "const": "sha256" },
            "target": { "const": "wasi-0.3/component" }
          }
        }
      }
    },
    "runtime": {
      "type": "object",
      "additionalProperties": false,
      "required": ["min_proof_level", "limits"],
      "properties": {
        "min_proof_level": { "enum": ["P0", "P1", "P2"] },
        "limits": {
          "type": "object",
          "additionalProperties": false,
          "required": ["memory_mb", "cpu_ms_per_run", "io_mb_per_run"],
          "properties": {
            "memory_mb":       { "type": "integer", "minimum": 16, "maximum": 4096 },
            "cpu_ms_per_run":  { "type": "integer", "minimum": 1,  "maximum": 60000 },
            "io_mb_per_run":   { "type": "integer", "minimum": 0,  "maximum": 1024 }
          }
        }
      }
    },
    "memory": {
      "type": "object",
      "additionalProperties": false,
      "required": ["snapshot_format", "crypto_suite"],
      "properties": {
        "snapshot_format": { "const": "tamga-snapshot/1" },
        "crypto_suite": { "const": "XChaCha20-Poly1305" }
      }
    },
    "capabilities": {
      "type": "array",
      "uniqueItems": true,
      "items": { "enum": ["fs", "net", "clock", "env", "random"] },
      "maxItems": 5
    },
    "payment": {
      "type": "object",
      "additionalProperties": false,
      "required": ["schemes"],
      "properties": {
        "schemes": { "type": "array", "minItems": 1, "items": { "const": "tamga-sim/1" } }
      }
    },
    "signature": {
      "type": "object",
      "additionalProperties": false,
      "required": ["algo", "key", "sig"],
      "properties": {
        "algo": { "const": "ed25519" },
        "key":  { "type": "string", "pattern": "^[a-f0-9]{64}$" },
        "sig":  { "type": "string", "pattern": "^[a-f0-9]{128}$" }
      }
    }
  }
}
```

Notes: in v0, `payment` accepts only `tamga-sim/1` (the simulated ledger, RFC-003); in v1 the enum widens (x402 etc.) — that is a **minor** version bump. `runtime.min_proof_level` is the lower bound the agent *requests*; the level the node *can offer* is written into the node manifest in RFC-004, and the match is checked before a run.

## 5. Validation Rules (enforced by the runner, in this order)

1. JSON parse → schema validation (§4, strict).
2. The sha256 of the `agent.wasm` file = `package.code.wasm_sha256`.
3. Signature verification: empty the field, canonicalize per RFC 8785, verify with `signature.key`.
4. Capability check: an undeclared syscall/WASM import is blocked at run time (a declared/actual inconsistency is an error, not silent permission).
5. If `min_proof_level` does not match what the node offers → RED (outside AT-001a's scope; a run-time check).

## 6. Test Vectors (wired to AT-001a)

| ID | Variant | Expected |
|---|---|---|
| TC-a1 | Valid manifest + matching wasm + valid signature | ACCEPT |
| TC-a2 | `code.wasm_sha256` does not match the file | RED: "code hash mismatch" |
| TC-a3 | Unknown top-level field (`"admin_backdoor": true`) | RED: "unknown field" (D3) |
| TC-a4 | `"root"` inside `capabilities` | RED: "unknown capability" (D4) |
| TC-a5 | Signature field corrupted (a single hex character changed) | RED: "signature invalid" |
| TC-a6 | Different `spec_version` (`"0.2.0"`) | RED: "unsupported spec_version" |

## 7. Example Manifest

```json
{
  "spec_version": "0.1.0",
  "package": {
    "name": "tamga-ornek-ajani",
    "version": "0.1.0",
    "code": { "wasm_sha256": "3a7b…64-hex…", "hash_algo": "sha256", "target": "wasi-0.3/component" }
  },
  "runtime": {
    "min_proof_level": "P0",
    "limits": { "memory_mb": 128, "cpu_ms_per_run": 5000, "io_mb_per_run": 10 }
  },
  "memory": { "snapshot_format": "tamga-snapshot/1", "crypto_suite": "XChaCha20-Poly1305" },
  "capabilities": ["clock", "random"],
  "payment": { "schemes": ["tamga-sim/1"] },
  "signature": { "algo": "ed25519", "key": "ab…64-hex…", "sig": "cd…128-hex…" }
}
```

## 8. Security Considerations

- The manifest is signed, but **the signer ≠ the agent's identity** (pk_A is born in the keystore during a run — primitive definition §3, internal decision log). The manifest signature proves the package's origin; it does not prove the agent's identity. This distinction is deliberate and normative.
- D4 (default-deny) and D5 (mandatory hash) fall under the human gate: changes that relax them cannot be merged on their own.
- Hash agility: a single algorithm in v0.1 (sha256); if a need to change it ever arises, a new RFC — existing packages continue to validate as-is.

## 9. Open Questions (deliberately deferred)

1. The full schema of the `seed/` graph → RFC-002 (together with snapshot export/import).
2. Multi-signer support (publisher + auditor) → a single signature in v0.1; an RFC if demand arises.
3. The v1 widening of the `payment.schemes` enum → tied to the tokenomics §3 simulation (internal decision log).
4. **There is no signer trust anchor (allowlist/pinning) in v0.1** — discovered during an evidence run (2026-09-02): the "wrong signer" scenario cannot be tested at the manifest level; every valid key can sign its own manifest. Package distribution/registry design is the subject of a separate RFC.

## 10. Approval Record

- [x] Founder approval: **2026-09-02** — this RFC was frozen, Status: **v0.1-FINAL**. Schema: `specs/manifest-0.1.0.schema.json`; validator: `tamga_validator.py`.

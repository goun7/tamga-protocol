> English twin of the Turkish-BORN original (docs/RFC-006-agent-net-shim.md). The Turkish file is the authoritative original; this translation exists for foreign readers. On any divergence, the Turkish governs.

# RFC-006 — Agent-Side Network Request Shim (D13: stdin/stdout single edge)

> **Status: IMPLEMENTED (2026-09-06, d59c1b4; AT-008 6/6, check-21; suite 21/21;
> CI green).** Founder approval: 2026-09-06 (shim slice now; demo target mock HTTPS).
> Predecessor: RFC-005 §2 honest finding (no primitive-level outbound in wasmtime-v48 CLI). This document
> is the public record; with honest notes — including test-side fault lessons.

## 1. Thesis

The agent does NOT open a socket (D4, permanent). The agent writes one **request line** to its
stdout; the runner passes the request through the **TamgaProxy CONNECT tunnel** and writes the response
to the agent's stdin as a **response line**. The proxy remains the ONE path of network egress; the
policy source (net.json + proxy) never changes; the runner itself never connects to a host directly.

## 2. Protocol (TAMGA-NET-1 / TAMGA-NET-RESP-1)

**Request (agent → stdout, single line, ≤64 KiB):**
`TAMGA-NET-1 {"id":1,"method":"GET","url":"https://host:443/path","headers":{...},"body_b64":null}`
method ∈ {GET,POST,PUT,DELETE,HEAD,PATCH}; url http/https only; body_b64 optional.

**Response (runner → agent stdin, single line):**
`TAMGA-NET-RESP-1 {"id":1,"ok":true,"status":200,"headers_b64":"...","body_b64":"..."}`
error: `{"id":1,"ok":false,"error":"net_denied:not_listed"}` (deny reasons — same family as proxy).

**stdin discipline (capability probe; two modes):** the runner scans the agent wasm for the
`TAMGA-NET-1 ` byte sequence:
- **net-aware agent** (marker present): stdin = `TAMGA-STDIN-1 <len>\n` + input bytes;
  stdin kept OPEN (response channel); when the agent writes to stdout, `flush` is REQUIRED.
- **legacy agent** (marker absent): stdin = input bytes + **immediate EOF** (byte-identical with D4;
  `read_to_end` agents do not block). A legacy agent printing a request line gets a silent refusal
  (`net_shim_ignored`).
- Honest boundary note: because the response channel holds stdin open, legacy semantics + response
  cannot be merged on a single stdin; the capability probe is the mechanical limit of this duality.

**Lock-step:** one request in flight at a time; no new request is processed before the response is written.

## 3. Security model (invariants unchanged)

- **Policy:** endpoint off the allow-list → proxy 403 → error response to agent (soft path; run continues)
- **Evidence integrity:** the stdout evidence file is the child output byte-for-byte — **request lines
  INCLUDED** in the write (extraction/editing = tampering, FORBIDDEN). Network evidence = events log (0600)
  + D12 fields; two proofs, separate legs.
- **TLS:** over CONNECT, `wrap_socket(server_hostname=<declared host>)` — TCP target pinned to the IP;
  certificate verification against the declared name; test CA only via the `TAMGA_NET_CA_BUNDLE` env
  (prod: unset; documented).
- **A shim error does not drop the run** (soft); ONLY the byte-cap mid-stream cut triggers the hard path
  (RED 11, no charge).

## 4. Acceptance evidence (AT-008; check-21)

| | senaryo | kanıt |
|---|---|---|
| a | net.json-bearing package + net-demo agent → mock echo | run OK; request line + status in stdout; charge net_mb>0; net_connect in events |
| b | request to a non-egress host | error response not_listed; run continues; net_denied in events |
| c | mock HTTPS (local CA) | 200 + body echo; certificate verified against the declared name |
| d | request in a package without net.json | silent refusal; `net_shim_ignored:1`; no net in receipt (D4) |
| e | cap 1 KiB + 8 KiB response | mid-stream capped → RED 11, no charge |
| f | evidence integrity | request line byte-for-byte in the stdout file; stdout_sha256 matches |

Lessons of realization (honest): AT-008c wants an IP-SAN certificate (D12 dns fail-closed rejects
unresolvable names, so the test uses 127.0.0.1 + IP:127.0.0.1 SAN); if the mock server closes before
reading Content-Length it eats an RST (body draining mandatory in mocks);
net_mb precision = round(bytes/2^20, 6 digits) (D12c). Evidence: `.evidence/AT-008/2026-09-06/`.

## 5. Consciously absent (honest; v1 limits)

- Streaming/WebSocket/multiple concurrent requests: NO (lock-step is enough)
- HTTP parser minimal (Content-Length + chunked) — NOT a general-purpose client;
  rich-client agent contract a separate RFC later
- **auth-header secrecy:** the request line IS WRITTEN to the stdout evidence — headers carrying
  secret keys contaminate the evidence; carrying secrets is the agent's OWN responsibility (header masking
  v0.2 candidate D14 — no draft exists)

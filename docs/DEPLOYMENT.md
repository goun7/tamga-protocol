# Tamga Oracle Relayer — Deployment Guide

This guide covers the production deployment of `tamga_oracle_relayer.py`
(KATMAN-0+1+2, 900 lines). The relayer listens for `RequestExecution` events on
an EVM chain, runs the registered WASI module inside the real wasmtime sandbox,
and posts the resulting proof back on-chain via `fulfillExecution`.

## 1. Dependencies

The core module keeps the **zero-new-PyPI-dependency** principle: it shares
`tamga_runner.py`'s dependency surface (PyNaCl). The EVM transport (KATMAN-2) is
optional:

```bash
pip install tamga-protocol[relayer]        # only web3<7 → daemon mode
# or from source:
pip install .[relayer]
```

Verify the install (ships a console-script):

```bash
tamga-relayer                                # usage guide
tamga-relayer registry-check relayer.registry.json
tamga keygen                                 # engine-free (verified by AT-013)
```

If web3 is absent, the daemon exits with a `message-RED` (reason_code 27) —
never a silent fall-through (usage_guard doctrine).

## 2. Registry (production manifest)

`relayer.registry.json` — the relayer runs **only** the `wasiModuleHash` values
registered here (fail-closed; decision file §2):

```json
{
  "_note": "metadata — keys with a leading underscore are not registry entries",
  "6129007a280fcee3845532d38e4be3ecf9fddb03809c35a335e0b1b9c2b142a5": {
    "pkg_path": "templates/",
    "cpu_ms_per_run": 5000,
    "max_input_bytes": 262144
  }
}
```

**Rules:**
- `cpu_ms_per_run` must be **measured, not guessed**: read `wall_ms` from
  `tamga_runner.py run <pkg> --seed <hex> --require-proof` and add a safe margin
  (this repo's module: 30–79 ms measured → 5000 ms budget).
- `cpu_ms_per_run` must be **identical** to the package's
  `tamga.json` `runtime.limits.cpu_ms_per_run` — `execute_request`
  cross-validates and returns `RED-23` on mismatch.
- `pkg_path` points at the package root containing `tamga.json` + `agent.wasm`.
  In production prefer a read-only copy: a run writes runtime state
  (`state.json`, `ledger.jsonl`) into the package directory.

**Atomic-reload constraint:** the registry is loaded **once** at daemon start.
There is **no hot-reload** — any change requires a restart. This is deliberate:
it closes the TOCTOU hole where a config edit silently redirects pending
requests to a different module.

**Fail-closed:** an unregistered hash returns `RED-20` and **no module is ever
spawned**. That is the guarantee the relayer is *not* an RCE vector (verified by
AT-198). Test it yourself:

```bash
tamga-relayer run-request --registry relayer.registry.json --seed $SEED \
  --module-hash 0x$(printf 'f%.0s' {1..64})   # → RED-20 module-not-registered
```

## 3. Secret management (AT-190/197)

Two secrets must be protected:

| Secret | Source | Production rule |
|---|---|---|
| `--ledger-secret` (cost-ledger HMAC) | `TAMGA_RELAYER_LEDGER_SECRET` env | **no dev-secret** — None → `RED-24`, known value → `RED-25` (AT-197) |
| `TAMGA_KS_PASSPHRASE` (D3 keystore) | systemd `EnvironmentFile` (0600, root) | required by the export path; carried in the daemon env |

Other environment variables: `TAMGA_RELAYER_KEY` (fulfill tx signing key),
`TAMGA_RELAYER_RPC_URL`, `TAMGA_RELAYER_ORACLE` (contract address),
`TAMGA_SESTER_PATH` (mesh sester module; on PYTHONPATH in production).

**Generating secrets:** `tamga keygen` for the agent identity key; for the
ledger secret use 32+ random bytes:
`python3 -c "import secrets;print(secrets.token_urlsafe(32))"`.

## 4. systemd unit (with watchdog)

`/etc/systemd/system/tamga-relayer.service`:

```ini
[Unit]
Description=Tamga Protocol on-chain oracle relayer
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=tamga
Group=tamga
WorkingDirectory=/opt/tamga
EnvironmentFile=/etc/tamga/relayer.env          # 0600 root — secrets live here
ExecStart=/opt/tamga/.venv/bin/tamga-relayer daemon \
    --registry /etc/tamga/relayer.registry.json \
    --seed ${TAMGA_SEED_HEX} \
    --rpc-url ${TAMGA_RELAYER_RPC_URL} \
    --oracle ${TAMGA_RELAYER_ORACLE} \
    --key ${TAMGA_RELAYER_KEY} \
    --ledger-secret ${TAMGA_RELAYER_LEDGER_SECRET} \
    --interval 15
Restart=always
RestartSec=5
WatchdogSec=90                                   # 3 × interval: watchdog deadline
                                                # stays longer than a poll cycle
NotifyAccess=main
TimeoutStopSec=30
StandardOutput=append:/var/log/tamga/relayer.log
StandardError=append:/var/log/tamga/relayer.log

# Resource bounds (consistent with D4: the sandbox is already fs/network-free)
MemoryMax=1G
TasksMax=64

[Install]
WantedBy=multi-user.target
```

`/etc/tamga/relayer.env` (template — substitute real values in production):

```sh
TAMGA_SEED_HEX=<64 hex — produced ONCE by quickstart, never re-printed>
TAMGA_KS_PASSPHRASE=<keystore passphrase>
TAMGA_RELAYER_KEY=0x<EVM signing key>
TAMGA_RELAYER_RPC_URL=https://base-sepolia.g.alchemy.com/v2/<KEY>
TAMGA_RELAYER_ORACLE=0x<ITamgaOracle contract address>
TAMGA_RELAYER_LEDGER_SECRET=<32+ random bytes>
```

```bash
chmod 600 /etc/tamga/relayer.env
systemctl daemon-reload
systemctl enable --now tamga-relayer
journalctl -u tamga-relayer -f
# daemon log line: [relayer] request 42 fulfilled: tx=0x… status=1 gasUsed=39935
#                    digest=87ab8c35… delivery=9cec8dbc… (keccak over outputData)
```

The daemon loop **does not stop on errors** — every failure is logged as a
`message-RED` and the next poll cycle continues. `Restart=always` +
`WatchdogSec` provide a second layer of assurance.

## 5. Security posture (summary)

| Property | Enforcement | Test |
|---|---|---|
| Not an RCE vector | unregistered hash → RED-20, no spawn (daemon path too) | AT-198 N1, AT-199 K7 |
| CPU double-bind | `min(request, manifest)` + [1,60000]; out-of-range → RED-21 | AT-198 K1–K5 |
| Ledger secret mandatory | None → RED-24; dev-secret → RED-25 | AT-197 K1–K6 |
| Independent proof verification | fnv1a64 stamp recomputed by the relayer (seal-2) | AT-195 |
| Portable seal-1 | digest = SHA-256(encrypted body), not the whole blob | AT-195 |
| Seal-3 live (ledger tip) | `{seq, h, prev}` taken from `append()`'s return — never a `led.tip` attribute that does not exist | AT-199 K2 |
| input_sha256 independent | recomputed by the relayer, not trusted from the runner | AT-199 K3 |
| delivery_hash | keccak-256 legacy-padding over the actual outputData bytes; *not* inside the payload (recursion-free) | AT-199 K4 |
| Sandbox | wasmtime D4: no fs preopens, no network | AT-194 (clean scan) |
| Message-RED | every error is `out(ok=False, reason_code, reason)` JSON — no traceback | AT-192 |

## 6. EVM test node (development)

AT-196 uses the real py-evm state machine (no anvil/solc required). The test
bootstraps its own venv:

```bash
pip install .[evm-test]     # web3<7 + eth-tester<0.10 + py-evm + setuptools<81
bash tests/at196_relayer_evm_uctan_uca_dikis.sh
# RESULT: 1 PASS, 0 FAIL — receipt status=1 gasUsed=39959
```

Note: PEP 668 blocks the system pip — always use a repo-local venv
(`.venv-evm/`, listed in `.gitignore`). When the network is unavailable the test
reports **SKIP, not FAIL**: an unreachable test node is infrastructure, not a
regression.

## 7. End-to-end flow (single request, CLI)

```bash
# 1. Package + seed (ONCE — the seed is never re-printed)
tamga quickstart /opt/tamga/pkg --name my-agent | tee quickstart.json
SEED=$(python3 -c "import json;print(json.load(open('quickstart.json'))['seed_hex'])")

# 2. Validate the registry
tamga-relayer registry-check relayer.registry.json
# {"ok": true, "modules": 1, "hashes": ["6129007a280fcee3"]}

# 3. Serve one request (without the daemon; production uses daemon mode)
tamga-relayer run-request --registry relayer.registry.json \
    --seed "$SEED" \
    --module-hash 6129007a280fcee3845532d38e4be3ecf9fddb03809c35a335e0b1b9c2b142a5 \
    --ledger-secret "$TAMGA_RELAYER_LEDGER_SECRET"
# → {"ok": true, "digest": "87ab8c35…", "stamp": "da4cba53a97ca717",
#    "effective_cpu_ms": 5000, "blob_sha256": "8eaf9229…", "payload": "{…JCS…}"}

# 4. Audit the proofs independently (KATMAN-0 surface)
tamga-relayer verify-stamp pkg/session-2.stdout     # seal-2: TAMGA:<fnv1a64>
tamga-relayer snapshot-digest snap.tsg              # seal-1: SHA-256(ct)
```

The proof chain: **EVM event → decode → real wasmtime run → `TAMGA:<fnv1a64>`
stamp (verified independently) → real XChaCha20-Poly1305 export →
`SHA-256(ct)` digest → JCS canonical fulfill payload → EIP-1559 signed tx →
on-chain receipt (`status:1` + `gasUsed`).

> English twin of the Turkish-BORN original (docs/VERIFY-EPOCH-ANCHOR.md). The Turkish file is the authoritative original; this translation exists for foreign readers. On any divergence, the Turkish governs.

# Verify an external epoch seal yourself (verify-it-yourself)

> This page explains how, without knowing Tamga, without trusting us, with a single Python interpreter,
> one verifies an **external epoch seal** (example: an Apodix/Vauban registry stamp).
> The method is exactly the replay we ran on our own side for the epoch-13 seal-flip on 2026-09-13
> (evidence: `.evidence/APODIX-EPOCH-13/2026-09-13/seal-flip-replay.log`).
> The lesson to draw is two-legged: **inclusion** and **anchor**.

## Why this page exists

The single rule of our evidence culture: **no one's word is GREEN until someone else runs it.** Before
any external registry seal is called "existent," you must produce the answers to four questions ON YOUR OWN machine:

1. Is the given fact REALLY a leaf of the claimed epoch tree? (inclusion)
2. Is the tree's root the same as the root written on the chain? (anchor)
3. Who wrote the root, in which block? (source reading — verify the seal itself too)
4. NONE of these proves the *content* of the fact is correct — inclusion and
   correctness are separate questions and are not confused. (honesty note)

## Requirement

- `python3` (stdlib is enough — you will write keccak yourself or use our single-file reference:
  [`tools/keccak256.py`](../tools/keccak256.py) — keccak is written INSIDE, no package is imported;
  self-verifies with three known-answer vectors)
- Merkle recipe: OpenZeppelin merkle-tree — `sort_leaves:true`, `sorted_pairs:true`,
  leaf = `keccak256(keccak256(bytes32(fact)))`

## Step 1 — get the proof data

```bash
curl -sS "https://explorer.testnet.apodix.vauban.tech/v1/anchors/proof/<fact-hash>" -o proof.json
```

Returned fields: `epoch_id`, `fact_hash`, `position`, `leaf_count`, `proof[]`, `root`, `l1`,
`tree`, `how_to_verify`.

## Step 2 — recompute the inclusion

```python
import json, sys
sys.path.insert(0, "tools")
from keccak256 import keccak256 as k

d = json.load(open("proof.json"))
node = k(k(bytes.fromhex(d["fact_hash"][2:])))   # yaprak: double-keccak(bytes32(fact))
for p in d["proof"]:                             # sorted-pairs yürüyüşü
    sib = bytes.fromhex(p[2:])
    lo, hi = sorted([node, sib])
    node = k(lo + hi)
print("dahil-etme GREEN:", "0x" + node.hex() == d["root"])
```

If the result is `True`, the fact is a leaf of that epoch tree. (The raw form of our real run:
`seal-flip-replay.log` — it follows the same path line by line.)

## Step 3 — read the root yourself on the chain

```python
import json, urllib.request, sys
sys.path.insert(0, "tools")
from keccak256 import keccak256 as k

data = "0x" + k(b"epoch(uint64)").hex()[:8] + f"{13:064x}"   # epoch(uint64) selector
corps = {"jsonrpc": "2.0", "id": 1, "method": "eth_call",
         "params": [{"to": "0x48421a2e448cb2E3fA66af2E047F86ee755cFB14", "data": data}, "latest"]}
req = urllib.request.Request("https://ethereum-sepolia-rpc.publicnode.com",
                             data=json.dumps(corps).encode(),
                             headers={"content-type": "application/json",
                                      "user-agent": "verify-it-yourself/1"})
ret = json.load(urllib.request.urlopen(req, timeout=60))["result"][2:]
print("root  :", "0x" + ret[0:64])
print("count :", int(ret[64:128], 16))
```

CHOOSE your own RPC (publicnode, alchemy, your own node) — the one that verifies the seal is not the
one that hands you an answer. The root must match the Step 2 result exactly; `factsCount == leaf_count`
must match too. **But also verify that the RPC you chose IS THE CLAIMED chain:** fire an
`eth_chainId` at your RPC, if it does not match the chain you expect, the root you read belongs to
ANOTHER world (sepolia `0xaa36a7`=11155111; the chain version of the payee-mismatch class in x402 #2887).
The CLI now makes this binding the default: given `--rpc` it runs an `--expect-chainid`
(default sepolia) pre-query; `--expect-chainid 0` is a conscious skip and prints an honesty note.

## To say GREEN

- Step 2 `True` **and** Step 3 root equal **and** counts equal → **GREEN** (inclusion + anchor).
- If the RPC does not answer — **INDETERMINATE** too — "could not look" and "green" are never confused.
- If the RPC answers but the chain binding does not hold (chainId ≠ expected) — **INDETERMINATE** —
  *looking in the wrong place* is the same outcome as failing to look in the right one: no-verdict.
- If the root does not hold or the proof does not run — **RED**.

## This page's measured word (honest limits)

This procedure proves the fact **was included in a seal-bearing epoch tree** and that seal stands
on the chain. It does NOT prove the correctness of the fact's own content (e.g., a STARK acceptance)
— that is the sealing party's own honesty note, and further questions. The moment the two questions
mix, this page loses its purpose; so this distinction is part of the page itself.

---

Source event: 2026-09-13 epoch-13 seal-flip — evidence log `seal-flip-replay.log`
(fact `0x0236…36e2`, position 55/60, root `0xaaf21f36…c458e`, Sepolia block 11693440).
Public report: x402 #3389, [issuecomment-5653083752](https://github.com/x402-foundation/x402/issues/3389#issuecomment-5653083752).

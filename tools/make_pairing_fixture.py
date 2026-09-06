#!/usr/bin/env python3
"""Build the public x402 <-> Tamga pairing fixture (RFC-005A Dilim-3, #3379 safal207).

Runs a REAL Tamga run (tc-a1 vector agent, grant -> run --input) and emits a single
directory with:
  pairing-fixture.json  the pairing document; EVERY field carries
                        source: simulated | observed | derived  (labeling discipline)
  delivery.stdout       the exact bytes the run produced (the deliverable)
  input.json            the exact input bytes (D11 commitment)

Nothing real is paid; the payment side is explicitly SIMULATED. No secrets are
embedded (the agent seed lives only in the workdir and is never written out).

Usage: python3 tools/make_pairing_fixture.py <workdir> <outdir>
"""
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "tools"))
from keccak256 import keccak256  # noqa: E402


def _sh(*args):
    r = subprocess.run([sys.executable, *args], capture_output=True, text=True,
                       cwd=str(ROOT))
    if r.returncode != 0:
        raise SystemExit(f"FAIL {' '.join(args)}\n{r.stdout}\n{r.stderr}")
    return r.stdout


def jcs(d):
    return json.dumps(d, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def main():
    work = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/tamga-fixture")
    out = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else ROOT / "docs" / "pairing")
    if work.exists():
        shutil.rmtree(work)
    pkg = work / "pkg"
    pkg.mkdir(parents=True)
    for f in ("tamga.json", "agent.wasm"):
        shutil.copy(ROOT / "tests" / "vectors" / "tc-a1" / f, pkg / f)

    seed = json.loads(_sh("tamga_runner.py", "keygen"))["seed_hex"]
    _sh("tamga_runner.py", "grant", str(pkg), "0.01", "pairing-fixture")
    inp = b'{"demo": "pairing-fixture", "v": 1}\n'
    (work / "input.json").write_bytes(inp)
    run = json.loads(_sh("tamga_runner.py", "run", str(pkg), "--seed", seed,
                         "--input", str(work / "input.json"),
                         "--note", "pairing-fixture (public demo run)"))
    if not run.get("ok"):
        raise SystemExit(f"run failed: {run}")

    recs = [json.loads(l) for l in (pkg / "ledger.jsonl").read_text().splitlines()
            if l.strip()]
    charge = [r for r in recs if r.get("op") == "charge"][-1]
    delivery = (pkg / f"session-{charge['session']}.stdout").read_bytes()

    d_sha = hashlib.sha256(delivery).hexdigest()
    fixture = {
        "fixture": "tamga-x402-pairing/1",
        "labeling_discipline": ("every field carries source: simulated (x402 side, "
                                "no real payment) | observed (from the real Tamga run) "
                                "| derived (computed from observed bytes)"),
        "x402_settlement": {
            "scheme": {"value": "tamga-sim/1", "source": "simulated"},
            "payment_id": {"value": "SIM-PAY-0001", "source": "simulated"},
            "note": {"value": "no real payment occurred; replace with a real "
                              "settlement to make this a live pairing",
                     "source": "simulated"},
        },
        "tamga_observed": {
            "receiptHash": {"value": charge["h"], "source": "observed",
                            "note": "x402 envelope receiptHash carries this value"},
            "charge_record": {"value": charge, "source": "observed",
                              "note": "membership: h = sha256(prev + jcs(record "
                                      "without h)); recompute to verify"},
            "engine": {"value": charge["engine"], "source": "observed"},
            "session": {"value": charge["session"], "source": "observed"},
            "pkg": {"value": charge["pkg"], "source": "observed"},
        },
        "input_commitment": {
            "input_sha256": {"value": charge["input_sha256"], "source": "observed",
                             "note": "D11: sha256(input.json) bound into the receipt"},
        },
        "delivery_bytes": {
            "what": {"value": "the complete stdout of the run (the deliverable)",
                     "source": "observed"},
            "byte_count": {"value": len(delivery), "source": "observed"},
            "sha256": {"value": d_sha, "source": "observed",
                       "note": "== charge stdout_sha256; Tamga is a SHA-256 ledger"},
            "keccak256": {"value": keccak256(delivery).hex(), "source": "derived",
                          "note": "same bytes under Keccak-256 (legacy padding) for "
                                  "durable-evidence contentHash comparison"},
        },
        "verify": ["python3 tools/verify_pairing_fixture.py docs/pairing"],
    }

    out.mkdir(parents=True, exist_ok=True)
    (out / "pairing-fixture.json").write_text(
        json.dumps(fixture, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (out / "delivery.stdout").write_bytes(delivery)
    (out / "input.json").write_bytes(inp)
    print(json.dumps({"ok": True, "out": str(out),
                      "receiptHash": charge["h"],
                      "stdout_sha256": d_sha}))


if __name__ == "__main__":
    main()

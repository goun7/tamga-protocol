#!/usr/bin/env python3
"""tests/bench_run_edge.py — E-4 run-edge benchmark (sessiz-host onay-turu).

Measures the runner's run-edge: FULL run (keygen+grant+metered run, evidence,
chain append) vs the wasmtime CHILD-ONLY time for the same work. Writes
.evidence/BENCH/<date>/run-edge.json with loadavg captured before AND after.

- micro_agent: tc-a1 example agent, n=30 subprocess medians
- c30_agent:   the 31 s c30 fingerprint agent, n=3 (dominated by agent work —
               the honest headline is the ~% overhead on a real workload)

Usage:  python3 tests/bench_run_edge.py [--n-micro 30] [--n-c30 3]
"""
import argparse
import json
import shutil
import os
import statistics
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SB = ROOT / "tests" / "simnet" / ".bench-edge"
WASMTIME = [str(ROOT / "tools" / "bin" / "wasmtime"), "run"]


def loadavg():
    return open("/proc/loadavg").read().split()[:3]


def sh(args, **kw):
    return subprocess.run(["python3", str(ROOT / "tamga_runner.py")] + args,
                          capture_output=True, text=True, env=os.environ, **kw)


def med_ms(times):
    return round(statistics.median(times), 2)


def child_only(wasm, n):
    times = []
    for _ in range(n):
        t0 = time.monotonic()
        subprocess.run(WASMTIME + [str(wasm)], capture_output=True)
        times.append((time.monotonic() - t0) * 1000)
    return med_ms(times)


def full_run(src, note):
    # Fresh pkg dir per sample: the ownership binding (state.json agent_id) makes
    # a reused dir belong to the first sample's agent — each sample pays its own
    # keygen+grant, which is exactly what the run-edge measures.
    pkg = SB / (note + "-" + time.strftime("%H%M%S") + "-" + str(time.monotonic_ns()))
    pkg.mkdir(parents=True)
    for f in ("tamga.json", "agent.wasm"):
        (pkg / f).write_bytes((src / f).read_bytes())
    t0 = time.monotonic()
    seed = json.loads(sh(["keygen"]).stdout)["seed_hex"]
    sh(["grant", str(pkg), "0.0001", note])
    r = sh(["run", str(pkg), "--seed", seed, "--note", note])
    if '"ok": true' not in r.stdout:
        raise RuntimeError("run RED: " + r.stdout[:200])
    return (time.monotonic() - t0) * 1000


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n-micro", type=int, default=30)
    ap.add_argument("--n-c30", type=int, default=3)
    args = ap.parse_args()
    la_bas = loadavg()

    os.environ["TAMGA_KS_PASSPHRASE"] = "simnet-2026"

    micro_child = child_only(ROOT / "tests/vectors/tc-a1/agent.wasm", args.n_micro)
    micro_full = med_ms([full_run(ROOT / "tests/vectors/tc-a1", "bench-edge-micro")
                         for _ in range(args.n_micro)])
    c30_child = child_only(ROOT / "tests/vectors/tc-c30/agent.wasm", args.n_c30)
    c30_full = med_ms([full_run(ROOT / "tests/vectors/tc-c30", "bench-edge-c30")
                       for _ in range(args.n_c30)])

    out = {"tarih": time.strftime("%FT%T%z"),
           "loadavg_bas": la_bas, "loadavg_son": loadavg(),
           "note": "run-edge E-4: full-run vs wasmtime-child-only; "
                   "sessiz-host onay-turu — mutlak değer yanındaki-tur ile karşılaştırılır",
           "micro_agent": {"n": args.n_micro, "child_only_ms": micro_child,
                           "full_run_ms": micro_full,
                           "overhead_pct": round((micro_full / micro_child - 1) * 100, 2)},
           "c30_agent": {"n": args.n_c30, "child_only_ms": c30_child,
                         "full_run_ms": c30_full,
                         "overhead_pct": round((c30_full / c30_child - 1) * 100, 2)}}
    text = json.dumps(out, ensure_ascii=False, indent=1)
    print(text)
    logf = ROOT / os.environ.get("TAMGA_EVIDENCE_DIR", ".evidence") / "BENCH" / time.strftime("%F") / "run-edge.json"
    logf.parent.mkdir(parents=True, exist_ok=True)
    logf.write_text(text + "\n", encoding="utf-8")
    shutil.rmtree(SB, ignore_errors=True)


if __name__ == "__main__":
    main()

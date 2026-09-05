#!/usr/bin/env python3
"""E-4 — runner overhead micro-benchmark (Phase-2 exit-criterion infrastructure).

Question: OUTSIDE the wasmtime child, how much extra overhead does the runner itself
incur? (identity derivation scrypt, snapshot encryption, chain verification, merkle,
import deep-verification). If the Phase-2 exit criterion is "runner overhead < X% of
run wall time", this is its baseline.

Method: each op N times, perf_counter, one-shot sandbox, wasmtime NEVER invoked
(load-independent; measuring the run edge is AT-001c's job). Evidence: .evidence/BENCH/<date>/.
"""
import json, os, pathlib, shutil, statistics, subprocess, sys, time

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
os.chdir(ROOT)
os.environ.setdefault("TAMGA_KS_PASSPHRASE", "simnet-2026")

SB = ROOT / "tests/simnet/.bench"
RUNNER = [sys.executable, "tamga_runner.py"]


def sh(*args):
    return subprocess.run(RUNNER + list(args), capture_output=True, text=True).stdout.strip()


def bench(name, n, fn):
    ts = []
    for _ in range(n):
        t0 = time.perf_counter()
        fn()
        ts.append((time.perf_counter() - t0) * 1000)
    ts.sort()
    return {"op": name, "n": n, "medyan_ms": round(statistics.median(ts), 2),
            "ortalama_ms": round(statistics.mean(ts), 2), "p95_ms": round(ts[int(n * 0.95) - 1], 2)}


def main():
    import hashlib
    shutil.rmtree(SB, ignore_errors=True)
    pkg = SB / "pkg"; pkg.mkdir(parents=True)
    for f in ("tamga.json", "agent.wasm"):
        (pkg / f).write_bytes((ROOT / "tests/vectors/tc-a1" / f).read_bytes())
    seed = json.loads(sh("keygen"))["seed_hex"]

    rows = []
    rows.append(bench("keygen(ed25519)", 50, lambda: sh("keygen")))
    rows.append(bench("grant+zincir-ekleme", 50, lambda: sh("grant", str(pkg), "0.0001", "bench")))
    rows.append(bench("ledger-verify(5-records)", 50, lambda: sh("ledger-verify", str(pkg))))
    rows.append(bench("memory-import+ADD-only", 30, lambda: sh("memory", str(pkg), "--import-json", "tests/simnet/memory-dersler.json")))
    rows.append(bench("memory-search", 50, lambda: sh("memory", str(pkg), "--search", "scrypt")))
    rows.append(bench("export(scrypt+XChaCha)", 20, lambda: sh("export", str(pkg), "-o", str(SB / "s.tsg"), "--seed", seed)))
    # Audit-9 B2: the fixture must be installed BEFORE benching — otherwise the early-RED path is measured
    hedef = SB / "hedef"; hedef.mkdir(exist_ok=True)
    for f in ("tamga.json", "agent.wasm"):
        (hedef / f).write_bytes((ROOT / "tests/vectors/tc-a1" / f).read_bytes())
    rows.append(bench("import(deep-verification)", 20, lambda: sh("import", str(SB / "s.tsg"), str(hedef))))

    load = open("/proc/loadavg").read().split()[:3]
    out = {"tarih": time.strftime("%FT%T%z"), "loadavg": load,
           "note": "excludes the run edge (wasmtime); scrypt n=2^15 dominates; "
                  "the load environment is busy with parallel sessions — absolute values are not meaningful, "
                  "the BETWEEN-OP RATIO is (Phase-2 exit-criterion baseline)",
           "sonuclar": rows}
    text = json.dumps(out, ensure_ascii=False, indent=2)
    print(text)
    logf = ROOT / "kanit/BENCH" / time.strftime("%F") / "runner-overhead.json"
    logf.parent.mkdir(parents=True, exist_ok=True)
    logf.write_text(text + "\n", encoding="utf-8")
    shutil.rmtree(SB, ignore_errors=True)


if __name__ == "__main__":
    main()

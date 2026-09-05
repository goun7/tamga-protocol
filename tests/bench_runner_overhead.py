#!/usr/bin/env python3
"""E-4 — runner overhead mikro-benchmark (Faz 2 çıkış-ölçütü altyapısı).

Soru: wasmtime çocuğunun DIŞINDA, runner'ın kendi emdirdiği ek yük ne kadar?
(kimlik türetme scrypt, snapshot şifreleme, zincir doğrulama, merkle, import
derin-dogrulama). Faz 2 çıkış ölçütü "runner overhead < X% koşum süresi" olacaksa
bunun taban çizgisi buradan gelir.

Yöntem: her op N kez, perf_counter, tek-kullanımlık sandbox, wasmtime ÇAĞRILMAZ
(load-bağımsız; koşum-kenarı ölçümü AT-001c'nin işidir). Kanıt: kanit/BENCH/<tarih>/.
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
    rows.append(bench("ledger-verify(5-kayıt)", 50, lambda: sh("ledger-verify", str(pkg))))
    rows.append(bench("memory-import+ADD-only", 30, lambda: sh("memory", str(pkg), "--import-json", "tests/simnet/mergen-dersler.json")))
    rows.append(bench("memory-search", 50, lambda: sh("memory", str(pkg), "--search", "scrypt")))
    rows.append(bench("export(scrypt+XChaCha)", 20, lambda: sh("export", str(pkg), "-o", str(SB / "s.tsg"), "--seed", seed)))
    rows.append(bench("import(derin-doğrulama)", 20, lambda: sh("import", str(SB / "s.tsg"), str(SB / "hedef"))))
    (SB / "hedef").mkdir(exist_ok=True)
    for f in ("tamga.json", "agent.wasm"):
        (SB / "hedef" / f).write_bytes((ROOT / "tests/vectors/tc-a1" / f).read_bytes())

    load = open("/proc/loadavg").read().split()[:3]
    out = {"tarih": time.strftime("%FT%T%z"), "loadavg": load,
           "not": "koşum-kenarı (wasmtime) hariç; scrypt n=2^15 baskın emdiridir; "
                  "load ortamı paralel oturumlarla meşgul — mutlak değer değil, "
                  "op-arası ORAN anlamlıdır (Faz 2 çıkış-ölçütü taban çizgisi)",
           "sonuclar": rows}
    text = json.dumps(out, ensure_ascii=False, indent=2)
    print(text)
    logf = ROOT / "kanit/BENCH" / time.strftime("%F") / "runner-overhead.json"
    logf.parent.mkdir(parents=True, exist_ok=True)
    logf.write_text(text + "\n", encoding="utf-8")
    shutil.rmtree(SB, ignore_errors=True)


if __name__ == "__main__":
    main()

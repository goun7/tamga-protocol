import json, pathlib, subprocess, os
os.environ["TAMGA_KS_PASSPHRASE"] = "simnet-2026"
RUN = ["python3", "tamga_runner.py"]
SEED = open("tests/simnet/seed6.hex").read().strip()
def sh(*a):
    r = subprocess.run(RUN + list(a), capture_output=True, text=True)
    return json.loads(r.stdout.strip().splitlines()[-1])
r1 = sh("run", "tests/simnet/node-B/pkg", "--seed", SEED)
print("run:", json.dumps({k: r1[k] for k in ("ok", "session") if k in r1}))
r2 = sh("export", "tests/simnet/node-B/pkg", "-o", "tests/simnet/snapshot6c.tsg", "--seed", SEED)
print("export:", json.dumps({"ok": r2["ok"], "sha": r2["sha256"][:16]}))
lp = pathlib.Path("tests/simnet/node-B/pkg/ledger.jsonl")
lines = lp.read_text().splitlines()
lines.pop()
lp.write_text("\n".join(lines) + "\n")
print("truncate: son charge silindi, kalan", len(lines), "satir")
r3 = sh("import", "tests/simnet/snapshot6c.tsg", "tests/simnet/node-B/pkg")
print("F21 import:", json.dumps(r3))
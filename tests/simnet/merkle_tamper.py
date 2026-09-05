import json, pathlib, subprocess, os, shutil
os.environ["TAMGA_KS_PASSPHRASE"] = "simnet-2026"
RUN = ["python3", "tamga_runner.py"]
SEED = open("tests/simnet/seed6.hex").read().strip()
sp = pathlib.Path("tests/simnet/node-B/pkg/state.json")
st = json.loads(sp.read_text())
for n in st["memory"]["nodes"]:
    if n["kind"] == "note":
        n["text"] = "KURCALANDI"; break
sp.write_text(json.dumps(st, ensure_ascii=False))
print("state'te not kurcalandi")
r = subprocess.run(RUN + ["export", "tests/simnet/node-B/pkg", "-o", "tests/simnet/snapshot6d.tsg", "--seed", SEED], capture_output=True, text=True)
print("export(yapildi):", r.stdout.strip().splitlines()[-1][:60])
shutil.rmtree("tests/simnet/node-B/pkg-t", ignore_errors=True)
os.makedirs("tests/simnet/node-B/pkg-t")
for f in ("tamga.json", "agent.wasm"):
    shutil.copy("tests/vectors/tc-a1/" + f, "tests/simnet/node-B/pkg-t/" + f)
r2 = subprocess.run(RUN + ["import", "tests/simnet/snapshot6d.tsg", "tests/simnet/node-B/pkg-t"], capture_output=True, text=True)
print("MERKLE import:", json.loads(r2.stdout.strip().splitlines()[-1]))
shutil.rmtree("tests/simnet/node-B/pkg-t")
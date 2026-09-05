#!/usr/bin/env python3
"""RFC-001 schema cross-validation (closes the validator TODO — Audit-1 note).

Method: decision-level equivalence. For each sample (6 real vectors + ~28 mutations):
  A) jsonschema (draft 2020-12, specs/manifest-0.1.0.schema.json) — is it valid?
  B) tamga_validator.py (stdlib schema block) — is it a schema-family RED (otherwise ACCEPT /
     hash/imza ailesi RED mi)?
Claim: A-invalid ⇔ B-schema-RED. A divergence = drift: one of the two implementations deviates from RFC-001.

Run: .venv-jsonschema/bin/python tests/cross_validate_schema.py
Evidence: .evidence/VALIDASYON/<date>/schema-crossvalidation.log
"""
import copy, hashlib, json, pathlib, subprocess, sys, time

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
try:
    import jsonschema
except ImportError:
    print("ERROR: jsonschema missing — run with .venv-jsonschema/bin/python")
    sys.exit(2)

SCHEMA = json.loads((ROOT / "specs/manifest-0.1.0.schema.json").read_text(encoding="utf-8"))
VEC = ROOT / "tests/vectors"
SB = ROOT / "tests/simnet/.schemacheck"
OUT = []


def log(s):
    OUT.append(s)
    print(s)


def manual_verdict(pkg: pathlib.Path):
    r = subprocess.run([sys.executable, str(ROOT / "tamga_validator.py"), "validate", str(pkg)],
                       capture_output=True, text=True, cwd=str(ROOT))  # Audit-9 B20: cwd-independent
    msg = r.stdout.strip()
    schema_family = ("schema_violation" in msg or "unknown_field" in msg or
                     "unknown_capability" in msg or "unsupported_spec_version" in msg)
    return r.returncode == 0, msg, schema_family


def check(name, manifest: dict):
    pkg = SB / name
    pkg.mkdir(parents=True, exist_ok=True)
    (pkg / "tamga.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    (pkg / "agent.wasm").write_bytes((VEC / "tc-a1/agent.wasm").read_bytes())
    try:
        jsonschema.validate(manifest, SCHEMA)
        js_valid = True
        js_err = ""
    except jsonschema.ValidationError as ex:
        js_valid = False
        js_err = f"{list(ex.absolute_path)}: {ex.message[:70]}"
    accept, msg, sch_red = manual_verdict(pkg)
    agree = (not js_valid) == sch_red
    tag = "AGREE" if agree else "!!DRIFT!!"
    log(f"[{tag}] {name:24s} js={'valid' if js_valid else 'INVALID':8s} "
        f"validator={'ACCEPT' if accept else msg[:58]}")
    if not js_valid:
        log(f"{'':26s} js-hata: {js_err}")
    return agree


def mutants(base: dict):
    out = []

    def add(name, fn):
        m = copy.deepcopy(base)
        fn(m)
        out.append((name, m))

    add("m01-spec-yok", lambda m: m.pop("spec_version"))
    add("m02-spec-0.2.0", lambda m: m.update(spec_version="0.2.0"))
    add("m03-bilinmeyen-kok", lambda m: m.update(hack=1))
    add("m04-package-yok", lambda m: m.pop("package"))
    add("m05-ad-buyuk", lambda m: m["package"].update(name="BadName"))
    add("m06-ad-kisa", lambda m: m["package"].update(name="ab"))
    add("m07-semver-kotu", lambda m: m["package"].update(version="1.0"))
    add("m08-code-yok", lambda m: m["package"].pop("code"))
    add("m09-hash-hex-degil", lambda m: m["package"]["code"].update(wasm_sha256="zz" * 32))
    add("m10-hash-algo", lambda m: m["package"]["code"].update(hash_algo="sha512"))
    add("m11-target-0.2", lambda m: m["package"]["code"].update(target="wasi-0.2/component"))
    add("m12-proof-P9", lambda m: m["runtime"].update(min_proof_level="P9"))
    add("m13-limit-buyuk", lambda m: m["runtime"]["limits"].update(memory_mb=8192))
    add("m14-limit-bool", lambda m: m["runtime"]["limits"].update(cpu_ms_per_run=True))
    add("m15-limit-str", lambda m: m["runtime"]["limits"].update(io_mb_per_run="5"))
    add("m16-limit-eksik", lambda m: m["runtime"]["limits"].pop("io_mb_per_run"))
    add("m17-limit-bilinmeyen", lambda m: m["runtime"]["limits"].update(gpu=1))
    add("m18-snap-2", lambda m: m["memory"].update(snapshot_format="tamga-snapshot/2"))
    add("m19-crypto-aes", lambda m: m["memory"].update(crypto_suite="AES-GCM"))
    add("m20-cap-dup", lambda m: m.update(capabilities=["clock", "clock"]))
    add("m21-cap-cok", lambda m: m.update(capabilities=["fs", "net", "clock", "env", "random", "teleport"]))
    add("m22-cap-dizi-degil", lambda m: m.update(capabilities="clock"))
    add("m23-scheme-bos", lambda m: m["payment"]["schemes"].clear() if "payment" in m
        else m.update(payment={"schemes": []}))
    add("m24-scheme-yabanci", lambda m: m["payment"]["schemes"].__setitem__(0, "tamga-real/1")
        if "payment" in m and m["payment"].get("schemes")
        else m.update(payment={"schemes": ["tamga-real/1"]}))
    add("m25-sig-algo", lambda m: m["signature"].update(algo="rsa"))
    add("m26-sig-key-hex", lambda m: m["signature"].update(key="zz" * 32))
    add("m27-sig-sig-hex", lambda m: m["signature"].update(sig="zz" * 64))
    add("m28-sig-yok", lambda m: m.pop("signature"))
    return out


def main():
    import shutil
    shutil.rmtree(SB, ignore_errors=True)
    SB.mkdir(parents=True)
    base = json.loads((VEC / "tc-a1/tamga.json").read_text(encoding="utf-8"))
    if "payment" not in base:
        base["payment"] = {"schemes": ["tamga-sim/1"]}

    log(f"# RFC-001 schema cross-validation — {time.strftime('%FT%T%z')}")
    log(f"# jsonschema {jsonschema.__version__ if hasattr(jsonschema,'__version__') else '4.x'} · "
        f"schema: specs/manifest-0.1.0.schema.json (draft 2020-12) · validator: tamga_validator.py")
    log("")

    ok = 0; total = 0
    log("## Real vectors")
    for tc in ["tc-a1", "tc-a2", "tc-a3", "tc-a4", "tc-a5", "tc-a6"]:
        total += 1
        m = json.loads((VEC / tc / "tamga.json").read_text(encoding="utf-8"))
        if "payment" not in m:
            m["payment"] = {"schemes": ["tamga-sim/1"]}
        ok += check(tc, m)
    log("")

    log("## Mutation matrix (tc-a1 base)")
    for name, m in mutants(base):
        total += 1
        ok += check(name, m)
    log("")
    log(f"RESULT: {ok}/{total} AGREE — {'cross-validation CLEAN' if ok == total else 'DRIFT → RFC-001 fidelity must be fixed'}")
    shutil.rmtree(SB, ignore_errors=True)


if __name__ == "__main__":
    logf = ROOT / "kanit/VALIDASYON" / time.strftime("%F") / "schema-crossvalidation.log"
    logf.parent.mkdir(parents=True, exist_ok=True)
    import io
    buf = io.StringIO(); _old = sys.stdout; sys.stdout = buf
    try:
        main()
    finally:
        sys.stdout = _old
    text = buf.getvalue()
    print(text)
    with open(logf, "a", encoding="utf-8") as f:
        f.write(text)
    sys.exit(0 if "CLEAN" in text.splitlines()[-1] else 1)  # English since i18n: match the printed verdict

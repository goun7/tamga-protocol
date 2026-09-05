#!/usr/bin/env python3
"""Tamga Manifest Validator — RFC-001 v0.1-FINAL
Validation order (normative, RFC §5): 1) parse 2) schema 3) hash 4) signature
Exit code: 0=ACCEPT, 1=RED. Every verdict carries a one-line reason (evidence culture).
Dependency: PyNaCl only (ed25519). Schema validation hand-rolled with stdlib;
cross-validated with jsonschema (2026-09-05): 6 vectors + 28 mutations,
34/34 agreement with jsonschema — test: tests/cross_validate_schema.py
(run with .venv-jsonschema/bin/python; the core dependency stays unchanged).
Note: RFC 8785 (JCS) — this schema holds only string/integer values; sorted-compact
serialization is JCS-equivalent. If a float field is added, jcs() must be updated.
"""
import sys, json, hashlib, re, pathlib
from nacl.signing import SigningKey, VerifyKey

def jcs(obj) -> bytes:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")

def cmd_keygen(args):
    out = pathlib.Path(args[0]); out.mkdir(parents=True, exist_ok=True)
    sk = SigningKey.generate()
    for name, data in (("seed.hex", sk.encode().hex()), ("pub.hex", sk.verify_key.encode().hex())):
        f = out / name; f.write_text(data); f.chmod(0o600)   # Audit-1 F5
    print("keys written:", out)

def cmd_sign(args):
    mp, wp, kp = args
    m = json.loads(pathlib.Path(mp).read_text(encoding="utf-8"))
    m["package"]["code"]["wasm_sha256"] = hashlib.sha256(pathlib.Path(wp).read_bytes()).hexdigest()
    sk = SigningKey(bytes.fromhex(pathlib.Path(kp).read_text().strip()))
    m["signature"] = {"algo": "ed25519", "key": sk.verify_key.encode().hex(), "sig": ""}
    m["signature"]["sig"] = sk.sign(jcs(m)).signature.hex()
    pathlib.Path(mp).write_text(json.dumps(m, indent=2, ensure_ascii=False), encoding="utf-8")
    print("signed:", mp)

def validate(pkg: pathlib.Path):
    # Audit-1 F11: source limits (before reading)
    mf = pkg / "tamga.json"
    if not mf.exists(): return 1, "RED parse_error: tamga.json not found"
    if mf.stat().st_size > 262144: return 1, "RED resource_limit: tamga.json > 256KB"
    wf = pkg / "agent.wasm"
    if wf.exists() and wf.stat().st_size > 64 * 1024 * 1024: return 1, "RED resource_limit: agent.wasm > 64MB"
    try:
        m = json.loads(mf.read_text(encoding="utf-8"))
    except Exception as e:
        return 1, "RED parse_error: " + str(e)
    e = []
    def bad(loc, msg): e.append((loc, msg))
    if not isinstance(m, dict): return 1, "RED schema_violation: (root) not an object"

    TOP = {"spec_version", "package", "runtime", "memory", "capabilities", "payment", "signature"}
    for k in m:
        if k not in TOP: bad(f"(root).{k}", "unknown field (D3: strict rejection)")
    for k in ("spec_version", "package", "runtime", "memory", "capabilities", "signature"):
        if k not in m: bad(k, "required field missing")
    if m.get("spec_version") != "0.1.0": bad("spec_version", "const ihlali (0.1.0)")

    p = m.get("package")
    if isinstance(p, dict):
        for k in p:
            if k not in {"name", "version", "code"}: bad(f"package.{k}", "bilinmeyen alan")
        for k in ("name", "version", "code"):
            if k not in p: bad(f"package.{k}", "required field missing")
        if isinstance(p.get("name"), str) and not re.fullmatch(r"[a-z0-9][a-z0-9-]{2,31}", p["name"]):
            bad("package.name", "pattern ihlali")
        if isinstance(p.get("version"), str) and not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", p["version"]):
            bad("package.version", "invalid semver")
        c = p.get("code")
        if isinstance(c, dict):
            for k in c:
                if k not in {"wasm_sha256", "hash_algo", "target"}: bad(f"package.code.{k}", "bilinmeyen alan")
            if "wasm_sha256" in c and not (isinstance(c["wasm_sha256"], str) and re.fullmatch(r"[a-f0-9]{64}", c["wasm_sha256"])):
                bad("package.code.wasm_sha256", "must be 64-hex")
            if "hash_algo" in c and c["hash_algo"] != "sha256": bad("package.code.hash_algo", "const ihlali")
            if "target" in c and c["target"] != "wasi-0.3/component": bad("package.code.target", "const ihlali (D6)")
        elif "code" in p: bad("package.code", "expected an object")
    elif "package" in m: bad("package", "nesne bekleniyordu")

    r = m.get("runtime")
    if isinstance(r, dict):
        for k in r:
            if k not in {"min_proof_level", "limits"}: bad(f"runtime.{k}", "bilinmeyen alan")
        if r.get("min_proof_level") not in ("P0", "P1", "P2"): bad("runtime.min_proof_level", "enum ihlali")
        L = {"memory_mb": (16, 4096), "cpu_ms_per_run": (1, 60000), "io_mb_per_run": (0, 1024)}
        lim = r.get("limits")
        if isinstance(lim, dict):
            for k in lim:
                if k not in L: bad(f"runtime.limits.{k}", "bilinmeyen alan")
            for k, (lo, hi) in L.items():
                if k in lim:
                    v = lim[k]
                    if isinstance(v, bool) or not isinstance(v, int): bad(f"runtime.limits.{k}", "must be an integer")
                    elif not (lo <= v <= hi): bad(f"runtime.limits.{k}", f"out of range [{lo},{hi}]")
            for k in L:
                if k not in lim: bad(f"runtime.limits.{k}", "zorunlu alan eksik")
        elif "limits" in r: bad("runtime.limits", "nesne bekleniyordu")
        if "min_proof_level" not in r: bad("runtime.min_proof_level", "zorunlu alan eksik")
    elif "runtime" in m: bad("runtime", "nesne bekleniyordu")

    mem = m.get("memory")
    if isinstance(mem, dict):
        for k in mem:
            if k not in {"snapshot_format", "crypto_suite"}: bad(f"memory.{k}", "bilinmeyen alan")
        if mem.get("snapshot_format") != "tamga-snapshot/1": bad("memory.snapshot_format", "const ihlali")
        if mem.get("crypto_suite") != "XChaCha20-Poly1305": bad("memory.crypto_suite", "const ihlali")
    elif "memory" in m: bad("memory", "nesne bekleniyordu")

    caps = m.get("capabilities")
    if isinstance(caps, list):
        if len(caps) > 5: bad("capabilities", "maxItems 5 ihlali")
        if len({repr(c) for c in caps}) != len(caps): bad("capabilities", "uniqueItems ihlali")
        for c in caps:
            if c not in ("fs", "net", "clock", "env", "random"): bad("capabilities", f"bilinmeyen yetenek: {c!r}")
    elif "capabilities" in m: bad("capabilities", "dizi bekleniyordu")

    if "payment" in m:
        pay = m["payment"]
        if isinstance(pay, dict):
            for k in pay:
                if k != "schemes": bad(f"payment.{k}", "bilinmeyen alan")
            sch = pay.get("schemes")
            if isinstance(sch, list):
                if len(sch) < 1: bad("payment.schemes", "minItems 1 ihlali")
                for s in sch:
                    if s != "tamga-sim/1": bad("payment.schemes", f"const ihlali: {s!r}")
            else: bad("payment.schemes", "dizi bekleniyordu")
        else: bad("payment", "nesne bekleniyordu")

    sig = m.get("signature")
    if isinstance(sig, dict):
        for k in sig:
            if k not in {"algo", "key", "sig"}: bad(f"signature.{k}", "bilinmeyen alan")
        if sig.get("algo") != "ed25519": bad("signature.algo", "const ihlali")
        if "key" in sig and not (isinstance(sig["key"], str) and re.fullmatch(r"[a-f0-9]{64}", sig["key"])):
            bad("signature.key", "must be 64-hex")
        if "sig" in sig and not (isinstance(sig["sig"], str) and re.fullmatch(r"[a-f0-9]{128}", sig["sig"])):
            bad("signature.sig", "must be 128-hex")
    elif "signature" in m: bad("signature", "nesne bekleniyordu")

    if e:
        loc, msg = e[0]
        if loc == "spec_version": return 1, "RED unsupported_spec_version"
        if loc.startswith("capabilities"): return 1, "RED unknown_capability: " + msg
        if "bilinmeyen alan" in msg: return 1, "RED unknown_field: " + loc
        return 1, f"RED schema_violation: {loc}: {msg}"

    # 3) code integrity (D5)
    want = m["package"]["code"]["wasm_sha256"]
    got = hashlib.sha256((pkg / "agent.wasm").read_bytes()).hexdigest()
    if want != got: return 1, "RED code_hash_mismatch"

    # 4) signature (D2: JCS with sig emptied)
    sig = m["signature"]; probe = dict(m); probe["signature"] = {**sig, "sig": ""}
    try:
        VerifyKey(bytes.fromhex(sig["key"])).verify(jcs(probe), bytes.fromhex(sig["sig"]))
    except Exception:
        return 1, "RED signature_invalid"
    return 0, "ACCEPT manifest_ok"

def cmd_validate(args):
    rc, msg = validate(pathlib.Path(args[0]))
    print(msg); sys.exit(rc)

if __name__ == "__main__":
    USAGE = """tamga_validator.py — Tamga Protocol manifest/keystore validator

commands:
  keygen                          generate an agent seed (same primitive as the runner)
  sign <tamga.json> <agent.wasm> <seed.hex>
                                  bind the package: stamps code_hash + agent_id, signs the manifest
  validate <pkg-dir>              full RFC-001 manifest validation (schema + pins + policy)

RED output carries reason_code 1-18 (see docs/ARCHITECTURE.md §7).
"""
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help", "help"):
        print(USAGE)
        sys.exit(0 if len(sys.argv) >= 2 else 1)
    {"keygen": cmd_keygen, "sign": cmd_sign, "validate": cmd_validate}[sys.argv[1]](sys.argv[2:])

#!/usr/bin/env python3
"""Tamga Manifest Validator — RFC-001 v0.1-FINAL
Validation order (normative, RFC §5): 1) parse 2) schema 3) hash 4) signature
Exit code: 0=ACCEPT, 1=RED. Every verdict carries a one-line reason (evidence culture).
Dependency: PyNaCl only (ed25519). Schema validation hand-rolled with stdlib;
cross-validated with jsonschema (2026-09-05): 6 vectors + 28 mutations,
34/34 agreement with jsonschema — test: tests/cross_validate_schema.py
(run with `python3 tests/cross_validate_schema.py` after `pip install jsonschema`; the runner itself keeps zero mandatory deps beyond PyNaCl).
Note: RFC 8785 (JCS) — this schema holds only string/integer values; sorted-compact
serialization is JCS-equivalent. If a float field is added, jcs() must be updated.
"""
import sys, json, hashlib, os, re, pathlib
from nacl.signing import SigningKey, VerifyKey

def _secure_open(path):
    """Audit-9 B6 parity with the runner: create the file 0600 from the start —
    closes the post-write chmod window on plaintext key material."""
    return os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)

def jcs(obj) -> bytes:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")

def cmd_keygen(args):
    out = pathlib.Path(args[0]); out.mkdir(parents=True, exist_ok=True)
    sk = SigningKey.generate()
    for name, data in (("seed.hex", sk.encode().hex()), ("pub.hex", sk.verify_key.encode().hex())):
        fd = _secure_open(out / name)                      # Audit-9 B6 parity: atomic 0600
        with os.fdopen(fd, "w") as f:
            f.write(data)                                  # Audit-1 F5
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

def _latest_charge_binds(pkg: pathlib.Path) -> bool:
    try:
        recs = [json.loads(l) for l in (pkg / "ledger.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
        ch = [r for r in recs if r.get("op") == "charge"]
        return bool(ch) and any(k in ch[-1] for k in ("net_decl_sha256", "net_events_sha256", "net_mb"))
    except Exception:
        return False


def validate(pkg: pathlib.Path, known_prior_hashes=()):
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
            if k not in {"min_proof_level", "limits", "net"}: bad(f"runtime.{k}", "bilinmeyen alan")
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
        # RFC-007 R1: runtime.net — the manifest-embedded network declaration.
        # Shape-gate here (keys/types/ranges); full semantic gate (resolution,
        # duplicates) happens at declaration load in the runner — fail-closed there.
        if "net" in r:
            n = r["net"]
            if not isinstance(n, dict):
                bad("runtime.net", "nesne bekleniyordu")
            else:
                nk = set(n) - {"egress", "max_bytes_per_run", "timeout_s"}
                if nk: bad(f"runtime.net.{sorted(nk)[0]}", "bilinmeyen alan")
                eg = n.get("egress")
                if not isinstance(eg, list) or not (1 <= len(eg) <= 8):
                    bad("runtime.net.egress", "1..8 elemanlı liste bekleniyordu")
                else:
                    for i, ep in enumerate(eg):   # NOT 'e': shadows the error list!
                        if not isinstance(ep, str) or ":" not in ep:
                            bad(f"runtime.net.egress[{i}]", "host:port metni bekleniyordu")
                        else:
                            try:
                                p = int(ep.rpartition(":")[2])
                                if not (1 <= p <= 65535): bad(f"runtime.net.egress[{i}].port", "1..65535")
                            except ValueError:
                                bad(f"runtime.net.egress[{i}].port", "sayı bekleniyordu")
                mb = n.get("max_bytes_per_run")
                if isinstance(mb, bool) or not isinstance(mb, int) or not (1024 <= mb <= 8 * 1024 * 1024):
                    bad("runtime.net.max_bytes_per_run", "1024..8388608 aralığında tamsayı")
                ts = n.get("timeout_s")
                if isinstance(ts, bool) or not isinstance(ts, int) or not (1 <= ts <= 120):
                    bad("runtime.net.timeout_s", "1..120 aralığında tamsayı")
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

    # 3b) RFC-005A D12 (slice-2, founder-approved 2026-09-06) + RFC-007 R3 formalization:
    # the charge receipt must bind the ACTIVE net declaration. Two sources, one rule —
    #   net.json (v0.1 bridge):    bound bytes = the FILE bytes
    #   runtime.net (v0.2, R1):    bound bytes = sha256(jcs(runtime.net subtree))
    # A post-run swap of either source fails validation. R3 conditional-unity (D12):
    # the trio net_decl_sha256 / net_events_sha256 / net_mb enters the charge TOGETHER
    # or not at all (half-bound receipts are RED in ledger-verify; here we check the
    # binding of the LATEST charge against whichever source is active).
    ndf = pkg / "net.json"
    mj = pkg / "tamga.json"
    rnet_active = None
    if mj.is_file():
        try:
            _m = json.loads(mj.read_text(encoding="utf-8"))
            if isinstance(_m.get("runtime", {}).get("net"), dict):
                rnet_active = _m["runtime"]["net"]
        except Exception:
            pass
    if rnet_active is not None and ndf.is_file():
        return 1, "RED net_decl_ambiguous: both net.json and runtime.net declare policy"
    # R3 deletion-detection: a charge that Binds D12 while NO declaration source is
    # active means the bridge file was deleted after the run — no more silent stripping.
    if ndf.is_file() or rnet_active is not None or _latest_charge_binds(pkg):
        try:
            recs = [json.loads(l) for l in (pkg / "ledger.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
        except Exception:
            recs = []
        ch = [r for r in recs if r.get("op") == "charge"]
        if ch:
            _ci = len(recs) - 1 - recs[::-1].index(ch[-1])   # son-charge-index (geçiş-kanıtı-sonrası)
            if not ndf.is_file() and rnet_active is None:
                return 1, "RED net_binding_missing: receipt binds a net declaration but no declaration source is active (bridge deleted?)"
            # D12a across the R1 migration: a charge binds the canonical form of the
            # source that was active WHEN IT WAS WRITTEN. Migration re-homes the SAME
            # policy content (file bytes <-> jcs subtree are content-equivalent), so the
            # accept-set holds BOTH canonical forms of the ACTIVE declaration. What the
            # gate must still catch: a post-run CHANGE of policy content (any hash not
            # in the set) and a bridge resurrection/deletion that changes the source.
            import tamga_netproxy as _t
            cands = set(known_prior_hashes)   # migration pass-down (migrate-net's post-gate)
            # R1 geçiş-kanıtı (bayraksız-yol): charge'dan-SONRAKI zincirdeki migrate-net
            # kaydı eski-bağlamayı-taşır. Kaçış-kapısı-tamper'e-karşı-ŞİFRESEL: kayıt-chain-h
            # altında; burada-chain-bütünlüğü-quick-verify-edilir (F19) — sahte-kaydı-kırar.
            _mig = [r for r in recs[_ci + 1:] if r.get("op") == "migrate-net"]
            if _mig:
                _prev, _ok = "0" * 64, True
                for _r in recs:
                    _noh = {k: v for k, v in _r.items() if k not in ("h", "node_sig")}
                    if _r.get("prev") != _prev or _r.get("h") != hashlib.sha256(
                            (_r.get("prev", "") + jcs(_noh).decode("utf-8")).encode("utf-8")).hexdigest():
                        _ok = False; break
                    _prev = _r["h"]
                if not _ok:
                    return 1, "RED ledger_broken: migration evidence record fails chain integrity"
                for _mr in _mig:
                    cands.add(_mr["old_net_decl_sha256"])
            if ndf.is_file():
                cands.add(hashlib.sha256(ndf.read_bytes()).hexdigest())
            if rnet_active is not None:
                # the active SUBTREE form, and the same content under the v0.1
                # declaration shape (format key included) — the two canonical forms
                # migrate-net documents in decl_canonicals
                cands.add(hashlib.sha256(jcs(rnet_active)).hexdigest())
                sub = {k: rnet_active[k] for k in ("egress", "max_bytes_per_run", "timeout_s")}
                cands.add(hashlib.sha256(jcs({"format": _t.NET_FORMAT, **sub})).hexdigest())
            if not cands:
                return 1, "RED net_binding_missing: no declaration source could be read"
            bound = ch[-1].get("net_decl_sha256")
            if bound is None:
                return 1, "RED net_binding_missing: receipt has no net_decl_sha256 though a net declaration is active"
            if bound not in cands:
                return 1, "RED net_binding_mismatch: the active net declaration changed after the run (receipt binds the pre-run declaration)"
        if ndf.is_file():                      # strict-declaration gate: file source only;
            try:                               # the manifest source was already shape-gated
                import tamga_netproxy as _tnp  # above (schema block) and is signed (D2)
            except ImportError:
                return 1, "RED net_proxy_missing: net.json present but tamga_netproxy unavailable"
            try:
                _tnp.load_net_decl(str(ndf))
            except _tnp.NetDeclError as ex:
                return 1, "RED net_decl_reject: " + str(ex)

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

validate() exits non-zero on RED and prints the failure reason as plain text
(the runner, not the validator, emits machine-readable reason_code receipts).
"""
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help", "help"):
        print(USAGE)
        sys.exit(0 if len(sys.argv) >= 2 else 1)
    {"keygen": cmd_keygen, "sign": cmd_sign, "validate": cmd_validate}[sys.argv[1]](sys.argv[2:])

#!/usr/bin/env python3
"""Audit-7 — embedded-chain (slice-8/F24) attack simulation (simnet, no wasmtime).

Scope: three attacks against the `ledger_records` + `ledger_tip` surface of the snapshot body:
  A1 record-splice : a charge fee is inflated and re-encrypted → import + ledger-verify
  A2 tip-swap      : a fabricated ledger_tip → imported into a chained node and a fresh node
  A3 merkle-fold   : memory is tampered but graph_merkle is recomputed consistently

NOTE (honest limit): attacks use the simnet passphrase + seed; this is the STRONG
adversary who tampers with the chain despite knowing the seed. The real threat-model
adversary (a seed-less host) is weaker — this measures the mechanism's upper bound.
Evidence: .evidence/GUVENLIK/<date>/audit-7.log
"""
import json, os, pathlib, subprocess, sys, hashlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
os.chdir(ROOT)
os.environ.setdefault("TAMGA_KS_PASSPHRASE", "simnet-2026")

import tamga_runner as tr  # the runner's own crypto primitives

SB = ROOT / "tests/simnet/.audit7"
OUT = []


def sh(*args):
    r = subprocess.run([sys.executable, "tamga_runner.py", *args],
                       capture_output=True, text=True)
    return r.stdout.strip()


def log(s):
    OUT.append(s)
    print(s)


def parse_snap(p):
    data = pathlib.Path(p).read_bytes()
    hlen = int.from_bytes(data[4:8], "big")
    header = json.loads(data[8:8 + hlen].decode())
    return data, hlen, header


def craft(src, mutate):
    """decrypt the snapshot body → mutate(header, state) → re-encrypt."""
    data, hlen, header = parse_snap(src)
    # unwrap the seed from the keystore (with the simnet passphrase) — both body key and identity
    seed = tr.xdec(bytes.fromhex(header["keystore_blob"]["ct"]), b"",
                   bytes.fromhex(header["keystore_blob"]["nonce"]),
                   tr.kdf(tr.passphrase(), bytes.fromhex(header["keystore_blob"]["salt"])))
    state = json.loads(tr.xdec(data[8 + hlen:], json.dumps(header, ensure_ascii=False, sort_keys=True).encode(),
                               bytes.fromhex(header["body_nonce"]), tr.body_key(seed)).decode())
    header, state = mutate(header, state)
    body_nonce = os.urandom(24)
    header["body_nonce"] = body_nonce.hex()
    hb = json.dumps(header, ensure_ascii=False, sort_keys=True).encode()
    ct = tr.xenc(json.dumps(state, ensure_ascii=False).encode(), hb, body_nonce, tr.body_key(seed))
    forged = tr.MAGIC + len(hb).to_bytes(4, "big") + hb + ct
    return forged


def fresh(name):
    p = SB / name
    p.mkdir(parents=True, exist_ok=True)
    for f in ("tamga.json", "agent.wasm"):
        (p / f).write_bytes((ROOT / "tests/vectors/tc-a1" / f).read_bytes())
    return p


def main():
    import shutil
    shutil.rmtree(SB, ignore_errors=True)
    (SB / "pkgA").mkdir(parents=True)
    for f in ("tamga.json", "agent.wasm"):
        (SB / "pkgA" / f).write_bytes((ROOT / "tests/vectors/tc-a1" / f).read_bytes())
    seed = json.loads(sh("keygen"))["seed_hex"]
    sh("grant", str(SB / "pkgA"), "0.01", "audit7-hibe")
    # build memory without wasmtime (external-memory bridge — slice-4 mechanism)
    mi = sh("memory", str(SB / "pkgA"), "--import-json", "tests/simnet/memory-dersler.json")
    base = SB / "base.tsg"
    sh("export", str(SB / "pkgA"), "-o", str(base), "--seed", seed)
    log(f"# precondition: memory-import ok={json.loads(mi).get('ok') if mi.startswith('{') else mi[:80]}")

    # ---------- A1a: record-splice, WEAK adversary (does not recompute hashes) ----------
    def a1a(header, state):
        for rec in state.get("ledger_records", []):
            if rec.get("op") == "grant":
                rec["amount"] = 100.0            # grant inflated, h left stale
                break
        return header, state
    (SB / "a1a.tsg").write_bytes(craft(base, a1a))
    r1a = sh("import", str(SB / "a1a.tsg"), str(fresh("pkgB")))
    j1a_import = json.loads(r1a)
    ok1a = j1a_import.get("ok")
    v1a = sh("ledger-verify", str(SB / "pkgB"))
    j1a = json.loads(v1a)
    log(f"A1a splice (hash eski): import ok={ok1a} reason={j1a_import.get('reason_code')} {j1a_import.get('reason','')} "
        f"· hedef ledger-verify ok={j1a.get('ok')} broken_at={j1a.get('broken_at')}")
    if not ok1a and j1a_import.get("reason_code") == 14:
        log("A1a RESULT: import RED before installation (expected — after Audit-7 D4 hardening)")
    elif ok1a and j1a.get("ok") is False:
        log("A1a RESULT: the chain hash caught the weak tampering later (pre-fix behavior)")
    else:
        log("A1a RESULT: UNEXPECTED")

    # ---------- A1b: record-splice, STRONG adversary (recomputes the whole chain) ----------
    def a1b(header, state):
        prev = "0" * 64
        for i, rec in enumerate(state.get("ledger_records", []), start=1):
            if rec.get("op") == "grant":
                rec["amount"] = 100.0
            rec["seq"] = i; rec["prev"] = prev
            no_h = {k: v for k, v in rec.items() if k != "h"}
            rec["h"] = hashlib.sha256((rec["prev"] + tr.jcs(no_h)).encode()).hexdigest()
            prev = rec["h"]
        return header, state
    (SB / "a1b.tsg").write_bytes(craft(base, a1b))
    r1b = sh("import", str(SB / "a1b.tsg"), str(fresh("pkgB2")))
    ok1b = json.loads(r1b).get("ok")
    v1b = json.loads(sh("ledger-verify", str(SB / "pkgB2")))
    log(f"A1b splice (chain recomputed): import ok={ok1b} · target ledger-verify ok={v1b.get('ok')} balance={v1b.get('balance_sim')}")
    if ok1b and v1b.get("ok"):
        log("A1b RESULT: OPEN FINDING F25 — a seed-owner can install a self-consistent fake history on a fresh node; "
            "current countermeasures: D4 append-only (a chained target is never clobbered) + provenance note; "
            "the permanent fix is node-cosign under RFC-003 (the node key enters the record hash)")
    else:
        log("A1b RESULT: the strong adversary was caught too (no F25 — unexpectedly good)")

    # ---------- A2: tip-swap ----------
    fake_tip = hashlib.sha256(b"uydurulmus-tip").hexdigest()
    def a2(header, state):
        state["ledger_tip"] = fake_tip
        return header, state
    (SB / "a2.tsg").write_bytes(craft(base, a2))
    r2_fresh = sh("import", str(SB / "a2.tsg"), str(fresh("pkgC")))          # fresh node
    r2_chain = sh("import", str(SB / "a2.tsg"), str(SB / "pkgA"))            # zincirli node
    ok2f = json.loads(r2_fresh).get("ok")
    ok2c = json.loads(r2_chain).get("ok")
    rc2c = json.loads(r2_chain).get("reason_code")
    log(f"A2 tip-swap: fresh node ok={ok2f} (deferral note expected) · chained node ok={ok2c} reason={rc2c}")
    if ok2f and not ok2c and rc2c == 14:
        log("A2 RESULT: tip-binding RED on the chained node (expected); fresh node defers (known, below)")
    else:
        log("A2 RESULT: UNEXPECTED")

    # ---------- A3: merkle-fold (consistent tampering) ----------
    def a3(header, state):
        n0 = state["memory"]["nodes"][0]
        n0["text"] = "SALDIRI-DEGISTI"
        state["graph_merkle"] = tr._graph_merkle(state["memory"])
        return header, state
    (SB / "a3.tsg").write_bytes(craft(base, a3))
    r3 = sh("import", str(SB / "a3.tsg"), str(fresh("pkgD")))
    ok3 = json.loads(r3).get("ok")
    log(f"A3 merkle-fold (consistent tampering): import ok={ok3}")
    if ok3:
        log("A3 RESULT: ACCEPT — documented limit: a seed owner can mint consistent state (upper-bound adversary); merkle defends against seed-less hosts")
    else:
        log("A3 RESULT: CLAIM — caught")

    shutil.rmtree(SB, ignore_errors=True)
    log("")
    log("# Audit-7 script end — evaluation recorded in SECURITY-AUDIT.md (canonical Turkish)")
    return 0 if "BEKLENMEDİK" not in "\n".join(OUT) and "İDDİA" not in "\n".join(OUT) else 1


if __name__ == "__main__":
    logf = ROOT / os.environ.get("TAMGA_EVIDENCE_DIR", ".evidence") / "GUVENLIK" / __import__("time").strftime("%F") / "audit-7.log"
    logf.parent.mkdir(parents=True, exist_ok=True)
    import io
    buf = io.StringIO()
    _old = sys.stdout
    sys.stdout = buf
    try:
        _rc = main()
    finally:
        sys.stdout = _old
    text = buf.getvalue()
    print(text)
    with open(logf, "a", encoding="utf-8") as f:
        f.write(f"# audit-7 — {__import__('time').strftime('%FT%T%z')}\n" + text)
    sys.exit(_rc or 0)

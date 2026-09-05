#!/usr/bin/env python3
"""Tamga Runner — RFC-002 v0.1-FINAL implementation (Phase 1, slices 1/2/3)
Slice 3: REAL WASI 0.3 execution — the agent runs process-isolated under
wasmtime v48.0.1 (digest-verified); session stdout is written to pkg/session-N.stdout (0600) as evidence.
Evidence culture: every operation prints ONE LINE JSON to stdout; reason_code per RFC-002 §6 + E-3/E-5:
6=seed_invalid 7=snapshot_too_large 8=snapshot_replay_rollback 9=agent_identity_mismatch
10=memory_limit 11=runtime_limit 12=agent_run_failed 13=not_component.
D4 implementation: no fs preopens, no network (-S allow-ip denied) to wasmtime → default-deny.
D3: the agent key never touches disk. Honest limits: in-use memory is exposed to the host (§5);
--seed argv (E-2); KDF scrypt (→Argon2id RFC-004); sim fiyatlar (→RFC-003);
no RAM fee without real measurement (see cmd_run).
"""
import sys, os, json, hashlib, pathlib, time, getpass, subprocess, resource
from nacl.bindings import (crypto_aead_xchacha20poly1305_ietf_encrypt as xenc,
                           crypto_aead_xchacha20poly1305_ietf_decrypt as xdec)
from nacl.signing import SigningKey, VerifyKey
import tamga_validator as tv

MAGIC = b"TSG1"
SAFE_SNAP_MAX = 64 * 1024 * 1024          # Audit-1 F1
MAX_NOTE_BYTES = 65536                    # Audit-2 F12
MAX_INPUT_BYTES = 1 << 20                 # slice-11: input ≤ 1MiB (hash bound into the receipt)

def _fnv1a64(b):
    """FNV-1a 64-bit — byte-identical to tests/agent-src/src/main.rs (slice-11)."""
    h = 0xcbf29ce484222325
    for x in b:
        h ^= x
        h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    return h
MAX_NODES = 10000                         # Audit-2 F13
FEE_MEDIAN_N = 5                          # OQ-8: pilot median-window (founder decision 2026-09-05)
# slice-4 (E-6): RFC-002 formula verbatim — fee = cpu_h*price + ram_gb_s*price + io_mb*price
SIM_PRICE = {"cpu_saati": 0.002, "ram_gb_sn": 0.0005, "io_mb": 0.001}   # TODO: RFC-003 pinler
WASMTIME = str(pathlib.Path(__file__).resolve().parent / "tools" / "bin" / "wasmtime")

def out(ok, **kw):
    print(json.dumps({"ok": bool(ok), **kw}, ensure_ascii=False))
    return 0 if ok else 1

def kdf(passphrase: bytes, salt: bytes) -> bytes:
    return hashlib.scrypt(passphrase, salt=salt, n=2**15, r=8, p=1, dklen=32, maxmem=64 * 1024 * 1024)

def body_key(seed: bytes) -> bytes:
    return hashlib.blake2b(seed + b"tamga-body-v1", digest_size=32).digest()

def passphrase() -> bytes:
    p = os.environ.get("TAMGA_KS_PASSPHRASE") or getpass.getpass("keystore passphrase: ")
    if not p.strip():
        raise ValueError("empty passphrase")            # Audit-1 F7
    return p.encode()

def _seed_from(a):
    seed = bytes.fromhex(a[a.index("--seed") + 1])      # Audit-1 F3 (hex)
    if len(seed) != 32:                                  # Audit-9 B3: ed25519 tam 32 bayt
        raise ValueError("seed must be 32 bytes")
    return seed

def _secure_open(path, append=False):
    """Audit-9 B6: make the 0600 claim atomic — closes the post-write chmod window."""
    flags = os.O_WRONLY | os.O_CREAT | (os.O_APPEND if append else os.O_TRUNC)
    return os.open(path, flags, 0o600)

def _pkg(pkg):
    p = pathlib.Path(pkg)
    return p, p / "state.json", p / "ledger.jsonl"

def _load_state(sp):
    if sp.exists():
        st = json.loads(sp.read_text(encoding="utf-8"))
    else:
        st = {"format": "tamga-state/0", "sessions": 0,
              "memory_probe": ["kimligim-muhrudur-1", "hafizam-benimledir-2"]}
    if st.get("format") == "tamga-state/0":             # Audit-2 F14
        probes = st.pop("memory_probe", [])
        st["format"] = "tamga-state/1"
        st["memory"] = {"next_id": len(probes) + 1,
                        "nodes": [{"id": f"m{i+1}", "kind": "note", "text": t}
                                  for i, t in enumerate(probes)],
                        "edges": []}
    return st

def _mem(st):
    return st.setdefault("memory", {"next_id": 1, "nodes": [], "edges": []})

def _node_fp(node):
    """Audit-5 F22: content fingerprints for id-less external nodes (ADD-only dedup)."""
    core = {k: node.get(k) for k in ("kind", "text", "valid_from", "valid_to", "supersedes")}
    return hashlib.sha256(jcs(core).encode("utf-8")).hexdigest()

def _graph_merkle(mem):
    """RFC-004 D6: memory integrity digest — ordered hash over nodes+edges."""
    nh = {n["id"]: hashlib.sha256(jcs(n).encode("utf-8")).hexdigest()
          for n in mem.get("nodes", [])}
    eh = [hashlib.sha256(jcs(e).encode("utf-8")).hexdigest() for e in mem.get("edges", [])]
    return hashlib.sha256(jcs({"nodes": nh, "edges": eh}).encode("utf-8")).hexdigest()

def _ledger_head(lp):
    """Stream-verify the chain and return the tip (last h); broken/absent → (None, reason).
    node-cosign: node_sig is outside the hash input; its signature is verified separately."""
    if not lp.exists(): return None, "yok"
    prev_h, n = "0" * 64, 0
    with open(lp, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line: continue
            n += 1
            try:
                rec = json.loads(line)
                no_h = {k: v for k, v in rec.items() if k != "h" and k != "node_sig"}
                exp = hashlib.sha256((rec.get("prev", "") + jcs(no_h)).encode("utf-8")).hexdigest()
                if rec.get("prev") != prev_h or rec.get("h") != exp or rec.get("seq") != n:
                    return None, f"broken@{n}"
                if "node_sig" in rec and not _node_sig_ok(rec):
                    return None, f"node_sig_invalid@{n}"
                prev_h = rec["h"]
            except Exception:
                return None, f"broken@{n}"
    return prev_h, "ok"

def _tip_in_chain(lp, tip):
    """F21 countermeasure: is the tip hash a member of the chain (streaming)?"""
    with open(lp, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try:
                if json.loads(line).get("h") == tip: return True
            except Exception:
                return False
    return False

def _records_head(recs):
    """Audit-7: _ledger_head equivalent for the embedded record list.
    D4 zero-trust: import verifies internal integrity BEFORE installing the chain.
    node-cosign: node_sig is NOT in the hash input (h covers the body without node_sig;
    the signature itself is verified separately — _node_sig_ok)."""
    prev_h, n = "0" * 64, 0
    try:
        for rec in recs:
            n += 1
            no_h = {k: v for k, v in rec.items() if k != "h" and k != "node_sig"}
            exp = hashlib.sha256((rec.get("prev", "") + jcs(no_h)).encode("utf-8")).hexdigest()
            if rec.get("prev") != prev_h or rec.get("h") != exp or rec.get("seq") != n:
                return None, f"broken@{n}"
            if "node_sig" in rec and not _node_sig_ok(rec):
                return None, f"node_sig_invalid@{n}"
            prev_h = rec["h"]
    except Exception:
        return None, f"broken@{n}"
    return prev_h, "ok"

def _node_sig_ok(rec):
    """node-cosign integrity layer: did node_sig sign h with node_id's key?
    (trust-list policy is separate: _cosign_policy_ok — L1.)"""
    try:
        VerifyKey(bytes.fromhex(rec["node_id"])).verify(
            rec["h"].encode(), bytes.fromhex(rec["node_sig"]))
        return True
    except Exception:
        return False

# --- ledger hash chain (RFC-003 D4 draft decision; ADD-only seal lesson) ---
def jcs(d):
    return json.dumps(d, sort_keys=True, ensure_ascii=False, separators=(",", ":"))

def _node_key_from(a):
    """DESIGN-node-cosign (F25): '--node-key <hex>' optional node signing key.
    The node key is SEPARATE from the agent seed (operator key); like the agent seed,
    passing it via argv is covered by E-2 (simnet acceptance).
    Audit-10: if the FLAG is present but its value cannot be read, do NOT return None —
    the caller produces RED (flag_given=True, key=None), closing the silent-unsigned-record exploit."""
    try:
        idx = a.index("--node-key")
    except ValueError:
        return None
    try:
        key = bytes.fromhex(a[idx + 1])
    except (ValueError, IndexError):
        key = None
    if key is None or len(key) != 32:
        raise ValueError("node_key_invalid: --node-key must be 64-hex (32 bytes)")
    return key

def _ledger_append(lp, rec, node_key=None):
    """Append the record to the chain with seq+prev+h; returns the written line.
    node_key verilirse node-cosign L1: node_id + node_sig(=ed25519(h)) eklenir
    (DESIGN-node-cosign.md; pre-implementation of RFC-003 Open Question 4)."""
    lines = lp.read_text(encoding="utf-8").splitlines() if lp.exists() else []
    last = None
    for l in reversed(lines):
        if l.strip():
            last = json.loads(l); break
    prev = last["h"] if last else "0" * 64
    rec["seq"] = len([l for l in lines if l.strip()]) + 1
    rec["prev"] = prev
    rec["ts"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    if node_key:
        rec["node_id"] = SigningKey(node_key).verify_key.encode().hex()   # BEFORE h: the chain binds the node identity
    h = hashlib.sha256((prev + jcs(rec)).encode("utf-8")).hexdigest()
    if node_key:
        rec["node_sig"] = SigningKey(node_key).sign(h.encode()).signature.hex()  # signs h; OUTSIDE the hash input
    rec["h"] = h
    fd = _secure_open(lp, append=True)
    with os.fdopen(fd, "a") as f:
        f.write(jcs(rec) + "\n")
    os.chmod(lp, 0o600)
    return rec

def cmd_ledger_verify(a):
    """RFC-003 D7: stream-verify the chain (F19: no full-file loading)."""
    pkg = pathlib.Path(a[0]) if a else pathlib.Path(".")
    lp = pkg / "ledger.jsonl"
    if not lp.exists():
        # Quickstart finding (2026-09-05): a chain-less pkg is not broken — an empty chain
        # is a legitimate pre-genesis state; the genesis tip is valid (D7 ok=true-correct).
        return out(True, op="ledger-verify", lines=0, head="0" * 64,
                   note="empty chain: no records yet (genesis tip is valid)")
    prev_h, n, broken = "0" * 64, 0, None
    with open(lp, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line: continue
            n += 1
            try:
                rec = json.loads(line)
                no_h = {k: v for k, v in rec.items() if k != "h" and k != "node_sig"}
                exp = hashlib.sha256((rec.get("prev", "") + jcs(no_h)).encode("utf-8")).hexdigest()
                if rec.get("prev") != prev_h or rec.get("h") != exp or rec.get("seq") != n:
                    broken = rec.get("seq", n); break
                if "node_sig" in rec and not _node_sig_ok(rec):
                    broken = rec.get("seq", n); break
                prev_h = rec["h"]
            except Exception:
                broken = n; break
    if broken is not None:
        return out(False, op="ledger-verify", reason_code=14, broken_at=broken,
                   reason="ledger_broken")
    return out(True, op="ledger-verify", lines=n, head=prev_h,
               note="chain tip verified (RFC-003 D7 draft)")

def cmd_grant(a):
    """RFC-003 D5/D8: simnet grant record — appended to the chain."""
    pkg = pathlib.Path(a[0])
    try:
        amount = round(float(a[1]), 9)
    except Exception:
        return out(False, op="grant", reason_code=14, reason="ledger_broken: amount is not a number")
    if not (0 < amount <= 1e6):                          # Audit-4 F18
        return out(False, op="grant", reason_code=14,
                   reason="ledger_broken: amount outside (0,1e6]")
    note = a[2] if len(a) > 2 else ""
    mf = pkg / "tamga.json"
    name = json.loads(mf.read_text(encoding="utf-8"))["package"]["name"] if mf.exists() else pkg.name
    try:
        nk = _node_key_from(a)
    except ValueError as e:
        return out(False, op="grant", reason_code=6, reason=str(e))  # Audit-10: no silent-unsigned records
    rec = _ledger_append(pkg / "ledger.jsonl",
                         {"op": "grant", "pkg": name, "amount": amount, "note": note},
                         node_key=nk)
    return out(True, op="grant", seq=rec["seq"], h=rec["h"], amount=amount,
               node_id=rec.get("node_id") if "node_id" in rec else None,
               note="appended to chain (RFC-003 D5 draft)")

def cmd_keygen(a):
    seed = os.urandom(32)
    agent_id = SigningKey(seed).verify_key.encode().hex()
    return out(True, op="keygen", agent_id=agent_id, seed_hex=seed.hex(),
               note="D3: seed not written to disk; store it safely")

def cmd_run(a):
    pkg = pathlib.Path(a[0])
    try:
        seed = _seed_from(a)
    except ValueError as e:
        # Audit-9 B3: valid-hex but not-32-byte seed — RED before any run/fee is recorded
        return out(False, op="run", reason_code=6, reason="seed_invalid: " + str(e))
    except Exception:
        return out(False, op="run", reason_code=6, reason="seed_invalid")
    try:
        node_key = _node_key_from(a)                        # node-cosign (opt-in)
    except ValueError as e:
        return out(False, op="run", reason_code=6, reason=str(e))  # Audit-10
    rc, msg = tv.validate(pkg)
    if rc != 0: return out(False, op="run", reason_code=3, reason="manifest_reject: " + msg)
    manifest = json.loads((pkg / "tamga.json").read_text(encoding="utf-8"))
    limits = manifest["runtime"]["limits"]
    wb = (pkg / "agent.wasm").read_bytes()
    if wb[:4] != b"\x00asm" or len(wb) < 8 or wb[4] != 0x0D:      # RFC-001 §5-5: component sniff
        return out(False, op="run", reason_code=13, reason="not_component: wasi-0.3/component bekleniyor")
    if not pathlib.Path(WASMTIME).exists():
        return out(False, op="run", reason_code=12, reason="agent_run_failed: wasmtime yok: " + WASMTIME)
    # --- real run: process-isolated wasmtime; D4: no fs preopens, no network ---
    # slice-4 (Audit-3 F15): stdout is written to DISK, not memory; io limit from file size.
    _, sp0, _ = _pkg(pkg)
    agent_id = SigningKey(seed).verify_key.encode().hex()
    st0 = _load_state(sp0)  # know the session number in advance (for the evidence file name)
    # Audit-9 B7: pkg↔agent ownership binding — if the state belongs to one agent, another
    # agent's seed cannot run it (prevents memory/ledger clobbering; reason 18).
    owner = st0.get("agent_id")
    if owner and owner != agent_id:
        return out(False, op="run", reason_code=18,
                   reason=f"agent_ownership_mismatch: state belongs to {owner[:16]}…; "
                          f"given seed produces {agent_id[:16]}… (R7): use export/import to migrate")
    sess_no = st0.get("sessions", 0) + 1
    # slice-11: --input <file> — the input hash is bound into the receipt (input half of the replay contract)
    inp_sha = None
    _tf_name = None                  # D11 input copy (deleted after the run — privacy)
    stdin_src = subprocess.DEVNULL   # F16-cont: the agent never inherits the parent stdin
    if "--input" in a:
        ip = pathlib.Path(a[a.index("--input") + 1])
        try:
            if not ip.is_file():
                return out(False, op="run", reason_code=10,
                           reason=f"input_invalid: file not found: {ip}")
            if ip.stat().st_size > MAX_INPUT_BYTES:
                return out(False, op="run", reason_code=10,
                           reason=f"input_invalid: > {MAX_INPUT_BYTES}B (D11 limit)")
            inp_bytes = ip.read_bytes()
        except OSError as e:
            return out(False, op="run", reason_code=10, reason=f"input_invalid: {e}")
        import tempfile, hashlib as _h
        tf = tempfile.NamedTemporaryFile(delete=False)
        tf.write(inp_bytes); tf.close()
        stdin_src = open(tf.name, "rb")
        _tf_name = tf.name
        inp_sha = _h.sha256(inp_bytes).hexdigest()
    art = pkg / f"session-{sess_no}.stdout"
    ru0 = resource.getrusage(resource.RUSAGE_CHILDREN)   # child CPU measurement start
    t0 = time.monotonic()
    # Audit-9 B5: the io limit is enforced DURING the run (RLIMIT_FSIZE) — not checked
    # after the fact; the agent cannot fill the disk until timeout. (F15 closure)
    io_limit = limits["io_mb_per_run"] * (1 << 20)
    import tempfile
    try:
        fd = os.open(art, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)  # Audit-9 B6: atomik 0600
        try:
            with os.fdopen(fd, "wb") as af:
                proc = subprocess.run([WASMTIME, "run", str(pkg / "agent.wasm")],
                                      stdin=stdin_src,
                                      stdout=af, stderr=subprocess.STDOUT,
                                      timeout=limits["cpu_ms_per_run"] / 1000,
                                      env={},   # Audit-3 F16: host env never leaks into the engine process
                                      preexec_fn=lambda: resource.setrlimit(
                                          resource.RLIMIT_FSIZE, (io_limit, io_limit)))
        finally:
            if os.path.exists(art):
                os.chmod(art, 0o600)
    except subprocess.TimeoutExpired:
        art.unlink(missing_ok=True)
        if _tf_name:
            pathlib.Path(_tf_name).unlink(missing_ok=True)   # D11: input copy; deleted after the run
        return out(False, op="run", reason_code=11,
                   reason=f"runtime_limit: cpu_ms_per_run={limits['cpu_ms_per_run']}")
    dt_ms = max(1, int((time.monotonic() - t0) * 1000))
    ru1 = resource.getrusage(resource.RUSAGE_CHILDREN)
    cpu_s = max(0.001, (ru1.ru_utime + ru1.ru_stime) - (ru0.ru_utime + ru0.ru_stime))
    ram_mb = max(0.0, ru1.ru_maxrss / 1024)   # honest note: maxrss is a MAX across children; simnet spawns a single child
    if isinstance(stdin_src, object) and stdin_src is not subprocess.DEVNULL:
        try: stdin_src.close()
        except Exception: pass
        pathlib.Path(_tf_name).unlink(missing_ok=True)      # D11 input copy: deleted after the run (privacy)
    if proc.returncode != 0:
        tail = art.read_text(encoding="utf-8", errors="replace")[-200:].replace("\n", " ") if art.exists() else ""
        art.unlink(missing_ok=True)
        return out(False, op="run", reason_code=12,
                   reason=f"agent_run_failed: rc={proc.returncode}: {tail}")
    # slice-11: --require-proof — the agent stamps the LAST line of its stdout with
    # "TAMGA:<fnv1a64>"; the runner recomputes the fingerprint of preceding bytes → RED 12 on mismatch.
    if "--require-proof" in a:
        raw = art.read_bytes()
        try:
            head, tag = raw.rsplit(b"TAMGA:", 1)
            tag = tag.rstrip(b"\n")
            if len(tag) != 16 or any(c not in b"0123456789abcdef" for c in tag):
                raise ValueError
            if _fnv1a64(head) != int(tag, 16):
                raise ValueError
        except ValueError:
            art.unlink(missing_ok=True)
            return out(False, op="run", reason_code=12,
                       reason="output_proof_mismatch: TAMGA line does not match the preceding bytes")
    io_bytes = art.stat().st_size
    if io_bytes > limits["io_mb_per_run"] * (1 << 20):
        art.unlink(missing_ok=True)
        return out(False, op="run", reason_code=11,
                   reason=f"runtime_limit: io > {limits['io_mb_per_run']}MB")
    os.chmod(art, 0o600)
    # --- state + memory ---
    note = a[a.index("--note") + 1] if "--note" in a else None
    link = a[a.index("--link") + 1] if "--link" in a else None
    if note is not None and len(note.encode("utf-8")) > MAX_NOTE_BYTES:
        return out(False, op="run", reason_code=10,
                   reason=f"memory_limit: note > {MAX_NOTE_BYTES}B")   # Audit-2 F12
    _, sp, lp = _pkg(pkg)
    st = st0
    mem = _mem(st)
    if len(mem["nodes"]) >= MAX_NODES:
        return out(False, op="run", reason_code=10, reason=f"memory_limit: nodes >= {MAX_NODES}")
    st["sessions"] = st.get("sessions", 0) + 1
    st["last_run"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    link_ignored, nid = None, None
    sup = a[a.index("--supersedes") + 1] if "--supersedes" in a else None
    if note is not None:
        nid = f"m{mem['next_id']}"; mem["next_id"] += 1
        node = {"id": nid, "kind": "note", "text": note, "ts": st["last_run"]}
        if sup is not None:                                   # RFC-004 D2: ADD-only correction
            if not any(n["id"] == sup for n in mem["nodes"]):
                return out(False, op="run", reason_code=17,
                           reason=f"state_invalid: supersedes hedefi yok: {sup}")
            node["supersedes"] = sup
        mem["nodes"].append(node)
        if link is not None:
            if any(n["id"] == link for n in mem["nodes"]):
                mem["edges"].append([link, nid, "ref"])
            else:
                link_ignored = link
    mem["nodes"].append({"id": f"s{st['sessions']}", "kind": "session_marker",   # RFC-004 §3
                         "text": f"oturum {st['sessions']} basladi", "ts": st["last_run"]})
    # --- accounting FIRST (so state carries the fresh ledger_tip — RFC-004 D6) ---
    io_mb = round(io_bytes / (1 << 20), 6)
    cpu_saat = round(cpu_s / 3600, 9)
    ram_gb_sn = round((ram_mb / 1024) * (dt_ms / 1000), 9)
    # OQ-8 (founder decision 2026-09-05): pilot billing = MEDIAN of the last N jobs
    # (N=FEE_MEDIAN_N). D1's wall noise (OQ-8 finding: the same job can swing ~172x)
    # does not hit the customer's bill; a fair median window. The permanent rule is
    # settled with pilot data (recorded: ERC-8004 mapping §6 + OQ log).
    fee = round(cpu_saat * SIM_PRICE["cpu_saati"] + ram_gb_sn * SIM_PRICE["ram_gb_sn"]
                + io_mb * SIM_PRICE["io_mb"], 9)   # raw (verbatim) fee — recorded for transparency
    recent = []
    if lp.exists():
        try:
            recent = [r.get("fee_sim", 0) for r in
                      (json.loads(l) for l in lp.read_text(encoding="utf-8").splitlines() if l.strip())
                      if r.get("op") == "charge"]
        except Exception:
            recent = []
    recent = recent[-(FEE_MEDIAN_N - 1):]
    fees_for_median = sorted(recent + [fee])
    _mid = len(fees_for_median) // 2
    median_fee = (fees_for_median[_mid] if len(fees_for_median) % 2
                  else (fees_for_median[_mid - 1] + fees_for_median[_mid]) / 2)
    charge = _ledger_append(lp, {"op": "charge", "pkg": manifest["package"]["name"],
                        "session": st["sessions"], "engine": "wasmtime-v48.0.1",
                        "cpu_saat": cpu_saat, "ram_gb_sn": ram_gb_sn, "io_mb": io_mb,
                        "wall_ms": dt_ms, "fee_birebir": fee,
                        "stdout_sha256": hashlib.sha256(art.read_bytes()).hexdigest(),
                        **({"input_sha256": inp_sha} if inp_sha else {}),
                        "fee_sim": round(median_fee, 9)},
                        node_key=node_key)   # Dilim-5 + node-cosign (opt-in) + OQ-8 medyan
    st["format"] = "tamga-state/1"
    st["ledger_tip"] = charge["h"]                            # Dilim-6: F21 panzehiri
    st["graph_merkle"] = _graph_merkle(mem)
    st["agent_id"] = agent_id                                 # Audit-9 B7: ownership binding
    fd = _secure_open(sp)                                     # Audit-9 B6: atomik 0600
    with os.fdopen(fd, "w") as f:
        f.write(json.dumps(st, ensure_ascii=False))
    kw = {"op": "run", "pkg": manifest["package"]["name"], "agent_id": agent_id,
          "session": st["sessions"], "nodes": len(mem["nodes"]),
          "engine": "wasmtime-v48.0.1", "wall_ms": dt_ms, "cpu_saat": cpu_saat,
          "ram_gb_sn": ram_gb_sn, "io_mb": io_mb, "fee_sim": fee,
          "stdout_sha256": hashlib.sha256(art.read_bytes()).hexdigest(),
          "stdout_file": str(art)}
    if note is not None: kw["note_id"] = nid
    if link_ignored: kw["link_ignored"] = link_ignored
    return out(True, **kw)

def cmd_memory(a):
    pkg = pathlib.Path(a[0])
    _, sp, _ = _pkg(pkg)
    st = _load_state(sp)
    mem = _mem(st)
    # --- RFC-004 D7 — external-system JSON bridge (ADD-only import) ---
    if "--import-json" in a:
        src = pathlib.Path(a[a.index("--import-json") + 1])
        try:
            data = json.loads(src.read_text(encoding="utf-8"))
        except Exception as e:
            return out(False, op="memory-import", reason_code=17,
                       reason="state_invalid: unreadable json: " + str(e))
        if not isinstance(data, dict) or not isinstance(data.get("nodes"), list):
            return out(False, op="memory-import", reason_code=17,
                       reason="state_invalid: {format, nodes[]} bekleniyor")
        added, skipped = 0, 0
        ids = {n["id"] for n in mem["nodes"]}
        fps = {_node_fp(n) for n in mem["nodes"]}     # content fingerprints for id-less external nodes
        for node in data["nodes"]:
            if not isinstance(node, dict) or not isinstance(node.get("text"), str) \
               or not node.get("text").strip():
                return out(False, op="memory-import", reason_code=17,
                           reason="state_invalid: node has no text")
            if _node_fp(node) in fps:
                skipped += 1; continue                  # Audit-5 F22: id-less external-node dedup
            if len(node["text"].encode("utf-8")) > MAX_NOTE_BYTES:      # Audit-2 F12
                return out(False, op="memory-import", reason_code=10,
                           reason=f"memory_limit: note > {MAX_NOTE_BYTES}B")
            if len(mem["nodes"]) >= MAX_NODES:                          # Audit-2 F13
                return out(False, op="memory-import", reason_code=10,
                           reason=f"memory_limit: nodes >= {MAX_NODES}")
            raw = node.get("id")
            if raw and raw in ids:
                skipped += 1; continue                                   # ADD-only: existing nodes never change
            if raw and isinstance(raw, str) and raw[1:].isdigit():
                nid = raw; mem["next_id"] = max(mem["next_id"], int(nid[1:]) + 1)
            else:
                nid = f"m{mem['next_id']}"; mem["next_id"] += 1
            node["id"] = nid
            fps.add(_node_fp(node))
            node.setdefault("kind", "fact")                              # RFC-004 §3: external lessons are fact-kind
            node.setdefault("ts", time.strftime("%Y-%m-%dT%H:%M:%S%z"))
            mem["nodes"].append(node); ids.add(nid); added += 1
        for edge in data.get("edges", []):
            if isinstance(edge, list) and len(edge) >= 3 and edge not in mem["edges"]:
                mem["edges"].append(edge)
        st["format"] = "tamga-state/1"; st["graph_merkle"] = _graph_merkle(mem)
        fd = _secure_open(sp)  # Audit-9 B6: atomik 0600
        with os.fdopen(fd, "w") as f:
            f.write(json.dumps(st, ensure_ascii=False))
        return out(True, op="memory-import", added=added, skipped=skipped,
                   nodes=len(mem["nodes"]), note="ADD-only merge (RFC-004 D2/D7 draft)")
    if "--export-json" in a:
        dst = pathlib.Path(a[a.index("--export-json") + 1])
        payload = {"format": "tamga-memory/1", "nodes": mem["nodes"], "edges": mem["edges"],
                   "graph_merkle": _graph_merkle(mem)}
        dst.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        os.chmod(dst, 0o600)
        return out(True, op="memory-export", file=str(dst), nodes=len(mem["nodes"]),
                   edges=len(mem["edges"]), sha256=hashlib.sha256(dst.read_bytes()).hexdigest())
    q = a[a.index("--search") + 1] if "--search" in a else None
    nodes = [n for n in mem["nodes"] if q and q.lower() in json.dumps(n, ensure_ascii=False).lower()] if q else mem["nodes"]
    return out(True, op="memory", pkg=pkg.name, count=len(nodes), nodes=nodes,
               edges=mem["edges"] if not q else [])

def cmd_export(a):
    pkg = pathlib.Path(a[0])
    try:
        dst = pathlib.Path(a[a.index("-o") + 1]); seed = _seed_from(a)
    except ValueError as e:
        return out(False, op="export", reason_code=6, reason="seed_invalid: " + str(e))
    except Exception:
        return out(False, op="export", reason_code=6, reason="seed_invalid")
    if not (pkg / "tamga.json").exists():
        # Audit-9 B11: traceback proven in quickstart.log — a JSON contract is required
        return out(False, op="export", reason_code=3, reason="manifest_reject: tamga.json yok")
    try:
        agent_id = SigningKey(seed).verify_key.encode().hex()
        _, sp, lp_x = _pkg(pkg)
        state = sp.read_bytes() if sp.exists() else b"{}"
        # slice-8 / F24: the chain travels with the body (portability invariant D3)
        ledger_records = [json.loads(l) for l in lp_x.read_text(encoding="utf-8").splitlines() if l.strip()] if lp_x.exists() else []
        st_obj = json.loads(state.decode("utf-8")) if state.strip() else {}
        st_obj["ledger_records"] = ledger_records
        state = json.dumps(st_obj, ensure_ascii=False).encode("utf-8")
        ks_nonce, body_nonce, salt = os.urandom(24), os.urandom(24), os.urandom(16)
        ks_ct = xenc(seed, b"", ks_nonce, kdf(passphrase(), salt))
        blob = {"kdf": "scrypt", "n": 2**15, "r": 8, "p": 1, "salt": salt.hex(),
                "nonce": ks_nonce.hex(), "ct": ks_ct.hex()}
        manifest = json.loads((pkg / "tamga.json").read_text(encoding="utf-8"))
        # Audit-2/E-4: pkg_name kanonik sahip = RFC-001 package.name
        header = {"format": "tamga-snapshot/1", "pkg_name": manifest["package"]["name"],
                  "pkg_wasm_sha256": manifest["package"]["code"]["wasm_sha256"],
                  "agent_id": agent_id, "cipher": "XChaCha20-Poly1305",
                  "keystore_blob": blob, "body_nonce": body_nonce.hex(),
                  "created": time.strftime("%Y-%m-%dT%H:%M:%S%z")}
        hb = json.dumps(header, ensure_ascii=False, sort_keys=True).encode("utf-8")
        ct = xenc(state, hb, body_nonce, body_key(seed))
        data = MAGIC + len(hb).to_bytes(4, "big") + hb + ct
        fd = _secure_open(dst)  # Audit-9 B6: atomik 0600
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        return out(True, op="export", pkg=pkg.name, file=str(dst), sha256=hashlib.sha256(data).hexdigest(),
                   bytes=len(data), note="D3: key not written to disk, traveled inside the encrypted keystore blob")
    except ValueError:
        return out(False, op="export", reason_code=4, reason="keystore_unlock_failed")

def _check_header(header):
    need_str = ("format", "pkg_name", "pkg_wasm_sha256", "agent_id", "cipher", "body_nonce", "created")
    if not isinstance(header, dict): return False
    for k in need_str:
        if not isinstance(header.get(k), str): return False
    if header["format"] != "tamga-snapshot/1": return False
    if header["cipher"] != "XChaCha20-Poly1305": return False
    if len(header["pkg_wasm_sha256"]) != 64 or len(header["agent_id"]) != 64: return False
    if len(header["body_nonce"]) != 48: return False
    b = header.get("keystore_blob")
    if not isinstance(b, dict): return False
    for k in ("kdf", "n", "r", "p", "salt", "nonce", "ct"):
        if k not in b: return False
    return isinstance(b["salt"], str) and isinstance(b["nonce"], str) and isinstance(b["ct"], str)

def cmd_keygen_node(a):
    """node-cosign (DESIGN-node-cosign.md): operator node key — written to disk
    with 0600 (unlike the agent seed; D3 only forbids the agent seed on disk).
    Usage: keygen-node <dir>"""
    out_d = pathlib.Path(a[0]); out_d.mkdir(parents=True, exist_ok=True)
    sk = SigningKey.generate()
    fd = _secure_open(out_d / "node_seed.hex")
    with os.fdopen(fd, "w") as f:
        f.write(sk.encode().hex())   # Audit-9 B6: atomic 0600 (operator private key)
    (out_d / "node_pub.hex").write_text(sk.verify_key.encode().hex())
    return out(True, op="keygen-node", dir=str(out_d), node_id=sk.verify_key.encode().hex(),
               note="node key written 0600 (operator identity; D3 applies to the agent seed only)")

def _cosign_policy(a):
    """import policy: --cosign-policy L0|L1 (default L0) + --node-trust <file>
    (required for L1; JSON array of trusted node_id hex strings)."""
    pol = "L0"
    try:
        if "--cosign-policy" in a: pol = a[a.index("--cosign-policy") + 1]
    except IndexError:
        pol = "L0"   # Audit-9 B11: a value-less flag means default, not a crash
    if pol not in ("L0", "L1"): pol = "L0"
    trust = None
    if "--node-trust" in a:
        try:
            trust = set(json.loads(pathlib.Path(a[a.index("--node-trust") + 1]).read_text(encoding="utf-8")))
        except Exception:
            trust = None
    return pol, trust

def cmd_import(a):
    if len(a) < 2: return out(False, op="import", reason_code=2, reason="snapshot_header_invalid: missing argument")
    snap = pathlib.Path(a[0]); pkg = pathlib.Path(a[1])
    try:
        if snap.stat().st_size > SAFE_SNAP_MAX:
            return out(False, op="import", reason_code=7, reason="snapshot_too_large")
        data = snap.read_bytes()
    except OSError as e:
        return out(False, op="import", reason_code=1, reason="snapshot_bad_magic: " + str(e))
    if data[:4] != MAGIC: return out(False, op="import", reason_code=1, reason="snapshot_bad_magic")
    hlen = int.from_bytes(data[4:8], "big")
    try:
        header = json.loads(data[8:8 + hlen].decode("utf-8"))
    except Exception as e:
        return out(False, op="import", reason_code=2, reason="snapshot_header_invalid: " + str(e))
    if not _check_header(header):
        return out(False, op="import", reason_code=2, reason="snapshot_header_invalid: field schema")
    rc, msg = tv.validate(pkg)
    if rc != 0: return out(False, op="import", reason_code=3, reason="manifest_reject: " + msg)
    local = json.loads((pkg / "tamga.json").read_text(encoding="utf-8"))
    if local["package"]["code"]["wasm_sha256"] != header["pkg_wasm_sha256"]:
        return out(False, op="import", reason_code=2, reason="snapshot_header_invalid: pkg_wasm_sha256 mismatch")
    if local["package"]["name"] != header["pkg_name"]:
        return out(False, op="import", reason_code=2, reason="snapshot_header_invalid: pkg_name mismatch")
    blob = header["keystore_blob"]
    try:
        seed = xdec(bytes.fromhex(blob["ct"]), b"", bytes.fromhex(blob["nonce"]),
                    kdf(passphrase(), bytes.fromhex(blob["salt"])))
    except Exception:
        return out(False, op="import", reason_code=4, reason="keystore_unlock_failed")
    if SigningKey(seed).verify_key.encode().hex() != header["agent_id"]:
        return out(False, op="import", reason_code=9, reason="agent_identity_mismatch")
    # Audit-9 B7 (import side): do NOT clobber the state of another agent LIVING on the
    # target (migration = to an empty node; ownership transfer is a documented flow).
    _, sp_x, _ = _pkg(pkg)
    if sp_x.exists():
        try:
            cur_owner = json.loads(sp_x.read_text(encoding="utf-8")).get("agent_id")
        except Exception:
            cur_owner = None
        if cur_owner and cur_owner != header["agent_id"]:
            return out(False, op="import", reason_code=18,
                       reason=f"agent_ownership_mismatch: target state belongs to {cur_owner[:16]}…; "
                              f"snapshot belongs to {header['agent_id'][:16]}… (import into an empty node)")
    hb = json.dumps(header, ensure_ascii=False, sort_keys=True).encode("utf-8")
    try:
        state = xdec(data[8 + hlen:], hb, bytes.fromhex(header["body_nonce"]), body_key(seed))
        parsed = json.loads(state.decode("utf-8"))
    except Exception:
        return out(False, op="import", reason_code=2, reason="snapshot_header_invalid: body AEAD tag")
    _, sp, lp = _pkg(pkg)
    cur = json.loads(sp.read_text(encoding="utf-8")).get("sessions", 0) if sp.exists() else 0
    if parsed.get("sessions", 0) < cur:
        return out(False, op="import", reason_code=8, reason="snapshot_replay_rollback")
    # --- slice-6: deep verification (RFC-004 D6 / E-8) ---
    if "graph_merkle" in parsed:
        if _graph_merkle(parsed.get("memory", {})) != parsed["graph_merkle"]:
            return out(False, op="import", reason_code=17,
                       reason="state_invalid: graph_merkle mismatch")
    tip = parsed.get("ledger_tip")
    head, why = _ledger_head(lp)
    tip_note = "no local ledger — tip check deferred on a fresh node"
    if why not in ("ok", "yok"):
        # Audit-9 B4: accepting an import while the LOCAL chain is broken would write an
        # unverifiable snapshot ledger_tip into state — RED is required.
        return out(False, op="import", reason_code=14, reason="ledger_broken: local chain " + why)
    if head is not None and tip:
        if not _tip_in_chain(lp, tip):                        # Audit-4 F21: truncate/replace attack
            return out(False, op="import", reason_code=14,
                       reason="ledger_broken: snapshot ledger_tip not found in local chain (truncate/replace?)")
        tip_note = "tip verified in chain"
    # slice-8 / F24: the embedded chain is installed on the target node
    recs = parsed.get("ledger_records")
    if recs is not None:
        # Audit-7 (D4 zero-trust hardening): the embedded chain is integrity-checked BEFORE
        # installation — a broken chain is never written to the target; import RED.
        _, why_emb = _records_head(recs)
        if why_emb != "ok":
            return out(False, op="import", reason_code=14,
                       reason="ledger_broken: embedded chain " + why_emb)
        pol, trust = _cosign_policy(a)
        if pol == "L1":
            # node-cosign L1: every record must be node_sig-signed and its node_id on the trust list
            # OQ-3 (founder decision 2026-09-05): revocation list — the signatures of a retired
            # node are ALSO invalid (dropping it from the list is not enough; closes the
            # key-theft scenario). Revocation file: JSON array [node_id, ...].
            revoked = []
            rf = SB_NODE_REVOKED if False else None
            import json as _json
            try:
                idx = a.index("--node-revoked") if "--node-revoked" in a else -1
                if idx >= 0 and idx + 1 < len(a):
                    revoked = _json.loads(pathlib.Path(a[idx + 1]).read_text(encoding="utf-8"))
            except Exception:
                return out(False, op="import", reason_code=2,
                           reason="snapshot_header_invalid: --node-revoked file unreadable")
            bad = None
            for rec in recs:
                if "node_sig" not in rec:
                    bad = f"node_sig_eksik@{rec.get('seq')}"; break
                if revoked and rec.get("node_id") in revoked:
                    bad = f"node_id_iptal_edildi@{rec.get('seq')}"; break
                if not trust or rec.get("node_id") not in trust:
                    bad = f"node_id_untrusted@{rec.get('seq')}"; break
            if bad:
                return out(False, op="import", reason_code=14,
                           reason="ledger_broken: cosign-L1 " + bad)
        head2, why2 = _ledger_head(lp)
        if head2 is None and why2 in ("yok",):
            body2 = {k: v for k, v in parsed.items() if k != "ledger_records"}
            fd = _secure_open(sp)  # Audit-9 B6: atomik 0600
            with os.fdopen(fd, "w") as f:
                f.write(json.dumps(body2, ensure_ascii=False))
            fd = _secure_open(lp)  # Audit-9 B6: atomik 0600
            with os.fdopen(fd, "w") as f:
                for rec in recs:
                    f.write(jcs(rec) + "\n")
            tip_note += "; embedded chain installed (" + str(len(recs)) + " records)"
        else:
            tip_note += "; target chain exists — embedded chain did not clobber it (D4 append-only)"
    body_final = {k: v for k, v in parsed.items() if k != "ledger_records"}
    fd = _secure_open(sp)  # Audit-9 B6: atomik 0600
    with os.fdopen(fd, "w") as f:
        f.write(json.dumps(body_final, ensure_ascii=False))
    return out(True, op="import", pkg=pkg.name, agent_id=header["agent_id"],
               resumed_session=parsed.get("sessions", 0),
               memory_nodes=len(parsed.get("memory", {}).get("nodes", [])),
               note="AT-001e: identity from keystore, memory from body — restored")

def cmd_ledger(a):
    pkg = pathlib.Path(a[0]) if a else pathlib.Path(".")
    lp = pkg / "ledger.jsonl"
    recs = []
    if lp.exists():
        try:
            recs = [json.loads(l) for l in lp.read_text(encoding="utf-8").splitlines() if l.strip()]
        except Exception:
            return out(False, op="ledger", reason_code=14,
                       reason="ledger_broken: ledger.jsonl malformed JSON line")  # Audit-9 B11
    grants = sum(r["amount"] for r in recs if r["op"] == "grant")
    fees = sum(r["fee_sim"] for r in recs if r["op"] == "charge")
    return out(True, op="ledger", pkg=pkg.name, charges=sum(1 for r in recs if r["op"] == "charge"),
               grants=len([r for r in recs if r["op"] == "grant"]), fees_sim=round(fees, 9),
               balance_sim=round(grants - fees, 9))

if __name__ == "__main__":
    cmds = {"keygen": cmd_keygen, "run": cmd_run, "export": cmd_export,
            "import": cmd_import, "ledger": cmd_ledger, "memory": cmd_memory,
            "grant": cmd_grant, "ledger-verify": cmd_ledger_verify,
            "keygen-node": cmd_keygen_node}
    sys.exit(cmds[sys.argv[1]](sys.argv[2:]))

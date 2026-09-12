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
SIM_PRICE = {"cpu_saati": 0.002, "ram_gb_sn": 0.0005, "io_mb": 0.001}   # simnet constants; pinned in RFC-003 §7 (conformance row) — real prices are the Phase-2 pilot gate
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
        try:
            st = json.loads(sp.read_text(encoding="utf-8"))
            if not isinstance(st, dict):
                raise ValueError("state root is not an object")
        except Exception as e:                               # Audit-15 S5: bozuk-state
            raise SystemExit(out(False, op="run", reason_code=5,
                                 reason=f"state_invalid: unreadable state.json ({e}) — "
                                        "fail-closed; restore from export snapshot"))
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

MAX_LINE_BYTES = 1 * 1024 * 1024          # Audit-11 D1: satır-bombası panzehiri (grant-note+JSON-overhead üstü)

def _ledger_lines(lp):
    """Stream ledger.jsonl as parsed records (F19: no full-file loading).
    Audit-11 D1: a line beyond MAX_LINE_BYTES is yielded as a sentinel {} WITHOUT
    reading it fully — the chain prev/seq check flags it broken (fail-closed),
    memory stays bounded, and no 50MB line ever lands in RAM."""
    with open(lp, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try:
                if len(line.encode("utf-8")) > MAX_LINE_BYTES:
                    yield {}      # sentinel: break the chain check without absorbing the bomb
                    continue
                yield json.loads(line)
            except Exception:
                yield {}          # sentinel: _verify_chain's prev/seq check flags it broken

def _verify_chain(recs):
    """Single chain-verification core (RFC-003 D5/D7/D8) — one implementation, three callers
    (_ledger_head, _records_head, cmd_ledger_verify). Hash rule: node_sig is OUTSIDE the
    hash input; its signature is verified separately (_node_sig_ok).
    Returns (tip, "ok") or (None, "broken@<n>" / "node_sig_invalid@<n>")."""
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

def _ledger_head(lp):
    """Stream-verify the chain and return the tip (last h); broken/absent → (None, reason).
    node-cosign: node_sig is outside the hash input; its signature is verified separately."""
    if not lp.exists(): return None, "yok"
    return _verify_chain(_ledger_lines(lp))

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
    D4 zero-trust: import verifies internal integrity BEFORE installing the chain."""
    return _verify_chain(recs)

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

def _ledger_append(lp, rec, node_key=None, op="append"):
    """Append the record to the chain with seq+prev+h; returns the written line.
    node_key verilirse node-cosign L1: node_id + node_sig(=ed25519(h)) eklenir
    (DESIGN-node-cosign.md; pre-implementation of RFC-003 Open Question 4)."""
    # Audit-11 D1: streaming append — full-file load yok (F19 disiplin append-tarafında da).
    # Son-GEÇERLİ-h-taşıyan-kayıt aranır (bozuk/yabancı-son-satır-onun-ARDINA-eklenemez —
    # zincir-zaten-RED'li; append fail-closed: son-h-bilinmiyorsa-ekleme-RED).
    last_rec = None; n = 0
    if lp.exists():
        with open(lp, "r", encoding="utf-8") as f:
            for l in f:
                if not l.strip(): continue
                n += 1
                try:
                    cand = json.loads(l)
                    if cand.get("h"): last_rec = cand
                except Exception:
                    pass   # bozuk-satır: sayılır ama-h-yok → son-geçerli-kalır
    if last_rec is None and n > 0:
        return out(False, op=op, reason_code=14,
                   reason="ledger_broken: tail has no valid head record — refuse to append")
    prev = last_rec["h"] if last_rec else "0" * 64
    rec["seq"] = n + 1
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

def _delivery_hash_arg(a):
    """RFC-007 R2 (D10, founder-approved): --delivery-alg sha256|keccak256 — the run
    embeds an OPTIONAL labeled delivery digest into the charge record:
    delivery_hash = {"alg": ..., "hex": ...} over the stdout bytes (the deliverable).
    Label REQUIRED (safal207: keccak256 != sha256 — an unlabeled field invites
    fake agreement). Unknown alg or unparseable arg -> RED before the run starts."""
    if "--delivery-alg" not in a:
        return None, None
    i = a.index("--delivery-alg")
    if i + 1 >= len(a):
        return None, out(False, op="run", reason_code=1,
                         reason="usage: --delivery-alg requires sha256|keccak256")
    alg = a[i + 1]
    if alg not in ("sha256", "keccak256"):
        return None, out(False, op="run", reason_code=10,
                         reason=f"delivery_alg_invalid: {alg!r} — must be sha256|keccak256")
    return alg, None


def _digest(alg: str, data: bytes) -> str:
    if alg == "sha256":
        return hashlib.sha256(data).hexdigest()
    # Kök-modül (wheel'de-de-çözülür; 2026-09-11: tools/ yolu kurulumda kırılırdı)
    from tamga_keccak import keccak256
    return keccak256(data).hex()


def cmd_ledger_verify(a):
    """RFC-003 D7: stream-verify the chain (F19: no full-file loading)."""
    pkg = pathlib.Path(a[0]) if a else pathlib.Path(".")
    lp = pkg / "ledger.jsonl"
    if not lp.exists():
        # Quickstart finding (2026-09-05): a chain-less pkg is not broken — an empty chain
        # is a legitimate pre-genesis state; the genesis tip is valid (D7 ok=true-correct).
        return out(True, op="ledger-verify", lines=0, head="0" * 64,
                   note="empty chain: no records yet (genesis tip is valid)")
    tip, why = _verify_chain(_ledger_lines(lp))
    if why != "ok":
        broken_at = int(why.split("@")[1]) if "@" in why else 0
        return out(False, op="ledger-verify", reason_code=14, broken_at=broken_at,
                   reason="ledger_broken")
    # RFC-007 R2 (D10): shape-gate on any labeled delivery digest found in the chain.
    # alg must be sha256|keccak256 (safal207: label REQUIRED), hex must be 64-hex;
    # field absent = D4 silence (no gate). Shape fault ≠ chain break but it IS a RED:
    # a mislabeled digest would fake cross-ledger agreement.
    # RFC-007 R3 (D12 conditional unity): net_decl_sha256 / net_events_sha256 / net_mb
    # enter a charge TOGETHER or not at all. A half-bound charge would let an operator
    # claim some D12 evidence without carrying all of it — RED 10 per record.
    with open(lp, "r", encoding="utf-8") as f:
        for ln, line in enumerate(f, 1):
            if not line.strip():
                continue
            rec = json.loads(line)
            dh = rec.get("delivery_hash")
            if dh is not None:
                if not isinstance(dh, dict) or set(dh) != {"alg", "hex"} \
                        or dh["alg"] not in ("sha256", "keccak256") \
                        or not isinstance(dh["hex"], str) or len(dh["hex"]) != 64 \
                        or any(c not in "0123456789abcdef" for c in dh["hex"]):
                    return out(False, op="ledger-verify", reason_code=10, broken_at=ln,
                               reason="delivery_hash_invalid: "
                                      "expected {alg: sha256|keccak256, hex: 64-hex}")
            if rec.get("op") == "charge":
                present = {k for k in ("net_decl_sha256", "net_events_sha256", "net_mb")
                           if k in rec}
                if present and len(present) != 3:
                    return out(False, op="ledger-verify", reason_code=10, broken_at=ln,
                               reason="net_trio_incomplete: D12 fields enter the charge "
                                      f"together or not at all (got {sorted(present)})")
                nm = rec.get("net_mb")
                if nm is not None:
                    if isinstance(nm, bool) or not isinstance(nm, (int, float)) \
                            or round(float(nm), 6) != float(nm):
                        return out(False, op="ledger-verify", reason_code=10, broken_at=ln,
                                   reason="net_mb_format: must be a number rounded to "
                                          "6 decimal places (MiB, RFC-003 §11)")
    lines = sum(1 for line in open(lp, "r", encoding="utf-8") if line.strip())
    return out(True, op="ledger-verify", lines=lines, head=tip,
               note="chain tip verified (RFC-003 D7 draft)")

def cmd_grant(a):
    """RFC-003 D5/D8: simnet grant record — appended to the chain."""
    pkg = pathlib.Path(a[0])
    try:
        amount = round(float(a[1]), 9)
    except Exception:
        return out(False, op="grant", reason_code=1, reason="parse_error: amount is not a number")
    if not (0 < amount <= 1e6):                          # Audit-4 F18 (policy bound, not chain break)
        return out(False, op="grant", reason_code=1,
                   reason="parse_error: amount outside (0,1e6]")
    note = a[2] if len(a) > 2 else ""
    if len(note.encode("utf-8")) > MAX_NOTE_BYTES:      # Audit-2 F12 — grant-a-da-uygula
        return out(False, op="grant", reason_code=8,
                   reason=f"memory_limit: note > {MAX_NOTE_BYTES}B")
    mf = pkg / "tamga.json"
    name = json.loads(mf.read_text(encoding="utf-8"))["package"]["name"] if mf.exists() else pkg.name
    try:
        nk = _node_key_from(a)
    except ValueError as e:
        return out(False, op="grant", reason_code=6, reason=str(e))  # Audit-10: no silent-unsigned records
    rec = _ledger_append(pkg / "ledger.jsonl",
                         {"op": "grant", "pkg": name, "amount": amount, "note": note},
                         node_key=nk, op="grant")
    return out(True, op="grant", seq=rec["seq"], h=rec["h"], amount=amount,
               node_id=rec.get("node_id") if "node_id" in rec else None,
               note="appended to chain (RFC-003 D5 draft)")

def cmd_keygen(a):
    seed = os.urandom(32)
    agent_id = SigningKey(seed).verify_key.encode().hex()
    return out(True, op="keygen", agent_id=agent_id, seed_hex=seed.hex(),
               note="D3: seed not written to disk; store it safely")

def cmd_quickstart(a):
    """tamga quickstart <dir> — first-package wizard: template agent + fresh key +
    sign + validate + FIRST RUN + ledger-verify, one command, zero interaction.

    B1 roadmap item (founder-approved 2026-09-11). Onboarding sürtünmesini tek
    komuta indirir: yeni kullanıcı dokümante adımları takip etmek yerine tek
    satırda 'run + charge + zincir' deneyimini yaşar. Kanıt-kültürü: her adımın
    JSON-çıktısı AT-021 altında taze koşumla doğrulanır (tests/at021_quickstart.sh).
    """
    if not a or a[0] in ("-h", "--help"):
        print('usage: tamga quickstart <dir> [--name <package-name>] [--seed <hex>]')
        print('       creates <dir>/tamga.json + agent.wasm, signs, validates, runs, verifies')
        return 0 if a else 1
    target = pathlib.Path(a[0]).expanduser().resolve()
    name = "tamga-hosgeldin"
    seed_hex = None
    i = 1
    while i < len(a):
        if a[i] == "--name" and i + 1 < len(a):
            name = a[i + 1]; i += 2
        elif a[i] == "--seed" and i + 1 < len(a):
            seed_hex = a[i + 1]; i += 2
        else:
            return out(False, op="quickstart", reason=f"unknown flag: {a[i]}")

    import re as _re
    if not _re.fullmatch(r"[a-z0-9][a-z0-9-]{2,31}", name):
        return out(False, op="quickstart",
                   reason="name-invalid: [a-z0-9][a-z0-9-]{2,31} kuralına uymalı")

    # 1) template-agent — repo'dan (geliştirme) veya wheel'den (kurulum: templates/ paketi) gömülü-kopya
    root_here = pathlib.Path(__file__).resolve().parent
    for cand in (root_here / "tests" / "vectors" / "tc-a1",          # repo-checkout
                 root_here / "templates",                             # pip-install (templates pkg)
                 root_here.parent / "tests" / "vectors" / "tc-a1"):    # cwd-relative fallback
        if (cand / "agent.wasm").exists():
            tpl = cand; break
    else:
        return out(False, op="quickstart",
                   reason="template-missing: tc-a1 template agent bulunamadı (kurulum bozuk?)")

    if target.exists() and any(target.iterdir()):
        return out(False, op="quickstart",
                   reason=f"target-not-empty: {target} boş olmalı (üzerine yazma kültürü yok)")
    target.mkdir(parents=True, exist_ok=True)

    steps = []
    def step(ok_label, detail):
        steps.append({"step": len(steps) + 1, "what": ok_label, "detail": detail})

    # 2) taze-anahtar (D3: seed yalnız-stdouts)
    seed = bytes.fromhex(seed_hex) if seed_hex else os.urandom(32)
    if len(seed) != 32:
        return out(False, op="quickstart", reason="seed must be 32 bytes")
    sk = SigningKey(seed)
    agent_id = sk.verify_key.encode().hex()

    # 3) manifest (tc-a1 şablonundan; isim + hash taze)
    wasm_bytes = (tpl / "agent.wasm").read_bytes()
    m = json.loads((tpl / "tamga.json").read_text(encoding="utf-8"))
    m["package"]["name"] = name
    m["package"]["code"]["wasm_sha256"] = hashlib.sha256(wasm_bytes).hexdigest()
    m["signature"] = {"algo": "ed25519", "key": agent_id, "sig": ""}
    import tamga_validator as _tv
    m["signature"]["sig"] = sk.sign(_tv.jcs(m)).signature.hex()
    (target / "agent.wasm").write_bytes(wasm_bytes)
    (target / "tamga.json").write_text(json.dumps(m, indent=2, ensure_ascii=False) + "\n",
                                        encoding="utf-8")
    step("paket-olusturuldu", f"{target}/tamga.json + agent.wasm (template: tc-a1)")

    # 4) validate
    rc, msg = tv.validate(target)
    if rc != 0:
        return out(False, op="quickstart", reason="validate-RED: " + msg, steps=steps)
    step("manifest-ACCEPT", "imza + şema + hash-doyası doğrulandı")

    # 5) İLK-RUN (grant → run; motor bootstrap'i run kendi yapar)
    import contextlib, io as _io
    with contextlib.redirect_stdout(_io.StringIO()):
        g_rc = cmd_grant([str(target), "0.01", "quickstart-hibe"])
    if g_rc != 0:
        return out(False, op="quickstart", reason="grant-fail", steps=steps)
    step("hibe-yazildi", "grant 0.01 tamga-sim (ilk-ücret-çekmesi-icin)")
    # İLK-RUN — aynı-process (bootstrap quickstart'ta ensure_wasmtime'dan-sonra
    # r.WASMTIME'ı GÜNCELLEMİŞ-OLABİLİR; subprocess o yolu göremezdi)
    with contextlib.redirect_stdout(_io.StringIO()) as run_buf:
        r_rc = cmd_run([str(target), "--seed", seed.hex()])
    try:
        run_out = json.loads(run_buf.getvalue())
    except Exception:
        return out(False, op="quickstart", reason="run-fail",
                   run_stdout=run_buf.getvalue()[:400], steps=steps)
    if r_rc != 0 or not run_out.get("ok"):
        return out(False, op="quickstart",
                   reason="run-RED: " + str(run_out.get("reason")), steps=steps)
    step("ilk-kosum-tamam", f"fee={run_out.get('fee_sim')} wall_ms={run_out.get('wall_ms')}")

    # 6) ledger-verify
    with contextlib.redirect_stdout(_io.StringIO()):
        v_rc = cmd_ledger_verify([str(target)])
    if v_rc != 0:
        return out(False, op="quickstart", reason="ledger-verify-RED", steps=steps)
    step("zincir-dogrulandi", "ledger-verify: tüm kayıtlar yeniden-hesaplandı")

    return out(True, op="quickstart", dir=str(target), package=name,
               agent_id=agent_id, seed_hex=seed.hex(), steps=steps,
               next_steps=[
                 "seed_hex'i saklayın (tekrar basılmaz): export/transfer için gerekir",
                 f"python3 tamga_runner.py ledger {target} — zinciri görün",
                 f"python3 tamga_runner.py export {target} -o snapshot.tsg --seed <hex>",
               ],
               note="quickstart: D3 seed not written to disk; store it safely")

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
        return out(False, op="run", reason_code=13, reason="not_component: expected a WASI 0.3 component")
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
    # RFC-007 R2: optional labeled delivery digest (D10)
    delivery_alg, derr = _delivery_hash_arg(a)
    if derr is not None:
        return derr
    # slice-11: --input <file> — the input hash is bound into the receipt (input half of the replay contract)
    inp_sha = None
    _tf_name = None                  # D11 input copy (deleted after the run — privacy)
    stdin_src = subprocess.DEVNULL   # F16-cont: the agent never inherits the parent stdin
    if "--input" in a:
        ii = a.index("--input")
        if ii + 1 >= len(a):
            return out(False, op="run", reason_code=10, reason="input_invalid: --input requires a file argument")
        ip = pathlib.Path(a[ii + 1])
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
    # --- RFC-005A slice-2 (D12, founder-approved 2026-09-06): egress proxy wiring ---
    # The proxy starts ONLY when the package declares net.json (v0.1 packages keep
    # D4 untouched: no net.json -> no proxy, no receipt fields, byte-identical flow).
    # The wasmtime box still cannot open sockets (v48 CLI grants no outbound; the
    # experiment is recorded in RFC-005A §8), so this slice proves the runner-side
    # enforcement + binding: declaration pinning, byte/conn caps, D12 receipt fields.
    net_decl_sha = None
    net_events_sha = None
    net_mb = None
    net_proxy = None
    net_events_path = None
    # RFC-007 R1 (founder-approved 2026-09-07): the declaration lives EITHER in the
    # legacy bridge file net.json (v0.1; dual-read window = one release) OR in the
    # manifest's runtime.net subtree (v0.2). BOTH present = ambiguous policy → RED.
    net_decl_file = pkg / "net.json"
    net_decl_src = None            # None | "file" | "manifest"
    if net_decl_file.is_file():
        net_decl_src = "file"
    try:
        mjson = json.loads((pkg / "tamga.json").read_text(encoding="utf-8"))
        if isinstance(mjson.get("runtime", {}).get("net"), dict):
            if net_decl_src == "file":
                return out(False, op="run", reason_code=10,
                           reason="net_decl_ambiguous: both net.json and runtime.net "
                                  "declare policy — migrate-net removes the bridge file")
            net_decl_src = "manifest"
            rnet = dict(mjson["runtime"]["net"])
            rnet.setdefault("format", "tamga-net-declaration/1")
    except (json.JSONDecodeError, OSError):
        pass
    if net_decl_src is not None:
        try:
            import tamga_netproxy as tnp
        except ImportError:
            return out(False, op="run", reason_code=12,
                       reason="net_proxy_missing: net.json present but tamga_netproxy unavailable")
        try:
            if net_decl_src == "file":
                ndecl = tnp.load_net_decl(str(net_decl_file))
                net_decl_sha = hashlib.sha256(net_decl_file.read_bytes()).hexdigest()
            else:
                ndecl = tnp.validate_net_decl_dict(rnet)
                # D12a semantics under R1: the bound bytes are the canonical JCS of
                # the runtime.net subtree itself (byte-exact manifest sections vary
                # with whitespace/key order — the canonical form is the invariant).
                canon = tv.jcs(mjson["runtime"]["net"])
                net_decl_sha = hashlib.sha256(canon).hexdigest()
        except tnp.NetDeclError as e:
            return out(False, op="run", reason_code=10,
                       reason=f"net_decl_reject: {e}")
        net_events_path = pkg / f"net-events-{sess_no}.jsonl"
        net_proxy = tnp.TamgaProxy(ndecl, events_path=str(net_events_path))
        net_proxy_port = net_proxy.start()   # loopback ephemeral; stopped in the post-run block
        # proxy_start goes into the events log: the operator (and the box, once the
        # agent-side socket path exists) discovers the port there — one source of truth.
        net_proxy._log({"event": "proxy_start", "port": net_proxy_port,
                        "egress": ndecl["egress"]})
        net_proxy.port = net_proxy_port          # D13: shim connects as a proxy client
    art = pkg / f"session-{sess_no}.stdout"
    ru0 = resource.getrusage(resource.RUSAGE_CHILDREN)   # child CPU measurement start
    t0 = time.monotonic()
    # Audit-9 B5: the io limit is enforced DURING the run (RLIMIT_FSIZE) — not checked
    # after the fact; the agent cannot fill the disk until timeout. (F15 closure)
    io_limit = limits["io_mb_per_run"] * (1 << 20)
    import tempfile
    try:
        # RFC-006 D13 (founder-approved 2026-09-06): net.json'lu paketlerde çocuk-süreç
        # AKIŞLI çalışır (şim pompası) — istekler vekil-tünelinden geçer, yanıtlar
        # çocuk-stdin'e yazılır; net.json'suz paket ESKİ-YOL (subprocess.run, bayt-bayt).
        payload = None
        if stdin_src is not subprocess.DEVNULL:
            stdin_src.seek(0)
            payload = stdin_src.read()
            stdin_src.seek(0)
        if net_proxy is not None:
            import tamga_net_shim as shim
            rc, shim_ignored, shim_timeout = shim.run_streamed(
                [WASMTIME, "run", str(pkg / "agent.wasm")], str(art), ndecl,
                net_proxy, limits["cpu_ms_per_run"] / 1000, io_limit,
                stdin_payload=payload)
            if shim_timeout:
                raise subprocess.TimeoutExpired("wasmtime", limits["cpu_ms_per_run"] / 1000)
            class _P:  # minimal post-run contract compat (returncode surface)
                returncode = rc
            proc = _P()
        else:
            fd = os.open(art, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)  # Audit-9 B6
            with os.fdopen(fd, "wb") as af:
                proc = subprocess.run([WASMTIME, "run", str(pkg / "agent.wasm")],
                                      stdin=stdin_src,
                                      stdout=af, stderr=subprocess.STDOUT,
                                      timeout=limits["cpu_ms_per_run"] / 1000,
                                      env={},   # Audit-3 F16: host env never leaks into the engine process
                                      preexec_fn=lambda: resource.setrlimit(
                                          resource.RLIMIT_FSIZE, (io_limit, io_limit)))
        if os.path.exists(art):
            os.chmod(art, 0o600)
    except subprocess.TimeoutExpired:
        art.unlink(missing_ok=True)
        if _tf_name:
            pathlib.Path(_tf_name).unlink(missing_ok=True)   # D11: input copy; deleted after the run
        if net_proxy:
            net_proxy.stop()
        return out(False, op="run", reason_code=11,
                   reason=f"runtime_limit: cpu_ms_per_run={limits['cpu_ms_per_run']}")
    dt_ms = max(1, int((time.monotonic() - t0) * 1000))
    ru1 = resource.getrusage(resource.RUSAGE_CHILDREN)
    cpu_s = max(0.001, (ru1.ru_utime + ru1.ru_stime) - (ru0.ru_utime + ru0.ru_stime))
    ram_mb = max(0.0, ru1.ru_maxrss / 1024)   # honest note: maxrss is a MAX across children; simnet spawns a single child
    if stdin_src is not subprocess.DEVNULL:
        try: stdin_src.close()
        except Exception: pass
        pathlib.Path(_tf_name).unlink(missing_ok=True)      # D11 input copy: deleted after the run (privacy)
    if proc.returncode != 0:
        tail = art.read_text(encoding="utf-8", errors="replace")[-200:].replace("\n", " ") if art.exists() else ""
        art.unlink(missing_ok=True)
        if net_proxy:
            net_proxy.stop()
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
            if net_proxy:
                net_proxy.stop()
            return out(False, op="run", reason_code=12,
                       reason="output_proof_mismatch: TAMGA line does not match the preceding bytes")
    # RFC-006 D13: agent net-requests counted from the evidence itself (both paths —
    # the artifact scan is the single source of truth; curating it is forbidden).
    nreq = 0
    try:
        raw = art.read_bytes()
        nreq = raw.count(b"\nTAMGA-NET-1 ")
        if raw.startswith(b"TAMGA-NET-1 "):
            nreq += 1
    except OSError:
        pass
    io_bytes = art.stat().st_size
    if io_bytes > limits["io_mb_per_run"] * (1 << 20):
        art.unlink(missing_ok=True)
        if net_proxy:
            net_proxy.stop()
        return out(False, op="run", reason_code=11,
                   reason=f"runtime_limit: io > {limits['io_mb_per_run']}MB")
    # --- D12: collect proxy session results (RFC-005A slice-2) ---
    if net_proxy:
        net_proxy.stop()
        if net_proxy.capped:
            art.unlink(missing_ok=True)
            return out(False, op="run", reason_code=11,
                       reason=f"runtime_limit: net_bytes > {ndecl['max_bytes_per_run']} "
                              f"(session capped; byte-cap is a run-level hard path)")
        nsum = net_proxy.summary()
        net_mb = round(nsum["bytes_total"] / (1 << 20), 6)   # D12c: MiB-6-hane (RFC-003 §11)
        if net_events_path is not None and net_events_path.exists():
            os.chmod(net_events_path, 0o600)
            net_events_sha = hashlib.sha256(net_events_path.read_bytes()).hexdigest()
        else:
            # a session with zero connections still gets its (empty) log hashed
            net_events_path.write_bytes(b"")
            os.chmod(net_events_path, 0o600)
            net_events_sha = hashlib.sha256(b"").hexdigest()
    os.chmod(art, 0o600)
    # --- state + memory ---
    ni = a.index("--note") if "--note" in a else -1
    note = a[ni + 1] if ni >= 0 and ni + 1 < len(a) else (None if ni < 0 else "")
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
                        **({"net_decl_sha256": net_decl_sha,                  # RFC-005A D12
                            "net_events_sha256": net_events_sha,
                            "net_mb": net_mb} if net_decl_sha else {}),
                        **({"delivery_hash": {"alg": delivery_alg,             # RFC-007 R2 (D10)
                                              "hex": _digest(delivery_alg, art.read_bytes())}}
                           if delivery_alg else {}),
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
    if net_decl_sha is not None:                                     # RFC-005A D12
        kw["net_mb"] = net_mb
        kw["net_decl_sha256"] = net_decl_sha
    if delivery_alg:                                                 # RFC-007 R2 (D10)
        kw["delivery_hash"] = {"alg": delivery_alg,
                               "hex": _digest(delivery_alg, art.read_bytes())}
    if nreq:                                                         # RFC-006 D13
        kw["net_shim_ignored"] = nreq
    return out(True, **kw)

def cmd_memory(a):
    pkg = pathlib.Path(a[0])
    _, sp, _ = _pkg(pkg)
    st = _load_state(sp)
    mem = _mem(st)
    # --- RFC-004 D7 — external-system JSON bridge (ADD-only import) ---
    if "--import-json" in a:
        mi = a.index("--import-json")
        if mi + 1 >= len(a):
            return out(False, op="memory", reason_code=10, reason="input_invalid: --import-json requires a file argument")
        src = pathlib.Path(a[mi + 1])
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
    qi = a.index("--search") if "--search" in a else -1
    q = a[qi + 1] if qi >= 0 and qi + 1 < len(a) else (None if qi < 0 else "")
    nodes = [n for n in mem["nodes"] if q and q.lower() in json.dumps(n, ensure_ascii=False).lower()] if q else mem["nodes"]
    return out(True, op="memory", pkg=pkg.name, count=len(nodes), nodes=nodes,
               edges=mem["edges"] if not q else [])

def cmd_export(a):
    pkg = pathlib.Path(a[0])
    try:
        dst = pathlib.Path(a[a.index("-o") + 1])
    except Exception:
        return out(False, op="export", reason_code=1,
                   reason="parse_error: export requires -o <file> --seed <hex>")
    try:
        seed = _seed_from(a)
    except ValueError as e:
        return out(False, op="export", reason_code=6, reason="seed_invalid: " + str(e))
    except Exception:
        return out(False, op="export", reason_code=6, reason="seed_invalid")
    if not (pkg / "tamga.json").exists():
        # Audit-9 B11: traceback proven in quickstart.log — a JSON contract is required
        return out(False, op="export", reason_code=3, reason="manifest_reject: tamga.json not found")
    rc_m, msg_m = tv.validate(pkg)                       # B11+ (Tur-7): export deep-validates
    if rc_m != 0:
        return out(False, op="export", reason_code=3, reason="manifest_reject: " + msg_m)
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
            try:
                idx = a.index("--node-revoked") if "--node-revoked" in a else -1
                if idx >= 0 and idx + 1 < len(a):
                    revoked = json.loads(pathlib.Path(a[idx + 1]).read_text(encoding="utf-8"))
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

def cmd_migrate_net(a):
    """RFC-007 R1 (founder-approved 2026-09-07): net.json -> runtime.net migration.
    One-way. Requires the AUTHOR seed (--seed-hex): the manifest is re-signed with
    the SAME author identity (pubkey must match signature.key — the tool never
    invents identity). Bridge file deleted after a validator-ACCEPT post-gate."""
    usage = "usage: migrate-net <pkg> --seed-hex <64hex>"
    if len(a) != 3 or a[1] != "--seed-hex":
        return out(False, op="migrate-net", reason_code=1, reason=usage)
    pkg = pathlib.Path(a[0])
    mj, nj = pkg / "tamga.json", pkg / "net.json"
    lp = pkg / "ledger.jsonl"
    if not mj.is_file():
        return out(False, op="migrate-net", reason_code=1, reason="tamga.json not found")
    if not nj.is_file():
        return out(False, op="migrate-net", reason_code=1,
                   reason="net.json not found — nothing to migrate")
    m = json.loads(mj.read_text(encoding="utf-8"))
    if "net" in m.get("runtime", {}):
        return out(False, op="migrate-net", reason_code=1,
                   reason="runtime.net already present — package already migrated")
    import tamga_netproxy as tnp
    from tamga_validator import SigningKey
    ndecl = tnp.load_net_decl(str(nj))                    # strict gate FIRST (fail-closed)
    try:
        sk = SigningKey(bytes.fromhex(a[2]))
    except (ValueError, TypeError):
        return out(False, op="migrate-net", reason_code=6, reason="seed_invalid")
    if sk.verify_key.encode().hex() != m["signature"]["key"]:
        return out(False, op="migrate-net", reason_code=9,
                   reason="author_identity_mismatch: seed pubkey != manifest signature.key")
    old_canon = tv.jcs({"format": tnp.NET_FORMAT, "egress": ndecl["egress"],
                        "max_bytes_per_run": ndecl["max_bytes_per_run"],
                        "timeout_s": ndecl["timeout_s"]}).decode()
    net_sub = {"egress": ndecl["egress"],
               "max_bytes_per_run": ndecl["max_bytes_per_run"],
               "timeout_s": ndecl["timeout_s"]}
    new_canon = tv.jcs(net_sub).decode()
    m.setdefault("runtime", {})["net"] = net_sub
    probe = dict(m); probe["signature"] = {**m["signature"], "sig": ""}   # D2: sig-boş-probe
    m["signature"]["sig"] = sk.sign(tv.jcs(probe)).signature.hex()
    old_file_sha = hashlib.sha256(nj.read_bytes()).hexdigest()   # delete-öncesi: geçmiş-charge'lar
    mj.write_text(json.dumps(m, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")  # buna-bound-kaldı
    nj.unlink()
    # R1-geçiş-kanıtı zincirde: bayrak-yok-CLI-validate bile-geçmiş-charge'ın-dosya-baytı-
    # bağlamasını-bu-kayıtla-doğrulayabilir (validator-kaçış-kullanımı-chain-h-doğrulaması-ile)
    mig_rec = _ledger_append(lp, {"op": "migrate-net", "pkg": m["package"]["name"],
                                  "old_net_decl_sha256": old_file_sha,
                                  "new_net_decl_sha256": new_canon,
                                  "note": "RFC-007 R1 one-way bridge migration (content-equivalent)"})
    rc, msg = tv.validate(pkg, known_prior_hashes=(old_file_sha,))
    if rc != 0:
        return out(False, op="migrate-net", reason_code=1,
                   reason=f"post-migration validation RED: {msg[:160]}")
    return out(True, op="migrate-net", pkg=pkg.name,
               migrated="net.json -> runtime.net",
               decl_canonicals={"old_net.json_form": old_canon,
                                "new_runtime.net_form": new_canon},
               note="one-way; bridge deleted; author identity preserved; RFC-007 Q3: "
                    "D12a meaning follows the canonical form of the active source")

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

USAGE = """tamga_runner.py — Tamga Protocol agent runner (RFC-002)

commands:
  keygen                          generate an ed25519 agent seed (printed once, never stored)
  quickstart <dir> [--name n]     first-package wizard: template agent + sign + run + verify
  keygen-node                     generate a node keystore + node identity
  grant <pkg> <amount> <label>    record a grant in the package ledger
                                  flags: run/grant --node-key <f>; run --supersedes <n> --link <id>;
                                         import --cosign-policy L0|L1 --node-trust <f> --node-revoked <f>
  run <pkg> --seed <hex> [--input f] [--require-proof] [--note s]
                                  execute the agent (wasmtime), charge fee, append ledger
  export <pkg> -o <file> --seed <hex>
                                  seal a snapshot (memory + embedded chain) for migration
  import <file> <pkg> [--cosign-policy L0|L1] [--node-trust f]
                                  import a snapshot (deep verification)
  ledger <pkg>                    print the ledger
  ledger-verify <pkg>             recompute and verify the hash chain
  memory <pkg> [--search q] [--import-json f] [--export-json f]
                                  memory operations on the node state (flags, not subcommands)
  project-head <pkg> [-o f]       chain-head → batch-leaf projection (RFC-009/AT-022;
                                  engine-free) — outputs TAMGA_PROJECT_HEAD_V1 JSON

setup: bash tests/setup.sh installs the pinned wasmtime engine.
version: 0.2.0 (spec_version-flip 2026-09-11, kurucu-ONAYLI)
exit codes: 0 ok · 1 error/usage (RED receipts carry reason_code 1-18).
"""
if __name__ == "__main__":
    cmds = {"keygen": cmd_keygen, "quickstart": cmd_quickstart, "run": cmd_run,
            "export": cmd_export, "import": cmd_import, "ledger": cmd_ledger,
            "memory": cmd_memory, "grant": cmd_grant, "ledger-verify": cmd_ledger_verify,
            "keygen-node": cmd_keygen_node, "migrate-net": cmd_migrate_net}
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help", "help"):
        print(USAGE)
        sys.exit(0 if len(sys.argv) >= 2 else 1)  # bare invocation = usage error
    if sys.argv[1] not in cmds:
        print(f"unknown command: {sys.argv[1]}\n\n{USAGE}")
        sys.exit(1)
    sys.exit(cmds[sys.argv[1]](sys.argv[2:]))

#!/usr/bin/env python3
"""Tamga Runner — RFC-002 v0.1-FINAL gerçeklemesi (Faz 1 Dilim-1/2/3)
Dilim-3: GERÇEK WASI 0.3 koşumu — ajan, wasmtime v48.0.1 (digest-doğrulamalı) altında
süreç-izole çalışır; session stdout'u pkg/session-N.stdout'a (0600) kanıt olarak yazılır.
Kanıt kültürü: her işlem stdout'a TEK SATIR JSON; reason_code RFC-002 §6 + E-3/E-5:
6=seed_invalid 7=snapshot_too_large 8=snapshot_replay_rollback 9=agent_identity_mismatch
10=memory_limit 11=runtime_limit 12=agent_run_failed 13=not_component.
D4 gerçeklemesi: wasmtime'a fs preopen verilmez, ağ (-S allow-ip) verilmez → default-deny.
D3: ajan anahtarı diske yazılmaz. Dürüst sınırlar: in-use bellek host'a açık (§5);
--seed argv (E-2); KDF scrypt (→Argon2id RFC-004); sim fiyatlar (→RFC-003);
ram ücreti gerçek ölçüm olmadan alınmaz (bkz. cmd_run).
"""
import sys, os, json, hashlib, pathlib, time, getpass, subprocess, resource
from nacl.bindings import (crypto_aead_xchacha20poly1305_ietf_encrypt as xenc,
                           crypto_aead_xchacha20poly1305_ietf_decrypt as xdec)
from nacl.signing import SigningKey
import tamga_validator as tv

MAGIC = b"TSG1"
SAFE_SNAP_MAX = 64 * 1024 * 1024          # Audit-1 F1
MAX_NOTE_BYTES = 65536                    # Audit-2 F12
MAX_NODES = 10000                         # Audit-2 F13
# Dilim-4 (E-6): RFC-002 formülüne birebir — ucret = cpu_saat*fiyat + ram_gb_sn*fiyat + io*fiyat
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
    p = os.environ.get("TAMGA_KS_PASSPHRASE") or getpass.getpass("keystore parolası: ")
    if not p.strip():
        raise ValueError("empty passphrase")            # Audit-1 F7
    return p.encode()

def _seed_from(a):
    return bytes.fromhex(a[a.index("--seed") + 1])      # Audit-1 F3

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
    """Audit-5 F22: id'siz dış düğümlerin içerik parmakizleri (ADD-only dedup)."""
    core = {k: node.get(k) for k in ("kind", "text", "valid_from", "valid_to", "supersedes")}
    return hashlib.sha256(jcs(core).encode("utf-8")).hexdigest()

def _graph_merkle(mem):
    """RFC-004 D6: hafıza bütünlük özeti — düğüm+kenar hash'lerinin sıralı birleşimi."""
    nh = {n["id"]: hashlib.sha256(jcs(n).encode("utf-8")).hexdigest()
          for n in mem.get("nodes", [])}
    eh = [hashlib.sha256(jcs(e).encode("utf-8")).hexdigest() for e in mem.get("edges", [])]
    return hashlib.sha256(jcs({"nodes": nh, "edges": eh}).encode("utf-8")).hexdigest()

def _ledger_head(lp):
    """Zinciri akış halinde doğrulayıp uc (son h) döner; kırık/yok → (None, neden)."""
    if not lp.exists(): return None, "yok"
    prev_h, n = "0" * 64, 0
    with open(lp, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line: continue
            n += 1
            try:
                rec = json.loads(line)
                no_h = {k: v for k, v in rec.items() if k != "h"}
                exp = hashlib.sha256((rec.get("prev", "") + jcs(no_h)).encode("utf-8")).hexdigest()
                if rec.get("prev") != prev_h or rec.get("h") != exp or rec.get("seq") != n:
                    return None, f"kırık@{n}"
                prev_h = rec["h"]
            except Exception:
                return None, f"kırık@{n}"
    return prev_h, "ok"

def _tip_in_chain(lp, tip):
    """F21 panzehiri: tip hash'i zincirin bir üyesi mi (akış halinde)?"""
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
    """Audit-7: gömülü kayıt listesi için _ledger_head eşdeğeri.
    D4 zero-trust: import, zinciri kurmadan ÖNCE içsel bütünlüğünü doğrular."""
    prev_h, n = "0" * 64, 0
    try:
        for rec in recs:
            n += 1
            no_h = {k: v for k, v in rec.items() if k != "h"}
            exp = hashlib.sha256((rec.get("prev", "") + jcs(no_h)).encode("utf-8")).hexdigest()
            if rec.get("prev") != prev_h or rec.get("h") != exp or rec.get("seq") != n:
                return None, f"kırık@{n}"
            prev_h = rec["h"]
    except Exception:
        return None, f"kırık@{n}"
    return prev_h, "ok"

# --- Dilim-5: ledger hash-zinciri (RFC-003 D4 taslak kararı; MERGEN ÖZ/MÜHÜR dersi) ---
def jcs(d):
    return json.dumps(d, sort_keys=True, ensure_ascii=False, separators=(",", ":"))

def _ledger_append(lp, rec):
    """Kaydı seq+prev+h alanlarıyla zincire ekler; yazılan satırı döner."""
    lines = lp.read_text(encoding="utf-8").splitlines() if lp.exists() else []
    last = None
    for l in reversed(lines):
        if l.strip():
            last = json.loads(l); break
    prev = last["h"] if last else "0" * 64
    rec["seq"] = len([l for l in lines if l.strip()]) + 1
    rec["prev"] = prev
    rec["ts"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    h = hashlib.sha256((prev + jcs(rec)).encode("utf-8")).hexdigest()
    rec["h"] = h
    with open(lp, "a") as f:
        f.write(jcs(rec) + "\n")
    os.chmod(lp, 0o600)
    return rec

def cmd_ledger_verify(a):
    """RFC-003 D7: zinciri akış halinde doğrular (F19: tam-dosya yükleme yok)."""
    pkg = pathlib.Path(a[0]) if a else pathlib.Path(".")
    lp = pkg / "ledger.jsonl"
    if not lp.exists():
        # Quickstart bulgusu (2026-09-05): zincirsiz pkg bozuk değil — boş zincir
        # meşru doğum-öncesi durumdur; genesis ucu geçerli (D7 ok=doğru-zincir).
        return out(True, op="ledger-verify", lines=0, head="0" * 64,
                   note="boş zincir: henüz kayıt yok (genesis ucu geçerli)")
    prev_h, n, broken = "0" * 64, 0, None
    with open(lp, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line: continue
            n += 1
            try:
                rec = json.loads(line)
                no_h = {k: v for k, v in rec.items() if k != "h"}
                exp = hashlib.sha256((rec.get("prev", "") + jcs(no_h)).encode("utf-8")).hexdigest()
                if rec.get("prev") != prev_h or rec.get("h") != exp or rec.get("seq") != n:
                    broken = rec.get("seq", n); break
                prev_h = rec["h"]
            except Exception:
                broken = n; break
    if broken is not None:
        return out(False, op="ledger-verify", reason_code=14, broken_at=broken,
                   reason="ledger_broken")
    return out(True, op="ledger-verify", lines=n, head=prev_h,
               note="zincir ucuca dogru (RFC-003 D7 taslak)")

def cmd_grant(a):
    """RFC-003 D5/D8: simnet hibe kaydı — zincire eklenir."""
    pkg = pathlib.Path(a[0])
    try:
        amount = round(float(a[1]), 9)
    except Exception:
        return out(False, op="grant", reason_code=14, reason="ledger_broken: amount sayı değil")
    if not (0 < amount <= 1e6):                          # Audit-4 F18
        return out(False, op="grant", reason_code=14,
                   reason="ledger_broken: amount (0,1e6] dışında")
    note = a[2] if len(a) > 2 else ""
    mf = pkg / "tamga.json"
    name = json.loads(mf.read_text(encoding="utf-8"))["package"]["name"] if mf.exists() else pkg.name
    rec = _ledger_append(pkg / "ledger.jsonl",
                         {"op": "grant", "pkg": name, "amount": amount, "note": note})
    return out(True, op="grant", seq=rec["seq"], h=rec["h"], amount=amount,
               note="zincire eklendi (RFC-003 D5 taslak)")

def cmd_keygen(a):
    seed = os.urandom(32)
    agent_id = SigningKey(seed).verify_key.encode().hex()
    return out(True, op="keygen", agent_id=agent_id, seed_hex=seed.hex(),
               note="D3: seed diske yazılmadı; güvenli saklayın")

def cmd_run(a):
    pkg = pathlib.Path(a[0])
    try:
        seed = _seed_from(a)
    except Exception:
        return out(False, op="run", reason_code=6, reason="seed_invalid")
    rc, msg = tv.validate(pkg)
    if rc != 0: return out(False, op="run", reason_code=3, reason="manifest_reject: " + msg)
    manifest = json.loads((pkg / "tamga.json").read_text(encoding="utf-8"))
    limits = manifest["runtime"]["limits"]
    wb = (pkg / "agent.wasm").read_bytes()
    if wb[:4] != b"\x00asm" or len(wb) < 8 or wb[4] != 0x0D:      # RFC-001 §5-5: component sniff
        return out(False, op="run", reason_code=13, reason="not_component: wasi-0.3/component bekleniyor")
    if not pathlib.Path(WASMTIME).exists():
        return out(False, op="run", reason_code=12, reason="agent_run_failed: wasmtime yok: " + WASMTIME)
    # --- gerçek koşum: süreç-izole wasmtime; D4: fs preopen yok, ağ yok ---
    # Dilim-4 (Audit-3 F15): stdout belleğe değil DİSKÉ yazılır; io sınırı dosya boyutundan.
    _, sp0, _ = _pkg(pkg)
    st0 = _load_state(sp0)  # session no'yu önceden bil (kanıt dosyası adı için)
    sess_no = st0.get("sessions", 0) + 1
    art = pkg / f"session-{sess_no}.stdout"
    ru0 = resource.getrusage(resource.RUSAGE_CHILDREN)   # child CPU ölçüm başlangıcı
    t0 = time.monotonic()
    try:
        with open(art, "wb") as af:
            proc = subprocess.run([WASMTIME, "run", str(pkg / "agent.wasm")],
                                  stdout=af, stderr=subprocess.STDOUT,
                                  timeout=limits["cpu_ms_per_run"] / 1000,
                                  env={})   # Audit-3 F16: host env motor sürecine sızmaz
    except subprocess.TimeoutExpired:
        art.unlink(missing_ok=True)
        return out(False, op="run", reason_code=11,
                   reason=f"runtime_limit: cpu_ms_per_run={limits['cpu_ms_per_run']}")
    dt_ms = max(1, int((time.monotonic() - t0) * 1000))
    ru1 = resource.getrusage(resource.RUSAGE_CHILDREN)
    cpu_s = max(0.001, (ru1.ru_utime + ru1.ru_stime) - (ru0.ru_utime + ru0.ru_stime))
    ram_mb = max(0.0, ru1.ru_maxrss / 1024)   # dürüst not: maxrss çocuklar arası MAX'tır; simnet'te tek child baskındır
    if proc.returncode != 0:
        tail = art.read_text(encoding="utf-8", errors="replace")[-200:].replace("\n", " ") if art.exists() else ""
        art.unlink(missing_ok=True)
        return out(False, op="run", reason_code=12,
                   reason=f"agent_run_failed: rc={proc.returncode}: {tail}")
    io_bytes = art.stat().st_size
    if io_bytes > limits["io_mb_per_run"] * (1 << 20):
        art.unlink(missing_ok=True)
        return out(False, op="run", reason_code=11,
                   reason=f"runtime_limit: io > {limits['io_mb_per_run']}MB")
    os.chmod(art, 0o600)
    # --- durum + hafıza ---
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
        if sup is not None:                                   # RFC-004 D2: ADD-only düzeltme
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
    # --- muhasebe ÖNCE (state'e güncel ledger_tip yazılsın — RFC-004 D6) ---
    io_mb = round(io_bytes / (1 << 20), 6)
    cpu_saat = round(cpu_s / 3600, 9)
    ram_gb_sn = round((ram_mb / 1024) * (dt_ms / 1000), 9)
    fee = round(cpu_saat * SIM_PRICE["cpu_saati"] + ram_gb_sn * SIM_PRICE["ram_gb_sn"]
                + io_mb * SIM_PRICE["io_mb"], 9)
    charge = _ledger_append(lp, {"op": "charge", "pkg": manifest["package"]["name"],
                        "session": st["sessions"], "engine": "wasmtime-v48.0.1",
                        "cpu_saat": cpu_saat, "ram_gb_sn": ram_gb_sn, "io_mb": io_mb,
                        "wall_ms": dt_ms, "stdout_sha256": hashlib.sha256(art.read_bytes()).hexdigest(),
                        "fee_sim": fee})   # Dilim-5: zincire eklenir (RFC-003 D4 taslak)
    st["format"] = "tamga-state/1"
    st["ledger_tip"] = charge["h"]                            # Dilim-6: F21 panzehiri
    st["graph_merkle"] = _graph_merkle(mem)
    sp.write_text(json.dumps(st, ensure_ascii=False), encoding="utf-8")
    os.chmod(sp, 0o600)
    agent_id = SigningKey(seed).verify_key.encode().hex()
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
    # --- Dilim-6b: RFC-004 D7 — dış sistem (ilk sıra MERGEN) JSON köprüsü ---
    if "--import-json" in a:
        src = pathlib.Path(a[a.index("--import-json") + 1])
        try:
            data = json.loads(src.read_text(encoding="utf-8"))
        except Exception as e:
            return out(False, op="memory-import", reason_code=17,
                       reason="state_invalid: json okunamadı: " + str(e))
        if not isinstance(data, dict) or not isinstance(data.get("nodes"), list):
            return out(False, op="memory-import", reason_code=17,
                       reason="state_invalid: {format, nodes[]} bekleniyor")
        added, skipped = 0, 0
        ids = {n["id"] for n in mem["nodes"]}
        fps = {_node_fp(n) for n in mem["nodes"]}     # id'siz dış düğümler için içerik-parmakizi
        for node in data["nodes"]:
            if not isinstance(node, dict) or not isinstance(node.get("text"), str) \
               or not node.get("text").strip():
                return out(False, op="memory-import", reason_code=17,
                           reason="state_invalid: düğümde text yok")
            if _node_fp(node) in fps:
                skipped += 1; continue                  # Audit-5 F22: id'siz dış düğüm dedup
            if len(node["text"].encode("utf-8")) > MAX_NOTE_BYTES:      # Audit-2 F12
                return out(False, op="memory-import", reason_code=10,
                           reason=f"memory_limit: note > {MAX_NOTE_BYTES}B")
            if len(mem["nodes"]) >= MAX_NODES:                          # Audit-2 F13
                return out(False, op="memory-import", reason_code=10,
                           reason=f"memory_limit: nodes >= {MAX_NODES}")
            raw = node.get("id")
            if raw and raw in ids:
                skipped += 1; continue                                   # ADD-only: mevcut asla değişmez
            if raw and isinstance(raw, str) and raw[1:].isdigit():
                nid = raw; mem["next_id"] = max(mem["next_id"], int(nid[1:]) + 1)
            else:
                nid = f"m{mem['next_id']}"; mem["next_id"] += 1
            node["id"] = nid
            fps.add(_node_fp(node))
            node.setdefault("kind", "fact")                              # RFC-004 §3: dış dersler fact türü
            node.setdefault("ts", time.strftime("%Y-%m-%dT%H:%M:%S%z"))
            mem["nodes"].append(node); ids.add(nid); added += 1
        for edge in data.get("edges", []):
            if isinstance(edge, list) and len(edge) >= 3 and edge not in mem["edges"]:
                mem["edges"].append(edge)
        st["format"] = "tamga-state/1"; st["graph_merkle"] = _graph_merkle(mem)
        sp.write_text(json.dumps(st, ensure_ascii=False), encoding="utf-8"); os.chmod(sp, 0o600)
        return out(True, op="memory-import", added=added, skipped=skipped,
                   nodes=len(mem["nodes"]), note="ADD-only birleştirme (RFC-004 D2/D7 taslak)")
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
    except Exception:
        return out(False, op="export", reason_code=6, reason="seed_invalid")
    try:
        agent_id = SigningKey(seed).verify_key.encode().hex()
        _, sp, lp_x = _pkg(pkg)
        state = sp.read_bytes() if sp.exists() else b"{}"
        # Dilim-8 / F24: zincir gövdeyle seyahat eder (taşınabilirlik değişmezi D3)
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
        dst.write_bytes(data); os.chmod(dst, 0o600)
        return out(True, op="export", pkg=pkg.name, file=str(dst), sha256=hashlib.sha256(data).hexdigest(),
                   bytes=len(data), note="D3: anahtar diske yazılmadı, şifreli keystore blob ile taşındı")
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

def cmd_import(a):
    if len(a) < 2: return out(False, op="import", reason_code=2, reason="snapshot_header_invalid: argüman")
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
        return out(False, op="import", reason_code=2, reason="snapshot_header_invalid: alan şeması")
    rc, msg = tv.validate(pkg)
    if rc != 0: return out(False, op="import", reason_code=3, reason="manifest_reject: " + msg)
    local = json.loads((pkg / "tamga.json").read_text(encoding="utf-8"))
    if local["package"]["code"]["wasm_sha256"] != header["pkg_wasm_sha256"]:
        return out(False, op="import", reason_code=2, reason="snapshot_header_invalid: pkg_wasm_sha256 uyuşmuyor")
    if local["package"]["name"] != header["pkg_name"]:
        return out(False, op="import", reason_code=2, reason="snapshot_header_invalid: pkg_name uyuşmuyor")
    blob = header["keystore_blob"]
    try:
        seed = xdec(bytes.fromhex(blob["ct"]), b"", bytes.fromhex(blob["nonce"]),
                    kdf(passphrase(), bytes.fromhex(blob["salt"])))
    except Exception:
        return out(False, op="import", reason_code=4, reason="keystore_unlock_failed")
    if SigningKey(seed).verify_key.encode().hex() != header["agent_id"]:
        return out(False, op="import", reason_code=9, reason="agent_identity_mismatch")
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
    # --- Dilim-6: derin doğrulama (RFC-004 D6 / E-8) ---
    if "graph_merkle" in parsed:
        if _graph_merkle(parsed.get("memory", {})) != parsed["graph_merkle"]:
            return out(False, op="import", reason_code=17,
                       reason="state_invalid: graph_merkle uyuşmuyor")
    tip = parsed.get("ledger_tip")
    head, why = _ledger_head(lp)
    tip_note = "yerel ledger yok — tip kontrolü yeni node'da ertelendi"
    if head is not None and tip:
        if why != "ok":
            return out(False, op="import", reason_code=14, reason="ledger_broken: " + why)
        if not _tip_in_chain(lp, tip):                        # Audit-4 F21: truncate/replace saldırısı
            return out(False, op="import", reason_code=14,
                       reason="ledger_broken: snapshot ledger_tip yerel zincirde yok (truncate/replace?)")
        tip_note = "tip zincirde doğrulandı"
    # Dilim-8 / F24: gövdedeki zincir hedef node'a kurulur
    recs = parsed.get("ledger_records")
    if recs is not None:
        # Audit-7 (D4 zero-trust takviyesi): gömülü zincir KURULMADAN ÖNCE içsel
        # bütünlüğü doğrulanır — bozuk zincir artık hedefe yazılmaz, import RED.
        _, why_emb = _records_head(recs)
        if why_emb != "ok":
            return out(False, op="import", reason_code=14,
                       reason="ledger_broken: gömülü zincir " + why_emb)
        head2, why2 = _ledger_head(lp)
        if head2 is None and why2 in ("yok",):
            body2 = {k: v for k, v in parsed.items() if k != "ledger_records"}
            sp.write_text(json.dumps(body2, ensure_ascii=False), encoding="utf-8")
            with open(lp, "w", encoding="utf-8") as f:
                for rec in recs:
                    f.write(jcs(rec) + "\n")
            os.chmod(lp, 0o600)
            tip_note += "; gömülü zincir kuruldu (" + str(len(recs)) + " kayıt)"
        else:
            tip_note += "; hedefte zincir var — gömülü zincir yereli ezmedi (D4 append-only)"
    body_final = {k: v for k, v in parsed.items() if k != "ledger_records"}
    sp.write_text(json.dumps(body_final, ensure_ascii=False), encoding="utf-8")
    os.chmod(sp, 0o600)
    return out(True, op="import", pkg=pkg.name, agent_id=header["agent_id"],
               resumed_session=parsed.get("sessions", 0),
               memory_nodes=len(parsed.get("memory", {}).get("nodes", [])),
               note="AT-001e: kimlik keystore'dan, hafıza gövdeden restore")

def cmd_ledger(a):
    pkg = pathlib.Path(a[0]) if a else pathlib.Path(".")
    lp = pkg / "ledger.jsonl"
    recs = [json.loads(l) for l in lp.read_text(encoding="utf-8").splitlines() if l.strip()] if lp.exists() else []
    grants = sum(r["amount"] for r in recs if r["op"] == "grant")
    fees = sum(r["fee_sim"] for r in recs if r["op"] == "charge")
    return out(True, op="ledger", pkg=pkg.name, charges=sum(1 for r in recs if r["op"] == "charge"),
               grants=len([r for r in recs if r["op"] == "grant"]), fees_sim=round(fees, 9),
               balance_sim=round(grants - fees, 9))

if __name__ == "__main__":
    cmds = {"keygen": cmd_keygen, "run": cmd_run, "export": cmd_export,
            "import": cmd_import, "ledger": cmd_ledger, "memory": cmd_memory,
            "grant": cmd_grant, "ledger-verify": cmd_ledger_verify}
    sys.exit(cmds[sys.argv[1]](sys.argv[2:]))

#!/usr/bin/env python3
"""Audit-8 — node-cosign attack simulation (adversarial test of the F25 fix).

A1 (strong adversary): the attacker forges a WHOLE chain with THEIR OWN node key
   (seq/prev/h/node_id/node_sig from scratch) → ACCEPT under L0 (known remnant, policy
   decision OQ-1) / RED under L1 (node_id_untrusted) — proof that L1 closes F25.
A2 (signature layer): the honest node_id is KEPT but node_sig is produced with the
   attacker's key → two layers: node_id bound in the hash + signature tied to the
   node_id key → RED.
A3 (partial-cosign drop): node_sig is dropped from some records → RED under L1.

Evidence: .evidence/GUVENLIK/<date>/audit-8.log
"""
import hashlib, json, os, pathlib, shutil, subprocess, sys, time, io

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
os.chdir(ROOT)
os.environ.setdefault("TAMGA_KS_PASSPHRASE", "simnet-2026")

import tamga_runner as tr
from nacl.signing import SigningKey

SB = ROOT / "tests/simnet/.audit8"
OUT = []


def log(s):
    OUT.append(s)
    print(s)


def sh(*args):
    return subprocess.run([sys.executable, "tamga_runner.py", *args],
                          capture_output=True, text=True).stdout.strip()


def craft_cosigned(base_tsg, node_key_hex, mutate_records):
    """decrypt the body → mutate ledger_records → rebuild the whole chain (strong adversary)
    → re-encrypt."""
    data = pathlib.Path(base_tsg).read_bytes()
    hlen = int.from_bytes(data[4:8], "big")
    header = json.loads(data[8:8 + hlen])
    seed = tr.xdec(bytes.fromhex(header["keystore_blob"]["ct"]), b"",
                   bytes.fromhex(header["keystore_blob"]["nonce"]),
                   tr.kdf(tr.passphrase(), bytes.fromhex(header["keystore_blob"]["salt"])))
    state = json.loads(tr.xdec(data[8 + hlen:], json.dumps(header, ensure_ascii=False, sort_keys=True).encode(),
                               bytes.fromhex(header["body_nonce"]), tr.body_key(seed)).decode())
    state["ledger_records"] = mutate_records(state.get("ledger_records", []), node_key_hex)
    bn = os.urandom(24)
    header["body_nonce"] = bn.hex()
    hb = json.dumps(header, ensure_ascii=False, sort_keys=True).encode()
    ct = tr.xenc(json.dumps(state, ensure_ascii=False).encode(), hb, bn, tr.body_key(seed))
    return tr.MAGIC + len(hb).to_bytes(4, "big") + hb + ct


def forge_chain(records, node_key_hex):
    """strong adversary: rebuilds the chain from scratch — prev/h/node_id/node_sig all the attacker's."""
    sk = SigningKey(bytes.fromhex(node_key_hex))
    prev = "0" * 64
    out_recs = []
    for i, rec in enumerate(records, start=1):
        rec = {k: v for k, v in rec.items() if k not in ("seq", "prev", "h", "node_id", "node_sig")}
        rec["seq"] = i; rec["prev"] = prev
        rec["node_id"] = sk.verify_key.encode().hex()
        h = hashlib.sha256((rec["prev"] + tr.jcs(rec)).encode()).hexdigest()
        rec["node_sig"] = sk.sign(h.encode()).signature.hex()
        rec["h"] = h
        prev = h
        out_recs.append(rec)
    return out_recs


def fresh(name):
    p = SB / name
    p.mkdir(parents=True, exist_ok=True)
    for f in ("tamga.json", "agent.wasm"):
        (p / f).write_bytes((ROOT / "tests/vectors/tc-a1" / f).read_bytes())
    return p


def main():
    shutil.rmtree(SB, ignore_errors=True)
    (SB / "pkg").mkdir(parents=True)
    for f in ("tamga.json", "agent.wasm"):
        (SB / "pkg" / f).write_bytes((ROOT / "tests/vectors/tc-a1" / f).read_bytes())
    seed = json.loads(sh("keygen"))["seed_hex"]
    node = SB / "node"; sh("keygen-node", str(node))
    honest_nk = (node / "node_seed.hex").read_text().strip()
    sh("grant", str(SB / "pkg"), "0.05", "audit8", "--node-key", honest_nk)
    base = SB / "base.tsg"
    sh("export", str(SB / "pkg"), "-o", str(base), "--seed", seed)
    trust = SB / "trust.json"
    pathlib.Path(trust).write_text(json.dumps([(node / "node_pub.hex").read_text().strip()]))
    attacker_nk = SigningKey.generate().encode().hex()

    log(f"# Audit-8 node-cosign attacks — {time.strftime('%FT%T%z')}")

    # A1: a whole chain with the attacker's own node key
    forged = SB / "a1.tsg"
    forged.write_bytes(craft_cosigned(base, attacker_nk, lambda recs, nk: forge_chain(recs, nk)))
    r_l0 = json.loads(sh("import", str(forged), str(fresh("pkgL0"))))
    r_l1 = json.loads(sh("import", str(forged), str(fresh("pkgL1")),
                         "--cosign-policy", "L1", "--node-trust", str(trust)))
    log(f"A1 whole-chain forgery (attacker node key):")
    log(f"  L0: ok={r_l0.get('ok')} — known remnant: policy decision OQ-1 (simnet acceptance)")
    log(f"  L1: ok={r_l1.get('ok')} reason={r_l1.get('reason_code')} {r_l1.get('reason','')}")
    log(f"A1 RESULT: {'L1 closed it (expected)' if r_l1.get('ok') is False and r_l1.get('reason_code') == 14 else 'UNEXPECTED'}")

    # A2: honest node_id + attacker signature (hash forced consistent)
    def a2_mutate(recs, nk):
        sk = SigningKey(bytes.fromhex(nk))
        honest_id = (node / "node_pub.hex").read_text().strip()
        out_recs = []
        prev = "0" * 64
        for i, rec in enumerate(recs, start=1):
            rec = {k: v for k, v in rec.items() if k not in ("seq", "prev", "h", "node_sig")}
            rec["seq"] = i; rec["prev"] = prev; rec["node_id"] = honest_id   # honest identity kept
            h = hashlib.sha256((rec["prev"] + tr.jcs(rec)).encode()).hexdigest()
            rec["node_sig"] = sk.sign(h.encode()).signature.hex()           # but the signature is the attacker's
            rec["h"] = h; prev = h
            out_recs.append(rec)
        return out_recs
    forged2 = SB / "a2.tsg"
    forged2.write_bytes(craft_cosigned(base, attacker_nk, a2_mutate))
    r2 = json.loads(sh("import", str(forged2), str(fresh("pkgA2"))))
    log(f"A2 honest-node_id + forged-signature: ok={r2.get('ok')} reason={r2.get('reason_code')} {r2.get('reason','')}")
    log(f"A2 RESULT: {'both layers caught the signature layer (expected)' if r2.get('ok') is False and 'node_sig' in str(r2.get('reason')) else 'UNEXPECTED'}")

    # A3: partial cosign (the last record's node_sig is dropped) → RED under L1
    def a3_mutate(recs, nk):
        recs = json.loads(json.dumps(recs))  # kopya
        for rec in recs:
            rec.pop("node_sig", None)        # the leftover: a chain without node_sig
        return recs
    forged3 = SB / "a3.tsg"
    forged3.write_bytes(craft_cosigned(base, honest_nk, a3_mutate))
    r3 = json.loads(sh("import", str(forged3), str(fresh("pkgA3")),
                       "--cosign-policy", "L1", "--node-trust", str(trust)))
    log(f"A3 partially/fully cosign-dropped chain under L1: ok={r3.get('ok')} reason={r3.get('reason_code')} {r3.get('reason','')}")
    log(f"A3 SONUÇ: {'L1 node_sig_eksik RED (beklendi)' if r3.get('ok') is False and 'node_sig_eksik' in str(r3.get('reason')) else 'BEKLENMEDİK'}")

    shutil.rmtree(SB, ignore_errors=True)
    return 0 if "BEKLENMEDİK" not in "\n".join(OUT) and "İDDİA" not in "\n".join(OUT) else 1


if __name__ == "__main__":
    logf = ROOT / os.environ.get("TAMGA_EVIDENCE_DIR", ".evidence") / "GUVENLIK" / time.strftime("%F") / "audit-8.log"
    logf.parent.mkdir(parents=True, exist_ok=True)
    buf = io.StringIO(); _old = sys.stdout; sys.stdout = buf
    try:
        _rc = main()
    finally:
        sys.stdout = _old
    text = buf.getvalue()
    print(text)
    with open(logf, "a", encoding="utf-8") as f:
        f.write(text)
    sys.exit(_rc or 0)

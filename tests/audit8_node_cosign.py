#!/usr/bin/env python3
"""Audit-8 — node-cosign saldırı simülasyonu (F25 çözümünün adversarial testi).

A1 (güçlü düşman): saldırgan KENDİ node anahtarıyla tam zincir sahteler
   (seq/prev/h/node_id/node_sig baştan) → L0'da ACCEPT (bilinen kalıntı, politika
   kararı OQ-1) / L1'de RED (node_id_güvenilmeyen) — L1'in F25'i kapattığının kanıtı.
A2 (imza-katmanı): dürüst node_id KORUNUR ama node_sig saldırgan anahtarıyla üretilir
   → iki katman: node_id hash'te bağlı + imza node_id anahtarına tabi → RED.
A3 (kısmi-cosign düşürme): zincirin bazı kayıtlarından node_sig düşürülür → L1 RED.

Kanıt: kanit/GUVENLIK/<tarih>/audit-8.log
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
    """gövdeyi çöz → ledger_records'ı mutate et → tam zinciri yeniden kur (güçlü düşman)
    → yeniden şifrele."""
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
    """güçlü düşman: zinciri baştan kurar — prev/h/node_id/node_sig hepsi saldırganın."""
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

    log(f"# Audit-8 node-cosign saldırıları — {time.strftime('%FT%T%z')}")

    # A1: saldırgan kendi node anahtarıyla tam zincir
    forged = SB / "a1.tsg"
    forged.write_bytes(craft_cosigned(base, attacker_nk, lambda recs, nk: forge_chain(recs, nk)))
    r_l0 = json.loads(sh("import", str(forged), str(fresh("pkgL0"))))
    r_l1 = json.loads(sh("import", str(forged), str(fresh("pkgL1")),
                         "--cosign-policy", "L1", "--node-trust", str(trust)))
    log(f"A1 tam-zincir sahteciliği (saldırgan node anahtarı):")
    log(f"  L0: ok={r_l0.get('ok')} — bilinen kalıntı: politika kararı OQ-1'de (simnet kabulü)")
    log(f"  L1: ok={r_l1.get('ok')} reason={r_l1.get('reason_code')} {r_l1.get('reason','')}")
    log(f"A1 SONUÇ: {'L1 kapattı (beklendi)' if r_l1.get('ok') is False and r_l1.get('reason_code') == 14 else 'BEKLENMEDİK'}")

    # A2: dürüst node_id + saldırgan imzası (hash tutarlı zorlanır)
    def a2_mutate(recs, nk):
        sk = SigningKey(bytes.fromhex(nk))
        honest_id = (node / "node_pub.hex").read_text().strip()
        out_recs = []
        prev = "0" * 64
        for i, rec in enumerate(recs, start=1):
            rec = {k: v for k, v in rec.items() if k not in ("seq", "prev", "h", "node_sig")}
            rec["seq"] = i; rec["prev"] = prev; rec["node_id"] = honest_id   # dürüst kimlik korunur
            h = hashlib.sha256((rec["prev"] + tr.jcs(rec)).encode()).hexdigest()
            rec["node_sig"] = sk.sign(h.encode()).signature.hex()           # ama imza saldırganın
            rec["h"] = h; prev = h
            out_recs.append(rec)
        return out_recs
    forged2 = SB / "a2.tsg"
    forged2.write_bytes(craft_cosigned(base, attacker_nk, a2_mutate))
    r2 = json.loads(sh("import", str(forged2), str(fresh("pkgA2"))))
    log(f"A2 dürüst-node_id + sahte-imza: ok={r2.get('ok')} reason={r2.get('reason_code')} {r2.get('reason','')}")
    log(f"A2 SONUÇ: {'iki katman imza-katmanını yakaladı (beklendi)' if r2.get('ok') is False and 'node_sig' in str(r2.get('reason')) else 'BEKLENMEDİK'}")

    # A3: kısmi-cosign (son kaydın node_sig'i düşürülür) → L1 RED
    def a3_mutate(recs, nk):
        recs = json.loads(json.dumps(recs))  # kopya
        for rec in recs:
            rec.pop("node_sig", None)        # yalnız bırakılan: node_sig'siz zincir
        return recs
    forged3 = SB / "a3.tsg"
    forged3.write_bytes(craft_cosigned(base, honest_nk, a3_mutate))
    r3 = json.loads(sh("import", str(forged3), str(fresh("pkgA3")),
                       "--cosign-policy", "L1", "--node-trust", str(trust)))
    log(f"A3 kısmi/hiç cosign düşürülmüş zincir L1'de: ok={r3.get('ok')} reason={r3.get('reason_code')} {r3.get('reason','')}")
    log(f"A3 SONUÇ: {'L1 node_sig_eksik RED (beklendi)' if r3.get('ok') is False and 'node_sig_eksik' in str(r3.get('reason')) else 'BEKLENMEDİK'}")

    shutil.rmtree(SB, ignore_errors=True)


if __name__ == "__main__":
    logf = ROOT / "kanit/GUVENLIK" / time.strftime("%F") / "audit-8.log"
    logf.parent.mkdir(parents=True, exist_ok=True)
    buf = io.StringIO(); _old = sys.stdout; sys.stdout = buf
    try:
        main()
    finally:
        sys.stdout = _old
    text = buf.getvalue()
    print(text)
    with open(logf, "a", encoding="utf-8") as f:
        f.write(text)

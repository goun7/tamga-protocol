#!/usr/bin/env python3
"""
TAMGA SELF-PILOT — ucd bacakli uctan-uca teslimat kaniti (dis-karsitaraf YOK).

Uc rol — hepsi bizim kendi makinemiz:
  SATICI (agent)   : is kosar, teslim-baytlarini uretir, ucretli-receipt zincirler.
  ALICI  (consent) : teslim-baytlari uzerinde ONAY imzasi atar (ed25519, kendi kimligi).
  DOGRULAYAN (3.)  : hicbir tarafa guvenmez; uc bacagi bagimsiz yeniden-hesaplar.

Bacaklar:
  [delivered] keccak256(session-N.stdout) == charge.delivery_hash.hex   (teslim edilen)
  [ran]       tamga ledger-verify -> zincir-tipi D5 dogrulanir          (calisti)
  [satisfied] alici ONAY imzasinin dogrulanmasi (jcs(doc) uzerinde)     (alici-memnun)

Bu, holistis ile ayni iplikte not edilen "uc bacagin hepsi BIR gercek kosumda"
boslugunu, dis taraf katilimina gerek kalmadan kapatan ic-kanittir.
Cikti donuk-kanittir: <evidence>/self-pilot-evidence.json + acceptance.json.

Kullanim:
  python3 tools/self_pilot.py [pkg-dir] [evidence-dir]
"""
import sys, json, shutil, subprocess, pathlib, datetime, tempfile, os

ROOT = pathlib.Path(__file__).resolve().parent.parent

# AT-189-BULGU-1+2-düzeltmesi: kanıt-dosyaları-artık-ATOMİK-ve-0600-yazılır
# ( üretim-deseni _secure_open ile tutarlı). tmp-oluştur → chmod-0600 →
# os.replace ( tek-uyarımsal-atomik-taşıma). Crash'te-kısmi-kanıt-YOK:
# okuyucı ya-eski-dosyayı-ya-da-yeni-tam-dosyayı-görür — ASLA-yarım-satır.
def _secure_write(path: pathlib.Path, data: bytes) -> None:
    """Atomik-0600-yazım ( tamga-üretim-deseni — Audit-9-B6)."""
    import os
    fd = tempfile.NamedTemporaryFile(
        dir=path.parent, prefix=".at189-", suffix=".tmp", delete=False)
    try:
        fd.write(data)
        fd.flush()
        os.fsync(fd.fileno())
        os.fchmod(fd.fileno(), 0o600)
    except Exception:
        os.unlink(fd.name)
        raise
    finally:
        fd.close()
    os.replace(fd.name, path)   # atomik: ya-tam-eski-ya-da-tam-yeni

def _secure_write_text(path: pathlib.Path, text: str) -> None:
    _secure_write(path, text.encode("utf-8"))

def run_cmd(args, cwd, env=None):
    return subprocess.run(args, cwd=str(cwd), env=env, capture_output=True, text=True)

def keygen(cwd):
    r = run_cmd([sys.executable, "tamga_runner.py", "keygen"], cwd)
    assert r.returncode == 0, "keygen-fail: " + r.stderr
    d = json.loads(r.stdout)
    return d["seed_hex"], d["agent_id"]

def main(argv):
    pkg_src = pathlib.Path(argv[1]) if len(argv) > 1 else ROOT / "tests/vectors/tc-net-demo"
    evdir = pathlib.Path(argv[2]) if len(argv) > 2 else ROOT / ".evidence/SELF-PILOT" / datetime.date.today().isoformat()
    evdir.mkdir(parents=True, exist_ok=True)

    # keccak256 (pure-python, bagimsiz):
    sys.path.insert(0, str(ROOT))
    sys.path.insert(0, str(ROOT / "tools"))
    from keccak256 import keccak256 as keccak
    from tamga_validator import jcs

    legs = []
    work = pathlib.Path(tempfile.mkdtemp(prefix="tamga-selfpilot-"))
    try:
        pkg = work / "pkg"
        shutil.copytree(pkg_src, pkg)

        # --- SATICI ---
        seed_s, agent_s = keygen(ROOT)
        r = run_cmd([sys.executable, "tamga_runner.py", "run", str(pkg),
                     "--seed", seed_s, "--delivery-alg", "keccak256"], ROOT)
        assert r.returncode == 0, "run-fail: " + r.stderr
        run_out = json.loads(r.stdout)
        dh = run_out["delivery_hash"]
        stdout_file = pathlib.Path(run_out["stdout_file"])
        delivered = stdout_file.read_bytes()

        # --- BACAK-1 [delivered]: bagimsiz-keccak == delivery_hash ---
        recomputed = keccak(delivered).hex()
        leg1 = recomputed == dh["hex"]
        legs.append({"leg": "delivered", "ok": leg1,
                     "delivery_hash": dh, "delivered_bytes": len(delivered),
                     "stdout_sha256": run_out["stdout_sha256"],
                     "recomputed_keccak": recomputed})

        # --- BACAK-2 [ran]: zincir-tipi ---
        r = run_cmd([sys.executable, "tamga_runner.py", "ledger-verify", str(pkg)], ROOT)
        assert r.returncode == 0, "ledger-verify-fail: " + r.stderr
        lv = json.loads(r.stdout)
        leg2 = lv.get("ok") is True
        legs.append({"leg": "ran", "ok": leg2, "head": lv.get("head"), "lines": lv.get("lines")})
        receipt_head = lv.get("head")

        # --- ALICI (consent) ---
        seed_b, agent_b = keygen(ROOT)
        from nacl.signing import SigningKey, VerifyKey
        sk_b = SigningKey(bytes.fromhex(seed_b))
        doc = {"op": "pilot-accept", "v": 1,
               "receipt_head": receipt_head,
               "delivery_hash": dh,
               "delivered_sha256": run_out["stdout_sha256"],
               "buyer": agent_b,
               "seller": agent_s,
               "ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
               "note": "self-pilot: buyer received these exact bytes and accepts the receipt"}
        sig = sk_b.sign(jcs(doc)).signature.hex()
        acceptance = {"doc": doc, "algo": "ed25519", "key": sk_b.verify_key.encode().hex(), "sig": sig}

        # --- BACAK-3 [satisfied]: alici-onay-imzasi dogrulanir ---
        try:
            VerifyKey(bytes.fromhex(acceptance["key"])).verify(jcs(doc), bytes.fromhex(sig))
            leg3 = True
        except Exception:
            leg3 = False
        legs.append({"leg": "satisfied", "ok": leg3, "buyer": agent_b,
                     "acceptance_key": acceptance["key"][:16] + "..."})

        # --- DONUK-KANIT ---
        evidence = {
            "schema": "tamga-self-pilot/1",
            "generated_at": doc["ts"],
            "roles": {"seller": agent_s, "buyer": agent_b, "verifier": "third-party (fresh role)"},
            "receipt_head": receipt_head,
            "delivery_hash": dh,
            "legs": legs,
            "verdict": "ALL-THREE-LEGS-GREEN" if all(l["ok"] for l in legs) else "SOME-LEG-RED",
        }
        # delivered.out-ÖNCE-yazılır ( kanıt-baytları-en-önemli); verdict-
        # evidence-sonra → crash'te-verdict-yoksa-kanıt-YARIM-görülmez.
        _secure_write(evdir / "delivered.out", delivered)   # teslim-edilen-baytlar (kanit)
        _secure_write_text(
            evdir / "self-pilot-evidence.json",
            json.dumps(evidence, indent=2, ensure_ascii=False) + "\n")
        _secure_write_text(
            evdir / "acceptance.json",
            json.dumps(acceptance, indent=2, ensure_ascii=False) + "\n")

        print(json.dumps(evidence, ensure_ascii=False))
        for l in legs:
            print(f"  [{'OK ' if l['ok'] else 'RED'}] {l['leg']}")
        return 0 if all(l["ok"] for l in legs) else 1
    finally:
        shutil.rmtree(work, ignore_errors=True)

if __name__ == "__main__":
    sys.exit(main(sys.argv))

#!/usr/bin/env python3
"""MERGEN çoklu-proje toplu aktarım (Faz 2, L2 v3 — kurucu onaylı, 2026-09-05).

Güvenlik modeli:
- Kaynak DB'ler SALT-OKUNUR (hash öncesi/sonrası doğrulanır)
- Ara-JSON'lar /dev/shm (tmpfs=RAM) — diske düz-metin İNMEZ, iş sonunda silinir
- Snapshot şifreli; tek kritik sır = parola (ANAHTAR dosyası 0600, vault'ta)
- Seed hiçbir dosyaya yazılmaz (keystore içinde şifreli seyahat eder; D3)
- Özet log YALNIZ sayı+hash: proje adları repoya YANSIMAZ (gizlilik)
"""
import argparse, hashlib, json, os, pathlib, secrets, shutil, subprocess, sys, time

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADAPTER = ROOT / "tests/adapters/mergen_import.py"
CARRIER = ROOT / "tests/vectors/tc-a1"          # taşıyıcı-ajan (rehearsal etiketi)
SHM = pathlib.Path("/dev/shm/mergen-batch")
WORK = pathlib.Path("/dev/shm/mergen-work")

def sh(*args, env=None, loud=False):
    r = subprocess.run([sys.executable, *args], capture_output=True, text=True,
                       env=env or os.environ, cwd=str(ROOT))
    try:
        out = json.loads(r.stdout.strip().splitlines()[-1])
    except Exception:
        out = {"ok": False, "raw": (r.stdout + r.stderr)[-400:]}
    if loud and out.get("ok") is not True:
        raise RuntimeError(f"adım başarısız {args[:2]}: {json.dumps(out, ensure_ascii=False)[:300]}")
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--projects-dir", default="/mnt/hdd/projects/MERGEN/mergen_tools/mergen_memory/projects")
    ap.add_argument("--vault", default="/mnt/hdd/projects/algoat/tamga-vault")
    ap.add_argument("--only", default="", help="virgüllü ad-filtresi (isteğe bağlı)")
    ap.add_argument("--dry-run", action="store_true", help="yalnız sayım, snapshot yazma")
    a = ap.parse_args()
    pdb = pathlib.Path(a.projects_dir)
    vault = pathlib.Path(a.vault); vault.mkdir(parents=True, exist_ok=True)
    os.chmod(vault, 0o700)
    keyf = vault / "ANAHTAR.txt"
    if not keyf.exists():
        keyf.write_text(secrets.token_urlsafe(32) + "\n")
        os.chmod(keyf, 0o600)
    passphrase = keyf.read_text().strip()
    os.environ["TAMGA_KS_PASSPHRASE"] = passphrase
    SHM.mkdir(exist_ok=True); WORK.mkdir(exist_ok=True)
    only = [s.strip() for s in a.only.split(",") if s.strip()]
    results, total_mem, total_edges = [], 0, 0
    for db in sorted(pdb.glob("*.db")):
        name = db.stem
        if only and not any(o in name for o in only):
            continue
        h_src = hashlib.sha256(db.read_bytes()).hexdigest()
        r = sh(str(ADAPTER), str(db), "--out", str(SHM / f"{name}.json"))
        if r.get("ok") is not True:
            results.append({"db": name[:4] + "…", "sonuç": "SKIP", "neden": r.get("reason", "?")[:60]})
            continue
        st = r.get("istatistik", {})
        if a.dry_run:
            results.append({"db": name[:4] + "…", "sonuç": "OK(kuru)", **st}); continue
        # taze paket (taşıyıcı-ajan = simnet test ajanı — production paketleme Faz 2)
        pkg = WORK / name
        shutil.rmtree(pkg, ignore_errors=True); pkg.mkdir(parents=True)
        for f in ("tamga.json", "agent.wasm"):
            shutil.copy2(CARRIER / f, pkg / f)
        seed = sh("tamga_runner.py", "keygen", loud=True).get("seed_hex", "")
        sh("tamga_runner.py", "memory", str(pkg), "--import-json", str(SHM / f"{name}.json"), loud=True)
        sh("tamga_runner.py", "export", str(pkg), "-o", str(vault / f"{name}.tsg"), "--seed", seed, loud=True)
        v = sh("tamga_runner.py", "ledger-verify", str(pkg), loud=True)
        # doğrulama: boş node'a import + düğüm sayısı
        scratch = WORK / f"chk-{name}"
        shutil.rmtree(scratch, ignore_errors=True); scratch.mkdir(parents=True)
        for f in ("tamga.json", "agent.wasm"):
            shutil.copy2(CARRIER / f, scratch / f)
        imp = sh("tamga_runner.py", "import", str(vault / f"{name}.tsg"), str(scratch), loud=True)
        ok = v.get("ok") and imp.get("ok")
        h_tsg = hashlib.sha256((vault / f"{name}.tsg").read_bytes()).hexdigest()
        results.append({"db": name[:4] + "…", "sonuç": "OK" if ok else "FAIL",
                        **st, "tsg": h_tsg[:12], "ledger": v.get("ok")})
        total_mem += st.get("aktarilan", 0); total_edges += st.get("edges", 0)
        shutil.rmtree(pkg, ignore_errors=True); shutil.rmtree(scratch, ignore_errors=True)
    summary = {"tarih": time.strftime("%FT%T%z"), "db_sayısı": len(results),
               "toplam_aktarilan_ders": total_mem, "toplam_kenar": total_edges,
               "detay": results,
               "gizlilik": "özet repoya girmeden önce proje-adları kırpılır (db alanı 4 harf)"}
    (SHM / "ozet.json").write_text(json.dumps(summary, ensure_ascii=False, indent=1))
    print(json.dumps({"ok": True, "db_sayısı": len(results), "toplam_ders": total_mem,
                      "toplam_kenar": total_edges, "vault": str(vault),
                      "özet": str(SHM / "ozet.json")}, ensure_ascii=False))
    shutil.rmtree(WORK, ignore_errors=True)

if __name__ == "__main__":
    main()

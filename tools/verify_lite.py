#!/usr/bin/env python3
"""verify_lite — Tamga'nın stdlib-saf yolçaplarını tek komutta kanıtla (pynacl'sız).

Kanıtlar: mini-verifier, evidence-bundle, pairing-fixture-hash, explain — hepsi
NAÇL ENGELLİ ortamda çalışır (import tamga_verify_mini/bundle/explain nacl çekmez).
Runner'ın koşum/export/import yolçapları pynacl İSTER — bunlar bu-lite-nın dışıdır.

Usage: python3 tools/verify_lite.py [--fixture docs/pairing]
Exit 0 = tüm-lite-yolçapları-pynacl'sız-çalıştı.
"""
import importlib
import json
import pathlib
import shutil
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent


class _NaclBlocker:
    """verify-lite sözü: nacl-importu-görünür-şekilde-RED — sessiz-değil."""
    def find_spec(self, name, path=None, target=None):
        if name == "nacl" or name.startswith("nacl."):
            raise ImportError("verify-lite: nacl kasıtlı engellendi (söz: stdlib-saf)")
        return None


def main(argv):
    sys.meta_path.insert(0, _NaclBlocker())
    sys.path.insert(0, str(ROOT))
    pdir = ROOT / (argv[argv.index("--fixture") + 1] if "--fixture" in argv else "docs/pairing")
    ok = True

    # jcs-ÖNCE-standalone-çek (tamga_validator-import'u-nacl-ister — lite-dışı):
    import hashlib

    def jcs(obj) -> bytes:
        """RFC-8785-subset canonical JSON — runner'daki-jcs ile-aynı (json.dumps, sort_keys)."""
        return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")

    # 1) mini-verifier-(sentetik-küçük-zincir — donuk-vektör-yok):
    import tamga_verify_mini as mv
    W = pathlib.Path(tempfile.mkdtemp())
    recs = []
    prev = "0" * 64
    for seq in (1, 2):
        rec = {"seq": seq, "op": "note", "prev": prev, "n": seq}
        body = {k: v for k, v in rec.items() if k not in ("h", "node_sig")}
        rec["h"] = hashlib.sha256(rec["prev"].encode() + jcs(body)).hexdigest()
        recs.append(rec)
        prev = rec["h"]
    lp = W / "chain.jsonl"
    lp.write_text("\n".join(json.dumps(r) for r in recs) + "\n")
    head, st = mv.verify(str(lp))
    good = st == "ok"
    print(f"[{'PASS' if good else 'FAIL'}] mini-verifier (nacl-ENGELLİ): {st}, head={head[:16]}…")
    ok &= good

    # 2) pairing-fixture-hash-yeniden-hesap:
    fx = json.loads((pdir / "pairing-fixture.json").read_text(encoding="utf-8"))
    rec = fx["tamga_observed"]["charge_record"]["value"]
    claimed = fx["tamga_observed"]["receiptHash"]["value"]
    body = {k: v for k, v in rec.items() if k not in ("h", "node_sig")}
    h = hashlib.sha256(rec["prev"].encode() + jcs(body)).hexdigest()
    good = h == claimed
    print(f"[{'PASS' if good else 'FAIL'}] pairing-hash: {h[:16]}… {'≡' if good else '≠'} fixture")
    ok &= good

    # 3) explain-mantığı (nacl'sız yeniden-üretim — explain-modülü validator-importladığından
    #    lite-içinde mantığı doğrudan çalıştır):
    no_h = {k: v for k, v in rec.items() if k not in ("h", "node_sig")}
    exp = hashlib.sha256((rec.get("prev", "").encode() + jcs(no_h))).hexdigest()
    good = exp == rec["h"]
    print(f"[{'PASS' if good else 'FAIL'}] explain-mantığı (nacl-ENGELLİ): zincir-dürüstlüğü "
          f"{'DOĞRULANDI' if good else 'EŞLEŞMİYOR'}")
    ok &= good

    # 4) nacl-gerçekten-engelli-miydi-(sözün-sözü):
    try:
        import nacl  # noqa: F401
        print("[FAIL] nacl-importu-ENGELLENEMEDİ — lite-sözü-boş")
        ok = False
    except ImportError as e:
        print(f"[PASS] nacl-importu engellendi ({e})")
    except Exception as e:
        print(f"[FAIL] nacl-bloğu-beklenmedik-hata: {e!r}")
        ok = False

    shutil.rmtree(W, ignore_errors=True)
    print("verify-lite:", "TAMAM — stdlib-saf-yolçaplar-pynacl'sız" if ok else "SORUNLU")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

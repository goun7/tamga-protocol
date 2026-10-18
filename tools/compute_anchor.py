#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Compute-anchor — RFC-011 DRAFT: the mesh's compute-work proof receipt.

KÖK'ün Seçenek-C evrimi (2026-10-18, `kok/docs/KOK_EVOLUSYON_ARASTIRMA_2026-10-18.md`):
kok bir L1 olmaktan çıkar ve bir compute-provider'ın **gerçekten hangi MatMul
işini yaptığını** kanıtlayan bağımsız-doğrulanabilir bir makbuza dönüşür. Bu
dosya, o makbuzun tamga ledger'ına bağlandığı yerdir.

Ne yapar
--------
`compute-anchor` op'u ledger'a bir kayıt yazar. Kayıt şunları taşır:

  - `receipt_hash`   kok kanıtının kendi hash-zinciri değeri (kok'un
                     pipe-delimited envelope digest'i — tamga'nın değil)
  - `miner_did`      işi yapanın did:key (kok'un kendi imzasının altında)
  - `task_program`   iddia edilen program (commitment'a bağlı)
  - `verified`       bizim doğrulayıcımız (kok/receipt/kok_receipt_verify_en.py)
                     bu makbuzu gerçekten ACCEPT mu etti — RED ise ekleme yok
  - `tool`           hangi araç doğruladı

Tek-kaynak ilkesi (RFC-009 R9 deseni): cmd_compute_anchor yazma-yolunda
doğrular, `ledger-verify` okuma-yolunda aynı fonksiyonu paylaşır. Yazmadan
önce makbuz bağımsız doğrulayıcıda ACCEPT olmak ZORUNDA — RED bir kanıtı
bağlamak "yeşil giydirme" olur (AT-050 üçlü-kapsam dersi).

Ne YAPMAZ (dürüst sınır)
------------------------
- **Ödemenin yapıldığını kanıtlamaz.** x402'nin #3379 tartışmasındaki üç
  eksen: durable-evidence (ne) + proof-of-done (iş) + capacity-attest (alıcı).
  Bu op sadece **proof-of-done** eksenidir.
- **İşin satın alındığını kanıtlamaz.** E-gap (TV-72/TV-77) dersi: hangi-iş
  bağlanabilir, bir-alıcının-istediği-iş bağlanamaz.
- Kok'un kanıtını **kok'un kodunu çağırarak** doğrulamaz. Doğrulayıcı
  tamga'ya kopyalanmış bağımsız bir koddur (kok_receipt_verify_en.py),
  çünkü prov'un kodunu import eden doğrulayıcı bağımsız değildir. Bu, tek
  yönlü bir bağlantıdır: kok değişirse bu dosyanın kopyası eskir —
  `receipt_version` alanı bu yüzden vardır.

Run:  python3 tools/compute_anchor.py <pkg> --receipt <kanit.json>
      python3 tools/compute_anchor.py verify <pkg> [--strict]
"""

import json
import os
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent                       # tamga repo kökü
sys.path.insert(0, str(ROOT))

# kok ledger'ına bağımlılık YOK: kok_receipt_verify_en.py'nin bir kopyası
# tools/ altında durur (tek-yön). Kok güncellenince kopya yenilenir ve
# receipt_version bump'lanır.
KOK_VERIFY_DIR = HERE / "kok_receipt"
KOK_VERIFY = KOK_VERIFY_DIR / "kok_receipt_verify_en.py"

COMPUTE_ANCHOR_VERSION = "TAMGA_COMPUTE_ANCHOR_V1"
COMPUTE_ANCHOR_OP = "compute-anchor"
RECEIPT_VERSION = 1                      # kok MiningProof proof_version ile aynı


def _err(msg, **kw):
    print(json.dumps({"ok": False, "reason": msg, **kw}, ensure_ascii=False))
    return 1


def _ok(**kw):
    print(json.dumps({"ok": True, **kw}, ensure_ascii=False))
    return 0


# ---------------------------------------------------------------------------
# Kopyalanmış bağımsız doğrulayıcı. kok/receipt/kok_receipt_verify_en.py'nin
# birebir kopyasıdır; bağımsız tutulur (kok repo'su silinse bile tamga bir
# makbuzu doğrulayabilmelidir).
# ---------------------------------------------------------------------------

def _load_kok_verifier():
    """Import the copied verifier module (not kok's, not tamga's)."""
    if not KOK_VERIFY.is_file():
        return None
    import importlib.util
    spec = importlib.util.spec_from_file_location("kok_receipt_verify_copy",
                                                 KOK_VERIFY)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def verify_kok_receipt_path(path) -> dict:
    """Bağımsız doğrulayıcıyı çağır; RED olursa (kind, detail) ile dön."""
    mod = _load_kok_verifier()
    if mod is None:
        return {"ok": False, "kind": "verifier_eksik",
                "detail": "%s bulunamadi — bagimsiz-dogrulayici-kopyasi gerek" % KOK_VERIFY}
    try:
        p = json.loads(open(path, encoding="utf-8").read())
    except Exception as e:
        return {"ok": False, "kind": "okunamadi", "detail": "%s" % e}
    v = mod.verdict(p)
    if v.get("verdict") != "ACCEPT":
        return {"ok": False, "kind": v.get("kind", "?"),
                "detail": v.get("detail", "?")}
    return {"ok": True, "verdict": v}


# ---------------------------------------------------------------------------
# Kayıt shape-contract — yazma ve okuma aynı fonksiyonu paylaşır (AT-062).
# ---------------------------------------------------------------------------

def _compute_anchor_violation(rec) -> tuple | None:
    """Ledger'a-yazılmasından-önce-ve-sonra-geçerli olması-gereken-shape.

    Returns (key, message) veya None."""
    if rec.get("anchor_version") != COMPUTE_ANCHOR_VERSION:
        return ("anchor_version",
                "anchor_version %r must be %r" % (rec.get("anchor_version"),
                                                  COMPUTE_ANCHOR_VERSION))
    if not isinstance(rec.get("receipt_version"), int) or \
       rec["receipt_version"] != RECEIPT_VERSION:
        return ("receipt_version",
                "receipt_version %r must be %d — bagimsiz-dogrulayici-kopru "
                "bu surumu okur" % (rec.get("receipt_version"), RECEIPT_VERSION))
    # receipt_hash: kok'un pipe-delimited envelope digest'ı — 64 lowercase hex.
    # (0x ön eki YOK: bu tamga'nın 0x+64 kuralının dışında, kok'un own digest
    # alanıdır — RFC-009 R9-3'ün kanonik-hex disiplini aynı, ön ek farklı.)
    rh = rec.get("receipt_hash")
    if not isinstance(rh, str) or len(rh) != 64 or \
       any(c not in "0123456789abcdef" for c in rh):
        return ("receipt_hash",
                "receipt_hash 64 lowercase-hex olmali (kok'un kendi envelope "
                "digest'i, 0x-on-ekisiz)")
    did = rec.get("miner_did")
    if not isinstance(did, str) or not did.startswith("did:key:z"):
        return ("miner_did", "miner_did bir did:key:z... olmali")
    prog = rec.get("task_program")
    if not isinstance(prog, str) or not prog:
        return ("task_program", "task_program boş-olmayan string olmali")
    if not isinstance(rec.get("presentation_only"), bool) or \
       not rec["presentation_only"]:
        return ("presentation_only",
                "presentation_only True olmali — bu kayit is-yapildigini "
                "sunar, odeme-yapildigini DEGIL")
    verified = rec.get("verified")
    if not isinstance(verified, bool) or not verified:
        return ("verified",
                "verified True olmali — RED bir makbuzu baglamak "
                "yesil-giydirme")
    return None


# ---------------------------------------------------------------------------


def cmd_compute_anchor(a) -> int:
    """Ledger'a bir compute-anchor kaydı yaz (önce bağımsız doğrula)."""
    usage = ("usage: compute-anchor <pkg> --receipt <kanit.json> "
             "[--tool <string>]")
    if not a or len(a) < 3:
        return _err(usage, op="compute-anchor")
    pkg = pathlib.Path(a[0])
    if not pkg.is_dir():
        return _err("package not found: %s" % pkg, op="compute-anchor")
    kv = {}
    for i in range(1, len(a) - 1, 2):
        kv[a[i]] = a[i + 1]
    if "--receipt" not in kv or not kv["--receipt"]:
        return _err(usage, op="compute-anchor")
    receipt_path = pathlib.Path(kv["--receipt"])
    if not receipt_path.is_file():
        return _err("receipt not found: %s" % receipt_path, op="compute-anchor")

    # Doğrulama-önce: RED kanıt ledger'a giremez.
    v = verify_kok_receipt_path(receipt_path)
    if not v.get("ok"):
        return _err("receipt RED: %s/%s — ledger'a-baglanamaz" %
                    (v.get("kind"), v.get("detail")),
                    op="compute-anchor")
    p = json.loads(receipt_path.read_text(encoding="utf-8"))
    rec = {"op": COMPUTE_ANCHOR_OP,
           "anchor_version": COMPUTE_ANCHOR_VERSION,
           "receipt_version": p.get("proof_version", RECEIPT_VERSION),
           "receipt_hash": p.get("receipt_hash", ""),
           "miner_did": p.get("miner_did", ""),
           "task_program": p.get("task_program", ""),
           "ctx": p.get("ctx"),
           "nonce": p.get("nonce"),
           "tile": [p.get("cert_i"), p.get("cert_j"), p.get("cert_value")],
           "verified": True,
           "tool": kv.get("--tool", "kok_receipt_verify_en.py (independent copy)"),
           "presentation_only": True}
    viol = _compute_anchor_violation(rec)
    if viol:
        return _err("anchor_invalid: %s" % viol[1], op="compute-anchor")

    # E1-opsyonu: tamga_runner'ın-compile etmek istemediği ortamlar için
    # kaydı sadece JSON olarak döndür (testlerin kullandığı path).
    if os.environ.get("COMPUTE_ANCHOR_DRY"):
        print(json.dumps({"ok": True, "record": rec}, ensure_ascii=False))
        return 0

    # Ledger'a yaz — tamga_runner'ın kendi _ledger_append'ini çağır.
    # NOT (emitter-registry): çağrı-aralığında {"op": ...} değişmezi-olmadan
    # statik-tarayıcı bu emitter'ı-göremez — bu-yüzden çağrı-aralığında
    # op-literal'i-yazılır ve _compute_anchor_violation ile-aynı-shape
    # denetlenir.
    import tamga_runner as tr
    from emitter_registry import register_emitter
    register_emitter(COMPUTE_ANCHOR_OP, "tools/compute_anchor.py")
    lp = pkg / "ledger.jsonl"
    r = tr._ledger_append(lp, {"op": "compute-anchor",
                               "anchor_version": COMPUTE_ANCHOR_VERSION,
                               "receipt_version": rec["receipt_version"],
                               "receipt_hash": rec["receipt_hash"],
                               "miner_did": rec["miner_did"],
                               "task_program": rec["task_program"],
                               "ctx": rec["ctx"],
                               "nonce": rec["nonce"],
                               "tile": rec["tile"],
                               "verified": True,
                               "tool": rec["tool"],
                               "presentation_only": True})
    if isinstance(r, int):
        return _err("ledger-write failed (rc=%s)" % r, op="compute-anchor")
    return _ok(op="compute-anchor", ledger=str(lp), seq=r.get("seq"),
               anchor_id=r.get("h"), receipt_hash=rec["receipt_hash"][:16])


def main():
    a = sys.argv[1:]
    if a and a[0] == "verify":
        # okuma-yolu: bir pkg'deki compute-anchor kayıtlarının-shape'ini denetle
        pkg = pathlib.Path(a[1]) if len(a) > 1 else pathlib.Path(".")
        lp = pkg / "ledger.jsonl"
        if not lp.is_file():
            return _err("ledger not found: %s" % lp, op="compute-anchor-verify")
        n = 0
        for ln, line in enumerate(open(lp, encoding="utf-8"), 1):
            if not line.strip():
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            if rec.get("op") != COMPUTE_ANCHOR_OP:
                continue
            n += 1
            viol = _compute_anchor_violation(rec)
            if viol:
                return _err("anchor_invalid @%d: %s" % (ln, viol[1]),
                            op="compute-anchor-verify")
        return _ok(op="compute-anchor-verify", anchors=n)
    rc = cmd_compute_anchor(a)
    return rc


if __name__ == "__main__":
    sys.exit(main())

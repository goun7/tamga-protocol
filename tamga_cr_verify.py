import argparse
#!/usr/bin/env python3
"""tamga_cr_verify — Computation-Receipts v0.1 kanoniklik-doğrulayıcısı (stdlib-only).

İki-kip:
  --candidates   : AT-029 aday-üreticisi (vendored CR-v0.1 vektörlerini TAMGA'NIN kendi
                   kanonik yolundan — tamga_verify_mini.jcs — geçirir; notlama upstream'in
                   TARAFSIZ runner'ının işi: tests/vendor-cr). Eski tools/cr_crossproof.py'nin
                   tek-sahip-varisi (0.2.9+ taşıma; shim yok).
  <receipt.json> : tek-belge doğrulaması: CR §2 kural-6 kanonik-baytları + sha256-digest
                   yeniden-üretir; --expect verilirse üç-sonuç: GREEN eşleşme / RED fark /
                   bozuk-JSON mesajlı-RED. --expect yoksa ÖLÇÜM (digest basar, rc0) —
                   hüküm-satma-kip; iddia-değil.

Kapsam-dürüstlüğü (AT-029 ile-birebir): canonicalisation-katmanı; receipt/chain/refuse
aritmetiği TAMGA-idiası-değildir — CR-certifier değiliz, sertifikasyon-iddiası-yok.
"""
import hashlib
import json
import pathlib
import struct
import sys

from tamga_verify_mini import jcs

ROOT = pathlib.Path(__file__).resolve().parent
REF = ROOT / "tests" / "vendor-cr" / "spec" / "CR-v0.1-conformance-vectors.json"

def digest_bytes(b: bytes) -> str:
    return "sha256:" + hashlib.sha256(b).hexdigest()


def tensor_digest(dtype: str, shape: list, pack_fmt: str, vals: list) -> str:
    h = hashlib.sha256()
    h.update(jcs({"dtype": dtype, "shape": shape}))
    h.update(struct.pack(pack_fmt, *vals))
    return "sha256:" + h.hexdigest()


def named_digest(entries: dict) -> str:
    """§3.2: sorted-by-codepoint names, her-eleman canonical({"name","digest"})."""
    h = hashlib.sha256()
    for name in sorted(entries):
        h.update(jcs({"name": name, "digest": entries[name]}))
    return "sha256:" + h.hexdigest()



def _candidates() -> int:
    reference = json.loads(REF.read_text(encoding="utf-8"))
    f64 = tensor_digest("f8", [2, 3], "<6d", [0.0, 1.0, 2.0, 3.0, 4.0, 5.0])
    i32 = tensor_digest("i4", [4], "<4i", [0, 1, 2, 3])
    i8 = tensor_digest("i1", [6], "<6b", [-3, -2, -1, 0, 1, 2])
    ours = {}
    for vec in reference:
        name = vec["name"]
        if name.startswith("canonical/"):
            c = jcs(vec["input"])
            ours[name] = {"name": name, "canonical": c.decode("utf-8"),
                          "digest": digest_bytes(c)}
        elif name == "tensor/float64-2x3":
            ours[name] = {"name": name, "digest": f64}
        elif name == "tensor/int32-4":
            ours[name] = {"name": name, "digest": i32}
        elif name == "tensor/int8-6":
            ours[name] = {"name": name, "digest": i8}
        elif name == "tensors/named-order-independent":
            ours[name] = {"name": name, "digest": named_digest({"w2": i32, "w1": f64})}
    for name in ours:
        assert name.startswith(("canonical/", "tensor/", "tensors/")), name
    print(json.dumps(list(ours.values()), ensure_ascii=False, indent=1))
    return 0


def verify_single(path: str, expect: str | None) -> int:
    try:
        doc = json.load(open(path, encoding="utf-8"))
    except json.JSONDecodeError as e:
        print(f"[RED] bozuk-JSON-girdi: {e}", file=sys.stderr)
        return 1
    c = jcs(doc)
    digest = digest_bytes(c)
    if expect is None:
        print(json.dumps({"digest": digest, "canonical_bayt": len(c),
                          "kip": "ölçüm (hüküm-için --expect ver)"}, ensure_ascii=False))
        return 0
    ok = digest.lower() == expect.lower() or digest.split(":", 1)[1].lower() == expect.lower().removeprefix("0x")
    verdict = "GREEN" if ok else "RED"
    print(json.dumps({"verdict": verdict, "digest": digest, "expect": expect}, ensure_ascii=False))
    print("[" + verdict + "] " + digest + " vs " + expect, file=sys.stderr)
    return 0 if ok else 1


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if "--candidates" in argv:
        return _candidates()
    if not argv:  # E-14 ailesi: sıfır-arg = mesajlı-RED (argparse'ın rc2'si İNDETERMİNE-kodudur — karışmaz)
        print("kullanim: tamga verify-cr <doc.json> [--expect sha256:...]  |  --candidates")
        return 1
    ap = argparse.ArgumentParser(prog="tamga verify-cr", description="CR v0.1 canonical digest doğrulaması")
    ap.add_argument("receipt", help="doğrulanacak JSON belgesi")
    ap.add_argument("--expect", help="beklenen-digest ('sha256:...' veya ham-hex)")
    a = ap.parse_args(argv)
    return verify_single(a.receipt, a.expect)


if __name__ == "__main__":
    sys.exit(main())

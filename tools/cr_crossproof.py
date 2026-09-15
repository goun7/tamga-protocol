#!/usr/bin/env python3
"""cr_crossproof.py — Tamga-aday-çıktısı için CR-v0.1 canonicalisation-vektörleri.

Amaç (AT-029, PR-592 cross-proof sözü): Anomly'nin yayınladığı vektörleri TAMGA'NIN
KENDİ kanonik-yolundan geçirmek — epoch-anchor digest'lerinin koştuğu AYNI fonksiyon
(tamga_verify_mini.jcs) + hashlib + struct. Başarı-ölçüsü upstream'in TARAFSIZ runner'ı
(tests/vendor-cr/python/conformance_runner.py, byte-identical vendored) tarafından
notlanır; bu dosya yalnız aday-üretir.

Kapsam: canonical/* (4) + tensor/* (3) + tensors/* (1) = canonicalisation-katmanı 8.
receipt/chain/refuse katmanları CR-aritmetik-semantiği gerektirir — Tamga CR-certifier
değildir; bu-iddia-edilmez (runner'a --require canonicalisation verilir).

Spec-girdisi: CR-v0.1 §2 (kanoniklik), §3 (digest biçimi), §3.1 (tensor:
H(canonical({"dtype":d,"shape":s}) || LE-C-rawbytes); dtype-string numpy-kodundan
baş-iki-bayrak-karakteri (| < > =) SOYULUR: |i1→i1), §3.2 (named-koleksiyon: ada-göre
codepoint-sıralı canonical({"name","digest"}) parçalarının zincir-akışı; boş-koleksiyon
= sha256(boş-bayt)). Tensör-VERİLERİ vektör-adlarında-sabitlenmiştir (arange-anlaşması,
upstream JS-örneğiyle-çapraz-teyitli): f8 2x3=[0..5], i4=[0..3], i1=[-3..2].

Kullanım: python3 tools/cr_crossproof.py > candidate.json
"""
import hashlib
import json
import pathlib
import struct
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from tamga_verify_mini import jcs  # epoch-anchor yoluyla AYNI kanonik-muskül

ROOT = pathlib.Path(__file__).resolve().parent.parent
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


def main() -> int:
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
            # upstream-vektör: {"w2": int32-dizisi, "w1": float64-matrisi}
            ours[name] = {"name": name, "digest": named_digest({"w2": i32, "w1": f64})}
    # Kapsam-dürüstlüğü: yalnız-canonicalisation-adi-üretildi (refuse/receipt sızarsa patla)
    for name in ours:
        assert name.startswith(("canonical/", "tensor/", "tensors/")), name
    print(json.dumps(list(ours.values()), ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())

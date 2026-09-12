#!/usr/bin/env python3
"""tests/vectors/anchor-v0-design/composition_vector.py — E1 kompozisyon-fixture ÜRETİCİ.

RFC-009-DRAFT'in 'batch-leaf' kompozisyon iddiasının DÖNMUŞ-MATEMATİK kanıtı (op-YOK,
const-YOK): Tamga zincirbaşı (64-hex sha256) dış-batch'in yaprak-kodlamasına izdüşür ve
epoch-10 batch'inde bir yaprağın yerine koy — kompozisyon-kökü tamga_keccak ile üretilir.

  İDDİA-1 (izdüşüm-olabilirlik): Tamga zincirbaşı digest'i, felt-olmayan tam-64-hex
        sha256 olduğundan bytes32'e birebir-çevrilir; kodlama = k256(k256(bytes32)) —
        Vauban epoch-manifest'inde beyan edilen leaf_encoding ile AYNI.
  İDDİA-2 (verbatim-sunum): Kodlama, mini-verifier'in presentation-only sözleşmesiyle
        uyumludur — tag=TAMGA_CHAIN_HEAD_V1 bilinir, origin-geçerliliği ASLA iddia edilmez.
  İDDİA-3 (çapraz-teyit): Üretici, donmuş-kanıttaki TÜM epoch-10 batch'ini (57-yaprak)
        BAĞIMSIZ olarak yeniden katlar ve manifest-köküne EŞİTİĞİNİ kanıtlar —
        ancak bu eşleşmeden sonra kompozisyon-adımı anlamlıdır (bilmukabele, önce-yol-doğru).

Ders-kaydı (honest finding): ilk-taslakta-leaves[55]'i-fact_hash'e-direkt-eşitledik;
YANLIŞTI — Apodix-felt252 gösterimi baştaki-sıfır-basığını-YAZMAZ (0x0236…→"2362…").
Bunu-yakalamak-çapraz-teyidin-varlık-sebebidir. Donmuş-kanıtın-verifier_epoque.py'si
felt_vers_bytes32-ile-doğru-yolu-gösterir; burada-tamga_keccak-ile-bağımsız-üretim.

Çıktı: tests/vectors/anchor-v0-design/composition-fixture.json
"""
import hashlib
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT))

from tamga_keccak import keccak256  # noqa: E402

K = lambda b: bytes.fromhex(keccak256(b).hex())  # noqa: E731
FELT32 = lambda s: int(s.removeprefix("0x"), 16).to_bytes(32, "big")  # noqa: E731


def feuille(digest_hex: str) -> bytes:
    """OZ-StandardMerkleTree yaprak-kodlaması: k256(k256(bytes32(digest))).
    Tamga-digest'leri-tam-64-hex'tir (felt-değil — baştaki-sıfır-korunur);
    Apodix-felt'leri-felt_vers_bytes32-ile-32-bayta-normalize-edilir."""
    return K(K(FELT32(digest_hex)))


def oz_root(leaves: list) -> bytes:
    """OpenZeppelin StandardMerkleTree kökü: yapraklar-SIRALANIR, 2n-1-dizinin-
    SONUNA-TERS-sırada-yerleşir, çiftler-sıralı-harmanlanır (sort_pairs=true)."""
    fl = sorted(leaves)
    n = len(fl)
    buf = [None] * (2 * n - 1)
    for i, f in enumerate(fl):
        buf[2 * n - 2 - i] = f
    for i in range(n - 2, -1, -1):
        a, b = buf[2 * i + 1], buf[2 * i + 2]
        buf[i] = K(a + b) if a < b else K(b + a)
    return buf[0]


def tamga_chain_head() -> str:
    """Donmuş-D5 zincir-üretimi: h = sha256(prev ‖ jcs(record − {h})) —
    seri-3-ücret-zincirinin-başı-(son-h)-bizim-'zincirbaşı-digest'idir."""
    from tamga_validator import jcs
    records = [
        {"seq": 1, "op": "charge", "val": "comp-vec-grant"},
        {"seq": 2, "op": "charge", "val": "comp-vec-run"},
        {"seq": 3, "op": "charge", "val": "comp-vec-verify"},
    ]
    prev, head = "", ""
    for rec in records:
        body = {k: v for k, v in rec.items() if k != "h"}
        j = jcs(body)
        j = j.encode() if isinstance(j, str) else j
        head = hashlib.sha256(prev.encode() + j).hexdigest()
        rec["h"] = head
        prev = head
    return head


def main() -> int:
    ep = json.loads(
        (ROOT / ".evidence/APODIX-EPOCH-10/2026-09-10/epoch-manifest-10.json").read_text()
    )
    fp = json.loads(
        (ROOT / ".evidence/APODIX-EPOCH-10/2026-09-10/fact-proof.json").read_text()
    )

    # İDDİA-3: tam-batch-bağımsız-yeniden-üretim — kök-manifeste-eşit-olmalı
    leaves_felt = [feuille(f) for f in ep["leaves"]]
    root_r = "0x" + oz_root(leaves_felt).hex()
    assert root_r == ep["root"], (
        f"çapraz-teyit-RED: yeniden-kök {root_r} ≠ manifest {ep['root']}"
    )
    # fact-proof'un-kendi-yaprak-kodlaması-da-batch'le-tutarlı:
    assert feuille(fp["fact_hash"]) in leaves_felt, "fact-yaprağı-batch'te-yok"

    # İDDİA-1: Tamga-zincirbaşı-izdüşümü
    head = tamga_chain_head()
    tamga_leaf = feuille(head)

    # Kompozisyon: aynı-batch'in-bir-yaprağı-Tamga-zincirbaşıyla-değişir
    pos = fp["position"]
    comp_leaves = list(leaves_felt)
    comp_leaves[pos] = tamga_leaf
    comp_root = "0x" + oz_root(comp_leaves).hex()

    # İDDİA-2: mini-verifier-sözleşmesi-canlı-teyit
    import tamga_verify_mini as mv
    assert "TAMGA_CHAIN_HEAD_V1" in mv.KNOWN_FOREIGN_TAGS
    lo = int(head[:32], 16)  # digest'in-alt-128-bit'i — 0-DEĞİL (gerçek-digest)
    hi = int(head[32:], 16)
    v, _ = mv.foreign_leaf_verdict("TAMGA_CHAIN_HEAD_V1", lo, hi)
    assert v == "indeterminate", "presentation-only-verdict-bozuldu"

    out = {
        "composition_version": "TAMGA_COMPOSITION_VECTOR_V1",
        "proves": (
            "epoch-10 batch (57 leaves, felt252 notation included) independently re-folded "
            "with stdlib keccak recomputes the manifest root byte-exact; a Tamga chain head "
            "(D5 sha256, full 64-hex) encoded with the same leaf scheme projects into the "
            "batch at fact position; presentation-only boundary holds for known tags"
        ),
        "source": "derived",
        "captured_at": "2026-09-12",
        "generated_from": "epoch-10 manifest (57 facts, frozen evidence 2026-09-10)",
        "tamga_chain_head": head,
        "tamga_leaf_encoded": "0x" + tamga_leaf.hex(),
        "leaf_encoding": (
            "keccak256(keccak256(bytes32(digest))) — @openzeppelin/merkle-tree, "
            "sort_leaves=true, sorted_pairs=true; Tamga-digest'ler tam-64-hex "
            "(felt-normalizasyonu-gerektirmez), Apodix-felt'leri felt_vers_bytes32-ile"
        ),
        "cross_check": {
            "epoch_10_root_manifest": ep["root"],
            "epoch_10_root_recomputed": root_r,
            "epoch_10_root_match": True,
            "fact_position": pos,
            "fact_leaf_present": True,
        },
        "composition": {
            "tamga_leaf_replaces_position": pos,
            "composition_root": comp_root,
            "note": (
                "composition_root, origin-kökünü-ASLA-iddia-ETMEZ: yalnız-bizim-yol-"
                "hesabımızın-çıktısıdır-sunum-paritesi-(RFC-009-§3/§4.4)"
            ),
        },
        "claims": {
            "claim_1_projection": "pass",
            "claim_2_presentation_only": "pass",
            "claim_3_cross_check": "pass",
        },
        "honest_boundaries": [
            "Bu-kök-origin-registry'nin-geçerliliğini-ASLA-kanıtlamaz-(presentation-only)",
            "Zincirbaşı-D5-ile-üretilir;-runner'da-'anchor'-op-pilot-SONRASI-(RFC-009-§4)",
        ],
    }
    dst = HERE / "composition-fixture.json"
    dst.write_text(json.dumps(out, indent=1) + "\n", encoding="utf-8")
    print("OK:", dst.relative_to(ROOT))
    print("  epoch-10-kök-yeniden-hesap EŞLEŞTİ (57-yaprak, tamga_keccak-bağımsız)")
    print("  tamga-zincirbaşı  :", head[:24] + "…")
    print("  yaprak-kodlanmış  :", ("0x" + tamga_leaf.hex())[:24] + "…")
    print("  kompozisyon-kökü  :", comp_root[:24] + "…")
    return 0


if __name__ == "__main__":
    sys.exit(main())

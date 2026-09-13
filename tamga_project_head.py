#!/usr/bin/env python3
"""tamga_project_head.py — chain-head → batch-leaf projection (engine-free, stdlib-only).

RFC-009-DRAFT §5 / AT-022'in kullanıcı-yüzeyi: GERÇEK bir paketin defterinden
zincir-ucu (D5 sha256, tam-64-hex) okunur; epoch-batch yaprak-şemasıyla
(k256(k256(bytes32))) kodlanır ve çıktı JSON'una (stdout ya da -o) yazılır.

SÖZLEŞME (sunum-paritesi — RFC-009 §3):
- Bu araç zincir-ucunu ve yaprak-kodlamasını ÜRETİR; dış-batch'in geçerliliğini
  ASLA iddia-etmez (presentation-only). Çıktıya dürüstlük-sınırı işlenir.
- Defter zinciri D5-uyumlu-doğrulanır; bozuk-zincir → RED (reason-14-ailesi).

Kullanım:
  tamga project-head <pkg>                  # stdout JSON
  tamga project-head <pkg> -o head.json      # dosyaya
"""
import argparse
import hashlib
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from tamga_keccak import keccak256  # noqa: E402
from tamga_validator import jcs  # noqa: E402

K = lambda b: bytes.fromhex(keccak256(b).hex())  # noqa: E731


def chain_head(pkg: pathlib.Path) -> tuple[str, int]:
    """Defteri D5 boyunca yeniden-oynar; (head, lines) döndürür; kırık → ValueError.

    Gerçek-D5 (tamga_runner._verify_chain ile birebir):
      - başlangıç-sentinel: prev_h = "0"*64; sayaç kayıttan SONRA artar (seq 1-tabanlı)
      - node_sig HASH-DIŞINDA (imza ayrıca-doğrulanır; burada yalnız zincir-matematiği)
      - h = sha256((rec["prev"] + jcs(record − {h, node_sig})).encode())
      - zincir-bağı: rec["prev"] == önceki-h, rec["seq"] == sıra
    """
    ledger = pkg / "ledger.jsonl"
    if not ledger.is_file():
        raise ValueError(f"defter-yok: {ledger}")
    prev_h, n = "0" * 64, 0
    for line in ledger.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        n += 1
        rec = json.loads(line)
        if not isinstance(rec, dict):
            raise ValueError(f"kayıt nesne değil (satır {n}) — reason-14 ailesi")
        no_h = {k: v for k, v in rec.items() if k != "h" and k != "node_sig"}
        j = jcs(no_h)
        j = j.encode() if isinstance(j, str) else j
        exp = hashlib.sha256(rec.get("prev", "").encode("utf-8") + j).hexdigest()
        if rec.get("prev") != prev_h or rec.get("h") != exp or rec.get("seq") != n:
            raise ValueError(f"zincir-kırık (reason-14): broken@{n}")
        prev_h = rec["h"]
    return prev_h, n


def project(head_hex: str) -> dict:
    raw = bytes.fromhex(head_hex)
    leaf = "0x" + K(K(raw)).hex()
    return {
        "projection_version": "TAMGA_PROJECT_HEAD_V1",
        "chain_head": head_hex,
        "digest_family": "sha256-64hex (felt-abbreviated DEĞİL; baştaki-sıfır-korunur)",
        "leaf_encoded": leaf,
        "leaf_encoding": "keccak256(keccak256(bytes32(digest))) — OZ-StandardMerkleTree şeması (sort_leaves, sorted_pairs)",
        "honest_boundary": (
            "presentation-only: bu-yaprak dış-batch'e-izdüşürülebilir; dış-registry'nin "
            "geçerliliği ASLA bu-çıktının-iddiası-değil (RFC-009 §3/§4.4)"
        ),
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="tamga project-head",
                                 description="chain-head → batch-leaf projection (RFC-009/AT-022)")
    ap.add_argument("pkg", help="paket-dizini (ledger.jsonl içeren)")
    ap.add_argument("-o", "--out", help="çıktı-dosyası (yoksa stdout)")
    a = ap.parse_args(argv)
    try:
        head, n = chain_head(pathlib.Path(a.pkg))
    except (ValueError, AttributeError, TypeError, KeyError) as e:
        print(f"RED: {e}", file=sys.stderr)
        return 1
    out = project(head)
    out["ledger_lines"] = n
    txt = json.dumps(out, indent=1, ensure_ascii=False) + "\n"
    if a.out:
        pathlib.Path(a.out).write_text(txt, encoding="utf-8")
        print(f"OK: {a.out} (chain-head {head[:16]}…, {n} kayıt)")
    else:
        print(txt, end="")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""
AT-057-üretim-corpus-üretici — .evidence/PROD-CORPUS/altında-deneysel-üretim-
ledger'ı-yazar.

NEDEN-AYRI-DOSYA: bash-heredoc-içinde-python-literal-leri-tırnaklama-tuzağına-
düştü ("0"*64-ve-rec-sözlükleri). Ayrı-modül-bunu-tamamen-ortadan-kaldırır ve
testin-okunabilirliğini-korar.

DÜRÜST-ETİKET: bu-CANLI-üretim-değildir — repo-içi-deneysel-üretim-koşusudur.
Ama tests/-dışında-olduğu-için-corpus_ops(production_only=True)-tarafından-üretim
sayılır ve seq+prev+h-üçlüsü-gerçek-ledger-formatına-uayar. Amacı-fixture-
kanıtıyla-üretim-kanıtı-arasındaki-ayrımı-makine-ile-sabitlemektir (Veridict-
canary-2026-09-20-aynası).
"""
import json
import os
import pathlib
import sys

sys.path.insert(0, ".")
sys.argv = ["x"]

import tamga_runner as TR  # noqa: E402

OUT = pathlib.Path(os.environ.get(
    "PROD", ".evidence/PROD-CORPUS/2026-09-20")) / "prodrun" / "ledger.jsonl"

RECORDS = [
    {"op": "charge", "pkg": "at057-prodrun", "session": 1,
     "engine": "wasmtime-v48.0.1", "cpu_saat": 0.01, "ram_gb_sn": 0.05,
     "io_mb": 0.0, "wall_ms": 12, "fee_birebir": "0",
     "stdout_sha256": "0" * 64, "reason": "at057-uretim-corpus-kaniti"},
    {"op": "grant", "pkg": "at057-prodrun", "session": 1,
     "to": "at057-identity", "amount": "1", "unit": "deneme",
     "reason": "at057-uretim-corpus-kaniti"},
    {"op": "migrate-net", "pkg": "at057-prodrun", "session": 1,
     "from": "old-node", "to": "new-node",
     "reason": "at057-uretim-corpus-kaniti"},
    # RFC-009-dış-zincir-çapası (AT-059-pilot, 2026-09-20): R9-1-sürüm-sabit +
    # R9-5-presentation-only-etiketi-üretim-corpus'unda-da-taşınır — anchor'ın
    # üretim-erişilebilirliği-kanıtlanır (üçüncü-seçenek-yasak-uyumlu).
    {"op": "anchor", "pkg": "at057-prodrun", "session": 1,
     "anchor_version": "TAMGA_EXTERNAL_ANCHOR_V1",
     "foreign_registry": "apodix/epoch",
     "foreign_fact": "0x02362521254a8ca4f75097267655f6aeb8524217a25c261f60538edc367136e2",
     "foreign_digest": "0x997c497ef5fe81b98290e990cd8f62e674bd55db8ab3c3ea85d3931b1e6ff71d",
     "verified_at": "2026-09-10T07:32:08Z",
     "tool": "verifier_epoque + tamga_keccak (dual-impl)",
     "presentation_only": True,
     "reason": "at057-uretim-corpus-kaniti"},
]


def main() -> int:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("", encoding="utf-8")
    ops = []
    for rec in RECORDS:
        r = TR._ledger_append(OUT, rec)
        # _ledger_append-hata-halinde-out(False,...)-int-döndürür (rc=1);
        # başarı-halinde-YAZILAN-SATIRI-(dict)-döndürür, 'ok'-içermez.
        if isinstance(r, int) or not isinstance(r, dict):
            print(f"  YAZIM-BAŞARISIZ {rec['op']}: {r}", file=sys.stderr)
            return 1
        ops.append(rec["op"])
    # üçlü-doğrulama
    for line in OUT.read_text(encoding="utf-8").splitlines():
        if line.strip():
            row = json.loads(line)
            assert all(k in row for k in ("seq", "prev", "h")), \
                f"üçlü-eksik: {row.keys()}"
    print(f"  üretim-ledger-üretildi: {OUT} ({len(ops)}-satır, üçlü-tamam)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

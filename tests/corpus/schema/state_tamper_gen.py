#!/usr/bin/env python3
"""schema-corpus üreticisi — state.json tamper desenleri (Audit-15/16 aileleri).

Girdi: sağlam bir state.json (JSON dosya-yolu argümanı).
Çıktı: 5 tamper-deseni — her biri deterministik, aynı girdi üzerinde birebir
aynı bayt'ları üretir; her birinin BEKLENEN sonucu manifest'te yazılı
(Audit-15 semantiği: state-tampering fail-closed ama zincire etksiz).

Desenler (Audit-15/16 ile kök-aynı):
  truncated     — ilk-40 bayta-böl (fail-closed RED-5 'state_invalid' beklenir)
  invalid-json  — gövdeye tek bozuk-karakter (RED-5 beklenir)
  tip-swap      — ledger_tip='f'*64 (komşu-kayda etki YOK; F21 disiplini)
  sessions-inflate — sessions=99 (zincire etki YOK; seq sağlam)
  nested-deep  — 1000-düzey iç içe yabancı-alan (çökme-YOK; tolerans beklenir)

Corpus-kuralı: yalnız üretici + deterministik; sağlam state'i saklamaz,
tüm süreç ad hoc paket klasöründe türetilir.

Kullanım:
  python3 state_tamper_gen.py <state.json> <out-dir>
"""

import hashlib
import json
import sys
import pathlib

PAT = ("truncated", "invalid-json", "tip-swap", "sessions-inflate", "nested-deep")


def derive(raw: bytes) -> dict:
    st = json.loads(raw)
    out = {
        "truncated": raw[:40],
        "invalid-json": raw[: len(raw) // 2] + b"\x00" + raw[len(raw) // 2 :],
    }
    s = dict(st); s["ledger_tip"] = "f" * 64
    out["tip-swap"] = json.dumps(s).encode()
    s = dict(st); s["sessions"] = 99
    out["sessions-inflate"] = json.dumps(s).encode()
    # nested-deep: 1000-düzey-iç-içe — json.dumps özyineleme-tavanı 3.10/3.11'de
    # RecursionError fırlatır (CI-matris-bulgusu 2026-09-11; 3.12+ C-yoluyla geçer).
    # Dize-birleştirme-üretimi: tavan-bağımsız, deterministik, haberleşme-yok:
    deep = json.dumps(st)
    out["nested-deep"] = ('{"n": ' * 1000 + deep + "}" * 1000).encode()
    return out


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    src, out = pathlib.Path(argv[0]), pathlib.Path(argv[1])
    raw = src.read_bytes()
    out.mkdir(parents=True, exist_ok=True)
    manifest = {"source_sha256": hashlib.sha256(raw).hexdigest(), "patterns": {}}
    expect = {
        "truncated": "RED-5 state_invalid (fail-closed, traceback-YOK)",
        "invalid-json": "RED-5 state_invalid (fail-closed)",
        "tip-swap": "zincire-ETKISIZ (ledger dogru kalir; F21)",
        "sessions-inflate": "zincire-ETKISIZ (seq bozulmaz)",
        "nested-deep": "tolere (cokme-YOK)",
    }
    for name in PAT:
        data = derive(raw)[name]
        p = out / f"{name}.json"
        p.write_bytes(data)
        manifest["patterns"][name] = {
            "bytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
            "expected": expect[name],
        }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2))
    print(f"corpus: 5 desen uretildi -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

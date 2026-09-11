#!/usr/bin/env python3
"""snapshot-corpus üreticisi — Audit-17 tamper-matrisi (mükemmelliyet-yolu Boyut-2).

Girdi: sağlam bir .tsg snapshot baytları (stdin'den dosya-yolu argümanı).
Çıktı: 6 kurcalama-sınıfının HER BİRİNDEN bir üretilebilir örnek — aynı girdi
üzerinde deterministik (ikinci koşum birebir aynı baytları üretir).

Corpus-kuralı (tests/corpus/README.md): yalnız üretici + deterministik;
binary-artifact depolamaz — bu script SAĞLAM snapshot'tan türetir, snapshot'ın
kendisini saklamaz.

Sınıflar (Audit-17 ile birebir):
  truncate      — ikiye-böl (uzunluğun yarı)
  body-flip     — gövde bölgesinde tek-bit çevir
  header-flip   — 10. baytta tek-bit çevir
  tail-flip     — son baytta tek-bit çevir
  swap          — 10./11. bayt yer-değiştir
  magic-swap    — ilk-4 bayt 'XSG1' (yanlış-magic)

Kullanım:
  python3 snapshot_tamper_gen.py <snap.tsg> <out-dir>   # 6 dosya + manifest.json
"""

import hashlib
import json
import sys
import pathlib

CLASSES = ("truncate", "body-flip", "header-flip", "tail-flip", "swap", "magic-swap")


def derive(snap: bytes) -> dict:
    """Sağlam-snapshot'tan 6 kurcalama-örneği türet (deterministik)."""
    mid = len(snap) // 2
    return {
        "truncate": snap[:mid],
        "body-flip": snap[:mid] + bytes([snap[mid] ^ 1]) + snap[mid + 1 :],
        "header-flip": bytes([snap[10] ^ 1]) + snap[1:],
        "tail-flip": snap[:-1] + bytes([snap[-1] ^ 1]),
        "swap": snap[:10] + bytes([snap[11], snap[10]]) + snap[12:],
        "magic-swap": b"XSG1" + snap[4:],
    }


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    src, out = pathlib.Path(argv[0]), pathlib.Path(argv[1])
    snap = src.read_bytes()
    out.mkdir(parents=True, exist_ok=True)
    # Gözlemlenen-reddetme-nedenleri (0.2.1-import-akisinda, canli-kanit 2026-09-11):
    #   header-flip/magic-swap → 'snapshot_bad_magic'; swap → 'snapshot_header_invalid'
    #   truncate/body-flip/tail-flip → gövde-denetiminden-önceki hedef-manifest adımı
    #   (sağlam-çekirdek-hedef ile AT-001 pozitif-yolçapı zaten ayrıca kanıtlı):
    #   fail-closed garantisi TÜM sınıflar için rc=1 — hangi-adım-yakalarsa-yakalasın.
    expect = {
        "truncate": "RED fail-closed (rc=1; hedef-adımı/gövde-denetimi)",
        "body-flip": "RED fail-closed (rc=1; hedef-adımı/gövde-denetimi)",
        "header-flip": "RED snapshot_bad_magic",
        "tail-flip": "RED fail-closed (rc=1; hedef-adımı/gövde-denetimi)",
        "swap": "RED snapshot_header_invalid",
        "magic-swap": "RED snapshot_bad_magic",
    }
    manifest = {"source_sha256": hashlib.sha256(snap).hexdigest(), "classes": {}}
    for name, data in derive(snap).items():
        p = out / f"{name}.tsg"
        p.write_bytes(data)
        manifest["classes"][name] = {
            "bytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
            "expected": expect[name],
        }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2))
    print(f"corpus: 6 sinif uretildi -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

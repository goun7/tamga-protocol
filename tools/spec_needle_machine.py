#!/usr/bin/env python3
"""
AT-047: spec-needle-machine — Sester'ın-test_spec_needles.py'sinin-bizdeki-karşılığı.

DERS (Sester-2026-09-20): "spec'te-yazıyor" elle-grep-ile-kanıtlanamaz — göz
kaçırır. Bu-test-her-normatif-needle'ı-spec-dosyalarında-ARAR; kural-spec'ten
düşerse-RED. YÖN-B-artık-makine-ile-locked.

İki-yön-bir-arada (AT-046-tarayıcısının-sabit-versiyonu):
  YÖN-A: her-kural-üretimde-uygulanıyor (kırım → RED)  [AT-046'da-ölçülür]
  YÖN-B: her-kural-spec'te-belgeli (needle-var)         ← BURADA-locked

Ek: ** gözlemlenen-op-kümesi-spec-ile-uyumlu** — canlı-ledger'da-çıkıp-spec'te
yazmayan-değer-RED (E1(c)-sınıfı-otomatik-yakalama).
"""
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent
sys.path.insert(0, str(REPO))
sys.path.insert(0, str(HERE))

SPEC_DIR = REPO / "tests" / "conformance" / "spec"

# (spec-dosyası, needle, kural-id)
NEEDLES = [
    ("LEDGER-SPEC.md", "`seq`-1-based-aritmetik-artan", "L-3.1"),
    ("LEDGER-SPEC.md", "`prev`-önceki-kaydın-`h`-değerine-eşit", "L-3.2"),
    ("LEDGER-SPEC.md", "`h`-yukarıdaki-formüle-göre-yeniden-hesaplandığında-birebir-aynı", "L-3.3"),
    ("LEDGER-SPEC.md", "kayıt-bir-JSON-nesnesi-olmalı", "L-3.4"),
    ("LEDGER-SPEC.md", "satır-1-MiB'-i-aşamaz", "L-3.5"),
    ("LEDGER-SPEC.md", "I-JSON sınırı (RFC 7493 §2)", "L-IJSON"),
    ("LEDGER-SPEC.md", "Boş-zincir", "L-4"),
    ("LEDGER-SPEC.md", "(a) `op`-değerleri-KISITLANMAMIŞTIR", "E1(a)"),
    ("LEDGER-SPEC.md", "bilinmeyen-ekstra-alanlara-izin", "E1(b)"),
    ("LEDGER-SPEC.md", "Erratum E1(c)", "E1(c)"),
    ("ANCHOR-SPEC.md", '`type == "sovereign-anchor"`', "A-5.1t"),
    ("ANCHOR-SPEC.md", '`version == "0.1"`', "A-5.1v"),
    ("ANCHOR-SPEC.md", "`results`-bir-nesne-olmalı", "A-5.2"),
    ("ANCHOR-SPEC.md", "anchor_root    = sha256", "A-5.3"),
    ("ANCHOR-SPEC.md", "`products_proved ==", "A-5.4"),
    ("ANCHOR-SPEC.md", "`all_proved ==", "A-5.5"),
    ("ANCHOR-SPEC.md", "UNVERIFIED-INDEPENDENTLY", "A-5.6"),
    ("ANCHOR-SPEC.md", "Erratum A1", "A-A1"),
]

# spec'te-listelenen-gözlemlenebilir-küme (E1(c)-den-sonra)
SPEC_OPS = ("charge", "grant", "fee", "replace", "note")


def check_needles() -> list:
    missing = []
    for fname, needle, rid in NEEDLES:
        p = SPEC_DIR / fname
        if not p.exists():
            missing.append((rid, fname, "DOSYA-YOK"))
            continue
        t = p.read_text(encoding="utf-8")
        if needle not in t:
            missing.append((rid, fname, f"needle-yok: {needle[:45]}"))
    return missing


def check_op_coverage() -> list:
    """E1(c)-sınıfı-otomatik-yakalama: canlı-ledger'da-çıkıp-spec'te-yazmayan-op."""
    spec = (SPEC_DIR / "LEDGER-SPEC.md").read_text(encoding="utf-8")
    found = set()
    for p in REPO.rglob("*.jsonl"):
        if "__pycache__" in p.parts or ".evidence" in p.parts:
            pass  # __pycache__-DAHİL — canlı-oturum-ledger'ı-oranın-olabilir
        try:
            for m in re.finditer(r'"op":\s*"([a-z][a-z-]*)"', p.read_text(encoding="utf-8", errors="replace")):
                found.add(m.group(1))
        except OSError:
            continue
    # spec'te-adı-geçen-değerler
    in_spec = {o for o in SPEC_OPS if o in spec}
    # fixture-dışı-üretim-op'ları: spec'te-adı-geçmeyenler
    undocumented = {o for o in found if o not in in_spec}
    # kontrol-op'ları (test-fixture'ları, kasıtlı): BILINMEYEN/ekstra serbest
    undocumented -= {"BILINMEYEN"}
    return sorted(undocumented), sorted(found)


def main(argv: list[str]) -> int:
    problems = []
    miss = check_needles()
    if miss:
        for rid, fname, why in miss:
            problems.append(f"[{rid}] {fname}: {why}")
    undoc, found = check_op_coverage()
    if undoc:
        problems.append(f"[E1(c)-otomatik] spec'te-yazmayan-ledger-op'ları: {undoc}")
    if problems:
        print("SPEC-NEEDLE-BAŞARISIZ:")
        for p in problems:
            print(f"  ✗ {p}")
        print(f"\n  needle-sayısı: {len(NEEDLES)} | gözlemlenen-op'lar: {found}")
        return 1
    print(f"  {len(NEEDLES)}-needle-hepsi-spec'te-belgeli (makine-ile-kanıtlandı)")
    print(f"  gözlemlenen-op'lar-hepsi-spec'te: {sorted(found)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

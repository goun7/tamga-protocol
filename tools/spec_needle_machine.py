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
# replace-çıkarıldı (E1(c)-düzeltme): tool/result-gürültüsü-idi
SPEC_OPS = ("charge", "grant", "fee", "note")


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
        try:
            txt = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        # LEDGER-FİLTRESİ (E1(c)-düzeltme): session.v3.jsonl-gibi-DSH-oturum
        # dosyaları-da-'op'-anahtarı-taşır → tool/result-gürültüsü. Yalnızca
        # seq+prev+h-üçlüsünü-taşıyan-satırlar-gerçek-ledger'dır.
        for line in txt.splitlines():
            if not ("\"seq\"" in line and "\"prev\"" in line and "\"h\"" in line):
                continue
            for m in re.finditer(r'"op":\s*"([a-z][a-z-]*)"', line):
                found.add(m.group(1))
    # spec'te-adı-geçen-değerler
    in_spec = {o for o in SPEC_OPS if o in spec}
    # fixture-dışı-üretim-op'ları: spec'te-adı-geçmeyenler
    undocumented = {o for o in found if o not in in_spec}
    # kontrol-op'ları (test-fixture'ları, kasıtlı): BILINMEYEN/ekstra serbest
    undocumented -= {"BILINMEYEN"}
    return sorted(undocumented), sorted(found)


def _spec_ops(spec_text: str) -> set:
    """Spec'te-adı-geçen-op-değerlerini-OTOMATIK-çıkar.

    DERS (Sester-2026-09-20): elle-tutulan-üretici-tabloları-kirlenir
    (onların-EVENT_TYPE_SOURCES'ı-yanlış-yol-gösteriyordu). Bu-liste-de-aynı
    tuzakta-idi — SPEC_OPS-sabiti-elle-yazılmıştı. Artık-spec'in-kendisinden
    okunuyor: hem-listeli-hem-reserved-değerler-belgeden-gelir.
    """
    # SADECE-yapısal-liste-satırları: "Kayıt-türleri:" + "**RESERVED".
    # Prose-erratum-cümlelerini-dahil-ETME — \`fee\` orada da-geçiyor-ve
    # makine-onu-iki-kez-listeli-sayıyor → ölü-tarama-bozuluyor.
    ids = set()
    lines = spec_text.splitlines()
    for i, line in enumerate(lines):
        if line.startswith("Kayıt-türleri:"):
            j = i + 1
            blob = line
            while j < len(lines) and lines[j].strip() and not lines[j].startswith("**"):
                blob += " " + lines[j]; j += 1
            ids |= set(re.findall(r"`([a-z][a-z-]+)`", blob))
        if line.startswith("**RESERVED"):
            j = i + 1
            blob = line
            while j < len(lines) and lines[j].strip() and not lines[j].startswith("**"):
                blob += " " + lines[j]; j += 1
            ids |= set(re.findall(r"`([a-z][a-z-]+)`", blob))
    return ids


def check_dead_entries() -> list:
    """Sester'ın-test_209_taxonomy_has_no_dead_entries'inin-bizdeki-karşılığı.

    Spec'te-listeli-ama-hiç-yayınlanmayan-op-RED — **ancak-açıkça-reserved
    olarak-belgelenmişse-GREEN.** Bu-ayırt-önemli:
      - Sester'ın-usage_event'i: panel-etiketinden-varsayım, emitter-yok,reserved
        notu-yok → ÖLÜ → kaldırıldı
      - Bizim-fee'miz: §1'de-açıkça-'ayrılmış'-diyor → meşru-reserved, kalır
    """
    spec = (SPEC_DIR / "LEDGER-SPEC.md").read_text(encoding="utf-8")
    found = set()
    for p in REPO.rglob("*.jsonl"):
        try:
            txt = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for line in txt.splitlines():
            if not ("\"seq\"" in line and "\"prev\"" in line and "\"h\"" in line):
                continue
            for m in re.finditer(r'"op":\s*"([a-z][a-z-]*)"', line):
                found.add(m.group(1))
    listed = _spec_ops(spec)
    dead = []
    for o in sorted(listed):
        if o in found:
            continue
        # reserved-olarak-belgeli-mi? YAPI-BAZLI: ayrı-bir-RESERVED-satırında
        # listeliyse-GREEN. Pencere-tabanlı-yaklaşım-BUĞDAYTI: parantez-içine
        # gömülen-yeni-değer-reserved-notundan-geçer-geliyordu (deneme-op,
        # fee'nin-ayrılmış-parantezi-içine-yazılınca-yeşil-döndü).
        # AYNI-satırda-reserved-anahtar-kelime-veya-RESERVED-listesinde
        # RESERVED-bloğunu-aynı-blob-okuma-ile-al (_spec_ops-ile-tutarlı)
        reserved = set()
        lines = spec.splitlines()
        for i, ln in enumerate(lines):
            if ln.startswith("**RESERVED"):
                j = i + 1
                blob = ln
                while j < len(lines) and lines[j].strip() and not lines[j].startswith("**"):
                    blob += " " + lines[j]; j += 1
                reserved |= set(re.findall(r"`([a-z][a-z-]+)`", blob))
        if o in reserved:
            continue
        dead.append(o)
    return dead


def main(argv: list[str]) -> int:
    problems = []
    miss = check_needles()
    if miss:
        for rid, fname, why in miss:
            problems.append(f"[{rid}] {fname}: {why}")
    undoc, found = check_op_coverage()
    if undoc:
        problems.append(f"[E1(c)-otomatik] spec'te-yazmayan-ledger-op'ları: {undoc}")
    dead = check_dead_entries()
    if dead:
        problems.append(f"[Sester-209-aynası] ÖLÜ-girdiler (listeli-ama-yayılmayan-"
                        f"ve-reserved-değil): {dead}")
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

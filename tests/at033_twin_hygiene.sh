#!/usr/bin/env bash
# at033_twin_hygiene.sh — dil-ikizi hijyeni (2026-09-16 gece-ikizi-üretiminden doğan sınıf-borcu):
#  K1. her docs/*.tr.md İNGİLİZCE-orijinalli olmalı (TR-density<40/k) — Türkçe-doğmuş belgeye
#      TR-ikiz üretmek SADECE-BLOCKQUOTE-FARKLI ÖZDEŞ-KOPYA demektir (005/006 + VERIFY-EPOCH'ta
#      iki-kez yakalandı; duplicate-owner kırmızı-çizgisi).
#  K2. her Türkçe-doğmuş belgenin (density≥40) .tr.md KARDEŞİ OLMAMALI.
#  K3. ikiz-yetimi: README dil-notu elle-sayaç TAŞIMAZ (disk-türer-tek-doğru-kaynak ilkesi —
#      "Nine Turkish twins now exist" tipi bayat-sayaç-baytları yasak).
set -u
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
F() { echo "  FAIL: $1"; exit 1; }
python3 - >"$D/out" 2>&1 <<'PY'
import pathlib, sys
def dens(t):
    tr = sum(t.count(c) for c in "çğıöşüÇĞİÖŞÜ"); le = sum(1 for c in t if c.isalpha())
    return tr / max(le, 1) * 1000
viol = []
born = []
for p in sorted(pathlib.Path("docs").glob("*.tr.md")):
    src = p.with_name(p.name[:-len(".tr.md")] + ".md")
    if not src.exists(): viol.append(f"{p.name}: orijinal-yok {src.name}")
    elif dens(src.read_text()) >= 40: viol.append(f"{p.name}: ORİJİNAL TÜRKÇE-doğmuş ({src.name}) — özdeş-kopya-ikiz yasak")
for p in sorted(pathlib.Path("docs").glob("*.md")):
    if p.name.endswith(".tr.md"): continue
    if dens(p.read_text()) >= 40:
        born.append(p.name)
        if p.with_name(p.stem + ".tr.md").exists():
            viol.append(f"{p.name}: TR-orijinale TR-kardeş-üretilmiş")
# K3: README'lerde elle-ikiz-sayaçı deseni (sekiz|dokuz|N Turkish twins|N Türkçe-ikiz)
import re
for f in ["README.md", "README.tr.md"]:
    t = pathlib.Path(f).read_text()
    if re.search(r"(sekiz|dokuz|yedi|on bir|Nine|Eight|Seven) Turkish twins|dokuz Türkçe-ikiz|sekiz Türkçe-ikiz", t, re.I):
        viol.append(f"{f}: elle-sayaç-ikiz-baytı (disk-türer olmalı)")
print("OK docs-md-scan; TR-doğmuş-aile:", ", ".join(born))
sys.exit(1 if viol else 0)
PY
RC=$?
[ $RC -ne 0 ] && cat "$D/out" && F "ikiz-hijyeni"
grep -q "OK" "$D/out" || cat "$D/out"
echo "AT-033 twin-hygiene: K1+K2+K3 PASS ($(cat "$D/out" | grep -c OK) taranmış-set temiz)"

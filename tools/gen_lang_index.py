#!/usr/bin/env python3
"""gen_lang_index.py — docs/INDEX.md içindeki Dil-durumu satırını DİSKTEN ÜRETİR.
Amacı: ikiz-kopyaların/elle-sayaçların babası olan 'elle-yazılmış-durum-satırı'nı bir araç
çıktısına dönüştürmek (AT-033 K3'ün uygulanan-hali: satır-türer, bayatlayamaz).
Kullanım: python3 tools/gen_lang_index.py [--check]   --check: fark-varsa rc1 (CI'ya-asılabilir)."""
import pathlib, re, sys

def dens(t: str) -> float:
    tr = sum(t.count(c) for c in "çğıöşüÇĞİÖŞÜ")
    le = sum(1 for c in t if c.isalpha())
    return tr / max(le, 1) * 1000

docs = pathlib.Path("docs")
base = "https://github.com/goun7/tamga-protocol/blob/main/docs/"
born = sorted(x.name for x in docs.glob("*.md")
              if not x.name.endswith((".tr.md", ".en.md")) and dens(x.read_text()) >= 40)
en = sorted(x.name for x in docs.glob("*.en.md"))
tr = sorted(x.name for x in docs.glob("*.tr.md"))
line = ("   Dil-durumu (tamamı-disk-türer, elle-bakım YOK — AT-033 bekçisi): bağlayıcı-orijinal BELGE-BAŞINA tek; "
        "İngilizce-doğmuşlar TR-ikizleriyle, Türkçe-doğmuşlar EN-kardeşleriyle. Türkçe-doğmuş aile: "
        + " · ".join(f"[{b}]({base}{b})" for b in born)
        + " (ayrışmada TR bağlar; EN-kardeşleri: " + " · ".join(f"[{e}]({base}{e})" for e in en) + ")"
        + " — İngilizce-doğmuş belgelerin TR-ikizleri: " + " · ".join(f"[{t}]({base}{t})" for t in tr) + "\n")
p = docs / "INDEX.md"
s = p.read_text()
m = re.search(r"   Dil-durumu[^\n]*\n", s)
if not m:
    print("HATA: INDEX'te Dil-durumu satırı yok", file=sys.stderr); sys.exit(2)
if "--check" in sys.argv:
    if s[m.start():m.end()] == line:
        sys.exit(0)
    print("FARK: Dil-durumu satırı diske-göre-bayat — regenerate et", file=sys.stderr); sys.exit(1)
p.write_text(s.replace(m.group(0), line))
print(f"üretildi: {len(born)} doğmuş-TR · {len(en)} EN-kardeş · {len(tr)} TR-ikiz")

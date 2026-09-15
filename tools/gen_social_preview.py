#!/usr/bin/env python3
"""gen_social_preview.py — docs/assets/social-preview.png üreteci (1200x640).

Kalıcılık-gerekçesi: 09-13 kartı elle üretildi; sürüm kartına "v0.2.4" gömüldü,
0.2.5/0.2.6 yayınlanınca kart BAYATLADI (taze-kullanıcı denetimi 2026-09-15).
Bu script sürümü pyproject.toml'dan, kontrol-sayısını docs/TESTS.md'den OKUR —
tek-gercek-kaynak-kuralı: kart ASLA elle-sürüm-metni TAŞIMAZ.

Kullanım: python3 tools/gen_social_preview.py
Bağımlılık: rsvg-convert (system), fontconfig'ta DejaVu Serif Condensed + Liberation Sans.
Doğrulama-rutini: çıktıyı OCR ile-oku (tesseract eng) — dört-satır-da-görünmüyorsa
kart BEYAZ-ENDEKS-Lİ; yayın-yasak.
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

def main() -> int:
    ver = re.search(r'^version = "([^"]+)"', (ROOT / "pyproject.toml").read_text(), re.M).group(1)
    tests = (ROOT / "docs" / "TESTS.md").read_text()
    fast = re.search(r"(\d+)/\d+ controls", tests).group(1)
    slow = re.search(r"(\d+)/\d+ with RUN_SLOW", tests).group(1)
    logo_src = (ROOT / "docs" / "assets" / "logo.svg").read_text()
    vb = re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', logo_src)
    vw, vh = float(vb.group(1)), float(vb.group(2))
    inner = re.sub(r"^.*?<svg[^>]*>", "", logo_src, flags=re.S)
    inner = re.sub(r"</svg>\s*$", "", inner)
    MW, MH = 210, 210 * vh / vw
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="640" viewBox="0 0 1200 640">
<rect width="1200" height="640" fill="#0b1220"/>
<rect x="0" y="0" width="1200" height="6" fill="#e8a33d"/>
<svg x="100" y="96" width="{MW:.0f}" height="{MH:.0f}" viewBox="0 0 {vw:.0f} {vh:.0f}" color="#e8a33d">{inner}</svg>
<text x="310" y="176" font-family="DejaVu Serif" font-weight="bold" font-size="92" fill="#e8a33d" letter-spacing="6">TAMGA</text>
<text x="312" y="232" font-family="Liberation Sans" font-size="34" fill="#94a3b8" letter-spacing="14">PROTOCOL</text>
<text x="100" y="330" font-family="DejaVu Serif" font-weight="bold" font-size="34" fill="#f1f5f9">Self-custodial agent state that survives the host</text>
<text x="100" y="388" font-family="Liberation Sans" font-size="26" fill="#38bdf8">{fast}/{fast} adversarial controls · v{ver} · {slow} with slow-gate</text>
<text x="100" y="440" font-family="Liberation Sans" font-size="22" fill="#64748b">ed25519 · XChaCha20-Poly1305 · hash-chain ledger · WASI re-execution</text>
<text x="100" y="560" font-family="Liberation Sans" font-size="26" fill="#94a3b8">github.com/goun7/tamga-protocol · Apache-2.0</text>
</svg>"""
    tmp = pathlib.Path("/tmp/social-preview.svg")
    tmp.write_text(svg, encoding="utf-8")
    out = ROOT / "docs" / "assets" / "social-preview.png"
    r = subprocess.run(["rsvg-convert", "-w", "1200", "-h", "640", "-o", str(out), str(tmp)])
    if r.returncode != 0:
        print("rsvg-convert BAŞARISIZ", file=sys.stderr); return 1
    # oto-doğrulama (2026-09-15 dersi: ilk regenerasyon satır-kenetlenmesiyle kaçtı —
    # OCR-YLA-yakalandı; şimdi araç KENDİ çıktısını band-profilinden-sayar):
    import numpy as np
    from PIL import Image
    im = np.array(Image.open(out).convert("RGB")).astype(int)
    fg = (im.sum(axis=2) > 240)  # #0b1220-toplam≈107 vs metin-min-#64748b≈356 altından-güvenli
    rows = fg[:, 80:1160].sum(axis=1)
    bands, cur, low_streak = [], None, 0
    for y, v in enumerate(rows):
        if v >= 12:                      # gerçek-metin-satırı
            cur = [cur[0], y] if cur else [y, y]
            low_streak = 0
        elif cur is not None:
            low_streak += 1              # antialiasing-kuyruğu-toleransı
            if low_streak >= 6:
                bands.append(cur); cur = None
    if cur is not None:
        bands.append(cur)
    gaps = [bands[i+1][0]-bands[i][1] for i in range(len(bands)-1)]
    if len(bands) != 6 or any(g < 14 for g in gaps):
        print(f"BAND-KONTROL BAŞARISIZ: {len(bands)} bant {bands}, boşluklar {gaps} "
              f"(6 bant, hepsi >=14px beklenirdi) — kart YAYINLANMADI", file=sys.stderr)
        return 2
    print(f"üretildi: {out} (v{ver}, {fast}/{slow}) — 6 bant, min-boşluk {min(gaps)}px ✓ "
          f"OCR-rutini yine-önerilir")
    return 0

if __name__ == "__main__":
    sys.exit(main())

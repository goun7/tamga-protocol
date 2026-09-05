#!/usr/bin/env python3
"""GitHub social-preview image — 1280x640 (GitHub recommended 2:1). Same visual language as banner.svg."""
from PIL import Image, ImageDraw, ImageFont

W, H = 1280, 640
img = Image.new("RGB", (W, H), "#0b1220")
d = ImageDraw.Draw(img)
# zemin gradyanı (sol-üst koyu → sağ-alt hafif açık lacivert)
for y in range(H):
    t = y / H
    r = int(11 + 5 * t); g = int(18 + 11 * t); b = int(32 + 19 * t)
    d.line([(0, y), (W, y)], fill=(r, g, b))
# kenar vurgusu
d.rectangle([3, 3, W-4, H-4], outline=(232, 163, 61), width=3)
d.rectangle([10, 10, W-11, H-11], outline=(56, 189, 248), width=1)

F = "/usr/share/fonts/noto/"
f_title = ImageFont.truetype(F + "NotoSans-Bold.ttf", 120)
f_sub   = ImageFont.truetype(F + "NotoSans-Bold.ttf", 34)
f_body  = ImageFont.truetype(F + "NotoSans-Regular.ttf", 27)
f_bodyB = ImageFont.truetype(F + "NotoSans-Bold.ttf", 27)

# mühür + zincir motifi (SVG'dekiyle aynı dil)
cx, cy = 200, 300
d.ellipse([cx-78, cy-78, cx+78, cy+78], outline=(56, 189, 248), width=8)
d.ellipse([cx-52, cy-52, cx+52, cy+52], outline=(56, 189, 248), width=4)
d.ellipse([cx-22, cy-22, cx+22, cy+22], fill=(232, 163, 61))
# zincir bağları
d.line([(cx+78, cy), (cx+150, cy)], fill=(56, 189, 248), width=7)
d.ellipse([cx+150-32, cy-32, cx+150+32, cy+32], outline=(56, 189, 248), width=5)
d.line([(cx+182, cy), (cx+240, cy)], fill=(56, 189, 248), width=5)
d.ellipse([cx+240-22, cy-22, cx+240+22, cy+22], outline=(56, 189, 248), width=4)

# başlık + alt-başlık
tx = 340
d.text((tx, 210), "TAMGA", font=f_title, fill=(241, 245, 249))
w = d.textlength("TAMGA", font=f_title)
d.text((tx, 345), "PROTOCOL", font=f_sub, fill=(125, 211, 252))
# altın çizgi
d.line([(tx, 400), (tx + 330, 400)], fill=(232, 163, 61), width=4)
# üç ayak
y = 440
for t in ["Portable identity", "Encrypted memory", "Verifiable work receipts"]:
    d.ellipse([tx, y+9, tx+12, y+21], fill=(232, 163, 61))
    d.text((tx+26, y), t, font=f_bodyB, fill=(203, 213, 225))
    y += 44
# durum-şeridi
d.text((tx, 580), "Phase 2 · pilot · Apache-2.0 · evidence-first", font=f_body, fill=(148, 163, 184))
img.save("docs/assets/social-preview.png", optimize=True)
print("docs/assets/social-preview.png —", img.size)

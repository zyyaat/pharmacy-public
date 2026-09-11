#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Task 67 — توليد أيقونات لانشر أندرويد من الأيقونة الرسمية للبراند.
# المصدر الرسمي: frontend/apps/*/public/brand/pharmacy-os-icon.svg
# (نفس الأيقونة المعتمدة في تطبيقات الواجهات الأمامية الأربعة — ملف واحد مطابق بالبايت).
# المخرجات: mobile/brand/launcher/ ويقوم prepare_android.sh (الترقيع 6) بنسخها
# إلى android/app/src/main/res/ أثناء البناء في CI.
#
# التشغيل:  python3 mobile/scripts/gen_launcher_icons.py
# المتطلبات: cairosvg + Pillow
import math
import os

import cairosvg
from PIL import Image, ImageDraw, ImageOps

HERE = os.path.dirname(os.path.abspath(__file__))
MOBILE = os.path.dirname(HERE)
REPO = os.path.dirname(MOBILE)
BRAND = os.path.join(MOBILE, 'brand', 'launcher')
SVG_PATH = os.path.join(
    REPO, 'frontend', 'apps', 'pharmacy-app', 'public', 'brand', 'pharmacy-os-icon.svg'
)

GREEN = '#00d084'
DARK = '#06100d'
HI = 1024  # دقة الرندر المصدر قبل النزول للأحجام

# أحجام legacy ic_launcher/ic_launcher_round (48dp × الكثافة)
LAUNCHER_SIZES = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
}
# أحجام طبقة foreground للأيقونة التكيفية (108dp × الكثافة)
FOREGROUND_SIZES = {
    'mipmap-mdpi': 108,
    'mipmap-hdpi': 162,
    'mipmap-xhdpi': 216,
    'mipmap-xxhdpi': 324,
    'mipmap-xxxhdpi': 432,
}

SVG = open(SVG_PATH, encoding='utf-8').read()

# الأعمدة الثلاثة = كل rect له خاصية x (مستطيل الخلفية الأخضر ليس فيه x)
BARS = '\n'.join(line.strip() for line in SVG.splitlines() if '<rect x=' in line)
if BARS.count('<rect') != 3:
    raise SystemExit(f'FATAL: expected 3 bars in SVG, found {BARS.count("<rect")}')

# ── 1) الأيقونة الكاملة (المربع الأخضر المستدير + الأعمدة) ────────────────
full = Image.open(__import__('io').BytesIO(
    cairosvg.svg2png(bytestring=SVG.encode('utf-8'),
                     output_width=HI, output_height=HI)))
full = full.convert('RGBA')

# ── 2) الأعمدة فقط (طبقة foreground — بلا الخلفية الخضراء) ────────────────
fg_svg_128 = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">'
              f'<g transform="rotate(-5 64 64)">{BARS}</g></svg>')
fg_src = Image.open(__import__('io').BytesIO(
    cairosvg.svg2png(bytestring=fg_svg_128.encode('utf-8'),
                     output_width=HI, output_height=HI))).convert('RGBA')
bbox = fg_src.getbbox()  # حدود الأعمدة المدورة داخل الكانفاس
bars = fg_src.crop(bbox)


def write(path: str, im: Image.Image) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, 'PNG')
    print(f'OK: {os.path.relpath(path, REPO)}  {im.size[0]}x{im.size[1]}')


# ── 3) ic_launcher.png + ic_launcher_round.png لكل الكثافات ───────────────
for folder, size in LAUNCHER_SIZES.items():
    legacy = full.resize((size, size), Image.LANCZOS)
    write(os.path.join(BRAND, folder, 'ic_launcher.png'), legacy)

    # النسخة الدائرية: قناع دائرة مندمجة تغطي كامل الكانفاس
    round_im = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    mask = Image.new('L', (size * 4, size * 4), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse((0, 0, size * 4 - 1, size * 4 - 1), fill=255)
    mask = mask.resize((size, size), Image.LANCZOS)
    round_im.paste(legacy, (0, 0), mask)
    write(os.path.join(BRAND, folder, 'ic_launcher_round.png'), round_im)

# ── 4) ic_launcher_foreground.png — الأعمدة وسط دائرة الأمان ──────────────
# قاعدة أندرويد: محتوى الطبقة يجب أن يقع داخل دائرة أمان قطرها 66/108 من الكانفاس.
# نُنزل الأعمدة حتى يكون نصف قطرها القطري ≈ 0.28 من الكانفاس (هامش مريح تحت 0.3055).
for folder, size in FOREGROUND_SIZES.items():
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    side = int(0.56 * size)  # أقصى بعد جانبي للمحتوى
    contained = ImageOps.contain(bars, (side, side), Image.LANCZOS)
    off = ((size - contained.size[0]) // 2, (size - contained.size[1]) // 2)
    canvas.paste(contained, off, contained)
    write(os.path.join(BRAND, folder, 'ic_launcher_foreground.png'), canvas)

# ── 5) أيقونة متجر Play ‏512×512 — مربع كامل بلا زوايا شفافة ──────────────
store_svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">'
             f'<rect width="128" height="128" fill="{GREEN}"/>'
             f'<g transform="rotate(-5 64 64)">{BARS}</g></svg>')
store = Image.open(__import__('io').BytesIO(
    cairosvg.svg2png(bytestring=store_svg.encode('utf-8'),
                     output_width=512, output_height=512))).convert('RGBA')
write(os.path.join(BRAND, 'playstore-icon.png'), store)

# ── 6) XML — الأيقونة التكيفية + لون الخلفية ──────────────────────────────
ADAPTIVE = ('<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '</adaptive-icon>\n')
anydpi = os.path.join(BRAND, 'mipmap-anydpi-v26')
write(os.path.join(anydpi, 'ic_launcher.xml'), Image.new('RGBA', (1, 1)))
with open(os.path.join(anydpi, 'ic_launcher.xml'), 'w', encoding='utf-8') as f:
    f.write(ADAPTIVE)
with open(os.path.join(anydpi, 'ic_launcher_round.xml'), 'w', encoding='utf-8') as f:
    f.write(ADAPTIVE)
print('OK: mipmap-anydpi-v26/ic_launcher.xml + ic_launcher_round.xml')

values_xml = os.path.join(BRAND, 'values', 'ic_launcher_background.xml')
os.makedirs(os.path.dirname(values_xml), exist_ok=True)
with open(values_xml, 'w', encoding='utf-8') as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n'
            '<resources>\n'
            '    <!-- أخضر البراند — نفس لون أيقونة الويب pharmacy-os-icon -->\n'
            f'    <color name="ic_launcher_background">{GREEN}</color>\n'
            '</resources>\n')
print('OK: values/ic_launcher_background.xml')

# ── 7) معاينة بصرية للفحص اليدوي ─────────────────────────────────────────
prev = Image.new('RGBA', (980, 360), (250, 250, 250, 255))
d = ImageDraw.Draw(prev)
d.text((30, 16), 'legacy 192 / round 192 / adaptive mock 192+96+48', fill=(20, 20, 20, 255))
prev.paste(full.resize((192, 192), Image.LANCZOS), (30, 60), full.resize((192, 192), Image.LANCZOS))
r192 = Image.open(os.path.join(BRAND, 'mipmap-xxxhdpi', 'ic_launcher_round.png'))
prev.paste(r192, (260, 60), r192)
fg432 = Image.open(os.path.join(BRAND, 'mipmap-xxxhdpi', 'ic_launcher_foreground.png'))
mock_bg = Image.new('RGBA', (192, 192), (0, 208, 132, 255))
m432 = fg432.resize((192, 192), Image.LANCZOS)
mock_bg.paste(m432, (0, 0), m432)
circ = Image.new('L', (768, 768), 0)
dc = ImageDraw.Draw(circ)
dc.ellipse((0, 0, 767, 767), fill=255)
circ = circ.resize((192, 192), Image.LANCZOS)
mocked = Image.new('RGBA', (192, 192), (0, 0, 0, 0))
mocked.paste(mock_bg, (0, 0), circ)
prev.paste(mocked, (490, 60), mocked)
fg96 = Image.open(os.path.join(BRAND, 'mipmap-xhdpi', 'ic_launcher_foreground.png')).resize((96, 96), Image.LANCZOS)
mock96 = Image.new('RGBA', (96, 96), (0, 208, 132, 255))
mock96.paste(fg96, (0, 0), fg96)
prev.paste(mock96, (720, 60), mock96)
lg48 = full.resize((48, 48), Image.LANCZOS)
prev.paste(lg48, (860, 60), lg48)
write(os.path.join(BRAND, 'preview.png'), prev)
print('DONE: launcher icons generated from the official brand SVG')

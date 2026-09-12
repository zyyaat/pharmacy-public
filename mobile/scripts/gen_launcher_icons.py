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
              f'{BARS}</svg>')
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

# ── 4) ic_launcher_foreground.png — الأعمدة بنسبة الويب داخل المساحة الظاهرة ─
# قاعدة أندرويد: كانفاس الطبقة 108dp لكن اللانشر يقتص المركز 72dp فقط ويكبّره
# (عامل 108/72 = 1.5×) ليملأ قناع الأيقونة. لذا نحسب الحجم على المساحة الظاهرة
# 72dp لا على الكانفاس كله: نريد الأعمدة بنفس نسبها في اللوجو المعتمد
# (54/128 عرضًا و58/128 ارتفاعًا) من المساحة الظاهرة — تطابق 1:1 مع أيقونة الويب.
VIEWPORT = 72.0 / 108.0  # نسبة المساحة الظاهرة من كانفاس الطبقة
TARGET_W = 54.0 / 128.0 * VIEWPORT  # 0.28125 من الكانفاس
TARGET_H = 58.0 / 128.0 * VIEWPORT  # 0.30208 من الكانفاس
for folder, size in FOREGROUND_SIZES.items():
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    box = (round(TARGET_W * size), round(TARGET_H * size))
    contained = ImageOps.contain(bars, box, Image.LANCZOS)
    off = ((size - contained.size[0]) // 2, (size - contained.size[1]) // 2)
    canvas.paste(contained, off, contained)
    write(os.path.join(BRAND, folder, 'ic_launcher_foreground.png'), canvas)

# تحقق رقمي صارم: نسب الأعمدة من المساحة الظاهرة يجب أن تطابق الويب (±1%).
chk = Image.open(os.path.join(BRAND, 'mipmap-xxxhdpi', 'ic_launcher_foreground.png'))
bb = chk.getbbox()
w_frac = (bb[2] - bb[0]) / chk.size[0] / VIEWPORT
h_frac = (bb[3] - bb[1]) / chk.size[1] / VIEWPORT
if abs(w_frac - 54 / 128) > 0.01 or abs(h_frac - 58 / 128) > 0.01:
    raise SystemExit(
        f'FATAL: foreground proportions off — w={w_frac:.3f} h={h_frac:.3f} '
        f'(expected {54 / 128:.3f} / {58 / 128:.3f} of the visible viewport)')
print(f'OK: proportions match the web icon — w={w_frac * 100:.1f}% '
      f'h={h_frac * 100:.1f}% of the visible 72dp viewport')

# ── 5) أيقونة متجر Play ‏512×512 — مربع كامل بلا زوايا شفافة ──────────────
store_svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">'
             f'<rect width="128" height="128" fill="{GREEN}"/>'
             f'{BARS}</svg>')
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

# ── 7) معاينة واقعية: محاكاة قصّ اللانشر الحقيقي (72/108) بأقنعة دائرة وسكويرل ─
fg432 = Image.open(os.path.join(BRAND, 'mipmap-xxxhdpi', 'ic_launcher_foreground.png'))
VP = 288  # المساحة الظاهرة 72dp بدقة xxxhdpi (432px = 108dp)
VX = (432 - VP) // 2


def launcher_mock(shape: str, out: int = 192) -> Image.Image:
    """يحاكي ما يعرضه اللانشر فعلًا: قصّ مركز 72/108 ثم قناع الدائرة/السكويرل."""
    crop = fg432.crop((VX, VX, VX + VP, VX + VP))
    bgim = Image.new('RGBA', (VP, VP), (0, 208, 132, 255))
    bgim.paste(crop, (0, 0), crop)
    mask = Image.new('L', (VP, VP), 0)
    dm = ImageDraw.Draw(mask)
    if shape == 'circle':
        dm.ellipse((0, 0, VP - 1, VP - 1), fill=255)
    else:  # squircle — قناع One UI/سامسونغ التقريبي
        dm.rounded_rectangle((0, 0, VP - 1, VP - 1), radius=int(0.28 * VP), fill=255)
    bgim.putalpha(mask)
    return bgim.resize((out, out), Image.LANCZOS)


prev = Image.new('RGBA', (1120, 340), (250, 250, 250, 255))
d = ImageDraw.Draw(prev)
d.text((30, 16), 'web icon (reference)  /  launcher circle  /  launcher squircle (One UI)  /  adaptive 96  /  legacy 48',
       fill=(20, 20, 20, 255))
prev.paste(full.resize((192, 192), Image.LANCZOS), (30, 60), full.resize((192, 192), Image.LANCZOS))
m_c = launcher_mock('circle')
prev.paste(m_c, (280, 60), m_c)
m_s = launcher_mock('squircle')
prev.paste(m_s, (530, 60), m_s)
fg96 = Image.open(os.path.join(BRAND, 'mipmap-xhdpi', 'ic_launcher_foreground.png'))
c96 = fg96.crop(((216 - 144) // 2, (216 - 144) // 2, (216 + 144) // 2, (216 + 144) // 2))
mock96 = Image.new('RGBA', (144, 144), (0, 208, 132, 255))
mock96.paste(c96, (0, 0), c96)
mask96 = Image.new('L', (144, 144), 0)
ImageDraw.Draw(mask96).rounded_rectangle((0, 0, 143, 143), radius=40, fill=255)
mock96.putalpha(mask96)
mock96 = mock96.resize((96, 96), Image.LANCZOS)
prev.paste(mock96, (780, 60), mock96)
lg48 = full.resize((48, 48), Image.LANCZOS)
prev.paste(lg48, (950, 60), lg48)
write(os.path.join(BRAND, 'preview.png'), prev)
print('DONE: launcher icons generated from the official brand SVG')

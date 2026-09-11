#!/usr/bin/env python3
"""Task 61 — يولّد mobile/lib/core/i18n_data.dart من ملفات i18n بتطبيق الويب
حرفيًا (نفس المفاتيح ونفس النصوص) حتى تتطابق لغة الموبايل مع الويب بالظبط."""
import json
import glob
import os

ROOT = "/home/z/my-project/pharmacy-public"
SRC = os.path.join(ROOT, "frontend/apps/pharmacy-app/src/i18n/messages")
OUT = os.path.join(ROOT, "mobile/lib/core/i18n_data.dart")


def esc(s: str) -> str:
    return (
        s.replace("\\", "\\\\")
        .replace("'", "\\'")
        .replace("$", "\\$")
        .replace("\n", "\\n")
        .replace("\r", "")
    )


# أفعال واجهة عامة يحتاجها الموبايل في مكوّنات مشتركة (تأكيد/ترقيم صفحات)
# نصوصها مأخوذة حرفيًا من ملفات الويب نفسها (customers.cancel، sales.back …)
MOBILE_EXTRA = {
    "ar": {"common": {
        "retry": "إعادة المحاولة", "previous": "السابق", "next": "التالي",
        "page_of": "إجمالي {total}", "cancel": "إلغاء", "confirm": "تأكيد",
        "save": "حفظ", "delete": "حذف", "edit": "تعديل", "add": "إضافة",
        "close": "إغلاق", "apply": "تطبيق", "search": "بحث", "done": "تم",
        "back": "رجوع", "view_all": "عرض الكل", "copy": "نسخ",
    }},
    "en": {"common": {
        "retry": "Retry", "previous": "Previous", "next": "Next",
        "page_of": "Total {total}", "cancel": "Cancel", "confirm": "Confirm",
        "save": "Save", "delete": "Delete", "edit": "Edit", "add": "Add",
        "close": "Close", "apply": "Apply", "search": "Search", "done": "Done",
        "back": "Back", "view_all": "View all", "copy": "Copy",
    }},
}


def merge(lang: str):
    """ nests: ns -> key -> text (مطابق لبنية Messages في الويب) """
    nested = {}
    for path in sorted(glob.glob(os.path.join(SRC, lang, "*.json"))):
        ns = os.path.splitext(os.path.basename(path))[0]
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        nested[ns] = {k: v for k, v in data.items() if isinstance(v, str)}
    for ns, kv in MOBILE_EXTRA.get(lang, {}).items():
        nested.setdefault(ns, {})
        for k, v in kv.items():
            nested[ns].setdefault(k, v)  # مفاتيح الويب لها الأولوية دائمًا
    return nested


def emit(buf, name, nested):
    buf.append(f"const Map<String, Map<String, String>> {name} = <String, Map<String, String>>{{")
    for ns in sorted(nested):
        buf.append(f"  '{esc(ns)}': <String, String>{{")
        for k in sorted(nested[ns]):
            buf.append(f"    '{esc(k)}': '{esc(nested[ns][k])}',")
        buf.append("  },")
    buf.append("};")


def main():
    ar = merge("ar")
    en = merge("en")
    buf = [
        "// GENERATED FILE — لا تعدّله يدويًا. ولّده scripts/mobile_i18n_generate.py",
        "// من frontend/apps/pharmacy-app/src/i18n/messages/{ar,en}/*.json حرفيًا",
        "// (Task 61: تطابق لغة الموبايل مع الويب بالظبط — نفس النطاقات والمفاتيح).",
        "",
    ]
    emit(buf, "kI18nAr", ar)
    buf.append("")
    emit(buf, "kI18nEn", en)
    buf.append("")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(buf))
    total = sum(len(v) for v in ar.values())
    print(f"ar: {len(ar)} namespaces / {total} keys -> {OUT}")


if __name__ == "__main__":
    main()


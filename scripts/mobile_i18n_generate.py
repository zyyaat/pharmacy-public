#!/usr/bin/env python3
"""Task 61 — يولّد mobile/lib/core/i18n_data.dart من ملفات i18n بتطبيق الويب
حرفيًا (نفس المفاتيح ونفس النصوص) حتى تتطابق لغة الموبايل مع الويب بالظبط.

Task 81 — نظام اللغات الثماني كالويب: يولّد kI18nAll لكل لغات locales في
i18n/config.ts (ar/en/fr/es/tr/zh/hi/ur) من نفس مصدر الحقيقة (web messages/).
اللغات الجزئية (auth ناقصًا مثلًا) يعوّضها رجوع AppI18n إلى العربية وقت
التشغيل — نفس دلالة deepMerge(catalogs.ar, catalogs[locale]) في messages/index.ts.
"""
import json
import glob
import os

ROOT = "/home/z/my-project/pharmacy-public"
SRC = os.path.join(ROOT, "frontend/apps/pharmacy-app/src/i18n/messages")
OUT = os.path.join(ROOT, "mobile/lib/core/i18n_data.dart")

# نفس ترتيب locales في frontend/apps/pharmacy-app/src/i18n/config.ts
LOCALES = ["ar", "en", "fr", "es", "tr", "zh", "hi", "ur"]


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
# Task 81: ترجمات نفس المفاتيح للغات الست الجديدة.
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
    "fr": {"common": {
        "retry": "Réessayer", "previous": "Précédent", "next": "Suivant",
        "page_of": "Total {total}", "cancel": "Annuler", "confirm": "Confirmer",
        "save": "Enregistrer", "delete": "Supprimer", "edit": "Modifier", "add": "Ajouter",
        "close": "Fermer", "apply": "Appliquer", "search": "Rechercher", "done": "Terminé",
        "back": "Retour", "view_all": "Tout afficher", "copy": "Copier",
    }},
    "es": {"common": {
        "retry": "Reintentar", "previous": "Anterior", "next": "Siguiente",
        "page_of": "Total {total}", "cancel": "Cancelar", "confirm": "Confirmar",
        "save": "Guardar", "delete": "Eliminar", "edit": "Editar", "add": "Añadir",
        "close": "Cerrar", "apply": "Aplicar", "search": "Buscar", "done": "Hecho",
        "back": "Volver", "view_all": "Ver todo", "copy": "Copiar",
    }},
    "tr": {"common": {
        "retry": "Tekrar dene", "previous": "Önceki", "next": "Sonraki",
        "page_of": "Toplam {total}", "cancel": "İptal", "confirm": "Onayla",
        "save": "Kaydet", "delete": "Sil", "edit": "Düzenle", "add": "Ekle",
        "close": "Kapat", "apply": "Uygula", "search": "Ara", "done": "Tamam",
        "back": "Geri", "view_all": "Tümünü gör", "copy": "Kopyala",
    }},
    "zh": {"common": {
        "retry": "重试", "previous": "上一页", "next": "下一页",
        "page_of": "共 {total} 条", "cancel": "取消", "confirm": "确认",
        "save": "保存", "delete": "删除", "edit": "编辑", "add": "添加",
        "close": "关闭", "apply": "应用", "search": "搜索", "done": "完成",
        "back": "返回", "view_all": "查看全部", "copy": "复制",
    }},
    "hi": {"common": {
        "retry": "पुनः प्रयास", "previous": "पिछला", "next": "अगला",
        "page_of": "कुल {total}", "cancel": "रद्द करें", "confirm": "पुष्टि करें",
        "save": "सहेजें", "delete": "हटाएँ", "edit": "संपादित करें", "add": "जोड़ें",
        "close": "बंद करें", "apply": "लागू करें", "search": "खोजें", "done": "पूर्ण",
        "back": "वापस", "view_all": "सभी देखें", "copy": "कॉपी करें",
    }},
    "ur": {"common": {
        "retry": "دوبارہ کوشش کریں", "previous": "پچھلا", "next": "اگلا",
        "page_of": "کل {total}", "cancel": "منسوخ کریں", "confirm": "تصدیق کریں",
        "save": "محفوظ کریں", "delete": "حذف کریں", "edit": "ترتیب دیں", "add": "شامل کریں",
        "close": "بند کریں", "apply": "لاگو کریں", "search": "تلاش کریں", "done": "مکمل",
        "back": "واپس", "view_all": "سب دیکھیں", "copy": "کاپی کریں",
    }},
}



# Task 90-restore — مفاتيح للموبايل فقط (لا وجود لها على الويب): بيع POS
# الأوفلاين وشارة الاتصال + مفاتيح تصدير التقارير. كانت في نسخة قديمة من
# هذا المولّد وسقطت من الملف المولّد عند إعادة توليد لاحقة — أعيدت هنا
# ليطابق المولّد الملف الملتزم به (اللغات الجزئية تأخذ نص العربية وقت
# التشغيل).
MOBILE_OFFLINE_ONLY = {
  "ar": {
    "errors": {
      "offline_sale_needed": "البيع يحتاج اتصالًا بالإنترنت — سلتك محفوظة كما هي، وأعد المحاولة عند عودة الاتصال."
    },
    "common": {
      "offline_chip": "غير متصل"
    },
    "reports": {
      "export_pdf": "تصدير PDF",
      "export_preparing": "جارٍ تحضير ملف PDF…",
      "export_failed": "تعذّر إنشاء ملف PDF — أعد المحاولة",
      "export_empty": "لا توجد بيانات لتصديرها بعد"
    }
  },
  "en": {
    "errors": {
      "offline_sale_needed": "Selling needs an internet connection — your cart is saved as is. Try again once you are back online."
    },
    "common": {
      "offline_chip": "Offline"
    },
    "reports": {
      "export_pdf": "Export PDF",
      "export_preparing": "Preparing the PDF file…",
      "export_failed": "Could not create the PDF file — try again",
      "export_empty": "Nothing to export yet"
    }
  },
  "fr": {
    "errors": {
      "offline_sale_needed": "La vente nécessite une connexion Internet — votre panier est conservé. Réessayez une fois la connexion rétablie."
    },
    "common": {
      "offline_chip": "غير متصل"
    },
    "reports": {
      "export_pdf": "Exporter en PDF",
      "export_preparing": "Préparation du fichier PDF…",
      "export_failed": "Impossible de créer le fichier PDF — réessayez",
      "export_empty": "Rien à exporter pour le moment"
    }
  },
  "es": {
    "errors": {
      "offline_sale_needed": "La venta necesita conexión a Internet: tu carrito se conserva tal cual. Inténtalo de nuevo cuando vuelvas a estar en línea."
    },
    "common": {
      "offline_chip": "غير متصل"
    },
    "reports": {
      "export_pdf": "Exportar PDF",
      "export_preparing": "Preparando el archivo PDF…",
      "export_failed": "No se pudo crear el archivo PDF: inténtalo de nuevo",
      "export_empty": "Todavía no hay nada que exportar"
    }
  },
  "tr": {
    "errors": {
      "offline_sale_needed": "Satış internet bağlantısı gerektiriyor — sepetiniz olduğu gibi korundu. Bağlantı geri geldiğinde tekrar deneyin."
    },
    "common": {
      "offline_chip": "غير متصل"
    },
    "reports": {
      "export_pdf": "PDF dışa aktar",
      "export_preparing": "PDF dosyası hazırlanıyor…",
      "export_failed": "PDF dosyası oluşturulamadı — tekrar deneyin",
      "export_empty": "Henüz dışa aktarılacak bir şey yok"
    }
  },
  "zh": {
    "errors": {
      "offline_sale_needed": "销售需要互联网连接——购物车已原样保留，恢复连接后请重试。"
    },
    "common": {
      "offline_chip": "غير متصل"
    },
    "reports": {
      "export_pdf": "导出 PDF",
      "export_preparing": "正在准备 PDF 文件…",
      "export_failed": "无法创建 PDF 文件——请重试",
      "export_empty": "暂无可导出的数据"
    }
  },
  "hi": {
    "errors": {
      "offline_sale_needed": "बिक्री के लिए इंटरनेट कनेक्शन ज़रूरी है — आपकी कार्ट वैसी की वैसी सुरक्षित है। कनेक्शन लौटने पर दोबारा प्रयास करें।"
    },
    "common": {
      "offline_chip": "غير متصل"
    },
    "reports": {
      "export_pdf": "PDF निर्यात करें",
      "export_preparing": "PDF फ़ाइल तैयार हो रही है…",
      "export_failed": "PDF फ़ाइल नहीं बन सकी — दोबारा प्रयास करें",
      "export_empty": "निर्यात करने के लिए अभी कुछ नहीं"
    }
  },
  "ur": {
    "errors": {
      "offline_sale_needed": "فروخت کے لیے انٹرنیٹ کنکشن ضروری ہے — آپ کی کارٹ ویسے کی ویسے محفوظ ہے۔ کنکشن واپس آنے پر دوبارہ کوشش کریں۔"
    },
    "common": {
      "offline_chip": "غير متصل"
    },
    "reports": {
      "export_pdf": "PDF برآمد کریں",
      "export_preparing": "PDF فائل تیار ہو رہی ہے…",
      "export_failed": "PDF فائل نہیں بن سکی — دوبارہ کوشش کریں",
      "export_empty": "برآمد کرنے کے لیے ابھی کچھ نہیں"
    }
  }
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
    for ns, kv in MOBILE_OFFLINE_ONLY.get(lang, {}).items():
        nested.setdefault(ns, {})
        for k, v in kv.items():
            nested[ns].setdefault(k, v)
    return nested


def emit(buf, name, nested):
    buf.append(f"const Map<String, Map<String, String>> {name} = <String, Map<String, String>>{{")
    for ns in sorted(nested):
        buf.append(f"  '{esc(ns)}': <String, String>{{")
        for k in sorted(nested[ns]):
            buf.append(f"    '{esc(k)}': '{esc(nested[ns][k])}',")
        buf.append("  },")
    buf.append("};")


def emit_all(buf, merged_by_locale):
    buf.append("const Map<String, Map<String, Map<String, String>>> kI18nAll = <String, Map<String, Map<String, String>>>{")
    for lang in LOCALES:
        nested = merged_by_locale[lang]
        buf.append(f"  '{esc(lang)}': <String, Map<String, String>>{{")
        for ns in sorted(nested):
            buf.append(f"    '{esc(ns)}': <String, String>{{")
            for k in sorted(nested[ns]):
                buf.append(f"      '{esc(k)}': '{esc(nested[ns][k])}',")
            buf.append("    },")
        buf.append("  },")
    buf.append("};")


def main():
    merged = {lang: merge(lang) for lang in LOCALES}
    buf = [
        "// GENERATED FILE — لا تعدّله يدويًا. ولّده scripts/mobile_i18n_generate.py",
        "// من frontend/apps/pharmacy-app/src/i18n/messages/{ar,en,fr,es,tr,zh,hi,ur}/*.json",
        "// حرفيًا (Task 61: تطابق لغة الموبايل مع الويب — Task 81: اللغات الثماني كالويب",
        "// واللغات الجزئية يكملها رجوع AppI18n إلى العربية وقت التشغيل).",
        "",
    ]
    emit_all(buf, merged)
    buf.append("")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(buf))
    for lang in LOCALES:
        total = sum(len(v) for v in merged[lang].values())
        print(f"{lang}: {len(merged[lang])} namespaces / {total} keys")
    print(f"-> {OUT}")


if __name__ == "__main__":
    main()

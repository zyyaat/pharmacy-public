#!/usr/bin/env python3
"""تحديث i18n الموبايل (lib/core/i18n_data.dart) ×8:
- paymob_not_configured → payment_not_configured (نفس القيم المحايدة)
- checkout_secure_hint: تعصيب (إزالة اسم Paymob) + إضافة checkout_sdk_blocked
"""
import re

PATH = "/home/z/my-project/pharmacy-public/mobile/lib/core/i18n_data.dart"

# old hint fragment → new neutral hint, per language, matched by unique substring
HINTS = {
    "الدفع يتم داخل هذه الصفحة عبر بوابة Paymob — لا نرى بيانات بطاقتك ولا نحتفظ بها.":
        "الدفع يتم داخل هذه الصفحة عبر بوابة الدفع — لا نرى بيانات بطاقتك ولا نحتفظ بها.",
    "Payment happens on this page via the Paymob gateway — we never see or store your card data.":
        "Payment happens on this page via the payment gateway — we never see or store your card data.",
}
# fallback: any remaining "بوابة Paymob"/"Paymob gateway" wording inside checkout_secure_hint rows
SDK_BLOCKED = {
    # keyed by the paymob_not_configured value of the same locale block
    "الدفع الإلكتروني غير مفعّل حالياً — تواصل مع الدعم لتأكيد الاشتراك":
        "تعذّر تحميل نافذة الدفع — تحقق من الاتصال أو عطّل حاجب الإعلانات ثم أعد المحاولة",
    "Online payment is not enabled yet — contact support to confirm your subscription":
        "Could not load the payment window — check your connection or disable ad blockers, then retry",
    "Le paiement en ligne n'est pas encore activé — contactez le support":
        "Impossible de charger la fenêtre de paiement — vérifiez votre connexion puis réessayez",
    "El pago en línea aún no está habilitado — contacta con soporte":
        "No se pudo cargar la ventana de pago — verifica tu conexión y reintenta",
    "Çevrimiçi ödeme henüz etkin değil — aboneliğinizi onaylamak için desteğe ulaşın":
        "Ödeme penceresi yüklenemedi — bağlantınızı kontrol edip tekrar deneyin",
    "在线支付尚未启用——请联系客服确认订阅":
        "无法加载付款窗口——请检查网络连接后重试",
    "ऑनलाइन भुगतान अभी सक्रिय नहीं है — सदस्यता की पुष्टि के लिए सहायता से संपर्क करें":
        "भुगतान विंडो लोड नहीं हो सकी — कनेक्शन जांचें और पुनः प्रयास करें",
    "آن لائن ادائگی ابھی فعال نہیں — سبسکرپشن کی تصدیق کے لیے سپورٹ سے رابطہ کریں":
        "ادائگی کی ونڈو لوڈ نہیں ہو سکی — کنکشن چیک کر کے دوبارہ کوشش کریں",
}

with open(PATH, encoding="utf-8") as f:
    src = f.read()

count_rename = 0
for old, new in HINTS.items():
    src = src.replace(old, new)

# أي صياغة متبقية باسم Paymob داخل checkout_secure_hint (لغات أخرى)
src = src.replace("عبر بوابة Paymob", "عبر بوابة الدفع")
src = src.replace("via the Paymob gateway", "via the payment gateway")

# rename key ×8 — القيم تبقى كما هي (محايدة أصلًا)
count_rename = src.count("'paymob_not_configured'")
src = src.replace("'paymob_not_configured'", "'payment_not_configured'")

# إضافة checkout_sdk_blocked بعد كل payment_not_configured
added = 0
lines = src.split("\n")
out = []
for line in lines:
    out.append(line)
    m = re.match(r"^(\s*)'payment_not_configured':\s*'(.*)',\s*$", line)
    if m:
        indent, val = m.group(1), m.group(2)
        sdk = SDK_BLOCKED.get(val)
        if sdk is None:
            # اللغات غير المغطاة: قيمة إنجليزية محايدة
            sdk = "Could not load the payment window — check your connection, then retry"
        esc = sdk.replace("\\", "\\\\").replace("'", "\\'")
        out.append(f"{indent}'checkout_sdk_blocked': '{esc}',")
        added += 1

src = "\n".join(out)
with open(PATH, "w", encoding="utf-8") as f:
    f.write(src)
print(f"renamed keys: {count_rename}, sdk_blocked added: {added}")
# بقايا Paymob في ملف i18n؟
for i, line in enumerate(src.split("\n"), 1):
    if "paymob" in line.lower() and "payment_not" not in line:
        print("REMAINING:", i, line.strip()[:120])

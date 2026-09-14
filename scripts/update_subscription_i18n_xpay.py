#!/usr/bin/env python3
"""تحديث i18n اشتراك pharmacy-app ×8 — تعصيب رسائل البوابة + مفتاحا
payment_not_configured و checkout_sdk_blocked الجديدان (المصدر: العربية).
en/fr/es مترجمة، tr/zh/hi/ur مشتقة بالنمط المعتمد في المستودع."""
import json
import os

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "frontend/apps/pharmacy-app/src/i18n/messages")

# (ملف، checkout_secure_hint، payment_not_configured، checkout_sdk_blocked)
LOCALES = {
    "ar": (
        "الدفع يتم داخل هذه الصفحة عبر بوابة الدفع — لا نرى بيانات بطاقتك ولا نحتفظ بها.",
        "الدفع الإلكتروني غير مفعّل حالياً — تواصل مع الدعم لتأكيد الاشتراك",
        "تعذّر تحميل نافذة الدفع — تحقق من الاتصال أو عطّل حاجب الإعلانات ثم أعد المحاولة",
    ),
    "en": (
        "Payment happens on this page via the payment gateway — we never see or store your card data.",
        "Online payment is not enabled yet — contact support to confirm your subscription",
        "Could not load the payment window — check your connection or disable ad blockers, then retry",
    ),
    "fr": (
        "Le paiement se fait sur cette page via la passerelle de paiement — nous ne voyons jamais vos données de carte.",
        "Le paiement en ligne n'est pas encore activé — contactez le support pour confirmer votre abonnement",
        "Impossible de charger la fenêtre de paiement — vérifiez votre connexion ou désactivez les bloqueurs de publicité, puis réessayez",
    ),
    "es": (
        "El pago se realiza en esta página a través de la pasarela de pago — nunca vemos ni almacenamos los datos de tu tarjeta.",
        "El pago en línea aún no está activado — contacta al soporte para confirmar tu suscripción",
        "No se pudo cargar la ventana de pago — verifica tu conexión o desactiva los bloqueadores de anuncios y reintenta",
    ),
    "tr": (
        "Ödeme bu sayfada ödeme geçidi üzerinden yapılır — kart verilerinizi asla görmeyiz veya saklamayız.",
        "Çevrimiçi ödeme henüz etkin değil — aboneliğinizi onaylamak için destekle iletişime geçin",
        "Ödeme penceresi yüklenemedi — bağlantınızı kontrol edin veya reklam engelleyicileri kapatıp tekrar deneyin",
    ),
    "zh": (
        "付款将通过支付网关在此页面完成——我们绝不查看或存储您的银行卡数据。",
        "在线付款尚未启用——请联系客服确认您的订阅",
        "无法加载付款窗口——请检查网络连接或禁用广告拦截器后重试",
    ),
    "hi": (
        "भुगतान इस पृष्ठ पर भुगतान गेटवे के माध्यम से होता है — हम आपका कार्ड डेटा कभी नहीं देखते या संग्रहीत करते।",
        "ऑनलाइन भुगतान अभी सक्षम नहीं है — अपनी सदस्यता की पुष्टि के लिए सहायता से संपर्क करें",
        "भुगतान विंडो लोड नहीं हो सकी — अपना कनेक्शन जांचें या विज्ञापन ब्लॉकर अक्षम करें और पुनः प्रयास करें",
    ),
    "ur": (
        "ادائگی اسی صفحے پر ادائگی گیٹ وے کے ذریعے ہوتی ہے — ہم آپ کا کارڈ ڈیٹا کبھی نہیں دیکھتے یا محفوظ نہیں کرتے۔",
        "آن لائن ادائگی ابھی فعال نہیں — اپنی سبسکرپشن کی تصدیق کے لیے سپورٹ سے رابطہ کریں",
        "ادائگی کی ونڈو لوڈ نہیں ہو سکی — اپنا کنکشن چیک کریں یا اشتہار بلاکرز بند کر کے دوبارہ کوشش کریں",
    ),
}

for loc, (hint, not_cfg, sdk_blocked) in LOCALES.items():
    path = os.path.join(BASE, loc, "subscription.json")
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    if "checkout_secure_hint" not in d or "paymob_not_configured" not in d:
        print(f"SKIP {loc}: expected keys missing")
        continue
    d["checkout_secure_hint"] = hint
    # rename paymob_not_configured → payment_not_configured (ترتيب محفوظ)
    items = []
    for k, v in d.items():
        if k == "paymob_not_configured":
            items.append(("payment_not_configured", not_cfg))
        elif k == "checkout_secure_hint":
            items.append((k, hint))
        else:
            items.append((k, v))
    # إدراج checkout_sdk_blocked بعد payment_not_configured مباشرة
    ordered = []
    for k, v in items:
        ordered.append((k, v))
        if k == "payment_not_configured":
            ordered.append(("checkout_sdk_blocked", sdk_blocked))
    with open(path, "w", encoding="utf-8") as f:
        json.dump(dict(ordered), f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"OK {loc}: keys={len(ordered)}")

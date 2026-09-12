#!/usr/bin/env python3
"""Task 90 — pharmacy-app i18n: subscription.json namespace.
ar/en real translations; the other 6 locales get {} and fall back to
Arabic per the Task 48 per-key fallback policy. Also adds the settings
section key."""
import json, os

BASE = "frontend/apps/pharmacy-app/src/i18n/messages"
LOCALES = ["ar", "en", "fr", "es", "tr", "zh", "hi", "ur"]

subscription = {
 "ar": {
  "title": "الاشتراك والخطط",
  "subtitle": "خطتك الحالية، استهلاكك، والخطط المتاحة للترقية",
  "status_trial": "فترة تجريبية",
  "status_active": "اشتراك نشط",
  "status_expired": "اشتراك منتهي",
  "status_cancelled": "ملغى",
  "status_suspended": "معلّق",
  "status_pending": "بانتظار تأكيد الدفع",
  "days_left": "متبقٍ {days} يومًا",
  "days_left_last": "يوم واحد متبقٍ — اشترك الآن",
  "plan_label": "الخطة الحالية",
  "renews_on": "تنتهي الفترة في {date}",
  "trial_ends": "تنتهي التجربة في {date}",
  "usage_title": "الاستهلاك",
  "limit_branches": "الفروع",
  "limit_users": "مستخدمو اللوحة",
  "limit_employees": "الموظفون",
  "limit_products": "المنتجات",
  "unlimited": "غير محدود",
  "plans_title": "الخطط المتاحة",
  "plans_subtitle": "اختر الخطة المناسبة — الترقية تُفعّل فور تأكيد الدفع",
  "current_plan": "خطتك الحالية",
  "per_month": "/شهريًا",
  "per_year": "/سنويًا",
  "subscribe_cta": "اشترك الآن",
  "subscribe_hint": "تواصل معنا لتأكيد الدفع وسيُفعَّل اشتراكك فورًا — بياناتك كلها محفوظة وسليمة.",
  "contact_owner": "لتفعيل الاشتراك: حوّل قيمة الخطة ثم أبلغ الدعم برقم التحويل.",
  "blocked_banner": "انتهت فترة التجربة — اختر خطة لاستعادة الوصول. بياناتك محفوظة بالكامل.",
  "suspended_banner": "تم تعليق الاشتراك — راجع صفحة الاشتراك أو تواصل مع الدعم.",
  "trial_banner": "تجربتك تنتهي خلال {days} يوم — اشترك لضمان استمرار العمل",
  "trial_banner_last": "آخر يوم من التجربة — اشترك الآن لعدم انقطاع الخدمة",
  "limit_reached": "وصلت للحد الأقصى في خطتك ({limit}) — رقِّ خطتك للاستمرار",
  "load_failed": "تعذر تحميل بيانات الاشتراك",
  "features_included": "الميزات",
  "month": "شهر", "year": "سنة"
 },
 "en": {
  "title": "Subscription & Plans",
  "subtitle": "Your current plan, usage, and available upgrades",
  "status_trial": "Trial",
  "status_active": "Active",
  "status_expired": "Expired",
  "status_cancelled": "Cancelled",
  "status_suspended": "Suspended",
  "status_pending": "Awaiting payment",
  "days_left": "{days} days left",
  "days_left_last": "Last day — subscribe now",
  "plan_label": "Current plan",
  "renews_on": "Period ends {date}",
  "trial_ends": "Trial ends {date}",
  "usage_title": "Usage",
  "limit_branches": "Branches",
  "limit_users": "Dashboard users",
  "limit_employees": "Employees",
  "limit_products": "Products",
  "unlimited": "Unlimited",
  "plans_title": "Available plans",
  "plans_subtitle": "Pick the right plan — upgrades activate once payment confirms",
  "current_plan": "Your plan",
  "per_month": "/month",
  "per_year": "/year",
  "subscribe_cta": "Subscribe now",
  "subscribe_hint": "Contact us to confirm payment and your subscription activates immediately — all your data stays safe.",
  "contact_owner": "To subscribe: transfer the plan amount and share the transfer reference with support.",
  "blocked_banner": "Your trial ended — pick a plan to restore access. All your data is safe.",
  "suspended_banner": "Subscription suspended — check the subscription page or contact support.",
  "trial_banner": "Your trial ends in {days} days — subscribe to keep working",
  "trial_banner_last": "Last trial day — subscribe now to avoid interruption",
  "limit_reached": "You reached your plan's limit for {limit} — upgrade to continue",
  "load_failed": "Failed to load subscription",
  "features_included": "Features",
  "month": "month", "year": "year"
 }
}

# settings.json section label
settings_section = {
 "ar": {"subscription": "الاشتراك والخطط"},
 "en": {"subscription": "Subscription & Plans"},
}

for loc in LOCALES:
    d = os.path.join(BASE, loc)
    data = subscription.get(loc, {})
    with open(os.path.join(d, "subscription.json"), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    # settings section key
    spath = os.path.join(d, "settings.json")
    settings = json.load(open(spath, encoding="utf-8"))
    sections = settings.get("sections", {})
    if "subscription" in settings_section.get(loc, {}):
        sections["subscription"] = settings_section[loc]["subscription"]
    elif "subscription" not in sections:
        sections["subscription"] = settings_section["en"]["subscription"]
    settings["sections"] = sections
    json.dump(settings, open(spath, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

# register namespace in index.ts
idx_path = os.path.join(BASE, "index.ts")
idx = open(idx_path, encoding="utf-8").read()
for loc in LOCALES:
    imp = f"import {loc}Settings from './{loc}/settings.json'\n"
    if imp in idx:
        idx = idx.replace(imp, imp + f"import {loc}Subscription from './{loc}/subscription.json'\n")
    cat = f"    settings: {loc}Settings,\n  }}"
    if cat in idx:
        idx = idx.replace(cat, f"    settings: {loc}Settings,\n    subscription: {loc}Subscription,\n  }}")
open(idx_path, "w", encoding="utf-8").write(idx)
print("pharmacy-app i18n done")

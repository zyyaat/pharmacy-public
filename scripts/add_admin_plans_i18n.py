#!/usr/bin/env python3
"""Task 90 — admin-dashboard i18n: plans.json + subscriptions.json ×8 locales
+ nav keys (plans/subscriptions) + index.ts registration."""
import json, os, re

BASE = "frontend/apps/admin-dashboard/src/i18n/messages"
LOCALES = ["ar", "en", "fr", "es", "tr", "zh", "hi", "ur"]

plans = {
 "ar": {
  "title": "الخطط", "subtitle": "إدارة خطط الاشتراك المتاحة للشركات — بالكامل من هنا دون كود",
  "new_plan": "خطة جديدة", "edit_plan": "تعديل الخطة", "create_plan": "إنشاء الخطة",
  "col_plan": "الخطة", "col_price_monthly": "شهري", "col_price_yearly": "سنوي",
  "col_status": "الحالة", "col_subscribers": "المشتركون", "col_actions": "إجراءات",
  "active": "مفعلة", "inactive": "معطلة",
  "form_name": "الاسم (إنجليزي)", "form_name_ar": "الاسم (عربي)", "form_slug": "المعرّف (slug)",
  "form_description": "الوصف", "form_price_monthly": "السعر الشهري (ج.م)", "form_price_yearly": "السعر السنوي (ج.م)",
  "form_features": "الميزات", "form_permissions": "الصلاحيات", "form_limits": "الحدود",
  "form_is_active": "مفعلة للاشتراك الجديد", "form_is_public": "ظاهرة في صفحة الأسعار", "form_sort": "الترتيب",
  "limit_key": "المفتاح", "limit_value": "القيمة (-1 = غير محدود)", "add_limit": "إضافة حد",
  "remove": "إزالة", "select_all_module": "تحديد الوحدة", "clear_module": "مسح الوحدة",
  "suggested_hint": "تفعيل الميزة يحدد صلاحياتها المقترحة تلقائيًا — عدّلها يدويًا عند الحاجة",
  "save": "حفظ", "cancel": "إلغاء", "delete": "حذف", "activate": "تفعيل", "deactivate": "تعطيل",
  "delete_confirm": "حذف الخطة؟ يُرفض الحذف إن كان عليها مشتركون حيّون.",
  "load_failed": "تعذر تحميل الخطط", "saved": "تم الحفظ", "failed": "فشلت العملية",
  "slug_taken": "المعرّف مستخدم بالفعل", "plan_has_subscribers": "لا يمكن حذف خطة عليها مشتركون حيّون — عطّلها بدلًا من حذفها",
  "unlimited": "غير محدود", "no_plans": "لا خطط بعد — أنشئ أول خطة",
  "limit_branches": "الفروع", "limit_users": "مستخدمو اللوحة", "limit_employees": "الموظفون", "limit_products": "المنتجات"
 },
 "en": {
  "title": "Plans", "subtitle": "Manage subscription plans available to companies — fully from here, no code",
  "new_plan": "New plan", "edit_plan": "Edit plan", "create_plan": "Create plan",
  "col_plan": "Plan", "col_price_monthly": "Monthly", "col_price_yearly": "Yearly",
  "col_status": "Status", "col_subscribers": "Subscribers", "col_actions": "Actions",
  "active": "Active", "inactive": "Inactive",
  "form_name": "Name (English)", "form_name_ar": "Name (Arabic)", "form_slug": "Slug",
  "form_description": "Description", "form_price_monthly": "Monthly price (EGP)", "form_price_yearly": "Yearly price (EGP)",
  "form_features": "Features", "form_permissions": "Permissions", "form_limits": "Limits",
  "form_is_active": "Open for new subscriptions", "form_is_public": "Visible on pricing page", "form_sort": "Sort order",
  "limit_key": "Key", "limit_value": "Value (-1 = unlimited)", "add_limit": "Add limit",
  "remove": "Remove", "select_all_module": "Select module", "clear_module": "Clear module",
  "suggested_hint": "Toggling a feature auto-selects its suggested permissions — adjust manually if needed",
  "save": "Save", "cancel": "Cancel", "delete": "Delete", "activate": "Activate", "deactivate": "Deactivate",
  "delete_confirm": "Delete this plan? Deletion is rejected while live subscribers exist.",
  "load_failed": "Failed to load plans", "saved": "Saved", "failed": "Operation failed",
  "slug_taken": "Slug already taken", "plan_has_subscribers": "Cannot delete a plan with live subscribers — deactivate it instead",
  "unlimited": "Unlimited", "no_plans": "No plans yet — create the first one",
  "limit_branches": "Branches", "limit_users": "Dashboard users", "limit_employees": "Employees", "limit_products": "Products"
 }
}
plans["fr"] = dict(plans["en"]); plans["es"] = dict(plans["en"]); plans["tr"] = dict(plans["en"])
plans["zh"] = dict(plans["en"]); plans["hi"] = dict(plans["en"]); plans["ur"] = dict(plans["en"])

subscriptions = {
 "ar": {
  "title": "الاشتراكات", "subtitle": "متابعة وإدارة اشتراكات الشركات والدفعات اليدوية",
  "col_company": "الشركة", "col_plan": "الخطة", "col_status": "الحالة",
  "col_period_end": "نهاية الفترة", "col_source": "المصدر", "col_actions": "إجراءات",
  "status_trial": "تجريبي", "status_active": "نشط", "status_expired": "منتهي",
  "status_cancelled": "ملغى", "status_suspended": "معلّق", "status_pending": "بانتظار الدفع",
  "source_manual": "يدوي", "source_registration": "تسجيل", "source_payment": "دفع", "source_migration": "ترحيل",
  "filter_status_all": "كل الحالات", "search_placeholder": "بحث باسم الشركة...",
  "assign": "إسناد خطة", "assign_title": "إسناد خطة لشركة",
  "assign_company": "الشركة (ID)", "assign_plan": "الخطة", "assign_interval": "دورية الفوترة",
  "interval_none": "بدون", "interval_monthly": "شهري", "interval_yearly": "سنوي",
  "assign_trial_days": "أيام تجربة (0 = اشتراك مباشر)", "assign_period_end": "نهاية الفترة (اختياري)",
  "extend": "تمديد", "extend_title": "تمديد الفترة", "new_period_end": "تاريخ النهاية الجديد",
  "cancel_sub": "إلغاء", "suspend": "تعليق", "reactivate": "إعادة تفعيل",
  "manual_payment": "تسجيل دفع يدوي", "manual_payment_title": "تسجيل دفع يدوي",
  "amount_egp": "المبلغ (ج.م) — فارغ = سعر الخطة", "note": "ملاحظة (رقم التحويل مثلًا)",
  "no_period": "بلا نهاية", "load_failed": "تعذر تحميل الاشتراكات", "saved": "تم التنفيذ",
  "failed": "فشلت العملية", "confirm_cancel": "إلغاء الاشتراك فورًا؟ يفقد العميل الوصول إلا لصفحة الاشتراكات.",
  "confirm_suspend": "تعليق وصول الشركة بالكامل؟", "no_subscriptions": "لا اشتراكات مطابقة"
 },
 "en": {
  "title": "Subscriptions", "subtitle": "Monitor and manage company subscriptions and manual payments",
  "col_company": "Company", "col_plan": "Plan", "col_status": "Status",
  "col_period_end": "Period end", "col_source": "Source", "col_actions": "Actions",
  "status_trial": "Trial", "status_active": "Active", "status_expired": "Expired",
  "status_cancelled": "Cancelled", "status_suspended": "Suspended", "status_pending": "Pending",
  "source_manual": "Manual", "source_registration": "Registration", "source_payment": "Payment", "source_migration": "Migration",
  "filter_status_all": "All statuses", "search_placeholder": "Search by company name...",
  "assign": "Assign plan", "assign_title": "Assign a plan to a company",
  "assign_company": "Company (ID)", "assign_plan": "Plan", "assign_interval": "Billing interval",
  "interval_none": "None", "interval_monthly": "Monthly", "interval_yearly": "Yearly",
  "assign_trial_days": "Trial days (0 = direct subscription)", "assign_period_end": "Period end (optional)",
  "extend": "Extend", "extend_title": "Extend period", "new_period_end": "New end date",
  "cancel_sub": "Cancel", "suspend": "Suspend", "reactivate": "Reactivate",
  "manual_payment": "Manual payment", "manual_payment_title": "Register manual payment",
  "amount_egp": "Amount (EGP) — empty = plan price", "note": "Note (e.g. transfer reference)",
  "no_period": "No end", "load_failed": "Failed to load subscriptions", "saved": "Done",
  "failed": "Operation failed", "confirm_cancel": "Cancel immediately? The company loses access except the subscription page.",
  "confirm_suspend": "Suspend the company's access entirely?", "no_subscriptions": "No matching subscriptions"
 }
}
subscriptions["fr"] = dict(subscriptions["en"]); subscriptions["es"] = dict(subscriptions["en"])
subscriptions["tr"] = dict(subscriptions["en"]); subscriptions["zh"] = dict(subscriptions["en"])
subscriptions["hi"] = dict(subscriptions["en"]); subscriptions["ur"] = dict(subscriptions["en"])

nav_add = {
 "ar": {"plans": "الخطط", "subscriptions": "الاشتراكات"},
 "en": {"plans": "Plans", "subscriptions": "Subscriptions"},
 "fr": {"plans": "Formules", "subscriptions": "Abonnements"},
 "es": {"plans": "Planes", "subscriptions": "Suscripciones"},
 "tr": {"plans": "Planlar", "subscriptions": "Abonelikler"},
 "zh": {"plans": "套餐", "subscriptions": "订阅"},
 "hi": {"plans": "प्लान", "subscriptions": "सदस्यताएँ"},
 "ur": {"plans": "پلانز", "subscriptions": "سبسکرپشنز"},
}

for loc in LOCALES:
    d = os.path.join(BASE, loc)
    with open(os.path.join(d, "plans.json"), "w", encoding="utf-8") as f:
        json.dump(plans[loc], f, ensure_ascii=False, indent=2)
    with open(os.path.join(d, "subscriptions.json"), "w", encoding="utf-8") as f:
        json.dump(subscriptions[loc], f, ensure_ascii=False, indent=2)
    nav_path = os.path.join(d, "nav.json")
    nav = json.load(open(nav_path, encoding="utf-8"))
    nav.update(nav_add[loc])
    json.dump(nav, open(nav_path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

# register namespaces in index.ts (imports + catalog entries per locale)
idx_path = os.path.join(BASE, "index.ts")
idx = open(idx_path, encoding="utf-8").read()
for loc in LOCALES:
    imp = f"import {loc}Settings from './{loc}/settings.json'\n"
    if imp in idx:
        idx = idx.replace(imp, imp +
            f"import {loc}Plans from './{loc}/plans.json'\n"
            f"import {loc}Subscriptions from './{loc}/subscriptions.json'\n")
    cat = f"    settings: {loc}Settings,\n  }}"
    if cat in idx:
        idx = idx.replace(cat,
            f"    settings: {loc}Settings,\n"
            f"    plans: {loc}Plans,\n"
            f"    subscriptions: {loc}Subscriptions,\n  }}")
open(idx_path, "w", encoding="utf-8").write(idx)

print("i18n files written:", len(LOCALES) * 2, "namespaces + nav keys + index.ts")

#!/usr/bin/env python3
"""Task 15 — add the per-company account page i18n keys to the
subscriptions namespace across all 8 locales. Arabic is the fallback base
(missing keys in other locales render Arabic), but we ship complete
translations for all languages like previous tasks."""

import json
import os

BASE = "frontend/apps/admin-dashboard/src/i18n/messages"

KEYS = {
    # Account page chrome
    "acc_manage": {
        "ar": "إدارة الحساب", "en": "Manage account", "es": "Gestionar cuenta",
        "fr": "Gérer le compte", "hi": "खाता प्रबंधित करें", "tr": "Hesabı yönet",
        "ur": "اکاؤنٹ منظم کریں", "zh": "管理账户",
    },
    "acc_loading": {
        "ar": "جارٍ تحميل الحساب…", "en": "Loading account…", "es": "Cargando cuenta…",
        "fr": "Chargement du compte…", "hi": "खाता लोड हो रहा है…", "tr": "Hesap yükleniyor…",
        "ur": "اکاؤنٹ لوڈ ہو رہا ہے…", "zh": "正在加载账户…",
    },
    "acc_no_company": {
        "ar": "لم يُحدد الحساب — عد إلى قائمة الاشتراكات واختر حسابًا",
        "en": "No account selected — go back to the subscriptions list and pick one",
        "es": "No hay cuenta seleccionada — vuelva a la lista de suscripciones",
        "fr": "Aucun compte sélectionné — revenez à la liste des abonnements",
        "hi": "कोई खाता चयनित नहीं — सदस्यता सूची पर वापस जाएँ",
        "tr": "Hesap seçilmedi — abonelik listesine dönün",
        "ur": "کوئی اکاؤنٹ منتخب نہیں — سبسکرپشن کی فہرست پر واپس جائیں",
        "zh": "未选择账户 — 请返回订阅列表选择",
    },
    "back_to_list": {
        "ar": "العودة للقائمة", "en": "Back to list", "es": "Volver a la lista",
        "fr": "Retour à la liste", "hi": "सूची पर वापस", "tr": "Listeye dön",
        "ur": "فہرست پر واپس", "zh": "返回列表",
    },
    "acc_tab_overview": {
        "ar": "نظرة عامة", "en": "Overview", "es": "Resumen", "fr": "Aperçu",
        "hi": "अवलोकन", "tr": "Genel bakış", "ur": "جائزہ", "zh": "概览",
    },
    "acc_tab_subscription": {
        "ar": "الاشتراك", "en": "Subscription", "es": "Suscripción", "fr": "Abonnement",
        "hi": "सदस्यता", "tr": "Abonelik", "ur": "سبسکرپشن", "zh": "订阅",
    },
    "acc_tab_overrides": {
        "ar": "الاستثناءات", "en": "Overrides", "es": "Excepciones", "fr": "Exceptions",
        "hi": "अपवाद", "tr": "İstisnalar", "ur": "استثنائات", "zh": "例外",
    },
    "acc_tab_logs": {
        "ar": "السجلات", "en": "Logs", "es": "Registros", "fr": "Journaux",
        "hi": "लॉग", "tr": "Kayıtlar", "ur": "لاگز", "zh": "日志",
    },
    "acc_tab_payments": {
        "ar": "المدفوعات", "en": "Payments", "es": "Pagos", "fr": "Paiements",
        "hi": "भुगतान", "tr": "Ödemeler", "ur": "ادائیگیاں", "zh": "付款",
    },
    "acc_card_plan": {
        "ar": "الخطة الحالية", "en": "Current plan", "es": "Plan actual",
        "fr": "Plan actuel", "hi": "वर्तमान प्लान", "tr": "Mevcut plan",
        "ur": "موجودہ پلان", "zh": "当前计划",
    },
    "acc_card_source": {
        "ar": "المصدر", "en": "Source", "es": "Origen", "fr": "Source",
        "hi": "स्रोत", "tr": "Kaynak", "ur": "ذریعہ", "zh": "来源",
    },
    "acc_card_overrides": {
        "ar": "استثناءات نشطة", "en": "Active overrides", "es": "Excepciones activas",
        "fr": "Exceptions actives", "hi": "सक्रिय अपवाद", "tr": "Aktif istisnalar",
        "ur": "فعال استثنائات", "zh": "有效例外",
    },
    "acc_card_phone": {
        "ar": "الهاتف", "en": "Phone", "es": "Teléfono", "fr": "Téléphone",
        "hi": "फ़ोन", "tr": "Telefon", "ur": "فون", "zh": "电话",
    },
    "acc_no_sub": {
        "ar": "لا يوجد اشتراك حاوي — أسند خطة من تبويب الاشتراك",
        "en": "No governing subscription — assign a plan from the subscription tab",
        "es": "No hay suscripción vigente — asigne un plan desde la pestaña Suscripción",
        "fr": "Aucun abonnement en vigueur — attribuez un plan depuis l'onglet Abonnement",
        "hi": "कोई सदस्यता नहीं — सदस्यता टैब से प्लान असाइन करें",
        "tr": "Geçerli abonelik yok — Abonelik sekmesinden plan atayın",
        "ur": "کوئی سبسکرپشن نہیں — سبسکرپشن ٹیب سے پلان تفویض کریں",
        "zh": "没有有效订阅 — 请在订阅选项卡中分配计划",
    },
    "acc_no_payments": {
        "ar": "لا مدفوعات مسجلة لهذا الحساب", "en": "No payments recorded for this account",
        "es": "No hay pagos registrados para esta cuenta",
        "fr": "Aucun paiement enregistré pour ce compte",
        "hi": "इस खाते के लिए कोई भुगतान दर्ज नहीं",
        "tr": "Bu hesap için kayıtlı ödeme yok",
        "ur": "اس اکاؤنٹ کے لیے کوئی ادائیگی درج نہیں", "zh": "该账户无付款记录",
    },
    "acc_usage_title": {
        "ar": "الاستخدام الحالي مقابل الحدود",
        "en": "Current usage vs limits", "es": "Uso actual vs límites",
        "fr": "Utilisation actuelle vs limites", "hi": "वर्तमान उपयोग बनाम सीमाएँ",
        "tr": "Mevcut kullanım ve limitler", "ur": "موجودہ استعمال بمقابلہ حدود",
        "zh": "当前用量与上限",
    },
    "acc_change_plan": {
        "ar": "تغيير الخطة", "en": "Change plan", "es": "Cambiar plan",
        "fr": "Changer de plan", "hi": "प्लान बदलें", "tr": "Planı değiştir",
        "ur": "پلان تبدیل کریں", "zh": "更改计划",
    },
    "acc_versions_title": {
        "ar": "سجل إصدارات الاشتراك", "en": "Subscription version history",
        "es": "Historial de versiones de suscripción",
        "fr": "Historique des versions d'abonnement",
        "hi": "सदस्यता संस्करण इतिहास", "tr": "Abonelik sürüm geçmişi",
        "ur": "سبسکرپشن ورژن تاریخ", "zh": "订阅版本历史",
    },
    "limit_branches": {
        "ar": "الفروع", "en": "Branches", "es": "Sucursales", "fr": "Succursales",
        "hi": "शाखाएँ", "tr": "Şubeler", "ur": "شاخیں", "zh": "分店",
    },
    "limit_users": {
        "ar": "المستخدمون", "en": "Users", "es": "Usuarios", "fr": "Utilisateurs",
        "hi": "उपयोगकर्ता", "tr": "Kullanıcılar", "ur": "صارفین", "zh": "用户",
    },
    "limit_employees": {
        "ar": "الموظفون", "en": "Employees", "es": "Empleados", "fr": "Employés",
        "hi": "कर्मचारी", "tr": "Çalışanlar", "ur": "ملازمین", "zh": "员工",
    },
    "limit_products": {
        "ar": "المنتجات", "en": "Products", "es": "Productos", "fr": "Produits",
        "hi": "उत्पाद", "tr": "Ürünler", "ur": "پروڈکٹس", "zh": "商品",
    },
    # Overrides
    "ov_badge": {
        "ar": "استثناءات: {n}", "en": "Overrides: {n}", "es": "Excepciones: {n}",
        "fr": "Exceptions : {n}", "hi": "अपवाद: {n}", "tr": "İstisnalar: {n}",
        "ur": "استثنائات: {n}", "zh": "例外：{n}",
    },
    "ov_explainer": {
        "ar": "الاستثناءات تُطبق على هذا الحساب وحده فوق خطة الأساس: منح وحدة أو صلاحية، منعها، أو تعديل حد كمي — دون إنشاء خطة جديدة ودون المساس بباقي المشتركين. منح ميزة يضم صلاحياتها المشتقة تلقائيًا، وحذفها يُرجع الكل لخطة الأساس.",
        "en": "Overrides apply to THIS account only, on top of its plan baseline: grant or deny a module/permission, or tweak a numeric limit — no new plan needed, other subscribers untouched. Granting a feature bundles its derived permissions automatically; deleting it falls everything back to the baseline.",
        "es": "Las excepciones se aplican solo a ESTA cuenta sobre su plan base: conceda o deniegue un módulo/permiso o ajuste un límite — sin crear un plan nuevo ni afectar a otros suscriptores. Conceder una función incluye automáticamente sus permisos derivados; eliminarla devuelve todo al plan base.",
        "fr": "Les exceptions s'appliquent à CE compte seul, par-dessus son plan de base : accorder/refuser un module ou une permission, ou ajuster une limite — sans créer de plan ni toucher aux autres abonnés. Accorder une fonctionnalité inclut automatiquement ses permissions dérivées ; la supprimer restaure le plan de base.",
        "hi": "अपवाद केवल इसी खाते पर, उसके प्लान आधार के ऊपर लागू होते हैं: मॉड्यूल/अनुमति दें या रोकें, या संख्यात्मक सीमा बदलें — नया प्लान बनाए बिना, अन्य ग्राहकों को छुए बिना। फ़ीचर देने पर उसकी व्युत्पन्न अनुमतियाँ स्वतः शामिल होती हैं; हटाने पर सब आधार प्लान पर लौटता है।",
        "tr": "İstisnalar yalnızca BU hesaba, plan tabanının üzerine uygulanır: modül/izin verin veya engelleyin ya da sayısal sınırı değiştirin — yeni plan oluşturmadan, diğer abonelere dokunmadan. Bir özelliğin verilmesi, türetilen izinlerini otomatik olarak içerir; silinmesi her şeyi taban plana döndürür.",
        "ur": "استثنائات صرف اسی اکاؤنٹ پر، اس کے پلان کی بنیاد کے اوپر لاگو ہوتے ہیں: ماڈیول/اجازت دیں یا روکیں، یا عددی حد تبدیل کریں — نیا پلان بنائے بغیر، دوسرے صارفین کو چھڑے بغیر۔ فیچر دینے پر اس کی ماخوذ اجازتیں خودکار شامل ہوتی ہیں؛ حذف کرنے پر سب بنیاد پر واپس۔",
        "zh": "例外仅应用于该账户，叠加在其计划基线之上：授予或拒绝模块/权限，或调整数量上限 — 无需新建计划，也不影响其他订阅者。授予功能时会自动包含其派生权限；删除后全部恢复为计划基线。",
    },
    "ov_list_title": {
        "ar": "استثناءات الحساب", "en": "Account overrides", "es": "Excepciones de la cuenta",
        "fr": "Exceptions du compte", "hi": "खाता अपवाद", "tr": "Hesap istisnaları",
        "ur": "اکاؤنٹ استثنائات", "zh": "账户例外",
    },
    "ov_add": {
        "ar": "إضافة استثناء", "en": "Add override", "es": "Añadir excepción",
        "fr": "Ajouter une exception", "hi": "अपवाद जोड़ें", "tr": "İstisna ekle",
        "ur": "استثنا شامل کریں", "zh": "添加例外",
    },
    "ov_empty": {
        "ar": "لا استثناءات — الحساب يسير على خطة الأساس كما هي",
        "en": "No overrides — the account runs on its plan baseline as-is",
        "es": "Sin excepciones — la cuenta opera sobre su plan base",
        "fr": "Aucune exception — le compte suit son plan de base",
        "hi": "कोई अपवाद नहीं — खाता अपने आधार प्लान पर चलता है",
        "tr": "İstisna yok — hesap plan tabanında çalışıyor",
        "ur": "کوئی استثنا نہیں — اکاؤنٹ اپنے بنیادی پلان پر چلتا ہے",
        "zh": "无例外 — 账户按计划基线运行",
    },
    "ov_add_title": {
        "ar": "إضافة استثناء لهذا الحساب", "en": "Add an override for this account",
        "es": "Añadir una excepción para esta cuenta",
        "fr": "Ajouter une exception pour ce compte",
        "hi": "इस खाते के लिए अपवाद जोड़ें",
        "tr": "Bu hesap için istisna ekle",
        "ur": "اس اکاؤنٹ کے لیے استثنا شامل کریں",
        "zh": "为该账户添加例外",
    },
    "ov_add_hint": {
        "ar": "الاستثناء يُلغي إعداد الخطة لهذا المفتاح فقط ويبقى باقي الإعدادات من الخطة",
        "en": "The override replaces the plan setting for this key only; everything else stays from the plan",
        "es": "La excepción reemplaza el ajuste del plan solo para esta clave; lo demás proviene del plan",
        "fr": "L'exception remplace le réglage du plan pour cette clé uniquement ; le reste vient du plan",
        "hi": "अपवाद केवल इस कुंजी के लिए प्लान सेटिंग बदलता है; बाकी प्लान से रहता है",
        "tr": "İstisna yalnızca bu anahtar için plan ayarını değiştirir; geri kalanı plandan gelir",
        "ur": "استثنا صرف اسی کلید کے لیے پلان کی ترتیب بدلتا ہے؛ باقی پلان سے رہتا ہے",
        "zh": "例外仅替换该键的计划设置，其余仍来自计划",
    },
    "ov_kind": {
        "ar": "النوع", "en": "Type", "es": "Tipo", "fr": "Type",
        "hi": "प्रकार", "tr": "Tür", "ur": "قسم", "zh": "类型",
    },
    "ov_kind_feature": {
        "ar": "ميزة (وحدة)", "en": "Feature (module)", "es": "Función (módulo)",
        "fr": "Fonctionnalité (module)", "hi": "फ़ीचर (मॉड्यूल)", "tr": "Özellik (modül)",
        "ur": "فیچر (ماڈیول)", "zh": "功能（模块）",
    },
    "ov_kind_permission": {
        "ar": "صلاحية (API)", "en": "Permission (API)", "es": "Permiso (API)",
        "fr": "Permission (API)", "hi": "अनुमति (API)", "tr": "İzin (API)",
        "ur": "اجازت (API)", "zh": "权限（API）",
    },
    "ov_kind_limit": {
        "ar": "حد كمي", "en": "Numeric limit", "es": "Límite numérico",
        "fr": "Limite numérique", "hi": "संख्यात्मक सीमा", "tr": "Sayısal sınır",
        "ur": "عددی حد", "zh": "数量上限",
    },
    "ov_kind_feature_": None,  # placeholder skipped
    "ov_feature": {
        "ar": "الميزة", "en": "Feature", "es": "Función", "fr": "Fonctionnalité",
        "hi": "फ़ीचर", "tr": "Özellik", "ur": "فیچر", "zh": "功能",
    },
    "ov_permission": {
        "ar": "الصلاحية", "en": "Permission", "es": "Permiso", "fr": "Permission",
        "hi": "अनुमति", "tr": "İzin", "ur": "اجازت", "zh": "权限",
    },
    "ov_limit_key": {
        "ar": "مفتاح الحد", "en": "Limit key", "es": "Clave del límite",
        "fr": "Clé de limite", "hi": "सीमा कुंजी", "tr": "Sınır anahtarı",
        "ur": "حد کی کلید", "zh": "上限键",
    },
    "ov_grant": {
        "ar": "منح", "en": "Grant", "es": "Conceder", "fr": "Accorder",
        "hi": "दें", "tr": "Ver", "ur": "فراہم کریں", "zh": "授予",
    },
    "ov_deny": {
        "ar": "منع", "en": "Deny", "es": "Denegar", "fr": "Refuser",
        "hi": "रोकें", "tr": "Engelle", "ur": "روکیں", "zh": "拒绝",
    },
    "ov_granted": {
        "ar": "ممنوح", "en": "Granted", "es": "Concedido", "fr": "Accordé",
        "hi": "प्रदत्त", "tr": "Verildi", "ur": "فراہم شدہ", "zh": "已授予",
    },
    "ov_denied": {
        "ar": "ممنوع", "en": "Denied", "es": "Denegado", "fr": "Refusé",
        "hi": "निषेध", "tr": "Engellendi", "ur": "ممنوع", "zh": "已拒绝",
    },
    "ov_unlimited": {
        "ar": "غير محدود", "en": "Unlimited", "es": "Ilimitado", "fr": "Illimité",
        "hi": "असीमित", "tr": "Sınırsız", "ur": "غیر محدود", "zh": "无限制",
    },
    "ov_bundled": {
        "ar": "مرتبطة بميزة", "en": "bundled", "es": "incluido", "fr": "groupé",
        "hi": "बंडल", "tr": "paket", "ur": "پیکج", "zh": "随附",
    },
    "ov_expired": {
        "ar": "منتهي", "en": "expired", "es": "caducado", "fr": "expiré",
        "hi": "समाप्त", "tr": "süresi geçti", "ur": "ختم", "zh": "已过期",
    },
    "ov_until": {
        "ar": "حتى", "en": "until", "es": "hasta", "fr": "jusqu'à",
        "hi": "तक", "tr": "kadar", "ur": "تک", "zh": "至",
    },
    "ov_permanent": {
        "ar": "دائم", "en": "permanent", "es": "permanente", "fr": "permanent",
        "hi": "स्थायी", "tr": "kalıcı", "ur": "دائمی", "zh": "永久",
    },
    "ov_reason": {
        "ar": "السبب (يظهر في السجل)", "en": "Reason (shown in the log)",
        "es": "Motivo (visible en el registro)", "fr": "Motif (visible dans le journal)",
        "hi": "कारण (लॉग में दिखता है)", "tr": "Sebep (kayıtta görünür)",
        "ur": "وجہ (لاگ میں نظر آتی ہے)", "zh": "原因（显示在日志中）",
    },
    "ov_expires": {
        "ar": "تاريخ الانتهاء (اختياري — الاستثناء ينعكس تلقائيًا)",
        "en": "Expiry date (optional — the override reverses itself)",
        "es": "Fecha de caducidad (opcional — la excepción se revierte sola)",
        "fr": "Date d'expiration (facultatif — l'exception s'annule d'elle-même)",
        "hi": "समाप्ति तिथि (वैकल्पिक — अपवाद स्वतः उलट जाता है)",
        "tr": "Bitiş tarihi (isteğe bağlı — istisna kendiliğinden geri alınır)",
        "ur": "تاریخ اختتام (اختیاری — استثنا خودبخود واپس)",
        "zh": "到期日期（可选 — 例外自动失效）",
    },
    "ov_bundle_hint": {
        "ar": "سيُمنح هذا الحساب الميزة مع {n} صلاحية مشتقة تلقائيًا كحزمة واحدة",
        "en": "This account will receive the feature bundled with {n} derived permissions automatically",
        "es": "Esta cuenta recibirá la función junto con {n} permisos derivados automáticamente",
        "fr": "Ce compte recevra la fonctionnalité avec {n} permissions dérivées automatiquement",
        "hi": "इस खाते को फ़ीचर {n} व्युत्पन्न अनुमतियों के साथ स्वतः मिलेगा",
        "tr": "Bu hesap özelliği {n} türetilmiş izinle birlikte otomatik alacak",
        "ur": "اس اکاؤنٹ کو فیچر {n} ماخوذ اجازتوں کے ساتھ خودکار ملے گا",
        "zh": "该账户将自动获得该功能及 {n} 项派生权限",
    },
    "ov_confirm_delete": {
        "ar": "حذف هذا الاستثناء والعودة لخطة الأساس؟",
        "en": "Delete this override and fall back to the plan baseline?",
        "es": "¿Eliminar esta excepción y volver al plan base?",
        "fr": "Supprimer cette exception et revenir au plan de base ?",
        "hi": "यह अपवाद हटाकर आधार प्लान पर लौटें?",
        "tr": "Bu istisnayı silip plan tabanına dönmek istiyor musunuz?",
        "ur": "یہ استثنا حذف کر کے بنیادی پلان پر واپس جائیں؟",
        "zh": "删除此例外并恢复计划基线？",
    },
    "ov_delete": {
        "ar": "حذف الاستثناء", "en": "Delete override", "es": "Eliminar excepción",
        "fr": "Supprimer l'exception", "hi": "अपवाद हटाएँ", "tr": "İstisnayı sil",
        "ur": "استثنا حذف کریں", "zh": "删除例外",
    },
    "ov_invalid_value": {
        "ar": "قيمة الحد يجب أن تكون رقمًا موجبًا أو -1 لغير محدود",
        "en": "The limit value must be a positive number or -1 for unlimited",
        "es": "El valor del límite debe ser positivo o -1 para ilimitado",
        "fr": "La valeur de la limite doit être positive ou -1 pour illimité",
        "hi": "सीमा मान सकारात्मक होनी चाहिए या असीमित के लिए -1",
        "tr": "Sınır değeri pozitif veya sınırsız için -1 olmalı",
        "ur": "حد کی قدر مثبت ہونی چاہیے یا غیر محدود کے لیے -1",
        "zh": "上限值必须为正数或 -1 表示无限制",
    },
    # Logs
    "log_title": {
        "ar": "سجل هذا الحساب", "en": "This account's log", "es": "Registro de esta cuenta",
        "fr": "Journal de ce compte", "hi": "इस खाते का लॉग", "tr": "Bu hesabın kaydı",
        "ur": "اس اکاؤنٹ کا لاگ", "zh": "该账户的日志",
    },
    "log_empty": {
        "ar": "لا أحداث مسجلة لهذا الحساب بعد",
        "en": "No events recorded for this account yet",
        "es": "Aún no hay eventos registrados para esta cuenta",
        "fr": "Aucun événement enregistré pour ce compte",
        "hi": "इस खाते के लिए अभी कोई घटना दर्ज नहीं",
        "tr": "Bu hesap için henüz kayıtlı olay yok",
        "ur": "اس اکاؤنٹ کے لیے ابھی کوئی واقعہ درج نہیں",
        "zh": "该账户暂无事件记录",
    },
    "log_prev": {
        "ar": "السابق", "en": "Previous", "es": "Anterior", "fr": "Précédent",
        "hi": "पिछला", "tr": "Önceki", "ur": "پچھلا", "zh": "上一页",
    },
    "log_next": {
        "ar": "التالي", "en": "Next", "es": "Siguiente", "fr": "Suivant",
        "hi": "अगला", "tr": "Sonraki", "ur": "اگلا", "zh": "下一页",
    },
}

LOCALES = ["ar", "en", "es", "fr", "hi", "tr", "ur", "zh"]
count = 0
for locale in LOCALES:
    path = os.path.join(BASE, locale, "subscriptions.json")
    data = json.load(open(path, encoding="utf-8"))
    added = 0
    for key, translations in KEYS.items():
        if translations is None:
            continue
        if key not in data:
            data[key] = translations[locale]
            added += 1
    json.dump(data, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    open(path, "a", encoding="utf-8").write("\n")
    count += added
    print(f"{locale}: +{added} keys → {len(data)}")
print(f"TOTAL added: {count}")

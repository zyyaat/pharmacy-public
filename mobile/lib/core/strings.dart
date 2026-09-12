import 'package:flutter/foundation.dart';

import 'i18n_data.dart';

/// Task 61 — المترجم المركزي للموبايل: نسخة طبق الأصل من i18n/translator.ts
/// في الويب: بحث بنطاق + مفتاح، استيفاء {param}، ورجوع مرئي بمسار المفتاح
/// عند فقدانه (مقصود — حتى يُلاحظ أي مفتاح ناقص فورًا).
///
/// Task 81 — نظام اللغات الثماني كالويب: قائمة اللغات مطابقة لـ i18n/config.ts
/// (ar/en/fr/es/tr/zh/hi/ur بترتيبه وأسمائه الأصلية في LOCALE_META)، وكود
/// غير معروف يُطبعّن إلى العربية مثل حارس isLocale، وأي مفتاح ناقص في لغة
/// جزئية يرجع إلى العربية — نفس دلالة deepMerge(catalogs.ar, catalogs[locale])
/// في messages/index.ts، لكن وقت البحث بدل النسخ المسبق.
class AppI18n extends ChangeNotifier {
  AppI18n._();
  static final AppI18n instance = AppI18n._();

  /// نفس ترتيب locales في i18n/config.ts — اللغة الافتراضية العربية أولًا.
  static const List<String> locales = <String>[
    'ar', 'en', 'fr', 'es', 'tr', 'zh', 'hi', 'ur',
  ];

  /// مثل LOCALE_META في i18n/config.ts: nativeName + englishName لكل لغة
  /// (تعرضها شاشة إعدادات اللغة بأسلوب language-setting.tsx).
  static const Map<String, (String, String)> localeMeta =
      <String, (String, String)>{
    'ar': ('العربية', 'Arabic'),
    'en': ('English', 'English'),
    'fr': ('Français', 'French'),
    'es': ('Español', 'Spanish'),
    'tr': ('Türkçe', 'Turkish'),
    'zh': ('中文', 'Chinese'),
    'hi': ('हिन्दी', 'Hindi'),
    'ur': ('اردو', 'Urdu'),
  };

  /// اتجاه RTL مثل dirFor في config.ts: العربية والأردية فقط.
  static const Set<String> _rtlLocales = <String>{'ar', 'ur'};

  static bool isValidLocale(String code) => locales.contains(code);

  String _locale = 'ar';
  String get locale => _locale;
  bool get isRtl => _rtlLocales.contains(_locale);

  Map<String, Map<String, String>> get _msgs => kI18nAll[_locale] ?? kI18nAll['ar']!;

  Future<void> setLocale(String locale) async {
    // مثل isLocale بالويب: كود غير معروف (تخزين قديم/تلاعب) يُطبعّن للعربية
    final String next = isValidLocale(locale) ? locale : 'ar';
    if (_locale == next) return;
    _locale = next;
    notifyListeners();
  }

  String? _resolve(Map<String, Map<String, String>> msgs, String ns, String key) {
    final nsMap = msgs[ns];
    if (nsMap != null && nsMap[key] != null) return nsMap[key];
    if (key.contains('.')) {
      final parts = key.split('.');
      if (parts.length >= 2) return msgs[parts[0]]?[parts.sublist(1).join('.')];
    }
    return null;
  }

  /// الويب: t = useT('ns') ثم t('key') — هنا t('ns', 'key').
  /// يدعم أيضًا مفتاحًا كاملًا 'ns.key' بتمرير ns فارغًا.
  /// المفتاح الناقص في اللغة الحالية يرجع للعربية أولًا (deepMerge)،
  /// وإلا فالمرجع المرئي بمسار المفتاح.
  String t(String ns, String key, [Map<String, Object?>? params]) {
    String? resolved = _resolve(_msgs, ns, key);
    resolved ??= _resolve(kI18nAll['ar']!, ns, key);
    var value = resolved ?? (ns.isEmpty ? key : '$ns.$key');
    if (params != null) {
      params.forEach((name, raw) {
        value = value.replaceAll('{$name}', '$raw');
      });
    }
    return value;
  }

  /// ترجمة كود خطأ الباكند عبر نطاق errors (كما يفعل runtimeTranslator('errors')).
  /// المرجع المرئي يعيد 'errors.<code>' عند غياب المفتاح — عندها نستخدم البديل.
  String error(String code, [String? fallback]) {
    final resolved = t('errors', code.toLowerCase());
    if (resolved.startsWith('errors.') && fallback != null && fallback.isNotEmpty) {
      return fallback;
    }
    return resolved;
  }
}

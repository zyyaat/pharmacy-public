import 'package:flutter/foundation.dart';

import 'i18n_data.dart';

/// Task 61 — المترجم المركزي للموبايل: نسخة طبق الأصل من i18n/translator.ts
/// في الويب: بحث بنطاق + مفتاح، استيفاء {param}، ورجوع مرئي بمسار المفتاح
/// عند فقدانه (مقصود — حتى يُلاحظ أي مفتاح ناقص فورًا).
class AppI18n extends ChangeNotifier {
  AppI18n._();
  static final AppI18n instance = AppI18n._();

  String _locale = 'ar';
  String get locale => _locale;
  bool get isRtl => _locale.startsWith('ar') || _locale == 'ur';

  Map<String, Map<String, String>> get _msgs => _locale == 'ar' ? kI18nAr : kI18nEn;

  Future<void> setLocale(String locale) async {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
  }

  /// الويب: t = useT('ns') ثم t('key') — هنا t('ns', 'key').
  /// يدعم أيضًا مفتاحًا كاملًا 'ns.key' بتمرير ns فارغًا.
  String t(String ns, String key, [Map<String, Object?>? params]) {
    String? resolved;
    final nsMap = _msgs[ns];
    if (nsMap != null && nsMap[key] != null) {
      resolved = nsMap[key];
    } else if (key.contains('.')) {
      final parts = key.split('.');
      if (parts.length >= 2) resolved = _msgs[parts[0]]?[parts.sublist(1).join('.')];
    }
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

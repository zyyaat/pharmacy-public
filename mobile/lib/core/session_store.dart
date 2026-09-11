import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// تخزين التفضيلات الحساسة/الدائمة: بيانات الدخول المحفوظة (للدخول الصامت)،
/// ولغة الواجهة، ووضع الثيم.
/// (كوكيز الجلسة نفسها لها مسارها الخاص في cookies.dart)
class SessionStore {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _kCredentials = 'pharmacy_saved_credentials';
  static const String _kLocale = 'ui_locale';
  static const String _kThemeMode = 'ui_theme_mode';

  /// بيانات الدخول المحفوظة — أساس قاعدة «يبقى مسجلاً حتى خروج يدوي»:
  /// إذا فسدت أو انتهت كوكيز الجلسة أعاد التطبيق فتح الجلسة صامتًا بها.
  /// التخزين مشفّر على الأندرويد (Keystore عبر encryptedSharedPreferences).
  Future<({String email, String password})?> credentials() async {
    try {
      final raw = await _storage.read(key: _kCredentials);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final email = (decoded['email'] ?? '').toString();
        final password = (decoded['password'] ?? '').toString();
        if (email.isNotEmpty && password.isNotEmpty) {
          return (email: email, password: password);
        }
      }
    } catch (_) {
      // بيانات تالفة = لا يوجد شيء محفوظ، لا تُتلف الجلسة الحية
    }
    return null;
  }

  Future<void> setCredentials(String email, String password) async {
    try {
      await _storage.write(
        key: _kCredentials,
        value: jsonEncode(<String, String>{
          'email': email,
          'password': password,
        }),
      );
    } catch (_) {
      // فشل التخزين لا يكسر الجلسة الحية — ستعمل بالكوكيز فقط
    }
  }

  /// يُمسح عند تسجيل الخروج اليدوي فقط، أو عند فشل الدخول الصامت
  /// لأن كلمة المرور تغيّرت (فيُطلب دخول يدوي جديد).
  Future<void> clearCredentials() async {
    try {
      await _storage.delete(key: _kCredentials);
    } catch (_) {}
  }

  Future<String?> locale() => _storage.read(key: _kLocale);

  Future<void> setLocale(String value) =>
      _storage.write(key: _kLocale, value: value);

  /// light / dark / system (افتراضي النظام مثل next-themes في الويب)
  Future<String?> themeMode() => _storage.read(key: _kThemeMode);

  Future<void> setThemeMode(String value) =>
      _storage.write(key: _kThemeMode, value: value);
}

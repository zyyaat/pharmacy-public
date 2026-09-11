import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// تخزين التفضيلات الحساسة/الدائمة: تجاوز عنوان الخادم ولغة الواجهة.
/// (الكوكيز نفسها لها مسارها الخاص في cookies.dart)
class SessionStore {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _kServerOverride = 'server_base_url_override';
  static const String _kLocale = 'ui_locale';
  static const String _kThemeMode = 'ui_theme_mode';

  Future<String?> serverOverride() =>
      _storage.read(key: _kServerOverride);

  Future<void> setServerOverride(String? value) async {
    if (value == null || value.trim().isEmpty) {
      await _storage.delete(key: _kServerOverride);
    } else {
      await _storage.write(key: _kServerOverride, value: value.trim());
    }
  }

  Future<String?> locale() => _storage.read(key: _kLocale);

  Future<void> setLocale(String value) =>
      _storage.write(key: _kLocale, value: value);

  /// light / dark / system (افتراضي النظام مثل next-themes في الويب)
  Future<String?> themeMode() => _storage.read(key: _kThemeMode);

  Future<void> setThemeMode(String value) =>
      _storage.write(key: _kThemeMode, value: value);
}

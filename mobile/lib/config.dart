// Task 59 — إعدادات البناء: القيم تُحقن وقت البناء عبر --dart-define-from-file
// (env.json الذي يولده الـ workflow من متغيرات GitHub) أو تُتجاوز من داخل
// التطبيق في شاشة الإعدادات (طبقة الطوارئ الثالثة).
class AppConfig {
  /// عنوان الـ API الافتراضي — يُستبدل بقيمة GitHub Variable/API_BASE_URL
  /// أو إدخال Run workflow عند البناء.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://pharmacy-api.example.com/api/v1',
  );

  static const String appName = 'Pharmacy OS';

  /// طول رمز التحقق من البريد (OTP) كما يصممه الباك اند.
  static const int otpLength = 6;

  static String normalizeBaseUrl(String raw) {
    var v = raw.trim();
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }
}

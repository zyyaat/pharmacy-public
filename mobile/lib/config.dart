// إعدادات البناء: القيم تُحقن وقت البناء فقط عبر --dart-define-from-file
// (env.json الذي يولده الـ workflow من متغيرات GitHub).
// ⚠️ عنوان الخادم من اختصاص المطورين حصرًا — لا يوجد أي إدخال له داخل
// التطبيق، فالعميل لا يستطيع تغييره من الشاشات إطلاقًا.
class AppConfig {
  /// عنوان الـ API — يُستبدل بقيمة GitHub Variable/API_BASE_URL
  /// أو إدخال Run workflow عند البناء.
  /// الافتراضي هو خادم الإنتاج الحقيقي (DockHosting) حتى يعمل التطبيق
  /// المبني بالإعدادات الافتراضية فورًا بلا أي ضبط إضافي.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://pharmacy-public.dockhosting.dev/api/v1',
  );

  static const String appName = 'Pharmacy OS';

  /// طول رمز التحقق من البريد (OTP) كما يصممه الباك اند.
  static const int otpLength = 6;
}

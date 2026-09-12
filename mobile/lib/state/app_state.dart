import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/offline.dart';
import '../core/session_store.dart';
import '../core/sync.dart';
import '../core/strings.dart';
import '../models/models.dart';

/// حالة التطبيق المركزية: اللغة + الثيم (فاتح/داكن/النظام) + آلة حالات
/// الجلسة (boot→me→…) + سياق الصيدلية + صلاحيات المستخدم.
enum AuthPhase { booting, anonymous, unverified, onboarding, ready }

class AppState extends ChangeNotifier {
  final ApiClient api = ApiClient.instance;
  final SessionStore store = SessionStore();

  String _locale = 'ar';
  ThemeMode _themeMode = ThemeMode.system;
  AuthPhase _phase = AuthPhase.booting;
  User? user;
  PharmacyContext? context;
  MyPermissions? permissions;
  String? pendingVerifyEmail;

  // بيانات التسجيل الحالي في الذاكرة فقط — تُخزَّن مشفّرة بعد فتح الجلسة
  // بنجاح (تحقق البريد) ليعمل الدخول الصامت في الإقلاعات القادمة.
  String? _pendingRegisterEmail;
  String? _pendingRegisterPassword;

  String get locale => _locale;
  ThemeMode get themeMode => _themeMode;
  AuthPhase get phase => _phase;
  // Task 81 — مثل dirFor بالويب: العربية والأردية RTL (كان الأردية تنساب LTR هنا)
  bool get isRtl => _locale == 'ar' || _locale == 'ur';
  String get tns => _locale; // تمرير للتنسيق

  // ------------------------------------------------------------- التهيئة

  Future<void> loadInitialLocale() async {
    try {
      final saved = await store.locale();
      // Task 81 — تحصين: لغة محفوظة من إصدار قديم/غير معروفة تُطبعّن للعربية
      // (نفس حارس isLocale بالويب) بدل أن تُترك قيمة غريبة في الحالة
      if (saved != null && saved.isNotEmpty && AppI18n.isValidLocale(saved)) {
        _locale = saved;
      }
    } catch (_) {}
    try {
      final mode = await store.themeMode();
      if (mode != null && mode.isNotEmpty) {
        _themeMode = mode == 'dark'
            ? ThemeMode.dark
            : mode == 'light'
                ? ThemeMode.light
                : ThemeMode.system;
      }
    } catch (_) {}
    await AppI18n.instance.setLocale(_locale);
  }

  /// تبديل الثيم مثل زر الشمس/القمر في رأس الويب (light ↔ dark)
  Future<void> toggleTheme() async {
    _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await store.setThemeMode(_themeMode == ThemeMode.dark
        ? 'dark'
        : _themeMode == ThemeMode.light
            ? 'light'
            : 'system');
    notifyListeners();
  }

  Future<void> setLocale(String locale) async {
    _locale = locale;
    await AppI18n.instance.setLocale(locale);
    await store.setLocale(locale);
    try {
      await api.setLocale(locale);
    } catch (_) {/* الخادم اختياري هنا — المحلي هو المرجع */}
    notifyListeners();
  }

  /// Task 84/87 — المزامنة الذكية بعد جاهزية الجلسة: fire-and-forget لا
  /// يمس الإقلاع ولا الواجهة. أول مرة: إحماء كامل (سجلات شهر تقريبًا) +
  /// مؤشر من ساعة الخادم. كل فتح تالٍ مع اتصال: طلب /sync واحد يجلب فقط
  /// ما تغيّر منذ المؤشر + قبور الحذف — بلا إعادة تنزيل ما هو مخزّن
  /// أصلًا. البوابة (PrefetchService.enabled) تُفعّل من main() فقط،
  /// والخدمة لا ترمي أبدًا.
  void _warmPrefetch() {
    unawaited(SyncService.instance.maybeRun());
  }

  // ------------------------------------------------------------- الجلسة

  /// تشغيل الإقلاع: من يقول «ما زال صالحًا» هو الخادم عبر /me.
  /// قاعدة المستخدم: يبقى مسجلاً حتى يسجّل الخروج بنفسه —
  /// فإذا فسدت/انتهت كوكيز الجلسة (401) جرّبنا الدخول الصامت بالبيانات
  /// المحفوظة، وفشل الشبكة لا يُخرج أحدًا (شاشة البداية تعيد المحاولة).
  Future<void> boot() async {
    _phase = AuthPhase.booting;
    notifyListeners();
    try {
      user = await api.me();
    } on ApiException catch (e) {
      if (e.isNetwork) rethrow;
      final ok = await _silentRelogin();
      if (!ok) {
        user = null;
        context = null;
        permissions = null;
        // Task 82 — رفض الخادم فعليًا (كلمة المرور تغيّرت/جلسة ملغاة):
        // كاش أعمال الجلسة لا يجوز أن يبقى على الجهاز
        await OfflineCache.instance.clear();
        _phase = AuthPhase.anonymous;
        notifyListeners();
        return;
      }
    } catch (_) {
      user = null;
      _phase = AuthPhase.anonymous;
      notifyListeners();
      return;
    }
    await _loadSessionData();
    if (context != null && (context!.pharmacyName.isEmpty)) {
      _phase = AuthPhase.onboarding;
    } else {
      _phase = AuthPhase.ready;
      _warmPrefetch();
    }
    notifyListeners();
  }

  Future<void> _loadSessionData() async {
    try {
      context = await api.context();
    } catch (_) {
      context = null;
    }
    try {
      permissions = await api.myPermissions();
    } catch (_) {
      permissions = null;
    }
  }

  Future<void> refreshSessionData() async {
    await _loadSessionData();
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    user = await api.login(email, password);
    pendingVerifyEmail = null;
    // حفظ الدخول لهذا الجهاز (مشفّر) — الجلسة تبقى حتى خروج يدوي
    await store.setCredentials(email.trim(), password);
    await _loadSessionData();
    _phase = AuthPhase.ready;
    _warmPrefetch();
    notifyListeners();
  }

  /// الدخول الصامت بالبيانات المحفوظة عند فقدان كوكيز الجلسة
  /// (انتهاء صلاحية refresh أو مسحها من الخادم). فشل الشبكة يُرمى
  /// ليُعاد الإقلاع لاحقًا ولا يُسقط الجلسة؛ أما رفض الدخول فعلي
  /// (كلمة المرور تغيّرت) يمسح المحفوظ ويطلب دخولًا يدويًا.
  Future<bool> _silentRelogin() async {
    final creds = await store.credentials();
    if (creds == null) return false;
    try {
      user = await api.login(creds.email, creds.password);
    } on ApiException catch (e) {
      if (e.isNetwork) rethrow;
      await store.clearCredentials();
      // Task 82 — رفض الدخول فعليًا = انتهاء بيانات الجلسة وكاشها معًا
      await OfflineCache.instance.clear();
      return false;
    } catch (_) {
      return false;
    }
    pendingVerifyEmail = null;
    return true;
  }

  /// تسجيل جديد → انتظار تحقق البريد (الويب: نفس المسار)
  Future<void> register({
    required String companyName,
    required String companyEmail,
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    await api.register(
      companyName: companyName,
      companyEmail: companyEmail,
      firstName: firstName,
      lastName: lastName,
      email: email,
      password: password,
    );
    _pendingRegisterEmail = email;
    _pendingRegisterPassword = password;
    pendingVerifyEmail = email;
    _phase = AuthPhase.unverified;
    notifyListeners();
  }

  /// تخزين بيانات التسجيل بعد فتح الجلسة بنجاح — مرة واحدة ثم تُنسى من الذاكرة.
  Future<void> _persistPendingCredentials(String email) async {
    final pass = _pendingRegisterPassword;
    if (pass == null || pass.isEmpty) return;
    final mail = (email.isNotEmpty ? email : (_pendingRegisterEmail ?? '')).trim();
    if (mail.isNotEmpty) await store.setCredentials(mail, pass);
    _pendingRegisterEmail = null;
    _pendingRegisterPassword = null;
  }

  /// التحقق من الرمز — جلسة فورية على الخادم (api_level 57+)
  Future<({bool sessionCreated, bool onboardingRequired})> verifyEmail(String email, String code) async {
    final result = await api.verifyEmail(email, code);
    if (result.user != null) user = result.user;
    if (result.sessionCreated) {
      await _persistPendingCredentials(email);
      await _loadSessionData();
      _phase = result.onboardingRequired || context == null ? AuthPhase.onboarding : AuthPhase.ready;
      if (_phase == AuthPhase.ready) _warmPrefetch();
      notifyListeners();
    }
    return (sessionCreated: result.sessionCreated, onboardingRequired: result.onboardingRequired);
  }

  /// الخادم قديم ولم يفتح جلسة (Task 58): نعيد المحاولة عبر /me قبل الاستسلام
  Future<bool> probeSessionAfterVerify() async {
    try {
      user = await api.me();
    } catch (_) {
      return false;
    }
    await _persistPendingCredentials(user?.email ?? '');
    await _loadSessionData();
    _phase = AuthPhase.ready;
    _warmPrefetch();
    notifyListeners();
    return true;
  }

  Future<void> completeOnboarding() async {
    await _loadSessionData();
    _phase = AuthPhase.ready;
    _warmPrefetch();
    notifyListeners();
  }

  /// تسجيل الخروج اليدوي — الطريق الوحيد لمغادرة الجلسة.
  /// ينجح حتى بلا شبكة: الكوكيز والبيانات المحفوظة تُمسح محليًا على أي حال.
  Future<void> logout() async {
    try {
      await api.logout();
    } catch (_) {
      // لا شبكة/خطأ خادم — لا يمنع الخروج المحلي
    }
    await store.clearCredentials();
    // Task 82 — الخروج اليدوي يمسح كاش بيانات الأعمال أيضًا (جهاز مشترك)
    await OfflineCache.instance.clear();
    _pendingRegisterEmail = null;
    _pendingRegisterPassword = null;
    user = null;
    context = null;
    permissions = null;
    pendingVerifyEmail = null;
    _phase = AuthPhase.anonymous;
    notifyListeners();
  }

  // ------------------------------------------------------------- الصلاحيات

  bool can(String key) => permissions?.can(key) ?? true;
  bool canAny(List<String> keys) => permissions?.canAny(keys) ?? true;
}

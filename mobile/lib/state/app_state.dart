import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/session_store.dart';
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

  String get locale => _locale;
  ThemeMode get themeMode => _themeMode;
  AuthPhase get phase => _phase;
  bool get isRtl => _locale.startsWith('ar');
  String get tns => _locale; // تمرير للتنسيق

  // ------------------------------------------------------------- التهيئة

  Future<void> loadInitialLocale() async {
    try {
      final saved = await store.locale();
      if (saved != null && saved.isNotEmpty) _locale = saved;
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

  Future<void> applyServerOverride(String? raw) async {
    await api.applyServerUrl(raw);
    await store.setServerOverride(raw);
    notifyListeners();
  }

  Future<String?> serverOverride() => store.serverOverride();

  // ------------------------------------------------------------- الجلسة

  /// تشغيل الإقلاع: من يقول «ما زال صالحًا» هو الخادم عبر /me.
  Future<void> boot() async {
    _phase = AuthPhase.booting;
    notifyListeners();
    try {
      user = await api.me();
    } on ApiException catch (e) {
      user = null;
      _phase = AuthPhase.anonymous;
      notifyListeners();
      if (e.isNetwork) rethrow;
      return;
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
    await _loadSessionData();
    _phase = AuthPhase.ready;
    notifyListeners();
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
    pendingVerifyEmail = email;
    _phase = AuthPhase.unverified;
    notifyListeners();
  }

  /// التحقق من الرمز — جلسة فورية على الخادم (api_level 57+)
  Future<({bool sessionCreated, bool onboardingRequired})> verifyEmail(String email, String code) async {
    final result = await api.verifyEmail(email, code);
    if (result.user != null) user = result.user;
    if (result.sessionCreated) {
      await _loadSessionData();
      _phase = result.onboardingRequired || context == null ? AuthPhase.onboarding : AuthPhase.ready;
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
    await _loadSessionData();
    _phase = AuthPhase.ready;
    notifyListeners();
    return true;
  }

  Future<void> completeOnboarding() async {
    await _loadSessionData();
    _phase = AuthPhase.ready;
    notifyListeners();
  }

  Future<void> logout() async {
    await api.logout();
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

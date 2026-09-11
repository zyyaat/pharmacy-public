import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/session_store.dart';
import '../core/strings.dart';
import '../models/models.dart';

/// حالات الجلسة — مطابقة لمنطق حارس (dashboard)/layout.tsx وverify-email في الويب:
/// boot ← جلسة سابقة؟ (me) → onboarding_required؟ المعالج : اللوحة، وإلا دخول.
enum AuthPhase { boot, anonymous, unverified, onboarding, ready }

class AuthProvider extends ChangeNotifier {
  final ApiClient api = ApiClient.instance;
  final SessionStore store = SessionStore();

  AuthPhase phase = AuthPhase.boot;
  User? user;

  /// بريد مرحلة التحقق (من التسجيل أو من EMAIL_NOT_VERIFIED عند الدخول)
  String pendingEmail = '';
  bool verificationSent = false;

  Future<void> boot() async {
    phase = AuthPhase.boot;
    notifyListeners();
    try {
      await api.applyServerUrl(await store.serverOverride());
    } catch (_) {}
    try {
      user = await api.me();
      _decide();
    } catch (_) {
      user = null;
      phase = AuthPhase.anonymous;
    }
    notifyListeners();
  }

  void _decide() {
    if (user != null && user!.onboardingRequired) {
      phase = AuthPhase.onboarding;
    } else {
      phase = AuthPhase.ready;
    }
  }

  void startVerification(String email, {bool sent = false}) {
    pendingEmail = email.trim();
    verificationSent = sent;
    phase = AuthPhase.unverified;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final u = await api.login(email.trim(), password);
    user = u;
    pendingEmail = u.email;
    _decide();
    notifyListeners();
  }

  /// يعيد true إذا فُتحت الجلسة فعلًا (مطابق لمنطق Task 58 في الويب:
  /// نثق بـ session_created، وإلا نفحص /me احتياطًا قبل أي استسلام).
  Future<bool> confirmVerification(String code) async {
    final r = await api.verifyEmail(pendingEmail, code);
    if (r.sessionCreated) {
      if (r.user != null) user = r.user;
      if (user == null) {
        try {
          user = await api.me();
        } catch (_) {}
      }
      _decide();
      notifyListeners();
      return true;
    }
    try {
      user = await api.me();
      _decide();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<OnboardingState> loadOnboarding() => api.getOnboarding();

  Future<void> completeOnboarding(OnboardingProfile profile) async {
    await api.updateOnboarding(profile.toUpdatePayload(complete: true));
    try {
      user = await api.me();
    } catch (_) {}
    phase = AuthPhase.ready;
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } catch (_) {}
    user = null;
    pendingEmail = '';
    phase = AuthPhase.anonymous;
    notifyListeners();
  }

  /// تجاوز عنوان الخادم من داخل التطبيق — يمسح الجلسة ويعيد للدخول
  Future<void> applyServerOverride(String? url) async {
    await store.setServerOverride(url);
    await api.applyServerUrl(url);
    user = null;
    phase = AuthPhase.anonymous;
    notifyListeners();
  }
}

class LocaleProvider extends ChangeNotifier {
  LocaleProvider(String initial) : _locale = initial;

  String _locale;
  String get locale => _locale;

  Future<void> set(SessionStore store, String value) async {
    if (_locale == value) return;
    _locale = value;
    notifyListeners();
    try {
      await store.setLocale(value);
    } catch (_) {}
    try {
      // Task 50 — حفظ اللغة على الحساب أيضًا (أفضل جهد؛ تفشل بصمت عند غياب جلسة)
      await ApiClient.instance.setLocale(value);
    } catch (_) {}
  }
}

// ------------------------------------------------------------ وصول الترجمة

extension TrContext on BuildContext {
  String _locale() =>
      Provider.of<LocaleProvider>(this, listen: false).locale;

  String tr(String key) => trFor(_locale(), key);

  String trF(String key, Map<String, String> vars) =>
      trFmt(_locale(), key, vars);
}

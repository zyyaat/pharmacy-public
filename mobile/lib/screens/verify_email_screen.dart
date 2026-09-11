import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// Task 62 — التحقق من البريد بنسخة الويب حرفيًا: بطاقة مركزية rounded-3xl
/// ظل 2xl فيها أيقونة 64 rounded-2xl تتنقل ألوانها حسب الحالة، اسم العلامة
/// بلون الهوية، عنوان 2xl، حقل رمز h-14 بخط 2xl بتباعد 0.6em، زر تحقق h-12
/// بظل الهوية، زر إعادة إرسال نصي، وزر رجوع محدد h-11.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _code = TextEditingController();
  bool _verifying = false;
  bool _resending = false;
  bool _verified = false;
  String? _error;
  String? _message;
  bool _sent = false;
  // الويب: error=true يلوّن الرسالة بالأحمر ويحوّل الأيقونة إلى '!' فقط —
  // هنا نفس الدور للرسالة المركزية (الرموز من الخادم تظهر كسطر خطأ مستقل _error).
  bool _messageIsError = false;
  // امتصاص arguments الواردة + الإعادة التلقائية للإرسال — مرة واحدة فقط
  // حتى لا تتكرر مع نداءات didChangeDependencies اللاحقة (ثيم/الخ).
  bool _entryHandled = false;

  @override
  void initState() {
    super.initState();
    final pending = context.read<AppState>().pendingVerifyEmail;
    if (pending != null && pending.isNotEmpty) _email.text = pending;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entryHandled) return;
    _entryHandled = true;
    // Task 68-f — نظير ?sent=1|0 في الويب (register/page.tsx:122-125):
    // true = جاءنا من التسجيل ورمزٌ أُرسل للتو، false = فشل الإرسال عند إنشاء
    // الحساب، غائب = مسار تسجيل الدخول/مباشر فيُفترض الإرسال ويعاد إرساله تلقائيًا.
    final args = ModalRoute.of(context)?.settings.arguments;
    final bool? sentOnCreate = args is bool ? args : null;
    if (sentOnCreate == true) {
      _sent = true;
      _message = AppI18n.instance.t('auth', 'verify_code_sent');
    } else if (sentOnCreate == false) {
      _message = AppI18n.instance.t('auth', 'verify_send_failed_on_create');
      _messageIsError = true;
    }
    // Task 68-f — الإعادة التلقائية للإرسال عند الوصول ببريد معبأ
    // (الويب verify-email/page.tsx:56-76) إلا إذا وصلنا برمزٍ أُرسل للتو (sent=1).
    if (_email.text.trim().isNotEmpty && sentOnCreate != true) {
      unawaited(_resend());
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final i18n = AppI18n.instance;
    if (_verifying) return;
    // Task 68-f — تحقق عميل مثل الويب (verify-email/page.tsx:85-94):
    // 6 أرقام بالضبط وإلا رسالة verify_default_message بلون الخطأ، ثم فحص البريد.
    final code = _code.text.trim();
    if (code.length != 6 || !RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _message = i18n.t('auth', 'verify_default_message');
        _messageIsError = true;
        _error = null;
      });
      return;
    }
    if (_email.text.trim().isEmpty) {
      setState(() {
        _message = i18n.t('auth', 'verify_email_first');
        _messageIsError = true;
        _error = null;
      });
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
      _message = null;
      _messageIsError = false;
    });
    final state = context.read<AppState>();
    try {
      final result = await state.verifyEmail(_email.text.trim(), code);
      if (!mounted) return;
      if (result.sessionCreated) {
        // Task 68-f — الويب يوجّه إلى /onboarding عندما يطلب الخادم المعالج
        // (verify-email/page.tsx:108) بدل /home دائمًا.
        final onboarding =
            result.onboardingRequired || state.phase == AuthPhase.onboarding;
        setState(() {
          _verified = true;
          _message = onboarding
              ? i18n.t('auth', 'verify_success_onboarding')
              : i18n.t('auth', 'verify_success_login');
        });
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, onboarding ? '/onboarding' : '/home');
        return;
      }
      // خادم قديم: نجاح التحقق بلا جلسة — نجرّب /me فعلًا قبل التسليم (Task 58)
      final probe = await state.probeSessionAfterVerify();
      if (!mounted) return;
      if (probe) {
        // الويب يقرأ onboarding_required من مستخدم /me (page.tsx:115-122)؛
        // نموذج المستخدم بالموبايل لا يحمل الحقل فأقرب إشارة مكافئة
        // (نفس مهلّة boot) هو فراغ اسم الصيدلية في السياق.
        final onboarding =
            state.context != null && state.context!.pharmacyName.isEmpty;
        setState(() {
          _verified = true;
          _message = onboarding
              ? i18n.t('auth', 'verify_success_onboarding')
              : i18n.t('auth', 'verify_success_login');
        });
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, onboarding ? '/onboarding' : '/home');
        return;
      }
      setState(() {
        _message = i18n.t('auth', 'verify_verified_but_session_missing');
        _error = null;
      });
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('auth', 'verify_failed'));
        _verifying = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = i18n.t('auth', 'verify_failed');
        _verifying = false;
      });
    }
  }

  Future<void> _resend() async {
    final i18n = AppI18n.instance;
    if (_resending || _email.text.trim().isEmpty) return;
    // الويب: setError(false)+setSent(false) عند البدء والرسالة القائمة تبقى ظاهرة
    setState(() {
      _resending = true;
      _error = null;
      _sent = false;
      _messageIsError = false;
    });
    try {
      // Task 68-f — علم الإرسال: sent=false ⇒ الرمز السابق ما زال صالحًا
      // (الويب verify-email/page.tsx:149-151 يعرض verify_code_exists).
      final sent = await ApiClient.instance.resendVerification(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _sent = sent;
        _message = sent
            ? i18n.t('auth', 'verify_code_sent')
            : i18n.t('auth', 'verify_code_exists');
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = AppI18n.instance.error(e.code, i18n.t('auth', 'verify_resend_failed')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = i18n.t('auth', 'verify_resend_failed'));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final successFg = dark ? AppColors.successFgDark : AppColors.successFg;
    // لون الأيقونة: نجاح → مصمتة بأبيض، خطأ → destructive/10، عادي → primary/10
    final Color iconBg;
    final Color iconFg;
    final String iconChar;
    if (_verified) {
      iconBg = theme.colorScheme.primary;
      iconFg = theme.colorScheme.onPrimary;
      iconChar = '✓';
    } else if (_error != null || _messageIsError) {
      iconBg = theme.colorScheme.error.withOpacity(0.10);
      iconFg = theme.colorScheme.error;
      iconChar = '!';
    } else {
      iconBg = theme.colorScheme.primary.withOpacity(0.10);
      iconFg = theme.colorScheme.primary;
      iconChar = '✓';
    }
    return AuthShell(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 512), // max-w-lg
            child: Container(
              padding: const EdgeInsets.all(32), // p-8
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: AppRadius.br3xl,
                border: Border.all(color: theme.dividerColor),
                boxShadow: WebShadow.xl2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // أيقونة الحالة
                  Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 64,
                      height: 64,
                      curve: Curves.easeOutBack,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: iconBg,
                        borderRadius: AppRadius.brXl,
                        boxShadow: _verified ? WebShadow.primaryGlow(theme.colorScheme.primary) : null,
                      ),
                      child: Text(
                        iconChar,
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: iconFg),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Pharmacy OS', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: theme.colorScheme.primary)),
                  const SizedBox(height: 12),
                  Text(i18n.t('auth', 'verify_heading'), textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.4)),
                  const SizedBox(height: 12),
                  Text(
                    _message ?? i18n.t('auth', 'verify_default_message'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: _error != null || _messageIsError
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurface.withOpacity(0.55),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // البريد
                  Text(i18n.t('auth', 'email'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  AuthInput(controller: _email, keyboard: TextInputType.emailAddress, ltr: true, hint: 'name@pharmacy.com'),
                  const SizedBox(height: 16),

                  // الرمز: h-14 بخط 2xl وتباعد واسع — Task 68-f: أرقام فقط وبحد
                  // 6 خانات مثل الويب (maxLength=6 + تنظيف onChange في page.tsx:201)
                  Text(i18n.t('auth', 'code_label'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  AuthInput(
                    controller: _code,
                    keyboard: TextInputType.number,
                    centered: true,
                    ltr: true,
                    height: 56,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    onChanged: (value) {
                      final digits = value.replaceAll(RegExp(r'\D'), '');
                      final clamped = digits.length > 6 ? digits.substring(0, 6) : digits;
                      if (clamped == value) return;
                      _code.value = TextEditingValue(
                        text: clamped,
                        selection: TextSelection.collapsed(offset: clamped.length),
                        composing: TextRange.empty,
                      );
                    },
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(fontSize: 14, color: theme.colorScheme.error), textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 16),

                  WButton(
                    _verifying ? i18n.t('auth', 'verifying') : i18n.t('auth', 'verify_button'),
                    onPressed: _verifying ? null : _verify,
                    loading: _verifying,
                    size: WButtonSize.xl,
                    glow: true,
                  ),

                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _resending ? null : _resend,
                    child: Text(
                      _resending ? i18n.t('auth', 'sending_code') : i18n.t('auth', 'resend_button'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _email.text.trim().isEmpty
                            ? theme.colorScheme.onSurface.withOpacity(0.4)
                            : theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  if (_sent) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(i18n.t('auth', 'check_inbox'), textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: successFg)),
                  ],

                  const SizedBox(height: 32),
                  // رجوع لتسجيل الدخول: h-11 rounded-xl border px-6
                  Center(
                    child: WButton(
                      i18n.t('auth', 'back_to_login'),
                      onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
                      variant: WButtonVariant.outline,
                      size: WButtonSize.lg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

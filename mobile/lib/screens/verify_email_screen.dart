import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// التحقق من البريد (OTP) — نفس سلوك صفحة verify-email في الويب:
/// رمز 6 أرقام، جلسة فورية عند النجاح → المعالج أو اللوحة، وعند خادم
/// قديم بلا session_created نجرّب /me قبل أي استسلام (تقسية Task 58).
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
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    final pending = context.read<AppState>().pendingVerifyEmail;
    if (pending != null && pending.isNotEmpty) _email.text = pending;
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
    setState(() {
      _verifying = true;
      _error = null;
      _message = null;
    });
    final state = context.read<AppState>();
    try {
      final result = await state.verifyEmail(_email.text.trim(), _code.text.trim());
      if (!mounted) return;
      if (result.sessionCreated) {
        setState(() => _message = result.onboardingRequired
            ? i18n.t('auth', 'verify_success_onboarding')
            : i18n.t('auth', 'verify_success_login'));
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/home');
        return;
      }
      // خادم قديم: نجاح التحقق بلا جلسة — نجرّب /me فعلًا قبل التسليم
      final probe = await state.probeSessionAfterVerify();
      if (!mounted) return;
      if (probe) {
        setState(() => _message = i18n.t('auth', 'verify_success_login'));
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/home');
        return;
      }
      setState(() {
        _message = i18n.t('auth', 'verify_verified_but_session_missing');
        _error = null;
      });
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.pushReplacementNamed('/login');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('auth', 'verify_failed'));
        _verifying = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.t('auth', 'verify_failed');
        _verifying = false;
      });
    }
  }

  Future<void> _resend() async {
    final i18n = AppI18n.instance;
    if (_resending) return;
    setState(() {
      _resending = true;
      _error = null;
      _message = null;
    });
    try {
      await ApiClient.instance.resendVerification(_email.text.trim());
      if (!mounted) return;
      setState(() => _message = i18n.t('auth', 'verify_code_sent'));
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
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('auth', 'verify_heading'))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.mark_email_read_outlined, size: 28, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(height: 14),
                    Text(i18n.t('auth', 'verify_heading'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(i18n.t('auth', 'verify_default_message'),
                        style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                    const SizedBox(height: 16),
                    Text(i18n.t('auth', 'email'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    AppInput(controller: _email, keyboard: TextInputType.emailAddress),
                    const SizedBox(height: 12),
                    Text(i18n.t('auth', 'code_label'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, letterSpacing: 10, fontWeight: FontWeight.w800),
                      decoration: InputDecoration(counterText: '', hintText: '••••••'),
                    ),
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: 10),
                      Text(_error!, style: TextStyle(fontSize: 12, color: theme.colorScheme.error), textAlign: TextAlign.center),
                    ],
                    if (_message != null) ...<Widget>[
                      const SizedBox(height: 10),
                      Text(_message!, style: TextStyle(fontSize: 12, color: AppColors.successFg, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 16),
                    PrimaryButton(i18n.t('auth', 'verify_button'), loading: _verifying, onPressed: _verify),
                    const SizedBox(height: 8),
                    SecondaryButton(i18n.t('auth', 'resend_button'), icon: Icons.refresh, onPressed: _resending ? null : _resend),
                    const SizedBox(height: 10),
                    Text(i18n.t('auth', 'check_inbox'), textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                    TextButton(
                      onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
                      child: Text(i18n.t('auth', 'back_to_login'), style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

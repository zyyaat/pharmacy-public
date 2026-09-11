import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// تأكيد البريد برمز OTP — بعد النجاح الجلسة تكون مفتوحة من الباك اند مباشرة
/// (Task 57) فنتوجه للمعالج أو اللوحة دون مطالبة بكلمة مرور ثانية.
/// إن لم تُفتح الجلسة (خادم قديم) نعيد المستخدم للدخول برسالة هادئة (Task 58).
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _code = TextEditingController();
  bool _loading = false;
  bool _resending = false;
  String? _error;
  String? _notice;
  int _resendIn = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    // لو جاءنا من التسجيل فالرمز أُرسل للتو — نبدأ عدّاد الإعادة فقط
    if (auth.verificationSent) _startCooldown(30);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _resendIn = seconds;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _resendIn -= 1;
        if (_resendIn <= 0) t.cancel();
      });
    });
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (code.length != AppConfig.otpLength) return;
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    final auth = context.read<AuthProvider>();
    try {
      final opened = await auth.confirmVerification(code);
      if (!mounted) return;
      if (opened) {
        _notice = auth.phase == AuthPhase.onboarding
            ? context.tr('verify_success_onboarding')
            : context.tr('verify_success_home');
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        Navigator.pushReplacementNamed(
          context,
          auth.phase == AuthPhase.onboarding ? '/onboarding' : '/home',
        );
      } else {
        setState(() {
          _notice = context.tr('verify_fallback_login');
          _loading = false;
        });
        await Future<void>.delayed(const Duration(milliseconds: 1600));
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(context, e);
        _loading = false;
      });
    }
  }

  Future<void> _resend() async {
    if (_resending || _resendIn > 0) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await auth.api.resendVerification(auth.pendingEmail);
      _startCooldown(30);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(context, e));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
    messenger.hideCurrentSnackBar();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final email = auth.pendingEmail;
    return Scaffold(
      body: AuthShell(
        title: context.tr('verify_title'),
        subtitle: context.trF('verify_subtext', <String, String>{'email': email}),
        children: [
          TextFormField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: AppConfig.otpLength,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 26, letterSpacing: 12, fontWeight: FontWeight.w700),
            decoration: appInputDecoration(context, context.tr('verify_code')).copyWith(
              counterText: '',
            ),
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 18),
          if (_error != null) ...[
            ErrorBox(message: _error!),
            const SizedBox(height: 14),
          ],
          if (_notice != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kBrandSeed.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _notice!,
                textAlign: TextAlign.center,
                style: TextStyle(color: kBrandSeed, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 14),
          ],
          PrimaryButton(
            label: _loading ? context.tr('verifying') : context.tr('verify_btn'),
            loading: _loading,
            onPressed: _submit,
          ),
          const SizedBox(height: 14),
          Center(
            child: _resendIn > 0
                ? Text(
                    context.trF('resend_in', <String, String>{'n': '$_resendIn'}),
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : TextButton.icon(
                    onPressed: _resending ? null : _resend,
                    icon: _resending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(context.tr('resend')),
                  ),
          ),
        ],
      ),
    );
  }
}

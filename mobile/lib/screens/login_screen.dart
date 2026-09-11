import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// تسجيل الدخول — تصميم صفحة الويب: بطاقة مركزية بعنوان الترحيب
/// ونفس التسميات (auth.json). EMAIL_NOT_VERIFIED → شاشة التحقق.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final i18n = AppI18n.instance;
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AppState>().login(_email.text.trim(), _password.text);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.emailNotVerified) {
        context.read<AppState>().pendingVerifyEmail = _email.text.trim();
        Navigator.pushNamed(context, '/verify');
        return;
      }
      setState(() {
        _error = e.isNetwork ? i18n.error(e.code) : i18n.t('auth', 'login_failed');
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.t('auth', 'login_failed');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final pending = context.watch<AppState>().pendingVerifyEmail;
    final args = ModalRoute.of(context)?.settings.arguments;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.local_pharmacy, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 10),
                      const Text('Pharmacy OS', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(i18n.t('auth', 'brand_tagline'), textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                  const SizedBox(height: 24),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(i18n.t('auth', 'login_heading'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(i18n.t('auth', 'login_subtext'),
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                        const SizedBox(height: 16),
                        if (pending != null && pending.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: AppCard(
                              padding: const EdgeInsets.all(10),
                              color: AppColors.successBg,
                              child: Text(i18n.t('auth', 'login_after_verified'),
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        if (args is String && args.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: AppCard(
                              padding: const EdgeInsets.all(10),
                              color: AppColors.successBg,
                              child: Text(i18n.t('auth', 'login_after_verified'),
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        Text(i18n.t('auth', 'email'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        AppInput(controller: _email, keyboard: TextInputType.emailAddress),
                        const SizedBox(height: 12),
                        Text(i18n.t('auth', 'password'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        AppInput(controller: _password, obscure: true),
                        if (_error != null) ...<Widget>[
                          const SizedBox(height: 12),
                          Text(_error!, style: TextStyle(fontSize: 12, color: theme.colorScheme.error), textAlign: TextAlign.center),
                        ],
                        const SizedBox(height: 16),
                        PrimaryButton(i18n.t('auth', 'login_label'), loading: _loading, onPressed: _submit),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(i18n.t('auth', 'no_account'), style: const TextStyle(fontSize: 13)),
                      TextButton(
                        onPressed: () => Navigator.pushNamed(context, '/register'),
                        child: Text(i18n.t('auth', 'create_account_link'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  Text(
                    i18n.t('auth', 'need_help'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.45)),
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

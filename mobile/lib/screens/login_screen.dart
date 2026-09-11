import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// Task 62 — تسجيل الدخول بنسخة الويب حرفيًا: بطاقة rounded-3xl ظل 2xl فوق
/// خلفية بدوائر ضبابية، شعار العلامة، تسمية أولية بلون الهوية، حقول h-12
/// rounded-xl بتركيز ring-4، وزر h-12 بظل primary/20.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _loading = false;
  bool _remember = false;
  String? _notice;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _absorbArguments() {
    final args = ModalRoute.of(context)?.settings.arguments;
    final pending = context.read<AppState>().pendingVerifyEmail;
    final i18n = AppI18n.instance;
    final from = (args is String && args.isNotEmpty) ? args : (pending ?? '');
    if (from.isNotEmpty && _email.text.isEmpty) {
      _email.text = from; // تعبئة البريد بعد العودة من التحقق (مثل ?email= في الويب)
    }
    if (from.isNotEmpty) {
      _notice = i18n.t('auth', 'login_after_verified');
      context.read<AppState>().pendingVerifyEmail = null;
    }
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
    final dark = theme.brightness == Brightness.dark;
    _absorbArguments();
    return AuthShell(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Container(
              padding: const EdgeInsets.all(28), // p-7
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: AppRadius.br3xl, // rounded-3xl
                border: Border.all(color: theme.dividerColor),
                boxShadow: WebShadow.xl2, // shadow-2xl
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // الشعار + السطر التعريفي (نسخة الجوال في الويب)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: BrandLogo(height: 40, dark: dark),
                  ),
                  const SizedBox(height: 8),
                  Text(i18n.t('auth', 'mobile_tagline'),
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                  const SizedBox(height: 40), // mb-10

                  Text(i18n.t('auth', 'login_label'),
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: theme.colorScheme.primary)),
                  const SizedBox(height: 8),
                  Text(i18n.t('auth', 'login_heading'),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(i18n.t('auth', 'login_subtext'),
                      style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                  const SizedBox(height: 32), // mt-8

                  if (_notice != null) ...<Widget>[
                    NoticeBanner(_notice!),
                    const SizedBox(height: 20),
                  ],
                  if (_error != null) ...<Widget>[
                    FormErrorBanner(_error!),
                    const SizedBox(height: 20),
                  ],

                  // البريد
                  Text(i18n.t('auth', 'email'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  AuthInput(
                    controller: _email,
                    keyboard: TextInputType.emailAddress,
                    ltr: true,
                    hint: 'name@pharmacy.com',
                  ),
                  const SizedBox(height: 20),

                  // كلمة المرور + نسيت كلمة المرور
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(i18n.t('auth', 'password'),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      ),
                      Text(i18n.t('auth', 'forgot_password'),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: theme.colorScheme.primary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  AuthInput(controller: _password, obscure: true, ltr: true, hint: '••••••••'),
                  const SizedBox(height: 20),

                  // تذكرني
                  InkWell(
                    borderRadius: AppRadius.brSm,
                    onTap: () => setState(() => _remember = !_remember),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: <Widget>[
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: Checkbox(value: _remember, onChanged: (v) => setState(() => _remember = v ?? false)),
                          ),
                          const SizedBox(width: 8),
                          Text(i18n.t('auth', 'remember_me'),
                              style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // زر الدخول: h-12 rounded-xl shadow-lg shadow-primary/20
                  WButton(
                    _loading ? i18n.t('auth', 'logging_in') : i18n.t('auth', 'login_label'),
                    onPressed: _loading ? null : _submit,
                    loading: _loading,
                    size: WButtonSize.xl,
                    glow: true,
                  ),

                  const SizedBox(height: 24), // mt-6
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(i18n.t('auth', 'no_account'), style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => Navigator.pushNamed(context, '/register'),
                        child: Text(i18n.t('auth', 'create_account_link'),
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: theme.colorScheme.primary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32), // mt-8
                  Text(
                    i18n.t('auth', 'need_help'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.45)),
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

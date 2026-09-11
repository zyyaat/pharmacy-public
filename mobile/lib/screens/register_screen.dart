import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// Task 62 — التسجيل بنسخة الويب حرفيًا: معالج 4 أسئلة، شريط علوي فيه
/// الشعار + «خطوة X من 4» + شريط تقدم h-1.5، بطاقة rounded-3xl ظل 2xl بحقول
/// h-14 rounded-2xl، زر متابعة flex-1 h-13 بظل primary/20 وزر رجوع محدد.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _pharmacyName = TextEditingController();
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();
  final TextEditingController _pharmacyEmail = TextEditingController();
  final TextEditingController _ownerEmail = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  int _step = 1;
  bool _loading = false;
  String? _error;

  static final RegExp _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  void dispose() {
    for (final c in <TextEditingController>[
      _pharmacyName, _firstName, _lastName, _pharmacyEmail, _ownerEmail, _password, _confirm,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _validateStep(int step) {
    final i18n = AppI18n.instance;
    String? problem;
    switch (step) {
      case 1:
        if (_pharmacyName.text.trim().length < 2) problem = i18n.t('auth', 'reg_err_name');
      case 2:
        if (_firstName.text.trim().isEmpty) problem = i18n.t('auth', 'reg_err_first');
        if (problem == null && _lastName.text.trim().isEmpty) problem = i18n.t('auth', 'reg_err_last');
      case 3:
        if (!_emailRe.hasMatch(_pharmacyEmail.text.trim())) problem = i18n.t('auth', 'reg_err_email');
        if (problem == null && !_emailRe.hasMatch(_ownerEmail.text.trim())) problem = i18n.t('auth', 'reg_err_email');
      case 4:
        if (_password.text != _confirm.text) problem = i18n.t('auth', 'password_mismatch');
        else if (_password.text.length < 10) problem = i18n.t('auth', 'password_hint');
    }
    if (problem != null) {
      setState(() => _error = problem);
      return false;
    }
    setState(() => _error = null);
    return true;
  }

  Future<void> _next() async {
    final i18n = AppI18n.instance;
    if (_step < 4) {
      if (!_validateStep(_step)) return;
      setState(() => _step += 1);
      return;
    }
    if (!_validateStep(4) || !_validateStep(3) || !_validateStep(2) || !_validateStep(1)) return;
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AppState>().register(
            companyName: _pharmacyName.text.trim(),
            companyEmail: (_pharmacyEmail.text.trim().isNotEmpty
                    ? _pharmacyEmail.text.trim()
                    : _ownerEmail.text.trim())
                .toLowerCase(),
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
            email: _ownerEmail.text.trim().toLowerCase(),
            password: _password.text,
          );
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/verify');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('auth', 'register_failed'));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.t('auth', 'register_failed');
        _loading = false;
      });
    }
  }

  void _back() {
    if (_step > 1) {
      setState(() {
        _step -= 1;
        _error = null;
      });
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return AuthShell(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 576), // max-w-xl
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // الشريط العلوي: الهوية + شريط التقدم بأسلوب Upwork
                Row(
                  children: <Widget>[
                    BrandLogo(height: 36, dark: dark),
                    const Spacer(),
                    Text('${i18n.t('auth', 'reg_step')} $_step ${i18n.t('auth', 'reg_of')} 4',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                    const SizedBox(width: 12),
                    ProgressTrack(value: _step / 4),
                  ],
                ),
                const SizedBox(height: 24),

                // بطاقة الخطوة الواحدة
                Container(
                  padding: const EdgeInsets.all(28), // p-7
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: AppRadius.br3xl,
                    border: Border.all(color: theme.dividerColor),
                    boxShadow: WebShadow.xl2,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300), // animate-fade-in
                    child: Column(
                      key: ValueKey<int>(_step),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(_stepTitle(i18n),
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.4)),
                        const SizedBox(height: 12),
                        Text(_stepSub(i18n),
                            style: TextStyle(fontSize: 14, height: 1.6, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                        const SizedBox(height: 32),
                        if (_error != null) ...<Widget>[
                          FormErrorBanner(_error!),
                          const SizedBox(height: 20),
                        ],
                        _buildStepFields(i18n),
                        const SizedBox(height: 24),
                        Row(
                          children: <Widget>[
                            if (_step > 1) ...<Widget>[
                              WButton(i18n.t('auth', 'reg_back'),
                                  onPressed: _back,
                                  variant: WButtonVariant.outline,
                                  size: WButtonSize.wizard),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: WButton(
                                _step == 4
                                    ? (_loading ? i18n.t('auth', 'creating_account') : i18n.t('auth', 'create_and_start'))
                                    : i18n.t('auth', 'reg_continue'),
                                onPressed: _loading ? null : _next,
                                loading: _loading,
                                size: WButtonSize.wizard,
                                glow: true,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(i18n.t('auth', 'have_account'), style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => Navigator.pushReplacementNamed(context, '/login'),
                      child: Text(i18n.t('auth', 'login_label'),
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: theme.colorScheme.primary)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _stepTitle(AppI18n i18n) {
    switch (_step) {
      case 1:
        return i18n.t('auth', 'reg_q1_title');
      case 2:
        return i18n.t('auth', 'reg_q2_title');
      case 3:
        return i18n.t('auth', 'reg_q3_title');
      default:
        return i18n.t('auth', 'reg_q4_title');
    }
  }

  String _stepSub(AppI18n i18n) {
    switch (_step) {
      case 1:
        return i18n.t('auth', 'reg_q1_sub');
      case 2:
        return i18n.t('auth', 'reg_q2_sub');
      case 3:
        return i18n.t('auth', 'reg_q3_sub');
      default:
        return i18n.t('auth', 'reg_q4_sub');
    }
  }

  Widget _buildStepFields(AppI18n i18n) {
    final theme = Theme.of(context);
    switch (_step) {
      case 1:
        return WizardInput(controller: _pharmacyName, hint: i18n.t('auth', 'pharmacy_name_ph'));
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppField(label: i18n.t('auth', 'first_name'),
                child: WizardInput(controller: _firstName, hint: i18n.t('auth', 'first_name_ph'))),
            const SizedBox(height: 20),
            AppField(label: i18n.t('auth', 'last_name'),
                child: WizardInput(controller: _lastName, hint: i18n.t('auth', 'last_name_ph'))),
          ],
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppField(
              label: i18n.t('auth', 'pharmacy_email'),
              hint: i18n.t('auth', 'reg_email_pharmacy_hint'),
              child: WizardInput(controller: _pharmacyEmail, keyboard: TextInputType.emailAddress, ltr: true, hint: 'pharmacy@example.com'),
            ),
            const SizedBox(height: 20),
            AppField(
              label: i18n.t('auth', 'owner_email'),
              hint: i18n.t('auth', 'reg_email_owner_hint'),
              child: WizardInput(controller: _ownerEmail, keyboard: TextInputType.emailAddress, ltr: true, hint: 'owner@example.com'),
            ),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppField(label: i18n.t('auth', 'password'),
                child: WizardInput(controller: _password, obscure: true, ltr: true, hint: i18n.t('auth', 'password_ph'))),
            const SizedBox(height: 20),
            AppField(label: i18n.t('auth', 'confirm_password'),
                child: WizardInput(controller: _confirm, obscure: true, ltr: true, hint: i18n.t('auth', 'confirm_password_ph'))),
            const SizedBox(height: 8),
            Text(i18n.t('auth', 'password_hint'),
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5))),
          ],
        );
    }
  }
}

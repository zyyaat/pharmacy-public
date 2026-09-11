import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/strings.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// التسجيل — معالج 4 أسئلة بأسلوب الويب (reg_*): اسم الصيدلية ← الاسم
/// الشخصي ← البريدان ← كلمة المرور، ثم شاشة التحقق من البريد.
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

  @override
  void dispose() {
    for (final c in <TextEditingController>[
      _pharmacyName, _firstName, _lastName, _pharmacyEmail, _ownerEmail, _password, _confirm,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _validateStep() {
    final i18n = AppI18n.instance;
    switch (_step) {
      case 1:
        if (_pharmacyName.text.trim().length < 2) {
          setState(() => _error = i18n.t('auth', 'reg_err_name'));
          return false;
        }
      case 2:
        if (_firstName.text.trim().isEmpty) {
          setState(() => _error = i18n.t('auth', 'reg_err_first'));
          return false;
        }
        if (_lastName.text.trim().isEmpty) {
          setState(() => _error = i18n.t('auth', 'reg_err_last'));
          return false;
        }
      case 3:
        final owner = _ownerEmail.text.trim();
        if (owner.isEmpty || !owner.contains('@')) {
          setState(() => _error = i18n.t('auth', 'reg_err_email'));
          return false;
        }
    }
    setState(() => _error = null);
    return true;
  }

  Future<void> _next() async {
    final i18n = AppI18n.instance;
    if (_step < 4) {
      if (!_validateStep()) return;
      setState(() {
        _step += 1;
        _error = null;
      });
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = i18n.t('auth', 'password_mismatch'));
      return;
    }
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
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n.t('auth', 'register_tagline')),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text('${i18n.t('auth', 'reg_step')} $_step ${i18n.t('auth', 'reg_of')} 4',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: _step / 4,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(2),
                    backgroundColor: theme.dividerColor,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 18),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(_stepTitle(i18n), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(_stepSub(i18n), style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                        const SizedBox(height: 16),
                        _buildStepFields(i18n),
                        if (_error != null) ...<Widget>[
                          const SizedBox(height: 12),
                          Text(_error!, style: TextStyle(fontSize: 12, color: theme.colorScheme.error), textAlign: TextAlign.center),
                        ],
                        const SizedBox(height: 16),
                        PrimaryButton(
                          _step == 4 ? i18n.t('auth', 'create_and_start') : i18n.t('auth', 'reg_continue'),
                          loading: _loading,
                          onPressed: _next,
                        ),
                        if (_step > 1) ...<Widget>[
                          const SizedBox(height: 6),
                          SecondaryButton(i18n.t('auth', 'reg_back'), onPressed: _back),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(i18n.t('auth', 'have_account'), style: const TextStyle(fontSize: 13)),
                      TextButton(
                        onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
                        child: Text(i18n.t('auth', 'login_label'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ],
              ),
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
    switch (_step) {
      case 1:
        return AppInput(controller: _pharmacyName, hint: i18n.t('auth', 'pharmacy_name_ph'));
      case 2:
        return Column(
          children: <Widget>[
            AppInput(controller: _firstName, hint: i18n.t('auth', 'first_name_ph')),
            const SizedBox(height: 10),
            AppInput(controller: _lastName, hint: i18n.t('auth', 'last_name_ph')),
          ],
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(i18n.t('auth', 'pharmacy_email'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            AppInput(controller: _pharmacyEmail, keyboard: TextInputType.emailAddress),
            const SizedBox(height: 4),
            Text(i18n.t('auth', 'reg_email_pharmacy_hint'),
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
            const SizedBox(height: 10),
            Text(i18n.t('auth', 'owner_email'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            AppInput(controller: _ownerEmail, keyboard: TextInputType.emailAddress),
            const SizedBox(height: 4),
            Text(i18n.t('auth', 'reg_email_owner_hint'),
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
          ],
        );
      default:
        return Column(
          children: <Widget>[
            AppInput(controller: _password, obscure: true, hint: i18n.t('auth', 'password_ph')),
            const SizedBox(height: 10),
            AppInput(controller: _confirm, obscure: true, hint: i18n.t('auth', 'confirm_password_ph')),
            const SizedBox(height: 8),
            Text(i18n.t('auth', 'password_hint'),
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
          ],
        );
    }
  }
}

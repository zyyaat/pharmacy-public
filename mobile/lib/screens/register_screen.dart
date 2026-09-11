import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/ui.dart';

/// تسجيل حساب صيدلية جديد — نفس نقطة النهاية /auth/register التي يستخدمها
/// معالج الويب (Task 57) وبنفس الحقول، ثم الانتقال لشاشة رمز التحقق.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _companyName = TextEditingController();
  final _companyEmail = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _companyName.dispose();
    _companyEmail.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_companyName.text.trim().length < 2) return context.tr('ob_name_required');
    final emailOk = _email.text.contains('@') && _email.text.contains('.');
    if (!emailOk) return context.tr('server_invalid');
    if (_password.text.length < 8) return context.tr('server_invalid');
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    final email = _email.text.trim();
    try {
      await auth.api.register(
        companyName: _companyName.text.trim(),
        companyEmail: _companyEmail.text.trim(),
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        email: email,
        password: _password.text,
      );
      if (!mounted) return;
      auth.startVerification(email, sent: true);
      Navigator.pushReplacementNamed(context, '/verify');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(context, e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthShell(
        title: context.tr('reg_title'),
        subtitle: context.tr('reg_subtext'),
        children: [
          TextFormField(
            controller: _companyName,
            decoration: appInputDecoration(context, context.tr('reg_company_name'),
                icon: Icons.storefront_rounded),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _companyEmail,
            keyboardType: TextInputType.emailAddress,
            decoration: appInputDecoration(context, context.tr('reg_company_email'),
                icon: Icons.business_center_outlined),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _firstName,
                  decoration:
                      appInputDecoration(context, context.tr('reg_first_name')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _lastName,
                  decoration:
                      appInputDecoration(context, context.tr('reg_last_name')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: appInputDecoration(context, context.tr('reg_email'),
                icon: Icons.alternate_email_rounded),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            obscureText: true,
            decoration: appInputDecoration(context, context.tr('reg_password'),
                icon: Icons.lock_outline_rounded),
          ),
          const SizedBox(height: 18),
          if (_error != null) ...[
            ErrorBox(message: _error!),
            const SizedBox(height: 14),
          ],
          PrimaryButton(
            label: context.tr('reg_submit'),
            loading: _loading,
            onPressed: _submit,
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('back')),
            ),
          ),
        ],
      ),
    );
  }
}

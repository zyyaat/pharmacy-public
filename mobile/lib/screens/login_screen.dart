import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _server = TextEditingController(text: ApiClient.instance.baseUrl);
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    try {
      await auth.login(_email.text, _password.text);
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        auth.phase == AuthPhase.onboarding ? '/onboarding' : '/home',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.emailNotVerified) {
        auth.startVerification(_email.text.trim());
        Navigator.pushReplacementNamed(context, '/verify');
        return;
      }
      setState(() {
        _error = friendlyError(context, e);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(context, e);
        _loading = false;
      });
    }
  }

  Future<void> _saveServer() async {
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final savedText = context.tr('settings_server_saved');
    await auth.applyServerOverride(_server.text.trim());
    messenger.showSnackBar(SnackBar(content: Text(savedText)));
    if (!mounted) return;
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthShell(
        title: context.tr('login_title'),
        subtitle: context.tr('login_subtext'),
        children: [
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: appInputDecoration(context, context.tr('email'),
                icon: Icons.alternate_email_rounded),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _password,
            obscureText: true,
            onFieldSubmitted: (_) => _submit(),
            decoration: appInputDecoration(context, context.tr('password'),
                icon: Icons.lock_outline_rounded),
          ),
          const SizedBox(height: 18),
          if (_error != null) ...[
            ErrorBox(message: _error!),
            const SizedBox(height: 14),
          ],
          PrimaryButton(
            label: context.tr('login_btn'),
            loading: _loading,
            onPressed: _submit,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(context.tr('no_account')),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/register'),
                child: Text(context.tr('create_account')),
              ),
            ],
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text(
                context.tr('advanced_server'),
                style: const TextStyle(fontSize: 13),
              ),
              leading: const Icon(Icons.dns_outlined, size: 20),
              children: [
                TextFormField(
                  controller: _server,
                  keyboardType: TextInputType.url,
                  decoration: appInputDecoration(
                      context, context.tr('server_url'), icon: Icons.link),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: _saveServer,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: Text(context.tr('save')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

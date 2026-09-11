import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../state/app_state.dart';
import '../../widgets/ui.dart';

/// الإعدادات: اللغة (ar/en محفوظة محليًا وعلى الحساب)، عنوان الخادم
/// (طبقة الطوارئ الثالثة لمتغيرات البيئة)، وتسجيل الخروج.
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab>
    with AutomaticKeepAliveClientMixin {
  late final TextEditingController _server =
      TextEditingController(text: ApiClient.instance.baseUrl);

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  Future<void> _setLocale(String value) async {
    final lp = context.read<LocaleProvider>();
    final auth = context.read<AuthProvider>();
    await lp.set(auth.store, value);
  }

  Future<void> _saveServer() async {
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final savedText = context.tr('settings_server_saved');
    await auth.applyServerOverride(_server.text.trim());
    messenger.showSnackBar(SnackBar(content: Text(savedText)));
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('settings_logout')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('ok'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('settings_logout'))),
        ],
      ),
    );
    if (confirmed != true) return;
    final auth = context.read<AuthProvider>();
    await auth.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final lp = context.watch<LocaleProvider>();
    final auth = context.watch<AuthProvider>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionCard(
          title: context.tr('settings_language'),
          icon: Icons.translate_rounded,
          child: Column(
            children: [
              RadioListTile<String>(
                value: 'ar',
                groupValue: lp.locale,
                onChanged: (v) => _setLocale(v ?? 'ar'),
                title: Text(context.tr('settings_lang_ar')),
              ),
              RadioListTile<String>(
                value: 'en',
                groupValue: lp.locale,
                onChanged: (v) => _setLocale(v ?? 'en'),
                title: Text(context.tr('settings_lang_en')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          title: context.tr('settings_server'),
          icon: Icons.dns_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _server,
                keyboardType: TextInputType.url,
                decoration:
                    appInputDecoration(context, context.tr('server_url')),
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
        const SizedBox(height: 14),
        _sectionCard(
          title: auth.user?.email ?? '',
          icon: Icons.account_circle_outlined,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout_rounded, color: Color(0xFFDC2626)),
            title: Text(
              context.tr('settings_logout'),
              style: const TextStyle(
                  color: Color(0xFFDC2626), fontWeight: FontWeight.w700),
            ),
            onTap: _logout,
          ),
        ),
        const SizedBox(height: 26),
        Center(
          child: Text(
            '${context.tr('settings_version')} 1.0.0',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        ),
      ],
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: kBrandSeed),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';
import 'settings_import_screen.dart';
import 'settings_receipts_screen.dart';

/// الإعدادات — أقسام الويب نفسها (الفواتير والطباعة، قاعدة البيانات،
/// اللغة، ترحيل المنتجات) + طبقتا الطوارئ للموبايل (عنوان الخادم).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final state = context.watch<AppState>();
    final ctx = state.context;
    final sections = <({IconData icon, String title, String desc, WidgetBuilder builder})>[
      (
        icon: Icons.receipt_outlined,
        title: i18n.t('settings', 'receiptsNavLabel'),
        desc: i18n.t('settings', 'receiptsNavDesc'),
        builder: (_) => const ReceiptsSettingsScreen(),
      ),
      (
        icon: Icons.storage_outlined,
        title: i18n.t('settings', 'databaseNavLabel'),
        desc: i18n.t('settings', 'databaseNavDesc'),
        builder: (_) => const DatabaseSettingsScreen(),
      ),
      (
        icon: Icons.translate,
        title: i18n.t('settings', 'languageNavLabel'),
        desc: i18n.t('settings', 'languageNavDesc'),
        builder: (_) => const LanguageSettingsScreen(),
      ),
      (
        icon: Icons.upload_file_outlined,
        title: i18n.t('settings', 'importNavLabel'),
        desc: i18n.t('settings', 'importNavDesc'),
        builder: (_) => const ImportScreen(),
      ),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        PageHeader(i18n.t('nav', 'settings'), subtitle: i18n.t('settings', 'languageNavDesc')),
        const SizedBox(height: 24),
        // بطاقة معلومات الصيدلية
        AppCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CardTitle(ctx?.pharmacyName ?? i18n.t('pos', 'fallbackPharmacyName')),
              const SizedBox(height: 8),
              KVRow(i18n.t('employees', 'branchCityLabel'), ctx == null || ctx.city.isEmpty || ctx.city == 'غير محدد' ? i18n.t('employees', 'unspecified') : ctx.city),
              KVRow(i18n.t('employees', 'branchPhoneLabel'), ctx == null || ctx.phone.isEmpty ? '—' : ctx.phone),
              KVRow(i18n.t('dashboard', 'total_products'), Fmt.number(ctx?.productCount ?? 0)),
              if (ctx?.branchName != null && ctx!.branchName!.isNotEmpty)
                KVRow(i18n.t('employees', 'thBranch'), ctx.branchName!),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // بطاقة الأقسام
        AppCard(
          child: Column(
            children: <Widget>[
              const SizedBox(height: 8),
              for (final section in sections)
                Column(
                  children: <Widget>[
                    InkWell(
                      borderRadius: AppRadius.br,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: section.builder)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        child: Row(
                          children: <Widget>[
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withOpacity(0.10),
                                borderRadius: AppRadius.brXl,
                              ),
                              alignment: Alignment.center,
                              child: Icon(section.icon, size: 20, color: theme.colorScheme.primary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(section.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text(section.desc, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, size: 20, color: theme.colorScheme.onSurface.withOpacity(0.35)),
                          ],
                        ),
                      ),
                    ),
                    if (section != sections.last)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Divider(height: 1, color: theme.dividerColor),
                      ),
                  ],
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _ServerOverrideCard(),
        const SizedBox(height: 12),
        Center(
          child: Text(
            i18n.t('reports', 'brand_tagline'),
            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.4)),
          ),
        ),
      ],
    );
  }
}

/// طبقة الطوارئ الثالثة: تجاوز عنوان الخادم من داخل التطبيق (Task 59)
class _ServerOverrideCard extends StatefulWidget {
  @override
  State<_ServerOverrideCard> createState() => _ServerOverrideCardState();
}

class _ServerOverrideCardState extends State<_ServerOverrideCard> {
  final TextEditingController _ctrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final override = await context.read<AppState>().serverOverride();
    if (override != null && mounted) _ctrl.text = override;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await context.read<AppState>().applyServerOverride(_ctrl.text.trim());
    if (mounted) {
      setState(() => _saving = false);
      await appSnackbar(context, AppI18n.instance.t('common', 'done'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('عنوان الخادم (تجاوز طوارئ)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('اتركه فارغًا لاستخدام الخادم الافتراضي المدمج',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(child: AppInput(controller: _ctrl, hint: 'https://…/api/v1', keyboard: TextInputType.url)),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                child: const Icon(Icons.save_outlined, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ اللغة

class LanguageSettingsScreen extends StatelessWidget {
  const LanguageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('settings', 'language_title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(i18n.t('settings', 'language_desc'),
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55))),
          const SizedBox(height: 14),
          for (final (String code, String _, String native) in <(String, String, String)>[
            ('ar', 'العربية', 'العربية'),
            ('en', 'English', 'English'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                onTap: () => context.read<AppState>().setLocale(code),
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: <Widget>[
                    Expanded(child: Text(native, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                    if (state.locale == code) Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ قاعدة البيانات

class DatabaseSettingsScreen extends StatefulWidget {
  const DatabaseSettingsScreen({super.key});
  @override
  State<DatabaseSettingsScreen> createState() => _DatabaseSettingsScreenState();
}

class _DatabaseSettingsScreenState extends State<DatabaseSettingsScreen> {
  List<MigrationItem> _migrations = <MigrationItem>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final i18n = AppI18n.instance;
    try {
      final list = await ApiClient.instance.systemMigrations();
      if (!mounted) return;
      setState(() {
        _migrations = list;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('settings', 'migrationsErrorFallback'));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = i18n.t('settings', 'migrationsErrorFallback');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n.t('settings', 'databaseTitle')),
        actions: <Widget>[
          IconButton(icon: const Icon(Icons.refresh, size: 20), tooltip: i18n.t('settings', 'refresh'), onPressed: _load),
        ],
      ),
      body: _loading
          ? const LoadingBox()
          : _error != null
              ? ErrorRetry(_error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          CardTitle(i18n.t('settings', 'schemaStatusTitle'), subtitle: i18n.t('settings', 'schemaStatusDesc')),
                          const SizedBox(height: 10),
                          Row(
                            children: <Widget>[
                              Text(i18n.t('settings', 'schemaVersionLabel'), style: const TextStyle(fontSize: 13)),
                              const Spacer(),
                              AppBadge(
                                _migrations.isEmpty ? '—' : _migrations.first.version,
                                tone: BadgeTone.success,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(i18n.t('settings', 'statusUpToDate'),
                              style: TextStyle(fontSize: 12, color: AppColors.successFg, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text(i18n.t('settings', 'appliedCountLabel') + ': ${Fmt.number(_migrations.length)}',
                              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.6))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SectionHeader(i18n.t('settings', 'historyTitle')),
                    if (_migrations.isEmpty)
                      Text(i18n.t('settings', 'noMigrationsYet'), style: const TextStyle(fontSize: 13))
                    else
                      for (final MigrationItem m in _migrations)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: <Widget>[
                              const Icon(Icons.check_circle_outline, size: 16, color: AppColors.successFg),
                              const SizedBox(width: 8),
                              Expanded(child: Text(m.version, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                              Text(Fmt.dateTime(m.appliedAt, locale: i18n.locale),
                                  style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                            ],
                          ),
                        ),
                  ],
                ),
    );
  }
}

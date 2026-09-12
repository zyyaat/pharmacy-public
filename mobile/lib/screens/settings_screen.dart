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
/// اللغة، ترحيل المنتجات). عنوان الخادم ليس من شأن العميل — لا يوجد
/// أي تحكم به هنا؛ يتحدد وقت البناء من المطورين فقط.
///
/// بوابة الأقسام مثل settings/layout.tsx + permissions.ts:54-58:
/// الترحيل ← inventory.import، الفواتير ← settings.receipts، قاعدة
/// البيانات ← المالك الكامل فقط (fullAccess)، واللغة ظاهرة دائمًا.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final state = context.watch<AppState>();
    final ctx = state.context;
    // المالك الكامل — وغياب الصلاحيات (مجهول/تحميل) يفشل بالسماح مثل
    // بقية التطبيق (state.can/canAny تعيد true عند permissions == null).
    final bool fullAccess = state.permissions?.fullAccess ?? true;
    // anyOf == null → قسم دائم الظهور (اللغة)؛ [] → المالك الكامل فقط
    // (قاعدة البيانات — SETTINGS_SECTION_PERMISSIONS بالويب فارغة له).
    final sections = <({IconData icon, String title, String desc, WidgetBuilder builder, List<String>? anyOf})>[
      (
        icon: Icons.receipt_outlined,
        title: i18n.t('settings', 'receiptsNavLabel'),
        desc: i18n.t('settings', 'receiptsNavDesc'),
        builder: (_) => const ReceiptsSettingsScreen(),
        anyOf: const <String>['settings.receipts'],
      ),
      (
        icon: Icons.storage_outlined,
        title: i18n.t('settings', 'databaseNavLabel'),
        desc: i18n.t('settings', 'databaseNavDesc'),
        builder: (_) => const DatabaseSettingsScreen(),
        anyOf: const <String>[],
      ),
      (
        icon: Icons.translate,
        title: i18n.t('settings', 'languageNavLabel'),
        desc: i18n.t('settings', 'languageNavDesc'),
        builder: (_) => const LanguageSettingsScreen(),
        anyOf: null,
      ),
      (
        icon: Icons.upload_file_outlined,
        title: i18n.t('settings', 'importNavLabel'),
        desc: i18n.t('settings', 'importNavDesc'),
        builder: (_) => const ImportScreen(),
        anyOf: const <String>['inventory.import'],
      ),
    ];
    final visibleSections = sections.where((section) {
      final List<String>? anyOf = section.anyOf;
      if (anyOf == null) return true; // اللغة لكل المستخدمين (layout.tsx:31-32)
      if (anyOf.isEmpty) return fullAccess; // قاعدة البيانات للمالك الكامل فقط
      return state.canAny(anyOf); // الإخفاء لا التعطيل — مثل Can بالويب
    }).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        PageHeader(i18n.t('nav', 'settings'), subtitle: i18n.t('settings', 'navAria')),
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
              for (final section in visibleSections)
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
                    if (section != visibleSections.last)
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

// ------------------------------------------------------------ اللغة

/// منتقي اللغة — نسخة language-setting.tsx: الحفظ على الحساب أولًا
/// (PATCH) ثم التطبيق المحلي؛ أثناء الانتظار سبّينة دوّارة، وعند الفشل
/// سطر خطأ والاختيار يبقى على اللغة القديمة (لا يُقلب الواجهة بلا نجاح).
class LanguageSettingsScreen extends StatefulWidget {
  const LanguageSettingsScreen({super.key});

  @override
  State<LanguageSettingsScreen> createState() => _LanguageSettingsScreenState();
}

class _LanguageSettingsScreenState extends State<LanguageSettingsScreen> {
  String? _pending; // اللغة قيد التطبيق (busy = pending === code بالويب)
  String? _error;

  Future<void> _select(String code) async {
    final AppState state = context.read<AppState>();
    if (code == state.locale || _pending != null) return; // disabled={pending !== null}
    setState(() {
      _pending = code;
      _error = null;
    });
    try {
      // مثل changeLocale بالويب: الحفظ الدائم على الحساب أولًا — فشل
      // الشبكة يرمي هنا فلا يتغير الاختيار المعروض إطلاقًا.
      await ApiClient.instance.setLocale(code);
      // التطبيق المحلي (القاموس + تخزين الجهاز) — مزامنة الخادم داخله
      // اختيارية أصلاً وقد نجحت في السطر السابق (نفس النداء القابل للتكرار).
      await state.setLocale(code);
    } catch (_) {
      if (mounted) setState(() => _error = AppI18n.instance.t('common', 'language_change_failed'));
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('settings', 'language_title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(i18n.t('settings', 'language_desc'),
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
          const SizedBox(height: 14),
          // nativeName + englishName مثل LOCALE_META في i18n/config.ts
          // Task 81 — القائمة الثمانية كاملة كالويب (نفس الترتيب والأسماء)
          for (final (String code, String native, String english) in <(String, String, String)>[
            for (final entry in AppI18n.localeMeta.entries)
              (entry.key, entry.value.$1, entry.value.$2),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                onTap: _pending == null ? () => _select(code) : null,
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(native, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(english,
                              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                        ],
                      ),
                    ),
                    if (_pending == code)
                      const LoaderSpin(size: 16) // Loader2 h-4 لكل صف لغة — مثل الويب
                    else if (state.locale == code)
                      Icon(Icons.check_circle, color: theme.colorScheme.primary),
                  ],
                ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _error!,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ قاعدة البيانات

/// 00000000000019_sales_discount_customers.sql → { number: 19, title: sales discount customers }
/// مثل parseMigration في database/page.tsx حرفيًا.
({String number, String title, String file}) _parseMigration(String version) {
  final RegExpMatch? match = RegExp(r'^(\d+)_(.+?)(?:\.sql)?$').firstMatch(version);
  if (match == null) return (number: '—', title: version, file: version);
  final int? n = int.tryParse(match.group(1)!);
  return (
    number: n == null ? '—' : '$n',
    title: match.group(2)!.replaceAll('_', ' '),
    file: version,
  );
}

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
    // الأحدث في الشارة: آخر عنصر في السجل (وليس الأول) — مثل items[items.length - 1]
    final latest = _migrations.isEmpty ? null : _parseMigration(_migrations.last.version);
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
                                latest == null ? '—' : 'v${latest.number}',
                                tone: BadgeTone.success,
                              ),
                            ],
                          ),
                          if (latest != null) ...<Widget>[
                            const SizedBox(height: 4),
                            Text(
                              latest.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                            ),
                          ],
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
                      // الأحدث أولاً مثل [...items].reverse() بالويب (historyDesc)
                      for (final MigrationItem m in _migrations.reversed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Icon(Icons.check_circle_outline, size: 16, color: AppColors.successFg),
                              const SizedBox(width: 8),
                              Text(_parseMigration(m.version).number,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      _parseMigration(m.version).title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _parseMigration(m.version).file,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textDirection: TextDirection.ltr, // <code dir="ltr"> بالويب
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(Fmt.dateTime(m.appliedAt, locale: i18n.locale),
                                  style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                            ],
                          ),
                        ),
                    const SizedBox(height: 14),
                    // صندوق الملاحظة — bg-muted/50 p-3 text-xs مثل نهاية بطاقة السجل بالويب
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withOpacity(0.04),
                        borderRadius: AppRadius.br,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(Icons.info_outline,
                              size: 14, color: theme.colorScheme.onSurface.withOpacity(0.55)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              i18n.t('settings', 'autoMigrationsNote'),
                              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55), height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

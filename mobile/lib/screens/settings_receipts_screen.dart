import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// الفواتير والطباعة — نفس نموذج الويب: بادئة الاسم، مقاس الورق، وضع
/// الطباعة، محتوى الإيصال، ومعاينة حية تحدّث فورًا.
class ReceiptsSettingsScreen extends StatefulWidget {
  const ReceiptsSettingsScreen({super.key});
  @override
  State<ReceiptsSettingsScreen> createState() => _ReceiptsSettingsScreenState();
}

class _ReceiptsSettingsScreenState extends State<ReceiptsSettingsScreen> {
  ReceiptSettings? _s;
  late TextEditingController _prefix;
  late TextEditingController _thankYou;
  late TextEditingController _returnPolicy;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _s = null;
    _prefix = TextEditingController();
    _thankYou = TextEditingController();
    _returnPolicy = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _prefix.dispose();
    _thankYou.dispose();
    _returnPolicy.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final i18n = AppI18n.instance;
    try {
      final s = await ApiClient.instance.getSettings();
      if (!mounted) return;
      setState(() {
        _s = s;
        _prefix.text = s.namePrefix;
        _thankYou.text = s.thankYouText;
        _returnPolicy.text = s.returnPolicyText;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('settings', 'saveErrorFallback'));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = i18n.t('settings', 'saveErrorFallback');
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final i18n = AppI18n.instance;
    final s = _s!;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await ApiClient.instance.updateSettings(<String, dynamic>{
        'paper_width_mm': s.paperWidthMm,
        'print_mode': s.printMode,
        'copies': s.copies,
        'name_prefix': _prefix.text.trim(),
        'show_phone': s.showPhone,
        'show_address': s.showAddress,
        'show_cashier': s.showCashier,
        'show_thank_you': s.showThankYou,
        'thank_you_text': _thankYou.text.trim(),
        'show_return_policy': s.showReturnPolicy,
        'return_policy_text': _returnPolicy.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        _s = updated;
        _saving = false;
      });
      await appSnackbar(context, i18n.t('settings', 'savedFlash'));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('settings', 'saveErrorFallback'));
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = i18n.t('settings', 'saveErrorFallback');
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final s = _s;
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('settings', 'receiptsTitle'))),
      body: _loading
          ? const LoadingBox()
          : _error != null && _s == null
              ? ErrorRetry(_error!, onRetry: _load)
              : s == null
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: <Widget>[
                        Text(i18n.t('settings', 'receiptsSubtitle'),
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                        const SizedBox(height: 14),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              CardTitle(i18n.t('settings', 'pharmacyNameTitle'), subtitle: i18n.t('settings', 'pharmacyNameDesc')),
                              const SizedBox(height: 10),
                              AppInput(controller: _prefix, hint: i18n.t('settings', 'customPrefixPlaceholder'), onChanged: (_) => setState(() {})),
                              const SizedBox(height: 8),
                              Text(
                                '${i18n.t('settings', 'showsOnReceipt')} ${_prefix.text.trim().isEmpty ? (context.watch<AppState>().context?.pharmacyName ?? i18n.t('settings', 'fallbackPharmacyWord')) : _prefix.text.trim()}',
                                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.55)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              CardTitle(i18n.t('settings', 'paperSizeTitle'), subtitle: i18n.t('settings', 'paperSizeDesc')),
                              const SizedBox(height: 10),
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: _PaperChoice(
                                      title: i18n.t('settings', 'mmSuffix', {'width': '80'}),
                                      desc: i18n.t('settings', 'paper80Desc'),
                                      selected: s.paperWidthMm == 80,
                                      onTap: () => setState(() => _s = _copy(s, paperWidthMm: 80)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _PaperChoice(
                                      title: i18n.t('settings', 'mmSuffix', {'width': '58'}),
                                      desc: i18n.t('settings', 'paper58Desc'),
                                      selected: s.paperWidthMm == 58,
                                      onTap: () => setState(() => _s = _copy(s, paperWidthMm: 58)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              CardTitle(i18n.t('settings', 'printModeTitle'), subtitle: i18n.t('settings', 'printModeDesc')),
                              const SizedBox(height: 10),
                              AppDropdown<String>(
                                value: s.printMode,
                                items: <DropdownMenuItem<String>>[
                                  DropdownMenuItem<String>(value: 'auto', child: Text(i18n.t('settings', 'printModeAuto'), style: const TextStyle(fontSize: 13))),
                                  DropdownMenuItem<String>(value: 'manual', child: Text(i18n.t('settings', 'printModeManual'), style: const TextStyle(fontSize: 13))),
                                ],
                                onChanged: (String? v) => setState(() => _s = _copy(s, printMode: v ?? 'auto')),
                              ),
                              const SizedBox(height: 10),
                              AppSwitchTile(
                                title: i18n.t('settings', 'copiesLabel'),
                                subtitle: i18n.t('settings', 'copiesDesc'),
                                value: s.copies == 2,
                                onChanged: (bool v) => setState(() => _s = _copy(s, copies: v ? 2 : 1)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              CardTitle(i18n.t('settings', 'contentTitle'), subtitle: i18n.t('settings', 'contentDesc')),
                              const SizedBox(height: 8),
                              AppSwitchTile(title: i18n.t('settings', 'showPhone'), value: s.showPhone, onChanged: (bool v) => setState(() => _s = _copy(s, showPhone: v))),
                              AppSwitchTile(title: i18n.t('settings', 'showAddress'), value: s.showAddress, onChanged: (bool v) => setState(() => _s = _copy(s, showAddress: v))),
                              AppSwitchTile(title: i18n.t('settings', 'showCashier'), value: s.showCashier, onChanged: (bool v) => setState(() => _s = _copy(s, showCashier: v))),
                              AppSwitchTile(title: i18n.t('settings', 'showThankYou'), value: s.showThankYou, onChanged: (bool v) => setState(() => _s = _copy(s, showThankYou: v))),
                              if (s.showThankYou)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: AppInput(controller: _thankYou, hint: i18n.t('settings', 'thankYouPlaceholder')),
                                ),
                              AppSwitchTile(title: i18n.t('settings', 'showReturnPolicy'), value: s.showReturnPolicy, onChanged: (bool v) => setState(() => _s = _copy(s, showReturnPolicy: v))),
                              if (s.showReturnPolicy)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: AppInput(controller: _returnPolicy, hint: i18n.t('settings', 'returnPolicyPlaceholder')),
                                ),
                            ],
                          ),
                        ),
                        if (_error != null) ...<Widget>[
                          const SizedBox(height: 12),
                          Text(_error!, style: TextStyle(fontSize: 12, color: theme.colorScheme.error), textAlign: TextAlign.center),
                        ],
                        const SizedBox(height: 16),
                        PrimaryButton(i18n.t('settings', 'saveSettings'), loading: _saving, onPressed: _save),
                      ],
                    ),
    );
  }

  ReceiptSettings _copy(
    ReceiptSettings s, {
    int? paperWidthMm,
    String? printMode,
    int? copies,
    bool? showPhone,
    bool? showAddress,
    bool? showCashier,
    bool? showThankYou,
    bool? showReturnPolicy,
  }) =>
      ReceiptSettings(
        paperWidthMm: paperWidthMm ?? s.paperWidthMm,
        printMode: printMode ?? s.printMode,
        copies: copies ?? s.copies,
        namePrefix: _prefix.text.trim(),
        thankYouText: _thankYou.text.trim(),
        returnPolicyText: _returnPolicy.text.trim(),
        showPhone: showPhone ?? s.showPhone,
        showAddress: showAddress ?? s.showAddress,
        showCashier: showCashier ?? s.showCashier,
        showThankYou: showThankYou ?? s.showThankYou,
        showReturnPolicy: showReturnPolicy ?? s.showReturnPolicy,
      );
}

class _PaperChoice extends StatelessWidget {
  final String title;
  final String desc;
  final bool selected;
  final VoidCallback onTap;
  const _PaperChoice({required this.title, required this.desc, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: AppRadius.br,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary.withOpacity(0.08) : Colors.transparent,
          borderRadius: AppRadius.br,
          border: Border.all(color: selected ? theme.colorScheme.primary : theme.dividerColor, width: selected ? 1.4 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: selected ? theme.colorScheme.primary : null)),
            const SizedBox(height: 4),
            Text(desc, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.55))),
          ],
        ),
      ),
    );
  }
}

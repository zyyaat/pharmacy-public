import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// معالج إعداد الصيدلية (Task 57) — نفس خطوات الويب الأربع بأسلوب
/// Upwork: الاسم ← التواصل ← الموقع ← المراجعة مع تخطي الاختياري
/// ومراجعة بأزرار تعديل، وإنهاء بـ complete=true.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _website = TextEditingController();
  final TextEditingController _city = TextEditingController();
  final TextEditingController _state = TextEditingController();
  final TextEditingController _address1 = TextEditingController();
  final TextEditingController _address2 = TextEditingController();
  final TextEditingController _postal = TextEditingController();
  int _step = 0; // 0 ترحيب، 1 اسم، 2 تواصل، 3 موقع، 4 مراجعة، 5 نجاح
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[_name, _phone, _website, _city, _state, _address1, _address2, _postal]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final i18n = AppI18n.instance;
    try {
      final s = await ApiClient.instance.getOnboarding();
      if (!mounted) return;
      setState(() {
        _name.text = s.pharmacy.name;
        _phone.text = s.pharmacy.phone;
        _website.text = s.pharmacy.website;
        _city.text = s.pharmacy.city == 'غير محدد' ? '' : s.pharmacy.city;
        _state.text = s.pharmacy.stateProvince;
        _address1.text = s.pharmacy.addressLine1;
        _address2.text = s.pharmacy.addressLine2;
        _postal.text = s.pharmacy.postalCode;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('auth', 'ob_err_load'));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.t('auth', 'ob_err_load');
        _loading = false;
      });
    }
  }

  bool _validateName() {
    final i18n = AppI18n.instance;
    if (_name.text.trim().length < 2) {
      setState(() => _error = i18n.t('auth', 'ob_name_required'));
      return false;
    }
    setState(() => _error = null);
    return true;
  }

  Future<void> _save({required bool complete}) async {
    final i18n = AppI18n.instance;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.updateOnboarding(<String, dynamic>{
        if (_name.text.trim().isNotEmpty) 'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'website': _website.text.trim(),
        if (_city.text.trim().isNotEmpty) 'city': _city.text.trim(),
        'state_province': _state.text.trim(),
        'address_line1': _address1.text.trim(),
        'address_line2': _address2.text.trim(),
        'postal_code': _postal.text.trim(),
        if (complete) 'complete': true,
      });
      if (!mounted) return;
      if (complete) {
        await context.read<AppState>().completeOnboarding();
        setState(() {
          _step = 5;
          _saving = false;
        });
      } else {
        setState(() {
          _step += 1;
          _saving = false;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('auth', 'ob_err_save'));
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.t('auth', 'ob_err_save');
        _saving = false;
      });
    }
  }

  Future<void> _finish() async {
    if (!_validateName()) {
      setState(() => _step = 1);
      return;
    }
    await _save(complete: true);
  }

  void _next() {
    if (_step == 1 && !_validateName()) return;
    setState(() {
      _error = null;
      _step = _step < 4 ? _step + 1 : 4;
    });
  }

  void _skip() {
    setState(() {
      _error = null;
      _step = 4;
    });
  }


  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    if (_loading) {
      return Scaffold(body: const LoadingBox(), appBar: AppBar(title: Text(i18n.t('auth', 'ob_app_label'))));
    }
    if (_error != null && _step == 0) {
      return Scaffold(
        appBar: AppBar(title: Text(i18n.t('auth', 'ob_app_label'))),
        body: Padding(padding: const EdgeInsets.all(16), child: ErrorRetry(_error!, onRetry: _load)),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n.t('auth', 'ob_app_label')),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (_step > 0 && _step < 5) ...<Widget>[
                    Row(
                      children: <Widget>[
                        Text('$_step / 4', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
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
                  ],
                  _buildStep(i18n, theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(AppI18n i18n, ThemeData theme) {
    switch (_step) {
      case 0:
        return _welcome(i18n, theme);
      case 1:
        return _stepCard(i18n, theme, i18n.t('auth', 'ob_s1_title'), i18n.t('auth', 'ob_s1_sub'),
            AppInput(controller: _name, hint: i18n.t('auth', 'pharmacy_name_ph')),
            showSkip: true);
      case 2:
        return _stepCard(i18n, theme, i18n.t('auth', 'ob_s2_title'), i18n.t('auth', 'ob_s2_sub'),
            Column(children: <Widget>[
              AppInput(controller: _phone, hint: i18n.t('auth', 'ob_phone_ph'), keyboard: TextInputType.phone),
              const SizedBox(height: 10),
              AppInput(controller: _website, hint: i18n.t('auth', 'ob_website_ph'), keyboard: TextInputType.url),
            ]),
            showSkip: true);
      case 3:
        return _stepCard(i18n, theme, i18n.t('auth', 'ob_s3_title'), i18n.t('auth', 'ob_s3_sub'),
            Column(children: <Widget>[
              AppInput(controller: _city, hint: i18n.t('auth', 'ob_city_ph')),
              const SizedBox(height: 10),
              AppInput(controller: _state, hint: i18n.t('auth', 'ob_state_ph')),
              const SizedBox(height: 10),
              AppInput(controller: _address1, hint: i18n.t('auth', 'ob_address1_ph')),
              const SizedBox(height: 10),
              AppInput(controller: _address2, hint: i18n.t('auth', 'ob_address2_ph')),
              const SizedBox(height: 10),
              AppInput(controller: _postal, hint: i18n.t('auth', 'ob_postal_ph'), keyboard: TextInputType.number),
            ]),
            showSkip: true);
      case 4:
        return _review(i18n, theme);
      default:
        return _success(i18n, theme);
    }
  }

  Widget _welcome(AppI18n i18n, ThemeData theme) {
    final user = context.watch<AppState>().user;
    return AppCard(
      child: Column(
        children: <Widget>[
          Text(
            '${i18n.t('auth', 'ob_welcome')} ${user?.firstName ?? ''} 👋',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(i18n.t('auth', 'ob_welcome_lead'), textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 18),
          PrimaryButton(i18n.t('auth', 'ob_continue'), onPressed: () => setState(() => _step = 1)),
        ],
      ),
    );
  }

  Widget _stepCard(AppI18n i18n, ThemeData theme, String title, String sub, Widget fields, {bool showSkip = false}) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(sub, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
          const SizedBox(height: 16),
          fields,
          if (_error != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(fontSize: 12, color: theme.colorScheme.error), textAlign: TextAlign.center),
          ],
          const SizedBox(height: 16),
          PrimaryButton(i18n.t('auth', 'ob_continue'), loading: _saving, onPressed: _next),
          if (showSkip) ...<Widget>[
            const SizedBox(height: 6),
            TextButton(onPressed: _skip, child: Text(i18n.t('auth', 'ob_skip'), style: const TextStyle(fontSize: 12))),
          ],
        ],
      ),
    );
  }

  Widget _review(AppI18n i18n, ThemeData theme) {
    final rows = <(String, String, VoidCallback)>[
      (i18n.t('auth', 'pharmacy_name'), _name.text, () => setState(() => _step = 1)),
      (i18n.t('auth', 'ob_phone'), _phone.text.isEmpty ? i18n.t('auth', 'ob_optional') : _phone.text, () => setState(() => _step = 2)),
      (i18n.t('auth', 'ob_website'), _website.text.isEmpty ? i18n.t('auth', 'ob_optional') : _website.text, () => setState(() => _step = 2)),
      (i18n.t('auth', 'ob_city'), _city.text.isEmpty ? i18n.t('auth', 'ob_optional') : _city.text, () => setState(() => _step = 3)),
      (i18n.t('auth', 'ob_state'), _state.text.isEmpty ? i18n.t('auth', 'ob_optional') : _state.text, () => setState(() => _step = 3)),
      (i18n.t('auth', 'ob_address1'), _address1.text.isEmpty ? i18n.t('auth', 'ob_optional') : _address1.text, () => setState(() => _step = 3)),
      (i18n.t('auth', 'ob_postal'), _postal.text.isEmpty ? i18n.t('auth', 'ob_optional') : _postal.text, () => setState(() => _step = 3)),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(i18n.t('auth', 'ob_s4_title'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(i18n.t('auth', 'ob_s4_sub'), style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
          const SizedBox(height: 14),
          for (final (String label, String value, VoidCallback edit) in rows) ...<Widget>[
            Row(
              children: <Widget>[
                SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55)))),
                Expanded(child: Text(value.isEmpty ? '—' : value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                TextButton(onPressed: edit, child: Text(i18n.t('auth', 'ob_edit'), style: const TextStyle(fontSize: 12))),
              ],
            ),
            const Divider(height: 8),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(fontSize: 12, color: theme.colorScheme.error), textAlign: TextAlign.center),
          ],
          const SizedBox(height: 12),
          PrimaryButton(i18n.t('auth', 'ob_finish'), loading: _saving, onPressed: _finish),
        ],
      ),
    );
  }

  Widget _success(AppI18n i18n, ThemeData theme) {
    return AppCard(
      child: Column(
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: AppColors.successBg, shape: BoxShape.circle),
            child: const Icon(Icons.check_circle_outline, size: 34, color: AppColors.successFg),
          ),
          const SizedBox(height: 14),
          Text(i18n.t('auth', 'ob_success_title'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(i18n.t('auth', 'ob_success_sub'), textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 18),
          PrimaryButton(i18n.t('auth', 'ob_enter'), onPressed: () {
            Navigator.pushReplacementNamed(context, '/home');
          }),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// Task 62 — معالج إعداد الصيدلية بنسخة الويب حرفيًا (Task 57): شريط علوي
/// فيه الشعار + «خطوة X من 4» + شريط تقدم، بطاقة rounded-3xl ظل 2xl فيها
/// صندوق أيقونة الخطوة 52 rounded-2xl bg-primary/10، حقول h-14 rounded-2xl،
/// جدول مراجعة rounded-2xl بصفوف متناوبة وأزرار تعديل، وشاشة نجاح بدائرة
/// primary نابضة مع نقاط احتفال.
///
/// Task 79 — درس شكوى «بيانات المعالج ليست الكاملة اللي في صفحة تعديل الفرع»:
/// 1) اكتملت الحقول: اسم الفرع الرئيسي وكود الفرع والبريد صارت تُجمع من أول
///    مرة إلى جانب حقول الصيدلية الثمانية (نفس حقول صفحة تعديل الفرع حرفيًا)،
///    وكل حقل يُظهر حالته: * حمراء للإجباري وكلمة «اختياري» لغيره + مفتاح
///    تفسيري أعلى الحقول.
/// 2) تنسيق العناوين: سطر تصنيف علوي بلون الهوية (التعريف/التواصل/الموقع/
///    المراجعة) فوق العنوان الكبير، يفصله خط فاصل عن الحقول — بدل كتلة
///    الأيقونة والعنوان السابقة بلا هيكل.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _branchName = TextEditingController();
  final TextEditingController _branchCode = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _website = TextEditingController();
  final TextEditingController _city = TextEditingController();
  final TextEditingController _state = TextEditingController();
  final TextEditingController _address1 = TextEditingController();
  final TextEditingController _address2 = TextEditingController();
  final TextEditingController _postal = TextEditingController();
  int _step = 1; // 1 الاسم، 2 التواصل، 3 الموقع، 4 المراجعة، 5 النجاح
  bool _loading = true;
  bool _saving = false;
  String? _error;
  late final AnimationController _pop;

  @override
  void initState() {
    super.initState();
    // Task 79: الإنشاء هنا لا في تهيئة حقل late — أول وصول لـ _pop كان يحدث
    // داخل dispose() إن لم يصل المستخدم لشاشة النجاح، والـ vsync يبحث حينها
    // عن أصل TickerMode وعنصر الشاشة مُلغى تنشيطه فترمي "Looking up a
    // deactivated widget's ancestor is unsafe" (فشلت بها اختبارات المعالج).
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: 0,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _name, _branchName, _branchCode, _phone, _email,
      _website, _city, _state, _address1, _address2, _postal,
    ]) {
      c.dispose();
    }
    _pop.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final i18n = AppI18n.instance;
    try {
      final s = await ApiClient.instance.getOnboarding();
      if (!mounted) return;
      setState(() {
        _name.text = s.pharmacy.name;
        _branchName.text = s.branch.name;
        _branchCode.text = s.branch.code;
        _email.text = s.branch.email;
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
        _error = i18n.t('auth', 'ob_err_load');
        _loading = false;
      });
    }
  }

  /// تحقق الخطوة 1: اسم الصيدلية واسم الفرع الرئيسي كلاهما إجباري
  /// (مطابق لنموذج الفرع على الويب: name + pharmacy_name مطلوبان).
  bool _validateStep1() {
    final i18n = AppI18n.instance;
    if (_name.text.trim().length < 2) {
      setState(() => _error = i18n.t('auth', 'ob_name_required'));
      return false;
    }
    if (_branchName.text.trim().isEmpty) {
      setState(() => _error = i18n.t('auth', 'ob_branch_required'));
      return false;
    }
    setState(() => _error = null);
    return true;
  }

  /// تحقق قبل الحفظ: البريد (إن وُجد) بصيغة سليمة — نفس قاعدة الخادم.
  bool _validateEmail() {
    final i18n = AppI18n.instance;
    final email = _email.text.trim();
    if (email.isNotEmpty && (!email.contains('@') || email.contains(RegExp(r'[ \t]')))) {
      setState(() => _error = i18n.t('auth', 'ob_invalid_email'));
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    final i18n = AppI18n.instance;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // الويب: PUT كل الحقول دائمًا (الفراغات مشمولة) + complete دائمًا.
      // Task 79: أُضيفت حقول الفرع الرئيسي (branch_name/branch_code/email)
      // لتطابق ما تعرضه صفحة تعديل الفرع من أول مرة.
      await ApiClient.instance.updateOnboarding(<String, dynamic>{
        'name': _name.text.trim(),
        'branch_name': _branchName.text.trim(),
        'branch_code': _branchCode.text.trim(),
        'phone': _phone.text.trim(),
        'email': _email.text.trim(),
        'website': _website.text.trim(),
        'city': _city.text.trim(),
        'state_province': _state.text.trim(),
        'address_line1': _address1.text.trim(),
        'address_line2': _address2.text.trim(),
        'postal_code': _postal.text.trim(),
        'complete': true,
      });
      if (!mounted) return;
      await context.read<AppState>().completeOnboarding();
      setState(() {
        _step = 5;
        _saving = false;
      });
      _pop.forward(); // animate-pop-in
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('auth', 'ob_err_save'));
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = i18n.t('auth', 'ob_err_save');
        _saving = false;
      });
    }
  }

  Future<void> _finish() async {
    if (!_validateStep1()) {
      setState(() => _step = 1);
      return;
    }
    if (!_validateEmail()) {
      setState(() => _step = 2);
      return;
    }
    await _save();
  }

  void _next() {
    if (_step == 1 && !_validateStep1()) return;
    if (_step == 2 && !_validateEmail()) return;
    setState(() {
      _error = null;
      _step = _step < 4 ? _step + 1 : 4;
    });
  }

  void _skip() {
    // الويب: skip يقدّم خطوة واحدة فقط بحد أقصى المراجعة — لا قفز مباشر للمراجعة
    setState(() {
      _error = null;
      if (_step < 4) _step += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    if (_loading) {
      return AuthShell(child: const LoadingBox());
    }
    if (_error != null && _step == 1 && _name.text.isEmpty) {
      // شاشة فشل التحميل — مثل الويب: بطاقة بأيقونة ! destructive
      return AuthShell(
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(40), // p-10
            constraints: const BoxConstraints(maxWidth: 448),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: AppRadius.br3xl,
              border: Border.all(color: Theme.of(context).dividerColor),
              boxShadow: WebShadow.xl2,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error.withOpacity(0.10),
                    borderRadius: AppRadius.brXl,
                  ),
                  child: Text('!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.error)),
                ),
                const SizedBox(height: 24),
                Text(_error!, textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, height: 1.6, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55))),
                const SizedBox(height: 24),
                // الويب: زر إعادة التحميل يحمل تسمية ob_continue وليس retry
                WButton(
                  i18n.t('auth', 'ob_continue'),
                  onPressed: _load,
                  size: WButtonSize.xl,
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_step == 5) return _success(i18n);
    return _wizardScaffold(i18n);
  }

  Widget _wizardScaffold(AppI18n i18n) {
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
                Container(
                  padding: const EdgeInsets.all(28), // p-7 (p-10 على الشاشات الأكبر)
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: AppRadius.br3xl,
                    border: Border.all(color: theme.dividerColor),
                    boxShadow: WebShadow.xl2,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Column(
                      key: ValueKey<int>(_step),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        // رأس الخطوة — Task 79: سطر تصنيف بلون الهوية (التعريف /
                        // التواصل / الموقع / المراجعة) فوق العنوان الكبير، ثم خط
                        // فاصل يفصل الرأس عن الحقول — هيكل واضح بدل كتلة بلا تنسيق.
                        Row(
                          children: <Widget>[
                            Container(
                              width: 52, // h-13 w-13
                              height: 52,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withOpacity(0.10),
                                borderRadius: AppRadius.brXl,
                              ),
                              alignment: Alignment.center,
                              child: Icon(_stepIcon(_step), size: 28, color: theme.colorScheme.primary),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(_stepCat(i18n),
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.8,
                                          color: theme.colorScheme.primary)),
                                  const SizedBox(height: 4),
                                  Text(_stepTitle(i18n),
                                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.4)),
                                  const SizedBox(height: 4),
                                  Text(_stepSub(i18n),
                                      style: TextStyle(fontSize: 13.5, height: 1.5, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Divider(height: 1, thickness: 1, color: theme.dividerColor),
                        const SizedBox(height: 16),
                        // المفتاح التفسيري: الحقول المعلّمة بـ * إجبارية — مرجع سريع قبل الحقول
                        if (_step < 4)
                          Row(
                            children: <Widget>[
                              Text('*', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: theme.colorScheme.error)),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(i18n.t('auth', 'ob_required_legend'),
                                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                              ),
                            ],
                          ),
                        if (_step < 4) const SizedBox(height: 20) else const SizedBox(height: 28),
                        if (_error != null) ...<Widget>[
                          FormErrorBanner(_error!),
                          const SizedBox(height: 20),
                        ],
                        _buildStepFields(i18n),
                        const SizedBox(height: 24),
                        Row(
                          children: <Widget>[
                            if (_step > 1) ...<Widget>[
                              WButton(i18n.t('auth', 'ob_back'),
                                  onPressed: () => setState(() => _step -= 1),
                                  variant: WButtonVariant.outline,
                                  size: WButtonSize.wizard),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: WButton(
                                _step == 4 ? (_saving ? i18n.t('auth', 'ob_saving') : i18n.t('auth', 'ob_finish')) : i18n.t('auth', 'ob_continue'),
                                onPressed: _saving ? null : (_step == 4 ? _finish : _next),
                                loading: _saving,
                                size: WButtonSize.wizard,
                                glow: true,
                              ),
                            ),
                          ],
                        ),
                        if (_step == 2 || _step == 3) ...<Widget>[
                          const SizedBox(height: 16),
                          Center(
                            child: GestureDetector(
                              onTap: _skip,
                              child: Text(i18n.t('auth', 'ob_skip'),
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _stepIcon(int step) {
    switch (step) {
      case 1:
        return Icons.store_outlined; // Store
      case 2:
        return Icons.phone_outlined; // Phone
      case 3:
        return Icons.location_on_outlined; // MapPin
      default:
        return Icons.checklist_outlined; // ClipboardList
    }
  }

  String _stepTitle(AppI18n i18n) {
    switch (_step) {
      case 1:
        return i18n.t('auth', 'ob_s1_title');
      case 2:
        return i18n.t('auth', 'ob_s2_title');
      case 3:
        return i18n.t('auth', 'ob_s3_title');
      default:
        return i18n.t('auth', 'ob_s4_title');
    }
  }

  String _stepSub(AppI18n i18n) {
    switch (_step) {
      case 1:
        return i18n.t('auth', 'ob_s1_sub');
      case 2:
        return i18n.t('auth', 'ob_s2_sub');
      case 3:
        return i18n.t('auth', 'ob_s3_sub');
      default:
        return i18n.t('auth', 'ob_s4_sub');
    }
  }

  /// سطر التصنيف العلوي لكل خطوة (Task 79) — يضبط سياق العنوان
  String _stepCat(AppI18n i18n) {
    switch (_step) {
      case 1:
        return i18n.t('auth', 'ob_s1_cat');
      case 2:
        return i18n.t('auth', 'ob_s2_cat');
      case 3:
        return i18n.t('auth', 'ob_s3_cat');
      default:
        return i18n.t('auth', 'ob_s4_cat');
    }
  }

  Widget _buildStepFields(AppI18n i18n) {
    final user = context.watch<AppState>().user;
    switch (_step) {
      case 1:
        // Task 79 — هوية الصيدلية والفرع الرئيسي معًا (نفس حقول صفحة تعديل
        // الفرع): الاسم إجباري (*)، اسم الفرع إجباري (*)، الكود اختياري.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppField(
              isRequired: true,
              label: '${i18n.t('auth', 'ob_welcome')} ${user?.firstName ?? ''}، ${i18n.t('auth', 'ob_app_label')}',
              child: WizardInput(key: const Key('ob_pharmacy_name'), controller: _name, hint: i18n.t('auth', 'pharmacy_name_ph')),
            ),
            const SizedBox(height: 20),
            AppField(
              isRequired: true,
              label: i18n.t('auth', 'ob_branch_name'),
              child: WizardInput(key: const Key('ob_branch_name'), controller: _branchName, hint: i18n.t('auth', 'ob_branch_name_ph')),
            ),
            const SizedBox(height: 20),
            AppField(
              label: i18n.t('auth', 'ob_branch_code'),
              hint: i18n.t('auth', 'ob_optional'),
              child: WizardInput(key: const Key('ob_branch_code'), controller: _branchCode, hint: i18n.t('auth', 'ob_branch_code_ph'), ltr: true, alignEnd: true),
            ),
          ],
        );
      case 2:
        // التواصل كله اختياري — الهاتف والبريد والموقع
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppField(
              label: i18n.t('auth', 'ob_phone'),
              hint: i18n.t('auth', 'ob_optional'),
              child: WizardInput(controller: _phone, hint: i18n.t('auth', 'ob_phone_ph'), keyboard: TextInputType.phone, ltr: true, alignEnd: true),
            ),
            const SizedBox(height: 20),
            AppField(
              label: i18n.t('auth', 'ob_email'),
              hint: i18n.t('auth', 'ob_optional'),
              child: WizardInput(key: const Key('ob_email'), controller: _email, hint: i18n.t('auth', 'ob_email_ph'), keyboard: TextInputType.emailAddress, ltr: true, alignEnd: true),
            ),
            const SizedBox(height: 20),
            AppField(
              label: i18n.t('auth', 'ob_website'),
              hint: i18n.t('auth', 'ob_optional'),
              child: WizardInput(controller: _website, hint: i18n.t('auth', 'ob_website_ph'), keyboard: TextInputType.url, ltr: true, alignEnd: true),
            ),
          ],
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: AppField(
                    label: i18n.t('auth', 'ob_city'),
                    hint: i18n.t('auth', 'ob_optional'),
                    child: WizardInput(controller: _city, hint: i18n.t('auth', 'ob_city_ph')),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: AppField(
                    label: i18n.t('auth', 'ob_state'),
                    hint: i18n.t('auth', 'ob_optional'),
                    child: WizardInput(controller: _state, hint: i18n.t('auth', 'ob_state_ph')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            AppField(
              label: i18n.t('auth', 'ob_address1'),
              hint: i18n.t('auth', 'ob_optional'),
              child: WizardInput(controller: _address1, hint: i18n.t('auth', 'ob_address1_ph')),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: AppField(
                    label: i18n.t('auth', 'ob_address2'),
                    hint: i18n.t('auth', 'ob_optional'),
                    child: WizardInput(controller: _address2, hint: i18n.t('auth', 'ob_address2_ph')),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: AppField(
                    label: i18n.t('auth', 'ob_postal'),
                    hint: i18n.t('auth', 'ob_optional'),
                    child: WizardInput(controller: _postal, hint: i18n.t('auth', 'ob_postal_ph'), keyboard: TextInputType.number, ltr: true, alignEnd: true),
                  ),
                ),
              ],
            ),
          ],
        );
      default:
        return _review(i18n);
    }
  }

  Widget _review(AppI18n i18n) {
    final theme = Theme.of(context);
    final rows = <(String, String, int)>[
      (i18n.t('auth', 'pharmacy_name'), _name.text, 1),
      // Task 79: صفوف الفرع الرئيسي والبريد في المراجعة أيضًا
      (i18n.t('auth', 'ob_branch_name_short'), _branchName.text, 1),
      (i18n.t('auth', 'ob_branch_code'), _branchCode.text, 1),
      (i18n.t('auth', 'ob_phone'), _phone.text, 2),
      (i18n.t('auth', 'ob_email'), _email.text, 2),
      (i18n.t('auth', 'ob_website'), _website.text, 2),
      (i18n.t('auth', 'ob_city'), _city.text, 3),
      (i18n.t('auth', 'ob_state'), _state.text, 3),
      (i18n.t('auth', 'ob_address1'), _address1.text, 3),
      // الويب: عنوان إضافي بين العنوان الأول والبريد
      (i18n.t('auth', 'ob_address2'), _address2.text, 3),
      (i18n.t('auth', 'ob_postal'), _postal.text, 3),
    ];
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.br2xl, // rounded-2xl
        border: Border.all(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), // px-4 py-3
              color: i.isOdd ? theme.colorScheme.onSurface.withOpacity(0.03) : null, // bg-muted/40
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 128, // w-32 — يتسع ل«البريد الإلكتروني» و«اسم الفرع»
                    child: Text(rows[i].$1, style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                  ),
                  Expanded(
                    child: Text(
                      rows[i].$2.trim().isEmpty ? '—' : rows[i].$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _step = rows[i].$3),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.10),
                        borderRadius: AppRadius.br,
                      ),
                      child: Text(i18n.t('auth', 'ob_edit'),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _success(AppI18n i18n) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    // نقاط الاحتفال الثماني بنفس مواقع/ألوان/تأخيرات الويب (page.tsx CONFETTI):
    // (يسار كنسبة من صندوق 96px، لون، بداية التدرج = التأخير/0.5s)
    const confetti = <(double, Color, double)>[
      (0.18, Color(0xFF34D399), 0.0),
      (0.26, Color(0xFF22D3EE), 0.3),
      (0.34, Color(0xFFA3E635), 0.6),
      (0.46, Color(0xFFFBBF24), 0.2),
      (0.58, Color(0xFF34D399), 0.5),
      (0.68, Color(0xFFF472B6), 0.1),
      (0.76, Color(0xFF22D3EE), 0.7),
      (0.84, Color(0xFFA3E635), 0.4),
    ];
    return AuthShell(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(40), // p-10 (sm:p-14)
            constraints: const BoxConstraints(maxWidth: 512),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: AppRadius.br3xl,
              border: Border.all(color: theme.dividerColor),
              boxShadow: WebShadow.xl2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: SizedBox(
                    width: 96, // h-24 w-24
                    height: 96,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        // نقاط تتصاعد خلف العلامة — تدرّج متأخر مثل animationDelay
                        for (final (double dx, Color color, double begin) in confetti)
                          Positioned(
                            bottom: 24, // bottom-6
                            left: 96 * dx,
                            child: ScaleTransition(
                              scale: CurvedAnimation(
                                parent: _pop,
                                curve: Interval(begin, 1.0, curve: Curves.easeOut),
                              ),
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ScaleTransition(
                          scale: CurvedAnimation(parent: _pop, curve: Curves.easeOutBack),
                          child: Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              color: primary,
                              shape: BoxShape.circle,
                              boxShadow: WebShadow.primaryGlowXl(primary),
                            ),
                            child: const Icon(Icons.check, size: 40, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32), // mt-8
                Text(i18n.t('auth', 'ob_success_title'), textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)), // text-3xl
                const SizedBox(height: 12),
                Text(i18n.t('auth', 'ob_success_sub'), textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, height: 1.6, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                const SizedBox(height: 32),
                WButton(
                  i18n.t('auth', 'ob_enter'),
                  onPressed: () => Navigator.pushReplacementNamed(context, '/home'),
                  size: WButtonSize.wizard,
                  glow: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

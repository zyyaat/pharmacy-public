import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// الفروع — قائمة الفروع + إضافة/تعديل + إيقاف، بنفس حقول صفحة الويب
/// (الفرع الرئيسي يزامن اسم الصيدلية عبر pharmacy_name).
/// بوابات التعديل مثل gate.tsx في الويب: الإخفاء لا التعطيل
/// (الإضافة branches.create، التعديل/الإيقاف branches.update).
class BranchesScreen extends StatefulWidget {
  const BranchesScreen({super.key});

  @override
  State<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends State<BranchesScreen> {
  List<Branch> _list = <Branch>[];
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
      final list = await ApiClient.instance.branches();
      if (!mounted) return;
      setState(() {
        _list = list;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('employees', 'branchesLoadErrorFallback'));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.t('employees', 'branchesLoadErrorFallback');
        _loading = false;
      });
    }
  }

  Future<void> _openForm({Branch? branch}) async {
    final appState = context.read<AppState>();
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BranchFormSheet(appState: appState, branch: branch),
    );
    _load();
  }

  Future<void> _deleteBranch(Branch b) async {
    final i18n = AppI18n.instance;
    final ok = await confirmDialog(
      context,
      title: i18n.t('employees', 'branchDeleteBtn'),
      body: i18n.t('employees', 'branchDeleteConfirm'),
      destructive: true,
    );
    if (ok != true) return;
    try {
      await ApiClient.instance.deleteBranch(b.id);
      if (!mounted) return;
      await appSnackbar(context, i18n.t('employees', 'branchDeleted'));
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      await appSnackbar(context, AppI18n.instance.error(e.code, i18n.t('employees', 'branchDeleteError')), error: true);
    } catch (_) {
      if (!mounted) return;
      await appSnackbar(context, i18n.t('employees', 'branchDeleteError'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final appState = context.watch<AppState>();
    final canCreate = appState.can('branches.create');
    final canUpdate = appState.can('branches.update');
    if (_loading) return const LoadingBox();
    if (_error != null) return ErrorRetry(_error!, onRetry: _load);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          PageHeader(
            i18n.t('employees', 'branchesTitle'),
            subtitle: i18n.t('employees', 'branchesSubtitle'),
            actions: <Widget>[
              if (canCreate)
                WButton(i18n.t('employees', 'branchesAddBtn'), icon: Icons.add, onPressed: () => _openForm()),
            ],
          ),
          const SizedBox(height: 24),
          AppCard(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: CardTitle(i18n.t('employees', 'branchesListTitle'), icon: Icons.storefront_outlined),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: _list.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Text(i18n.t('employees', 'branchesEmpty'),
                              style: TextStyle(
                                  fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
                        )
                      : Column(
                          children: <Widget>[ // شبكة عمود واحد على الهاتف (md:2 xl:3 في الويب)
                            for (final Branch b in _list) ...<Widget>[
                              _BranchTile(
                                branch: b,
                                onEdit: canUpdate ? () => _openForm(branch: b) : null,
                                onDelete: canUpdate && !b.isMain ? () => _deleteBranch(b) : null,
                              ),
                              if (b != _list.last) const SizedBox(height: 16),
                            ],
                          ],
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

/// بلاطة فرع — rounded-xl border مثل شبكة الويب: الفرع الرئيسي بحد
/// primary/30 وخلفية primary/5، المتوقف بشفافية 70%، وشارة الحالة
/// (نشط/متوقف) دائمًا ظاهرة، وصفوف مُعنونة (كود/مدير/هاتف/بريد).
class _BranchTile extends StatelessWidget {
  final Branch branch;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  const _BranchTile({required this.branch, this.onEdit, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final Branch b = branch;
    final mutedFg = theme.colorScheme.onSurface.withOpacity(0.55);
    // العنوان والمدينة كلاهما بيانات حقيقية بترتيب الويب «العنوان، المدينة»
    // مع بديل «بدون عنوان» عند الفراغ (page.tsx:88)
    final addressLine = <String>[
      if (b.address.isNotEmpty) b.address,
      if (b.city.isNotEmpty && b.city != 'غير محدد') b.city,
    ].join('، ');
    return Opacity(
      opacity: b.isActive ? 1 : 0.70, // opacity-70 مثل الويب
      child: CardBox(
        borderColor: b.isMain ? theme.colorScheme.primary.withOpacity(0.30) : null,
        color: b.isMain ? theme.colorScheme.primary.withOpacity(0.05) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(child: Text(b.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                          if (b.isMain) ...<Widget>[
                            const SizedBox(width: 6),
                            AppBadge(i18n.t('employees', 'branchMainBadge'), tone: BadgeTone.primary),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        addressLine.isEmpty ? i18n.t('employees', 'noAddress') : addressLine,
                        style: TextStyle(fontSize: 13, color: mutedFg),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _statusPill(context, active: b.isActive),
              ],
            ),
            const SizedBox(height: 12),
            // الصفوف المُعنونة كما في الويب: الكود (إن وُجد)، المدير (إن وُجد)، الهاتف، البريد
            if (b.code.isNotEmpty) _labeledRow(context, i18n.t('employees', 'branchCodeLabel'), b.code),
            if (b.managerName.isNotEmpty) _labeledRow(context, i18n.t('employees', 'branchManagerLabel'), b.managerName),
            _labeledRow(context, i18n.t('employees', 'branchPhoneLabel'), b.phone.isEmpty ? '—' : b.phone),
            _labeledRow(context, i18n.t('employees', 'branchEmailCardLabel'), b.email.isEmpty ? '—' : b.email),
            if (onEdit != null || onDelete != null) ...<Widget>[
              const SizedBox(height: 12),
              Container(height: 1, color: theme.dividerColor), // border-t مثل الويب
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  if (onEdit != null)
                    WButton(i18n.t('employees', 'branchEditBtn'),
                        icon: Icons.edit_outlined,
                        variant: WButtonVariant.outline, size: WButtonSize.sm, onPressed: onEdit),
                  if (onDelete != null) ...<Widget>[
                    const SizedBox(width: 8),
                    WButton(i18n.t('employees', 'branchDeleteBtn'),
                        icon: Icons.block,
                        variant: WButtonVariant.outline, size: WButtonSize.sm,
                        color: theme.colorScheme.error, onPressed: onDelete),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// شارة الحالة الدائمة: نشط (bg-primary/10) / متوقف (bg-muted) كالويب
  Widget _statusPill(BuildContext context, {required bool active}) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: active
            ? theme.colorScheme.primary.withOpacity(0.10)
            : (dark ? AppColors.darkMuted : AppColors.lightMuted),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        active ? i18n.t('employees', 'branchActive') : i18n.t('employees', 'branchStopped'),
        style: TextStyle(
          fontSize: 12,
          color: active
              ? theme.colorScheme.primary
              : (dark ? AppColors.darkMutedFg : AppColors.lightMutedFg),
        ),
      ),
    );
  }

  Widget _labeledRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        '$label $value',
        style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55)),
      ),
    );
  }
}

class _BranchFormSheet extends StatefulWidget {
  final AppState appState;
  final Branch? branch;
  const _BranchFormSheet({required this.appState, this.branch});
  @override
  State<_BranchFormSheet> createState() => _BranchFormSheetState();
}

class _BranchFormSheetState extends State<_BranchFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late final TextEditingController _city;
  late final TextEditingController _pharmacyName;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.branch != null;
  bool get _isMainEdit => _isEdit && widget.branch!.isMain;

  @override
  void initState() {
    super.initState();
    final b = widget.branch;
    _name = TextEditingController(text: b?.name ?? '');
    _code = TextEditingController(text: b?.code ?? '');
    _phone = TextEditingController(text: b?.phone ?? '');
    _email = TextEditingController(text: b?.email ?? '');
    _address = TextEditingController(text: b?.address ?? '');
    _city = TextEditingController(text: b?.city == 'غير محدد' ? '' : (b?.city ?? ''));
    // Task 51 (الويب [id]/page.tsx:32-34): تعبئة اسم الصيدلية من قيمة قاعدة
    // البيانات الحقيقية — pharmacy_name ثم سياق الصيدلية ثم اسم الفرع آخر الملجآت
    _pharmacyName = TextEditingController(text: b != null && b.isMain ? _pharmacyNameFallback(b) : '');
  }

  String _pharmacyNameFallback(Branch b) {
    final stored = b.pharmacyName;
    if (stored != null && stored.isNotEmpty) return stored;
    final contextName = widget.appState.context?.pharmacyName ?? '';
    if (contextName.isNotEmpty) return contextName;
    return b.name;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _city.dispose();
    _pharmacyName.dispose();
    super.dispose();
  }

  /// تسميات جدول الويب تحمل «:» (الكود:) — نموذج الإضافة يقتطعها
  /// كما يفعل field.label.replace(/:$/, '') في branch-form-fields.tsx
  String _formLabel(String label) => label.endsWith(':') ? label.substring(0, label.length - 1) : label;

  Future<void> _save() async {
    final i18n = AppI18n.instance;
    if (_saving) return;
    final name = _name.text.trim();
    // تحقق الويب ([id]:84): الاسم مطلوب، واسم الصيدلية مطلوب عند تعديل
    // الفرع الرئيسي — رسالة خطأ بدل التجاهل الصامت
    if (name.isEmpty || (_isMainEdit && _pharmacyName.text.trim().isEmpty)) {
      setState(() => _error = i18n.t('employees', 'branchSaveError'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final payload = <String, dynamic>{
      'name': name,
      if (_code.text.trim().isNotEmpty) 'code': _code.text.trim(),
      if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
      if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
      if (_address.text.trim().isNotEmpty) 'address': _address.text.trim(),
      if (_city.text.trim().isNotEmpty) 'city': _city.text.trim(),
      // الفرع الرئيسي يرسل pharmacy_name دائمًا (التحقق أعلاه يضمن عدم فراغه)
      if (_isMainEdit) 'pharmacy_name': _pharmacyName.text.trim(),
    };
    try {
      if (_isEdit) {
        await ApiClient.instance.updateBranch(widget.branch!.id, payload);
      } else {
        await ApiClient.instance.createBranch(payload);
      }
      if (_isMainEdit) {
        // الفرع الرئيسي = معلومات الصيدلية ([id]:93-96) — الشريط الجانبي
        // ورأس الفاتورة يتحدثان فورًا بإعادة جلب سياق الصيدلية
        try {
          await widget.appState.refreshSessionData();
        } catch (_) {}
      }
      if (!mounted) return;
      await appSnackbar(context, i18n.t('employees', 'branchSaved'));
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('employees', 'branchSaveError'));
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = i18n.t('employees', 'branchSaveError');
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(_isEdit ? i18n.t('employees', 'branchesEditTitle') : i18n.t('employees', 'branchesNewTitle'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              if (_isMainEdit) ...<Widget>[
                const SizedBox(height: 6),
                // ملاحظة المزامنة بصندوق primary/5 وحد primary/20 مثل الويب
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.primary.withOpacity(0.20)),
                  ),
                  child: Text(i18n.t('employees', 'branchMainSyncNote'),
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                ),
              ],
              const SizedBox(height: 12),
              if (_isMainEdit) ...<Widget>[
                _LabeledInput(
                  label: i18n.t('employees', 'pharmacyNameLabel'),
                  requiredMark: true,
                  child: AppInput(controller: _pharmacyName),
                ),
                const SizedBox(height: 10),
              ],
              // ترتيب حقول الويب: الاسم، الكود، الهاتف، البريد، العنوان، المدينة
              _LabeledInput(
                label: i18n.t('employees', 'branchNameLabel'),
                requiredMark: true,
                child: AppInput(controller: _name),
              ),
              const SizedBox(height: 10),
              _LabeledInput(
                label: _formLabel(i18n.t('employees', 'branchCodeLabel')),
                child: AppInput(controller: _code),
              ),
              const SizedBox(height: 10),
              _LabeledInput(
                label: _formLabel(i18n.t('employees', 'branchPhoneLabel')),
                child: AppInput(controller: _phone, keyboard: TextInputType.phone),
              ),
              const SizedBox(height: 10),
              _LabeledInput(
                label: i18n.t('employees', 'branchEmailLabel'),
                child: AppInput(controller: _email, keyboard: TextInputType.emailAddress),
              ),
              const SizedBox(height: 10),
              _LabeledInput(
                label: i18n.t('employees', 'branchAddressLabel'),
                child: AppInput(controller: _address),
              ),
              const SizedBox(height: 10),
              _LabeledInput(
                label: i18n.t('employees', 'branchCityLabel'),
                child: AppInput(controller: _city),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 10),
                FormErrorBanner(_error!),
              ],
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: PrimaryButton(i18n.t('employees', 'branchSave'), loading: _saving, onPressed: _save),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: WButton(
                      i18n.t('employees', 'branchCancel'),
                      variant: WButtonVariant.ghost,
                      expand: true,
                      onPressed: _saving ? null : () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// تسمية حقل مع نجمة * حمراء للحقول المطلوبة (مثل
/// {field.label}<span className="text-destructive"> *</span> في الويب)
class _LabeledInput extends StatelessWidget {
  final String label;
  final bool requiredMark;
  final Widget child;
  const _LabeledInput({required this.label, this.requiredMark = false, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Flexible(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
            if (requiredMark)
              Text(' *',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.error)),
          ],
        ),
        const SizedBox(height: 8), // mb-2
        child,
      ],
    );
  }
}

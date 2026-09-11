import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// الموظفون — مطابقة صفحة الويب (employees/page.tsx + permissions-editor.tsx):
/// - البوابات منفصلة: employees.create للإضافة، employees.update
///   للتفعيل/الإيقاف، employees.manage_permissions لمحرر الصلاحيات.
/// - عمود «الصلاحيات» (عرض / تعديل) ومن يفتح محرر الصلاحيات هو من يملك
///   manage_permissions فقط.
/// - الوظيفة تُعرض كما دخلها أو بتسمية الدور (rolePharmacist...) مثل الويب.
/// - نموذج الإضافة: محرر صلاحيات كامل (قوالب + أقسام + مفاتيح) وحمولة الطلب
///   template_id ما لم يُخصَّص المحرر، عندها permissions مصفوفة.
class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  List<Employee> _list = <Employee>[];
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
      final list = await ApiClient.instance.employees();
      if (!mounted) return;
      setState(() {
        _list = list;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('employees', 'loadErrorFallback'));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.t('employees', 'loadErrorFallback');
        _loading = false;
      });
    }
  }

  Future<void> _toggleStatus(Employee e) async {
    final i18n = AppI18n.instance;
    final next = e.status == 'active' ? 'inactive' : 'active';
    try {
      await ApiClient.instance.setEmployeeStatus(e.id, next);
      if (!mounted) return;
      await appSnackbar(context, next == 'inactive' ? i18n.t('employees', 'deactivatedNotice') : i18n.t('employees', 'activatedNotice'));
      _load();
    } on ApiException catch (err) {
      if (!mounted) return;
      await appSnackbar(context, AppI18n.instance.error(err.code, i18n.t('employees', 'statusChangeErrorFallback')), error: true);
    } catch (_) {
      if (!mounted) return;
      await appSnackbar(context, i18n.t('employees', 'statusChangeErrorFallback'), error: true);
    }
  }

  Future<void> _openPermissions(Employee e) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EmployeePermissionsScreen(employee: e)));
    // الويب يعيد تحميل القائمة بعد حفظ الصلاحيات (savePermissions → load)
    _load();
  }

  /// الوظيفة كما بالويب: job_title إن وُجد وإلا تسمية الدور
  /// (الافتراضي pharmacist) — page.tsx:223.
  String _jobLabel(Employee e, Map<String, String> roleLabels) {
    if (e.jobTitle.isNotEmpty) return e.jobTitle;
    final role = (e.role == null || e.role!.isEmpty) ? 'pharmacist' : e.role!;
    return roleLabels[role] ?? role;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final state = context.watch<AppState>();
    // ثلاث بوابات منفصلة كما بالويب (page.tsx:33-34) — fullAccess يمر كلها
    // عبر MyPermissions.can.
    final canCreate = state.can('employees.create');
    final canManage = state.can('employees.manage_permissions');
    final canUpdate = state.can('employees.update');
    final roleLabels = <String, String>{
      'pharmacy_admin': i18n.t('employees', 'rolePharmacyAdmin'),
      'pharmacist': i18n.t('employees', 'rolePharmacist'),
      'cashier': i18n.t('employees', 'roleCashier'),
      'inventory_manager': i18n.t('employees', 'roleInventoryManager'),
      'hr_manager': i18n.t('employees', 'roleHrManager'),
      'accountant': i18n.t('employees', 'roleAccountant'),
    };
    if (_loading) return const LoadingBox();
    if (_error != null) return ErrorRetry(_error!, onRetry: _load);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          PageHeader(
            i18n.t('employees', 'title'),
            subtitle: i18n.t('employees', 'subtitle'),
            actions: <Widget>[
              if (canCreate)
                WButton(
                  i18n.t('employees', 'addNew'),
                  icon: Icons.person_add_alt_outlined,
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EmployeeFormScreen()));
                    _load();
                  },
                ),
            ],
          ),
          const SizedBox(height: 24),
          AppCard(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: CardTitle(i18n.t('employees', 'listTitle'), icon: Icons.group_outlined),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: _list.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Text(i18n.t('employees', 'empty'),
                              style: TextStyle(
                                  fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
                        )
                      : WebTable(
                          minWidth: 820, // min-w-[820px] كما بالويب
                          headers: <String>[
                            i18n.t('employees', 'thName'),
                            i18n.t('employees', 'thEmail'),
                            i18n.t('employees', 'thJob'),
                            i18n.t('employees', 'thBranch'),
                            i18n.t('employees', 'permissions'),
                            i18n.t('employees', 'thStatus'),
                            if (canManage || canUpdate) i18n.t('employees', 'thActions'),
                          ],
                          rows: <List<Widget>>[
                            for (final Employee e in _list)
                              <Widget>[
                                Text(e.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(e.email, textDirection: TextDirection.ltr),
                                Text(_jobLabel(e, roleLabels)),
                                Text((e.branchName == null || e.branchName!.isEmpty) ? '—' : e.branchName!),
                                // عمود الصلاحيات: شارة عرض / تعديل لمن يملك
                                // manage_permissions، وإلا «—» باهتة (page.tsx:226-237)
                                canManage
                                    ? WButton(i18n.t('employees', 'viewEdit'),
                                        icon: Icons.shield_outlined,
                                        variant: WButtonVariant.outline, size: WButtonSize.sm,
                                        onPressed: () => _openPermissions(e))
                                    : Text('—',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
                                AppBadge(
                                  e.status == 'active' ? i18n.t('employees', 'statusActive') : i18n.t('employees', 'statusInactive'),
                                  tone: e.status == 'active' ? BadgeTone.success : BadgeTone.destructive,
                                ),
                                if (canManage || canUpdate)
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: <Widget>[
                                      if (canManage)
                                        WButton(i18n.t('employees', 'permissions'),
                                            icon: Icons.verified_user_outlined,
                                            variant: WButtonVariant.ghost, size: WButtonSize.sm,
                                            onPressed: () => _openPermissions(e)),
                                      if (canUpdate)
                                        _GhostActionButton(
                                          e.status == 'active' ? i18n.t('employees', 'deactivate') : i18n.t('employees', 'activate'),
                                          icon: Icons.power_settings_new,
                                          // أيقونة ملونة فقط كما بالويب (page.tsx:261)
                                          iconColor: e.status == 'active'
                                              ? Theme.of(context).colorScheme.error
                                              : AppColors.successFg,
                                          tooltip: e.status == 'active'
                                              ? i18n.t('employees', 'deactivateTitle')
                                              : i18n.t('employees', 'activateTitle'),
                                          onPressed: () => _toggleStatus(e),
                                        ),
                                    ],
                                  ),
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

/// زر شبح صغير بأيقونة ملونة (web Button ghost sm + Power ملونة) —
/// WButton يلوّن الأيقونة والنص معًا، والويب يلوّن الأيقونة فقط.
class _GhostActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? iconColor;
  final String? tooltip;
  final VoidCallback? onPressed;
  const _GhostActionButton(
    this.label, {
    required this.icon,
    this.iconColor,
    this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final button = Container(
      height: 36, // WButton sm
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: iconColor ?? scheme.onSurface),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onSurface)),
          ),
        ],
      ),
    );
    final w = Material(
      color: Colors.transparent,
      borderRadius: AppRadius.brMd,
      child: InkWell(borderRadius: AppRadius.brMd, onTap: onPressed, child: button),
    );
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

// ------------------------------------------------------------ محرر الصلاحيات

/// ترتيب الأقسام المنطقي الثابت (permissions-editor.tsx:19-22)
const List<String> _kModuleOrder = <String>[
  'dashboard', 'pos', 'sales', 'inventory', 'customers',
  'employees', 'attendance', 'branches', 'reports', 'settings', 'pharmacy',
];

/// الصلاحيات الحساسة بعلامة كهرمانية (permissions-editor.tsx:25-28)
const Set<String> _kSensitiveKeys = <String>{
  'employees.delete', 'employees.manage_permissions', 'inventory.import',
  'inventory.writeoff', 'customers.delete', 'settings.general', 'pharmacy.admin',
};

/// محرر الصلاحيات المرن — نسخة permissions-editor.tsx:
/// صف قوالب جاهزة (تمييز القالب المطبق/المطابق تمامًا) + بطاقات أقسام
/// قابلة للطي بمفتاح رئيسي لكل قسم + مفتاح لكل صلاحية.
/// يبلّغ الأب عند كل تغيير: (المفاتيح المختارة، معرف القالب المطبق أو null
/// إن كان التغيير يدويًا) — ليقرر نموذج الإضافة شكل الحمولة.
class _PermissionsEditor extends StatefulWidget {
  final Set<String> selected;
  final void Function(Set<String> selected, String? appliedTemplateId) onChanged;
  const _PermissionsEditor({required this.selected, required this.onChanged});

  @override
  State<_PermissionsEditor> createState() => _PermissionsEditorState();
}

class _PermissionsEditorState extends State<_PermissionsEditor> {
  List<PermissionModule> _catalog = <PermissionModule>[];
  List<PermissionTemplate> _templates = <PermissionTemplate>[];
  bool _loading = true;
  String? _appliedTemplateId;
  final Set<String> _collapsed = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<List<dynamic>>(<Future<List<dynamic>>>[
        ApiClient.instance.permissionCatalog(),
        ApiClient.instance.permissionTemplates(),
      ]);
      if (!mounted) return;
      final catalog = results[0].cast<PermissionModule>().toList()
        ..sort((PermissionModule a, PermissionModule b) =>
            _kModuleOrder.indexOf(a.module).compareTo(_kModuleOrder.indexOf(b.module)));
      setState(() {
        _catalog = catalog;
        _templates = results[1].cast<PermissionTemplate>().toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _applyTemplate(PermissionTemplate tpl) {
    setState(() => _appliedTemplateId = tpl.id);
    widget.onChanged(tpl.permissions.toSet(), tpl.id);
  }

  void _toggleKey(String key, bool next) {
    final nextSet = widget.selected.toSet();
    if (next) {
      nextSet.add(key);
    } else {
      nextSet.remove(key);
    }
    setState(() => _appliedTemplateId = null);
    widget.onChanged(nextSet, null);
  }

  void _toggleModule(PermissionModule mod, bool next) {
    final keys = mod.permissions.map((p) => p.key).toSet();
    final nextSet = widget.selected.toSet();
    if (next) {
      nextSet.addAll(keys);
    } else {
      nextSet.removeAll(keys);
    }
    setState(() => _appliedTemplateId = null);
    widget.onChanged(nextSet, null);
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(i18n.t('employees', 'loadingPerms'),
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // القوالب الجاهزة (grid 2 أعمدة على الموبايل مثل sm:grid-cols-3 بالويب)
        Row(
          children: <Widget>[
            Icon(Icons.verified_user_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
            Text(i18n.t('employees', 'templatesTitle'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(i18n.t('employees', 'templatesHint'),
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < _templates.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: _templateCard(_templates[i])),
                if (i + 1 < _templates.length) ...<Widget>[
                  const SizedBox(width: 8),
                  Expanded(child: _templateCard(_templates[i + 1])),
                ],
              ],
            ),
          ),
        const SizedBox(height: 16),
        // تفاصيل الصلاحيات
        Row(
          children: <Widget>[
            Icon(Icons.shield_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                i18n.t('employees', 'detailsTitle', {'count': Fmt.number(widget.selected.length)}),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_catalog.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(i18n.t('employees', 'noPermissionsDefined'),
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
            ),
          ),
        for (final PermissionModule m in _catalog)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _moduleCard(m),
          ),
      ],
    );
  }

  Widget _templateCard(PermissionTemplate tpl) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = widget.selected;
    final active = _appliedTemplateId == tpl.id;
    final matchCount = tpl.permissions.where(selected.contains).length;
    final exact = matchCount == tpl.permissions.length && matchCount == selected.length;
    final highlighted = active || (exact && tpl.permissions.isNotEmpty);
    final name = tpl.displayNameAr.isNotEmpty ? tpl.displayNameAr : tpl.displayName;
    return InkWell(
      borderRadius: AppRadius.br,
      onTap: () => _applyTemplate(tpl),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: highlighted ? scheme.primary.withOpacity(0.05) : Colors.transparent,
          borderRadius: AppRadius.br,
          border: Border.all(
            color: highlighted ? scheme.primary : theme.dividerColor,
            width: highlighted ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(tpl.descriptionAr, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: scheme.onSurface.withOpacity(0.5))),
            const SizedBox(height: 4),
            Text(
              AppI18n.instance.t('employees', 'permsCount', {'count': Fmt.number(tpl.permissions.length)}),
              style: TextStyle(fontSize: 11, color: scheme.primary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moduleCard(PermissionModule m) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final i18n = AppI18n.instance;
    final keys = m.permissions.map((p) => p.key).toList();
    final enabledCount = keys.where(widget.selected.contains).length;
    final allOn = enabledCount == keys.length && keys.isNotEmpty;
    final isCollapsed = _collapsed.contains(m.module);
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.br,
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 12, end: 12, top: 10, bottom: 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: InkWell(
                    borderRadius: AppRadius.brSm,
                    onTap: () => setState(() {
                      if (isCollapsed) {
                        _collapsed.remove(m.module);
                      } else {
                        _collapsed.add(m.module);
                      }
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: <Widget>[
                          Transform.rotate(
                            angle: isCollapsed ? -math.pi / 2 : 0,
                            child: Icon(Icons.expand_more, size: 16, color: scheme.onSurface.withOpacity(0.5)),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(m.label,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: allOn ? scheme.primary.withOpacity(0.10) : scheme.onSurface.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('$enabledCount/${keys.length}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: allOn ? scheme.primary : scheme.onSurface.withOpacity(0.55))),
                ),
                const SizedBox(width: 8),
                Semantics(
                  label: i18n.t('employees', 'toggleModuleAria', {'module': m.label}),
                  child: _MiniToggle(value: allOn, onChanged: (bool next) => _toggleModule(m, next)),
                ),
              ],
            ),
          ),
          if (!isCollapsed)
            Container(
              width: double.infinity,
              decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.dividerColor))),
              padding: const EdgeInsets.all(12),
              child: Column(
                children: <Widget>[
                  for (final perm in m.permissions) _permRow(perm),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _permRow(({String key, String nameAr, String category}) perm) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final selected = widget.selected.contains(perm.key);
    final sensitive = _kSensitiveKeys.contains(perm.key);
    final label = perm.nameAr.isNotEmpty ? perm.nameAr : perm.key;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withOpacity(0.05) : Colors.transparent,
          borderRadius: AppRadius.brMd,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: sensitive ? FontWeight.w600 : FontWeight.w400,
                      color: scheme.onSurface),
                  children: <InlineSpan>[
                    if (sensitive)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(start: 4),
                          child: Text('●',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: dark ? AppColors.warningFgDark : AppColors.warningFg)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            _MiniToggle(value: selected, onChanged: (bool next) => _toggleKey(perm.key, next)),
          ],
        ),
      ),
    );
  }
}

/// مفتاح تشغيل صغير 44×24 مثل Toggle في permissions-editor.tsx —
/// thumb أبيض 16 يتحرك من بداية المسار (مطفأ) إلى نهايته (شغّال) بشكل
/// اتجاهي RTL-aware.
class _MiniToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _MiniToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 44,
        height: 24,
        decoration: BoxDecoration(
          color: value ? scheme.primary : scheme.onSurface.withOpacity(0.30),
          borderRadius: BorderRadius.circular(999),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment: value ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
          child: Container(
            width: 16,
            height: 16,
            margin: const EdgeInsetsDirectional.all(4),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[BoxShadow(color: Color(0x33000000), blurRadius: 2)],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ إضافة موظف

class EmployeeFormScreen extends StatefulWidget {
  const EmployeeFormScreen({super.key});
  @override
  State<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends State<EmployeeFormScreen> {
  final TextEditingController _first = TextEditingController();
  final TextEditingController _last = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _job = TextEditingController();
  String? _branchId;
  Set<String> _perms = <String>{};
  String? _templateId;
  bool _customized = false;
  List<Branch> _branches = <Branch>[];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _job.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    try {
      final branches = await ApiClient.instance.branches();
      if (!mounted) return;
      setState(() => _branches = branches);
    } catch (_) {}
  }

  /// الحمولة كما بالويب (page.tsx:102-111): الصلاحيات المصفوفة هي المرجع،
  /// لكن بروح تعليمات التدقيق: المحرر غير مُخصَّص → template_id كما كان،
  /// وبمجرد أي تخصيص يدوي → permissions (الخادم: القائمة الصريحة تسبق القالب).
  Map<String, dynamic> _payload(String firstName, String lastName, String email) {
    return <String, dynamic>{
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'password': _password.text,
      if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
      if (_job.text.trim().isNotEmpty) 'job_title': _job.text.trim(),
      if (_branchId != null) 'branch_id': _branchId,
      if (_customized)
        'permissions': _perms.toList(growable: false)
      else if (_templateId != null && _templateId!.isNotEmpty)
        'template_id': _templateId,
    };
  }

  Future<void> _save() async {
    final i18n = AppI18n.instance;
    final firstName = _first.text.trim();
    final lastName = _last.text.trim();
    final email = _email.text.trim();
    // الويب يطلب الاسم الأول والأخير والبريد معًا (page.tsx:92)
    if (firstName.isEmpty || lastName.isEmpty || email.isEmpty) {
      setState(() => _error = i18n.t('employees', 'errNameEmailRequired'));
      return;
    }
    if (_password.text.length < 8) {
      setState(() => _error = i18n.t('employees', 'errPasswordTooShort'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.createEmployee(_payload(firstName, lastName, email));
      if (!mounted) return;
      await appSnackbar(context, i18n.t('employees', 'employeeCreatedNotice'));
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('employees', 'employeeCreateErrorFallback'));
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = i18n.t('employees', 'employeeCreateErrorFallback');
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('employees', 'addNew'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppField(label: i18n.t('employees', 'firstNameLabel'), child: AppInput(controller: _first, hint: i18n.t('employees', 'firstNamePlaceholder'))),
                const SizedBox(height: 10),
                AppField(label: i18n.t('employees', 'lastNameLabel'), child: AppInput(controller: _last, hint: i18n.t('employees', 'lastNamePlaceholder'))),
                const SizedBox(height: 10),
                AppField(
                  label: i18n.t('employees', 'emailLabel'),
                  hint: i18n.t('employees', 'emailHint'),
                  child: AppInput(
                    controller: _email,
                    keyboard: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr, // dir="ltr"
                    hint: 'staff@pharmacy.com',
                  ),
                ),
                const SizedBox(height: 10),
                AppField(
                  label: i18n.t('employees', 'passwordLabel'),
                  hint: i18n.t('employees', 'passwordHint'),
                  // الويب يعرض كلمة المرور نصًا ظاهرًا (type="text")
                  child: AppInput(controller: _password, textDirection: TextDirection.ltr, hint: '••••••••'),
                ),
                const SizedBox(height: 10),
                AppField(
                  label: i18n.t('employees', 'phoneLabel'),
                  child: AppInput(controller: _phone, keyboard: TextInputType.phone, textDirection: TextDirection.ltr, hint: '01xxxxxxxxx'),
                ),
                const SizedBox(height: 10),
                AppField(label: i18n.t('employees', 'jobTitleLabel'), child: AppInput(controller: _job, hint: i18n.t('employees', 'jobTitlePlaceholder'))),
                const SizedBox(height: 10),
                AppField(
                  label: i18n.t('employees', 'branchLabel'),
                  child: AppDropdown<String>(
                    value: _branchId,
                    hint: i18n.t('employees', 'noBranchOption'),
                    items: <DropdownMenuItem<String>>[
                      for (final Branch b in _branches)
                        DropdownMenuItem<String>(value: b.id, child: Text(b.name, style: const TextStyle(fontSize: 13))),
                    ],
                    onChanged: (String? v) => setState(() => _branchId = v),
                  ),
                ),
                const SizedBox(height: 16),
                // صندوق محرر الصلاحيات بحدود مثل الويب (page.tsx:329-331)
                CardBox(
                  padding: const EdgeInsets.all(16),
                  radius: AppRadius.v,
                  child: _PermissionsEditor(
                    selected: _perms,
                    onChanged: (Set<String> selected, String? appliedTemplateId) {
                      setState(() {
                        _perms = selected;
                        if (appliedTemplateId != null) {
                          // قالب طُبّق من الصف — يبقى template_id ما لم يُخصَّص
                          _templateId = appliedTemplateId;
                          _customized = false;
                        } else {
                          // تخصيص يدوي (مفتاح/قسم) — الحمولة تصبح مصفوفة
                          _templateId = null;
                          _customized = true;
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center),
          ],
          const SizedBox(height: 16),
          PrimaryButton(i18n.t('employees', 'saveEmployee'), loading: _saving, onPressed: _save),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ صلاحيات موظف

class EmployeePermissionsScreen extends StatefulWidget {
  final Employee employee;
  const EmployeePermissionsScreen({super.key, required this.employee});
  @override
  State<EmployeePermissionsScreen> createState() => _EmployeePermissionsScreenState();
}

class _EmployeePermissionsScreenState extends State<EmployeePermissionsScreen> {
  Set<String> _selected = <String>{};
  Set<String> _original = <String>{};
  bool _loading = true;
  bool _saving = false;
  bool _hasExplicit = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final i18n = AppI18n.instance;
    try {
      final perms = await ApiClient.instance.employeePermissions(widget.employee.id);
      if (!mounted) return;
      setState(() {
        _selected = perms.permissions.toSet();
        _original = perms.permissions.toSet();
        _hasExplicit = perms.hasExplicit;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('employees', 'loadingPerms'));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = i18n.t('employees', 'loadErrorFallback');
        _loading = false;
      });
    }
  }

  /// dirty كما بالويب (page.tsx:168-169): طول مختلف أو مفتاح جديد غير موجود
  /// في الأصل — زر الحفظ معطل حتى يتغير شيء فعليًا.
  bool get _dirty => _selected.length != _original.length || !_selected.containsAll(_original);

  Future<void> _save() async {
    final i18n = AppI18n.instance;
    setState(() => _saving = true);
    try {
      await ApiClient.instance.updateEmployeePermissions(widget.employee.id, _selected.toList());
      if (!mounted) return;
      await appSnackbar(context, i18n.t('employees', 'permsUpdatedNotice'));
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      await appSnackbar(context, AppI18n.instance.error(e.code, i18n.t('employees', 'permsSaveErrorFallback')), error: true);
      setState(() => _saving = false);
    } catch (_) {
      if (!mounted) return;
      await appSnackbar(context, i18n.t('employees', 'permsSaveErrorFallback'), error: true);
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('employees', 'permsModalTitle', {'name': widget.employee.displayName}))),
      body: _loading
          ? const LoadingBox()
          : _error != null
              ? ErrorRetry(_error!, onRetry: _load)
              : Column(
                  children: <Widget>[
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: <Widget>[
                          Text(widget.employee.email,
                              textDirection: TextDirection.ltr,
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                          const SizedBox(height: 12),
                          if (!_hasExplicit) ...<Widget>[
                            // تنبيه كهرماني للإعداد القديم (page.tsx:360-364)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.warningBg,
                                borderRadius: AppRadius.br,
                                border: Border.all(color: (dark ? AppColors.warningFgDark : AppColors.warningFg).withOpacity(0.40)),
                              ),
                              child: Text(i18n.t('employees', 'legacyPermsNote'),
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: dark ? AppColors.warningFgDark : AppColors.warningFg)),
                            ),
                            const SizedBox(height: 12),
                          ],
                          // صندوق المحرر بحدود وتمرير مثل max-h-[60vh] p-4 بالويب
                          CardBox(
                            padding: const EdgeInsets.all(12),
                            radius: AppRadius.v,
                            child: _PermissionsEditor(
                              selected: _selected,
                              onChanged: (Set<String> selected, _) => setState(() => _selected = selected),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: PrimaryButton(
                        i18n.t('employees', 'savePerms'),
                        loading: _saving,
                        onPressed: _dirty ? _save : null, // معطل حتى تغيير فعلي
                      ),
                    ),
                  ],
                ),
    );
  }
}

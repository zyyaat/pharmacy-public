import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/ui.dart';

/// الموظفون — صفحة الويب نفسها: قائمة بالحالة والفرع، إضافة موظف
/// بقالب صلاحيات، تعديل الصلاحيات بالنطاقات، وإيقاف/تفعيل الحساب.
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
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('employees', 'title'))),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_employee',
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EmployeeFormScreen()));
          _load();
        },
        icon: const Icon(Icons.person_add_alt),
        label: Text(i18n.t('employees', 'addNew'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const LoadingBox()
          : _error != null
              ? ErrorRetry(_error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _list.isEmpty
                      ? ListView(children: <Widget>[EmptyState(i18n.t('employees', 'empty'), icon: Icons.group_outlined)])
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                          itemCount: _list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (BuildContext ctx, int i) {
                            final Employee e = _list[i];
                            final active = e.status == 'active';
                            return AppCard(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(e.displayName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                                      ),
                                      AppBadge(active ? i18n.t('employees', 'statusActive') : i18n.t('employees', 'statusInactive'),
                                          tone: active ? BadgeTone.success : BadgeTone.muted),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(e.email, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                                  if (e.jobTitle.isNotEmpty)
                                    Text(e.jobTitle, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                                  if (e.branchName != null && e.branchName!.isNotEmpty)
                                    Text('${i18n.t('employees', 'thBranch')}: ${e.branchName}',
                                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.45))),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => _openPermissions(e),
                                          icon: const Icon(Icons.key_outlined, size: 16),
                                          label: Text(i18n.t('employees', 'permissions'), style: const TextStyle(fontSize: 12)),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton.icon(
                                        onPressed: () => _toggleStatus(e),
                                        icon: Icon(active ? Icons.block : Icons.check_circle_outline, size: 16),
                                        label: Text(active ? i18n.t('employees', 'deactivate') : i18n.t('employees', 'activate'),
                                            style: const TextStyle(fontSize: 12)),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: active ? AppColors.lightDestructive : AppColors.successFg,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
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
  String? _templateId;
  List<Branch> _branches = <Branch>[];
  List<PermissionTemplate> _templates = <PermissionTemplate>[];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMeta();
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

  Future<void> _loadMeta() async {
    try {
      final branches = await ApiClient.instance.branches();
      if (!mounted) return;
      setState(() => _branches = branches);
    } catch (_) {}
    try {
      final templates = await ApiClient.instance.permissionTemplates();
      if (!mounted) return;
      setState(() => _templates = templates);
    } catch (_) {}
  }

  Future<void> _save() async {
    final i18n = AppI18n.instance;
    final firstName = _first.text.trim();
    final email = _email.text.trim();
    if (firstName.isEmpty || email.isEmpty) {
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
      await ApiClient.instance.createEmployee(<String, dynamic>{
        'first_name': firstName,
        'last_name': _last.text.trim(),
        'email': email,
        'password': _password.text,
        if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
        if (_job.text.trim().isNotEmpty) 'job_title': _job.text.trim(),
        if (_branchId != null) 'branch_id': _branchId,
        if (_templateId != null) 'template_id': _templateId,
      });
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
                AppField(label: i18n.t('employees', 'emailLabel'), hint: i18n.t('employees', 'emailHint'), child: AppInput(controller: _email, keyboard: TextInputType.emailAddress)),
                const SizedBox(height: 10),
                AppField(label: i18n.t('employees', 'passwordLabel'), hint: i18n.t('employees', 'passwordHint'), child: AppInput(controller: _password, obscure: true)),
                const SizedBox(height: 10),
                AppField(label: i18n.t('employees', 'phoneLabel'), child: AppInput(controller: _phone, keyboard: TextInputType.phone)),
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
                const SizedBox(height: 10),
                AppField(
                  label: i18n.t('employees', 'templatesTitle'),
                  hint: i18n.t('employees', 'templatesHint'),
                  child: AppDropdown<String>(
                    value: _templateId,
                    hint: i18n.t('common', 'select_placeholder'),
                    items: <DropdownMenuItem<String>>[
                      for (final PermissionTemplate t in _templates)
                        DropdownMenuItem<String>(value: t.id, child: Text(t.displayNameAr.isEmpty ? t.displayName : t.displayNameAr, style: const TextStyle(fontSize: 13))),
                    ],
                    onChanged: (String? v) => setState(() => _templateId = v),
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
  List<PermissionModule> _catalog = <PermissionModule>[];
  Set<String> _selected = <String>{};
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
      final catalog = await ApiClient.instance.permissionCatalog();
      final perms = await ApiClient.instance.employeePermissions(widget.employee.id);
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _selected = perms.permissions.toSet();
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
                          if (!_hasExplicit)
                            AppCard(
                              color: AppColors.infoBg,
                              child: Text(i18n.t('employees', 'legacyPermsNote'),
                                  style: const TextStyle(fontSize: 12)),
                            ),
                          const SizedBox(height: 12),
                          for (final PermissionModule m in _catalog)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: AppCard(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        Expanded(child: Text(m.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                                        Text(i18n.t('employees', 'permsCount', {'count': Fmt.number(_selected.where(_selectedIn(m)).length)}),
                                            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: <Widget>[
                                        for (final perm in m.permissions)
                                          FilterChip(
                                            label: Text(perm.nameAr, style: const TextStyle(fontSize: 11)),
                                            selected: _selected.contains(perm.key),
                                            onSelected: (bool v) => setState(() {
                                              if (v) {
                                                _selected.add(perm.key);
                                              } else {
                                                _selected.remove(perm.key);
                                              }
                                            }),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
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
                        onPressed: _save,
                      ),
                    ),
                  ],
                ),
    );
  }

  bool Function(String) _selectedIn(PermissionModule m) =>
      (String key) => m.permissions.any((perm) => perm.key == key);
}

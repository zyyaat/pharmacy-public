import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/ui.dart';

/// الفروع — قائمة الفروع + إضافة/تعديل + إيقاف، بنفس حقول صفحة الويب
/// (الفرع الرئيسي يزامن اسم الصيدلية عبر pharmacy_name).
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
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BranchFormSheet(branch: branch),
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('employees', 'branchesTitle'))),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_branch',
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_business),
        label: Text(i18n.t('employees', 'branchesAddBtn'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const LoadingBox()
          : _error != null
              ? ErrorRetry(_error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _list.isEmpty
                      ? ListView(children: <Widget>[EmptyState(i18n.t('employees', 'branchesEmpty'), icon: Icons.storefront_outlined)])
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                          itemCount: _list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (BuildContext ctx, int i) {
                            final Branch b = _list[i];
                            return AppCard(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Expanded(child: Text(b.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                                      if (b.isMain) AppBadge(i18n.t('employees', 'branchMainBadge'), tone: BadgeTone.primary),
                                      if (!b.isActive) ...<Widget>[
                                        const SizedBox(width: 6),
                                        AppBadge(i18n.t('employees', 'branchStopped'), tone: BadgeTone.muted),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    <String>[
                                      if (b.code.isNotEmpty) '${i18n.t('employees', 'branchCodeLabel')} ${b.code}',
                                      if (b.city.isNotEmpty && b.city != 'غير محدد') b.city,
                                      if (b.address.isNotEmpty) b.address,
                                      if (b.phone.isNotEmpty) '${i18n.t('employees', 'branchPhoneLabel')} ${b.phone}',
                                      if (b.managerName.isNotEmpty) '${i18n.t('employees', 'branchManagerLabel')} ${b.managerName}',
                                    ].join(' · '),
                                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.55)),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => _openForm(branch: b),
                                          icon: const Icon(Icons.edit_outlined, size: 16),
                                          label: Text(i18n.t('employees', 'branchEditBtn'), style: const TextStyle(fontSize: 12)),
                                        ),
                                      ),
                                      if (!b.isMain) ...<Widget>[
                                        const SizedBox(width: 8),
                                        OutlinedButton.icon(
                                          onPressed: () => _deleteBranch(b),
                                          icon: const Icon(Icons.block, size: 16),
                                          label: Text(i18n.t('employees', 'branchDeleteBtn'), style: const TextStyle(fontSize: 12)),
                                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.lightDestructive),
                                        ),
                                      ],
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

class _BranchFormSheet extends StatefulWidget {
  final Branch? branch;
  const _BranchFormSheet({this.branch});
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
    _pharmacyName = TextEditingController(text: b?.pharmacyName ?? '');
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

  Future<void> _save() async {
    final i18n = AppI18n.instance;
    if (_name.text.trim().isEmpty || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final payload = <String, dynamic>{
      'name': _name.text.trim(),
      if (_code.text.trim().isNotEmpty) 'code': _code.text.trim(),
      if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
      if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
      if (_address.text.trim().isNotEmpty) 'address': _address.text.trim(),
      if (_city.text.trim().isNotEmpty) 'city': _city.text.trim(),
      if (_isEdit && widget.branch!.isMain && _pharmacyName.text.trim().isNotEmpty)
        'pharmacy_name': _pharmacyName.text.trim(),
    };
    try {
      if (_isEdit) {
        await ApiClient.instance.updateBranch(widget.branch!.id, payload);
      } else {
        await ApiClient.instance.createBranch(payload);
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
              if (_isEdit && widget.branch!.isMain) ...<Widget>[
                const SizedBox(height: 6),
                Text(i18n.t('employees', 'branchMainSyncNote'), style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55))),
              ],
              const SizedBox(height: 12),
              if (_isEdit && widget.branch!.isMain) ...<Widget>[
                AppField(label: i18n.t('employees', 'pharmacyNameLabel'), child: AppInput(controller: _pharmacyName)),
                const SizedBox(height: 10),
              ],
              AppField(label: i18n.t('employees', 'branchNameLabel'), child: AppInput(controller: _name)),
              const SizedBox(height: 10),
              AppField(label: i18n.t('employees', 'branchCityLabel'), child: AppInput(controller: _city)),
              const SizedBox(height: 10),
              AppField(label: i18n.t('employees', 'branchAddressLabel'), child: AppInput(controller: _address)),
              const SizedBox(height: 10),
              AppField(label: i18n.t('employees', 'branchPhoneLabel'), child: AppInput(controller: _phone, keyboard: TextInputType.phone)),
              const SizedBox(height: 10),
              AppField(label: i18n.t('employees', 'branchEmailLabel'), child: AppInput(controller: _email, keyboard: TextInputType.emailAddress)),
              const SizedBox(height: 10),
              AppField(label: i18n.t('employees', 'branchCodeLabel'), child: AppInput(controller: _code)),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 14),
              PrimaryButton(i18n.t('employees', 'branchSave'), loading: _saving, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}

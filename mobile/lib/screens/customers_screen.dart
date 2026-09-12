import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';
import 'customer_statement_screen.dart';

/// Task 62 — العملاء بنسخة الويب حرفيًا: بطاقة العملاء (رأس بعنوان وزر
/// «إضافة» outline sm، نموذج إضافة عند التفعيل، وقائمة عملاء بشارات الديون)
/// — كشف الحساب يُفتح شاشة تفصيلية بنفس بطاقة كشف الويب.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  List<Customer> _list = <Customer>[];
  bool _creating = false;
  bool _debtsOnly = false;
  bool _loading = true;
  bool _adding = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final i18n = AppI18n.instance;
    try {
      final list = await ApiClient.instance.customers(search: _searchCtrl.text.trim(), debtsOnly: _debtsOnly);
      if (!mounted) return;
      setState(() {
        _list = list;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('customers', 'loadError'));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = i18n.t('customers', 'loadError');
        _loading = false;
      });
    }
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    // مهلة 200ms مثل useEffect في صفحة عملاء الويب
    _debounce = Timer(const Duration(milliseconds: 200), _load);
  }

  Future<void> _addCustomer() async {
    if (_adding) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      // مثل الويب (page.tsx:96) — رسالة خطأ بدل التجاهل الصامت
      await appSnackbar(context, AppI18n.instance.t('customers', 'nameRequired'), error: true);
      return;
    }
    setState(() => _adding = true);
    try {
      await ApiClient.instance.createCustomer(name, _phoneCtrl.text.trim());
      _nameCtrl.clear();
      _phoneCtrl.clear();
      await _load();
      if (mounted) {
        setState(() {
          _adding = false;
          _creating = false;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _adding = false);
      appSnackbar(context, AppI18n.instance.error(e.code, e.message), error: true);
    } catch (_) {
      if (mounted) {
        setState(() => _adding = false);
        appSnackbar(context, AppI18n.instance.t('customers', 'create_failed'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final state = context.watch<AppState>();
    final canCreate = state.can('customers.create');
    // Task 75 — مثل الويب (customers/page.tsx): الهيكل كاملًا ظاهر أثناء
    // التحميل (البحث ونموذج الإضافة)، والقائمة نفسها مكانها النص الباهت.
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          PageHeader(i18n.t('customers', 'title'), subtitle: i18n.t('customers', 'subtitle')),
          const SizedBox(height: 24),

          // بطاقة العملاء (العمود الأول في شبكة الويب)
          AppCard(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: CardTitle(
                    i18n.t('customers', 'customersTitle'),
                    // وصف البطاقة = searchHint كما في CardDescription بالويب
                    subtitle: i18n.t('customers', 'searchHint'),
                    trailing: canCreate
                        ? WButton(
                            _creating ? i18n.t('common', 'cancel') : i18n.t('customers', 'newCustomer'),
                            variant: _creating ? WButtonVariant.ghost : WButtonVariant.outline,
                            size: WButtonSize.sm,
                            onPressed: () => setState(() => _creating = !_creating),
                          )
                        : null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SearchField(
                        controller: _searchCtrl,
                        hint: i18n.t('customers', 'searchPlaceholder'),
                        onChanged: _onSearch,
                        onClear: () {
                          _searchCtrl.clear();
                          _load();
                        },
                      ),
                      const SizedBox(height: 12),
                      if (_creating) ...<Widget>[
                        AppInput(controller: _nameCtrl, hint: i18n.t('customers', 'namePlaceholder')),
                        const SizedBox(height: 8),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: AppInput(
                                controller: _phoneCtrl,
                                hint: i18n.t('customers', 'phonePlaceholder'),
                                keyboard: TextInputType.phone,
                              ),
                            ),
                            const SizedBox(width: 8),
                            WButton(i18n.t('pos', 'add'), icon: Icons.person_add_alt_1, loading: _adding, onPressed: _addCustomer),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_loading && _list.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Text(i18n.t('common', 'loading'),
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                        )
                      else if (_error != null && _list.isEmpty)
                        ErrorRetry(_error!, onRetry: _load)
                      else if (_list.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Text(i18n.t('customers', 'emptyList'),
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                        )
                      else
                        for (final Customer c in _list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: CardBox(
                              onTap: () async {
                                await Navigator.of(context).push(MaterialPageRoute<void>(
                                  builder: (_) => CustomerStatementScreen(customer: c),
                                ));
                                _load();
                              },
                              child: Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(c.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 2),
                                        Text(
                                          c.phone.isEmpty ? i18n.t('pos', 'noPhone') : c.phone,
                                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // الرصيد شارة فقط — المبلغ الحر المكرر حُذف،
                                  // والمستحق عليه بنغمة destructive مثل الويب
                                  _debtBadge(i18n, c),
                                ],
                              ),
                            ),
                          ),
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

  Widget _debtBadge(AppI18n i18n, Customer c) {
    if (c.balancePiastres > 0) {
      return AppBadge(i18n.t('customers', 'owedBadge', {'amount': Fmt.money(c.balancePiastres, locale: i18n.locale)}),
          tone: BadgeTone.destructive);
    }
    if (c.balancePiastres < 0) {
      return AppBadge(i18n.t('customers', 'creditBadge', {'amount': Fmt.money(-c.balancePiastres, locale: i18n.locale)}),
          tone: BadgeTone.success);
    }
    return AppBadge(i18n.t('customers', 'settledBadge'), tone: BadgeTone.success);
  }
}

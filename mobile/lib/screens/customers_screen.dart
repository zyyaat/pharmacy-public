import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/ui.dart';
import 'customer_statement_screen.dart';

/// حسابات العملاء — نفس صفحة الويب: بحث، إضافة عميل، ديون الآجل
/// بشاراتها، وكشف حساب مع تحصيل دفعة.
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
        _error = AppI18n.instance.t('customers', 'loadError');
        _loading = false;
      });
    }
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _addCustomer() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _adding) {
      return;
    }
    setState(() => _adding = true);
    try {
      await ApiClient.instance.createCustomer(name, _phoneCtrl.text.trim());
      _nameCtrl.clear();
      _phoneCtrl.clear();
      await _load();
      if (mounted) setState(() => _adding = false);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _adding = false);
      appSnackbar(context, AppI18n.instance.error(e.code, e.message), error: true);
    } catch (_) {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('customers', 'title'))),
      body: _loading && _list.isEmpty
          ? const LoadingBox()
          : _error != null
              ? ErrorRetry(_error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      Text(i18n.t('customers', 'subtitle'),
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                      const SizedBox(height: 12),
                      SearchField(
                        controller: _searchCtrl,
                        hint: i18n.t('customers', 'searchPlaceholder'),
                        onChanged: _onSearch,
                        onClear: () { _searchCtrl.clear(); _load(); },
                      ),
                      const SizedBox(height: 10),
                      AppCard(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(i18n.t('customers', 'newCustomer'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            AppInput(controller: _nameCtrl, hint: i18n.t('customers', 'namePlaceholder')),
                            const SizedBox(height: 8),
                            Row(
                              children: <Widget>[
                                Expanded(child: AppInput(controller: _phoneCtrl, hint: i18n.t('customers', 'phonePlaceholder'), keyboard: TextInputType.phone)),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: _adding ? null : _addCustomer,
                                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                                  child: _adding
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Icon(Icons.person_add_alt_1, size: 20),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          FilterChip(
                            label: Text(i18n.t('nav', 'customer_debts'), style: const TextStyle(fontSize: 12)),
                            selected: _debtsOnly,
                            onSelected: (bool v) {
                              _debtsOnly = v;
                              _load();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_list.isEmpty)
                        EmptyState(i18n.t('customers', 'searchHint'), icon: Icons.note_alt_outlined)
                      else
                        for (final Customer c in _list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: AppCard(
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
                                        Text(c.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 2),
                                        Text(
                                          c.phone.isEmpty ? i18n.t('pos', 'noPhone') : c.phone,
                                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: <Widget>[
                                      Text(
                                        Fmt.money(c.balancePiastres, locale: i18n.locale),
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: c.balancePiastres > 0 ? AppColors.warningFg : AppColors.successFg,
                                        ),
                                      ),
                                      if (c.balancePiastres > 0) ...<Widget>[
                                        const SizedBox(height: 2),
                                        AppBadge(i18n.t('nav', 'debtor_badge'), tone: BadgeTone.warning),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
    );
  }
}

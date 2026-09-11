import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/ui.dart';
import 'sale_detail_screen.dart';

/// سجل البيع — نفس بنية صفحة الويب: بحث + بطاقات فواتير بحالتها
/// (مكتملة/مرتجعة جزئيًا/مرتجعة بالكامل) + آجل + مرتجعات + ترقيم صفحات.
class SalesListScreen extends StatefulWidget {
  const SalesListScreen({super.key});

  @override
  State<SalesListScreen> createState() => _SalesListScreenState();
}

class _SalesListScreenState extends State<SalesListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<SaleSummary> _sales = <SaleSummary>[];
  int _total = 0;
  int _offset = 0;
  bool _loading = true;
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
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final i18n = AppI18n.instance;
    try {
      final page = await ApiClient.instance.listPOSSales(offset: _offset, search: _searchCtrl.text.trim());
      if (!mounted) return;
      setState(() {
        _sales = page.sales;
        _total = page.total;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('sales', 'loadError'));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.t('sales', 'loadError');
        _loading = false;
      });
    }
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _offset = 0;
      _load();
    });
  }

  String _unitsLabel(int units) {
    final i18n = AppI18n.instance;
    if (units == 1) return i18n.t('sales', 'oneUnit');
    if (units == 2) return i18n.t('sales', 'twoUnits');
    return i18n.t('sales', 'manyUnits', {'count': Fmt.number(units)});
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _loading && _sales.isEmpty
          ? const LoadingBox()
          : _error != null && _sales.isEmpty
              ? ErrorRetry(_error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      Text(i18n.t('sales', 'title'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(i18n.t('sales', 'subtitle'),
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                      const SizedBox(height: 14),
                      SearchField(
                        controller: _searchCtrl,
                        hint: i18n.t('sales', 'searchPlaceholder'),
                        onChanged: _onSearch,
                        onClear: () { _searchCtrl.clear(); _offset = 0; _load(); },
                      ),
                      const SizedBox(height: 12),
                      if (_sales.isEmpty) ...<Widget>[
                        EmptyState(
                          _searchCtrl.text.isEmpty ? i18n.t('sales', 'emptyTitle') : i18n.t('sales', 'emptySearchHint'),
                          icon: Icons.receipt_long_outlined,
                        ),
                        if (_searchCtrl.text.isEmpty)
                          Text(i18n.t('sales', 'emptyFirstHint'), textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.45))),
                      ] else ...<Widget>[
                        for (final SaleSummary s in _sales)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: AppCard(
                              onTap: () async {
                                await Navigator.of(context).push(MaterialPageRoute<void>(
                                  builder: (_) => SaleDetailScreen(saleId: s.id),
                                ));
                                _load();
                              },
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text('#${Fmt.number(s.invoiceNumber)}',
                                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                                      ),
                                      AppBadge(_statusLabel(s.status), tone: AppBadge.saleStatus(s.status)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(Fmt.dateTime(s.createdAt, locale: i18n.locale),
                                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                                  const SizedBox(height: 6),
                                  Text(
                                    s.productsCount == 0
                                        ? i18n.t('sales', 'noProducts')
                                        : i18n.t('sales', 'productsAndUnits', {
                                            'products': Fmt.number(s.productsCount),
                                            'units': _unitsLabel(s.totalQuantityBase),
                                          }),
                                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.7)),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: <Widget>[
                                      if (s.paymentType == 'credit')
                                        Padding(
                                          padding: const EdgeInsets.only(right: 8),
                                          child: AppBadge(
                                            s.customerName.isEmpty
                                                ? i18n.t('sales', 'creditBadge')
                                                : i18n.t('sales', 'creditBadgeWithCustomer', {'customer': s.customerName}),
                                            tone: BadgeTone.warning,
                                          ),
                                        ),
                                      if (s.discountAmountPiastres > 0)
                                        Text(i18n.t('sales', 'discount', {'amount': Fmt.money(s.discountAmountPiastres, locale: i18n.locale)}),
                                            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                                      const Spacer(),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: <Widget>[
                                          Text(Fmt.money(s.totalAmountPiastres, locale: i18n.locale),
                                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                                          if (s.returnedAmountPiastres > 0)
                                            Text(i18n.t('sales', 'returnedAmount', {'amount': Fmt.money(s.returnedAmountPiastres, locale: i18n.locale)}),
                                                style: TextStyle(fontSize: 11, color: AppColors.warningFg)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        PaginationRow(total: _total, limit: 20, offset: _offset, onOffset: (int o) { _offset = o; _load(); }),
                      ],
                    ],
                  ),
                ),
    );
  }

  String _statusLabel(String status) {
    final i18n = AppI18n.instance;
    switch (status) {
      case 'completed':
        return i18n.t('sales', 'statusCompleted');
      case 'partially_returned':
        return i18n.t('sales', 'statusPartiallyReturned');
      case 'returned':
        return i18n.t('sales', 'statusReturned');
      default:
        return status;
    }
  }
}

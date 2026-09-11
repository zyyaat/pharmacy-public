import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../models/models.dart';
import '../widgets/ui.dart';
import 'sale_detail_screen.dart';

/// Task 62 — سجل البيع بنسخة الويب حرفيًا: بطاقات فواتير p-4 فيها رقم
/// INV-000123 بخط أحادي الاتجاه LTR، التاريخ، العدد، شارات الحالة والآجل،
/// والإجمالي في النهاية، مع زر «تحميل المزيد» أسفل القائمة.
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

  String _invoiceLabel(int n) {
    final s = n.toString().padLeft(6, '0');
    return 'INV-$s';
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    return _loading && _sales.isEmpty
        ? const LoadingBox()
        : _error != null && _sales.isEmpty
            ? ErrorRetry(_error!, onRetry: _load)
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    // البحث — نفس صف البحث في الويب
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: SearchField(
                            controller: _searchCtrl,
                            hint: i18n.t('sales', 'searchPlaceholder'),
                            onChanged: _onSearch,
                            onClear: () { _searchCtrl.clear(); _offset = 0; _load(); },
                          ),
                        ),
                        const SizedBox(width: 8),
                        WButton(i18n.t('sales', 'searchButton'),
                            variant: WButtonVariant.secondary, size: WButtonSize.sm,
                            onPressed: () { _offset = 0; _load(); }),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (_sales.isEmpty) ...<Widget>[
                      AppCard(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24), // py-16
                          child: Column(
                            children: <Widget>[
                              Text(i18n.t('sales', 'emptyTitle'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 12),
                              Text(
                                _searchCtrl.text.isEmpty ? i18n.t('sales', 'emptyFirstHint') : i18n.t('sales', 'emptySearchHint'),
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.55)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...<Widget>[
                      for (final SaleSummary s in _sales)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12), // space-y-3
                          child: AppCard(
                            padding: const EdgeInsets.all(16), // p-4
                            onTap: () async {
                              await Navigator.of(context).push(MaterialPageRoute<void>(
                                builder: (_) => SaleDetailScreen(saleId: s.id),
                              ));
                              _load();
                            },
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(_invoiceLabel(s.invoiceNumber),
                                          textDirection: TextDirection.ltr,
                                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 2),
                                      Text(Fmt.dateTime(s.createdAt, locale: i18n.locale),
                                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                                    ],
                                  ),
                                ),
                                Text(
                                  s.productsCount == 0
                                      ? i18n.t('sales', 'noProducts')
                                      : i18n.t('sales', 'productsAndUnits', {
                                          'products': Fmt.number(s.productsCount),
                                          'units': _unitsLabel(s.totalQuantityBase),
                                        }),
                                  style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.6)),
                                ),
                                const SizedBox(width: 12),
                                AppBadge(_statusLabel(s.status), tone: AppBadge.saleStatus(s.status)),
                                if (s.paymentType == 'credit') ...<Widget>[
                                  const SizedBox(width: 6),
                                  AppBadge(
                                    s.customerName.isEmpty
                                        ? i18n.t('sales', 'creditBadge')
                                        : i18n.t('sales', 'creditBadgeWithCustomer', {'customer': s.customerName}),
                                    tone: BadgeTone.warning,
                                  ),
                                ],
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: <Widget>[
                                    Text(Fmt.money(s.totalAmountPiastres, locale: i18n.locale),
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                                    if (s.returnedAmountPiastres > 0)
                                      Text(i18n.t('sales', 'returnedAmount', {'amount': Fmt.money(s.returnedAmountPiastres, locale: i18n.locale)}),
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: theme.colorScheme.error)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      // تحميل المزيد — مثل زر الويب الثانوي الصغير
                      if (_offset + 20 < _total)
                        Center(
                          child: WButton(i18n.t('sales', 'loadMore'),
                              variant: WButtonVariant.secondary, size: WButtonSize.sm,
                              onPressed: () { _offset += 20; _load(); }),
                        ),
                    ],
                  ],
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

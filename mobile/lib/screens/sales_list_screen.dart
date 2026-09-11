import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../models/models.dart';
import '../widgets/ui.dart';
import 'sale_detail_screen.dart';

/// Task 68-c — سجل البيع مطابقًا لصفحة sales/page.tsx في الويب حرفيًا:
/// PageHeader(title + subtitle)، بطاقة لكل فاتورة (INV-000012 بخط أحادي
/// الاتجاه LTR، تاريخ · وقت 12 ساعة ص/م، «N أصناف · M وحدات» برقم خام،
/// شارات الحالة والآجل، سطر «خصم X» المضمر عند وجود خصم، الإجمالي
/// والمرتجع)، إيصالات الاسترجاع المتداخلة أسفل كل بطاقة (RET-000012 +
/// التاريخ + المبلغ السالب + السبب)، و«تحميل المزيد» تُلحق الصفحة
/// الجديدة بالقائمة (append) بدل استبدالها — كما يفعل الويب تمامًا.
class SalesListScreen extends StatefulWidget {
  const SalesListScreen({super.key});

  @override
  State<SalesListScreen> createState() => _SalesListScreenState();
}

class _SalesListScreenState extends State<SalesListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final List<SaleSummary> _sales = <SaleSummary>[];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  Timer? _debounce;

  /// البحث المطبَّق — كما في الويب: submitSearch يثبّت القيمة ويحمّل
  /// الصفحة الأولى فقط، وأثناء الكتابة يعمل تأخير 400ms.
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load(append: false);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// [append] = false: الصفحة الأولى تستبدل القائمة (بحث/سحب للتحديث/عودة
  /// من التفاصيل). [append] = true: «تحميل المزيد» تُلحق عند إزاحة طول
  /// القائمة الحالي — مطابق للويب: load(sales.length, search, true).
  Future<void> _load({required bool append}) async {
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
      }
      _error = null;
    });
    final i18n = AppI18n.instance;
    try {
      final page = await ApiClient.instance.listPOSSales(
        offset: append ? _sales.length : 0,
        search: _search,
      );
      if (!mounted) return;
      setState(() {
        _total = page.total;
        if (append) {
          _sales.addAll(page.sales);
        } else {
          _sales
            ..clear()
            ..addAll(page.sales);
        }
        _loading = false;
        _loadingMore = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('sales', 'loadError'));
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = i18n.t('sales', 'loadError');
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _submitSearch() {
    _debounce?.cancel();
    setState(() => _search = _searchCtrl.text.trim());
    _load(append: false);
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _submitSearch);
  }

  String _invoiceLabel(int n) => 'INV-${n.toString().padLeft(6, '0')}';

  /// وقت 12 ساعة ص/م — مطابق لformatSaleTime في الويب
  /// (Intl: hour numeric, minute 2-digit ⇒ «8:30 ص» / «8:30 am»).
  String _time12h(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '—';
    final ar = AppI18n.instance.locale == 'ar';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final mm = d.minute.toString().padLeft(2, '0');
    final period = ar ? (d.hour < 12 ? 'ص' : 'م') : (d.hour < 12 ? 'am' : 'pm');
    return '$h:$mm $period';
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final hasMore = _sales.length < _total;
    return _loading && _sales.isEmpty
        ? const LoadingBox()
        : RefreshIndicator(
            onRefresh: () => _load(append: false),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                PageHeader(i18n.t('sales', 'title'), subtitle: i18n.t('sales', 'subtitle')),
                const SizedBox(height: 24),
                // صف البحث — نفس form الويب (Input + زر بحث ثانوي)
                Row(
                  children: <Widget>[
                    Expanded(
                      child: SearchField(
                        controller: _searchCtrl,
                        hint: i18n.t('sales', 'searchPlaceholder'),
                        onChanged: _onSearchChanged,
                        onClear: () {
                          _searchCtrl.clear();
                          _submitSearch();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    WButton(i18n.t('sales', 'searchButton'),
                        variant: WButtonVariant.secondary, size: WButtonSize.sm,
                        onPressed: _submitSearch),
                  ],
                ),
                const SizedBox(height: 24),
                if (_error != null && _sales.isEmpty && !_loading)
                  ErrorRetry(_error!, onRetry: () => _load(append: false))
                else if (_sales.isEmpty)
                  // بطاقة الفراغ — ReceiptText + emptyTitle + التلميح حسب البحث
                  AppCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                      child: Column(
                        children: <Widget>[
                          Icon(Icons.receipt_long,
                              size: 40, color: theme.colorScheme.onSurface.withOpacity(0.3)),
                          const SizedBox(height: 12),
                          Text(i18n.t('sales', 'emptyTitle'),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 8),
                          Text(
                            _search.isEmpty ? i18n.t('sales', 'emptyFirstHint') : i18n.t('sales', 'emptySearchHint'),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.55)),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...<Widget>[
                  // خطأ أثناء «تحميل المزيد» — بطاقة خطأ فوق القائمة كما في الويب
                  if (_error != null) ...<Widget>[
                    ErrorBanner(_error!),
                    const SizedBox(height: 12),
                  ],
                  for (final SaleSummary s in _sales)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          AppCard(
                            padding: const EdgeInsets.all(16), // p-4
                            onTap: () async {
                              await Navigator.of(context).push(MaterialPageRoute<void>(
                                builder: (_) => SaleDetailScreen(saleId: s.id),
                              ));
                              _load(append: false);
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
                                      Text(
                                          '${Fmt.date(s.createdAt, locale: i18n.locale)} · ${_time12h(s.createdAt)}',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: theme.colorScheme.onSurface.withOpacity(0.55))),
                                    ],
                                  ),
                                ),
                                Flexible(
                                  child: Text(
                                    // الويب يمرر الرقم الخام: t('productsAndUnits', {units: total_quantity_base})
                                    s.productsCount == 0
                                        ? i18n.t('sales', 'noProducts')
                                        : i18n.t('sales', 'productsAndUnits', {
                                            'products': Fmt.number(s.productsCount),
                                            'units': Fmt.number(s.totalQuantityBase),
                                          }),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 14,
                                        color: theme.colorScheme.onSurface.withOpacity(0.6)),
                                  ),
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
                                // سطر «خصم X» المضمر — مثل web page.tsx:120-122
                                if (s.discountAmountPiastres > 0) ...<Widget>[
                                  const SizedBox(width: 8),
                                  Text(
                                      i18n.t('sales', 'discount',
                                          {'amount': Fmt.money(s.discountAmountPiastres, locale: i18n.locale)}),
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: theme.colorScheme.error)),
                                ],
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: <Widget>[
                                    Text(Fmt.money(s.totalAmountPiastres, locale: i18n.locale),
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                                    if (s.returnedAmountPiastres > 0)
                                      Text(
                                          i18n.t('sales', 'returnedAmount',
                                              {'amount': Fmt.money(s.returnedAmountPiastres, locale: i18n.locale)}),
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: theme.colorScheme.error)),
                                  ],
                                ),
                                const SizedBox(width: 4),
                                // ChevronLeft مع rtl-flip: يشير دائمًا باتجاه التقدم
                                Icon(rtl ? Icons.chevron_left : Icons.chevron_right,
                                    size: 20, color: theme.colorScheme.onSurface.withOpacity(0.45)),
                              ],
                            ),
                          ),
                          // إيصالات الاسترجاع المتداخلة تحت البطاقة — web 136-155
                          for (final SaleReturnSummary r in s.returns)
                            Container(
                              margin: const EdgeInsetsDirectional.only(start: 16, top: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: theme.colorScheme.error.withOpacity(0.30)),
                                color: theme.colorScheme.error.withOpacity(0.05),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Icon(Icons.replay, size: 16, color: theme.colorScheme.error),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(i18n.t('sales', 'returnInvoice'),
                                            style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: theme.colorScheme.error)),
                                      ),
                                      const SizedBox(width: 8),
                                      Text('RET-${r.returnNumber.toString().padLeft(6, '0')}',
                                          textDirection: TextDirection.ltr,
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: theme.colorScheme.onSurface.withOpacity(0.55))),
                                      const Spacer(),
                                      Text('-${Fmt.money(r.totalAmountPiastres, locale: i18n.locale)}',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: theme.colorScheme.error)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text('${Fmt.date(r.createdAt, locale: i18n.locale)} · ${_time12h(r.createdAt)}',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: theme.colorScheme.onSurface.withOpacity(0.55))),
                                  if (r.reason.isNotEmpty) ...<Widget>[
                                    const SizedBox(height: 2),
                                    Text(i18n.t('sales', 'reason', {'reason': r.reason}),
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: theme.colorScheme.onSurface.withOpacity(0.55))),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  // تحميل المزيد — تُلحق الصفحة الجديدة ولا تستبدل (web 159-169)
                  if (hasMore)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Center(
                        child: WButton(
                          i18n.t('sales', 'loadMore'),
                          variant: WButtonVariant.secondary,
                          loading: _loadingMore,
                          onPressed: _loadingMore ? null : () => _load(append: true),
                        ),
                      ),
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

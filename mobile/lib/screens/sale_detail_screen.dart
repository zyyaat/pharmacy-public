import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/ui.dart';

/// تفاصيل الفاتورة + الاسترجاع — مطابقة لصفحة sales/[id] في الويب:
/// أصناف الفاتورة بأسعارها، الإجمالي/المسترجع/الصافي، فواتير الاسترجاع
/// السابقة، ونافذة استرجاع الأصناف بالكميات المتاحة.
class SaleDetailScreen extends StatefulWidget {
  final String saleId;
  const SaleDetailScreen({super.key, required this.saleId});

  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
  SaleDetail? _detail;
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
      final d = await ApiClient.instance.getSale(widget.saleId);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.status == 404 ? i18n.t('sales', 'notFound') : AppI18n.instance.error(e.code, i18n.t('sales', 'detailLoadError'));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.t('sales', 'detailLoadError');
        _loading = false;
      });
    }
  }

  String _qtyLabel(int base) {
    final i18n = AppI18n.instance;
    if (base == 1) return i18n.t('sales', 'oneUnit');
    if (base == 2) return i18n.t('sales', 'twoUnits');
    return i18n.t('sales', 'manyUnits', {'count': Fmt.number(base)});
  }

  Future<void> _openReturn() async {
    final i18n = AppI18n.instance;
    final detail = _detail!;
    final controllers = <String, TextEditingController>{
      for (final SaleItemRow it in detail.items)
        it.saleItemId: TextEditingController(text: '0'),
    };
    final reasonCtrl = TextEditingController();
    final ok = await appBottomSheet<bool>(
      context,
      title: i18n.t('sales', 'returnModalTitle'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(i18n.t('sales', 'returnModalHint'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 12),
          GhostButton(i18n.t('sales', 'fillAllQuantities'), icon: Icons.done_all, onPressed: () {
            for (final SaleItemRow it in detail.items) {
              final available = it.returnableQuantityBase;
              controllers[it.saleItemId]!.text = available > 0 ? '$available' : '0';
            }
          }),
          for (final SaleItemRow it in detail.items)
            if (it.returnableQuantityBase > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('${it.productName} ${it.strength}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(
                            i18n.t('sales', 'availableLine', {
                              'quantity': Fmt.number(it.returnableQuantityBase),
                              'amount': Fmt.money(it.amountPiastres, locale: i18n.locale),
                            }),
                            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 74,
                      child: AppInput(controller: controllers[it.saleItemId]!, keyboard: TextInputType.number),
                    ),
                  ],
                ),
              ),
          AppInput(controller: reasonCtrl, hint: i18n.t('sales', 'returnReasonPlaceholder'), maxLines: 2),
          const SizedBox(height: 12),
          PrimaryButton(
            i18n.t('sales', 'confirmReturn'),
            onPressed: () => Navigator.pop(context, true),
          ),
          const SizedBox(height: 6),
          SecondaryButton(i18n.t('sales', 'cancel'), onPressed: () => Navigator.pop(context, false)),
        ],
      ),
    );
    if (ok != true) return;
    final items = <Map<String, dynamic>>[
      for (final SaleItemRow it in detail.items)
        if ((int.tryParse(controllers[it.saleItemId]!.text.trim()) ?? 0) > 0)
          <String, dynamic>{
            'sale_item_id': it.saleItemId,
            'quantity': int.tryParse(controllers[it.saleItemId]!.text.trim()) ?? 0,
          },
    ];
    if (items.isEmpty) return;
    try {
      final result = await ApiClient.instance.createSaleReturn(
        widget.saleId,
        items,
        reasonCtrl.text.trim(),
        DateTime.now().microsecondsSinceEpoch.toString(),
      );
      if (!mounted) return;
      await appSnackbar(context, i18n.t('sales', 'returnSuccess', {
        'number': Fmt.number(result.returnNumber),
        'amount': Fmt.money(result.totalAmount, locale: i18n.locale),
      }));
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      await appSnackbar(context, AppI18n.instance.error(e.code, i18n.t('sales', 'returnSubmitError')), error: true);
    } catch (_) {
      if (!mounted) return;
      await appSnackbar(context, i18n.t('sales', 'returnSubmitError'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final d = _detail;
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('sales', 'title'))),
      body: _loading
          ? const LoadingBox()
          : _error != null
              ? ErrorRetry(_error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text('#${Fmt.number(d!.sale.invoiceNumber)}',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                              ),
                              AppBadge(
                                d.sale.status == 'completed'
                                    ? i18n.t('sales', 'statusCompleted')
                                    : d.sale.status == 'partially_returned'
                                        ? i18n.t('sales', 'statusPartiallyReturned')
                                        : i18n.t('sales', 'statusReturned'),
                                tone: AppBadge.saleStatus(d.sale.status),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(Fmt.dateTime(d.sale.createdAt, locale: i18n.locale),
                              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                          if (d.sale.customerName.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 4),
                            Text(i18n.t('sales', 'creditBadgeWithCustomer', {'customer': d.sale.customerName}),
                                style: TextStyle(fontSize: 12, color: AppColors.warningFg, fontWeight: FontWeight.w600)),
                          ],
                          const Divider(height: 24),
                          KVRow(i18n.t('sales', 'totalInvoice'), Fmt.money(d.sale.totalAmountPiastres, locale: i18n.locale), money: true),
                          if (d.sale.discountAmountPiastres > 0)
                            KVRow(i18n.t('sales', 'discount', {'amount': Fmt.money(d.sale.discountAmountPiastres, locale: i18n.locale)}), '-${Fmt.money(d.sale.discountAmountPiastres, locale: i18n.locale)}'),
                          if (d.sale.returnedAmountPiastres > 0) ...<Widget>[
                            KVRow(i18n.t('sales', 'totalReturned'), Fmt.money(d.sale.returnedAmountPiastres, locale: i18n.locale)),
                            KVRow(i18n.t('sales', 'netAfterReturn'), Fmt.money(d.sale.totalAmountPiastres - d.sale.returnedAmountPiastres, locale: i18n.locale)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SectionHeader(i18n.t('sales', 'invoiceItems')),
                    AppCard(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: <Widget>[
                          for (final SaleItemRow it in d.items) ...<Widget>[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text('${it.productName} ${it.strength}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${_qtyLabel(it.quantityBase)} × ${Fmt.money(it.unitPricePiastres, locale: i18n.locale)}'
                                        '${it.returnedQuantityBase > 0 ? ' · ${i18n.t('sales', 'returnedUnits', {'count': Fmt.number(it.returnedQuantityBase)})}' : ''}',
                                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.55)),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(Fmt.money(it.amountPiastres, locale: i18n.locale), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                              ],
                            ),
                            if (it != d.items.last) const Divider(height: 16),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (d.sale.returns.isNotEmpty) ...<Widget>[
                      SectionHeader(i18n.t('sales', 'returnsTitle', {'count': Fmt.number(d.sale.returns.length)})),
                      for (final SaleReturnSummary r in d.sale.returns)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AmountRow(
                            title: 'RET-${Fmt.number(r.returnNumber)}',
                            subtitle: '${Fmt.dateTime(r.createdAt, locale: i18n.locale)} · ${i18n.t('sales', 'reason', {'reason': r.reason.isEmpty ? '—' : r.reason})}',
                            amountPiastres: r.totalAmountPiastres,
                            credit: true,
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],
                    if (d.items.any((SaleItemRow it) => it.returnableQuantityBase > 0)) ...<Widget>[
                      const SizedBox(height: 4),
                      PrimaryButton(i18n.t('sales', 'returnItems'), icon: Icons.undo, onPressed: _openReturn),
                    ],
                  ],
                ),
    );
  }
}

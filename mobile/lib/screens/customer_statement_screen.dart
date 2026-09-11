import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// كشف حساب العميل — قيود الآجل والمدفوعات بالرصيد الجاري، ونافذة
/// تحصيل دفعة (بالبياسترات الصحيحة دائمًا).
class CustomerStatementScreen extends StatefulWidget {
  final Customer customer;
  const CustomerStatementScreen({super.key, required this.customer});

  @override
  State<CustomerStatementScreen> createState() => _CustomerStatementScreenState();
}

class _CustomerStatementScreenState extends State<CustomerStatementScreen> {
  CustomerStatement? _statement;
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
      final s = await ApiClient.instance.customerStatement(widget.customer.id);
      if (!mounted) return;
      setState(() {
        _statement = s;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('customers', 'statementError'));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.t('customers', 'statementError');
        _loading = false;
      });
    }
  }

  Future<void> _pay() async {
    final i18n = AppI18n.instance;
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final ok = await appBottomSheet<bool>(
      context,
      title: i18n.t('customers', 'paymentsTitle'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(i18n.t('customers', 'paymentsHint'), style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55))),
          const SizedBox(height: 10),
          AppField(
            label: i18n.t('customers', 'amountLabel'),
            child: AppInput(controller: amountCtrl, hint: i18n.t('customers', 'amountPlaceholder'), keyboard: const TextInputType.numberWithOptions(decimal: true)),
          ),
          const SizedBox(height: 10),
          AppField(label: i18n.t('customers', 'noteLabel'), child: AppInput(controller: noteCtrl, hint: i18n.t('customers', 'notePlaceholder'))),
          const SizedBox(height: 12),
          PrimaryButton(i18n.t('customers', 'recordPayment'), onPressed: () => Navigator.pop(context, true)),
          const SizedBox(height: 6),
          SecondaryButton(i18n.t('customers', 'cancel'), onPressed: () => Navigator.pop(context, false)),
        ],
      ),
    );
    if (ok != true) return;
    final piastres = Fmt.parseEGPToPiastres(amountCtrl.text);
    if (piastres == null || piastres <= 0) {
      // المفتاح الصحيح amountInvalid مثل الويب (page.tsx:120)
      await appSnackbar(context, i18n.t('customers', 'amountInvalid'), error: true);
      return;
    }
    try {
      await ApiClient.instance.createCustomerPayment(widget.customer.id, piastres, noteCtrl.text.trim());
      if (!mounted) return;
      await appSnackbar(context, i18n.t('customers', 'recordPayment'));
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      await appSnackbar(context, AppI18n.instance.error(e.code, i18n.t('customers', 'paymentError')), error: true);
    } catch (_) {
      if (!mounted) return;
      await appSnackbar(context, i18n.t('customers', 'paymentError'), error: true);
    }
  }

  /// عمودا عليه/سداد: الآجل يظهر عليه بالأحمر، والتحصيل سداد بالأخضر،
  /// والفراغ شرطة صريحة — كأعمدة جدول الكشف في صفحة عملاء الويب
  Widget _duePaidCells(BuildContext context, StatementEntry e) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withOpacity(0.5);
    final String due = e.isPayment ? '—' : Fmt.money(e.dueAmountPiastres, locale: i18n.locale);
    final String paid = e.isPayment ? Fmt.money(e.amountPiastres, locale: i18n.locale) : '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(i18n.t('customers', 'colDue'), style: TextStyle(fontSize: 10, color: muted)),
            const SizedBox(width: 4),
            Text(due,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: e.isPayment ? muted : theme.colorScheme.error)),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(i18n.t('customers', 'colPaid'), style: TextStyle(fontSize: 10, color: muted)),
            const SizedBox(width: 4),
            Text(paid,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: e.isPayment ? AppColors.successFg : muted)),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final s = _statement;
    // بوابة التحصيل مثل Can perm="customers.payments" في الويب (page.tsx:276) —
    // الإخفاء لا التعطيل
    final canPay = context.watch<AppState>().can('customers.payments');
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('customers', 'statementTitleFor', {'name': widget.customer.name}))),
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
                          // ترويسة الكشف بالويب: الهاتف أو «بدون رقم هاتف»
                          Text(
                            widget.customer.phone.isEmpty ? i18n.t('customers', 'noPhone') : widget.customer.phone,
                            style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.6)),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(i18n.t('customers', 'currentBalance'),
                                    style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.6))),
                              ),
                              // المستحق بنغمة destructive حمراء مثل الويب (وليس amber)
                              Text(
                                Fmt.money(s!.balancePiastres, locale: i18n.locale),
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: s.balancePiastres > 0 ? theme.colorScheme.error : AppColors.successFg,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (canPay) ...<Widget>[
                      const SizedBox(height: 14),
                      PrimaryButton(i18n.t('customers', 'recordPayment'), icon: Icons.payments_outlined, onPressed: _pay),
                      const SizedBox(height: 16),
                    ],
                    if (s.entries.isEmpty)
                      EmptyState(i18n.t('customers', 'emptyStatement'), icon: Icons.receipt_long_outlined)
                    else
                      for (final StatementEntry e in s.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AppCard(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Expanded(
                                      child: e.isPayment
                                          ? Text(i18n.t('customers', 'paymentEntry'),
                                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))
                                          : Text.rich(
                                              TextSpan(
                                                children: <InlineSpan>[
                                                  TextSpan(text: i18n.t('customers', 'creditSale')),
                                                  if (e.invoiceNumber != null)
                                                    TextSpan(
                                                      // مرجع الفاتورة مُبطن INV-000123 بخط monospace مثل الويب
                                                      text: ' INV-${e.invoiceNumber!.toString().padLeft(6, '0')}',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontFamily: 'monospace',
                                                        color: theme.colorScheme.onSurface.withOpacity(0.75),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                            ),
                                    ),
                                    const SizedBox(width: 8),
                                    // عمودا «عليه/سداد» كصفوف الجدول في الويب (page.tsx:261-266)
                                    _duePaidCells(context, e),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${Fmt.dateTime(e.createdAt, locale: i18n.locale)} · ${i18n.t('customers', 'colBalance')}: ${Fmt.money(e.balancePiastres, locale: i18n.locale)}',
                                  style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                                ),
                                if (!e.isPayment && e.returnedAmountPiastres > 0)
                                  Text(
                                    i18n.t('sales', 'returnedAmount', {'amount': Fmt.money(e.returnedAmountPiastres, locale: i18n.locale)}),
                                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.6)),
                                  ),
                                if (e.note != null && e.note!.isNotEmpty)
                                  Text(e.note!, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.6))),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
    );
  }
}

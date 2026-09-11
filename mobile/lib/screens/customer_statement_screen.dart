import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
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
      await appSnackbar(context, i18n.t('customers', 'paymentInvalid'), error: true);
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

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final s = _statement;
    return Scaffold(
      appBar: AppBar(title: Text(widget.customer.name)),
      body: _loading
          ? const LoadingBox()
          : _error != null
              ? ErrorRetry(_error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    AppCard(
                      child: Column(
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(i18n.t('customers', 'currentBalance'),
                                    style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.6))),
                              ),
                              Text(
                                Fmt.money(s!.balancePiastres, locale: i18n.locale),
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: s.balancePiastres > 0 ? AppColors.warningFg : AppColors.successFg,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    PrimaryButton(i18n.t('customers', 'recordPayment'), icon: Icons.payments_outlined, onPressed: _pay),
                    const SizedBox(height: 16),
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
                                  children: <Widget>[
                                    Expanded(
                                      child: Text(
                                        e.isPayment
                                            ? i18n.t('customers', 'paymentEntry')
                                            : i18n.t('customers', 'creditSale') + (e.invoiceNumber == null ? '' : ' #${Fmt.number(e.invoiceNumber!)}'),
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    Text(
                                      (e.isPayment ? '+' : '') + Fmt.money(e.amountPiastres, locale: i18n.locale),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: e.isPayment ? AppColors.successFg : AppColors.warningFg,
                                      ),
                                    ),
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

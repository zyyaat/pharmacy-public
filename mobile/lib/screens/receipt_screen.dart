import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../models/models.dart';
import '../widgets/ui.dart';

/// معاينة الإيصال الحراري — نسخة موبايل من receipt-template في الويب:
/// نفس الحقول بترتيبها، بنفس قواعد الإعدادات (بادئة الاسم، الهاتف، العنوان،
/// الكاشير، الشكر، سياسة الاسترجاع) وبعرض الورق المختار.
class ReceiptScreen extends StatefulWidget {
  final String saleId;
  const ReceiptScreen({super.key, required this.saleId});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  SaleDetail? _detail;
  ReceiptSettings? _settings;
  String? _pharmacyName;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final i18n = AppI18n.instance;
    try {
      final detail = await ApiClient.instance.getSale(widget.saleId);
      ReceiptSettings settings = ReceiptSettings(
        paperWidthMm: 80, printMode: 'auto', copies: 1, namePrefix: '',
        thankYouText: '', returnPolicyText: '', showPhone: false, showAddress: false,
        showCashier: false, showThankYou: true, showReturnPolicy: true,
      );
      try {
        settings = await ApiClient.instance.getSettings();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _settings = settings;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('sales', 'detailLoadError'));
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

  String get _receiptText {
    final i18n = AppI18n.instance;
    final d = _detail!;
    final s = _settings!;
    final buf = StringBuffer();
    final name = s.namePrefix.isEmpty ? (_pharmacyName ?? i18n.t('pos', 'fallbackPharmacyName')) : '${s.namePrefix} $_pharmacyName';
    buf.writeln(name);
    buf.writeln('${i18n.t('pos', 'invoiceNo')} ${Fmt.number(d.sale.invoiceNumber)}');
    buf.writeln('${i18n.t('pos', 'date')}: ${Fmt.dateTime(d.sale.createdAt, locale: i18n.locale)}');
    buf.writeln('---');
    for (final SaleItemRow it in d.items) {
      final qty = it.saleUnit == 'box'
          ? i18n.t('pos', 'qtyBox', {'count': Fmt.number(it.quantityBase)})
          : i18n.t('pos', 'qtyStrip', {'count': Fmt.number(it.quantityBase)});
      buf.writeln('${it.productName} ${it.strength}');
      buf.writeln('  $qty × ${Fmt.money(it.unitPricePiastres, locale: i18n.locale)} = ${Fmt.money(it.amountPiastres, locale: i18n.locale)}');
    }
    buf.writeln('---');
    if (d.sale.discountAmountPiastres > 0) {
      buf.writeln('${i18n.t('sales', 'discount', {'amount': Fmt.money(d.sale.discountAmountPiastres, locale: i18n.locale)})}');
    }
    buf.writeln('${i18n.t('pos', 'totalWithItems', {'items': Fmt.number(d.items.length)})}: ${Fmt.money(d.sale.totalAmountPiastres, locale: i18n.locale)}');
    if (d.sale.paymentType == 'credit') {
      buf.writeln(i18n.t('pos', 'creditInvoice'));
    }
    if (s.showThankYou) {
      buf.writeln(s.thankYouText.isEmpty ? i18n.t('pos', 'defaultThankYou') : s.thankYouText);
    }
    if (s.showReturnPolicy) {
      buf.writeln(s.returnPolicyText.isEmpty ? i18n.t('pos', 'defaultReturnPolicy') : s.returnPolicyText);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('pos', 'invoiceNo'))),
      body: _loading
          ? const LoadingBox()
          : _error != null
              ? ErrorRetry(_error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    Center(
                      child: Container(
                        width: _settings!.paperWidthMm == 58 ? 260 : 320,
                        padding: const EdgeInsets.all(14),
                        color: theme.brightness == Brightness.dark ? Colors.white : Colors.white,
                        child: DefaultTextStyle(
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: _settings!.paperWidthMm == 58 ? 11 : 12,
                            fontFamily: 'monospace',
                            height: 1.5,
                          ),
                          child: Text(_receiptText),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_settings!.copies == 2) ...<Widget>[
                      Center(child: Text(i18n.t('pos', 'copyPharmacy'), style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55)))),
                      const SizedBox(height: 8),
                    ],
                    SecondaryButton(
                      i18n.t('common', 'copy'),
                      icon: Icons.copy,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _receiptText));
                        appSnackbar(context, i18n.t('common', 'done'));
                      },
                    ),
                    const SizedBox(height: 8),
                    SecondaryButton(
                      i18n.t('common', 'back'),
                      icon: Icons.arrow_back,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
    );
  }
}

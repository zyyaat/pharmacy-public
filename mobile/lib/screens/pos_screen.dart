import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../state/app_state.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/ui.dart';
import 'receipt_screen.dart';

/// Task 62 — نقطة البيع بنسخة الويب حرفيًا: بطاقة إضافة الأصناف (بحث/باركود
/// بتصحيح)، بطاقة السلة (عنوان + وصف العدد، أزرار إيقاف/تفريغ، شرائط
/// الفواتير المعلقة على bg-muted/40، سطور rounded-xl border بوحدة وعدّاد
/// h-10، صندوق الخصم/الدفع، صندوق العميل الآجل border-primary/30
/// bg-primary/5، صف الإجمالي text-2xl primary مع فاصل علوي).
/// الأسعار المرجعية من الخادم دائمًا (409 price_changed يعرض رسالة الخادم).
class POSScreen extends StatefulWidget {
  const POSScreen({super.key});

  @override
  State<POSScreen> createState() => _POSScreenState();
}

class _CartLine {
  final Product product;
  bool isBox;
  int qty = 1;
  _CartLine({required this.product, this.isBox = true});

  int get unitPricePiastres => isBox
      ? product.sellingPricePiastres
      : Fmt.stripPrice(
          sellingPricePiastres: product.sellingPricePiastres,
          partialSellingPricePiastres: product.partialSellingPricePiastres,
          unitsPerBox: product.unitsPerBox,
        );

  int get lineTotal => unitPricePiastres * qty;
}

class _ParkedSale {
  final List<_CartLine> lines;
  _ParkedSale(this.lines);
}

class _POSScreenState extends State<POSScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _discountCtrl = TextEditingController();
  final List<_CartLine> _cart = <_CartLine>[];
  final List<_ParkedSale> _parked = <_ParkedSale>[];
  List<Product> _suggestions = <Product>[];
  bool _searching = false;
  Timer? _debounce;
  bool _discountIsPercent = true;
  bool _credit = false;
  Customer? _customer;
  bool _checkingOut = false;
  String? _message;
  String? _error;
  String? _lastSaleId;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _doSearch(v.trim()));
  }

  Future<void> _doSearch(String q) async {
    if (q.isEmpty) {
      setState(() => _suggestions = <Product>[]);
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await ApiClient.instance.searchPOSProducts(q);
      if (!mounted) return;
      setState(() => _suggestions = results);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _suggestions = <Product>[]);
      appSnackbar(context, AppI18n.instance.error(e.code, e.message), error: true);
    } catch (_) {
      if (mounted) setState(() => _suggestions = <Product>[]);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  /// باركود Enter: مطابقة تامة تُضاف مباشرة — وإلا تظهر الاقتراحات
  Future<void> _onBarcodeSubmitted(String barcode) async {
    final b = barcode.trim();
    if (b.isEmpty) return;
    setState(() => _searching = true);
    try {
      final exact = await ApiClient.instance.lookupPOSProduct(b);
      if (!mounted) return;
      if (exact != null) {
        _addLine(exact);
        _searchCtrl.clear();
        setState(() => _suggestions = <Product>[]);
      } else {
        final results = await ApiClient.instance.searchPOSProducts(b);
        if (!mounted) return;
        setState(() {
          _suggestions = results;
          _error = results.isEmpty ? AppI18n.instance.t('pos', 'barcodeNoProduct') : AppI18n.instance.t('pos', 'barcodeNotExact');
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = AppI18n.instance.t('pos', 'barcodeSearchFailed'));
      appSnackbar(context, AppI18n.instance.error(e.code, e.message), error: true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _addLine(Product p) {
    final existing = _cart.where((_CartLine l) => l.product.id == p.id && l.isBox).toList();
    if (existing.isNotEmpty) {
      setState(() => existing.first.qty += 1);
      return;
    }
    setState(() => _cart.add(_CartLine(product: p, isBox: p.boxStrip)));
  }

  int get _subtotal => _cart.fold<int>(0, (int sum, _CartLine l) => sum + l.lineTotal);

  int get _discountPiastres {
    final raw = _discountCtrl.text.trim();
    if (raw.isEmpty || _cart.isEmpty) return 0;
    if (_discountIsPercent) {
      final pct = double.tryParse(raw.replaceAll('%', ''));
      if (pct == null || pct <= 0 || pct > 100) return 0;
      return (_subtotal * pct / 100).round();
    }
    final egp = Fmt.parseEGPToPiastres(raw);
    if (egp == null || egp <= 0) return 0;
    return egp > _subtotal ? _subtotal : egp;
  }

  bool get _discountInvalid => _discountCtrl.text.trim().isNotEmpty && _discountPiastres == 0;

  int get _total {
    final t = _subtotal - _discountPiastres;
    return t < 0 ? 0 : t;
  }

  // ------------------------------------------------------------ إيقاف مؤقت

  void _park() {
    if (_cart.isEmpty) return;
    final i18n = AppI18n.instance;
    setState(() {
      _parked.insert(0, _ParkedSale(List<_CartLine>.from(_cart)));
      _cart.clear();
      _discountCtrl.clear();
      _credit = false;
      _customer = null;
    });
    appSnackbar(context, i18n.t('pos', 'parkedInvoices'));
  }

  void _resume(_ParkedSale p) {
    if (_cart.isNotEmpty) {
      final i18n = AppI18n.instance;
      confirmDialog(context, title: i18n.t('pos', 'resumeConfirm'), body: i18n.t('pos', 'resumeConfirm')).then((bool? ok) {
        if (ok == true) _applyResume(p);
      });
      return;
    }
    _applyResume(p);
  }

  void _applyResume(_ParkedSale p) {
    setState(() {
      _cart.addAll(p.lines);
      _parked.remove(p);
    });
  }

  // ------------------------------------------------------------ الدفع

  Future<void> _pickCustomer() async {
    final picked = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CustomerPickerSheet(),
    );
    if (picked != null && mounted) setState(() => _customer = picked);
  }

  Future<void> _checkout() async {
    final i18n = AppI18n.instance;
    if (_cart.isEmpty || _checkingOut) return;
    if (_discountInvalid) {
      setState(() => _error = _discountIsPercent ? i18n.t('pos', 'discountPercentError') : i18n.t('pos', 'discountAmountError'));
      return;
    }
    if (_credit && _customer == null) {
      setState(() => _error = i18n.t('pos', 'creditRequiresCustomer'));
      return;
    }
    setState(() {
      _checkingOut = true;
      _error = null;
      _message = null;
    });
    try {
      final items = <Map<String, dynamic>>[
        for (final _CartLine l in _cart)
          <String, dynamic>{
            'pharmacy_product_id': l.product.id,
            'sale_unit': l.isBox ? 'box' : 'strip',
            'quantity': l.qty,
          },
      ];
      final options = <String, dynamic>{};
      final discount = _discountPiastres;
      if (discount > 0) {
        options['discount'] = _discountIsPercent
            ? <String, dynamic>{'kind': 'percent', 'value': double.tryParse(_discountCtrl.text.trim()) ?? 0}
            : <String, dynamic>{'kind': 'amount', 'value': discount};
      }
      if (_credit && _customer != null) {
        options['payment_type'] = 'credit';
        options['customer_id'] = _customer!.id;
      }
      final result = await ApiClient.instance.createPOSSale(
        items: items,
        idempotencyKey: DateTime.now().microsecondsSinceEpoch.toString(),
        options: options.isEmpty ? null : options,
      );
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _discountCtrl.clear();
        _credit = false;
        _customer = null;
        _lastSaleId = result.saleId;
        _message = i18n.t('pos', 'saleSuccess', {'total': Fmt.money(result.totalAmount, locale: i18n.locale)});
      });
      await _openReceipt(result.saleId);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.status == 409 ? e.message : i18n.error(e.code, i18n.t('errors', 'sale_failed')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = AppI18n.instance.t('errors', 'sale_failed'));
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  Future<void> _openReceipt(String saleId) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReceiptScreen(saleId: saleId)));
  }

  // ------------------------------------------------------------ الواجهة

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        PageHeader(i18n.t('pos', 'title'), subtitle: i18n.t('pos', 'subtitle')),
        const SizedBox(height: 24),

        // بطاقة إضافة الأصناف
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: CardTitle(i18n.t('pos', 'addProductTitle'),
                    icon: Icons.search, subtitle: i18n.t('pos', 'addProductDesc')),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: <Widget>[
                    TextField(
                      controller: _searchCtrl,
                      onChanged: _onSearchChanged,
                      onSubmitted: _onBarcodeSubmitted,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        hintText: i18n.t('pos', 'searchPlaceholder'),
                        prefixIcon: const Icon(Icons.qr_code_scanner, size: 20),
                        suffixIcon: _searching
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                            : (_searchCtrl.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() => _suggestions = <Product>[]);
                                    },
                                  )),
                        isDense: true,
                      ),
                    ),
                    if (_suggestions.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: AppRadius.br,
                          border: Border.all(color: theme.dividerColor),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: <Widget>[
                            for (final Product p in _suggestions.take(6))
                              _SuggestionTile(product: p, onAdd: () => _addLine(p)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // بطاقة السلة
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: CardTitle(
                        i18n.t('pos', 'cartTitle'),
                        icon: Icons.receipt_long_outlined,
                        subtitle: _cart.isNotEmpty
                            ? i18n.t('pos', 'cartCount', {'count': Fmt.number(_cart.length)})
                            : i18n.t('pos', 'cartEmpty'),
                      ),
                    ),
                    if (_cart.isNotEmpty) ...<Widget>[
                      WButton(i18n.t('pos', 'park'),
                          icon: Icons.pause_circle_outline,
                          variant: WButtonVariant.outline,
                          onPressed: _park),
                      const SizedBox(width: 8),
                      IconButtonGhost(
                        Icons.delete_outline,
                        tooltip: i18n.t('pos', 'clearCart'),
                        color: theme.colorScheme.error,
                        onPressed: () => setState(() {
                          _cart.clear();
                          _discountCtrl.clear();
                        }),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // الفواتير المعلّقة — شرائط استئناف/حذف على خلفية muted/40
                    if (_parked.isNotEmpty) ...<Widget>[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface.withOpacity(0.04),
                          borderRadius: AppRadius.brXl,
                        ),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            Text(i18n.t('pos', 'parkedInvoices'),
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                            for (final _ParkedSale p in _parked)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: theme.dividerColor),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    GestureDetector(
                                      onTap: () => _resume(p),
                                      child: Text(
                                        i18n.t('pos', 'parkedLabelMany', {
                                          'count': Fmt.number(p.lines.length),
                                          'total': Fmt.money(p.lines.fold<int>(0, (int s, _CartLine l) => s + l.lineTotal), locale: i18n.locale),
                                        }),
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () => setState(() => _parked.remove(p)),
                                      child: Icon(Icons.delete_outline,
                                          size: 14, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_cart.isEmpty)
                      EmptyState(i18n.t('pos', 'startEmpty'), icon: null, dashed: true)
                    else
                      for (final _CartLine l in _cart) ...<Widget>[
                        _CartLineTile(line: l, onChanged: () => setState(() {}), onRemove: () => setState(() => _cart.remove(l))),
                        const SizedBox(height: 12),
                      ],

                    // الخصم + طريقة الدفع
                    if (_cart.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      CardBox(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(
                                  flex: 2,
                                  child: AppField(
                                    label: i18n.t('pos', 'discountLabel'),
                                    child: AppInput(
                                      controller: _discountCtrl,
                                      keyboard: const TextInputType.numberWithOptions(decimal: true),
                                      hint: _discountIsPercent ? i18n.t('pos', 'discountPercentPlaceholder') : i18n.t('pos', 'discountAmountPlaceholder'),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: AppField(
                                    label: '',
                                    child: AppDropdown<String>(
                                      value: _discountIsPercent ? 'percent' : 'amount',
                                      items: <DropdownMenuItem<String>>[
                                        DropdownMenuItem<String>(value: 'amount', child: Text(i18n.t('pos', 'discountKindAmount'), style: const TextStyle(fontSize: 13))),
                                        DropdownMenuItem<String>(value: 'percent', child: Text(i18n.t('pos', 'discountKindPercent'), style: const TextStyle(fontSize: 13))),
                                      ],
                                      onChanged: (String? v) => setState(() {
                                        _discountIsPercent = v == 'percent';
                                        _discountCtrl.clear();
                                      }),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_discountInvalid)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  _discountIsPercent ? i18n.t('pos', 'discountInvalidPercent') : i18n.t('pos', 'discountInvalidAmount'),
                                  style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
                                ),
                              ),
                            const SizedBox(height: 16),
                            AppField(
                              label: i18n.t('pos', 'paymentLabel'),
                              child: AppDropdown<String>(
                                value: _credit ? 'credit' : 'cash',
                                items: <DropdownMenuItem<String>>[
                                  DropdownMenuItem<String>(value: 'cash', child: Text(i18n.t('pos', 'paymentCash'), style: const TextStyle(fontSize: 14))),
                                  if (context.read<AppState>().can('customers.view'))
                                    DropdownMenuItem<String>(value: 'credit', child: Text(i18n.t('pos', 'paymentCredit'), style: const TextStyle(fontSize: 14))),
                                ],
                                onChanged: (String? v) => setState(() => _credit = v == 'credit'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // اختيار العميل للآجل
                      if (_credit) ...<Widget>[
                        CardBox(
                          borderColor: theme.colorScheme.primary.withOpacity(0.30),
                          color: theme.colorScheme.primary.withOpacity(0.05),
                          child: _customer == null
                              ? InkWell(
                                  borderRadius: AppRadius.brXl,
                                  onTap: _pickCustomer,
                                  child: Row(
                                    children: <Widget>[
                                      Icon(Icons.person_outline, size: 20, color: theme.colorScheme.primary),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(i18n.t('pos', 'customerSearchPlaceholder'), style: const TextStyle(fontSize: 14))),
                                      Text(i18n.t('pos', 'changeCustomer'),
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
                                    ],
                                  ),
                                )
                              : Row(
                                  children: <Widget>[
                                    Icon(Icons.person, size: 20, color: theme.colorScheme.primary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(_customer!.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                          Text(
                                            '${_customer!.phone.isEmpty ? i18n.t('pos', 'noPhone') : _customer!.phone}'
                                            '${_customer!.balancePiastres != 0 ? ' · ${Fmt.money(_customer!.balancePiastres, locale: i18n.locale)}' : ''}',
                                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    GhostButton(i18n.t('pos', 'changeCustomer'), onPressed: _pickCustomer),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // صف الإجماليات
                      Container(
                        padding: const EdgeInsets.only(top: 20), // border-t pt-5
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: theme.dividerColor)),
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(i18n.t('pos', 'totalsHint'),
                                  style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: <Widget>[
                                if (_discountPiastres > 0) ...<Widget>[
                                  Text(i18n.t('pos', 'beforeDiscount', {'total': Fmt.money(_subtotal, locale: i18n.locale)}),
                                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                                  Text(i18n.t('pos', 'discountLine', {'total': Fmt.money(_discountPiastres, locale: i18n.locale)}),
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.error)),
                                ],
                                Text(i18n.t('pos', 'total'),
                                    style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                                Text(Fmt.money(_total, locale: i18n.locale),
                                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
                              ],
                            ),
                            const SizedBox(width: 20),
                            WButton(
                              _credit ? i18n.t('pos', 'checkoutCredit') : i18n.t('pos', 'checkout'),
                              onPressed: _checkout,
                              loading: _checkingOut,
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (_error != null) ...<Widget>[
                      const SizedBox(height: 16),
                      ErrorBanner(_error!),
                    ],
                    if (_message != null) ...<Widget>[
                      const SizedBox(height: 16),
                      SuccessBanner(
                        _message!,
                        action: _lastSaleId != null
                            ? WButton(
                                i18n.t('pos', 'printInvoice'),
                                icon: Icons.print_outlined,
                                variant: WButtonVariant.outline,
                                size: WButtonSize.sm,
                                onPressed: () => _openReceipt(_lastSaleId!),
                              )
                            : null,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// صف اقتراح داخل صندوق محدد بفواصل — مثل dropdown نتائج الويب
class _SuggestionTile extends StatelessWidget {
  final Product product;
  final VoidCallback onAdd;
  const _SuggestionTile({required this.product, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final boxes = product.boxStrip ? product.stock ~/ (product.unitsPerBox > 0 ? product.unitsPerBox : 1) : product.stock;
    final strips = product.boxStrip ? product.stock % (product.unitsPerBox > 0 ? product.unitsPerBox : 1) : 0;
    final stockText = product.boxStrip
        ? i18n.t('pos', 'stockBoxStrip', {'boxes': Fmt.number(boxes), 'strips': Fmt.number(strips)})
        : i18n.t('pos', 'stockPacks', {'count': Fmt.number(product.stock)});
    return InkWell(
      onTap: onAdd,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('${product.name} ${product.strength}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(stockText, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(Fmt.money(product.boxStrip ? product.sellingPricePiastres : Fmt.stripPrice(sellingPricePiastres: product.sellingPricePiastres, partialSellingPricePiastres: product.partialSellingPricePiastres, unitsPerBox: product.unitsPerBox), locale: i18n.locale),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                Icon(Icons.add_circle, size: 20, color: theme.colorScheme.primary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// سطر سلة POS — rounded-xl border p-4: الاسم + المخزون، اختيار الوحدة،
/// عدّاد كمية h-10 rounded-lg، الإجمالي + تحذير تجاوز المخزون، وحذف شبحي.
class _CartLineTile extends StatelessWidget {
  final _CartLine line;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  const _CartLineTile({required this.line, required this.onChanged, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final p = line.product;
    final unitsPerBox = p.unitsPerBox > 0 ? p.unitsPerBox : 1;
    final boxes = p.boxStrip ? p.stock ~/ unitsPerBox : p.stock;
    final strips = p.boxStrip ? p.stock % unitsPerBox : 0;
    final stockText = p.boxStrip
        ? i18n.t('pos', 'stockBoxStrip', {'boxes': Fmt.number(boxes), 'strips': Fmt.number(strips)})
        : i18n.t('pos', 'stockPacks', {'count': Fmt.number(p.stock)});
    final requestedBase = line.isBox ? line.qty * unitsPerBox : line.qty;
    String unitLabel;
    if (line.isBox) {
      unitLabel = i18n.t('pos', 'unitBox');
    } else {
      unitLabel = line.qty == 1
          ? i18n.t('pos', 'unitStripOne')
          : line.qty == 2
              ? i18n.t('pos', 'unitStripTwo')
              : i18n.t('pos', 'unitStrips', {'count': Fmt.number(line.qty)});
    }
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('${p.name}${p.strength.isEmpty ? '' : ' ${p.strength}'}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('${p.barcode} · $stockText',
                        style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                  ],
                ),
              ),
              IconButtonGhost(
                Icons.delete_outline,
                tooltip: i18n.t('pos', 'deleteLine'),
                color: theme.colorScheme.error,
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              // الوحدة
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(i18n.t('pos', 'unitLabel'), style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                    const SizedBox(height: 4),
                    if (p.boxStrip)
                      AppDropdown<String>(
                        value: line.isBox ? 'box' : '1',
                        items: <DropdownMenuItem<String>>[
                          DropdownMenuItem<String>(value: 'box', child: Text(i18n.t('pos', 'unitBox'), style: const TextStyle(fontSize: 13))),
                          for (int s = 1; s < unitsPerBox; s++)
                            DropdownMenuItem<String>(
                              value: '$s',
                              child: Text(
                                s == 1 ? i18n.t('pos', 'unitStripOne') : s == 2 ? i18n.t('pos', 'unitStripTwo') : i18n.t('pos', 'unitStrips', {'count': Fmt.number(s)}),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                        ],
                        onChanged: (String? v) {
                          line.isBox = v == 'box';
                          line.qty = 1;
                          onChanged();
                        },
                      )
                    else
                      Text(unitLabel, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // الكمية
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(i18n.t('pos', 'quantity'), style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                    const SizedBox(height: 4),
                    QtyStepper(
                      value: line.qty,
                      onDec: () {
                        if (line.qty > 1) {
                          line.qty -= 1;
                          onChanged();
                        }
                      },
                      onInc: () {
                        line.qty += 1;
                        onChanged();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // الإجمالي
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(unitLabel, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                    const SizedBox(height: 4),
                    Text(Fmt.money(line.lineTotal, locale: i18n.locale),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    if (requestedBase > p.stock)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(i18n.t('pos', 'overStock'),
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.error)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// منتقي العملاء للآجل: بحث + إضافة عميل جديد (كصفحة الويب)
class _CustomerPickerSheet extends StatefulWidget {
  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _newName = TextEditingController();
  final TextEditingController _newPhone = TextEditingController();
  List<Customer> _list = <Customer>[];
  bool _loading = true;
  bool _adding = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _newName.dispose();
    _newPhone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ApiClient.instance.customers(search: _search.text.trim());
      if (!mounted) return;
      setState(() {
        _list = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _addNew() async {
    final name = _newName.text.trim();
    if (name.isEmpty || _adding) return;
    setState(() => _adding = true);
    try {
      final c = await ApiClient.instance.createCustomer(name, _newPhone.text.trim());
      if (!mounted) return;
      Navigator.pop(context, c);
    } on ApiException catch (e) {
      if (!mounted) return;
      appSnackbar(context, AppI18n.instance.error(e.code, e.message), error: true);
      setState(() => _adding = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(i18n.t('nav', 'customers'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              SearchField(controller: _search, hint: i18n.t('pos', 'customerSearchPlaceholder'), onChanged: _onChanged, onClear: () { _search.clear(); _load(); }),
              const SizedBox(height: 12),
              if (_loading)
                const LoadingBox()
              else if (_list.isEmpty)
                Text(i18n.t('common', 'no_options'), style: const TextStyle(fontSize: 14), textAlign: TextAlign.center)
              else
                ..._list.take(8).map((Customer c) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(c.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text(c.phone.isEmpty ? i18n.t('pos', 'noPhoneShort') : c.phone, style: const TextStyle(fontSize: 12)),
                      trailing: Text(Fmt.money(c.balancePiastres, locale: i18n.locale),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.balancePiastres > 0 ? AppColors.warningFg : null)),
                      onTap: () => Navigator.pop(context, c),
                    )),
              const Divider(height: 22),
              Text(i18n.t('pos', 'customerAutoAddedHint'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55))),
              const SizedBox(height: 8),
              AppInput(controller: _newName, hint: i18n.t('pos', 'customerNamePlaceholder')),
              const SizedBox(height: 8),
              AppInput(controller: _newPhone, hint: i18n.t('pos', 'customerPhonePlaceholder'), keyboard: TextInputType.phone),
              const SizedBox(height: 12),
              WButton(i18n.t('pos', 'add'), icon: Icons.person_add_alt_1, loading: _adding, onPressed: _addNew),
            ],
          ),
        ),
      ),
    );
  }
}

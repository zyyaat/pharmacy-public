import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/ui.dart';
import 'receipt_screen.dart';

/// نقطة البيع — بنية صفحة الويب نفسها: بحث/باركود بتصحيح أخطاء، سلة
/// بوحدات بيع (علبة/شريط)، خصم، نقدي/آجل بعميل، إيقاف مؤقت للفاتورة،
/// وإيصال بعد الحفظ. الأسعار المرجعية من الخادم دائمًا (409 price_changed
/// يعرض رسالة الخادم كما يفعل الويب).
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
    final existing = _cart.where((_CartLine l) => l.product.id == p.id).toList();
    if (existing.isNotEmpty) {
      setState(() => existing.first.qty += 1);
      return;
    }
    setState(() => _cart.add(_CartLine(product: p, isBox: p.boxStrip)));
  }

  int get _subtotal => _cart.fold<int>(0, (int sum, _CartLine l) => sum + l.lineTotal);

  int get _discountPiastres {
    final raw = _discountCtrl.text.trim();
    if (raw.isEmpty) return 0;
    if (_discountIsPercent) {
      final pct = double.tryParse(raw.replaceAll('%', ''));
      if (pct == null || pct <= 0 || pct > 100) return 0;
      return (_subtotal * pct / 100).round();
    }
    final egp = Fmt.parseEGPToPiastres(raw);
    if (egp == null || egp <= 0) return 0;
    return egp > _subtotal ? _subtotal : egp;
  }

  int get _total {
    final t = _subtotal - _discountPiastres;
    return t < 0 ? 0 : t;
  }

  // ------------------------------------------------------------ إيقاف مؤقت

  void _park() {
    if (_cart.isEmpty) return;
    setState(() {
      _parked.insert(0, _ParkedSale(List<_CartLine>.from(_cart)));
      _cart.clear();
      _discountCtrl.clear();
      _credit = false;
      _customer = null;
    });
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(i18n.t('pos', 'title'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(i18n.t('pos', 'subtitle'),
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
          const SizedBox(height: 14),
          // البحث + الباركود
          AppCard(
            padding: const EdgeInsets.all(12),
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
                        ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                        : (_searchCtrl.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () { _searchCtrl.clear(); setState(() => _suggestions = []); })),
                    isDense: true,
                  ),
                ),
                if (_suggestions.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  ..._suggestions.take(6).map((Product p) => _SuggestionTile(product: p, onAdd: () => _addLine(p))),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!, style: TextStyle(fontSize: 12, color: theme.colorScheme.error)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // السلة
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(child: CardTitle(i18n.t('pos', 'cartTitle'),
                        subtitle: _cart.isEmpty ? null : i18n.t('pos', 'cartCount', {'count': Fmt.number(_cart.length)}))),
                    if (_cart.isNotEmpty) ...<Widget>[
                      GhostButton(i18n.t('pos', 'park'), onPressed: _park, icon: Icons.pause_circle_outline),
                      GhostButton(i18n.t('pos', 'clearCart'), onPressed: () => setState(() => _cart.clear()), icon: Icons.delete_outline, color: theme.colorScheme.error),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                if (_cart.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: Text(i18n.t('pos', 'cartEmpty'), style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.5)))),
                  )
                else
                  for (final _CartLine l in _cart) _CartLineTile(line: l, onChanged: () => setState(() {}), onRemove: () => setState(() => _cart.remove(l))),
                if (_parked.isNotEmpty) ...<Widget>[
                  const Divider(height: 22),
                  Text(i18n.t('pos', 'parkedInvoices'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  for (final _ParkedSale p in _parked)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              i18n.t('pos', 'parkedLabelMany', {'count': Fmt.number(p.lines.length), 'total': Fmt.money(p.lines.fold<int>(0, (int s, _CartLine l) => s + l.lineTotal), locale: i18n.locale)}),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          GhostButton(i18n.t('sales', 'back').isEmpty ? '' : i18n.t('common', 'back'), onPressed: () => _resume(p), icon: Icons.play_arrow),
                          IconButton(icon: const Icon(Icons.delete_outline, size: 18), tooltip: i18n.t('pos', 'deleteParked'), onPressed: () => setState(() => _parked.remove(p))),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          // الخصم والدفع
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(i18n.t('pos', 'discountLabel'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      flex: 2,
                      child: AppInput(controller: _discountCtrl, keyboard: TextInputType.number,
                          hint: _discountIsPercent ? i18n.t('pos', 'discountPercentPlaceholder') : i18n.t('pos', 'discountAmountPlaceholder'),
                          onChanged: (_) => setState(() {})),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: AppDropdown<String>(
                        value: _discountIsPercent ? 'percent' : 'amount',
                        items: <DropdownMenuItem<String>>[
                          DropdownMenuItem<String>(value: 'percent', child: Text(i18n.t('pos', 'discountKindPercent'), style: const TextStyle(fontSize: 13))),
                          DropdownMenuItem<String>(value: 'amount', child: Text(i18n.t('pos', 'discountKindAmount'), style: const TextStyle(fontSize: 13))),
                        ],
                        onChanged: (String? v) => setState(() => _discountIsPercent = v != 'amount'),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Text(i18n.t('pos', 'paymentLabel'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: PayChoice(
                        label: i18n.t('pos', 'paymentCash'),
                        icon: Icons.payments_outlined,
                        selected: !_credit,
                        onTap: () => setState(() => _credit = false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: PayChoice(
                        label: i18n.t('pos', 'paymentCredit'),
                        icon: Icons.credit_card,
                        selected: _credit,
                        onTap: () => setState(() => _credit = true),
                      ),
                    ),
                  ],
                ),
                if (_credit) ...<Widget>[
                  const SizedBox(height: 10),
                  AppCard(
                    padding: const EdgeInsets.all(10),
                    onTap: _pickCustomer,
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.person_outline, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _customer == null
                                ? i18n.t('pos', 'customerSearchPlaceholder')
                                : '${_customer!.name} · ${Fmt.money(_customer!.balancePiastres, locale: i18n.locale)}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(i18n.t('pos', 'changeCustomer'), style: TextStyle(fontSize: 12, color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          // الإجمالي + الدفع
          AppCard(
            child: Column(
              children: <Widget>[
                KVRow(i18n.t('reports', 'kpi_gross_sales'), Fmt.money(_subtotal, locale: i18n.locale)),
                if (_discountPiastres > 0) KVRow(i18n.t('sales', 'discount', {'amount': Fmt.money(_discountPiastres, locale: i18n.locale)}), '-${Fmt.money(_discountPiastres, locale: i18n.locale)}'),
                const Divider(height: 18),
                Row(
                  children: <Widget>[
                    Expanded(child: Text(i18n.t('pos', 'total'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                    Text(Fmt.money(_total, locale: i18n.locale), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: theme.colorScheme.primary)),
                  ],
                ),
                const SizedBox(height: 12),
                PrimaryButton(i18n.t('pos', 'title'), icon: Icons.check_circle_outline, loading: _checkingOut, onPressed: _cart.isEmpty ? null : _checkout),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_message!, style: TextStyle(fontSize: 13, color: AppColors.successFg, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

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
      borderRadius: AppRadius.brSm,
      onTap: onAdd,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('${product.name} ${product.strength}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(stockText, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5))),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('${p.name} ${p.strength}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                if (p.boxStrip)
                  Row(
                    children: <Widget>[
                      _UnitChip(label: i18n.t('pos', 'unitBox'), selected: line.isBox, onTap: () { line.isBox = true; onChanged(); }),
                      const SizedBox(width: 6),
                      _UnitChip(label: i18n.t('pos', 'unitStripOne'), selected: !line.isBox, onTap: () { line.isBox = false; onChanged(); }),
                    ],
                  )
                else
                  Text(unitLabel, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.55))),
              ],
            ),
          ),
          Row(
            children: <Widget>[
              IconButton(
                onPressed: line.qty > 1 ? () { line.qty -= 1; onChanged(); } : null,
                icon: const Icon(Icons.remove_circle_outline, size: 20),
              ),
              Text(Fmt.number(line.qty), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              IconButton(onPressed: () { line.qty += 1; onChanged(); }, icon: const Icon(Icons.add_circle_outline, size: 20)),
            ],
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 92,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(Fmt.money(line.lineTotal, locale: i18n.locale), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                Text(unitLabel, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.45))),
                IconButton(icon: Icon(Icons.close, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.5)), tooltip: i18n.t('pos', 'deleteLine'), onPressed: onRemove),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UnitChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _UnitChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? theme.colorScheme.primary : theme.dividerColor),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
            color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.6))),
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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(i18n.t('nav', 'customers'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              SearchField(controller: _search, hint: i18n.t('pos', 'customerSearchPlaceholder'), onChanged: _onChanged, onClear: () { _search.clear(); _load(); }),
              const SizedBox(height: 10),
              if (_loading)
                const LoadingBox()
              else if (_list.isEmpty)
                Text(i18n.t('common', 'no_options'), style: const TextStyle(fontSize: 13), textAlign: TextAlign.center)
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
              Text(i18n.t('pos', 'customerAutoAddedHint'), style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55))),
              const SizedBox(height: 8),
              AppInput(controller: _newName, hint: i18n.t('pos', 'customerNamePlaceholder')),
              const SizedBox(height: 8),
              AppInput(controller: _newPhone, hint: i18n.t('pos', 'customerPhonePlaceholder'), keyboard: TextInputType.phone),
              const SizedBox(height: 10),
              PrimaryButton(i18n.t('pos', 'add'), icon: Icons.person_add_alt_1, loading: _adding, onPressed: _addNew),
            ],
          ),
        ),
      ),
    );
  }
}

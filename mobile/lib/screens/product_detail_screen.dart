import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../models/models.dart';
import '../widgets/ui.dart';
import 'product_form_screen.dart';

/// تفاصيل المنتج + التحكم في مخزون التشغيلة (تسوية +/− بسبب موثّق)
/// كما في صفحتي inventory/[id] و stock_button في الويب.
class ProductDetailScreen extends StatefulWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  ProductDetail? _product;
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
      final p = await ApiClient.instance.product(widget.productId);
      if (!mounted) return;
      setState(() {
        _product = p;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('inventory', 'error_load_product'));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.t('inventory', 'error_load_product');
        _loading = false;
      });
    }
  }

  Future<void> _adjustStock() async {
    final p = _product!;
    final isAdd = await showModalBottomSheet<bool>(
      context: context,
      builder: (BuildContext ctx) => _AdjustSheet(product: p),
    );
    if (isAdd == null) return;
    // النتيجة مطبقة داخل الورقة نفسها — نعيد التحميل عند الإغلاق فقط
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final p = _product;
    return Scaffold(
      appBar: AppBar(
        title: Text(p == null ? i18n.t('inventory', 'title') : i18n.t('inventory', 'edit_title_named', {'name': p.name})),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: i18n.t('inventory', 'edit'),
            onPressed: p == null
                ? null
                : () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => ProductFormScreen(existing: p),
                    ));
                    _load();
                  },
          ),
        ],
      ),
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
                              Expanded(child: Text('${p!.name} ${p.strength}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                              AppBadge(p.isActive ? i18n.t('employees', 'statusActive') : i18n.t('employees', 'statusInactive'),
                                  tone: p.isActive ? BadgeTone.success : BadgeTone.muted),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(p.genericName.isEmpty ? '—' : p.genericName,
                              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                          const Divider(height: 24),
                          KVRow(i18n.t('inventory', 'label_dosage_form'), p.dosageForm.isEmpty ? '—' : p.dosageForm),
                          KVRow(i18n.t('inventory', 'label_barcode'), p.barcode.isEmpty ? '—' : p.barcode),
                          KVRow(i18n.t('inventory', 'packaging_title'), p.boxStrip ? i18n.t('inventory', 'packaging_box_strip') : i18n.t('inventory', 'packaging_whole')),
                          if (p.boxStrip) KVRow(i18n.t('inventory', 'label_units_per_box'), Fmt.number(p.unitsPerBox)),
                          KVRow(i18n.t('inventory', 'label_cost_price'), Fmt.money(p.costPricePiastres, locale: i18n.locale), money: true),
                          KVRow(i18n.t('inventory', 'label_selling_price'), Fmt.money(p.sellingPricePiastres, locale: i18n.locale), money: true),
                          if (p.boxStrip)
                            KVRow(
                              i18n.t('inventory', 'label_strip_price'),
                              Fmt.money(Fmt.stripPrice(
                                sellingPricePiastres: p.sellingPricePiastres,
                                partialSellingPricePiastres: p.partialSellingPricePiastres,
                                unitsPerBox: p.unitsPerBox,
                              ), locale: i18n.locale),
                              money: true,
                            ),
                          KVRow(i18n.t('inventory', 'label_min_stock'), Fmt.number(p.minStockLevel)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    PrimaryButton(i18n.t('inventory', 'stock_button'), icon: Icons.inventory_2_outlined, onPressed: _adjustStock),
                  ],
                ),
    );
  }
}

class _AdjustSheet extends StatefulWidget {
  final ProductDetail product;
  const _AdjustSheet({required this.product});
  @override
  State<_AdjustSheet> createState() => _AdjustSheetState();
}

class _AdjustSheetState extends State<_AdjustSheet> {
  bool _isAdd = true;
  final TextEditingController _qtyCtrl = TextEditingController();
  final TextEditingController _reasonCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final i18n = AppI18n.instance;
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (qty <= 0) {
      setState(() => _error = i18n.t('inventory', 'error_amount_positive'));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ApiClient.instance.adjustBatchStock(
        widget.product.id, // الباكند يقبل batch/stock التسوية على مستوى المنتج الحالي
        _isAdd ? qty : -qty,
        _reasonCtrl.text.trim(),
        DateTime.now().microsecondsSinceEpoch.toString(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('inventory', 'error_adjust_failed'));
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.t('inventory', 'error_adjust_failed');
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final p = widget.product;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(i18n.t('inventory', 'adjust_title'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(i18n.t('inventory', 'adjust_product_batch', {'name': p.name, 'batch': '—'}),
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55))),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: PayChoice(
                      label: i18n.t('inventory', 'adjust_add'),
                      icon: Icons.add,
                      selected: _isAdd,
                      onTap: () => setState(() => _isAdd = true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PayChoice(
                      label: i18n.t('inventory', 'adjust_remove'),
                      icon: Icons.remove,
                      selected: !_isAdd,
                      onTap: () => setState(() => _isAdd = false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppField(
                label: p.boxStrip ? i18n.t('inventory', 'adjust_boxes') : i18n.t('inventory', 'adjust_packs'),
                child: AppInput(controller: _qtyCtrl, keyboard: TextInputType.number),
              ),
              const SizedBox(height: 10),
              AppField(
                label: i18n.t('inventory', 'adjust_reason_label'),
                child: AppInput(controller: _reasonCtrl, hint: i18n.t('inventory', 'adjust_reason_placeholder')),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 14),
              PrimaryButton(
                _isAdd ? i18n.t('inventory', 'adjust_submit_add') : i18n.t('inventory', 'adjust_submit_remove'),
                loading: _submitting,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

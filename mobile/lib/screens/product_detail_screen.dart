import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';
import 'product_form_screen.dart';

/// تفاصيل المنتج + التحكم في مخزون التشغيلة (تسوية +/− بسبب موثّق)
/// كما في نافذة AdjustStockModal بصفحة inventory في الويب.
class ProductDetailScreen extends StatefulWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  ProductDetail? _product;
  List<InventoryItem> _batches = <InventoryItem>[];
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
      // Task 68-b (B): نقطة نهاية /pharmacy/products/:id لا تعيد batch_id إطلاقًا
      // (product_edit_handler.go:55-84 يرد حقول المنتج فقط)، لذا تُحلَّل
      // التشغيلة الحقيقية من GET /pharmacy/inventory — نفس مصدر جدول الويب
      // الذي يحمل batch_id لكل صف (inventory/page.tsx:76 item.batch_id).
      List<InventoryItem> batches = const <InventoryItem>[];
      try {
        final inv = await ApiClient.instance.inventory();
        batches = inv
            .where((InventoryItem it) => it.pharmacyProductId == widget.productId)
            .toList();
      } catch (_) {
        // فشل جلب التشغيلات لا يمنع عرض بيانات المنتج — ضبط المخزون يُعطَّل فقط
        batches = const <InventoryItem>[];
      }
      if (!mounted) return;
      setState(() {
        _product = p;
        _batches = batches;
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
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) => _AdjustSheet(product: p, batches: _batches),
    );
    // النتيجة مطبقة داخل الورقة نفسها — نعيد التحميل عند الإغلاق فقط
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final p = _product;
    // Task 68-b (B/E): زر ضبط المخزون مقيد بـ inventory.adjust مثل الويب
    // (المالك بصلاحيات كاملة يراه دائمًا لأن can() تعيد true بلا قيود مخزنة).
    final canAdjust = context.watch<AppState>().can('inventory.adjust');
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
                    if (canAdjust)
                      PrimaryButton(i18n.t('inventory', 'stock_button'), icon: Icons.inventory_2_outlined, onPressed: _adjustStock),
                  ],
                ),
    );
  }
}

/// ورقة ضبط مخزون التشغيلة — نفس نافذة الويب: اتجاه +/-، علب وشرائط،
/// سبب، الكمية المتوقعة مع منع السالب، وزر إلغاء صريح (page.tsx:124-129).
/// Task 68-b (B): التنفيذ على batch_id الحقيقي — تمرير product.id كان يُسقط
/// الطلب 404 (inventory_batch_not_found) حتميًا.
class _AdjustSheet extends StatefulWidget {
  final ProductDetail product;
  final List<InventoryItem> batches;
  const _AdjustSheet({required this.product, required this.batches});
  @override
  State<_AdjustSheet> createState() => _AdjustSheetState();
}

class _AdjustSheetState extends State<_AdjustSheet> {
  bool _isAdd = true;
  InventoryItem? _batch;
  final TextEditingController _boxesCtrl = TextEditingController();
  final TextEditingController _stripsCtrl = TextEditingController();
  final TextEditingController _reasonCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // أقرب انتهاء أولًا (ترتيب الخادم: product_name ثم expiry NULLS LAST)
    _batch = widget.batches.isEmpty ? null : widget.batches.first;
  }

  @override
  void dispose() {
    _boxesCtrl.dispose();
    _stripsCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  bool get _boxStrip => widget.product.boxStrip;

  int get _unitsPerBox => widget.product.unitsPerBox > 1 ? widget.product.unitsPerBox : 1;

  int get _amount {
    final boxes = int.tryParse(_boxesCtrl.text) ?? 0;
    if (!_boxStrip) return boxes;
    final strips = int.tryParse(_stripsCtrl.text) ?? 0;
    return boxes * _unitsPerBox + strips;
  }

  int get _currentQty => _batch?.quantity ?? 0;

  int get _projected => _currentQty + (_isAdd ? _amount : -_amount);

  Future<void> _submit() async {
    final i18n = AppI18n.instance;
    final batch = _batch;
    if (batch == null) return;
    final qty = _amount;
    if (qty <= 0) {
      setState(() => _error = i18n.t('inventory', 'error_amount_positive'));
      return;
    }
    if (_projected < 0) return; // الزر معطّل — حارس إضافي فقط
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ApiClient.instance.adjustBatchStock(
        batch.batchId, // Task 68-b (B): batch_id الحقيقي وليس product.id
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

  /// صياغة الكمية كما في formatQuantity بالويب: «2 علبة و3 شريط» إلخ
  String _qtyWords(InventoryItem it) {
    final i18n = AppI18n.instance;
    if (!_boxStrip) return '${Fmt.number(it.quantity)} ${i18n.t('inventory', 'units_pack')}';
    final boxes = it.quantity ~/ _unitsPerBox;
    final strips = it.quantity % _unitsPerBox;
    if (boxes == 0 && strips == 0) return i18n.t('inventory', 'qty_out_of_stock');
    if (boxes == 0) return i18n.t('inventory', 'qty_strips_only', {'count': Fmt.number(strips)});
    if (strips == 0) return i18n.t('inventory', 'qty_boxes_only', {'count': Fmt.number(boxes)});
    return i18n.t('inventory', 'qty_box_and_strip', {'boxes': Fmt.number(boxes), 'strips': Fmt.number(strips)});
  }

  String _batchLabel(InventoryItem it) {
    final number = it.batchNumber.isEmpty ? it.batchId : it.batchNumber;
    return it.branchName.isEmpty ? number : '$number — ${it.branchName}';
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final p = widget.product;
    final batch = _batch;
    final hasBatch = batch != null;
    final amount = _amount;
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
              // Task 68-b (J): رقم التشغيلة الحقيقي بدل «—» الثابت
              Text(i18n.t('inventory', 'adjust_product_batch', {
                    'name': p.name,
                    'batch': hasBatch
                        ? (batch.batchNumber.isEmpty ? batch.batchId : batch.batchNumber)
                        : '—',
                  }),
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
              const SizedBox(height: 4),
              Text(
                i18n.t('inventory', 'adjust_current_quantity', {
                  'quantity': hasBatch ? _qtyWords(batch) : i18n.t('inventory', 'qty_out_of_stock'),
                }),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface.withOpacity(0.75)),
              ),
              const SizedBox(height: 12),
              if (widget.batches.length > 1) ...<Widget>[
                AppField(
                  label: i18n.t('inventory', 'th_batch'),
                  child: AppDropdown<String>(
                    value: batch!.batchId,
                    items: <DropdownMenuItem<String>>[
                      for (final InventoryItem it in widget.batches)
                        DropdownMenuItem<String>(value: it.batchId, child: Text(_batchLabel(it), style: const TextStyle(fontSize: 13))),
                    ],
                    onChanged: (String? v) => setState(() {
                      for (final InventoryItem it in widget.batches) {
                        if (it.batchId == v) {
                          _batch = it;
                          break;
                        }
                      }
                    }),
                  ),
                ),
                const SizedBox(height: 12),
              ],
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
                      destructive: true,
                      onTap: () => setState(() => _isAdd = false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Task 68-b (J): حقل شرائط إضافي لمنتجات BOX_STRIP كما في الويب
              if (_boxStrip)
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppField(
                        label: i18n.t('inventory', 'adjust_boxes'),
                        child: AppInput(
                          controller: _boxesCtrl,
                          keyboard: const TextInputType.numberWithOptions(decimal: false),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppField(
                        label: i18n.t('inventory', 'adjust_strips'),
                        child: AppInput(
                          controller: _stripsCtrl,
                          keyboard: const TextInputType.numberWithOptions(decimal: false),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                  ],
                )
              else
                AppField(
                  label: i18n.t('inventory', 'adjust_packs'),
                  child: AppInput(
                    controller: _boxesCtrl,
                    keyboard: const TextInputType.numberWithOptions(decimal: false),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              const SizedBox(height: 10),
              AppField(
                label: i18n.t('inventory', 'adjust_reason_label'),
                child: AppInput(controller: _reasonCtrl, hint: i18n.t('inventory', 'adjust_reason_placeholder')),
              ),
              if (hasBatch && amount > 0) ...<Widget>[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _projected < 0 ? theme.colorScheme.error.withOpacity(0.10) : theme.colorScheme.onSurface.withOpacity(0.04),
                    borderRadius: AppRadius.br,
                  ),
                  child: Text(
                    '${i18n.t('inventory', 'adjust_after_quantity', {'quantity': Fmt.number(_projected)})}'
                    '${_projected < 0 ? ' ${i18n.t('inventory', 'adjust_negative_warning')}' : ''}',
                    style: TextStyle(
                        fontSize: 12,
                        color: _projected < 0 ? theme.colorScheme.error : theme.colorScheme.onSurface.withOpacity(0.6)),
                  ),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(fontSize: 12, color: theme.colorScheme.error)),
                ),
              const SizedBox(height: 14),
              // Task 68-b (E): زر إلغاء صريح + تعطيل التنفيذ عندما تصبح الكمية
              // المتوقعة سالبة (page.tsx:125-128 disabled={projected < 0})
              Row(
                children: <Widget>[
                  Expanded(
                    child: WButton(
                      _isAdd ? i18n.t('inventory', 'adjust_submit_add') : i18n.t('inventory', 'adjust_submit_remove'),
                      loading: _submitting,
                      onPressed: hasBatch && !_submitting && _projected >= 0 ? _submit : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  WButton(
                    i18n.t('inventory', 'cancel'),
                    variant: WButtonVariant.outline,
                    onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

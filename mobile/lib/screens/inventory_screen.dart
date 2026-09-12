import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';
import 'pos_screen.dart';
import 'product_detail_screen.dart';
import 'product_form_screen.dart';

/// Task 62 — المخزون بنسخة الويب حرفيًا: رأس صفحة مع زرّي «فتح نقطة البيع»
/// (outline) و«إضافة دواء»، بطاقة واحدة برأس فيها الأيقونة + البحث، ثم
/// جدول WebTable بتمرير أفقي: الدواء/التشغيلة/الفرع/الكمية/الصلاحية/الحالة/
/// إجراءات، وشارة الحالة، ونافذة ضبط المخزون (Modal rounded-lg p-6).
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<InventoryItem> _items = <InventoryItem>[];
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
      final items = await ApiClient.instance.inventory();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('inventory', 'error_load_failed'));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = i18n.t('inventory', 'error_load_failed');
        _loading = false;
      });
    }
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => setState(() {}));
  }

  List<InventoryItem> get _filtered {
    // البحث يشمل التركيز أيضاً — مثل فلتر الويب على كل الأعمدة
    final q = _searchCtrl.text.trim().toLowerCase();
    return _items.where((InventoryItem it) {
      return '$it.productName ${it.genericName} ${it.brandName} ${it.strength} ${it.barcode} ${it.batchNumber}'
          .toLowerCase()
          .contains(q);
    }).toList();
  }

  /// Task 68-b (D): نغمات الشارات مثل الويب حرفيًا (inventory/page.tsx:14-20):
  /// expiring_soon → secondary و quarantined → outline (كلاهما muted هنا)،
  /// والحالة المجهولة → outline (muted) وليس success.
  BadgeTone _statusTone(String status) {
    switch (status.toLowerCase()) {
      case 'out_of_stock':
        return BadgeTone.destructive;
      case 'low_stock':
        return BadgeTone.warning;
      case 'expiring_soon':
      case 'quarantined':
        return BadgeTone.muted;
      case 'normal':
        return BadgeTone.success;
      default:
        return BadgeTone.muted;
    }
  }

  String _statusLabel(String status) {
    final i18n = AppI18n.instance;
    switch (status.toLowerCase()) {
      case 'out_of_stock':
        return i18n.t('inventory', 'status_out_of_stock');
      case 'low_stock':
        return i18n.t('inventory', 'status_low_stock');
      case 'expiring_soon':
        return i18n.t('inventory', 'status_expiring_soon');
      case 'quarantined':
        return i18n.t('inventory', 'status_quarantined');
      default:
        return i18n.t('inventory', 'status_normal');
    }
  }

  String _qtyLabel(InventoryItem it) {
    final i18n = AppI18n.instance;
    if (it.quantity <= 0) return i18n.t('inventory', 'qty_out_of_stock');
    if (it.boxStrip) {
      final boxes = it.quantity ~/ it.unitsPerBox;
      final strips = it.quantity % it.unitsPerBox;
      if (boxes == 0 && strips == 0) return i18n.t('inventory', 'qty_out_of_stock');
      if (boxes == 0) return i18n.t('inventory', 'qty_strips_only', {'count': Fmt.number(strips)});
      if (strips == 0) return i18n.t('inventory', 'qty_boxes_only', {'count': Fmt.number(boxes)});
      return i18n.t('inventory', 'qty_box_and_strip', {'boxes': Fmt.number(boxes), 'strips': Fmt.number(strips)});
    }
    return '${Fmt.number(it.quantity)} ${i18n.t('inventory', 'units_pack')}';
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final state = context.watch<AppState>();
    final canManage = state.can('inventory.manage_products') || state.permissions?.fullAccess == true;
    // Task 68-b (A): مفتاح الصلاحية الصحيح «inventory.adjust» كما في الويب والباك اند
    // (handler.go:129 perm("inventory.adjust")) — كان adjust_stock فلا يظهر الزر أبدًا.
    final canAdjust = state.can('inventory.adjust');
    final canPOS = state.can('pos.access');
    final filtered = _filtered;

    // Task 75 — مثل الويب (inventory/page.tsx:187-198): هيكل الصفحة كاملًا ظاهر
    // (رأس + بطاقة بالعنوان والبحث) والتحميل/الخطأ نص داخل محتوى البطاقة —
    // لا سبينر يستبدل الصفحة كلها.
    return RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    PageHeader(
                      i18n.t('inventory', 'title'),
                      subtitle: i18n.t('inventory', 'subtitle'),
                      actions: <Widget>[
                        if (canPOS)
                          WButton(
                            i18n.t('inventory', 'open_pos'),
                            icon: Icons.shopping_cart_outlined,
                            variant: WButtonVariant.outline,
                            onPressed: () => Navigator.of(context)
                                .push(MaterialPageRoute<void>(builder: (_) => const POSScreen())),
                          ),
                        if (canManage)
                          WButton(
                            i18n.t('inventory', 'add_product'),
                            icon: Icons.add,
                            onPressed: () async {
                              await Navigator.of(context)
                                  .push(MaterialPageRoute<void>(builder: (_) => const ProductFormScreen()));
                              _load();
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    AppCard(
                      child: Column(
                        children: <Widget>[
                          // رأس البطاقة: الأيقونة + العنوان والبحث
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                            child: Column(
                              children: <Widget>[
                                CardTitle(i18n.t('inventory', 'all_items'), icon: Icons.inventory_2_outlined),
                                const SizedBox(height: 16),
                                SearchField(
                                  controller: _searchCtrl,
                                  hint: i18n.t('inventory', 'search_placeholder'),
                                  onChanged: _onSearch,
                                  onClear: () {
                                    _searchCtrl.clear();
                                    setState(() {});
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.all(24),
                            // التحميل/الخطأ داخل البطاقة كما بالويب — لا يخفيان هيكل الصفحة
                            child: _loading
                                ? Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 40),
                                    child: Text(i18n.t('inventory', 'loading'),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
                                  )
                                : _error != null
                                    ? ErrorRetry(_error!, onRetry: _load)
                                    : filtered.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 40),
                                    child: Text(i18n.t('inventory', 'no_matches'),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
                                  )
                                : WebTable(
                                    minWidth: 860,
                                    headers: <String>[
                                      i18n.t('inventory', 'th_product'),
                                      i18n.t('inventory', 'th_batch'),
                                      i18n.t('inventory', 'th_branch'),
                                      i18n.t('inventory', 'th_quantity'),
                                      i18n.t('inventory', 'th_expiry'),
                                      i18n.t('inventory', 'th_status'),
                                      if (canManage || canAdjust) i18n.t('inventory', 'th_actions'),
                                    ],
                                    rows: <List<Widget>>[
                                      for (final InventoryItem it in filtered)
                                        <Widget>[
                                          // الدواء: الاسم + التركيز + الاسم العلمي/الشركة
                                          GestureDetector(
                                            onTap: () async {
                                              await Navigator.of(context).push(MaterialPageRoute<void>(
                                                builder: (_) => ProductDetailScreen(productId: it.pharmacyProductId),
                                              ));
                                              _load();
                                            },
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: <Widget>[
                                                Text('${it.productName}${_strengthSuffix(it)}',
                                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                                Text(
                                                  it.genericName.isNotEmpty ? it.genericName : it.brandName,
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55)),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(it.batchNumber.isEmpty ? '—' : it.batchNumber),
                                          Text(it.branchName.isEmpty ? i18n.t('inventory', 'all_branches') : it.branchName),
                                          // الكمية
                                          it.quantity <= 0
                                              ? Text(_qtyLabel(it),
                                                  style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600))
                                              : Text(_qtyLabel(it), style: const TextStyle(fontWeight: FontWeight.w600)),
                                          Text(it.expiryDate == null || it.expiryDate!.isEmpty
                                              ? '—'
                                              : Fmt.date(it.expiryDate, locale: i18n.locale)),
                                          AppBadge(_statusLabel(it.status), tone: _statusTone(it.status)),
                                          if (canManage || canAdjust)
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              children: <Widget>[
                                                if (canManage)
                                                  WButton(
                                                    i18n.t('inventory', 'edit'),
                                                    icon: Icons.edit_outlined,
                                                    variant: WButtonVariant.outline,
                                                    size: WButtonSize.sm,
                                                    onPressed: () async {
                                                      // نموذج التعديل يحتاج القيم المخزنة الفعلية — نفس سلوك الويب
                                                      try {
                                                        final detail = await ApiClient.instance.product(it.pharmacyProductId);
                                                        if (!context.mounted) return;
                                                        await Navigator.of(context).push(MaterialPageRoute<void>(
                                                          builder: (_) => ProductFormScreen(existing: detail),
                                                        ));
                                                        _load();
                                                      } catch (_) {
                                                        _load();
                                                        if (context.mounted) {
                                                          appSnackbar(context, i18n.t('inventory', 'edit_load_failed'), error: true);
                                                        }
                                                      }
                                                    },
                                                  ),
                                                if (canAdjust) ...<Widget>[
                                                  const SizedBox(width: 6),
                                                  WButton(
                                                    i18n.t('inventory', 'stock_button'),
                                                    icon: Icons.add_box_outlined,
                                                    variant: it.quantity <= 0 ? WButtonVariant.primary : WButtonVariant.ghost,
                                                    size: WButtonSize.sm,
                                                    onPressed: () => _openAdjustModal(it),
                                                  ),
                                                ],
                                              ],
                                            ),
                                        ],
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
  }

  String _strengthSuffix(InventoryItem it) {
    // نفس قاعدة الويب: التركيز يُلحق فقط إن لم يكن الاسم يحمل جرعة
    final name = it.productName.toLowerCase();
    if (name.contains(RegExp(r'\d+\s*(mg|mcg|g|ml|iu)'))) return '';
    return it.strength.isEmpty ? '' : ' ${it.strength}';
  }

  void _openAdjustModal(InventoryItem it) {
    showAppModal(
      context,
      title: AppI18n.instance.t('inventory', 'adjust_title'),
      child: _AdjustStockForm(item: it, onSaved: _load),
    );
  }
}

/// نموذج ضبط المخزون — مثل الويب: زرا إضافة/خصم، صناديق وشرائط، سبب،
/// وملاحظة الكمية المتوقعة (تحذير إن كانت سالبة).
class _AdjustStockForm extends StatefulWidget {
  final InventoryItem item;
  final Future<void> Function() onSaved;
  const _AdjustStockForm({required this.item, required this.onSaved});

  @override
  State<_AdjustStockForm> createState() => _AdjustStockFormState();
}

class _AdjustStockFormState extends State<_AdjustStockForm> {
  bool _add = true;
  final TextEditingController _boxes = TextEditingController();
  final TextEditingController _strips = TextEditingController();
  final TextEditingController _reason = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _boxes.dispose();
    _strips.dispose();
    _reason.dispose();
    super.dispose();
  }

  int get _amount {
    final boxes = int.tryParse(_boxes.text) ?? 0;
    if (!widget.item.boxStrip) return boxes;
    final strips = int.tryParse(_strips.text) ?? 0;
    return boxes * widget.item.unitsPerBox + strips;
  }

  int get _projected => widget.item.quantity + (_add ? _amount : -_amount);

  Future<void> _submit() async {
    final i18n = AppI18n.instance;
    if (_amount <= 0) {
      setState(() => _error = i18n.t('inventory', 'error_amount_positive'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.adjustBatchStock(
        widget.item.batchId,
        _add ? _amount : -_amount,
        _reason.text.trim(),
        DateTime.now().microsecondsSinceEpoch.toString(),
      );
      await widget.onSaved();
      if (!mounted) return;
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('inventory', 'error_adjust_failed'));
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = i18n.t('inventory', 'error_adjust_failed');
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final it = widget.item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '${i18n.t('inventory', 'adjust_product_batch', {'name': it.productName, 'batch': it.batchNumber})}\n'
          '${i18n.t('inventory', 'adjust_current_quantity', {'quantity': it.quantity <= 0 ? i18n.t('inventory', 'qty_out_of_stock') : _qtyPlain(it)})}',
          style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.55), height: 1.6),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: PayChoice(
                label: i18n.t('inventory', 'adjust_add'),
                icon: Icons.add,
                selected: _add,
                onTap: () => setState(() => _add = true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PayChoice(
                label: i18n.t('inventory', 'adjust_remove'),
                icon: Icons.remove,
                selected: !_add,
                destructive: true,
                onTap: () => setState(() => _add = false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (it.boxStrip)
          Row(
            children: <Widget>[
              Expanded(
                child: AppField(label: i18n.t('inventory', 'adjust_boxes'),
                    child: AppInput(controller: _boxes, keyboard: const TextInputType.numberWithOptions(decimal: false), onChanged: (_) => setState((){}))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppField(label: i18n.t('inventory', 'adjust_strips'),
                    child: AppInput(controller: _strips, keyboard: const TextInputType.numberWithOptions(decimal: false), onChanged: (_) => setState((){}))),
              ),
            ],
          )
        else
          AppField(label: i18n.t('inventory', 'adjust_packs'),
              child: AppInput(controller: _boxes, keyboard: const TextInputType.numberWithOptions(decimal: false), onChanged: (_) => setState((){}))),
        const SizedBox(height: 16),
        AppField(label: i18n.t('inventory', 'adjust_reason_label'),
            child: AppInput(controller: _reason, hint: i18n.t('inventory', 'adjust_reason_placeholder'))),
        if (_amount > 0) ...<Widget>[
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
                  fontSize: 12, color: _projected < 0 ? theme.colorScheme.error : theme.colorScheme.onSurface.withOpacity(0.6)),
            ),
          ),
        ],
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          ErrorBanner(_error!),
        ],
        const SizedBox(height: 16),
        // Task 68-b (E): مثل الويب (page.tsx:124-129) — زر التنفيذ بعنوان الإضافة/
        // الخصم الصريح معطّل عندما تصبح الكمية المتوقعة سالبة، وبجانبه زر إلغاء.
        Row(
          children: <Widget>[
            Expanded(
              child: WButton(
                _add ? i18n.t('inventory', 'adjust_submit_add') : i18n.t('inventory', 'adjust_submit_remove'),
                onPressed: (_saving || _projected < 0) ? null : _submit,
                loading: _saving,
              ),
            ),
            const SizedBox(width: 8),
            WButton(
              i18n.t('inventory', 'cancel'),
              variant: WButtonVariant.outline,
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }

  String _qtyPlain(InventoryItem it) {
    if (it.boxStrip) {
      final boxes = it.quantity ~/ it.unitsPerBox;
      final strips = it.quantity % it.unitsPerBox;
      return '${Fmt.number(boxes)}+${Fmt.number(strips)}';
    }
    return Fmt.number(it.quantity);
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../models/models.dart';
import '../widgets/ui.dart';
import 'product_detail_screen.dart';
import 'product_form_screen.dart';

/// المخزون والأدوية — صفحة التشغيلات الفعلية (كميات، صلاحية، حالة، فرع)
/// مع بحث وبطاقات حالة بنفس ألوان الويب.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<InventoryItem> _items = <InventoryItem>[];
  String _filter = 'all'; // all | low | out | expiring
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
        _error = AppI18n.instance.t('inventory', 'error_load_failed');
        _loading = false;
      });
    }
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => setState(() {}));
  }

  List<InventoryItem> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _items.where((InventoryItem it) {
      final matchesSearch = q.isEmpty ||
          it.productName.toLowerCase().contains(q) ||
          it.barcode.contains(q) ||
          it.batchNumber.toLowerCase().contains(q);
      if (!matchesSearch) return false;
      switch (_filter) {
        case 'low':
          return it.status.toLowerCase().contains('low');
        case 'out':
          return it.status.toLowerCase().contains('out') || it.quantity <= 0;
        case 'expiring':
          return it.daysUntilExpiry != null && it.daysUntilExpiry! <= 90;
        default:
          return true;
      }
    }).toList();
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
      return i18n.t('inventory', 'qty_boxes_only', {'count': Fmt.number(it.quantity)});
    }
    return i18n.t('inventory', 'qty_strips_only', {'count': Fmt.number(it.quantity)});
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_product',
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProductFormScreen()));
          _load();
        },
        icon: const Icon(Icons.add),
        label: Text(i18n.t('inventory', 'add_product'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const LoadingBox()
          : _error != null
              ? ErrorRetry(_error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                    children: <Widget>[
                      Text(i18n.t('inventory', 'title'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(i18n.t('inventory', 'subtitle'),
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                      const SizedBox(height: 14),
                      SearchField(
                        controller: _searchCtrl,
                        hint: i18n.t('inventory', 'search_placeholder'),
                        onChanged: _onSearch,
                        onClear: () { _searchCtrl.clear(); setState(() {}); },
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          _FilterChip(label: i18n.t('inventory', 'all_items'), value: 'all', current: _filter, onSelect: (String v) => setState(() => _filter = v)),
                          _FilterChip(label: i18n.t('inventory', 'status_low_stock'), value: 'low', current: _filter, onSelect: (String v) => setState(() => _filter = v)),
                          _FilterChip(label: i18n.t('inventory', 'status_out_of_stock'), value: 'out', current: _filter, onSelect: (String v) => setState(() => _filter = v)),
                          _FilterChip(label: i18n.t('inventory', 'status_expiring_soon'), value: 'expiring', current: _filter, onSelect: (String v) => setState(() => _filter = v)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (filtered.isEmpty)
                        EmptyState(i18n.t('inventory', 'no_matches'), icon: Icons.medication_outlined)
                      else
                        for (final InventoryItem it in filtered)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: AppCard(
                              onTap: () async {
                                await Navigator.of(context).push(MaterialPageRoute<void>(
                                  builder: (_) => ProductDetailScreen(productId: it.pharmacyProductId),
                                ));
                                _load();
                              },
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text('${it.productName} ${it.strength}',
                                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                                      ),
                                      AppBadge(_statusLabel(it.status), tone: AppBadge.stockStatus(it.status)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${i18n.t('inventory', 'th_batch')}: ${it.batchNumber.isEmpty ? '—' : it.batchNumber}'
                                    ' · ${i18n.t('inventory', 'th_branch')}: ${it.branchName.isEmpty ? '—' : it.branchName}',
                                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: <Widget>[
                                      Text(_qtyLabel(it), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                      const Spacer(),
                                      Text(Fmt.money(Fmt.stripPrice(
                                        sellingPricePiastres: it.sellingPricePiastres,
                                        partialSellingPricePiastres: it.partialSellingPricePiastres,
                                        unitsPerBox: it.unitsPerBox,
                                      ), locale: i18n.locale), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                  if (it.expiryDate != null && it.expiryDate!.isNotEmpty) ...<Widget>[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: <Widget>[
                                        Text('${i18n.t('inventory', 'th_expiry')}: ${Fmt.date(it.expiryDate, locale: i18n.locale)}',
                                            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                                        const Spacer(),
                                        ExpiryBadge(it.daysUntilExpiry),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String current;
  final ValueChanged<String> onSelect;
  const _FilterChip({required this.label, required this.value, required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = value == current;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => onSelect(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? theme.colorScheme.primary : theme.dividerColor),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
            color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface.withOpacity(0.7))),
      ),
    );
  }
}

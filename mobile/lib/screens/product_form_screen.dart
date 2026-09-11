import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/ui.dart';

/// إضافة/تعديل منتج — نفس حقول صفحتي inventory/new و edit في الويب:
/// بيانات العلاج، التعبئة (عبوة كاملة / شرائط)، الأسعار، والمخزون الافتتاحي
/// للإضافة فقط.
class ProductFormScreen extends StatefulWidget {
  final ProductDetail? existing;
  const ProductFormScreen({super.key, this.existing});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _generic;
  late final TextEditingController _strength;
  late final TextEditingController _barcode;
  late final TextEditingController _cost;
  late final TextEditingController _selling;
  late final TextEditingController _stripPrice;
  late final TextEditingController _unitsPerBox;
  late final TextEditingController _minStock;
  late final TextEditingController _initialBoxes;
  late final TextEditingController _initialStrips;
  late final TextEditingController _batch;
  late final TextEditingController _expiry;
  String _dosage = '';
  bool _boxStrip = true;
  bool _isActive = true;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _generic = TextEditingController(text: p?.genericName ?? '');
    _strength = TextEditingController(text: p?.strength ?? '');
    _barcode = TextEditingController(text: p?.barcode ?? '');
    _cost = TextEditingController(text: p == null ? '' : Fmt.piastresToInput(p.costPricePiastres));
    _selling = TextEditingController(text: p == null ? '' : Fmt.piastresToInput(p.sellingPricePiastres));
    _stripPrice = TextEditingController(
        text: p == null || !p.boxStrip || p.partialSellingPricePiastres <= 0
            ? ''
            : Fmt.piastresToInput(p.partialSellingPricePiastres));
    _unitsPerBox = TextEditingController(text: p == null || p.unitsPerBox <= 1 ? '' : '${p.unitsPerBox}');
    _minStock = TextEditingController(text: p == null ? '' : '${p.minStockLevel}');
    _initialBoxes = TextEditingController();
    _initialStrips = TextEditingController();
    _batch = TextEditingController();
    _expiry = TextEditingController();
    _dosage = p?.dosageForm ?? '';
    _boxStrip = p?.boxStrip ?? true;
    _isActive = p?.isActive ?? true;
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _name, _generic, _strength, _barcode, _cost, _selling, _stripPrice,
      _unitsPerBox, _minStock, _initialBoxes, _initialStrips, _batch, _expiry,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final i18n = AppI18n.instance;
    if (!_formKey.currentState!.validate() || _saving) return;
    final name = _name.text.trim();
    final cost = Fmt.parseEGPToPiastres(_cost.text);
    final selling = Fmt.parseEGPToPiastres(_selling.text);
    if (name.isEmpty || cost == null || selling == null) {
      setState(() => _error = i18n.t('inventory', 'error_prices_required'));
      return;
    }
    int? partial;
    final unitsPerBox = _boxStrip ? (int.tryParse(_unitsPerBox.text.trim()) ?? 0) : 0;
    if (_boxStrip) {
      if (unitsPerBox < 2) {
        setState(() => _error = i18n.t('inventory', 'fieldUnitsPerBoxHint'));
        return;
      }
      final stripPrice = Fmt.parseEGPToPiastres(_stripPrice.text);
      if (stripPrice == null || stripPrice <= 0) {
        setState(() => _error = i18n.t('inventory', 'error_strip_price_invalid'));
        return;
      }
      partial = stripPrice;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_isEdit) {
        await ApiClient.instance.updateProduct(widget.existing!.id, <String, dynamic>{
          'name': name,
          'generic_name': _generic.text.trim(),
          'dosage_form': _dosage,
          'strength': _strength.text.trim(),
          'barcode': _barcode.text.trim(),
          'packaging_type': _boxStrip ? 'BOX_STRIP' : 'WHOLE_ONLY',
          'units_per_box': _boxStrip ? unitsPerBox : 1,
          'cost_price_piastres': cost,
          'selling_price_piastres': selling,
          'partial_selling_price_piastres': partial,
          'min_stock_level': int.tryParse(_minStock.text.trim()) ?? 0,
          'is_active': _isActive,
        });
      } else {
        await ApiClient.instance.createProduct(<String, dynamic>{
          'name': name,
          'generic_name': _generic.text.trim(),
          'dosage_form': _dosage,
          'strength': _strength.text.trim(),
          'barcode': _barcode.text.trim(),
          'packaging_type': _boxStrip ? 'BOX_STRIP' : 'WHOLE_ONLY',
          'units_per_box': _boxStrip ? unitsPerBox : 1,
          'cost_price_piastres': cost,
          'selling_price_piastres': selling,
          'partial_selling_price_piastres': partial,
          'min_stock_level': int.tryParse(_minStock.text.trim()) ?? 0,
          'initial_boxes': int.tryParse(_initialBoxes.text.trim()) ?? 0,
          'initial_strips': int.tryParse(_initialStrips.text.trim()) ?? 0,
          'batch_number': _batch.text.trim(),
          'expiry_date': _expiry.text.trim(),
        });
      }
      if (!mounted) return;
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, _isEdit ? i18n.t('inventory', 'error_save_edits') : i18n.t('inventory', 'error_save_product'));
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = _isEdit ? i18n.t('inventory', 'error_save_edits') : i18n.t('inventory', 'error_save_product');
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? i18n.t('inventory', 'edit_title') : i18n.t('inventory', 'new_title'))),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  CardTitle(i18n.t('inventory', 'treatment_info_title'), subtitle: i18n.t('inventory', 'treatment_info_desc')),
                  const SizedBox(height: 12),
                  AppField(label: i18n.t('inventory', 'label_name'), child: AppInput(controller: _name, hint: i18n.t('inventory', 'placeholder_name'), validator: (String? v) => (v == null || v.trim().isEmpty) ? ' ' : null)),
                  const SizedBox(height: 10),
                  AppField(label: i18n.t('inventory', 'label_generic_name'), child: AppInput(controller: _generic, hint: i18n.t('inventory', 'placeholder_optional'))),
                  const SizedBox(height: 10),
                  AppField(
                    label: i18n.t('inventory', 'label_dosage_form'),
                    child: AppDropdown<String>(
                      value: _dosage.isEmpty ? null : _dosage,
                      hint: i18n.t('common', 'select_placeholder'),
                      items: <DropdownMenuItem<String>>[
                        for (final (String k, String label) in <(String, String)>[
                          ('أقراص', 'dosage_tablet'), ('كبسولات', 'dosage_capsule'), ('شراب', 'dosage_syrup'),
                          ('حقن', 'dosage_injection'), ('كريم', 'dosage_cream'), ('قطرة', 'dosage_drop'),
                          ('بخاخ', 'dosage_inhaler'),
                        ])
                          DropdownMenuItem<String>(value: k, child: Text(i18n.t('inventory', label), style: const TextStyle(fontSize: 13))),
                      ],
                      onChanged: (String? v) => setState(() => _dosage = v ?? ''),
                    ),
                  ),
                  const SizedBox(height: 10),
                  AppField(label: i18n.t('inventory', 'label_strength'), child: AppInput(controller: _strength, hint: i18n.t('inventory', 'placeholder_strength_other'))),
                  const SizedBox(height: 10),
                  AppField(label: i18n.t('inventory', 'label_barcode'), child: AppInput(controller: _barcode, hint: i18n.t('inventory', 'placeholder_barcode'), keyboard: TextInputType.text)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  CardTitle(i18n.t('inventory', 'packaging_title'), subtitle: i18n.t('inventory', 'packaging_desc')),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _PackChoice(
                          title: i18n.t('inventory', 'packaging_whole'),
                          desc: i18n.t('inventory', 'packaging_whole_desc'),
                          selected: !_boxStrip,
                          onTap: () => setState(() => _boxStrip = false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _PackChoice(
                          title: i18n.t('inventory', 'packaging_box_strip'),
                          desc: i18n.t('inventory', 'packaging_box_strip_desc'),
                          selected: _boxStrip,
                          onTap: () => setState(() => _boxStrip = true),
                        ),
                      ),
                    ],
                  ),
                  if (_boxStrip) ...<Widget>[
                    const SizedBox(height: 10),
                    AppField(label: i18n.t('inventory', 'label_units_per_box'), child: AppInput(controller: _unitsPerBox, keyboard: TextInputType.number)),
                    const SizedBox(height: 10),
                    AppField(label: i18n.t('inventory', 'label_strip_price'), child: AppInput(controller: _stripPrice, hint: i18n.t('inventory', 'placeholder_strip_price'), keyboard: const TextInputType.numberWithOptions(decimal: true))),
                  ],
                  if (_isEdit) ...<Widget>[
                    const SizedBox(height: 10),
                    AppSwitchTile(title: i18n.t('inventory', 'active_label'), value: _isActive, onChanged: (bool v) => setState(() => _isActive = v)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  CardTitle(
                    _isEdit ? i18n.t('inventory', 'prices_title') : i18n.t('inventory', 'prices_initial_title'),
                    subtitle: _isEdit ? i18n.t('inventory', 'prices_desc') : i18n.t('inventory', 'prices_initial_desc'),
                  ),
                  const SizedBox(height: 12),
                  AppField(label: i18n.t('inventory', 'label_cost_price'), child: AppInput(controller: _cost, hint: i18n.t('inventory', 'placeholder_cost_price'), keyboard: const TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(height: 10),
                  AppField(label: i18n.t('inventory', 'label_selling_price'), child: AppInput(controller: _selling, hint: i18n.t('inventory', 'placeholder_selling_price'), keyboard: const TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(height: 10),
                  AppField(label: i18n.t('inventory', 'label_min_stock'), child: AppInput(controller: _minStock, keyboard: TextInputType.number)),
                  if (!_isEdit) ...<Widget>[
                    const SizedBox(height: 10),
                    AppField(label: i18n.t('inventory', 'label_initial_boxes'), child: AppInput(controller: _initialBoxes, keyboard: TextInputType.number)),
                    const SizedBox(height: 10),
                    AppField(label: i18n.t('inventory', 'label_initial_strips'), child: AppInput(controller: _initialStrips, keyboard: TextInputType.number)),
                    const SizedBox(height: 10),
                    AppField(label: i18n.t('inventory', 'label_batch_number'), child: AppInput(controller: _batch, hint: i18n.t('inventory', 'placeholder_batch_number'))),
                    const SizedBox(height: 10),
                    AppField(label: i18n.t('inventory', 'label_expiry_date'), child: AppInput(controller: _expiry, hint: 'YYYY-MM-DD')),
                  ],
                ],
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 16),
            PrimaryButton(_isEdit ? i18n.t('inventory', 'save_edits') : i18n.t('inventory', 'save_product'), loading: _saving, onPressed: _save),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _PackChoice extends StatelessWidget {
  final String title;
  final String desc;
  final bool selected;
  final VoidCallback onTap;
  const _PackChoice({required this.title, required this.desc, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: AppRadius.br,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary.withOpacity(0.08) : Colors.transparent,
          borderRadius: AppRadius.br,
          border: Border.all(color: selected ? theme.colorScheme.primary : theme.dividerColor, width: selected ? 1.4 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                color: selected ? theme.colorScheme.primary : null)),
            const SizedBox(height: 4),
            Text(desc, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.55)), maxLines: 3),
          ],
        ),
      ),
    );
  }
}

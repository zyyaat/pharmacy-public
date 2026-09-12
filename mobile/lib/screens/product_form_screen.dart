import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/ui.dart';

/// إضافة/تعديل منتج — نفس حقول ProductFormFields في الويب:
/// بيانات العلاج (شكل دوائي بقيم enum + تركيز رقم ووحدة)، التعبئة
/// (عبوة كاملة / شرائط مع اقتراح سعر الشريط)، الأسعار، والمخزون الافتتاحي
/// للإضافة فقط مع منتقي تاريخ للصلاحية.
class ProductFormScreen extends StatefulWidget {
  final ProductDetail? existing;
  const ProductFormScreen({super.key, this.existing});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  /// Task 68-b (C): قيم enum الإنجليزية المخزنة في قاعدة البيانات حرفيًا مثل
  /// product-form-fields.tsx:12-21 (dosageForms) — التسمية العربية للعرض فقط
  /// عبر مفتاح inventory؛ كان الموبايل يخزّن التسمية العربية فيرفضها الباكند
  /// (invalid_dosage_form 22P02) ويظهر القائمة فارغة لصفوف الويب.
  static const List<(String, String)> _dosageForms = <(String, String)>[
    ('tablet', 'dosage_tablet'),
    ('capsule', 'dosage_capsule'),
    ('syrup', 'dosage_syrup'),
    ('injection', 'dosage_injection'),
    ('cream', 'dosage_cream'),
    ('drop', 'dosage_drop'),
    ('inhaler', 'dosage_inhaler'),
    ('other', 'dosage_other'),
  ];

  /// التسميات العربية الخاطئة التي خزّنها الموبايل قبل الإصلاح — تُحوَّل إلى
  /// enum عند فتح التعديل (Task 68-b C: مطابقة قيمة→اختيار بقوة)
  static const Map<String, String> _legacyDosageLabels = <String, String>{
    'أقراص': 'tablet',
    'كبسولات': 'capsule',
    'شراب': 'syrup',
    'حقن': 'injection',
    'كريم': 'cream',
    'قطرة': 'drop',
    'بخاخ': 'inhaler',
    'أخرى': 'other',
  };

  /// Task 68-b (F): وحدات التركيز الثمانية حرفيًا من lib/product.ts (strengthUnits)
  static const List<(String, String)> _strengthUnits = <(String, String)>[
    ('mg', 'unit_mg'),
    ('mcg', 'unit_mcg'),
    ('g', 'unit_g'),
    ('ml', 'unit_ml'),
    ('mg/ml', 'unit_mg_ml'),
    ('IU', 'unit_iu'),
    ('%', 'unit_percent'),
    ('other', 'unit_other_full'),
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _generic;
  late final TextEditingController _strengthValue;
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
  late final FocusNode _sellingFocus;
  late final FocusNode _unitsFocus;
  late String _strengthUnit;
  String _dosage = 'tablet';
  bool _boxStrip = true;
  bool _isActive = true;
  bool _saving = false;
  String? _error;
  // نظام الباركود (Final Decision 6): شارة النوع + زر التوليد للتعديل
  // وخيار التوليد التلقائي عند الإنشاء بلا باركود.
  String _barcodeType = '';
  bool _generatingBarcode = false;
  bool _autoGenerateBarcode = true;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    // Task 68-b (F): التركيز المحفوظ «500mg» يُفكك إلى رقم + وحدة مثل splitStrength
    final (String strengthSplitValue, String strengthSplitUnit) = _splitStrength(p?.strength ?? '');
    _name = TextEditingController(text: p?.name ?? '');
    _generic = TextEditingController(text: p?.genericName ?? '');
    _strengthValue = TextEditingController(text: strengthSplitValue);
    _strengthUnit = strengthSplitUnit;
    _barcode = TextEditingController(text: p?.barcode ?? '');
    _cost = TextEditingController(text: p == null ? '' : Fmt.piastresToInput(p.costPricePiastres));
    _selling = TextEditingController(text: p == null ? '' : Fmt.piastresToInput(p.sellingPricePiastres));
    _stripPrice = TextEditingController(
        text: p == null || !p.boxStrip || p.partialSellingPricePiastres <= 0
            ? ''
            : Fmt.piastresToInput(p.partialSellingPricePiastres));
    _unitsPerBox = TextEditingController(text: p == null || p.unitsPerBox <= 1 ? '' : '${p.unitsPerBox}');
    // Task 68-b (I): الافتراضي «0» مثل EMPTY_PRODUCT_FORM في الويب
    _minStock = TextEditingController(text: p == null ? '0' : '${p.minStockLevel}');
    _initialBoxes = TextEditingController();
    _initialStrips = TextEditingController();
    _batch = TextEditingController();
    _expiry = TextEditingController();
    _dosage = _resolveDosage(p?.dosageForm);
    _boxStrip = p?.boxStrip ?? true;
    _isActive = p?.isActive ?? true;
    _barcodeType = p?.barcodeType ?? '';
    // Task 68-b (I): اقتراح سعر الشريط عند مغادرة سعر البيع/عدد الشرائط
    // (نفس onBlur في الويب — product-form-fields.tsx:168/196)
    _sellingFocus = FocusNode()..addListener(_onPriceFocusChanged);
    _unitsFocus = FocusNode()..addListener(_onPriceFocusChanged);
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _name, _generic, _strengthValue, _barcode, _cost, _selling, _stripPrice,
      _unitsPerBox, _minStock, _initialBoxes, _initialStrips, _batch, _expiry,
    ]) {
      c.dispose();
    }
    _sellingFocus.dispose();
    _unitsFocus.dispose();
    super.dispose();
  }

  /// قيمة الشكل الدوائي الجاهزة للحفظ: enum إنجليزي معروف كما هو، تسمية عربية
  /// قديمة تُحوَّل لenum، والقيم الفارغة تعود لافتراضي الويب «tablet».
  String _resolveDosage(String? stored) {
    final v = (stored ?? '').trim();
    if (v.isEmpty) return 'tablet';
    if (_dosageForms.any((f) => f.$1 == v)) return v;
    return _legacyDosageLabels[v] ?? v;
  }

  /// ترجمة الوحدة المكتوبة (MG / ملجم / µg …) إلى قيمة القائمة —
  /// نسخة normalizeStrengthUnit من lib/product.ts:41-54
  String _normalizeStrengthUnit(String raw) {
    final unit = raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (unit.isEmpty) return '';
    const Map<String, String> aliases = <String, String>{
      'mg': 'mg', 'ملجم': 'mg', 'ملغ': 'mg',
      'mcg': 'mcg', 'ug': 'mcg', 'µg': 'mcg', 'μg': 'mcg', 'ميكروجرام': 'mcg', 'ميكروغرام': 'mcg',
      'g': 'g', 'جم': 'g', 'جرام': 'g', 'غرام': 'g',
      'ml': 'ml', 'مل': 'ml', 'ملليتر': 'ml', 'مليلتر': 'ml',
      'mg/ml': 'mg/ml', 'mg/1ml': 'mg/ml', 'ملجم/مل': 'mg/ml', 'ملغ/مل': 'mg/ml',
      'مج/مل': 'mg/ml', 'مجم/مل': 'mg/ml',
      'iu': 'IU', 'i.u': 'IU', 'i.u.': 'IU', 'وحدةدولية': 'IU', 'وحدهدولية': 'IU',
      '%': '%', '٪': '%', 'نسبة': '%', 'نسبةمئوية': '%',
    };
    return aliases[unit] ?? '';
  }

  /// تفكيك تركيز محفوظ («500mg» / «5%» / «2.5ml») إلى رقم + وحدة —
  /// نسخة splitStrength من lib/product.ts:60-69
  (String, String) _splitStrength(String strength) {
    final clean = strength.trim();
    if (clean.isEmpty) return ('', 'mg');
    final RegExpMatch? m = RegExp(r'^(\d+(?:[.,]\d+)?)\s*(.+)$').firstMatch(clean);
    if (m != null) {
      final unit = _normalizeStrengthUnit(m.group(2)!);
      if (unit.isNotEmpty) return (m.group(1)!.replaceFirst(',', '.'), unit);
    }
    return (clean, 'other');
  }

  /// تركيب التركيز النهائي المخزَّن — نسخة composeStrength من lib/product.ts:72-77
  String _composeStrength(String value, String unit) {
    final clean = value.trim();
    if (clean.isEmpty) return '';
    if (unit.isEmpty || unit == 'other') return clean;
    return '${clean.replaceAll(RegExp(r'\s+'), '').replaceAll(',', '.')}$unit';
  }

  /// Task 68-b (I): اقتراح سعر الشريط = سعر العلبة ÷ عدد الشرائط (نصف لأعلى)
  /// عندما لم يكتب المستخدم شيئًا — نسخة suggestStripPrice
  /// (product-form-fields.tsx:62-69): عدد صحيح بياسة ثم تحويله لجنيه.
  void _suggestStripPrice() {
    if (_stripPrice.text.trim().isNotEmpty) return;
    final boxPiastres = Fmt.parseEGPToPiastres(_selling.text);
    final units = int.tryParse(_unitsPerBox.text.trim()) ?? 0;
    if (boxPiastres == null || units < 2) return;
    _stripPrice.text = Fmt.piastresToInput((boxPiastres / units).round());
  }

  /// عند مغادرة أيٍّ من الحقلين (الحقل الآخر لم يعد مركزًا عليه)
  void _onPriceFocusChanged() {
    if (!_sellingFocus.hasFocus && !_unitsFocus.hasFocus) _suggestStripPrice();
  }

  /// Task 68-b (G): منتقي تاريخ يعيد ISO yyyy-MM-dd مثل input type=date
  /// بالويب — القيم المخزنة القديمة تظهر وتظل قابلة للتعديل.
  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 5);
    final lastDate = DateTime(now.year + 20);
    DateTime initial = DateTime.tryParse(_expiry.text.trim()) ?? now;
    if (initial.isBefore(firstDate)) initial = firstDate;
    if (initial.isAfter(lastDate)) initial = lastDate;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked == null) return;
    setState(() => _expiry.text = Fmt.isoDay(picked));
  }

  /// توليد باركود داخلي لمنتج قائم بلا باركود — خادمي حصراً عبر sequence
  /// ذرية (القرار النهائي 4)، والرمز يُعرض في الحقل فورًا بشارة «داخلي».
  Future<void> _generateBarcode() async {
    if (_generatingBarcode || !_isEdit) return;
    setState(() {
      _generatingBarcode = true;
      _error = null;
    });
    try {
      final code = await ApiClient.instance.generateProductBarcode(widget.existing!.id);
      if (!mounted) return;
      setState(() {
        _barcode.text = code;
        _barcodeType = 'RCN_EAN13';
        _generatingBarcode = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, AppI18n.instance.t('inventory', 'barcode_generate_error'));
        _generatingBarcode = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.t('inventory', 'barcode_generate_error');
        _generatingBarcode = false;
      });
    }
  }

  Future<void> _save() async {
    final i18n = AppI18n.instance;
    if (!_formKey.currentState!.validate() || _saving) return;
    // Task 68-b (I): تعويض غياب blur المتصفح في فلاتر — الاقتراح يُطبق قبل التحقق
    _suggestStripPrice();
    final name = _name.text.trim();
    final cost = Fmt.parseEGPToPiastres(_cost.text);
    final selling = Fmt.parseEGPToPiastres(_selling.text);
    if (name.isEmpty || cost == null || selling == null) {
      setState(() => _error = i18n.t('inventory', 'error_prices_required'));
      return;
    }
    // Task 68-b (F): تركيب التركيز من الرقم + الوحدة، وتحقق readProductFormCommon:
    // «أخرى» تقبل أي نص، وبقية الوحدات تشترط رقماً فقط (error_strength_invalid)
    final strengthRaw = _strengthValue.text.trim();
    final strength = _composeStrength(strengthRaw, _strengthUnit);
    if (strength.isNotEmpty &&
        _strengthUnit != 'other' &&
        !RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(strengthRaw)) {
      setState(() => _error = i18n.t('inventory', 'error_strength_invalid'));
      return;
    }
    int? partial;
    final unitsPerBox = _boxStrip ? (int.tryParse(_unitsPerBox.text.trim()) ?? 0) : 0;
    if (_boxStrip) {
      if (unitsPerBox < 2) {
        // Task 68-b (H): المفتاح في نطاق pos وليس inventory — كان يظهر النص الخام
        setState(() => _error = i18n.t('pos', 'fieldUnitsPerBoxHint'));
        return;
      }
      final stripRaw = _stripPrice.text.trim();
      if (stripRaw.isEmpty) {
        // Task 68-b (I): الفارغ = مطلوب (رسالة مختلفة عن غير الصالح مثل الويب)
        setState(() => _error = i18n.t('inventory', 'error_strip_price_required'));
        return;
      }
      final stripPrice = Fmt.parseEGPToPiastres(stripRaw);
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
          'strength': strength,
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
          'strength': strength,
          'barcode': _barcode.text.trim(),
          // الخيار الظاهر عند فراغ الباركود: توليد خادمي داخل معاملة الإنشاء
          if (_barcode.text.trim().isEmpty) 'generate_barcode': _autoGenerateBarcode,
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
    final theme = Theme.of(context);
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
                  // Task 68-b (C): القيمة المخزنة enum إنجليزي والتسمية معروضة مترجمة
                  AppField(
                    label: i18n.t('inventory', 'label_dosage_form'),
                    child: AppDropdown<String>(
                      value: _dosage,
                      hint: i18n.t('common', 'select_placeholder'),
                      items: <DropdownMenuItem<String>>[
                        for (final (String value, String label) in _dosageForms)
                          DropdownMenuItem<String>(value: value, child: Text(i18n.t('inventory', label), style: const TextStyle(fontSize: 13))),
                        // قيمة enum صحيحة خارج القائمة الثمانية (مثل ointment من
                        // الاستيراد) تُعرض تحت «أخرى» وتُحفظ كما هي بلا فقد بيانات
                        if (!_dosageForms.any((f) => f.$1 == _dosage))
                          DropdownMenuItem<String>(value: _dosage, child: Text(i18n.t('inventory', 'dosage_other'), style: const TextStyle(fontSize: 13))),
                      ],
                      onChanged: (String? v) => setState(() => _dosage = v ?? 'tablet'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Task 68-b (F): حقلان — قيمة رقمية + وحدة من قائمة الثمانية
                  AppField(
                    label: i18n.t('inventory', 'label_strength'),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: AppInput(
                            controller: _strengthValue,
                            hint: i18n.t('inventory', _strengthUnit == 'other' ? 'placeholder_strength_other' : 'placeholder_strength_value'),
                            keyboard: _strengthUnit == 'other'
                                ? TextInputType.text
                                : const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 168,
                          child: AppDropdown<String>(
                            value: _strengthUnit,
                            items: <DropdownMenuItem<String>>[
                              for (final (String value, String label) in _strengthUnits)
                                DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(i18n.t('inventory', label), style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            onChanged: (String? v) => setState(() => _strengthUnit = v ?? 'mg'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // الباركود اختياري (مواءمة مع الاستيراد) — شارة النوع الدلالي
                  // تُظهر «داخلي/مصنع/مخصص» بدل إظهار رمز النوع الخام (القرار 2/5)
                  AppField(
                    label: i18n.t('inventory', 'label_barcode'),
                    trailing: _barcodeType.isEmpty
                        ? null
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _barcodeType == 'RCN_EAN13'
                                  ? theme.colorScheme.primary.withOpacity(0.10)
                                  : theme.colorScheme.onSurface.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              i18n.t(
                                'inventory',
                                _barcodeType == 'RCN_EAN13'
                                    ? 'barcode_badge_internal'
                                    : (_barcodeType == 'GTIN_EAN13' || _barcodeType == 'GTIN_UPCA'
                                        ? 'barcode_badge_gtin'
                                        : 'barcode_badge_custom'),
                              ),
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                  color: _barcodeType == 'RCN_EAN13'
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface.withOpacity(0.6)),
                            ),
                          ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        AppInput(
                          controller: _barcode,
                          hint: i18n.t('inventory', 'placeholder_barcode'),
                          keyboard: TextInputType.text,
                          onChanged: (_) => setState(() {}),
                        ),
                        if (RegExp(r'^2\d{12}$').hasMatch(_barcode.text.trim()))
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(i18n.t('inventory', 'barcode_rcn_warning'),
                                style: TextStyle(fontSize: 11, color: Colors.amber.shade800)),
                          ),
                        if (_barcode.text.trim().isEmpty && !_isEdit) ...<Widget>[
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: () => setState(() => _autoGenerateBarcode = !_autoGenerateBarcode),
                            child: Row(
                              children: <Widget>[
                                SizedBox(
                                  width: 16, height: 16,
                                  child: Checkbox(value: _autoGenerateBarcode, onChanged: (bool? v) => setState(() => _autoGenerateBarcode = v ?? true)),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(i18n.t('inventory', 'barcode_generate_checkbox'),
                                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.6))),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (_barcode.text.trim().isEmpty && _isEdit) ...<Widget>[
                          const SizedBox(height: 4),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton(
                              onPressed: _generatingBarcode ? null : _generateBarcode,
                              child: Text(
                                _generatingBarcode ? i18n.t('inventory', 'barcode_generating') : i18n.t('inventory', 'barcode_generate_button'),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
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
                    AppField(
                      label: i18n.t('inventory', 'label_units_per_box'),
                      child: AppInput(
                        controller: _unitsPerBox,
                        focusNode: _unitsFocus,
                        keyboard: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
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
                  AppField(
                    label: i18n.t('inventory', 'label_selling_price'),
                    child: AppInput(
                      controller: _selling,
                      focusNode: _sellingFocus,
                      hint: i18n.t('inventory', 'placeholder_selling_price'),
                      keyboard: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
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
                    // Task 68-b (G): منتقي تاريخ بدل نص حر — ينتج ISO yyyy-MM-dd
                    AppField(
                      label: i18n.t('inventory', 'label_expiry_date'),
                      child: GestureDetector(
                        onTap: _pickExpiry,
                        child: AbsorbPointer(
                          child: AppInput(
                            controller: _expiry,
                            hint: 'YYYY-MM-DD',
                            suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
                          ),
                        ),
                      ),
                    ),
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

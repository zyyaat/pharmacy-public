import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/ui.dart';

/// Task 68-c — حركات المخزون مطابقة لصفحة inventory/movements بالويب:
/// PageHeader مع عداد count_shown، فلاتر مسودّة (بحث بتأخير 400ms + نوع/
/// اتجاه/من-إلى تُطبَّق بزر «تطبيق» صريح و«مسح الفلاتر» عند وجود فلاتر
/// مطبقة فقط)، وجدول بأعمدة: التاريخ (شهر قصير + وقت 12 ساعة ص/م)،
/// الدواء (الاسم العلمي + السبب/ملاحظات)، التشغيلة، النوع بشارة ملونة
/// حسب خريطة variants، الكمية بأسهم داخل/خارج ملونة، الرصيد بعدها،
/// بواسطة (th_by)، الفرع — مع حالة فراغ بأيقونة وتمييز empty_filtered.
class MovementsScreen extends StatefulWidget {
  const MovementsScreen({super.key});

  @override
  State<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends State<MovementsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final List<StockMovementRow> _rows = <StockMovementRow>[];

  // القيم المطبَّقة (المرسلة إلى الخادم) — كـ filters في الويب
  String _search = '';
  String _type = '';
  String _direction = '';
  String _from = '';
  String _to = '';

  // مسودّات النموذج قبل التطبيق — كـ *Input في الويب
  String _typeInput = '';
  String _directionInput = '';
  String _fromInput = '';
  String _toInput = '';

  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  Timer? _debounce;

  static const List<String> _monthsShortAr = <String>[
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];
  static const List<String> _monthsShortEn = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const List<(String, String)> _types = <(String, String)>[
    ('sale', 'type_sale'),
    ('return_from_customer', 'type_return_from_customer'),
    ('purchase', 'type_purchase'),
    ('return_to_supplier', 'type_return_to_supplier'),
    ('adjustment', 'type_adjustment'),
    ('transfer_in', 'type_transfer_in'),
    ('transfer_out', 'type_transfer_out'),
    ('expiry_writeoff', 'type_expiry_writeoff'),
    ('damage_writeoff', 'type_damage_writeoff'),
    ('theft_loss', 'type_theft_loss'),
    ('production_input', 'type_production_input'),
    ('production_output', 'type_production_output'),
  ];

  @override
  void initState() {
    super.initState();
    _load(append: false);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _hasFilters =>
      _search.isNotEmpty || _type.isNotEmpty || _direction.isNotEmpty || _from.isNotEmpty || _to.isNotEmpty;

  /// [append] = false: الصفحة الأولى بالفلاتر المطبَّقة تستبدل القائمة.
  /// [append] = true: «تحميل المزيد» تُلحق عند إزاحة طول القائمة الحالي.
  Future<void> _load({required bool append}) async {
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
      }
      _error = null;
    });
    final i18n = AppI18n.instance;
    try {
      final page = await ApiClient.instance.stockMovements(
        type: _type,
        search: _search,
        from: _from,
        to: _to,
        direction: _direction,
        offset: append ? _rows.length : 0,
      );
      if (!mounted) return;
      setState(() {
        if (append) {
          _rows.addAll(page.movements);
        } else {
          _rows
            ..clear()
            ..addAll(page.movements);
        }
        _total = page.total;
        _loading = false;
        _loadingMore = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('movements', 'error_load'));
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = i18n.t('movements', 'error_load');
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  /// submitFilters في الويب: تثبيت المسودّات كفلاتر مطبقة وتحميل الصفحة الأولى
  void _applyFilters() {
    _debounce?.cancel();
    setState(() {
      _search = _searchCtrl.text.trim();
      _type = _typeInput;
      _direction = _directionInput;
      _from = _fromInput;
      _to = _toInput;
    });
    _load(append: false);
  }

  /// resetFilters في الويب: مسح المسودّات والمطبَّق معًا وإعادة التحميل
  void _resetFilters() {
    _debounce?.cancel();
    setState(() {
      _searchCtrl.clear();
      _typeInput = '';
      _directionInput = '';
      _fromInput = '';
      _toInput = '';
      _search = '';
      _type = '';
      _direction = '';
      _from = '';
      _to = '';
    });
    _load(append: false);
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _applyFilters);
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(initial.year + 2),
      locale: Locale(AppI18n.instance.locale),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromInput = Fmt.isoDay(picked);
      } else {
        _toInput = Fmt.isoDay(picked);
      }
    });
  }

  // --------------------------------------------------------- مساعدات العرض

  /// formatMovementDate — يوم رقمي + شهر قصير + سنة
  String _fmtDay(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return iso;
    final months = AppI18n.instance.locale == 'ar' ? _monthsShortAr : _monthsShortEn;
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  /// formatMovementTime — ساعة رقمين + دقيقة + ص/م (12 ساعة)
  String _fmtClock(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '—';
    final ar = AppI18n.instance.locale == 'ar';
    final h = (d.hour % 12 == 0 ? 12 : d.hour % 12).toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    final period = ar ? (d.hour < 12 ? 'ص' : 'م') : (d.hour < 12 ? 'am' : 'pm');
    return '$h:$mm $period';
  }

  /// formatMovementQuantity — ترجمة شريط/علبة عبر i18n والباقي كما ورد
  String _unitLabel(String unit) {
    final i18n = AppI18n.instance;
    if (unit == 'strip') return i18n.t('movements', 'unit_strip');
    if (unit == 'box') return i18n.t('movements', 'unit_box');
    return unit;
  }

  String _quantityText(num quantity, String unit) => '${Fmt.number(quantity.abs())} ${_unitLabel(unit)}';

  /// movementTypeVariant في lib/movements.ts — خريطة نغمات الشارة حرفيًا
  BadgeTone _typeTone(String type) {
    switch (type) {
      case 'purchase':
      case 'return_from_customer':
      case 'transfer_in':
      case 'production_output':
        return BadgeTone.success;
      case 'sale':
        return BadgeTone.primary;
      case 'return_to_supplier':
      case 'expiry_writeoff':
      case 'damage_writeoff':
      case 'theft_loss':
        return BadgeTone.destructive;
      default:
        return BadgeTone.muted;
    }
  }

  String _typeKey(String type) {
    for (final (String v, String key) in _types) {
      if (v == type) return key;
    }
    return type;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final body = <Widget>[
      PageHeader(
        i18n.t('movements', 'title'),
        subtitle: i18n.t('movements', 'subtitle'),
        // count_shown بجوار العنوان عند وجود إجمالي — كما في الويب
        actions: <Widget>[
          if (_total > 0)
            Text(
              i18n.t('movements', 'count_shown', {'shown': Fmt.number(_rows.length), 'total': Fmt.number(_total)}),
              style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.55)),
            ),
        ],
      ),
      const SizedBox(height: 24),

      // الفلاتر — مسودّة حتى الضغط على «تطبيق» (كـ form الويب)
      AppCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: <Widget>[
            SearchField(
              controller: _searchCtrl,
              hint: i18n.t('movements', 'search_placeholder'),
              onChanged: _onSearchChanged,
              onClear: () {
                _searchCtrl.clear();
                _applyFilters();
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: AppDropdown<String>(
                    value: _typeInput,
                    hint: i18n.t('movements', 'filter_all_types'),
                    items: <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(value: '', child: Text(i18n.t('movements', 'filter_all_types'), style: const TextStyle(fontSize: 13))),
                      for (final (String v, String key) in _types)
                        DropdownMenuItem<String>(value: v, child: Text(i18n.t('movements', key), style: const TextStyle(fontSize: 13))),
                    ],
                    onChanged: (String? v) => setState(() => _typeInput = v ?? ''),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppDropdown<String>(
                    value: _directionInput,
                    hint: i18n.t('movements', 'direction_all'),
                    items: <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(value: '', child: Text(i18n.t('movements', 'direction_all'), style: const TextStyle(fontSize: 13))),
                      DropdownMenuItem<String>(value: 'in', child: Text(i18n.t('movements', 'direction_in'), style: const TextStyle(fontSize: 13))),
                      DropdownMenuItem<String>(value: 'out', child: Text(i18n.t('movements', 'direction_out'), style: const TextStyle(fontSize: 13))),
                    ],
                    onChanged: (String? v) => setState(() => _directionInput = v ?? ''),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: WButton(
                    _fromInput.isEmpty ? i18n.t('movements', 'from_label') : _fromInput,
                    icon: Icons.date_range,
                    variant: WButtonVariant.outline,
                    size: WButtonSize.sm,
                    onPressed: () => _pickDate(isFrom: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: WButton(
                    _toInput.isEmpty ? i18n.t('movements', 'to_label') : _toInput,
                    icon: Icons.date_range,
                    variant: WButtonVariant.outline,
                    size: WButtonSize.sm,
                    onPressed: () => _pickDate(isFrom: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                WButton(i18n.t('movements', 'apply'),
                    variant: WButtonVariant.secondary, size: WButtonSize.sm,
                    onPressed: _applyFilters),
                // «مسح الفلاتر» تظهر فقط عند وجود فلاتر مطبقة — كالويب
                if (_hasFilters) ...<Widget>[
                  const SizedBox(width: 8),
                  WButton(i18n.t('movements', 'clear_filters'),
                      variant: WButtonVariant.ghost, size: WButtonSize.sm,
                      icon: Icons.restart_alt,
                      onPressed: _resetFilters),
                ],
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),

      // خطأ أثناء التحميل/«تحميل المزيد» فوق الجدول — كالويب
      if (_error != null && _rows.isNotEmpty) ...<Widget>[
        ErrorBanner(_error!),
        const SizedBox(height: 12),
      ],

      // بطاقة الجدول
      AppCard(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading && _rows.isEmpty
              ? const LoadingBox()
              : _error != null && _rows.isEmpty
                  ? ErrorRetry(_error!, onRetry: () => _load(append: false))
                  : _rows.isEmpty
                      ? // حالة الفراغ: أيقونة + empty_filtered/empty_default
                      Column(
                          children: <Widget>[
                            Icon(Icons.assignment_outlined,
                                size: 40, color: theme.colorScheme.onSurface.withOpacity(0.25)),
                            const SizedBox(height: 12),
                            Text(i18n.t('movements', 'empty_title'),
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 8),
                            Text(
                              _hasFilters ? i18n.t('movements', 'empty_filtered') : i18n.t('movements', 'empty_default'),
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                            ),
                          ],
                        )
                      : WebTable(
                          minWidth: 980,
                          headers: <String>[
                            i18n.t('movements', 'th_date'),
                            i18n.t('movements', 'th_product'),
                            i18n.t('movements', 'th_batch'),
                            i18n.t('movements', 'th_type'),
                            i18n.t('movements', 'th_quantity'),
                            i18n.t('movements', 'th_balance_after'),
                            i18n.t('movements', 'th_by'),
                            i18n.t('movements', 'th_branch'),
                          ],
                          rows: <List<Widget>>[
                            for (final StockMovementRow r in _rows)
                              <Widget>[
                                // التاريخ: سطران (يوم شهر سنة / وقت 12 ساعة ص/م)
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(_fmtDay(r.createdAt),
                                        style: TextStyle(
                                            fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.8))),
                                    Text(_fmtClock(r.createdAt),
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: theme.colorScheme.onSurface.withOpacity(0.5))),
                                  ],
                                ),
                                // الدواء: الاسم + العلمي + السبب/الملاحظات
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(r.productName,
                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                    if (r.genericName != null && r.genericName!.isNotEmpty)
                                      Text(r.genericName!,
                                          maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: theme.colorScheme.onSurface.withOpacity(0.5))),
                                    if ((r.reason != null && r.reason!.isNotEmpty) ||
                                        (r.notes != null && r.notes!.isNotEmpty))
                                      Text(
                                        (r.reason != null && r.reason!.isNotEmpty) ? r.reason! : r.notes!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                                      ),
                                  ],
                                ),
                                Text((r.batchNumber == null || r.batchNumber!.isEmpty)
                                    ? '—'
                                    : r.batchNumber!,
                                    textDirection: (r.batchNumber == null || r.batchNumber!.isEmpty)
                                        ? null
                                        : TextDirection.ltr,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurface.withOpacity(0.7))),
                                AppBadge(
                                  i18n.t('movements', _typeKey(r.movementType)),
                                  tone: _typeTone(r.movementType),
                                ),
                                // الكمية: سهم + إشارة + عدد مطلق ملون (emerald/destructive)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(
                                      r.quantity >= 0 ? Icons.south_west : Icons.north_east,
                                      size: 14,
                                      color: r.quantity >= 0
                                          ? (dark ? AppColors.successFgDark : AppColors.successFg)
                                          : theme.colorScheme.error,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      '${r.quantity >= 0 ? '+' : '−'}${_quantityText(r.quantity, r.unit)}',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: r.quantity >= 0
                                              ? (dark ? AppColors.successFgDark : AppColors.successFg)
                                              : theme.colorScheme.error),
                                    ),
                                  ],
                                ),
                                Text(r.quantityAfter == null
                                    ? '—'
                                    : _quantityText(r.quantityAfter!, r.unit),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurface.withOpacity(0.7))),
                                Text(r.actorName == null || r.actorName!.isEmpty ? '—' : r.actorName!,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurface.withOpacity(0.7))),
                                Text(r.branchName == null || r.branchName!.isEmpty ? '—' : r.branchName!,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurface.withOpacity(0.7))),
                              ],
                          ],
                        ),
        ),
      ),

      // تحميل المزيد
      if (_rows.length < _total && !_loading && _error == null && _rows.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Center(
            child: WButton(
              i18n.t('movements', 'load_more'),
              variant: WButtonVariant.secondary,
              loading: _loadingMore,
              onPressed: _loadingMore ? null : () => _load(append: true),
            ),
          ),
        ),
    ];
    return RefreshIndicator(
      onRefresh: () => _load(append: false),
      child: ListView(padding: const EdgeInsets.all(16), children: body),
    );
  }
}

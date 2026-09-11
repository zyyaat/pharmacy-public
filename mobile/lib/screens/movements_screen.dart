import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/ui.dart';

/// Task 62 — حركات المخزون بنسخة الويب حرفيًا: رأس صفحة، بطاقة فلاتر
/// (بحث/نوع/اتجاه/من-إلى/مسح) ثم جدول بتمرير أفقي: الصنف/النوع/الكمية
/// بشارة الاتجاه/التشغيلة/التاريخ/المستخدم/المرجع، مع تحميل المزيد.
class MovementsScreen extends StatefulWidget {
  const MovementsScreen({super.key});

  @override
  State<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends State<MovementsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final List<StockMovementRow> _rows = <StockMovementRow>[];
  String _type = '';
  String _direction = '';
  String _from = '';
  String _to = '';
  int _total = 0;
  bool _loading = true;
  String? _error;

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
    _load(reset: true);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final i18n = AppI18n.instance;
    try {
      final page = await ApiClient.instance.stockMovements(
        type: _type,
        search: _searchCtrl.text.trim(),
        from: _from,
        to: _to,
        direction: _direction,
        offset: reset ? 0 : _rows.length,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _rows.clear();
        _rows.addAll(page.movements);
        _total = page.total;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('movements', 'error_load'));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = i18n.t('movements', 'error_load');
        _loading = false;
      });
    }
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
        _from = Fmt.isoDay(picked);
      } else {
        _to = Fmt.isoDay(picked);
      }
    });
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final body = <Widget>[
      PageHeader(i18n.t('movements', 'title'), subtitle: i18n.t('movements', 'subtitle')),
      const SizedBox(height: 24),

      // بطاقة الفلاتر — مثل بطاقة الفلترة في الويب
      AppCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: <Widget>[
            SearchField(
              controller: _searchCtrl,
              hint: i18n.t('movements', 'search_placeholder'),
              onChanged: (_) => _load(reset: true),
              onClear: () {
                _searchCtrl.clear();
                _load(reset: true);
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: AppDropdown<String>(
                    value: _type.isEmpty ? '' : _type,
                    hint: i18n.t('movements', 'filter_all_types'),
                    items: <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(value: '', child: Text(i18n.t('movements', 'filter_all_types'), style: const TextStyle(fontSize: 13))),
                      for (final (String v, String key) in _types)
                        DropdownMenuItem<String>(value: v, child: Text(i18n.t('movements', key), style: const TextStyle(fontSize: 13))),
                    ],
                    onChanged: (String? v) {
                      setState(() => _type = v ?? '');
                      _load(reset: true);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppDropdown<String>(
                    value: _direction.isEmpty ? '' : _direction,
                    hint: i18n.t('movements', 'direction_all'),
                    items: <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(value: '', child: Text(i18n.t('movements', 'direction_all'), style: const TextStyle(fontSize: 13))),
                      DropdownMenuItem<String>(value: 'in', child: Text(i18n.t('movements', 'direction_in'), style: const TextStyle(fontSize: 13))),
                      DropdownMenuItem<String>(value: 'out', child: Text(i18n.t('movements', 'direction_out'), style: const TextStyle(fontSize: 13))),
                    ],
                    onChanged: (String? v) {
                      setState(() => _direction = v ?? '');
                      _load(reset: true);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: WButton(
                    _from.isEmpty ? i18n.t('movements', 'from_label') : _from,
                    icon: Icons.date_range,
                    variant: WButtonVariant.outline,
                    size: WButtonSize.sm,
                    onPressed: () => _pickDate(isFrom: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: WButton(
                    _to.isEmpty ? i18n.t('movements', 'to_label') : _to,
                    icon: Icons.date_range,
                    variant: WButtonVariant.outline,
                    size: WButtonSize.sm,
                    onPressed: () => _pickDate(isFrom: false),
                  ),
                ),
                const SizedBox(width: 8),
                IconButtonGhost(
                  Icons.filter_alt_off_outlined,
                  tooltip: i18n.t('movements', 'clear_filters'),
                  onPressed: () {
                    setState(() {
                      _type = '';
                      _direction = '';
                      _from = '';
                      _to = '';
                      _searchCtrl.clear();
                    });
                    _load(reset: true);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),

      // بطاقة الجدول
      AppCard(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: CardTitle(i18n.t('movements', 'title'), icon: Icons.swap_horiz,
                  subtitle: i18n.t('movements', 'count_shown', {'shown': Fmt.number(_rows.length), 'total': Fmt.number(_total)})),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: _loading && _rows.isEmpty
                  ? const LoadingBox()
                  : _error != null
                      ? ErrorRetry(_error!, onRetry: () => _load(reset: true))
                      : _rows.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Text(i18n.t('movements', 'empty_title'),
                                  style: TextStyle(
                                      fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                            )
                          : WebTable(
                              minWidth: 780,
                              headers: <String>[
                                i18n.t('movements', 'th_product'),
                                i18n.t('movements', 'th_type'),
                                i18n.t('movements', 'th_quantity'),
                                i18n.t('movements', 'th_batch'),
                                i18n.t('movements', 'th_date'),
                                i18n.t('movements', 'th_user'),
                              ],
                              rows: <List<Widget>>[
                                for (final StockMovementRow r in _rows)
                                  <Widget>[
                                    Text(r.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    Text(i18n.t('movements', _typeKey(r.movementType))),
                                    // الكمية بشارة الاتجاه (داخل/خارج)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: r.quantity > 0 ? AppColors.successBg : AppColors.warningBg,
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        '${r.quantity > 0 ? '+' : ''}${Fmt.number(r.quantity)} ${r.unit}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: r.quantity > 0 ? AppColors.successFg : AppColors.warningFg),
                                      ),
                                    ),
                                    Text((r.batchNumber == null || r.batchNumber!.isEmpty) ? '—' : r.batchNumber!),
                                    Text(Fmt.dateTime(r.createdAt, locale: i18n.locale)),
                                    Text(r.actorName == null || r.actorName!.isEmpty ? '—' : r.actorName!),
                                  ],
                              ],
                            ),
            ),
            if (_rows.length < _total && !_loading && _error == null && _rows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Center(
                  child: WButton(
                    i18n.t('movements', 'load_more'),
                    variant: WButtonVariant.secondary,
                    size: WButtonSize.sm,
                    onPressed: () => _load(),
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(padding: const EdgeInsets.all(16), children: body),
    );
  }

  String _typeKey(String type) {
    for (final (String v, String key) in _types) {
      if (v == type) return key;
    }
    return 'type_adjustment';
  }
}

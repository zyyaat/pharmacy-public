import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/ui.dart';

/// سجل حركات المخزون — نفس فلاتر صفحة الويب: النوع، الاتجاه، من/إلى،
/// بحث، مع ترقيم صفحات (تحميل المزيد).
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
        _error = AppI18n.instance.t('movements', 'error_load');
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
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('movements', 'title'))),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: <Widget>[
                SearchField(
                  controller: _searchCtrl,
                  hint: i18n.t('movements', 'search_placeholder'),
                  onChanged: (_) => _load(reset: true),
                  onClear: () { _searchCtrl.clear(); _load(reset: true); },
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppDropdown<String>(
                        value: _type.isEmpty ? '' : _type,
                        hint: i18n.t('movements', 'filter_all_types'),
                        items: <DropdownMenuItem<String>>[
                          const DropdownMenuItem<String>(value: '', child: Text('كل الحركات', style: TextStyle(fontSize: 13))),
                          for (final (String v, String key) in _types)
                            DropdownMenuItem<String>(value: v, child: Text(i18n.t('movements', key), style: const TextStyle(fontSize: 13))),
                        ],
                        onChanged: (String? v) { setState(() => _type = v ?? ''); _load(reset: true); },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppDropdown<String>(
                        value: _direction.isEmpty ? '' : _direction,
                        hint: i18n.t('movements', 'direction_all'),
                        items: <DropdownMenuItem<String>>[
                          DropdownMenuItem<String>(value: '', child: Text(i18n.t('movements', 'direction_all'), style: const TextStyle(fontSize: 13))),
                          DropdownMenuItem<String>(value: 'in', child: Text(i18n.t('movements', 'direction_in'), style: const TextStyle(fontSize: 13))),
                          DropdownMenuItem<String>(value: 'out', child: Text(i18n.t('movements', 'direction_out'), style: const TextStyle(fontSize: 13))),
                        ],
                        onChanged: (String? v) { setState(() => _direction = v ?? ''); _load(reset: true); },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(isFrom: true),
                        icon: const Icon(Icons.date_range, size: 16),
                        label: Text(_from.isEmpty ? i18n.t('movements', 'from_label') : _from, style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(isFrom: false),
                        icon: const Icon(Icons.date_range, size: 16),
                        label: Text(_to.isEmpty ? i18n.t('movements', 'to_label') : _to, style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                    IconButton(
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
                      icon: const Icon(Icons.filter_alt_off_outlined, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    i18n.t('movements', 'count_shown', {'shown': Fmt.number(_rows.length), 'total': Fmt.number(_total)}),
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading && _rows.isEmpty
                ? const LoadingBox()
                : _error != null
                    ? ErrorRetry(_error!, onRetry: () => _load(reset: true))
                    : _rows.isEmpty
                        ? EmptyState(i18n.t('movements', 'empty_title'), icon: Icons.swap_horiz)
                        : RefreshIndicator(
                            onRefresh: () => _load(reset: true),
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                              itemCount: _rows.length + (_rows.length < _total ? 1 : 0),
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (BuildContext ctx, int i) {
                                if (i >= _rows.length) {
                                  return GhostButton(i18n.t('movements', 'load_more'), onPressed: () => _load());
                                }
                                final StockMovementRow r = _rows[i];
                                final isIn = r.quantity > 0;
                                return AppCard(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Row(
                                        children: <Widget>[
                                          Expanded(
                                            child: Text(r.productName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: isIn ? AppColors.successBg : AppColors.warningBg,
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              '${isIn ? '+' : ''}${Fmt.number(r.quantity)} ${r.unit}',
                                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: isIn ? AppColors.successFg : AppColors.warningFg),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${i18n.t('movements', _typeKey(r.movementType))} · ${Fmt.dateTime(r.createdAt, locale: i18n.locale)}',
                                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.55)),
                                      ),
                                      if (r.batchNumber != null && r.batchNumber!.isNotEmpty)
                                        Text('${i18n.t('movements', 'th_batch')}: ${r.batchNumber}',
                                            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  String _typeKey(String type) {
    for (final (String v, String key) in _types) {
      if (v == type) return key;
    }
    return 'type_adjustment';
  }
}

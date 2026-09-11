import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// التقارير — صفحة الويب نفسها: تقرير مبيعات (KPIs + رسم يومي + الأكثر
/// بيعًا)، تقرير مخزون (قيم + نواقص + صلاحيات)، تقرير حركات (ملخص بالنوع)،
/// مع فترات جاهزة ومخصصة.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final state = context.watch<AppState>();
    final reports = <({IconData icon, String title, String desc, WidgetBuilder builder})>[
      if (state.can('reports.sales'))
        (
          icon: Icons.trending_up,
          title: i18n.t('reports', 'sales_title'),
          desc: i18n.t('reports', 'sales_desc'),
          builder: (_) => const SalesReportScreen(),
        ),
      if (state.can('reports.inventory'))
        (
          icon: Icons.inventory_2_outlined,
          title: i18n.t('reports', 'inventory_title'),
          desc: i18n.t('reports', 'inventory_desc'),
          builder: (_) => const InventoryReportScreen(),
        ),
      if (state.can('reports.movements'))
        (
          icon: Icons.swap_horiz,
          title: i18n.t('reports', 'movements_title'),
          desc: i18n.t('reports', 'movements_desc'),
          builder: (_) => const MovementsReportScreen(),
        ),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('reports', 'title'))),
      body: reports.isEmpty
          ? EmptyState(i18n.t('reports', 'empty'), icon: Icons.bar_chart_outlined)
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: reports.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (BuildContext ctx, int i) => AppCard(
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: reports[i].builder)),
                child: Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(reports[i].icon, size: 22, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(reports[i].title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(reports[i].desc, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: theme.colorScheme.onSurface.withOpacity(0.35)),
                  ],
                ),
              ),
            ),
    );
  }
}

// ------------------------------------------------------------ أداة الفترة

class _PeriodPicker extends StatefulWidget {
  final ValueChanged<({String? from, String? to})> onApply;
  const _PeriodPicker({required this.onApply});
  @override
  State<_PeriodPicker> createState() => _PeriodPickerState();
}

class _PeriodPickerState extends State<_PeriodPicker> {
  String _preset = 'last7';
  DateTime? _customFrom;
  DateTime? _customTo;

  ({String? from, String? to}) _range() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_preset) {
      case 'today':
        return (from: Fmt.isoDay(today), to: Fmt.isoDay(today));
      case 'yesterday':
        final y = today.subtract(const Duration(days: 1));
        return (from: Fmt.isoDay(y), to: Fmt.isoDay(y));
      case 'last7':
        return (from: Fmt.isoDay(today.subtract(const Duration(days: 6))), to: Fmt.isoDay(today));
      case 'last30':
        return (from: Fmt.isoDay(today.subtract(const Duration(days: 29))), to: Fmt.isoDay(today));
      case 'this_month':
        return (from: Fmt.isoDay(DateTime(today.year, today.month, 1)), to: Fmt.isoDay(today));
      case 'last_month':
        final first = DateTime(today.year, today.month, 1);
        return (from: Fmt.isoDay(first.subtract(const Duration(days: 1))), to: Fmt.isoDay(first.subtract(const Duration(days: 1))));
      default:
        return (
          from: _customFrom == null ? null : Fmt.isoDay(_customFrom!),
          to: _customTo == null ? null : Fmt.isoDay(_customTo!),
        );
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: Locale(AppI18n.instance.locale),
    );
    if (picked == null) return;
    setState(() {
      _preset = 'custom';
      if (isFrom) {
        _customFrom = picked;
      } else {
        _customTo = picked;
      }
    });
    final r = _range();
    widget.onApply(r);
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final presets = <(String, String)>[
      ('today', 'preset_today'),
      ('yesterday', 'preset_yesterday'),
      ('last7', 'preset_last7'),
      ('last30', 'preset_last30'),
      ('this_month', 'preset_this_month'),
      ('last_month', 'preset_last_month'),
      ('custom', 'preset_custom'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final (String v, String key) in presets)
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  setState(() => _preset = v);
                  widget.onApply(_range());
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _preset == v ? Theme.of(context).colorScheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _preset == v ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor),
                  ),
                  child: Text(i18n.t('reports', key), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                      color: _preset == v ? Theme.of(context).colorScheme.onPrimary : null)),
                ),
              ),
          ],
        ),
        if (_preset == 'custom') ...<Widget>[
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDate(isFrom: true),
                  child: Text(_customFrom == null ? i18n.t('reports', 'from_date') : Fmt.date(Fmt.isoDay(_customFrom!), locale: i18n.locale), style: const TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDate(isFrom: false),
                  child: Text(_customTo == null ? i18n.t('reports', 'to_date') : Fmt.date(Fmt.isoDay(_customTo!), locale: i18n.locale), style: const TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------ مبيعات

class SalesReportScreen extends StatefulWidget {
  const SalesReportScreen({super.key});
  @override
  State<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends State<SalesReportScreen> {
  SalesReport? _report;
  String? _from;
  String? _to;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = (DateTime.now(), DateTime.now());
    _from = Fmt.isoDay(r.$1.subtract(const Duration(days: 6)));
    _to = Fmt.isoDay(r.$2);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final i18n = AppI18n.instance;
    try {
      final r = await ApiClient.instance.salesReport(from: _from, to: _to);
      if (!mounted) return;
      setState(() {
        _report = r;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('reports', 'error_load_sales'));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = i18n.t('reports', 'error_load_sales');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final r = _report;
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('reports', 'sales_title'))),
      body: _loading
          ? const LoadingBox()
          : _error != null
              ? ErrorRetry(_error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    _PeriodPicker(onApply: (({String? from, String? to}) range) {
                      _from = range.from;
                      _to = range.to;
                      _load();
                    }),
                    const SizedBox(height: 14),
                    if (r == null)
                      EmptyState(i18n.t('reports', 'no_sales_in_period'))
                    else ...<Widget>[
                      AppCard(
                        child: Column(
                          children: <Widget>[
                            KVRow(i18n.t('reports', 'kpi_gross_sales'), Fmt.money(r.grossPiastres, locale: i18n.locale), money: true),
                            KVRow(i18n.t('reports', 'hint_invoices', {'count': Fmt.number(r.invoicesCount)}), ''),
                            KVRow(i18n.t('reports', 'kpi_returns'), Fmt.money(r.returnedPiastres, locale: i18n.locale), money: true),
                            KVRow(i18n.t('reports', 'kpi_net_sales'), Fmt.money(r.netPiastres, locale: i18n.locale), money: true),
                            KVRow(i18n.t('reports', 'kpi_units_sold'), Fmt.number(r.unitsBase)),
                            KVRow(i18n.t('reports', 'kpi_avg_invoice'), Fmt.money(r.avgInvoicePiastres, locale: i18n.locale), money: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            CardTitle(i18n.t('reports', 'daily_net_sales')),
                            const SizedBox(height: 12),
                            if (r.daily.isEmpty)
                              Text(i18n.t('reports', 'no_chart_data'), style: const TextStyle(fontSize: 12))
                            else
                              MiniBarChart(
                                points: <({String label, int value})>[
                                  for (final p in r.daily.take(14)) (label: p.day.substring(5), value: p.net),
                                ],
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            CardTitle(i18n.t('reports', 'top_products')),
                            const SizedBox(height: 10),
                            if (r.topProducts.isEmpty)
                              Text(i18n.t('reports', 'no_sales_in_period'), style: const TextStyle(fontSize: 12))
                            else
                              for (final p in r.topProducts.take(10))
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: <Widget>[
                                      Expanded(child: Text('${p.name} ${p.genericName}', style: const TextStyle(fontSize: 13))),
                                      Text('${Fmt.number(p.qtyBase)} · ${Fmt.money(p.amount, locale: i18n.locale)}',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }
}

// ------------------------------------------------------------ مخزون

class InventoryReportScreen extends StatefulWidget {
  const InventoryReportScreen({super.key});
  @override
  State<InventoryReportScreen> createState() => _InventoryReportScreenState();
}

class _InventoryReportScreenState extends State<InventoryReportScreen> {
  InventoryReport? _report;
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
      final r = await ApiClient.instance.inventoryReport();
      if (!mounted) return;
      setState(() {
        _report = r;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('reports', 'error_load_inventory'));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = i18n.t('reports', 'error_load_inventory');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final r = _report;
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('reports', 'inventory_title'))),
      body: _loading
          ? const LoadingBox()
          : _error != null
              ? ErrorRetry(_error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    if (r == null) const SizedBox.shrink() else ...<Widget>[
                      AppCard(
                        child: Column(
                          children: <Widget>[
                            KVRow(i18n.t('reports', 'kpi_cost_value'), Fmt.money(r.costValue, locale: i18n.locale), money: true),
                            KVRow(i18n.t('reports', 'hint_batches_products', {'batches': Fmt.number(r.batchesCount), 'products': Fmt.number(r.productsCount)}), ''),
                            KVRow(i18n.t('reports', 'kpi_retail_value'), Fmt.money(r.retailValue, locale: i18n.locale), money: true),
                            KVRow(i18n.t('reports', 'hint_units_base', {'count': Fmt.number(r.unitsBase)}), ''),
                            KVRow(i18n.t('reports', 'kpi_low_items'), Fmt.number(r.lowStockCount)),
                            KVRow(i18n.t('reports', 'kpi_out_items'), Fmt.number(r.outOfStockCount)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            CardTitle(i18n.t('reports', 'expiry_section')),
                            const SizedBox(height: 8),
                            KVRow(i18n.t('reports', 'expiry_expired'), '${Fmt.number(r.expiredCount)} · ${Fmt.money(r.expiredValue, locale: i18n.locale)}', money: true),
                            KVRow(i18n.t('reports', 'expiry_30'), Fmt.number(r.expiring30)),
                            KVRow(i18n.t('reports', 'expiry_31_60'), Fmt.number(r.expiring60)),
                            KVRow(i18n.t('reports', 'expiry_61_90'), Fmt.number(r.expiring90)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            CardTitle(i18n.t('reports', 'low_stock_list')),
                            const SizedBox(height: 8),
                            if (r.lowStockItems.isEmpty)
                              Text(i18n.t('reports', 'no_low_stock_items'), style: const TextStyle(fontSize: 12))
                            else
                              for (final it in r.lowStockItems.take(20))
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: <Widget>[
                                      Expanded(child: Text('${it.name} ${it.genericName}', style: const TextStyle(fontSize: 13))),
                                      AppBadge(Fmt.number(it.quantity), tone: AppBadge.stockStatus(it.status)),
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
                            CardTitle(i18n.t('reports', 'expiry_list')),
                            const SizedBox(height: 8),
                            if (r.expiringItems.isEmpty)
                              Text(i18n.t('reports', 'no_expiring_items'), style: const TextStyle(fontSize: 12))
                            else
                              for (final it in r.expiringItems.take(20))
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text('${it.name} · ${it.batchNumber}',
                                            style: const TextStyle(fontSize: 13)),
                                      ),
                                      Text(it.extraDate == null ? '—' : Fmt.date(it.extraDate, locale: i18n.locale),
                                          style: TextStyle(fontSize: 12, color: AppColors.warningFg, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }
}

// ------------------------------------------------------------ حركات

class MovementsReportScreen extends StatefulWidget {
  const MovementsReportScreen({super.key});
  @override
  State<MovementsReportScreen> createState() => _MovementsReportScreenState();
}

class _MovementsReportScreenState extends State<MovementsReportScreen> {
  MovementsReport? _report;
  String? _from;
  String? _to;
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
    final now = DateTime.now();
    _from = Fmt.isoDay(now.subtract(const Duration(days: 6)));
    _to = Fmt.isoDay(now);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final i18n = AppI18n.instance;
    try {
      final r = await ApiClient.instance.movementsReport(from: _from, to: _to);
      if (!mounted) return;
      setState(() {
        _report = r;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.error(e.code, i18n.t('reports', 'error_load_movements'));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = i18n.t('reports', 'error_load_movements');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final r = _report;
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('reports', 'movements_title'))),
      body: _loading
          ? const LoadingBox()
          : _error != null
              ? ErrorRetry(_error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    _PeriodPicker(onApply: (({String? from, String? to}) range) {
                      _from = range.from;
                      _to = range.to;
                      _load();
                    }),
                    const SizedBox(height: 14),
                    if (r == null)
                      EmptyState(i18n.t('reports', 'no_movements_in_period'))
                    else ...<Widget>[
                      AppCard(
                        child: Column(
                          children: <Widget>[
                            KVRow(i18n.t('reports', 'kpi_transactions'), Fmt.number(r.transactions)),
                            KVRow(i18n.t('reports', 'kpi_total_in'), Fmt.number(r.quantityIn)),
                            KVRow(i18n.t('reports', 'kpi_total_out'), Fmt.number(r.quantityOut)),
                            KVRow(i18n.t('reports', 'kpi_net_change'), Fmt.number(r.quantityIn - r.quantityOut)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            CardTitle(i18n.t('reports', 'summary_by_type')),
                            const SizedBox(height: 8),
                            if (r.byType.isEmpty)
                              Text(i18n.t('reports', 'no_movements_in_period'), style: const TextStyle(fontSize: 12))
                            else
                              for (final row in r.byType)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(
                                          i18n.t('reports', _typeKey(row.type)),
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                      Text('${Fmt.number(row.tx)} · +${Fmt.number(row.qtyIn)} / -${Fmt.number(row.qtyOut)}',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ],
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

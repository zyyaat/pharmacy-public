import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';
import 'movements_screen.dart';
import 'product_form_screen.dart';
import 'pos_screen.dart';
import 'reports_screen.dart';

/// لوحة التحكم — نفس بنية صفحة الويب: 4 بطاقات إحصائية بنغماتها،
/// الإجراءات السريعة، حالة المخزون (النواقص)، وسجل النشاط.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardStats? _stats;
  List<ActivityItem> _activity = <ActivityItem>[];
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
      final stats = await ApiClient.instance.dashboardStats();
      List<ActivityItem> activity = <ActivityItem>[];
      try {
        activity = await ApiClient.instance.dashboardActivity();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _activity = activity;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.isNetwork ? i18n.error(e.code) : i18n.t('dashboard', 'error_load');
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppI18n.instance.t('dashboard', 'error_load');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final state = context.watch<AppState>();
    if (_loading) return const LoadingBox();
    if (_error != null) return ErrorRetry(_error!, onRetry: _load);
    final stats = _stats;
    if (stats == null) {
      return ErrorRetry(i18n.t('dashboard', 'error_load'), onRetry: _load);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(i18n.t('dashboard', 'title'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(i18n.t('dashboard', 'subtitle'),
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55))),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (BuildContext ctx, BoxConstraints c) {
            final cross = c.maxWidth > 520 ? 2 : 1;
            return GridView.count(
              crossAxisCount: cross,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: cross == 2 ? 2.6 : 3.4,
              children: <Widget>[
                StatCard(
                  label: i18n.t('dashboard', 'total_products'),
                  value: Fmt.number(stats.totalProducts),
                  icon: Icons.medication_outlined,
                  tone: StatTone.primary,
                ),
                StatCard(
                  label: i18n.t('dashboard', 'low_stock_products'),
                  value: Fmt.number(stats.lowStockCount),
                  icon: Icons.warning_amber_outlined,
                  tone: StatTone.warning,
                ),
                StatCard(
                  label: i18n.t('dashboard', 'sales_units_today'),
                  value: Fmt.number(stats.salesUnitsToday),
                  icon: Icons.trending_up,
                  tone: StatTone.success,
                ),
                StatCard(
                  label: i18n.t('dashboard', 'attendance_today'),
                  value: '${Fmt.number(stats.activeToday)} / ${Fmt.number(stats.activeEmployees)}',
                  icon: Icons.group_outlined,
                  tone: StatTone.info,
                ),
              ],
            );
          }),
          const SizedBox(height: 16),
          _QuickActions(state: state),
          const SizedBox(height: 16),
          _LowStockCard(items: stats.lowStockItems),
          const SizedBox(height: 16),
          if (_activity.isNotEmpty) _ActivityCard(items: _activity),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final AppState state;
  const _QuickActions({required this.state});

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final actions = <({IconData icon, String label, WidgetBuilder builder})>[
      if (state.can('inventory.manage_products') || state.can('inventory.import') || state.permissions?.fullAccess == true)
        (
          icon: Icons.add_circle_outline,
          label: i18n.t('dashboard', 'add_product'),
          builder: (_) => const ProductFormScreen(),
        ),
      if (state.can('pos.access'))
        (
          icon: Icons.receipt_long_outlined,
          label: i18n.t('nav', 'pos'),
          builder: (_) => const POSScreen(),
        ),
      if (state.can('inventory.movements.view'))
        (
          icon: Icons.swap_horiz,
          label: i18n.t('dashboard', 'nav_inventory'),
          builder: (_) => const MovementsScreen(),
        ),
      if (state.canAny(<String>['reports.sales', 'reports.inventory', 'reports.movements']))
        (
          icon: Icons.bar_chart_outlined,
          label: i18n.t('dashboard', 'nav_reports'),
          builder: (_) => const ReportsScreen(),
        ),
    ];
    if (actions.isEmpty) {
      return AppCard(child: Text(i18n.t('dashboard', 'no_quick_actions'), style: const TextStyle(fontSize: 13)));
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CardTitle(i18n.t('dashboard', 'quick_actions')),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (final action in actions)
                ActionChip(
                  avatar: Icon(action.icon, size: 18, color: Theme.of(context).colorScheme.primary),
                  label: Text(action.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  backgroundColor: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.darkAccent
                      : AppColors.lightAccent,
                  side: BorderSide.none,
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: action.builder)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LowStockCard extends StatelessWidget {
  final List<DashboardLowStock> items;
  const _LowStockCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CardTitle(
            i18n.t('dashboard', 'inventory_status'),
            subtitle: i18n.t('dashboard', 'inventory_status_desc'),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(i18n.t('dashboard', 'no_low_stock'),
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
              ),
            )
          else
            for (final item in items) ...<Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(item.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          i18n.t('dashboard', 'reorder_note', {'min': Fmt.number(item.minStockLevel)}),
                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AppBadge(
                    item.strips > 0
                        ? '${Fmt.number(item.quantity)} + ${Fmt.number(item.strips)}'
                        : Fmt.number(item.quantity),
                    tone: AppBadge.stockStatus(item.status),
                  ),
                ],
              ),
              if (item != items.last) const Divider(height: 20),
            ],
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final List<ActivityItem> items;
  const _ActivityCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const CardTitle('النشاط الأخير'),
          const SizedBox(height: 12),
          for (final item in items) ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(item.description, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(
                        '${item.userName} · ${Fmt.dateTime(item.timestamp, locale: AppI18n.instance.locale)}',
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (item != items.last) const Divider(height: 18),
          ],
        ],
      ),
    );
  }
}

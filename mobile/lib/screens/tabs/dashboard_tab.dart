import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/ui.dart';

/// بطاقات إحصاءات اللوحة (GET /pharmacy/dashboard/stats — مفاتيح camelCase)
/// مع قائمة الأصناف شبه النافدة.
class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab>
    with AutomaticKeepAliveClientMixin {
  Future<DashboardStats>? _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = ApiClient.instance.dashboardStats();
  }

  Future<void> _reload() async {
    setState(() => _future = ApiClient.instance.dashboardStats());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _reload,
      color: kBrandSeed,
      child: FutureBuilder<DashboardStats>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 60),
                ErrorBox(message: friendlyError(context, snap.error!)),
                const SizedBox(height: 14),
                Center(
                  child: TextButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(context.tr('retry')),
                  ),
                ),
              ],
            );
          }
          final s = snap.data!;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.35,
                children: [
                  StatCard(
                    icon: Icons.medication_rounded,
                    label: context.tr('stat_products'),
                    value: '${s.totalProducts}',
                    tint: kBrandSeed,
                  ),
                  StatCard(
                    icon: Icons.warning_amber_rounded,
                    label: context.tr('stat_low_stock'),
                    value: '${s.lowStockCount}',
                    tint: const Color(0xFFF59E0B),
                  ),
                  StatCard(
                    icon: Icons.badge_outlined,
                    label: context.tr('stat_active_employees'),
                    value: '${s.activeEmployees}',
                    tint: const Color(0xFF8B5CF6),
                  ),
                  StatCard(
                    icon: Icons.event_available_rounded,
                    label: context.tr('stat_active_today'),
                    value: '${s.activeToday}',
                    tint: const Color(0xFF10B981),
                  ),
                  StatCard(
                    icon: Icons.shopping_bag_outlined,
                    label: context.tr('stat_sales_today'),
                    value: '${s.salesUnitsToday}',
                    tint: const Color(0xFF0EA5E9),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                context.tr('low_stock_title'),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (s.lowStockItems.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    context.tr('low_stock_empty'),
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Theme.of(context).colorScheme.outline),
                  ),
                )
              else
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      for (final item in s.lowStockItems.take(5))
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.water_drop_outlined,
                              color: Color(0xFFF59E0B), size: 20),
                          title: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: item.genericName.isEmpty
                              ? null
                              : Text(item.genericName,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Text(
                            '${item.quantity} ${context.tr('units')}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

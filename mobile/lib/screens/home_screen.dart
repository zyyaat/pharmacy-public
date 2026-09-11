import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/strings.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';
import 'dashboard_screen.dart';
import 'inventory_screen.dart';
import 'movements_screen.dart';
import 'pos_screen.dart';
import 'sales_list_screen.dart';

/// Task 61 — هيكل التطبيق الرئيسي: شريط سفلي بخمسة أقسام (مثل عمود الويب
/// الرئيسي) + قائمة «المزيد» تغطي بقية صفحات الويب بترتيب الشريط الجانبي
/// نفسه، مع بوابة الصلاحيات نفسها.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final i18n = AppI18n.instance;
    final nav = <({IconData icon, String label, bool allowed, WidgetBuilder builder})>[
      (
        icon: Icons.space_dashboard_outlined,
        label: i18n.t('nav', 'dashboard'),
        allowed: true,
        builder: (_) => const DashboardScreen(),
      ),
      (
        icon: Icons.receipt_long_outlined,
        label: i18n.t('nav', 'pos'),
        allowed: state.can('pos.access'),
        builder: (_) => const POSScreen(),
      ),
      (
        icon: Icons.medication_outlined,
        label: i18n.t('nav', 'inventory'),
        allowed: state.can('inventory.view'),
        builder: (_) => const InventoryScreen(),
      ),
      (
        icon: Icons.history,
        label: i18n.t('nav', 'sales'),
        allowed: state.can('sales.view'),
        builder: (_) => const SalesListScreen(),
      ),
      (
        icon: Icons.menu,
        label: i18n.t('nav', 'settings'),
        allowed: true,
        builder: (_) => const MoreScreen(onChanged: null),
      ),
    ];
    final current = nav[_index];

    return Scaffold(
      appBar: _ShellAppBar(title: current.label),
      body: IndexedStack(index: _index, children: <Widget>[
        for (final (i, tab) in nav.indexed)
          tab.allowed
              ? tab.builder(context)
              : NoAccessScreen(
                  key: ValueKey('na_$i'),
                  title: tab.label,
                ),
      ]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (int i) => setState(() => _index = i),
        items: <BottomNavigationBarItem>[
          for (final tab in nav)
            BottomNavigationBarItem(icon: Icon(tab.icon), label: tab.label),
        ],
      ),
    );
  }
}

class _ShellAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  const _ShellAppBar({required this.title});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final i18n = AppI18n.instance;
    final ctx = state.context;
    final subtitle = ctx == null
        ? i18n.t('nav', 'loading_pharmacy')
        : ctx.branchName == null || ctx.branchName!.isEmpty
            ? ctx.pharmacyName
            : '${ctx.pharmacyName} · ${ctx.branchName}';
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(subtitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55))),
        ],
      ),
      actions: <Widget>[
        IconButton(
          tooltip: i18n.t('nav', 'change_language'),
          onPressed: () async {
            final next = state.locale == 'ar' ? 'en' : 'ar';
            await context.read<AppState>().setLocale(next);
          },
          icon: const Icon(Icons.translate, size: 20),
        ),
        IconButton(
          tooltip: i18n.t('nav', 'logout'),
          onPressed: () async {
            await context.read<AppState>().logout();
            if (context.mounted) {
              Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/login', (_) => false);
            }
          },
          icon: const Icon(Icons.logout, size: 20),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// قائمة «المزيد»: بقية صفحات الويب بترتيب الشريط الجانبي + الإعدادات
class MoreScreen extends StatelessWidget {
  final VoidCallback? onChanged;
  const MoreScreen({super.key, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final i18n = AppI18n.instance;
    final items = <_MoreItem>[
      _MoreItem(
        icon: Icons.note_alt_outlined,
        label: i18n.t('nav', 'customers'),
        allowed: state.can('customers.view'),
        route: '/customers',
      ),
      _MoreItem(
        icon: Icons.swap_horiz,
        label: i18n.t('nav', 'movements'),
        allowed: state.can('inventory.movements.view'),
        builder: (_) => const MovementsScreen(),
      ),
      _MoreItem(
        icon: Icons.group_outlined,
        label: i18n.t('nav', 'employees'),
        allowed: state.can('employees.view'),
        route: '/employees',
      ),
      _MoreItem(
        icon: Icons.event_available_outlined,
        label: i18n.t('nav', 'attendance'),
        allowed: state.can('attendance.view'),
        route: '/attendance',
      ),
      _MoreItem(
        icon: Icons.storefront_outlined,
        label: i18n.t('nav', 'branches'),
        allowed: state.can('branches.view'),
        route: '/branches',
      ),
      _MoreItem(
        icon: Icons.bar_chart_outlined,
        label: i18n.t('nav', 'reports'),
        allowed: state.canAny(<String>['reports.sales', 'reports.inventory', 'reports.movements']),
        route: '/reports',
      ),
      _MoreItem(
        icon: Icons.settings_outlined,
        label: i18n.t('nav', 'settings'),
        allowed: true,
        route: '/settings',
      ),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _UserCard(),
        const SizedBox(height: 16),
        for (final item in items)
          if (item.allowed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                onTap: () {
                  if (item.route != null) {
                    Navigator.of(context).pushNamed(item.route!);
                  } else if (item.builder != null) {
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: item.builder!));
                  }
                },
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Row(
                  children: <Widget>[
                    Icon(item.icon, size: 22, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(child: Text(item.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                    Icon(Icons.chevron_right, size: 20, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.35)),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            i18n.t('reports', 'brand_tagline'),
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4)),
          ),
        ),
      ],
    );
  }
}

class _MoreItem {
  final IconData icon;
  final String label;
  final bool allowed;
  final String? route;
  final WidgetBuilder? builder;
  const _MoreItem({required this.icon, required this.label, required this.allowed, this.route, this.builder});
}

class _UserCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final i18n = AppI18n.instance;
    final user = state.user;
    final ctx = state.context;
    final name = user?.displayName.isNotEmpty == true ? user!.displayName : i18n.t('nav', 'user_fallback');
    final role = ctx?.user.role ?? '';
    return AppCard(
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 22,
            backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.12),
            child: Text(
              name.isNotEmpty ? name.characters.first.toUpperCase() : 'م',
              style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  user?.email ?? '',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55)),
                ),
              ],
            ),
          ),
          if (role.isNotEmpty) AppBadge(role, tone: BadgeTone.primary),
        ],
      ),
    );
  }
}

/// شاشة «غير متاح لحسابك» — مثل no_access في الويب
class NoAccessScreen extends StatelessWidget {
  final String title;
  const NoAccessScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.lock_outline, size: 44, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3)),
            const SizedBox(height: 14),
            Text(i18n.t('common', 'no_access_title'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(i18n.t('common', 'no_access_body'), style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55)), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(title, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4))),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/offline.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';
import 'attendance_screen.dart';
import 'branches_screen.dart';
import 'customers_screen.dart';
import 'dashboard_screen.dart';
import 'employees_screen.dart';
import 'inventory_screen.dart';
import 'movements_screen.dart';
import 'pos_screen.dart';
import 'reports_screen.dart';
import 'sales_list_screen.dart';
import 'settings_screen.dart';

/// Task 62 — هيكل التطبيق بنسخة الويب حرفيًا: قائمة جانبية Drawer (شعار
/// العلامة، صندوق «الصيدلية الحالية» bg-primary/10، عناصر القائمة بمؤشر
/// نشط شريطي وعارض عدّاد المخزون، قسم إعدادات بفاصل، تذييل مستخدم مع
/// تسجيل خروج) + رأس h-16 (همبرغر، بحث، لغة، ثيم، جرس إشعارات بشارة
/// حمراء ولوحة منسدلة: ديون العملاء + نواقص المخزون).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeShellState();
}

/// حالة الهيكل مكشوفة ليتسنّى لبطاقات الإجراءات السريعة تنشيط صفحة
/// بالمعرّف نفسه (مثل تغيير المسار في الويب).
class HomeShellState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _active = 'dashboard';
  List<LowStockItem> _lowStock = <LowStockItem>[];
  List<Customer> _debts = <Customer>[];
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _refreshAlerts();
    // نفس دورية الويب: تحديث الإشعارات كل دقيقة حتى يتخذ الصيدلي إجراءً
    _pollTimer = Timer.periodic(const Duration(minutes: 1), (_) => _refreshAlerts());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshAlerts() async {
    final state = context.read<AppState>();
    try {
      if (state.can('inventory.view')) {
        final items = await ApiClient.instance.lowStock();
        if (mounted) setState(() => _lowStock = items);
      }
    } catch (_) {}
    try {
      if (state.can('customers.view')) {
        final debts = await ApiClient.instance.customers(debtsOnly: true);
        if (mounted) setState(() => _debts = debts.where((Customer c) => c.balancePiastres > 0).toList());
      }
    } catch (_) {}
  }

  void goTo(String key) {
    setState(() => _active = key);
    _refreshAlerts();
  }

  void _openDrawer() {
    // بمفتاح Scaffold لا نعتمد على Scaffold.of الذي يرمي لو مُرِّر سياق
    // أعلى من الـ Scaffold نفسه (كان يُفشل الضغط على القائمة صامتًا في release).
    _scaffoldKey.currentState?.openDrawer();
  }

  /// ترتيب هبوط الويب LANDING_PRIORITY (permissions.ts) — أول صفحة مسموحة
  /// تُستخدم للتحويل الصامت عند منع الصفحة النشطة (dashboard.view...).
  static const List<String> _landingPriority = <String>[
    'pos', 'inventory', 'sales', 'customers', 'movements',
    'reports', 'employees', 'attendance', 'branches',
  ];

  ShellPage? _firstAllowedPage(List<ShellPage> pages) {
    for (final String key in _landingPriority) {
      for (final ShellPage p in pages) {
        if (p.key == key && p.allowed) return p;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final i18n = AppI18n.instance;
    final pages = _pages(state, i18n);
    // Task 68-a — مثل RequirePermission في الويب: صفحة نشطة ممنوعة تُستبدل
    // بأول صفحة مسموحة بترتيب LANDING_PRIORITY؛ وبلا أي صفحة تظل شاشة
    // «غير متاح» الحالية معروضة (pages.first ببوابة allowed=false).
    ShellPage current = pages.firstWhere(
      (ShellPage p) => p.key == _active,
      orElse: () => pages.first,
    );
    if (!current.allowed) {
      current = _firstAllowedPage(pages) ?? pages.first;
    }
    return Scaffold(
      key: _scaffoldKey,
      drawer: _SidebarDrawer(active: current.key, onSelect: (String key) => goTo(key)),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _HeaderBar(
              onMenu: _openDrawer,
              onAlertsChanged: _refreshAlerts,
              alertCount: (state.can('inventory.view') ? _lowStock.length : 0) +
                  (state.can('customers.view') ? _debts.length : 0),
              lowStock: state.can('inventory.view') ? _lowStock : const <LowStockItem>[],
              debts: state.can('customers.view') ? _debts : const <Customer>[],
            ),
            // Task 82 — شريط «لا يوجد اتصال» أسفل الرأس مباشرة: يظهر حين تكون
            // الصفحات تعرض الكاش المحلي (إشارة نتائج API + مراقب الواجهات)
            ValueListenableBuilder<bool>(
              valueListenable: NetworkSignal.offline,
              builder: (BuildContext context, bool offline, _) => offline
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: OfflineBanner(
                        title: i18n.t('common', 'offline_banner_title'),
                        hint: i18n.t('common', 'offline_banner_hint'),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: IndexedStack(
                index: pages.indexOf(current),
                children: <Widget>[
                  for (final ShellPage p in pages)
                    p.allowed
                        ? (p.builder != null
                            ? p.builder!(context)
                            : NoAccessScreen(key: ValueKey<String>('na_${p.key}'), title: p.label))
                        : NoAccessScreen(key: ValueKey<String>('na_${p.key}'), title: p.label),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<ShellPage> _pages(AppState state, AppI18n i18n) {
    return <ShellPage>[
      ShellPage(
        key: 'dashboard',
        icon: Icons.space_dashboard_outlined,
        label: i18n.t('nav', 'dashboard'),
        allowed: state.can('dashboard.view'), // بوابة الويب RequirePermission 'dashboard.view'
        builder: (_) => const DashboardScreen(),
      ),
      ShellPage(
        key: 'inventory',
        icon: Icons.inventory_2_outlined,
        label: i18n.t('nav', 'inventory'),
        allowed: state.can('inventory.view'),
        builder: (_) => const InventoryScreen(),
      ),
      ShellPage(
        key: 'pos',
        icon: Icons.receipt_long_outlined,
        label: i18n.t('nav', 'pos'),
        allowed: state.can('pos.access'),
        builder: (_) => const POSScreen(),
      ),
      ShellPage(
        key: 'sales',
        icon: Icons.history,
        label: i18n.t('nav', 'sales'),
        allowed: state.can('sales.view'),
        builder: (_) => const SalesListScreen(),
      ),
      ShellPage(
        key: 'customers',
        icon: Icons.note_alt_outlined,
        label: i18n.t('nav', 'customers'),
        allowed: state.can('customers.view'),
        builder: (_) => const CustomersScreen(),
      ),
      ShellPage(
        key: 'movements',
        icon: Icons.swap_horiz,
        label: i18n.t('nav', 'movements'),
        allowed: state.can('inventory.movements.view'),
        builder: (_) => const MovementsScreen(),
      ),
      ShellPage(
        key: 'employees',
        icon: Icons.group_outlined,
        label: i18n.t('nav', 'employees'),
        allowed: state.can('employees.view'),
        builder: (_) => const EmployeesScreen(),
      ),
      ShellPage(
        key: 'attendance',
        icon: Icons.event_available_outlined,
        label: i18n.t('nav', 'attendance'),
        allowed: state.can('attendance.view'),
        builder: (_) => const AttendanceScreen(),
      ),
      ShellPage(
        key: 'branches',
        icon: Icons.storefront_outlined,
        label: i18n.t('nav', 'branches'),
        allowed: state.can('branches.view'),
        builder: (_) => const BranchesScreen(),
      ),
      ShellPage(
        key: 'reports',
        icon: Icons.bar_chart_outlined,
        label: i18n.t('nav', 'reports'),
        allowed: state.canAny(<String>['reports.sales', 'reports.inventory', 'reports.movements', 'reports.financial', 'reports.employees']),
        builder: (_) => const ReportsScreen(),
      ),
      ShellPage(
        key: 'settings',
        icon: Icons.settings_outlined,
        label: i18n.t('nav', 'settings'),
        // sidebar.tsx: الرابط يختفي كليًا عمن لا يملك أي قسم إعدادات
        allowed: state.canAny(<String>[
          'settings.general',
          'settings.billing',
          'settings.integrations',
          'settings.receipts',
          'inventory.import',
        ]),
        builder: (_) => const SettingsScreen(),
      ),
    ];
  }
}

/// صفحة داخل الشل
class ShellPage {
  final String key;
  final IconData icon;
  final String label;
  final bool allowed;
  final WidgetBuilder? builder;
  const ShellPage({required this.key, required this.icon, required this.label, required this.allowed, this.builder});
}

/// جسر التنقّل: أي شاشة داخل الشل تستطيع تنشيط صفحة أخرى بالمعرّف
class HomeNav {
  static void go(BuildContext context, String key) {
    final HomeShellState? shell = context.findAncestorStateOfType<HomeShellState>();
    if (shell != null) {
      shell.goTo(key);
    }
  }
}

// ---------------------------------------------------------------- القائمة الجانبية

/// Sidebar في الويب: w-[260px] bg-card border-e، رأس شعار h-16، صندوق
/// الصيدلية، عناصر القائمة (مؤشر نشط start-0 h-8 w-1 rounded-e-full)،
/// قسم إعدادات بفاصل، تذييل المستخدم مع تسجيل الخروج.
class _SidebarDrawer extends StatelessWidget {
  final String active;
  final ValueChanged<String> onSelect;
  const _SidebarDrawer({required this.active, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final state = context.watch<AppState>();
    final i18n = AppI18n.instance;
    final primary = theme.colorScheme.primary;
    final ctx = state.context;
    final user = state.user;

    // عناصر القائمة بترتيب الويب نفسه (عناصر الشل بدون الإعدادات)
    final items = <(String, IconData, String, bool, int?)>[
      ('dashboard', Icons.space_dashboard_outlined, i18n.t('nav', 'dashboard'), state.can('dashboard.view'), null),
      ('inventory', Icons.inventory_2_outlined, i18n.t('nav', 'inventory'), state.can('inventory.view'), ctx?.productCount),
      ('pos', Icons.receipt_long_outlined, i18n.t('nav', 'pos'), state.can('pos.access'), null),
      ('sales', Icons.history, i18n.t('nav', 'sales'), state.can('sales.view'), null),
      ('customers', Icons.note_alt_outlined, i18n.t('nav', 'customers'), state.can('customers.view'), null),
      ('movements', Icons.swap_horiz, i18n.t('nav', 'movements'), state.can('inventory.movements.view'), null),
      ('employees', Icons.group_outlined, i18n.t('nav', 'employees'), state.can('employees.view'), null),
      ('attendance', Icons.event_available_outlined, i18n.t('nav', 'attendance'), state.can('attendance.view'), null),
      ('branches', Icons.storefront_outlined, i18n.t('nav', 'branches'), state.can('branches.view'), null),
      ('reports', Icons.bar_chart_outlined, i18n.t('nav', 'reports'),
          state.canAny(<String>['reports.sales', 'reports.inventory', 'reports.movements', 'reports.financial', 'reports.employees']), null),
    ];

    final name = user?.displayName.isNotEmpty == true
        ? user!.displayName
        : (user != null && (user.firstName.isNotEmpty || user.lastName.isNotEmpty)
            ? '${user.firstName} ${user.lastName}'.trim()
            : i18n.t('nav', 'user_fallback'));
    final role = ctx?.user.role ?? i18n.t('nav', 'pharmacy_account');

    return Drawer(
      width: 260, // w-[260px]
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // رأس الشعار h-16 border-b
            Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
              alignment: AlignmentDirectional.centerStart,
              // FittedBox: عرض الشعار الفعري قد يفوق عرض الدرج قليلًا — نُصغّر بسلاسة
              child: FittedBox(fit: BoxFit.scaleDown, child: BrandLogo(height: 36, dark: dark)),
            ),

            // صندوق الصيدلية الحالية — bg-primary/10 rounded-lg p-3
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.10),
                  borderRadius: AppRadius.br,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(i18n.t('nav', 'current_pharmacy'),
                        style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                    const SizedBox(height: 4),
                    Text(ctx?.pharmacyName ?? i18n.t('nav', 'loading_pharmacy'),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    // sidebar.tsx: اسم الفرع (· مدينة) → مدينة الصيدلية → no_branch
                    Text(
                      ctx == null
                          ? i18n.t('nav', 'no_branch')
                          : ((ctx.branchName != null && ctx.branchName!.isNotEmpty)
                              ? '${ctx.branchName}${(ctx.branchCity != null && ctx.branchCity!.isNotEmpty) ? ' · ${ctx.branchCity}' : ''}'
                              : (ctx.city.isNotEmpty ? ctx.city : i18n.t('nav', 'no_branch'))),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55)),
                    ),
                  ],
                ),
              ),
            ),

            // عناصر القائمة
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(i18n.t('nav', 'main_section'),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                  ),
                  for (final (String key, IconData icon, String label, bool allowed, int? count) in items)
                    if (allowed)
                      _NavItem(
                        icon: icon,
                        label: label,
                        count: key == 'inventory' ? count : null,
                        active: active == key,
                        primary: primary,
                        onTap: () {
                          Navigator.pop(context); // إغلاق الدرج
                          onSelect(key);
                        },
                      ),
                  // قسم الإعدادات بفاصل علوي — يختفي كليًا (بالفاصل) عمن لا
                  // يملك أي قسم إعدادات (sidebar.tsx settingsAllowed)
                  if (state.canAny(<String>[
                    'settings.general',
                    'settings.billing',
                    'settings.integrations',
                    'settings.receipts',
                    'inventory.import',
                  ])) ...<Widget>[
                    const SizedBox(height: 16),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 12), child: Divider(height: 1, color: theme.dividerColor)),
                    const SizedBox(height: 16),
                    _NavItem(
                      icon: Icons.settings_outlined,
                      label: i18n.t('nav', 'settings'),
                      active: active == 'settings',
                      primary: primary,
                      onTap: () {
                        Navigator.pop(context);
                        onSelect('settings');
                      },
                    ),
                  ],
                ],
              ),
            ),

            // تذييل المستخدم — أفاتار دائري + الاسم + الدور + تسجيل خروج
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.dividerColor))),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.10),
                      shape: BoxShape.circle,
                    ),
                    // الويب: {t('avatar_initial')} — حرف ثابت للهوية لا أول حرف من الاسم
                    child: Text(
                      i18n.t('nav', 'avatar_initial'),
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: primary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                        Text(role, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                      ],
                    ),
                  ),
                  IconButtonGhost(
                    Icons.logout,
                    tooltip: i18n.t('nav', 'logout'),
                    color: theme.colorScheme.onSurface.withOpacity(0.55),
                    onPressed: () async {
                      final navigator = Navigator.of(context, rootNavigator: true);
                      await context.read<AppState>().logout();
                      navigator.pushNamedAndRemoveUntil('/login', (_) => false);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// عنصر قائمة جانبية — rounded-lg px-3 py-2.5 text-sm font-medium مع
/// المؤشر الشريطي النشط وعدّاد المخزون الدائري
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final int? count;
  final Color primary;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.primary,
    required this.onTap,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = active ? primary : theme.colorScheme.onSurface.withOpacity(0.55);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4), // space-y-1
      child: Material(
        color: active ? primary.withOpacity(0.10) : Colors.transparent,
        borderRadius: AppRadius.br,
        child: InkWell(
          borderRadius: AppRadius.br,
          onTap: onTap,
          child: Stack(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), // px-3 py-2.5
                child: Row(
                  children: <Widget>[
                    Icon(icon, size: 20, color: fg),
                    const SizedBox(width: 12),
                    Expanded(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: fg))),
                    if (count != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: active ? primary.withOpacity(0.20) : theme.colorScheme.onSurface.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          Fmt.number(count!),
                          style: TextStyle(
                              fontSize: 12,
                              color: active ? primary : theme.colorScheme.onSurface.withOpacity(0.55)),
                        ),
                      ),
                  ],
                ),
              ),
              // المؤشر النشط: start-0 top-1/2 h-8 w-1 rounded-e-full bg-primary
              if (active)
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Container(
                      width: 4,
                      height: 32,
                      decoration: BoxDecoration(
                        color: primary,
                        borderRadius: BorderRadiusDirectional.horizontal(end: Radius.circular(999)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- الرأس

/// Header في الويب: h-16 border-b bg-background/80 backdrop-blur مع بحث
/// وأزرار اللغة/الثيم/الجرس (بشارة عدد حمراء أعلى-بداية).
class _HeaderBar extends StatelessWidget {
  final VoidCallback onMenu;
  final VoidCallback onAlertsChanged;
  final int alertCount;
  final List<LowStockItem> lowStock;
  final List<Customer> debts;
  const _HeaderBar({
    required this.onMenu,
    required this.onAlertsChanged,
    required this.alertCount,
    required this.lowStock,
    required this.debts,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<AppState>();
    final i18n = AppI18n.instance;
    final dark = theme.brightness == Brightness.dark;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 64, // h-16
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor.withOpacity(0.80), // bg-background/80
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: <Widget>[
              IconButtonGhost(Icons.menu, onPressed: onMenu),
              const SizedBox(width: 8),
              // حقل البحث — مثل الويب
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 448), // max-w-md
                  child: TextField(
                    readOnly: true,
                    onTap: () {},
                    decoration: InputDecoration(
                      hintText: i18n.t('nav', 'search_placeholder'),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      prefixIconColor: theme.colorScheme.onSurface.withOpacity(0.45),
                      isDense: true,
                      filled: true,
                      fillColor: theme.scaffoldBackgroundColor,
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // اللغة
              IconButtonGhost(
                Icons.translate,
                tooltip: i18n.t('nav', 'change_language'),
                onPressed: () async {
                  final next = state.locale == 'ar' ? 'en' : 'ar';
                  await context.read<AppState>().setLocale(next);
                },
              ),
              // الثيم: شمس/قمر مثل الويب
              IconButtonGhost(
                dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                tooltip: dark ? i18n.t('nav', 'light_mode') : i18n.t('nav', 'dark_mode'),
                onPressed: () => context.read<AppState>().toggleTheme(),
              ),
              // الجرس + لوحة الإشعارات
              _NotificationsBell(
                count: alertCount,
                lowStock: lowStock,
                debts: debts,
                onChanged: onAlertsChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// جرس الإشعارات: بشارة عدد destructive، ولوحة منسدلة w-80 بتصميم الويب
class _NotificationsBell extends StatelessWidget {
  final int count;
  final List<LowStockItem> lowStock;
  final List<Customer> debts;
  final VoidCallback onChanged;
  const _NotificationsBell({
    required this.count,
    required this.lowStock,
    required this.debts,
    required this.onChanged,
  });

  Future<void> _openPanel(BuildContext context) async {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final state = context.read<AppState>();
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.2),
      builder: (BuildContext ctx) {
        return Align(
          alignment: AlignmentDirectional.topEnd,
          child: Padding(
            padding: EdgeInsetsDirectional.only(top: 68, end: 12, start: MediaQuery.of(ctx).size.width * 0.15),
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 320), // w-80
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: AppRadius.brXl,
                  border: Border.all(color: theme.dividerColor),
                  boxShadow: WebShadow.lg,
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // رأس اللوحة
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
                      child: Row(
                        children: <Widget>[
                          Expanded(child: Text(i18n.t('nav', 'notifications'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                          Text(
                            count > 0 ? i18n.t('nav', 'alerts_count', {'count': Fmt.number(count)}) : i18n.t('nav', 'no_alerts'),
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55)),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 384), // max-h-96
                        child: SingleChildScrollView(
                          child: count == 0
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 32),
                                  child: Text(i18n.t('nav', 'all_clear'),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    // ديون العملاء
                                    if (debts.isNotEmpty) ...<Widget>[
                                      _sectionLabel(i18n.t('nav', 'customer_debts'), theme),
                                      for (final Customer d in debts)
                                        _row(
                                          theme,
                                          title: d.name,
                                          subtitle: i18n.t('nav', 'debt_owed', {'amount': Fmt.money(d.balancePiastres, locale: i18n.locale)}),
                                          badge: i18n.t('nav', 'debtor_badge'),
                                          badgeFg: theme.brightness == Brightness.dark ? AppColors.warningFgDark : AppColors.warningFg,
                                          badgeBg: const Color(0x1AF59E0B),
                                          onTap: () {
                                            Navigator.pop(ctx);
                                            HomeNav.go(context, 'customers');
                                          },
                                        ),
                                    ],
                                    // نواقص المخزون
                                    if (lowStock.isNotEmpty) ...<Widget>[
                                      _sectionLabel(i18n.t('nav', 'low_stock'), theme),
                                      for (final LowStockItem it in lowStock)
                                        _row(
                                          theme,
                                          title: it.productName,
                                          // header.tsx:178 — تركيز الدواء بجانب اسمه بذكاء
                                          titleSuffix: _extraStrengthLabel(it.productName, it.strength),
                                          subtitle: (it.fullBoxes == 0 && it.strips == 0)
                                              ? i18n.t('nav', 'out_of_stock_line', {'min': _boxWord(it.minStockLevel, i18n)})
                                              : i18n.t('nav', 'low_stock_line', {
                                                  'min': _boxWord(it.minStockLevel, i18n),
                                                  'available': _availability(it, i18n),
                                                }),
                                          badge: (it.fullBoxes == 0 && it.strips == 0) ? i18n.t('nav', 'out_badge') : i18n.t('nav', 'low_badge'),
                                          badgeFg: theme.colorScheme.error,
                                          badgeBg: theme.colorScheme.error.withOpacity(0.10),
                                          onTap: () {
                                            Navigator.pop(ctx);
                                            HomeNav.go(context, 'inventory');
                                          },
                                        ),
                                    ],
                                  ],
                                ),
                        ),
                      ),
                    ),
                    // روابط الانتقال السفلية
                    if (debts.isNotEmpty && state.can('customers.view'))
                      _panelLink(theme, i18n.t('nav', 'open_customers'), () {
                        Navigator.pop(ctx);
                        HomeNav.go(context, 'customers');
                      }),
                    if (lowStock.isNotEmpty && state.can('inventory.view'))
                      _panelLink(theme, i18n.t('nav', 'open_inventory'), () {
                        Navigator.pop(ctx);
                        HomeNav.go(context, 'inventory');
                      }),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    onChanged();
  }

  Widget _sectionLabel(String text, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: theme.colorScheme.onSurface.withOpacity(0.03),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface.withOpacity(0.55))),
    );
  }

  /// نفس extraStrengthLabel في الويب (lib/product.ts): لا نُلحق التركيز
  /// إذا كان الاسم المسجّل يحمل جرعة أصلًا أو يحتوي نص التركيز نفسه.
  static final RegExp _doseInNamePattern =
      RegExp(r'\d\s*(?:mg|µg|mcg|g|ml|iu|ملجم|ملغ|مل|جرام|وحدة)', caseSensitive: false);

  String _extraStrengthLabel(String name, String strength) {
    final clean = strength.trim();
    if (clean.isEmpty) return '';
    if (name.toLowerCase().contains(clean.toLowerCase())) return '';
    if (_doseInNamePattern.hasMatch(name)) return '';
    return clean;
  }

  Widget _row(
    ThemeData theme, {
    required String title,
    String? titleSuffix,
    required String subtitle,
    required String badge,
    required Color badgeFg,
    required Color badgeBg,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.6)))),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text.rich(
                    TextSpan(
                      text: title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      children: <InlineSpan>[
                        if (titleSuffix != null && titleSuffix.isNotEmpty)
                          TextSpan(
                            text: ' $titleSuffix', // ms-1 text-xs font-normal text-muted-foreground
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: theme.colorScheme.onSurface.withOpacity(0.55),
                            ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(999)),
              child: Text(badge, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: badgeFg)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panelLink(ThemeData theme, String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.dividerColor))),
        alignment: Alignment.center,
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
      ),
    );
  }

  // نفس مساعدات الويب: boxWordAr وavailabilityAr
  String _boxWord(int count, AppI18n i18n) {
    if (count == 1) return i18n.t('inventory', 'box_word_one');
    if (count == 2) return i18n.t('inventory', 'box_word_two');
    if (count <= 10) return i18n.t('inventory', 'box_word_many', {'count': Fmt.number(count)});
    return i18n.t('inventory', 'box_word_other', {'count': Fmt.number(count)});
  }

  String _availability(LowStockItem it, AppI18n i18n) {
    if (it.fullBoxes == 0 && it.strips == 0) return i18n.t('inventory', 'qty_out_of_stock');
    if (it.strips == 0) return i18n.t('inventory', 'qty_boxes_only', {'count': Fmt.number(it.fullBoxes)});
    if (it.fullBoxes == 0) return i18n.t('inventory', 'qty_strips_only', {'count': Fmt.number(it.strips)});
    return i18n.t('inventory', 'availability_box_and_strip', {'boxes': Fmt.number(it.fullBoxes), 'strips': Fmt.number(it.strips)});
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        IconButtonGhost(
          Icons.notifications_outlined,
          tooltip: count > 0 ? i18n.t('nav', 'notifications_with_count', {'count': '$count'}) : i18n.t('nav', 'notifications'),
          onPressed: () => _openPanel(context),
        ),
        if (count > 0)
          PositionedDirectional(
            start: -2,
            top: 2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16),
              height: 16,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onPrimary),
              ),
            ),
          ),
      ],
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

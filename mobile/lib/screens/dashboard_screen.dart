import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';
import 'home_screen.dart';
import 'product_form_screen.dart';

/// Task 62 — لوحة التحكم بنسخة الويب حرفيًا: رأس صفحة بعنوان 2xl وزر
/// «إضافة دواء» المتدرج، 4 بطاقات إحصائية (عمود واحد على الهاتف مثل
/// grid-cols-1، عمودان من 640px)، ثم بطاقة حالة المخزون بسطور النواقص
/// داخل مربعات rounded-xl وبطاقة الإجراءات السريعة بشبكة عمودين.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardStats? _stats;
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
      if (!mounted) return;
      setState(() {
        _stats = stats;
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
        _error = i18n.t('dashboard', 'error_load');
        _loading = false;
      });
    }
  }

  bool get _canAddProduct {
    final state = context.read<AppState>();
    return state.can('inventory.manage_products') || state.permissions?.fullAccess == true;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    if (_loading) {
      // مثل الويب: Card بنص dashboard.loading بدل الهيكل العظمي المجرد
      return AppCard(
        padding: const EdgeInsets.all(32), // p-8
        child: Center(
          child: Text(
            i18n.t('dashboard', 'loading'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
          ),
        ),
      );
    }
    if (_error != null) return ErrorRetry(_error!, onRetry: _load);
    final stats = _stats;
    if (stats == null) {
      return ErrorRetry(i18n.t('dashboard', 'error_load'), onRetry: _load);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16), // p-4
        children: <Widget>[
          // رأس الصفحة + زر الإضافة المتدرج
          PageHeader(
            i18n.t('dashboard', 'title'),
            subtitle: i18n.t('dashboard', 'subtitle'),
            actions: <Widget>[
              if (_canAddProduct)
                WButton(
                  i18n.t('dashboard', 'add_product'),
                  icon: Icons.add,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const ProductFormScreen()),
                  ),
                  variant: WButtonVariant.gradient,
                ),
            ],
          ),
          const SizedBox(height: 24), // space-y-6

          // بطاقات الإحصائيات — عمودان من 640px مثل الويب
          LayoutBuilder(builder: (BuildContext ctx, BoxConstraints c) {
            final twoCols = c.maxWidth >= 640; // sm:grid-cols-2
            final cards = <Widget>[
              StatCard(
                label: i18n.t('dashboard', 'total_products'),
                value: Fmt.number(stats.totalProducts),
                icon: Icons.inventory_2_outlined, // Package
                tone: StatTone.primary,
              ),
              StatCard(
                label: i18n.t('dashboard', 'low_stock_products'),
                value: Fmt.number(stats.lowStockCount),
                icon: Icons.warning_amber_outlined, // AlertTriangle
                tone: StatTone.warning,
              ),
              StatCard(
                label: i18n.t('dashboard', 'sales_units_today'),
                value: Fmt.number(stats.salesUnitsToday),
                icon: Icons.trending_up, // TrendingUp
                tone: StatTone.success,
              ),
              StatCard(
                label: i18n.t('dashboard', 'attendance_today'),
                value: '${Fmt.number(stats.activeToday)} / ${Fmt.number(stats.activeEmployees)}',
                icon: Icons.group_outlined, // Users
                tone: StatTone.info,
              ),
            ];
            if (!twoCols) {
              return Column(
                children: <Widget>[
                  for (final card in cards) ...<Widget>[card, const SizedBox(height: 16)],
                ],
              );
            }
            return GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 2.1,
              children: cards,
            );
          }),
          const SizedBox(height: 24),

          _LowStockCard(items: stats.lowStockItems),
          const SizedBox(height: 24),
          const _QuickActionsCard(),
        ],
      ),
    );
  }
}

/// حالة المخزون — بطاقة بعنوان text-lg ووصف، وسطور النواقص كل سطر في
/// مربع rounded-xl border p-3.5 بصندوق أيقونة 40 amber وشارة التوفر.
class _LowStockCard extends StatelessWidget {
  final List<DashboardLowStock> items;
  const _LowStockCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: CardTitle(
              i18n.t('dashboard', 'inventory_status'),
              subtitle: i18n.t('dashboard', 'inventory_status_desc'),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(i18n.t('dashboard', 'no_low_stock'),
                          style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                    ),
                  )
                : Column(
                    children: <Widget>[
                      for (final item in items) ...<Widget>[
                        LowStockTile(
                          name: item.name,
                          subtitle: item.genericName, // الويب: السطر الفرعي = الاسم العلمي
                          badge: _availabilityWord(item.quantity, item.strips, i18n), // شارة التوفر بصياغة الويب
                          badgeTone: BadgeTone.warning, // الويب: <Badge variant="warning"> ثابتة لا حسب الحالة
                          note: i18n.t('dashboard', 'reorder_note', {'min': _boxWord(item.minStockLevel, i18n)}),
                          iconBg: AppColors.warningBg,
                          iconFg: theme.brightness == Brightness.dark ? AppColors.warningFgDark : AppColors.warningFg,
                        ),
                        if (item != items.last) const SizedBox(height: 16),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // نفس مساعدات الويب lib/product.ts — صياغة عربية للعلب والشرائط
  String _boxWord(int count, AppI18n i18n) {
    if (count == 1) return i18n.t('inventory', 'box_word_one');
    if (count == 2) return i18n.t('inventory', 'box_word_two');
    if (count >= 3 && count <= 10) return i18n.t('inventory', 'box_word_many', {'count': Fmt.number(count)});
    return i18n.t('inventory', 'box_word_other', {'count': Fmt.number(count)});
  }

  String _stripWord(int count, AppI18n i18n) {
    if (count == 1) return i18n.t('inventory', 'strip_word_one');
    if (count == 2) return i18n.t('inventory', 'strip_word_two');
    if (count >= 3 && count <= 10) return i18n.t('inventory', 'strip_word_many', {'count': Fmt.number(count)});
    return i18n.t('inventory', 'strip_word_other', {'count': Fmt.number(count)});
  }

  /// availabilityAr في الويب — لوحة التحكم تمرّر quantity كالعلب الكاملة
  String _availabilityWord(int fullBoxes, int strips, AppI18n i18n) {
    if (fullBoxes > 0 && strips > 0) {
      return i18n.t('inventory', 'availability_box_and_strip', {
        'boxes': Fmt.number(fullBoxes),
        'strips': _stripWord(strips, i18n),
      });
    }
    if (fullBoxes > 0) return _boxWord(fullBoxes, i18n);
    return _stripWord(strips, i18n);
  }
}

/// الإجراءات السريعة — شبكة عمودين من مربعات rounded-xl بأيقونة 24
/// بلون الهوية وتسمية text-xs (مثل الويب: مخزون/موظفون/حضور/تقارير).
class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard();

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final state = context.watch<AppState>();
    // الإجراءات الأربعة في الويب مع بواباتها — التنقل عبر مفتاح صفحات
    // الشل (IndexedStack) نفسه كما في تبديل المسارات بالويب.
    final tiles = <Widget>[];
    void addTile(IconData icon, String label, VoidCallback onTap) {
      tiles.add(QuickActionTile(icon: icon, label: label, onTap: onTap));
    }

    if (state.can('inventory.view')) {
      addTile(Icons.inventory_2_outlined, i18n.t('dashboard', 'nav_inventory'),
          () => _ShellNav.open(context, 'inventory'));
    }
    if (state.can('employees.view')) {
      addTile(Icons.group_outlined, i18n.t('dashboard', 'nav_employees'),
          () => _ShellNav.open(context, 'employees'));
    }
    if (state.can('attendance.view')) {
      addTile(Icons.event_available_outlined, i18n.t('dashboard', 'nav_attendance'),
          () => _ShellNav.open(context, 'attendance'));
    }
    if (state.canAny(<String>['reports.sales', 'reports.inventory', 'reports.movements', 'reports.financial', 'reports.employees'])) {
      addTile(Icons.bar_chart_outlined, i18n.t('dashboard', 'nav_reports'),
          () => _ShellNav.open(context, 'reports'));
    }
    if (tiles.isEmpty) {
      return AppCard(
        padding: const EdgeInsets.all(24),
        child: Text(i18n.t('dashboard', 'no_quick_actions'),
            style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
      );
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: CardTitle(i18n.t('dashboard', 'quick_actions')),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.4,
              children: tiles,
            ),
          ),
        ],
      ),
    );
  }
}

/// جسر تنقّل للهيكل: ينشّط صفحة من صفحات الشل بالمعرّف نفسه
/// (نفس تجربة الويب — النقر على الإجراء السريع يبدّل الصفحة الرئيسية).
class _ShellNav {
  static void open(BuildContext context, String key) {
    HomeNav.go(context, key);
  }
}

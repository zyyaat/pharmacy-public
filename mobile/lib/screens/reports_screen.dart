import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// Task 68-k — التقارير مطابقة لصفحات الويب حرفيًا (طباعة PDF مؤجَّلة بخطة
/// Task 68 فلا ReportSheet هنا):
/// مركز البطاقات (reports/page.tsx): عنوان + subtitle + بوابة anyOf بنفس
/// المفاتيح الخمسة + بطاقة لكل تقرير بمحتوى عمودي وCTA «فتح التقرير» بسهم.
/// تقرير المبيعات (reports/sales): KPI cards بنغمات وتلميحات، رسم يومي بكل
/// أيام الفترة وتسميات ≈8، جدول الأكثر بيعًا بأربعة أعمدة، وفواتير الفترة.
/// تقرير المخزون (reports/inventory): KPIs بنغمات، مجموعات الصلاحية 2×2
/// ملوّنة مع سطر قيمة المخزون المنتهي، جدولا النواقص والصلاحيات الكاملان،
/// وتفاصيل المخزون الحالي بثمانية أعمدة (أول 500 تشغيلة).
/// تقرير الحركات (reports/movements): KPIs بإشارات، ملخص بالنوع مع عمود
/// الصافي وملاحظة الوحدة الأساسية، وتفاصيل الحركات بفلاتر نوع/اتجاه
/// (تطبيق/مسح) وحد 200 سطر وجدول ثماني الأعمدة.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  /// بوابة المركز — RequirePermission anyOf في reports/page.tsx:41
  static const List<String> _hubPerms = <String>[
    'reports.sales',
    'reports.inventory',
    'reports.movements',
    'reports.financial',
    'reports.employees',
  ];

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final state = context.watch<AppState>();
    if (!state.canAny(_hubPerms)) {
      // عمليًا الشل يحجب صفحة التقارير قبل الوصول (نفس anyOf) — بطاقة
      // «غير متاح» هنا للدفاع في العمق كـ RequirePermission بالويب
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.lock_outline, size: 44, color: theme.colorScheme.onSurface.withOpacity(0.3)),
              const SizedBox(height: 14),
              Text(i18n.t('common', 'no_access_title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(i18n.t('common', 'no_access_body'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.55))),
            ],
          ),
        ),
      );
    }
    final rtl = i18n.isRtl;
    final reports = <({IconData icon, String title, String desc, WidgetBuilder builder})>[
      if (state.can('reports.sales'))
        (
          icon: Icons.receipt_long_outlined,
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        PageHeader(i18n.t('reports', 'title'), subtitle: i18n.t('reports', 'subtitle')),
        const SizedBox(height: 24),
        if (reports.isEmpty)
          AppCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(i18n.t('reports', 'empty'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.5))),
            ),
          )
        else
          // بطاقة تقرير عمودية كصفحة الويب: أيقونة 44 ثم العنوان ثم الوصف
          // ثم CTA «فتح التقرير» بسهم أمامي (page.tsx:61-75)
          for (final r in reports) ...<Widget>[
            AppCard(
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: r.builder)),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 44, // h-11 w-11
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.10),
                      borderRadius: AppRadius.brXl,
                    ),
                    child: Icon(r.icon, size: 20, color: theme.colorScheme.primary),
                  ),
                  const SizedBox(height: 12),
                  Text(r.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(r.desc,
                      style: TextStyle(
                          fontSize: 13, height: 1.5, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(i18n.t('reports', 'open_report'),
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
                      const SizedBox(width: 4),
                      // ChevronLeft مع rtl-flip بالويب: للأمام (يمين LTR / يسار RTL)
                      Icon(rtl ? Icons.chevron_left : Icons.chevron_right,
                          size: 16, color: theme.colorScheme.primary),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
      ],
    );
  }
}

// ------------------------------------------------------------ أداة الفترة

/// منتقي الفترة — القوائم الجاهزة تُطبَّق فورًا مثل changePreset بالويب،
/// والمخصصة بمنتقَي تاريخ يطبّقان فورًا أيضًا (لا زر تطبيق منفصل هنا).
class _PeriodPicker extends StatefulWidget {
  final ValueChanged<({String? from, String? to})> onApply;
  const _PeriodPicker({required this.onApply});
  @override
  State<_PeriodPicker> createState() => _PeriodPickerState();
}

class _PeriodPickerState extends State<_PeriodPicker> {
  // الويب يفتح التقارير على last30 (reports/sales/page.tsx:45)
  String _preset = 'last30';
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

// ------------------------------------------------------------ عناصر مشتركة

/// تسمية قسم داخل التقرير — h3 text-sm font-bold بالويب (14px عريض)
/// مع أيقونة اختيارية وسطر عدّ/ملاحظة في الجهة المقابلة.
class _SectionTitle extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? iconColor;
  final Widget? trailing;
  const _SectionTitle(this.text, {this.icon, this.iconColor, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12), // mb-3
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 8), // gap-2
          ],
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// صندوق الفراغ — rounded-lg border py-8 text-center text-sm muted
/// (p.className="rounded-lg border border-dashed py-8 text-center" بالويب)
class _EmptyNote extends StatelessWidget {
  final String text;
  const _EmptyNote(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: AppRadius.br,
        border: Border.all(color: theme.dividerColor),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.45))),
    );
  }
}

enum _KpiTone { neutral, success, destructive, warning }

/// KpiItem في components/reports/kpi-cards.tsx
class _KpiItem {
  final String label;
  final String value;
  final String? hint;
  final _KpiTone tone;
  const _KpiItem(this.label, this.value, {this.hint, this.tone = _KpiTone.neutral});
}

/// KpiCards — بطاقة لكل مؤشر: label صغير muted ثم value عريض بنغمة ثم hint.
/// عمودان على الهاتف (grid-cols-2 بالويب) مع مسافة 12 بين البطاقات.
class _KpiCards extends StatelessWidget {
  final List<_KpiItem> items;
  const _KpiCards(this.items);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    Color toneColor(_KpiTone tone) {
      switch (tone) {
        case _KpiTone.success:
          return dark ? AppColors.successFgDark : AppColors.successFg; // emerald
        case _KpiTone.destructive:
          return theme.colorScheme.error;
        case _KpiTone.warning:
          return dark ? AppColors.warningFgDark : AppColors.warningFg; // amber
        case _KpiTone.neutral:
          return theme.colorScheme.onSurface;
      }
    }

    final rows = <Widget>[];
    for (int i = 0; i < items.length; i += 2) {
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: _card(context, items[i], toneColor)),
          const SizedBox(width: 12),
          if (i + 1 < items.length)
            Expanded(child: _card(context, items[i + 1], toneColor))
          else
            const Expanded(child: SizedBox()),
        ],
      ));
      if (i + 2 < items.length) rows.add(const SizedBox(height: 12));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  Widget _card(BuildContext context, _KpiItem item, Color Function(_KpiTone) toneColor) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16), // p-4
      decoration: BoxDecoration(
        color: theme.colorScheme.surface, // bg-card
        borderRadius: AppRadius.brXl,
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(item.label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface.withOpacity(0.55))),
          const SizedBox(height: 4),
          Text(
            item.value,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700, height: 1.2, color: toneColor(item.tone)),
          ),
          if (item.hint != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(item.hint!,
                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5))),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ مساعدات العرض

String _money(int piastres) => Fmt.money(piastres, locale: AppI18n.instance.locale);

/// يوم الشهر من YYYY-MM-DD لتسميات الرسم — dayLabel في lib/reports.ts:105
String _dayLabel(String isoDay) {
  final parts = isoDay.split('-');
  if (parts.length < 3) return isoDay;
  final d = int.tryParse(parts[2]);
  return d == null ? isoDay : '$d';
}

/// يوم رقمي + شهر طويل + سنة — formatSaleDate في lib/sales.ts (month: long)
String _fmtSaleDate(String iso) => Fmt.date(iso, locale: AppI18n.instance.locale);

/// يوم رقمي + شهر قصير + سنة — formatMovementDate في lib/movements.ts:56
String _fmtDay(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  final months = AppI18n.instance.locale == 'ar' ? _monthsShortAr : _monthsShortEn;
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

const List<String> _monthsShortAr = <String>[
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];
const List<String> _monthsShortEn = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// ساعة 12 بصيغة ص/م — formatSaleTime / fmtDateTime({hour, minute})
String _fmtClock(String iso, {bool padHour = false}) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '—';
  final ar = AppI18n.instance.locale == 'ar';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final hh = padHour ? h.toString().padLeft(2, '0') : '$h';
  final mm = d.minute.toString().padLeft(2, '0');
  final period = ar ? (d.hour < 12 ? 'ص' : 'م') : (d.hour < 12 ? 'am' : 'pm');
  return '$hh:$mm $period';
}

/// ترجمة شريط/علبة عبر نطاق movements والباقي كما ورد — lib/movements.ts:72
String _unitLabel(String unit) {
  final i18n = AppI18n.instance;
  if (unit == 'strip') return i18n.t('movements', 'unit_strip');
  if (unit == 'box') return i18n.t('movements', 'unit_box');
  return unit;
}

String _quantityText(num quantity, String unit) => '${Fmt.number(quantity.abs())} ${_unitLabel(unit)}';

// ------------------------------------------------------------ مبيعات

class SalesReportScreen extends StatefulWidget {
  const SalesReportScreen({super.key});
  @override
  State<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends State<SalesReportScreen> {
  // INVOICES_LIMIT في reports/sales/page.tsx:40
  static const int _invoicesLimit = 100;

  SalesReport? _report;
  List<SaleSummary> _invoices = const <SaleSummary>[];
  int _invoicesTotal = 0;
  String? _from;
  String? _to;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // أول تحميل: آخر 30 يوم (presetRange('last30') بالويب)
    final now = DateTime.now();
    _from = Fmt.isoDay(now.subtract(const Duration(days: 29)));
    _to = Fmt.isoDay(now);
    _load();
  }

  /// getSalesReport + listPOSSales بالتوازي (Promise.all بالويب 61-64)
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final i18n = AppI18n.instance;
    try {
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        ApiClient.instance.salesReport(from: _from, to: _to),
        ApiClient.instance.listPOSSales(
          limit: _invoicesLimit,
          offset: 0,
          search: '',
          from: _from ?? '',
          to: _to ?? '',
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _report = results[0] as SalesReport;
        final inv = results[1] as ({List<SaleSummary> sales, int total, int limit, int offset});
        _invoices = inv.sales;
        _invoicesTotal = inv.total;
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

  /// kpis في reports/sales/page.tsx:118-152 — نغمات وتلميحات مطابقة
  List<_KpiItem> _kpis(SalesReport s) {
    final i18n = AppI18n.instance;
    return <_KpiItem>[
      _KpiItem(
        i18n.t('reports', 'kpi_gross_sales'),
        _money(s.grossPiastres),
        hint: i18n.t('reports', 'hint_invoices', {'count': Fmt.number(s.invoicesCount)}),
      ),
      _KpiItem(
        i18n.t('reports', 'kpi_returns'),
        _money(s.returnedPiastres),
        hint: i18n.t('reports', 'hint_return_notes', {'count': Fmt.number(s.returnsCount)}),
        tone: s.returnedPiastres > 0 ? _KpiTone.destructive : _KpiTone.neutral,
      ),
      _KpiItem(
        i18n.t('reports', 'kpi_net_sales'),
        _money(s.netPiastres),
        tone: _KpiTone.success,
      ),
      _KpiItem(
        i18n.t('reports', 'kpi_units_sold'),
        Fmt.number(s.unitsBase),
        hint: i18n.t('reports', 'hint_base_units'),
      ),
      _KpiItem(
        i18n.t('reports', 'kpi_avg_invoice'),
        _money(s.avgInvoicePiastres),
        hint: s.invoicesCount > 0
            ? i18n.t('reports', 'hint_avg_invoice',
                {'count': Fmt.number((s.unitsBase / s.invoicesCount).round())})
            : null,
      ),
    ];
  }

  /// saleStatusLabel في lib/sales.ts:15 — الافتراضي مكتملة
  String _saleStatusLabel(String status) {
    final i18n = AppI18n.instance;
    switch (status) {
      case 'returned':
        return i18n.t('sales', 'statusReturned');
      case 'partially_returned':
        return i18n.t('sales', 'statusPartiallyReturned');
      default:
        return i18n.t('sales', 'statusCompleted');
    }
  }

  /// saleStatusVariant في lib/sales.ts:27
  BadgeTone _saleStatusTone(String status) {
    switch (status) {
      case 'returned':
        return BadgeTone.destructive;
      case 'partially_returned':
        return BadgeTone.warning;
      default:
        return BadgeTone.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final r = _report;
    final Widget body;
    if (_loading && r == null) {
      body = const LoadingBox();
    } else if (_error != null && r == null) {
      body = ErrorRetry(_error!, onRetry: _load);
    } else {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          // عند فشل إعادة التحميل يبقى التقرير الأخير معبطًا ببطاقة خطأ (الويب 202-206)
          if (_error != null && r != null) ...<Widget>[
            ErrorBanner(_error!),
            const SizedBox(height: 12),
          ],
          Text(i18n.t('reports', 'sales_subtitle'),
              style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.55))),
          const SizedBox(height: 12),
          _PeriodPicker(onApply: (({String? from, String? to}) range) {
            _from = range.from;
            _to = range.to;
            _load();
          }),
          const SizedBox(height: 20),
          if (r != null) ...<Widget>[
            _KpiCards(_kpis(r)),
            const SizedBox(height: 20),
            // المبيعات اليومية — كل أيام الفترة مع سطر chart_max/summary
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SectionTitle(i18n.t('reports', 'daily_net_sales')),
                if (r.daily.isEmpty)
                  Text(i18n.t('reports', 'no_chart_data'),
                      style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.5)))
                else
                  MiniBarChart(
                    points: <({String label, int value})>[
                      for (final p in r.daily) (label: _dayLabel(p.day), value: p.net),
                    ],
                    summary: i18n.t('reports', 'chart_summary_days',
                        {'count': Fmt.number(r.daily.length)}),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            // المنتجات الأكثر بيعاً — جدول 4 أعمدة برقم ترتيب (الويب 249-281)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SectionTitle(i18n.t('reports', 'top_products')),
                if (r.topProducts.isEmpty)
                  _EmptyNote(i18n.t('reports', 'no_sales_in_period'))
                else
                  WebTable(
                    minWidth: 640,
                    headers: <String>[
                      '#',
                      i18n.t('reports', 'col_item'),
                      i18n.t('reports', 'col_quantity'),
                      i18n.t('reports', 'col_revenue'),
                    ],
                    rows: <List<Widget>>[
                      for (int i = 0; i < r.topProducts.length; i++)
                        <Widget>[
                          Text('${i + 1}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface.withOpacity(0.5))),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(r.topProducts[i].name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              if (r.topProducts[i].genericName.isNotEmpty)
                                Text(r.topProducts[i].genericName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: theme.colorScheme.onSurface.withOpacity(0.5))),
                            ],
                          ),
                          Text(Fmt.number(r.topProducts[i].qtyBase),
                              style: const TextStyle(fontSize: 13)),
                          Text(_money(r.topProducts[i].amount),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        ],
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 20),
            // فواتير الفترة — قائمة آخر 100 فاتورة ضمن الفترة (الويب 285-362)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SectionTitle(
                  i18n.t('reports', 'period_invoices'),
                  trailing: Text(
                    _invoicesTotal > _invoicesLimit
                        ? i18n.t('reports', 'invoices_showing',
                            {'limit': Fmt.number(_invoicesLimit), 'total': Fmt.number(_invoicesTotal)})
                        : i18n.t('reports', 'invoices_count', {'count': Fmt.number(_invoicesTotal)}),
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                  ),
                ),
                if (_invoices.isEmpty)
                  _EmptyNote(i18n.t('reports', 'no_invoices_in_period'))
                else
                  WebTable(
                    minWidth: 940,
                    headers: <String>[
                      i18n.t('reports', 'col_invoice'),
                      i18n.t('reports', 'col_date'),
                      i18n.t('reports', 'col_status'),
                      i18n.t('reports', 'col_items'),
                      i18n.t('reports', 'col_units'),
                      i18n.t('reports', 'col_total'),
                      i18n.t('reports', 'col_returned'),
                    ],
                    rows: <List<Widget>>[
                      for (final s in _invoices)
                        <Widget>[
                          // INV-000012 بمقدار 6 أرقام وباتجاه LTR إجباري
                          Text('INV-${s.invoiceNumber.toString().padLeft(6, '0')}',
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(_fmtSaleDate(s.createdAt),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurface.withOpacity(0.8))),
                              Text(_fmtClock(s.createdAt),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: theme.colorScheme.onSurface.withOpacity(0.5))),
                            ],
                          ),
                          AppBadge(_saleStatusLabel(s.status), tone: _saleStatusTone(s.status)),
                          Text(Fmt.number(s.productsCount), style: const TextStyle(fontSize: 13)),
                          Text(Fmt.number(s.totalQuantityBase), style: const TextStyle(fontSize: 13)),
                          Text(_money(s.totalAmountPiastres),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          if (s.returnedAmountPiastres > 0)
                            Text(_money(s.returnedAmountPiastres),
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: theme.colorScheme.error))
                          else
                            Text('—',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: theme.colorScheme.onSurface.withOpacity(0.5))),
                        ],
                    ],
                  ),
              ],
            ),
          ],
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('reports', 'sales_title'))),
      body: body,
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
  List<InventoryItem> _items = const <InventoryItem>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// getInventoryReport + getInventory بالتوازي (Promise.all بالويب 63-67)
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final i18n = AppI18n.instance;
    try {
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        ApiClient.instance.inventoryReport(),
        ApiClient.instance.inventory(),
      ]);
      if (!mounted) return;
      setState(() {
        _report = results[0] as InventoryReport;
        _items = results[1] as List<InventoryItem>;
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

  /// kpis في reports/inventory/page.tsx:84-114
  List<_KpiItem> _kpis(InventoryReport r) {
    final i18n = AppI18n.instance;
    return <_KpiItem>[
      _KpiItem(
        i18n.t('reports', 'kpi_cost_value'),
        _money(r.costValue),
        hint: i18n.t('reports', 'hint_batches_products',
            {'batches': Fmt.number(r.batchesCount), 'products': Fmt.number(r.productsCount)}),
      ),
      _KpiItem(
        i18n.t('reports', 'kpi_retail_value'),
        _money(r.retailValue),
        hint: i18n.t('reports', 'hint_units_base', {'count': Fmt.number(r.unitsBase)}),
        tone: _KpiTone.success,
      ),
      _KpiItem(
        i18n.t('reports', 'kpi_low_items'),
        Fmt.number(r.lowStockCount),
        hint: i18n.t('reports', 'hint_at_or_below_min'),
        tone: r.lowStockCount > 0 ? _KpiTone.warning : _KpiTone.neutral,
      ),
      _KpiItem(
        i18n.t('reports', 'kpi_out_items'),
        Fmt.number(r.outOfStockCount),
        tone: r.outOfStockCount > 0 ? _KpiTone.destructive : _KpiTone.neutral,
      ),
    ];
  }

  /// statusBadgeKeys في reports/inventory/page.tsx:33-39 — المجهول يرجع normal
  (BadgeTone, String) _detailStatus(String status) {
    final i18n = AppI18n.instance;
    switch (status.toLowerCase()) {
      case 'low_stock':
        return (BadgeTone.warning, i18n.t('reports', 'status_low'));
      case 'out_of_stock':
        return (BadgeTone.destructive, i18n.t('reports', 'status_out'));
      case 'expiring_soon':
        return (BadgeTone.warning, i18n.t('reports', 'status_expiring_soon'));
      case 'quarantined':
        return (BadgeTone.warning, i18n.t('reports', 'status_quarantined'));
      default:
        return (BadgeTone.success, i18n.t('reports', 'status_normal'));
    }
  }

  /// expiryTone في reports/inventory/page.tsx:42-46 — secondary يُعرض outline
  BadgeTone _expiryTone(int days) {
    if (days <= 0) return BadgeTone.destructive;
    if (days <= 30) return BadgeTone.warning;
    return BadgeTone.muted;
  }

  /// بلاطة مجموعة صلاحية — rounded-xl border p-4 بأيقونة 32 بخلفية ملوّنة
  Widget _bucket(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int count,
    required Color fg,
    required Color bg,
  }) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16), // p-4
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.brXl,
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 32, // h-8 w-8
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: bg, borderRadius: AppRadius.br),
                child: Icon(icon, size: 16, color: fg),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface.withOpacity(0.55))),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(i18n.t('reports', 'hint_batches', {'count': Fmt.number(count)}),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final r = _report;
    final Widget body;
    if (_loading && r == null) {
      body = const LoadingBox();
    } else if (_error != null && r == null) {
      body = ErrorRetry(_error!, onRetry: _load);
    } else {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (_error != null && r != null) ...<Widget>[
            ErrorBanner(_error!),
            const SizedBox(height: 12),
          ],
          Text(i18n.t('reports', 'inventory_subtitle'),
              style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.55))),
          const SizedBox(height: 12),
          if (r != null) ...<Widget>[
            _KpiCards(_kpis(r)),
            const SizedBox(height: 20),
            // مجموعات الصلاحية — 2×2 بلاطات ملوّنة (الويب 205-227)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SectionTitle(i18n.t('reports', 'expiry_section')),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: _bucket(
                        context,
                        icon: Icons.dangerous_outlined,
                        label: i18n.t('reports', 'expiry_expired'),
                        count: r.expiredCount,
                        fg: theme.colorScheme.error,
                        bg: theme.colorScheme.error.withOpacity(0.10),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _bucket(
                        context,
                        icon: Icons.calendar_month,
                        label: i18n.t('reports', 'expiry_30'),
                        count: r.expiring30,
                        fg: dark ? AppColors.warningFgDark : AppColors.warningFg,
                        bg: AppColors.warningBg,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: _bucket(
                        context,
                        icon: Icons.calendar_month,
                        label: i18n.t('reports', 'expiry_31_60'),
                        count: r.expiring60,
                        fg: theme.colorScheme.onSurface,
                        bg: theme.colorScheme.onSurface.withOpacity(0.05),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _bucket(
                        context,
                        icon: Icons.calendar_month,
                        label: i18n.t('reports', 'expiry_61_90'),
                        count: r.expiring90,
                        fg: theme.colorScheme.onSurface,
                        bg: theme.colorScheme.onSurface.withOpacity(0.05),
                      ),
                    ),
                  ],
                ),
                // سطر قيمة المخزون المنتهي/قريب الانتهاء (الويب 228-237)
                if (r.expiredValue > 0 || r.expiringValue > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text.rich(
                      TextSpan(
                        style: TextStyle(
                            fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                        children: <InlineSpan>[
                          TextSpan(text: '${i18n.t('reports', 'expired_value_label')} '),
                          TextSpan(
                            text: _money(r.expiredValue),
                            style: TextStyle(
                                fontWeight: FontWeight.w700, color: theme.colorScheme.error),
                          ),
                          TextSpan(text: ' · ${i18n.t('reports', 'expiring_value_label')} '),
                          TextSpan(
                            text: _money(r.expiringValue),
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            // النواقص — 6 أعمدة بتشغيلة/فرع/حد أدنى/شارة حالة (الويب 251-297)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SectionTitle(
                  i18n.t('reports', 'low_stock_list'),
                  icon: Icons.warning_amber_rounded,
                  iconColor: dark ? AppColors.warningFgDark : AppColors.warningFg,
                ),
                if (r.lowStockItems.isEmpty)
                  _EmptyNote(i18n.t('reports', 'no_low_stock_items'))
                else
                  WebTable(
                    minWidth: 880,
                    headers: <String>[
                      i18n.t('reports', 'col_item'),
                      i18n.t('reports', 'col_batch'),
                      i18n.t('reports', 'col_branch'),
                      i18n.t('reports', 'col_available'),
                      i18n.t('reports', 'col_min'),
                      i18n.t('reports', 'col_status'),
                    ],
                    rows: <List<Widget>>[
                      for (final it in r.lowStockItems)
                        <Widget>[
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(it.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              if (it.genericName.isNotEmpty)
                                Text(it.genericName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: theme.colorScheme.onSurface.withOpacity(0.5))),
                            ],
                          ),
                          Text(it.batchNumber.isEmpty ? '—' : it.batchNumber,
                              textDirection: it.batchNumber.isEmpty ? null : TextDirection.ltr,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface.withOpacity(0.7))),
                          Text(it.branchName.isEmpty ? '—' : it.branchName,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface.withOpacity(0.7))),
                          Text(Fmt.number(it.quantity),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          Text(Fmt.number(it.threshold),
                              style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.onSurface.withOpacity(0.5))),
                          AppBadge(
                            it.quantity <= 0
                                ? i18n.t('reports', 'status_out')
                                : i18n.t('reports', 'status_low'),
                            tone: it.quantity <= 0 ? BadgeTone.destructive : BadgeTone.warning,
                          ),
                        ],
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 20),
            // الصلاحيات القريبة — 5 أعمدة بكمية وشارة أيام متبقية (الويب 312-356)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SectionTitle(
                  i18n.t('reports', 'expiry_list'),
                  icon: Icons.calendar_month,
                  iconColor: dark ? AppColors.warningFgDark : AppColors.warningFg,
                ),
                if (r.expiringItems.isEmpty)
                  _EmptyNote(i18n.t('reports', 'no_expiring_items'))
                else
                  WebTable(
                    minWidth: 800,
                    headers: <String>[
                      i18n.t('reports', 'col_item'),
                      i18n.t('reports', 'col_batch'),
                      i18n.t('reports', 'col_available'),
                      i18n.t('reports', 'col_expiry_date'),
                      i18n.t('reports', 'col_days_left'),
                    ],
                    rows: <List<Widget>>[
                      for (final it in r.expiringItems)
                        <Widget>[
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(it.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              if (it.genericName.isNotEmpty)
                                Text(it.genericName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: theme.colorScheme.onSurface.withOpacity(0.5))),
                            ],
                          ),
                          Text(it.batchNumber.isEmpty ? '—' : it.batchNumber,
                              textDirection: it.batchNumber.isEmpty ? null : TextDirection.ltr,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface.withOpacity(0.7))),
                          Text(Fmt.number(it.quantity), style: const TextStyle(fontSize: 13)),
                          Text(it.extraDate == null
                              ? '—'
                              : Fmt.date(it.extraDate, locale: i18n.locale),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface.withOpacity(0.7))),
                          AppBadge(
                            it.threshold <= 0
                                ? i18n.t('reports', 'batch_expired')
                                : i18n.t('reports', 'days_left',
                                    {'count': Fmt.number(it.threshold)}),
                            tone: _expiryTone(it.threshold),
                          ),
                        ],
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 20),
            // تفاصيل المخزون الحالي — 8 أعمدة بأول 500 تشغيلة (الويب 362-436)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SectionTitle(
                  i18n.t('reports', 'current_inventory'),
                  trailing: _items.length >= 500
                      ? Text(i18n.t('reports', 'first_500'),
                          style: TextStyle(
                              fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5)))
                      : null,
                ),
                if (_items.isEmpty)
                  _EmptyNote(i18n.t('reports', 'no_inventory'))
                else
                  WebTable(
                    minWidth: 1060,
                    headers: <String>[
                      i18n.t('reports', 'col_item'),
                      i18n.t('reports', 'col_batch'),
                      i18n.t('reports', 'col_branch'),
                      i18n.t('reports', 'col_available'),
                      i18n.t('reports', 'col_sale_price'),
                      i18n.t('reports', 'col_total_cost'),
                      i18n.t('reports', 'col_expiry'),
                      i18n.t('reports', 'col_status'),
                    ],
                    rows: <List<Widget>>[
                      for (final it in _items)
                        <Widget>[
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(it.productName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              if (it.genericName.isNotEmpty)
                                Text(it.genericName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: theme.colorScheme.onSurface.withOpacity(0.5))),
                            ],
                          ),
                          Text(it.batchNumber.isEmpty ? '—' : it.batchNumber,
                              textDirection: it.batchNumber.isEmpty ? null : TextDirection.ltr,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface.withOpacity(0.7))),
                          Text(it.branchName.isEmpty ? '—' : it.branchName,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface.withOpacity(0.7))),
                          Text(Fmt.number(it.quantity),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          Text(_money(it.sellingPricePiastres), style: const TextStyle(fontSize: 13)),
                          // total_cost بالخادم عمود مولّد = quantity × cost_per_unit
                          Text(_money(it.quantity * it.costPerUnitPiastres),
                              style: const TextStyle(fontSize: 13)),
                          Text(it.expiryDate == null
                              ? '—'
                              : Fmt.date(it.expiryDate, locale: i18n.locale),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface.withOpacity(0.7))),
                          Builder(builder: (BuildContext context) {
                            final (tone, label) = _detailStatus(it.status);
                            return AppBadge(label, tone: tone);
                          }),
                        ],
                    ],
                  ),
              ],
            ),
          ],
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('reports', 'inventory_title'))),
      body: body,
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
  // DETAILS_LIMIT في reports/movements/page.tsx:45
  static const int _detailsLimit = 200;

  MovementsReport? _report;
  List<StockMovementRow> _details = const <StockMovementRow>[];
  int _detailsTotal = 0;
  String _typeInput = 'all';
  String _directionInput = 'all';
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
    // أول تحميل: آخر 30 يوم (presetRange('last30') بالويب)
    final now = DateTime.now();
    _from = Fmt.isoDay(now.subtract(const Duration(days: 29)));
    _to = Fmt.isoDay(now);
    _load();
  }

  /// getMovementsReport + listStockMovements بالتوازي (Promise.all بالويب 92-104)
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final i18n = AppI18n.instance;
    try {
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        ApiClient.instance.movementsReport(from: _from, to: _to),
        ApiClient.instance.stockMovements(
          type: _typeInput == 'all' ? '' : _typeInput,
          direction: _directionInput == 'all' ? '' : _directionInput,
          from: _from ?? '',
          to: _to ?? '',
          limit: _detailsLimit,
          offset: 0,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _report = results[0] as MovementsReport;
        final det = results[1] as ({List<StockMovementRow> movements, int total});
        _details = det.movements;
        _detailsTotal = det.total;
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

  /// applyDetailFilters بالويب: إعادة تحميل التقرير والتفاصيل معًا بالفلاتر
  void _applyDetailFilters() => _load();

  /// resetDetailFilters بالويب: العودة إلى «الكل» وإعادة التحميل
  void _clearDetailFilters() {
    setState(() {
      _typeInput = 'all';
      _directionInput = 'all';
    });
    _load();
  }

  /// kpis في reports/movements/page.tsx:168-196 — قيم بإشارة ونغمة
  List<_KpiItem> _kpis(MovementsReport r) {
    final i18n = AppI18n.instance;
    final net = r.quantityIn - r.quantityOut;
    return <_KpiItem>[
      _KpiItem(
        i18n.t('reports', 'kpi_transactions'),
        Fmt.number(r.transactions),
        hint: i18n.t('reports', 'hint_movement_in_period'),
      ),
      _KpiItem(
        i18n.t('reports', 'kpi_total_in'),
        '+${Fmt.number(r.quantityIn)}',
        hint: i18n.t('reports', 'hint_base_unit'),
        tone: _KpiTone.success,
      ),
      _KpiItem(
        i18n.t('reports', 'kpi_total_out'),
        '−${Fmt.number(r.quantityOut)}',
        hint: i18n.t('reports', 'hint_base_unit'),
        tone: _KpiTone.destructive,
      ),
      _KpiItem(
        i18n.t('reports', 'kpi_net_change'),
        '${net >= 0 ? '+' : '−'}${Fmt.number(net.abs())}',
        tone: net >= 0 ? _KpiTone.success : _KpiTone.destructive,
      ),
    ];
  }

  /// movementTypeLabel في lib/movements.ts:26-30 — النوع المجهول يُعرض كما
  /// ورد من الخادم (لا إسقاط إجباري إلى type_adjustment)
  String _typeLabel(String type) {
    final i18n = AppI18n.instance;
    for (final (String v, String key) in _types) {
      if (v == type) return i18n.t('reports', key);
    }
    return type;
  }

  /// movementTypeVariant في lib/movements.ts:32-49
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

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final Color inColor = dark ? AppColors.successFgDark : AppColors.successFg; // emerald
    final Color outColor = theme.colorScheme.error;
    final r = _report;
    final Widget body;
    if (_loading && r == null) {
      body = const LoadingBox();
    } else if (_error != null && r == null) {
      body = ErrorRetry(_error!, onRetry: _load);
    } else {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (_error != null && r != null) ...<Widget>[
            ErrorBanner(_error!),
            const SizedBox(height: 12),
          ],
          Text(i18n.t('reports', 'movements_subtitle'),
              style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.55))),
          const SizedBox(height: 12),
          _PeriodPicker(onApply: (({String? from, String? to}) range) {
            _from = range.from;
            _to = range.to;
            _load();
          }),
          const SizedBox(height: 20),
          if (r != null) ...<Widget>[
            _KpiCards(_kpis(r)),
            const SizedBox(height: 20),
            // الملخص حسب النوع — 5 أعمدة بعمود صافي ونغمات (الويب 263-313)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SectionTitle(i18n.t('reports', 'summary_by_type')),
                if (r.byType.isEmpty)
                  _EmptyNote(i18n.t('reports', 'no_movements_in_period'))
                else ...<Widget>[
                  WebTable(
                    minWidth: 860,
                    headers: <String>[
                      i18n.t('reports', 'col_movement_type'),
                      i18n.t('reports', 'col_transactions'),
                      i18n.t('reports', 'col_in'),
                      i18n.t('reports', 'col_out'),
                      i18n.t('reports', 'col_net'),
                    ],
                    rows: <List<Widget>>[
                      for (final row in r.byType)
                        <Widget>[
                          AppBadge(_typeLabel(row.type), tone: _typeTone(row.type)),
                          Text(Fmt.number(row.tx), style: const TextStyle(fontSize: 13)),
                          Text(
                            row.qtyIn > 0 ? '+${Fmt.number(row.qtyIn)}' : '—',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: row.qtyIn > 0 ? inColor : theme.colorScheme.onSurface.withOpacity(0.5)),
                          ),
                          Text(
                            row.qtyOut > 0 ? '−${Fmt.number(row.qtyOut)}' : '—',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: row.qtyOut > 0 ? outColor : theme.colorScheme.onSurface.withOpacity(0.5)),
                          ),
                          Builder(builder: (BuildContext context) {
                            final net = row.qtyIn - row.qtyOut;
                            return Text(
                              '${net >= 0 ? '+' : '−'}${Fmt.number(net.abs())}',
                              style: const TextStyle(fontSize: 13),
                            );
                          }),
                        ],
                    ],
                  ),
                  // base_units_note تحت الجدول (الويب 311-313)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(i18n.t('reports', 'base_units_note'),
                        style: TextStyle(
                            fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            // تفاصيل الحركات — فلاتر نوع/اتجاه + تطبيق/مسح + جدول 8 أعمدة (316-452)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SectionTitle(i18n.t('reports', 'details_title')),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppDropdown<String>(
                        value: _typeInput,
                        items: <DropdownMenuItem<String>>[
                          DropdownMenuItem<String>(
                              value: 'all',
                              child: Text(i18n.t('reports', 'type_all'), style: const TextStyle(fontSize: 13))),
                          for (final (String v, String key) in _types)
                            DropdownMenuItem<String>(
                                value: v,
                                child: Text(i18n.t('reports', key), style: const TextStyle(fontSize: 13))),
                        ],
                        onChanged: (String? v) => setState(() => _typeInput = v ?? 'all'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppDropdown<String>(
                        value: _directionInput,
                        items: <DropdownMenuItem<String>>[
                          DropdownMenuItem<String>(
                              value: 'all',
                              child: Text(i18n.t('reports', 'dir_all'), style: const TextStyle(fontSize: 13))),
                          DropdownMenuItem<String>(
                              value: 'in',
                              child: Text(i18n.t('reports', 'dir_in'), style: const TextStyle(fontSize: 13))),
                          DropdownMenuItem<String>(
                              value: 'out',
                              child: Text(i18n.t('reports', 'dir_out'), style: const TextStyle(fontSize: 13))),
                        ],
                        onChanged: (String? v) => setState(() => _directionInput = v ?? 'all'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    WButton(
                      i18n.t('reports', 'apply'),
                      variant: WButtonVariant.secondary,
                      size: WButtonSize.sm,
                      loading: _loading,
                      onPressed: _loading ? null : _applyDetailFilters,
                    ),
                    if (_typeInput != 'all' || _directionInput != 'all') ...<Widget>[
                      const SizedBox(width: 8),
                      WButton(
                        i18n.t('reports', 'clear'),
                        variant: WButtonVariant.ghost,
                        size: WButtonSize.sm,
                        icon: Icons.restart_alt,
                        onPressed: _clearDetailFilters,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                // عدّاد التفاصيل — details_showing فوق الحد وإلا details_count
                Text(
                  _detailsTotal > _detailsLimit
                      ? i18n.t('reports', 'details_showing',
                          {'limit': Fmt.number(_detailsLimit), 'total': Fmt.number(_detailsTotal)})
                      : i18n.t('reports', 'details_count', {'count': Fmt.number(_detailsTotal)}),
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                ),
                const SizedBox(height: 8),
                if (_details.isEmpty)
                  _EmptyNote(i18n.t('reports', 'no_matching_movements'))
                else
                  WebTable(
                    minWidth: 1020,
                    headers: <String>[
                      i18n.t('reports', 'col_date'),
                      i18n.t('reports', 'col_medication'),
                      i18n.t('reports', 'col_batch'),
                      i18n.t('reports', 'col_type'),
                      i18n.t('reports', 'col_quantity'),
                      i18n.t('reports', 'col_balance_after'),
                      i18n.t('reports', 'col_by'),
                      i18n.t('reports', 'col_branch'),
                    ],
                    rows: <List<Widget>>[
                      for (final m in _details)
                        <Widget>[
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(_fmtDay(m.createdAt),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurface.withOpacity(0.8))),
                              Text(_fmtClock(m.createdAt, padHour: true),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: theme.colorScheme.onSurface.withOpacity(0.5))),
                            ],
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(m.productName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              if ((m.reason != null && m.reason!.isNotEmpty) ||
                                  (m.notes != null && m.notes!.isNotEmpty))
                                Text(
                                  (m.reason != null && m.reason!.isNotEmpty) ? m.reason! : m.notes!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: theme.colorScheme.onSurface.withOpacity(0.5)),
                                ),
                            ],
                          ),
                          Text((m.batchNumber == null || m.batchNumber!.isEmpty)
                              ? '—'
                              : m.batchNumber!,
                              textDirection: (m.batchNumber == null || m.batchNumber!.isEmpty)
                                  ? null
                                  : TextDirection.ltr,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface.withOpacity(0.7))),
                          AppBadge(_typeLabel(m.movementType), tone: _typeTone(m.movementType)),
                          // الكمية: سهم + إشارة + عدد مطلق ملون (emerald/destructive)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                m.quantity >= 0 ? Icons.south_west : Icons.north_east,
                                size: 14,
                                color: m.quantity >= 0 ? inColor : outColor,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '${m.quantity >= 0 ? '+' : '−'}${_quantityText(m.quantity, m.unit)}',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: m.quantity >= 0 ? inColor : outColor),
                              ),
                            ],
                          ),
                          Text(m.quantityAfter == null
                              ? '—'
                              : _quantityText(m.quantityAfter!, m.unit),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface.withOpacity(0.7))),
                          Text((m.actorName == null || m.actorName!.isEmpty) ? '—' : m.actorName!,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface.withOpacity(0.7))),
                          Text((m.branchName == null || m.branchName!.isEmpty) ? '—' : m.branchName!,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface.withOpacity(0.7))),
                        ],
                    ],
                  ),
              ],
            ),
          ],
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(i18n.t('reports', 'movements_title'))),
      body: body,
    );
  }
}

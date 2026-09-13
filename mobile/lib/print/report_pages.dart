// المرحلة 4 — تمكين الطباعة للتقارير في الموبايل.
//
// بنّائات صفحات A4 المشتركة لكل التقارير (مبيعات/مخزون/حركات): نفس مبدأ
// report_exporter — الصفحات ويدجت Flutter تُلتقط RepaintBoundary → PDF A4
// → طباعة نظام (layoutPdf) أو مشاركة (sharePdf). العربية آمنة 100% لأن
// التشكيل لمحرك نصوص Flutter — لا نص عربي داخل مكتبة PDF إطلاقًا.
//
// كل البنّائات هنا دوال نقية من البيانات → ويدجت (بلا شبكة ولا حالة)،
// وملوّنة بألوان ثابتة للطباعة على ورق أبيض (لا تبعثemes الوضع الداكن).
import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'report_exporter.dart' show kReportPageWidth, kReportPageHeight;

/// عرض المحتوى داخل الصفحة (794 − حاشيتا 40)
const double kReportContentWidth = kReportPageWidth - 80;

// ------------------------------------------------------------- تنسيق مشترك

/// أنماط خلايا الجداول — كانت _exCell داخل شاشة المبيعات ومُعمَّمة الآن
TextStyle reportCellStyle({double size = 10.5, FontWeight? w, Color? color, bool dim = false}) {
  return TextStyle(
      fontSize: size,
      fontWeight: w,
      color: color ?? (dim ? Colors.black45 : Colors.black87));
}

/// جدول التقرير على الورق — رأس باهت عريض + خطوط داخلية خافتة
Widget reportTable({
  required List<String> header,
  required Map<int, TableColumnWidth> columnWidths,
  required List<List<Widget>> rows,
}) {
  final List<Widget> cells = header
      .map((String h) => Text(h,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.black54)))
      .toList();
  return Table(
    columnWidths: columnWidths,
    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
    border: const TableBorder(
      horizontalInside: BorderSide(color: Color(0x14000000)),
      bottom: BorderSide(color: Color(0x24000000)),
    ),
    children: <TableRow>[
      TableRow(
        children: <Widget>[
          for (final Widget c in cells)
            Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4), child: c),
        ],
      ),
      for (final List<Widget> row in rows)
        TableRow(
          children: <Widget>[
            for (final Widget c in row)
              Padding(padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4), child: c),
          ],
        ),
    ],
  );
}

/// شبكة المؤشرات على الورق — بطاقتان بالصف (نفس _exportKpis السابق)
Widget reportKpiGrid(List<({String label, String value, String? hint})> kpis) {
  return Wrap(
    spacing: 10,
    runSpacing: 10,
    children: <Widget>[
      for (final ({String label, String value, String? hint}) k in kpis)
        SizedBox(
          width: (kReportContentWidth - 10) / 2,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0x1F000000)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(k.label,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.black54)),
                const SizedBox(height: 4),
                Text(k.value,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black87)),
                if (k.hint != null && k.hint!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(k.hint!,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 9, color: Colors.black38)),
                  ),
              ],
            ),
          ),
        ),
    ],
  );
}

/// رأس الصفحة الأولى: اسم الصيدلية + عنوان التقرير + الفترة + زمن الإنشاء
Widget reportHeader({
  required String pharmacyName,
  required String title,
  String? periodText,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      if (pharmacyName.isNotEmpty)
        Text(pharmacyName,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.black87)),
      Text(title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.brandGreen)),
      if (periodText != null && periodText.isNotEmpty) ...<Widget>[
        const SizedBox(height: 4),
        Text(periodText, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
      Text(
          '${reportDayLabel(Fmt.isoDay(DateTime.now()))} · ${reportClockLabel(DateTime.now().toIso8601String())}',
          style: const TextStyle(fontSize: 9.5, color: Colors.black38)),
      const SizedBox(height: 8),
      Container(
        height: 3,
        width: 56,
        decoration: BoxDecoration(
          color: AppColors.brandGreen,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ],
  );
}

/// عنوان قسم فوق الجداول في الصفحات التالية + ملاحظة اختيارية (الحد/العدّ)
Widget reportSectionTitle(String title, {String? note}) {
  return Row(
    children: <Widget>[
      Expanded(
        child: Text(title,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.black87)),
      ),
      if (note != null && note.isNotEmpty)
        Text(note, style: const TextStyle(fontSize: 9, color: Colors.black38)),
    ],
  );
}

/// تقسيم صفوف الجدول على صفحات بمقدار [size]
List<List<T>> chunkReportRows<T>(List<T> rows, int size) {
  if (rows.isEmpty) return <List<T>>[];
  final List<List<T>> chunks = <List<T>>[];
  for (int start = 0; start < rows.length; start += size) {
    final int end = (start + size).clamp(0, rows.length);
    chunks.add(rows.sublist(start, end));
  }
  return chunks;
}

/// غلاف كل صفحة: مقاس A4 ثابت + اتجاه اللغة + تذييل (المصدر + ترقيم)
List<Widget> wrapReportPages(List<Widget> contents, {required String footer}) {
  final TextDirection dir = AppI18n.instance.isRtl ? TextDirection.rtl : TextDirection.ltr;
  return <Widget>[
    for (int i = 0; i < contents.length; i++)
      Directionality(
        textDirection: dir,
        child: Container(
          width: kReportPageWidth,
          height: kReportPageHeight,
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(40, 36, 40, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: contents[i]),
              const SizedBox(height: 8),
              Row(children: <Widget>[
                Expanded(
                  child: Text(footer,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 9, color: Colors.black38)),
                ),
                Text('${i + 1} / ${contents.length}',
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontSize: 9, color: Colors.black38)),
              ]),
            ],
          ),
        ),
      ),
  ];
}

// ------------------------------------------------------- تسميات زمنية مشتركة

const List<String> _monthsShortAr = <String>[
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];
const List<String> _monthsShortEn = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// «5 سبتمبر 2026» — كانت _fmtDayStr داخل شاشة المبيعات
String reportDayLabel(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  final months = AppI18n.instance.locale == 'ar' ? _monthsShortAr : _monthsShortEn;
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

/// ساعة 12 بصيغة ص/م — كانت _fmtClock داخل شاشة المبيعات
String reportClockLabel(String iso, {bool padHour = false}) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '—';
  final ar = AppI18n.instance.locale == 'ar';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final hh = padHour ? h.toString().padLeft(2, '0') : '$h';
  final mm = d.minute.toString().padLeft(2, '0');
  final period = ar ? (d.hour < 12 ? 'ص' : 'م') : (d.hour < 12 ? 'am' : 'pm');
  return '$hh:$mm $period';
}

/// «12 شريط» — الكمية المطلقة مع تسمية الوحدة المترجمة
String quantityTextWithUnit(num quantity, String unit) {
  final String unitLabel = switch (unit) {
    'strip' => AppI18n.instance.t('movements', 'unit_strip'),
    'box' => AppI18n.instance.t('movements', 'unit_box'),
    _ => unit,
  };
  return '${Fmt.number(quantity.abs())} $unitLabel';
}

// ------------------------------------------------------- تقرير المخزون (A4)

/// صفحات تقرير المخزون: رأس + مؤشرات + مجموعات الصلاحية، النواقص،
/// الصلاحيات القريبة، ثم تفاصيل المخزون الحالي مقسمة صفوفًا.
List<Widget> buildInventoryReportPages({
  required InventoryReport report,
  required List<InventoryItem> items,
  required String pharmacyName,
  String? detailsNote,
  int rowsPerPage = 16,
}) {
  final AppI18n i18n = AppI18n.instance;
  final InventoryReport r = report;
  final List<Widget> contents = <Widget>[];

  // — صفحة 1: الرأس + المؤشرات + مجموعات الصلاحية + قيمة المخزون المنتهي
  contents.add(Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      reportHeader(
        pharmacyName: pharmacyName,
        title: i18n.t('reports', 'inventory_title'),
      ),
      const SizedBox(height: 14),
      reportKpiGrid(<({String label, String value, String? hint})>[
        (
          label: i18n.t('reports', 'kpi_cost_value'),
          value: Fmt.money(r.costValue, locale: i18n.locale),
          hint: i18n.t('reports', 'hint_batches_products',
              {'batches': Fmt.number(r.batchesCount), 'products': Fmt.number(r.productsCount)}),
        ),
        (
          label: i18n.t('reports', 'kpi_retail_value'),
          value: Fmt.money(r.retailValue, locale: i18n.locale),
          hint: i18n.t('reports', 'hint_units_base', {'count': Fmt.number(r.unitsBase)}),
        ),
        (
          label: i18n.t('reports', 'kpi_low_items'),
          value: Fmt.number(r.lowStockCount),
          hint: i18n.t('reports', 'hint_at_or_below_min'),
        ),
        (
          label: i18n.t('reports', 'kpi_out_items'),
          value: Fmt.number(r.outOfStockCount),
          hint: null,
        ),
      ]),
      const SizedBox(height: 16),
      reportSectionTitle(i18n.t('reports', 'expiry_section')),
      const SizedBox(height: 10),
      Row(children: <Widget>[
        Expanded(child: _invBucket(i18n.t('reports', 'expiry_expired'), r.expiredCount,
            const Color(0xFFB91C1C))),
        const SizedBox(width: 10),
        Expanded(child: _invBucket(i18n.t('reports', 'expiry_30'), r.expiring30,
            const Color(0xFFB45309))),
      ]),
      const SizedBox(height: 10),
      Row(children: <Widget>[
        Expanded(child: _invBucket(i18n.t('reports', 'expiry_31_60'), r.expiring60,
            Colors.black54)),
        const SizedBox(width: 10),
        Expanded(child: _invBucket(i18n.t('reports', 'expiry_61_90'), r.expiring90,
            Colors.black54)),
      ]),
      if (r.expiredValue > 0 || r.expiringValue > 0)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 12, color: Colors.black45),
              children: <InlineSpan>[
                TextSpan(text: '${i18n.t('reports', 'expired_value_label')} '),
                TextSpan(
                  text: Fmt.money(r.expiredValue, locale: i18n.locale),
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFB91C1C)),
                ),
                TextSpan(text: ' · ${i18n.t('reports', 'expiring_value_label')} '),
                TextSpan(
                  text: Fmt.money(r.expiringValue, locale: i18n.locale),
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87),
                ),
              ],
            ),
          ),
        ),
    ],
  ));

  // — صفحات النواقص (تُحذف إن لم توجد بيانات)
  for (final List<InventoryAlertItem> chunk in chunkReportRows(r.lowStockItems, rowsPerPage)) {
    contents.add(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        reportSectionTitle(i18n.t('reports', 'low_stock_list')),
        const SizedBox(height: 10),
        reportTable(
          header: <String>[
            i18n.t('reports', 'col_item'),
            i18n.t('reports', 'col_batch'),
            i18n.t('reports', 'col_branch'),
            i18n.t('reports', 'col_available'),
            i18n.t('reports', 'col_min'),
            i18n.t('reports', 'col_status'),
          ],
          columnWidths: const <int, TableColumnWidth>{
            0: FlexColumnWidth(),
            1: FixedColumnWidth(84),
            2: FixedColumnWidth(92),
            3: FixedColumnWidth(66),
            4: FixedColumnWidth(56),
            5: FixedColumnWidth(78),
          },
          rows: <List<Widget>>[
            for (final InventoryAlertItem it in chunk) ...<List<Widget>>[
              <Widget>[
                _itemCell(it.name, it.genericName),
                _ltrText(it.batchNumber.isEmpty ? '—' : it.batchNumber),
                _plainText(it.branchName.isEmpty ? '—' : it.branchName),
                Text(Fmt.number(it.quantity),
                    style: reportCellStyle(w: FontWeight.w700)),
                Text(Fmt.number(it.threshold), style: reportCellStyle(dim: true)),
                Text(it.quantity <= 0
                        ? i18n.t('reports', 'status_out')
                        : i18n.t('reports', 'status_low'),
                    style: reportCellStyle(
                        size: 10,
                        w: FontWeight.w700,
                        color: it.quantity <= 0 ? const Color(0xFFB91C1C) : const Color(0xFFB45309))),
              ],
            ],
          ],
        ),
      ],
    ));
  }

  // — صفحات الصلاحيات القريبة (تُحذف إن لم توجد بيانات)
  for (final List<InventoryAlertItem> chunk in chunkReportRows(r.expiringItems, rowsPerPage)) {
    contents.add(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        reportSectionTitle(i18n.t('reports', 'expiry_list')),
        const SizedBox(height: 10),
        reportTable(
          header: <String>[
            i18n.t('reports', 'col_item'),
            i18n.t('reports', 'col_batch'),
            i18n.t('reports', 'col_available'),
            i18n.t('reports', 'col_expiry_date'),
            i18n.t('reports', 'col_days_left'),
          ],
          columnWidths: const <int, TableColumnWidth>{
            0: FlexColumnWidth(),
            1: FixedColumnWidth(84),
            2: FixedColumnWidth(66),
            3: FixedColumnWidth(92),
            4: FixedColumnWidth(84),
          },
          rows: <List<Widget>>[
            for (final InventoryAlertItem it in chunk) ...<List<Widget>>[
              <Widget>[
                _itemCell(it.name, it.genericName),
                _ltrText(it.batchNumber.isEmpty ? '—' : it.batchNumber),
                Text(Fmt.number(it.quantity), style: reportCellStyle()),
                _plainText(it.extraDate == null ? '—' : Fmt.date(it.extraDate, locale: i18n.locale)),
                Text(it.threshold <= 0
                        ? i18n.t('reports', 'batch_expired')
                        : i18n.t('reports', 'days_left', {'count': Fmt.number(it.threshold)}),
                    style: reportCellStyle(
                        size: 10,
                        w: FontWeight.w700,
                        color: it.threshold <= 0
                            ? const Color(0xFFB91C1C)
                            : (it.threshold <= 30 ? const Color(0xFFB45309) : Colors.black54))),
              ],
            ],
          ],
        ),
      ],
    ));
  }

  // — صفحات تفاصيل المخزون الحالي (8 أعمدة)
  for (final List<InventoryItem> chunk in chunkReportRows(items, rowsPerPage)) {
    contents.add(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        reportSectionTitle(i18n.t('reports', 'current_inventory'), note: detailsNote),
        const SizedBox(height: 10),
        reportTable(
          header: <String>[
            i18n.t('reports', 'col_item'),
            i18n.t('reports', 'col_batch'),
            i18n.t('reports', 'col_branch'),
            i18n.t('reports', 'col_available'),
            i18n.t('reports', 'col_sale_price'),
            i18n.t('reports', 'col_total_cost'),
            i18n.t('reports', 'col_expiry'),
            i18n.t('reports', 'col_status'),
          ],
          columnWidths: const <int, TableColumnWidth>{
            0: FlexColumnWidth(),
            1: FixedColumnWidth(78),
            2: FixedColumnWidth(86),
            3: FixedColumnWidth(62),
            4: FixedColumnWidth(78),
            5: FixedColumnWidth(78),
            6: FixedColumnWidth(84),
            7: FixedColumnWidth(76),
          },
          rows: <List<Widget>>[
            for (final InventoryItem it in chunk) ...<List<Widget>>[
              <Widget>[
                _itemCell(it.productName, it.genericName),
                _ltrText(it.batchNumber.isEmpty ? '—' : it.batchNumber),
                _plainText(it.branchName.isEmpty ? '—' : it.branchName),
                Text(Fmt.number(it.quantity),
                    style: reportCellStyle(w: FontWeight.w700)),
                Text(Fmt.money(it.sellingPricePiastres, locale: i18n.locale),
                    style: reportCellStyle(size: 10)),
                // total_cost = quantity × cost_per_unit (عمود generated بالخادم)
                Text(Fmt.money(it.quantity * it.costPerUnitPiastres, locale: i18n.locale),
                    style: reportCellStyle(size: 10)),
                _plainText(it.expiryDate == null ? '—' : Fmt.date(it.expiryDate, locale: i18n.locale)),
                Builder(builder: (BuildContext context) {
                  final (String label, Color color) = _invStatus(i18n, it.status);
                  return Text(label, style: reportCellStyle(size: 10, w: FontWeight.w700, color: color));
                }),
              ],
            ],
          ],
        ),
      ],
    ));
  }

  final String footer = pharmacyName.isNotEmpty ? pharmacyName : 'Pharmacy OS';
  return wrapReportPages(contents, footer: footer);
}

/// بلاطة مجموعة صلاحية على الورق — حدود ملوّنة وعدّ بارز
Widget _invBucket(String label, int count, Color color) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0x24000000)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.black54)),
        const SizedBox(height: 6),
        Text(Fmt.number(count),
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: color)),
      ],
    ),
  );
}

/// (تسمية، لون) حالة التشغيلة للورق — مطابقة statusBadgeKeys بالويب
(String, Color) _invStatus(AppI18n i18n, String status) {
  switch (status.toLowerCase()) {
    case 'low_stock':
      return (i18n.t('reports', 'status_low'), const Color(0xFFB45309));
    case 'out_of_stock':
      return (i18n.t('reports', 'status_out'), const Color(0xFFB91C1C));
    case 'expiring_soon':
      return (i18n.t('reports', 'status_expiring_soon'), const Color(0xFFB45309));
    case 'quarantined':
      return (i18n.t('reports', 'status_quarantined'), const Color(0xFFB45309));
    default:
      return (i18n.t('reports', 'status_normal'), Colors.black45);
  }
}

Widget _itemCell(String name, String genericName) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text(name,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: reportCellStyle(w: FontWeight.w700)),
      if (genericName.isNotEmpty)
        Text(genericName,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: reportCellStyle(size: 9.5, dim: true)),
    ],
  );
}

Widget _ltrText(String text) {
  return Text(text,
      textDirection: TextDirection.ltr,
      style: reportCellStyle(size: 10, dim: true));
}

Widget _plainText(String text) {
  return Text(text,
      maxLines: 1, overflow: TextOverflow.ellipsis,
      style: reportCellStyle(size: 10, dim: true));
}

// ------------------------------------------------------- تقرير الحركات (A4)

/// صفحات تقرير الحركات: رأس + مؤشرات + ملخص بالنوع، ثم تفاصيل الحركات
/// مقسمة صفوفًا. [typeLabel] يمرَّر من الشاشة (قائمة الأنواع المعروفة هناك).
List<Widget> buildMovementsReportPages({
  required MovementsReport report,
  required List<StockMovementRow> details,
  required int detailsTotal,
  required String? fromIso,
  required String? toIso,
  required String pharmacyName,
  required String Function(String type) typeLabel,
  String? detailsLimitNote,
  int rowsPerPage = 14,
}) {
  final AppI18n i18n = AppI18n.instance;
  final MovementsReport r = report;
  final int net = r.quantityIn - r.quantityOut;
  final List<Widget> contents = <Widget>[];

  // — صفحة 1: الرأس + المؤشرات + الملخص بالنوع
  contents.add(Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      reportHeader(
        pharmacyName: pharmacyName,
        title: i18n.t('reports', 'movements_title'),
        periodText: (fromIso != null || toIso != null)
            ? '${reportDayLabel(fromIso ?? '')} – ${reportDayLabel(toIso ?? '')}'
            : null,
      ),
      const SizedBox(height: 14),
      reportKpiGrid(<({String label, String value, String? hint})>[
        (
          label: i18n.t('reports', 'kpi_transactions'),
          value: Fmt.number(r.transactions),
          hint: i18n.t('reports', 'hint_movement_in_period'),
        ),
        (
          label: i18n.t('reports', 'kpi_total_in'),
          value: '+${Fmt.number(r.quantityIn)}',
          hint: i18n.t('reports', 'hint_base_unit'),
        ),
        (
          label: i18n.t('reports', 'kpi_total_out'),
          value: '−${Fmt.number(r.quantityOut)}',
          hint: i18n.t('reports', 'hint_base_unit'),
        ),
        (
          label: i18n.t('reports', 'kpi_net_change'),
          value: '${net >= 0 ? '+' : '−'}${Fmt.number(net.abs())}',
          hint: null,
        ),
      ]),
      const SizedBox(height: 16),
      reportSectionTitle(i18n.t('reports', 'summary_by_type')),
      const SizedBox(height: 10),
      if (r.byType.isEmpty)
        Text(i18n.t('reports', 'no_movements_in_period'),
            style: const TextStyle(fontSize: 11, color: Colors.black45))
      else ...<Widget>[
        reportTable(
          header: <String>[
            i18n.t('reports', 'col_movement_type'),
            i18n.t('reports', 'col_transactions'),
            i18n.t('reports', 'col_in'),
            i18n.t('reports', 'col_out'),
            i18n.t('reports', 'col_net'),
          ],
          columnWidths: const <int, TableColumnWidth>{
            0: FlexColumnWidth(),
            1: FixedColumnWidth(84),
            2: FixedColumnWidth(92),
            3: FixedColumnWidth(92),
            4: FixedColumnWidth(92),
          },
          rows: <List<Widget>>[
            for (final ({String type, int tx, int qtyIn, int qtyOut}) row in r.byType) ...<List<Widget>>[
              <Widget>[
                Text(typeLabel(row.type),
                    style: reportCellStyle(size: 10, w: FontWeight.w700)),
                Text(Fmt.number(row.tx), style: reportCellStyle()),
                Text(row.qtyIn > 0 ? '+${Fmt.number(row.qtyIn)}' : '—',
                    style: reportCellStyle(
                        w: FontWeight.w700,
                        color: row.qtyIn > 0 ? const Color(0xFF047857) : Colors.black38)),
                Text(row.qtyOut > 0 ? '−${Fmt.number(row.qtyOut)}' : '—',
                    style: reportCellStyle(
                        w: FontWeight.w700,
                        color: row.qtyOut > 0 ? const Color(0xFFB91C1C) : Colors.black38)),
                Builder(builder: (BuildContext context) {
                  final int rowNet = row.qtyIn - row.qtyOut;
                  return Text('${rowNet >= 0 ? '+' : '−'}${Fmt.number(rowNet.abs())}',
                      style: reportCellStyle());
                }),
              ],
            ],
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(i18n.t('reports', 'base_units_note'),
              style: const TextStyle(fontSize: 10, color: Colors.black38)),
        ),
      ],
    ],
  ));

  // — صفحات التفاصيل (8 أعمدة)
  for (final List<StockMovementRow> chunk in chunkReportRows(details, rowsPerPage)) {
    contents.add(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        reportSectionTitle(i18n.t('reports', 'details_title'), note: detailsLimitNote),
        const SizedBox(height: 10),
        reportTable(
          header: <String>[
            i18n.t('reports', 'col_date'),
            i18n.t('reports', 'col_medication'),
            i18n.t('reports', 'col_batch'),
            i18n.t('reports', 'col_type'),
            i18n.t('reports', 'col_quantity'),
            i18n.t('reports', 'col_balance_after'),
            i18n.t('reports', 'col_by'),
            i18n.t('reports', 'col_branch'),
          ],
          columnWidths: const <int, TableColumnWidth>{
            0: FixedColumnWidth(76),
            1: FlexColumnWidth(),
            2: FixedColumnWidth(72),
            3: FixedColumnWidth(88),
            4: FixedColumnWidth(84),
            5: FixedColumnWidth(66),
            6: FixedColumnWidth(78),
            7: FixedColumnWidth(78),
          },
          rows: <List<Widget>>[
            for (final StockMovementRow m in chunk) ...<List<Widget>>[
              <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(reportDayLabel(m.createdAt), style: reportCellStyle(size: 9.5)),
                    Text(reportClockLabel(m.createdAt, padHour: true),
                        style: reportCellStyle(size: 9, dim: true)),
                  ],
                ),
                _itemCell(m.productName,
                    (m.reason != null && m.reason!.isNotEmpty) ? m.reason! : (m.notes ?? '')),
                _ltrText((m.batchNumber == null || m.batchNumber!.isEmpty) ? '—' : m.batchNumber!),
                Text(typeLabel(m.movementType),
                    style: reportCellStyle(size: 10, w: FontWeight.w700)),
                Text(
                  '${m.quantity >= 0 ? '+' : '−'}${quantityTextWithUnit(m.quantity, m.unit)}',
                  style: reportCellStyle(
                      size: 10,
                      w: FontWeight.w700,
                      color: m.quantity >= 0 ? const Color(0xFF047857) : const Color(0xFFB91C1C)),
                ),
                Text(m.quantityAfter == null
                        ? '—'
                        : quantityTextWithUnit(m.quantityAfter!, m.unit),
                    style: reportCellStyle(size: 9.5, dim: true)),
                _plainText((m.actorName == null || m.actorName!.isEmpty) ? '—' : m.actorName!),
                _plainText((m.branchName == null || m.branchName!.isEmpty) ? '—' : m.branchName!),
              ],
            ],
          ],
        ),
      ],
    ));
  }

  final String footer = pharmacyName.isNotEmpty ? pharmacyName : 'Pharmacy OS';
  return wrapReportPages(contents, footer: footer);
}

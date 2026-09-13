// المرحلة 4 — اختبار تمكين الطباعة للتقارير في الموبايل:
//   1) مفاتيح الطباعة موجودة في اللغات الثماني (print_report / print_failed).
//   2) chunkReportRows يقسّم صفوف الجداول بإنصاف (فراغ/قسمة تامة/بواقي).
//   3) wrapReportPages يغلّف كل صفحة بمقاس A4 وتذييل ترقيم «i / N» واتجاه اللغة.
//   4) buildInventoryReportPages: صفحة رأس+مؤشرات+صلاحيات + صفحات النواقص
//      والصلاحيات القريبة (تُحذف فارغة) + تفاصيل المخزون مقسمة.
//   5) buildMovementsReportPages: صفحة الملخص بالنوع + صفحات تفاصيل بالسهم
//      والإشارة والوحدة، وملاحظة الحد عند تجاوزه.
//   6) reportDayLabel/reportClockLabel/quantityTextWithUnit مطابقة الأصل.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_mobile/core/strings.dart';
import 'package:pharmacy_mobile/models/models.dart';
import 'package:pharmacy_mobile/print/report_pages.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await AppI18n.instance.setLocale('ar');
  });

  test('مفاتيح الطباعة موجودة وغير فارغة في اللغات الثماني', () {
    final AppI18n i18n = AppI18n.instance;
    for (final String code in AppI18n.locales) {
      i18n.setLocale(code);
      expect(i18n.t('reports', 'print_report'), isNotEmpty,
          reason: '$code بلا print_report');
      expect(i18n.t('reports', 'print_failed'), isNotEmpty,
          reason: '$code بلا print_failed');
    }
  });

  test('chunkReportRows — فراغ / قسمة تامة / بواقي', () {
    expect(chunkReportRows<int>(<int>[], 5), isEmpty);
    expect(chunkReportRows<int>(<int>[1, 2, 3, 4, 5], 5), <List<int>>[
      <int>[1, 2, 3, 4, 5],
    ]);
    expect(chunkReportRows<int>(<int>[1, 2, 3, 4, 5, 6, 7], 3), <List<int>>[
      <int>[1, 2, 3],
      <int>[4, 5, 6],
      <int>[7],
    ]);
  });

  testWidgets('wrapReportPages — غلاف A4 + ترقيم + تذييل', (WidgetTester tester) async {
    final List<Widget> pages = wrapReportPages(
      <Widget>[const Text('صفحة أولى'), const Text('صفحة ثانية')],
      footer: 'صيدلية النور',
    );
    expect(pages.length, 2);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: Column(children: pages)),
      ),
    ));
    expect(find.text('صفحة أولى'), findsOneWidget);
    expect(find.text('صفحة ثانية'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('صيدلية النور'), findsNWidgets(2));
  });

  testWidgets('buildInventoryReportPages — رأس + نواقص + صلاحيات + تفاصيل مقسمة',
      (WidgetTester tester) async {
    InventoryAlertItem alert({
      required String name,
      required int quantity,
      required int threshold,
      String status = 'low_stock',
      String? extraDate,
    }) =>
        InventoryAlertItem(
          name: name,
          genericName: '',
          batchNumber: 'B1',
          branchName: 'الفرع الرئيسي',
          quantity: quantity,
          threshold: threshold,
          sellingPricePiastres: 1000,
          status: status,
          extraDate: extraDate,
        );

    final InventoryReport report = InventoryReport(
      batchesCount: 12,
      productsCount: 8,
      unitsBase: 340,
      costValue: 120000,
      retailValue: 190000,
      lowStockCount: 3,
      outOfStockCount: 1,
      expiredCount: 1,
      expiring30: 2,
      expiring60: 0,
      expiring90: 0,
      expiredValue: 5000,
      expiringValue: 9000,
      lowStockItems: <InventoryAlertItem>[
        alert(name: 'أدوية ناقصة أ', quantity: 2, threshold: 5),
        alert(name: 'أدوية ناقصة ب', quantity: 0, threshold: 3),
        alert(name: 'أدوية ناقصة ج', quantity: 4, threshold: 6),
      ],
      expiringItems: <InventoryAlertItem>[
        alert(name: 'قريب الانتهاء أ', quantity: 6, threshold: 0, extraDate: '2026-09-01'),
        alert(name: 'قريب الانتهاء ب', quantity: 3, threshold: 12, extraDate: '2026-10-01'),
      ],
    );

    InventoryItem item(int i) => InventoryItem(
          batchId: 'b$i',
          pharmacyProductId: 'p$i',
          productName: 'منتج $i',
          genericName: '',
          brandName: '',
          barcode: '',
          dosageForm: '',
          strength: '',
          batchNumber: 'B$i',
          unit: 'strip',
          branchName: 'الفرع الرئيسي',
          status: i == 0 ? 'out_of_stock' : 'normal',
          quantity: i,
          costPerUnitPiastres: 500,
          sellingPricePiastres: 1000,
          partialSellingPricePiastres: 300,
          unitsPerBox: 4,
          minStockLevel: 5,
          packagingType: 'BOX_STRIP',
        );

    // 40 تشغيلة → صفحة + 1 نواقص + 1 صلاحيات + ceil(40/16)=3 تفاصيل = 6 صفحات
    final List<Widget> pages = buildInventoryReportPages(
      report: report,
      items: List<InventoryItem>.generate(40, item),
      pharmacyName: 'صيدلية النور',
      detailsNote: 'أول 500',
    );
    expect(pages.length, 6);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: Column(children: pages)),
      ),
    ));
    expect(find.textContaining('تقرير المخزون'), findsWidgets);
    expect(find.textContaining('منتج 1'), findsWidgets);
    expect(find.text(AppI18n.instance.t('reports', 'status_out')), findsWidgets);
    expect(find.text('3 / 6'), findsOneWidget);
  });

  testWidgets('buildInventoryReportPages — بلا نواقص أو صلاحيات تُحذف صفحاتها',
      (WidgetTester tester) async {
    final InventoryReport report = InventoryReport(
      batchesCount: 0,
      productsCount: 0,
      unitsBase: 0,
      costValue: 0,
      retailValue: 0,
      lowStockCount: 0,
      outOfStockCount: 0,
      expiredCount: 0,
      expiring30: 0,
      expiring60: 0,
      expiring90: 0,
      expiredValue: 0,
      expiringValue: 0,
      lowStockItems: const <InventoryAlertItem>[],
      expiringItems: const <InventoryAlertItem>[],
    );
    final List<Widget> pages = buildInventoryReportPages(
      report: report,
      items: const <InventoryItem>[],
      pharmacyName: '',
    );
    // الصفحة الأولى فقط (رأس + مؤشرات + مجموعات صلاحية صفرية)
    expect(pages.length, 1);
  });

  testWidgets('buildMovementsReportPages — ملخص بالنوع + تفاصيل + ملاحظة الحد',
      (WidgetTester tester) async {
    final MovementsReport report = MovementsReport(
      transactions: 5,
      quantityIn: 120,
      quantityOut: 70,
      byType: <({String type, int tx, int qtyIn, int qtyOut})>[
        (type: 'sale', tx: 3, qtyIn: 0, qtyOut: 50),
        (type: 'purchase', tx: 2, qtyIn: 120, qtyOut: 0),
      ],
    );

    StockMovementRow row(int i) => StockMovementRow(
          id: 'm$i',
          movementType: i.isEven ? 'sale' : 'purchase',
          productName: 'حركة $i',
          quantity: i.isEven ? -(i + 1) : (i + 1),
          unit: 'strip',
          createdAt: '2026-09-13T14:30:00Z',
          quantityAfter: 100,
        );

    final List<Widget> pages = buildMovementsReportPages(
      report: report,
      details: List<StockMovementRow>.generate(30, row), // 30 ← 14+14+2
      detailsTotal: 120,
      fromIso: '2026-08-15',
      toIso: '2026-09-14',
      pharmacyName: 'صيدلية النور',
      typeLabel: (String t) => t == 'sale' ? 'بيع' : 'شراء',
      detailsLimitNote: 'يُعرض 200 من 120',
    );
    expect(pages.length, 4); // صفحة الملخص + 3 صفحات تفاصيل

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: Column(children: pages)),
      ),
    ));
    expect(find.textContaining('تقرير حركات المخزون'), findsWidgets);
    expect(find.textContaining('حركة 1'), findsWidgets);
    expect(find.text('شراء'), findsWidgets); // نوع مُمرَّر من الشاشة
    expect(find.text('4 / 4'), findsOneWidget);
  });

  test('reportDayLabel / reportClockLabel / quantityTextWithUnit مطابقة الأصل',
      () async {
    final AppI18n i18n = AppI18n.instance;
    await i18n.setLocale('ar');
    expect(reportDayLabel('2026-09-05'), '5 سبتمبر 2026');
    expect(reportDayLabel('ليس تاريخًا'), 'ليس تاريخًا');
    expect(reportClockLabel('2026-09-05T14:30:00Z'), isNot('—'));
    expect(reportClockLabel(' garbage'), '—');

    // الوحدة المترجمة عبر نطاق movements والمجهولة كما وردت
    expect(quantityTextWithUnit(12, 'strip'), contains('12'));
    expect(quantityTextWithUnit(12, 'strip'), contains(i18n.t('movements', 'unit_strip')));
    expect(quantityTextWithUnit(7, 'mystery_unit'), '7 mystery_unit');

    await i18n.setLocale('en');
    expect(reportDayLabel('2026-09-05'), '5 Sep 2026');
    expect(reportClockLabel('2026-09-05T09:05:00Z'), contains('am'));
    await i18n.setLocale('ar');
  });
}

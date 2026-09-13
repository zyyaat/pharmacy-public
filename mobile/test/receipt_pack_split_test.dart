// اختبار انحدار تفكيك الكمية على أكبر وحدة صحيحة في الإيصال («2 علبة × 40 /
// 3 شريط × 10»): يثبت أن مجموع مبالغ سطور الصنف = مبلغ الصنف حرفياً في كل
// الحالات، وأن التسميات والأسعار تُشتق صحيحاً للبيع بالشريط والعلبة، وأن
// المنتج بلا تغليف فعلية يبقى سطراً واحداً كما هو — مطابق receipt-template.tsx.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pharmacy_mobile/core/strings.dart';
import 'package:pharmacy_mobile/models/models.dart';
import 'package:pharmacy_mobile/print/receipt_template.dart';

SaleItemRow _item({
  required String saleUnit,
  required int unitsPerBox,
  required int quantityBase,
  required int unitPrice,
  required int amount,
}) {
  return SaleItemRow(
    saleItemId: 'si',
    productId: 'p',
    productName: 'علاج',
    genericName: '',
    strength: '',
    barcode: '',
    packagingType: 'BOX_STRIP',
    saleUnit: saleUnit,
    batchNumber: 'b',
    unitsPerBox: unitsPerBox,
    quantityBase: quantityBase,
    unitPricePiastres: unitPrice,
    amountPiastres: amount,
    returnedQuantityBase: 0,
    returnableQuantityBase: quantityBase,
    returnedAmountPiastres: 0,
  );
}

ReceiptSettings _settings(int paperWidthMm) => ReceiptSettings(
      paperWidthMm: paperWidthMm,
      printMode: 'manual',
      copies: 1,
      namePrefix: '',
      thankYouText: '',
      returnPolicyText: '',
      showPhone: false,
      showAddress: false,
      showCashier: false,
      showThankYou: false,
      showReturnPolicy: false,
    );

/// يبني الإيصال ويجمع كل نصوصه المعروضة في سلسلة واحدة للفحص
Future<String> _render(
  WidgetTester tester, {
  required int paperWidthMm,
  required List<SaleItemRow> items,
  required int totalPiastres,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.rtl,
      child: ReceiptTemplate(
        sale: SaleSummary(
          id: 's',
          invoiceNumber: 1,
          status: 'completed',
          totalAmountPiastres: totalPiastres,
          discountAmountPiastres: 0,
          paymentType: 'cash',
          customerName: '',
          createdAt: '2026-09-13T10:00:00Z',
          productsCount: items.length,
          totalQuantityBase: 0,
          returnedAmountPiastres: 0,
          returns: const <SaleReturnSummary>[],
        ),
        items: items,
        pharmacy: const ReceiptPharmacy(name: 'صيدلية'),
        settings: _settings(paperWidthMm),
      ),
    ),
  );
  final buffer = StringBuffer();
  for (final w in tester.allWidgets) {
    if (w is Text) buffer.writeln(w.data ?? w.textSpan?.toPlainText());
    if (w is RichText) buffer.writeln(w.text.toPlainText());
  }
  return buffer.toString();
}

void main() {
  setUpAll(() {
    AppI18n.instance.setLocale('ar');
  });

  testWidgets('المثال المرجعي: 11 شريط وعلبة 4 => «علبتان × 40» + «3 شرائط × 10» والمبلغان 80/30', (tester) async {
    final t = await _render(
      tester,
      paperWidthMm: 58,
      totalPiastres: 11000,
      items: [
        _item(saleUnit: 'strip', unitsPerBox: 4, quantityBase: 11, unitPrice: 1000, amount: 11000),
      ],
    );
    expect(t, contains('علبتان × 40.00 ج.م'));
    expect(t, contains('3 شرائط × 10.00 ج.م'));
    expect(t, contains('80.00 ج.م')); // مبلغ سطر العلب
    expect(t, contains('30.00 ج.م')); // مبلغ سطر الشرائط
    expect(t, contains('110.00 ج.م')); // إجمالي الفاتورة
  });

  testWidgets('النفس بالعرض الواسع 80مم — نفس السطرين والمبالغ', (tester) async {
    final t = await _render(
      tester,
      paperWidthMm: 80,
      totalPiastres: 11000,
      items: [
        _item(saleUnit: 'strip', unitsPerBox: 4, quantityBase: 11, unitPrice: 1000, amount: 11000),
      ],
    );
    expect(t, contains('علبتان × 40.00 ج.م'));
    expect(t, contains('3 شرائط × 10.00 ج.م'));
    expect(t, contains('80.00 ج.م'));
    expect(t, contains('30.00 ج.م'));
  });

  testWidgets('8 شرائط = علبتان كاملتان بسطر واحد فقط بلا شرائط متبقية', (tester) async {
    final t = await _render(
      tester,
      paperWidthMm: 58,
      totalPiastres: 8000,
      items: [
        _item(saleUnit: 'strip', unitsPerBox: 4, quantityBase: 8, unitPrice: 1000, amount: 8000),
      ],
    );
    expect(t, contains('علبتان × 40.00 ج.م'));
    expect(t, isNot(contains('شريط ×')));
  });

  testWidgets('3 شرائط فقط (أقل من علبة) = سطر شريط واحد كما كان', (tester) async {
    final t = await _render(
      tester,
      paperWidthMm: 58,
      totalPiastres: 3000,
      items: [
        _item(saleUnit: 'strip', unitsPerBox: 4, quantityBase: 3, unitPrice: 1000, amount: 3000),
      ],
    );
    expect(t, contains('3 شرائط × 10.00 ج.م'));
    expect(t, isNot(contains('علبة ×')));
  });

  testWidgets('بيع بالعلبة مع متبقي: 10 وحدات أساس (2.5 علبة) => علبتان × 40 + شريطان × 10', (tester) async {
    final t = await _render(
      tester,
      paperWidthMm: 58,
      totalPiastres: 10000,
      items: [
        _item(saleUnit: 'box', unitsPerBox: 4, quantityBase: 10, unitPrice: 4000, amount: 10000),
      ],
    );
    expect(t, contains('علبتان × 40.00 ج.م'));
    expect(t, contains('شريطان × 10.00 ج.م'));
    expect(t, contains('80.00 ج.م'));
    expect(t, contains('20.00 ج.م'));
  });

  testWidgets('منتج بلا تغليف فعلية (units_per_box = 1) يبقى سطراً واحداً بمبلغ الصنف كاملاً', (tester) async {
    final t = await _render(
      tester,
      paperWidthMm: 58,
      totalPiastres: 5000,
      items: [
        _item(saleUnit: 'strip', unitsPerBox: 1, quantityBase: 5, unitPrice: 1000, amount: 5000),
      ],
    );
    expect(t, contains('5 شرائط'));
    expect(t, contains('50.00 ج.م'));
    expect(t, isNot(contains('علبة ×')));
  });
}

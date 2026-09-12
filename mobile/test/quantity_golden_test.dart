// Golden vectors for the mobile quantity display SSOT (Final Decision 12).
// The SAME vectors file (scripts/golden_quantity_vectors.json) is executed by
// the web runner (scripts/run_golden_quantity_vectors.js) — one shared
// contract, two platforms, zero drift (barcode-design-v2-review.md §6).
//
// Run: flutter test test/quantity_golden_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pharmacy_mobile/core/format.dart';

QuantityUnit _unit(String value) {
  switch (value) {
    case 'box':
      return QuantityUnit.box;
    case 'strip':
      return QuantityUnit.strip;
    case 'unit':
      return QuantityUnit.unit;
  }
  throw ArgumentError('unknown unit: $value');
}

void main() {
  test('mobile quantity core matches the shared golden vectors', () {
    final file = File('../../scripts/golden_quantity_vectors.json');
    expect(file.existsSync(), isTrue,
        reason: 'the shared vectors file must live next to the repo scripts');
    final dynamic doc = jsonDecode(file.readAsStringSync());
    final List<dynamic> vectors = (doc as Map<String, dynamic>)['vectors'] as List<dynamic>;

    int failures = 0;
    for (final dynamic vector in vectors) {
      final Map<String, dynamic> input =
          (vector as Map<String, dynamic>)['input'] as Map<String, dynamic>;
      final Map<String, dynamic> expected =
          vector['expected'] as Map<String, dynamic>;

      final QuantityIntent got = SoldQuantity.intent(
        saleUnit: input['sale_unit'] as String,
        packagingType: input['packaging_type'] as String,
        unitsPerBox: (input['units_per_box'] as num).toInt(),
        quantityBase: input['quantity_base'] as num,
        saleQuantity: input['sale_quantity'] == null
            ? null
            : (input['sale_quantity'] as num).toDouble(),
      );

      final bool ok = got.unit == _unit(expected['unit'] as String) &&
          (got.count - (expected['count'] as num).toDouble()).abs() < 1e-9;
      if (ok) {
        // ignore: avoid_print
        print('ok   ${vector['name']} -> ${got.unit} ${got.count}');
      } else {
        failures++;
        // ignore: avoid_print
        print('FAIL ${vector['name']}: got ${got.unit} ${got.count}, '
            'want ${expected['unit']} ${expected['count']}');
      }
    }
    expect(failures, 0, reason: 'every shared golden vector must pass on mobile');
  });

  test('historical stability: packaging edits never reinterpret old invoices', () {
    // سيناريو التقرير §5.2: بيع 2 علبة × 5 شرائط، ثم عدّل المدير
    // units_per_box إلى 10 — الفاتورة القديمة تظل «2 علبة» عبر الـsnapshot.
    final QuantityIntent beforeEdit = SoldQuantity.intent(
      saleUnit: 'box', packagingType: 'BOX_STRIP', unitsPerBox: 5,
      quantityBase: 10, saleQuantity: 2,
    );
    final QuantityIntent afterEdit = SoldQuantity.intent(
      saleUnit: 'box', packagingType: 'BOX_STRIP', unitsPerBox: 10,
      quantityBase: 10, saleQuantity: 2,
    );
    expect(beforeEdit.count, 2);
    expect(afterEdit.count, 2); // بلا snapshot لكانت ستفسَر «1 علبة» خطأً
  });
}

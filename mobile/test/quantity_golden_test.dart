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

/// Resolves the shared vectors file at <repo-root>/scripts/ no matter which
/// directory `flutter test` was launched from. Walks upward from the current
/// directory so it works both locally and on CI checkouts (Task 86 CI fix:
/// the old hardcoded ../../ path resolved OUTSIDE the repo on GitHub Actions).
File _findSharedVectorsFile() {
  Directory dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    final candidate = File('${dir.path}/scripts/golden_quantity_vectors.json');
    if (candidate.existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  // Never found — return the conventional location for a clear failure reason.
  return File('scripts/golden_quantity_vectors.json');
}

void main() {
  test('mobile quantity core matches the shared golden vectors', () {
    final file = _findSharedVectorsFile();
    expect(file.existsSync(), isTrue,
        reason: 'the shared vectors file must live next to the repo scripts '
            '(searched upward from ${Directory.current.path})');
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

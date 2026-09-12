/// Task 61 — نسخة موبايل من lib/money.ts + i18n/format.ts في الويب.
/// قاعدة Task 47 ثابتة: الأرقام لاتينية (0-9) في كل اللغات دون استثناء،
/// والعملة: عربي = «1,234.56 ج.م» / باقي اللغات = «EGP 1,234.56».
import 'strings.dart';

class Fmt {
  Fmt._();
  static const int piastresPerUnit = 100;

  static const List<String> _monthsAr = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];
  static const List<String> _monthsEn = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  // ------------------------------------------------------------ أرقام

  /// 12345 -> "12,345" (أرقام لاتينية دائمًا، تجميع آلاف بفاصلة)
  static String number(num value) {
    final neg = value < 0;
    final v = value.abs();
    final isInt = v == v.truncateToDouble();
    final s = isInt ? v.truncate().toString() : v.toStringAsFixed(2);
    final parts = s.split('.');
    final intPart = _group(parts[0]);
    final out = parts.length > 1 ? '$intPart.${parts[1]}' : intPart;
    return neg ? '-$out' : out;
  }

  static String _group(String digits) {
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final remaining = digits.length - i;
      b.write(digits[i]);
      if (remaining > 1 && remaining % 3 == 1) b.write(',');
    }
    return b.toString();
  }

  // ------------------------------------------------------------ نقود

  /// 10000 -> «100.00 ج.م» (عربي) أو «EGP 100.00»
  static String money(int piastres, {String locale = 'ar'}) {
    final value = piastres.isFinite ? piastres.truncate() : 0;
    final egp = value / piastresPerUnit;
    final formatted = egp.abs().toStringAsFixed(2);
    final parts = formatted.split('.');
    final grouped = '${_group(parts[0])}.${parts[1]}';
    final sign = value < 0 ? '-' : '';
    return locale == 'ar' ? '$sign$grouped ج.م' : '${sign}EGP $grouped';
  }

  /// «105.5» -> 10550 بياسة (exact، مطابق لparseEGPToPiastres)
  static int? parseEGPToPiastres(String raw) {
    final trimmed = raw.trim().replaceAll('٫', '.').replaceAll(',', '');
    if (trimmed.isEmpty) return null;
    final value = double.tryParse(trimmed);
    if (value == null || value < 0) return null;
    final piastres = (value * piastresPerUnit).round();
    return piastres;
  }

  /// 10550 -> "105.50" (لحقول التحرير)
  static String piastresToInput(int piastres) =>
      (piastres.truncate() / piastresPerUnit).toStringAsFixed(2);

  /// السعر الفعلي للشريط: partial إن وُجد وإلا نصف selling/units (نصف لأعلى)
  static int stripPrice({
    required int sellingPricePiastres,
    required int partialSellingPricePiastres,
    required int unitsPerBox,
  }) {
    if (partialSellingPricePiastres > 0) return partialSellingPricePiastres;
    if (unitsPerBox > 0) return (sellingPricePiastres / unitsPerBox).round();
    return sellingPricePiastres;
  }

  // ------------------------------------------------------------ تواريخ

  static DateTime? _parse(dynamic iso) {
    if (iso is DateTime) return iso;
    if (iso is String && iso.isNotEmpty) return DateTime.tryParse(iso)?.toLocal();
    return null;
  }

  /// "2026-09-11T08:00:00Z" -> «11 سبتمبر 2026»
  static String date(dynamic iso, {String locale = 'ar'}) {
    final d = _parse(iso);
    if (d == null) return '—';
    final months = locale == 'ar' ? _monthsAr : _monthsEn;
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  /// «11 سبتمبر 2026، 08:30»
  static String dateTime(dynamic iso, {String locale = 'ar'}) {
    final d = _parse(iso);
    if (d == null) return '—';
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${date(iso, locale: locale)}، $hh:$mm';
  }

  /// "08:30"
  static String time(dynamic iso) {
    final d = _parse(iso);
    if (d == null) return '—';
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  /// "2026-09-11" لحقول التاريخ وطلبات from/to
  static String isoDay(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// مدة بالدقائق -> «3 س 25 د»
  static String duration(int? totalMinutes) {
    if (totalMinutes == null || totalMinutes <= 0) return '—';
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h == 0) return '$m د';
    if (m == 0) return '$h س';
    return '$h س $m د';
  }
}

// ==================================================================
// عرض الكمية المقروءة — SSOT (barcode-design-v2-review.md §5.3/§6)
// ==================================================================

/// نسخة موبايل من lib/quantity.ts حرفيًا — نفس المتجهات الذهبية المشتركة
/// (scripts/golden_quantity_vectors.json) تُنفَّذ هنا وفي الويب لمنع أي
/// تباعد بين المنصتين. القواعد المقفلة من القرار النهائي 12:
///  1) الفاتورة تعرض نية البيع بلا تحويل إجباري لأكبر وحدة.
///  2) الـsnapshot وقت الكتابة هو مصدر التفسير التاريخي وحده.
///  3) الصفوف القديمة (saleQuantity = null) عبر fallback موثق.
///  4) عرضي حصرًا — المال والمرتجعات يقرأون base/piastres ولا يلمسون هذا.
enum QuantityUnit { box, strip, unit }

class QuantityIntent {
  final QuantityUnit unit;
  final double count;
  const QuantityIntent(this.unit, this.count);
}

class SoldQuantity {
  SoldQuantity._();

  /// تخفيض سطر مبيع مخزَّن إلى نيته العرضية — المكان الوحيد لحساب العلبة/القاعدة للعرض.
  static QuantityIntent intent({
    required String saleUnit, // 'box' | 'strip'
    required String packagingType, // 'WHOLE_ONLY' | 'BOX_STRIP'
    required int unitsPerBox,
    required num quantityBase,
    double? saleQuantity,
  }) {
    if (saleUnit != 'box') {
      // سطر شرائط: النية هي الـbase نفسه (المال والمرتجعات عليه).
      return QuantityIntent(
        packagingType == 'BOX_STRIP' ? QuantityUnit.strip : QuantityUnit.unit,
        quantityBase.toDouble(),
      );
    }
    // سطر علبة: النية هي عدد العلب الذي أدخله الكاشير.
    if (saleQuantity != null && saleQuantity > 0) {
      return QuantityIntent(QuantityUnit.box, saleQuantity);
    }
    // صف قديم بلا snapshot — fallback موثق: base ÷ units الحالية.
    final double boxes =
        unitsPerBox > 0 ? quantityBase / unitsPerBox : quantityBase.toDouble();
    return QuantityIntent(QuantityUnit.box, boxes);
  }

  /// _trimQuantity — صحيح بلا كسور وإلا كسران بلا أصفار زائدة
  static String trimCount(double value) {
    if (value == value.truncateToDouble()) return value.truncate().toString();
    String s = value.toStringAsFixed(2);
    s = s.replaceAll(RegExp(r'\.?0+$'), '');
    return s;
  }

  /// الترجمة عبر كتالوج sales (نفس المفاتيح التي يستخدمها الويب: oneBox/manyStrips/…)
  static String text(QuantityIntent intent, AppI18n i18n) {
    switch (intent.unit) {
      case QuantityUnit.box:
        if (intent.count == 1) return i18n.t('sales', 'oneBox');
        if (intent.count == 2) return i18n.t('sales', 'twoBoxes');
        return i18n.t('sales', 'manyBoxes', {'count': trimCount(intent.count)});
      case QuantityUnit.strip:
        if (intent.count == 1) return i18n.t('sales', 'oneStrip');
        if (intent.count == 2) return i18n.t('sales', 'twoStrips');
        return i18n.t('sales', 'manyStrips', {'count': trimCount(intent.count)});
      case QuantityUnit.unit:
        if (intent.count == 1) return i18n.t('sales', 'oneUnit');
        if (intent.count == 2) return i18n.t('sales', 'twoUnits');
        return i18n.t('sales', 'manyUnits', {'count': trimCount(intent.count)});
    }
  }
}

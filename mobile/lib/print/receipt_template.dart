// Task 68-j — قالب الإيصال الحراري: نسخة حرفية من receipt-template.tsx في الويب.
// ويدجت أبيض خالص بمظهر حراري أحادي: نفس هوامش الويب (3مم أفقياً/4مم عمودياً)،
// 11px عند 58مم و12.5px عند 80مم، فوارق منقطة بين الأقسام وألوان neutral الثابتة
// — العربية تُشكَّل بمحرك نصوص Flutter نفسه فالالتقاط كصورة للطباعة آمن 100%.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/strings.dart';
import '../models/models.dart';

// ------------------------------------------------------------- ثوابت المظهر

/// px/[3mm] وpy/[4mm] بالويب — عرض mm في CSS = mm × 96/25.4
const double _kPxPerMm = 96 / 25.4;
const Color _kInk = Color(0xFF111111); // text-[#111]
const Color _kNeutral500 = Color(0xFF737373); // border-neutral-500
const Color _kNeutral600 = Color(0xFF525252); // text-neutral-600
const Color _kNeutral700 = Color(0xFF404040); // text-neutral-700

// ------------------------------------------------------------- الاسم المركب

/// composePharmacyDisplayName — receipt-template.tsx:61-67 حرفيًا:
/// بادئة تنتهي بنقطة تُلصق بالاسم مباشرة (صيدلية د. + محمد => صيدلية د.محمد)،
/// وغير ذلك تفصل بمسافة (صيدلية + محمد => صيدلية محمد)، ولو كان الاسم المسجّل
/// يبدأ أصلًا بالبادئة يُترك كما هو بلا تكرار (صيدلية + صيدلية النور).
String composePharmacyDisplayName(String prefix, String name) {
  final String cleanName = name.trim();
  final String cleanPrefix = prefix.trim();
  if (cleanPrefix.isEmpty) return cleanName;
  if (cleanName.startsWith(cleanPrefix)) return cleanName;
  return cleanPrefix.endsWith('.') ? '$cleanPrefix$cleanName' : '$cleanPrefix $cleanName';
}

/// بيانات رأس الإيصال — نظير ReceiptPharmacy بالويب (نص فارغ = غير متاح)
class ReceiptPharmacy {
  final String name;
  final String city;
  final String address;
  final String phone;
  const ReceiptPharmacy({this.name = '', this.city = '', this.address = '', this.phone = ''});
}

// ------------------------------------------------------------- القالب

/// نسخة إيصال واحدة — طباعة النسختين وفاصل «قص هنا» تتولد في الشاشة المستدعية
/// (كما يفعل ReceiptPrinter بالويب مع كل نسخة داخل RepaintBoundary مستقلة).
class ReceiptTemplate extends StatelessWidget {
  final SaleSummary sale;
  final List<SaleItemRow> items;
  final ReceiptPharmacy pharmacy;
  final String? cashierName;
  final ReceiptSettings settings;
  final bool showCopyLabel;
  final String? copyLabel;

  const ReceiptTemplate({
    super.key,
    required this.sale,
    required this.items,
    required this.pharmacy,
    required this.settings,
    this.cashierName,
    this.showCopyLabel = false,
    this.copyLabel,
  });

  // ------------------------------------------------------- مساعدات المطابقة

  /// DOSE_IN_NAME_PATTERN — lib/product.ts:12 (لا إلحاق إن كان الاسم يحمل جرعة)
  static final RegExp _doseInName =
      RegExp(r'\d\s*(?:mg|µg|mcg|g|ml|iu|ملجم|ملغ|مل|جرام|وحدة)', caseSensitive: false);

  /// extraStrengthLabel — lib/product.ts:14-20: '' عند عدم الحاجة للإلحاق
  static String? _extraStrengthLabel(String name, String strength) {
    final String clean = strength.trim();
    if (clean.isEmpty) return null;
    if (name.toLowerCase().contains(clean.toLowerCase())) return null;
    if (_doseInName.hasMatch(name)) return null;
    return clean;
  }

  /// trim — receipt-template.tsx:47-49: صحيح بلا كسور، وإلا كسران ثم إسقاط الأصفار
  static String _trimQuantity(num value) {
    final double v = value.toDouble();
    if (v == v.truncateToDouble()) return v.truncate().toString();
    String s = v.toStringAsFixed(2);
    s = s.replaceAll(RegExp(r'\.?0+$'), '');
    return s;
  }

  /// displayQuantity — receipt-template.tsx:41-45: الشريط كما هو، والعلبة =
  /// quantity_base ÷ units_per_box (الخطأ القديم كان عرض الـ base كعلب)
  static String _displayQuantity(SaleItemRow item, AppI18n i18n) {
    if (item.saleUnit != 'box') {
      return i18n.t('pos', 'qtyStrip', {'count': _trimQuantity(item.quantityBase)});
    }
    final double boxes =
        item.unitsPerBox > 0 ? item.quantityBase / item.unitsPerBox : item.quantityBase.toDouble();
    return i18n.t('pos', 'qtyBox', {'count': _trimQuantity(boxes)});
  }

  /// receiptDate — fmtDateTime(iso, {dateStyle:'short', timeStyle:'short'}):
  /// تاريخ قصير dd/MM/yyyy والوقت 12 ساعة بص/م للعربية (ar-EG) و24 ساعة للبقية.
  static String _receiptDateText(SaleSummary sale, AppI18n i18n) {
    final DateTime? d = DateTime.tryParse(sale.createdAt)?.toLocal();
    if (d == null) return '—';
    final String date =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    final String minute = d.minute.toString().padLeft(2, '0');
    if (i18n.locale.startsWith('ar')) {
      final int h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      return '$date، $h:$minute ${d.hour < 12 ? 'ص' : 'م'}';
    }
    return '$date, ${d.hour}:$minute';
  }

  static String _invoiceValue(int invoiceNumber) =>
      'INV-${invoiceNumber.toString().padLeft(6, '0')}';

  // --------------------------------------------------------------- البناء

  @override
  Widget build(BuildContext context) {
    final AppI18n i18n = AppI18n.instance;
    final bool compact = settings.paperWidthMm < 70; // 58مم: الأعمدة تضيق فتتكدد السطور
    final double fontSize = compact ? 11 : 12.5;
    final double width = settings.paperWidthMm * _kPxPerMm; // 58مم ≈ 219 / 80مم ≈ 302 منطقياً
    final double contentWidth = width - 2 * 3 * _kPxPerMm;
    final String headerName = composePharmacyDisplayName(settings.namePrefix, pharmacy.name);
    final String addressCity = <String>[pharmacy.address.trim(), pharmacy.city.trim()]
        .where((String part) => part.isNotEmpty)
        .join(i18n.t('pos', 'addressCitySeparator'));
    final bool hasCashier =
        settings.showCashier && cashierName != null && cashierName!.trim().isNotEmpty;

    return SizedBox(
      width: width,
      child: Container(
        color: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: 3 * _kPxPerMm, vertical: 4 * _kPxPerMm),
        child: DefaultTextStyle(
          style: TextStyle(color: _kInk, fontSize: fontSize, height: 1.55, fontFamily: 'monospace'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (showCopyLabel)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '— ${copyLabel ?? i18n.t('pos', 'copyCustomer')} —',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w700,
                        color: _kNeutral600,
                        letterSpacing: 0.3),
                  ),
                ),

              // الرأس — الاسم المركب من البادئة والاسم المسجّل
              Text(
                headerName.isEmpty ? i18n.t('pos', 'fallbackPharmacyName') : headerName,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: compact ? 15 : 17, fontWeight: FontWeight.w800),
              ),
              if (settings.showAddress && addressCity.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(addressCity,
                      textAlign: TextAlign.center, style: const TextStyle(color: _kNeutral700)),
                ),
              if (settings.showPhone && pharmacy.phone.trim().isNotEmpty)
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(pharmacy.phone.trim(),
                      textAlign: TextAlign.center, style: const TextStyle(color: _kNeutral700)),
                ),

              const _DashedLine(),

              // بيانات الفاتورة — رقم الفاتورة LTR مع حشو 6 خانات
              _InfoRow(
                label: i18n.t('pos', 'invoiceNo'),
                value: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(_invoiceValue(sale.invoiceNumber)),
                ),
              ),
              _InfoRow(
                label: i18n.t('pos', 'date'),
                value: Text(_receiptDateText(sale, i18n)),
              ),
              if (hasCashier) _InfoRow(label: i18n.t('pos', 'cashier'), value: Text(cashierName!)),

              const _DashedLine(),

              ..._buildItems(i18n, compact, contentWidth),

              const _DashedLine(),

              // الخصم ثم الإجمالي — الإجمالي هو الصافي بعد الخصم دائمًا
              if (sale.discountAmountPiastres > 0)
                _InfoRow(
                  label: _discountLabel(i18n),
                  value: Text('-${Fmt.money(sale.discountAmountPiastres, locale: i18n.locale)}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      i18n.t('pos', 'totalWithItems', {
                        'items': items.length == 1
                            ? i18n.t('pos', 'totalItemsOne')
                            : i18n.t('pos', 'totalItemsMany', {'count': items.length}),
                      }),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    Fmt.money(sale.totalAmountPiastres, locale: i18n.locale),
                    style: TextStyle(
                        fontSize: compact ? 15 : 16.5, fontWeight: FontWeight.w800, height: 1.2),
                  ),
                ],
              ),

              const _DashedLine(),

              // فاتورة آجل — تُقيد على حساب العميل في صفحة حسابات العملاء
              if (sale.paymentType == 'credit')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    sale.customerName.isNotEmpty
                        ? i18n.t('pos', 'creditInvoiceWithCustomer', {'name': sale.customerName})
                        : i18n.t('pos', 'creditInvoice'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),

              // الذيل — السطور تظهر فقط عند تفعيل المفتاح AND وجود نص محفوظ (كالويب)
              if (settings.showThankYou && settings.thankYouText.trim().isNotEmpty)
                Text(settings.thankYouText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              if (settings.showReturnPolicy && settings.returnPolicyText.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(settings.returnPolicyText,
                      textAlign: TextAlign.center, style: const TextStyle(color: _kNeutral700)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// تسمية صف الخصم: الويب يستدعي t('discount') في نطاق pos فلا يوجد المفتاح
  /// فيه (يرجع المرجع المرئي الخام) — نستخدم أقرب مفتاح موجود 'خصم {amount}'
  /// من نطاق sales بمبلغ فارغ للحصول على الكلمة المجردة بلا لمس كتالوجات i18n.
  static String _discountLabel(AppI18n i18n) =>
      i18n.t('sales', 'discount', {'amount': ''}).trim();

  /// الأصناف — space-y-1 (4px بين السطور)؛ 58مم سطران للصنف و80مم سطر واحد
  List<Widget> _buildItems(AppI18n i18n, bool compact, double contentWidth) {
    final List<Widget> out = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      final SaleItemRow item = items[i];
      final String? strengthLabel = _extraStrengthLabel(item.productName, item.strength);
      final String qty = _displayQuantity(item, i18n);
      final String unitPrice = Fmt.money(item.unitPricePiastres, locale: i18n.locale);
      final String amount = Fmt.money(item.amountPiastres, locale: i18n.locale);
      if (i > 0) out.add(const SizedBox(height: 4));
      final Widget name = Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(text: item.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (strengthLabel != null)
              TextSpan(text: ' $strengthLabel', style: const TextStyle(color: _kNeutral500)),
          ],
        ),
        style: TextStyle(height: compact ? 1.35 : 1.55),
      );
      if (compact) {
        out.add(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              name,
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Expanded(
                    child: Text('$qty × $unitPrice', style: const TextStyle(color: _kNeutral700)),
                  ),
                  const SizedBox(width: 8),
                  Text(amount, style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        );
      } else {
        out.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Expanded(child: name),
              const SizedBox(width: 8),
              Text(qty, style: const TextStyle(color: _kNeutral700)),
              const SizedBox(width: 8),
              SizedBox(
                width: contentWidth * 0.22, // w-[22%] بالويب
                child: Text(amount,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.start),
              ),
            ],
          ),
        );
      }
    }
    return out;
  }
}

// ------------------------------------------------------------- عناصر مشتركة

/// صف معلومة «تسمية … قيمة» — Row label/value بفجوة 2 (8px) كما في Row بالويب
class _InfoRow extends StatelessWidget {
  final String label;
  final Widget value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(label, style: const TextStyle(color: _kNeutral700)),
        const SizedBox(width: 8),
        DefaultTextStyle.merge(style: const TextStyle(fontWeight: FontWeight.w600), child: value),
      ],
    );
  }
}

/// فاصل منقّط — border-t border-dashed border-neutral-500 مع my-1.5
class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(height: 1, child: CustomPaint(painter: _DashPainter())),
    );
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  final double thickness;
  const _DashPainter()
      : color = _kNeutral500,
        thickness = 1;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = thickness;
    const double dash = 4;
    const double gap = 4;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(math.min(x + dash, size.width), 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.thickness != thickness;
}

/// فاصل «قص هنا» بين النسختين — receipt-printer.tsx:70-86 حرفيًا: خطان منقّطان
/// بينهما النص بخط 10px. يُعرض في المعاينة فقط ولا يوضع داخل أي RepaintBoundary
/// فلا يطبع كصفحة مستقلة (كل نسخة = صفحة مستقلة أصلًا في PDF الموبايل).
class ReceiptCutSeparator extends StatelessWidget {
  const ReceiptCutSeparator({super.key});

  @override
  Widget build(BuildContext context) {
    final AppI18n i18n = AppI18n.instance;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 3 * _kPxPerMm, vertical: 2 * _kPxPerMm),
      child: Row(
        children: <Widget>[
          const Expanded(child: SizedBox(height: 1, child: CustomPaint(painter: _DashPainter()))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(i18n.t('pos', 'cutHere'),
                style: TextStyle(fontSize: 10, color: _kNeutral600)),
          ),
          const Expanded(child: SizedBox(height: 1, child: CustomPaint(painter: _DashPainter()))),
        ],
      ),
    );
  }
}

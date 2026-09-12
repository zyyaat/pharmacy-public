// المرحلة 3 — تصدير PDF محلي 100% للتقارير (Offline-First).
// المبدأ نفس نهج receipt_printer (Task 68): بناء صفحات التقرير ويدجت Flutter
// ثم التقاطها RepaintBoundary → صور ناضجة → صفحات PDF مقاس A4 → مشاركة عبر
// نظام المشاركة في أندرويد (حفظ في الملفات / بريد / واتساب…).
// العربية آمنة 100% لأن تشكيلها يقوم به محرك نصوص Flutter نفسه — لا نص عربي
// داخل مكتبة PDF إطلاقًا. المصدر بيانات في الذاكرة (من الكاش عند الانقطاع)
// فالتصدير يعمل بلا إنترنت تمامًا.
import 'dart:ui' as ui show ImageByteFormat;

import 'package:flutter/widgets.dart' show GlobalKey;
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// نتيجة التصدير — ok=true فُتحت ورقة المشاركة (أو ألغاها المستخدم).
class ReportExportResult {
  const ReportExportResult({required this.ok, this.error});
  final bool ok;
  final String? error;
}

/// مقاس صفحة الالتقاط المنطقي — A4 بدقة 96dpi (794×1123 منطقيًا).
/// كل ويدجت صفحة يجب أن يُبنى داخل SizedBox بهذا المقاس بالضبط حتى تكون
/// نسبة الالتقاط = نسبة A4 وتملأ الصفحة بلا قصّ ولا حواف غريبة.
const double kReportPageWidth = 794;
const double kReportPageHeight = 1123;

/// يلتقط كل مفتاح RepaintBoundary (صفحة تقرير) ويحوّله لصفحة PDF بمقاس A4
/// (عرض ثابت 210مم والارتفاع بنسبة الالتقاط محصورًا بسقف 297مم)، ثم يستدعي
/// ورقة المشاركة في أندرويد عبر Printing.sharePdf.
Future<ReportExportResult> shareReportPdf({
  required List<GlobalKey> boundaryKeys,
  required String jobName,
}) async {
  try {
    final doc = pw.Document();
    var pages = 0;
    for (final key in boundaryKeys) {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) continue;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) continue;
      final bytes = byteData.buffer.asUint8List();
      const double pageW = 210.0 * PdfPageFormat.mm;
      const double pageH = 297.0 * PdfPageFormat.mm;
      // الارتفاع بنسبة الصورة الملتقطة بعرض A4 — والسقف ارتفاع A4. صفحة
      // مبنية بمقاس A4 الصحيح تعطي النسبة نفسها فتملأ الصفحة تمامًا.
      final double drawH = (pageW * image.height / image.width).clamp(0.0, pageH);
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat(pageW, drawH, marginAll: 0),
        build: (ctx) => pw.Image(
          pw.MemoryImage(bytes),
          width: pageW,
          height: drawH,
          fit: pw.BoxFit.fill,
        ),
      ));
      pages++;
    }
    if (pages == 0) {
      return const ReportExportResult(ok: false, error: 'report_capture_failed');
    }
    await Printing.sharePdf(bytes: await doc.save(), filename: '$jobName.pdf');
    return const ReportExportResult(ok: true);
  } catch (e) {
    return ReportExportResult(ok: false, error: e.toString());
  }
}

// Task 68 — طباعة الإيصال الحراري الحقيقية.
// المبدأ: نلتقط ويدجت الإيصال (RepaintBoundary) كصورة ناضجة ثم نغلفها في صفحة PDF
// بعرض ورق الطابعة (58/80مم من الإعدادات) ونطبعها عبر نظام الطباعة في أندرويد —
// نفس نهج window.print في الويب. العربية آمنة 100% لأن الالتقاط من ويدجت Flutter
// نفسه (محرك نصوص Flutter يشكّل العربية) — لا نص عربي داخل مكتبة PDF إطلاقًا.
// النسخ المتعددة: كل نسخة = صفحة في نفس الـ PDF، وبينها خط قص «✂» مرسوم ويدجت.
import 'dart:ui' as ui show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// نتيجة الطباعة — ok=true نجحت العملية (أو ألغاها المستخدم من منتقي الطابعة).
class ReceiptPrintResult {
  const ReceiptPrintResult({required this.ok, this.error});
  final bool ok;
  final String? error;
}

/// يلتقط كل مفتاح RepaintBoundary (نسخة إيصال) ويحوّله لصفحة PDF بنفس أبعاد
/// الصورة بنسبة عرض الورق، ثم يستدعي منتقي الطباعة في أندرويد.
/// [paperWidthMm] من إعدادات الفواتير (58 أو 80 عادةً).
Future<ReceiptPrintResult> printReceiptBoundaries({
  required List<GlobalKey> boundaryKeys,
  required double paperWidthMm,
  String? jobName,
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
      final mmPerPx = paperWidthMm / image.width;
      final heightMm = (image.height * mmPerPx).clamp(20.0, 1500.0);
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat(
          paperWidthMm * PdfPageFormat.mm,
          heightMm.toDouble() * PdfPageFormat.mm,
          marginAll: 0,
        ),
        build: (ctx) => pw.Image(
          pw.MemoryImage(bytes),
          width: paperWidthMm * PdfPageFormat.mm,
          height: heightMm.toDouble() * PdfPageFormat.mm,
          fit: pw.BoxFit.fill,
        ),
      ));
      pages++;
    }
    if (pages == 0) {
      return const ReceiptPrintResult(
          ok: false, error: 'receipt_capture_failed');
    }
    await Printing.layoutPdf(
        onLayout: (_) async => doc.save(), name: jobName ?? 'receipt');
    return const ReceiptPrintResult(ok: true);
  } catch (e) {
    return ReceiptPrintResult(ok: false, error: e.toString());
  }
}

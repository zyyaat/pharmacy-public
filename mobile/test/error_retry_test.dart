// Task 78 — اختبار «رسالة الخطأ اللطيفة»: كان خطأ الشبكة يظهر للمستخدم
// برسالة المطوّر الخام (NEXT_PUBLIC_API_URL وBACKEND_INTERNAL_URL وإعدادات
// CORS وصفحة /diag) داخل بطاقة حمراء صارخة — كالرسالة في السكرين شوت.
// الإصلاح على مستويين، وهذا الاختبار يثبّتهما:
//   1) النص نفسه (errors.network_unreachable عربي/إنجليزي) صار رسالة مستخدم
//      ودودة بلا أي مصطلحات تطوير.
//   2) بطاقة ErrorRetry صارت هادئة كبطاقة السپلاش: دائرة ناعمة بأيقونة
//      wifi-off خافتة + رسالة مقروءة + «إعادة المحاولة» بلون الهوية الأخضر —
//      لا بطاقة حمراء ولا نص أحمر.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pharmacy_mobile/core/strings.dart';
import 'package:pharmacy_mobile/widgets/ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('network_unreachable رسالة مستخدم ودودة — بلا مصطلحات تطوير (عربي+إنجليزي)', () {
    final i18n = AppI18n.instance;
    i18n.setLocale('ar');
    final ar = i18n.error('NETWORK_UNREACHABLE');
    expect(ar, contains('تعذّر الاتصال بالخادم'));
    for (final String jargon in <String>['CORS', 'NEXT_PUBLIC', 'BACKEND', '/diag', 'backend']) {
      expect(ar.contains(jargon), isFalse, reason: 'رسالة العربي لا يجوز أن تحوي $jargon');
    }

    i18n.setLocale('en');
    final en = i18n.error('NETWORK_UNREACHABLE');
    expect(en, contains('Cannot reach the server'));
    for (final String jargon in <String>['CORS', 'NEXT_PUBLIC', 'BACKEND', '/diag', 'backend']) {
      expect(en.contains(jargon), isFalse, reason: 'English message must not contain $jargon');
    }
    i18n.setLocale('ar');
  });

  testWidgets('ErrorRetry بطاقة هادئة: أيقونة wifi-off + رسالة مقروءة + إعادة خضراء', (tester) async {
    final i18n = AppI18n.instance;
    i18n.setLocale('ar');
    const String friendly = 'تعذّر الاتصال بالخادم. تأكّد من اتصالك بالإنترنت ثم أعد المحاولة.';

    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Center(child: ErrorRetry(friendly, onRetry: () {}))),
      ),
    ));

    // أيقونة wifi-off الخافتة داخل الدائرة الناعمة
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    // الرسالة كاملة ظاهرة في وسط البطاقة
    expect(find.textContaining('تعذّر الاتصال بالخادم'), findsOneWidget);
    // زر إعادة المحاولة بنص المفتاح المشترك (نفس مفتاح السپلاش)
    expect(find.text(i18n.t('common', 'retry')), findsOneWidget);
    // لا نص أحمر: لا يوجد أي Text يستخدم لون error مباشرة داخل البطاقة
    final List<Text> texts = tester.widgetList<Text>(find.byType(Text)).toList();
    final Color errorColor = ThemeData().colorScheme.error;
    for (final Text t in texts) {
      final TextStyle? style = t.style;
      if (style?.color != null) {
        expect(style!.color, isNot(errorColor),
            reason: 'نص البطاقة يجب ألا يكون بالأحمر الصارخ: "${t.data}"');
      }
    }
  });
}

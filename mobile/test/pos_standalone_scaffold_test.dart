// Task 77 — اختبار انحدار «صفحة نقطة البيع الوحشة»: الشاشة تُفتح بمسارين —
// من داخل HomeShell (له Scaffold) وكمسار مستقل من زر «فتح نقطة البيع» في
// المخزون. بدون Scaffold داخل الشاشة نفسها كان DefaultTextStyle الجذري في
// MaterialApp (نمط التحذير الأحمر/الأصفر material/app.dart:33) يسرّب لكل
// نصوصها: عناوين حمراء وتسطير أصفر مزدوج وخلفية سوداء. هذا الاختبار يضخّ
// الشاشة كمسار مستقل تمامًا كما على الجهاز ويضمن:
//   1) وجود Scaffold داخل POSScreen نفسها
//   2) أن النصوص ترث ثيم التطبيق لا نمط التحذير (بلا تسطير، بلا أحمر)
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';

import 'package:pharmacy_mobile/core/api_client.dart';
import 'package:pharmacy_mobile/core/strings.dart';
import 'package:pharmacy_mobile/core/theme.dart';
import 'package:pharmacy_mobile/models/models.dart';
import 'package:pharmacy_mobile/screens/pos_screen.dart';
import 'package:pharmacy_mobile/state/app_state.dart';

/// بديل خادم: أي مسار → قائمة فارغة (POS لا يجلب شيئًا عند الفتح).
class _EmptyAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = jsonEncode(<String, dynamic>{'data': <dynamic>[]});
    return ResponseBody.fromString(
      body,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void _stubSecureStorage(WidgetTester tester) {
  const MethodChannel channel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    channel,
    (MethodCall call) async => null,
  );
}

Future<void> _pumpStandalonePOS(WidgetTester tester) async {
  final state = AppState()
    ..user = User.fromJson(<String, dynamic>{
      'id': 'u1',
      'email': 'owner@pharmacy.eg',
      'first_name': 'صاحب',
      'last_name': 'الصيدلية',
      'display_name': 'صاحب الصيدلية',
      'role': 'OWNER',
    })
    ..context = PharmacyContext.fromJson(<String, dynamic>{
      'pharmacy': <String, dynamic>{
        'id': 'p1',
        'name': 'صيدلية الشفاء',
        'city': 'القاهرة',
        'address': 'شارع التحرير',
        'phone': '0223334444',
        'product_count': 42,
      },
      'branch': <String, dynamic>{'id': 'b1', 'name': 'الفرع الرئيسي', 'city': 'القاهرة'},
      'user': <String, dynamic>{'id': 'u1', 'role': 'OWNER'},
    })
    ..permissions = MyPermissions.fromJson(<String, dynamic>{
      'principal_type': 'pharmacy',
      'role': 'owner',
      'permissions': <String>[],
      'full_access': true,
    });
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        title: 'Pharmacy OS',
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        supportedLocales: const <Locale>[Locale('ar'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // تمامًا كما يفعل زر «فتح نقطة البيع»: الشاشة هي home المسار — بلا هيكل.
        home: const POSScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() {
    ApiClient.instance.dio.httpClientAdapter = _EmptyAdapter();
  });

  testWidgets('POSScreen standalone has its own Scaffold (no shell required)',
      (WidgetTester tester) async {
    _stubSecureStorage(tester);
    AppI18n.instance.setLocale('ar');
    await _pumpStandalonePOS(tester);

    final exception = tester.takeException();
    if (exception != null) fail('استثناء build: $exception');

    expect(
      find.byType(Scaffold),
      findsOneWidget,
      reason: 'الشاشة المستقلة يجب أن تحمل Scaffold الخاص بها',
    );
  });

  testWidgets('standalone POS text inherits the app theme — never the '
      'red/yellow MaterialApp fallback style', (WidgetTester tester) async {
    _stubSecureStorage(tester);
    AppI18n.instance.setLocale('ar');
    await _pumpStandalonePOS(tester);

    final exception = tester.takeException();
    if (exception != null) fail('استثناء build: $exception');

    // نمط التحذير: أحمر 0xD0FF0000 + تسطير أصفر مزدوج — أي نص داخل الشاشة
    // يرثه يعني تسرّب DefaultTextStyle الجذري.
    final contexts = tester.elementList(find.byType(Text)).toList();
    expect(contexts, isNotEmpty);
    for (final Element element in contexts) {
      final TextStyle style = DefaultTextStyle.of(element).style;
      expect(
        style.decoration,
        isNot(TextDecoration.underline),
        reason: 'نص ورث نمط التحذير (تسطير): "${(element.widget as Text).data}"',
      );
      if (style.color != null) {
        expect(
          style.color!.value,
          isNot(const Color(0xD0FF0000).value),
          reason: 'نص بلون التحذير الأحمر: "${(element.widget as Text).data}"',
        );
      }
    }
  });
}

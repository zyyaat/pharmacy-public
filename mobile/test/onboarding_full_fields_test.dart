// Task 79 — اختبار «معالج الإعداد بكامل بيانات الفرع»: كان المعالج يجمع 8
// حقول صيدلية فقط ولا يسأل عن اسم الفرع الرئيسي ولا كوده ولا البريد — فتفتح
// صفحة تعديل الفرع بعده ناقصة. هذا الاختبار يضخّ الشاشة مع خادم مزيف ويضمن:
//   1) الخطوة 1 تعرض اسم الصيدلية واسم الفرع الرئيسي بعلامة الإجباري * أحمر
//      وكود الفرع بكلمة «اختياري»، مع سطر التصنيف «التعريف» والمفتاح التفسيري
//   2) خطوة التواصل تعرض البريد الإلكتروني
//   3) خطوة المراجعة تعرض صفوف الفرع الثلاثة الجديدة (11 صفًّا)
//   4) الحفظ يرسل branch_name وbranch_code وemail إلى الخادم فعليًا
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';

import 'package:pharmacy_mobile/core/api_client.dart';
import 'package:pharmacy_mobile/core/strings.dart';
import 'package:pharmacy_mobile/screens/onboarding_screen.dart';
import 'package:pharmacy_mobile/state/app_state.dart';

/// خادم مزيف: GET/PUT /pharmacy/onboarding — يلتقط جسم PUT للتحقق منه.
class _OnboardingAdapter implements HttpClientAdapter {
  Map<String, dynamic>? capturedPut;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method.toUpperCase() == 'PUT') {
      final body = await requestStream?.fold<List<int>>(
        <int>[],
        (acc, chunk) => acc..addAll(chunk),
      );
      if (body != null) {
        capturedPut = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      }
    }
    final payload = <String, dynamic>{
      'data': <String, dynamic>{
        'onboarding_required': true,
        'pharmacy': <String, dynamic>{
          'name': 'صيدلية الشفاء',
          'phone': '',
          'website': '',
          'email': '',
          'address_line1': '',
          'address_line2': '',
          'city': 'غير محدد',
          'state_province': '',
          'postal_code': '',
          'country': 'EG',
        },
        'branch': <String, dynamic>{
          'name': 'الفرع الرئيسي',
          'code': 'MAIN',
          'email': 'owner@pharmacy.eg',
        },
      },
    };
    return ResponseBody.fromString(
      jsonEncode(payload),
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

Future<void> _pumpWizard(WidgetTester tester) async {
  await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
    value: AppState(),
    child: MaterialApp(
      routes: <String, WidgetBuilder>{
        '/home': (_) => const SizedBox.shrink(),
      },
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: const OnboardingScreen(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// زر المتابعة تحت طيّ الصفحة على سطح الاختبار 800×600 — مرّره للرؤية أولًا
Future<void> _tapButton(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('المعالج يجمع بيانات الفرع كاملة من أول مرة ويرسلها للحفظ',
      (tester) async {
    final i18n = AppI18n.instance;
    i18n.setLocale('ar');
    _stubSecureStorage(tester);
    final adapter = _OnboardingAdapter();
    ApiClient.instance.dio.httpClientAdapter = adapter;

    await _pumpWizard(tester);

    // الخطوة 1: سطر التصنيف + العنوان + المفتاح التفسيري
    expect(find.text(i18n.t('auth', 'ob_s1_cat')), findsOneWidget);
    expect(find.text(i18n.t('auth', 'ob_s1_title')), findsOneWidget);
    expect(find.text(i18n.t('auth', 'ob_required_legend')), findsOneWidget);

    // حقول الخطوة 1 الثلاثة ظاهرة مع الحفظ المسبق من الخادم
    expect(find.text(i18n.t('auth', 'ob_branch_name')), findsOneWidget);
    expect(find.text(i18n.t('auth', 'ob_branch_code')), findsOneWidget);
    // الحفظ المسبق من الخادم ظاهر (القيمة + تلميح الحقل يشتركان في النص)
    expect(find.text('الفرع الرئيسي'), findsWidgets);

    // الإجباري نجمتان حمراوان (الاسم + اسم الفرع) والكود «اختياري»
    expect(find.text('*'), findsNWidgets(3)); // نجمتان للحقلين + نجمة المفتاح
    expect(find.text(i18n.t('auth', 'ob_optional')), findsOneWidget);

    // متابعة → التواصل: البريد الإلكتروني ظاهر مع الهاتف والموقع
    await _tapButton(tester, find.text(i18n.t('auth', 'ob_continue')));
    expect(find.text(i18n.t('auth', 'ob_s2_cat')), findsOneWidget);
    expect(find.text(i18n.t('auth', 'ob_email')), findsOneWidget);
    expect(find.text(i18n.t('auth', 'ob_optional')), findsNWidgets(3));

    // متابعة → الموقع ثم متابعة → المراجعة: 11 صفًّا بصفوف الفرع الجديدة
    await _tapButton(tester, find.text(i18n.t('auth', 'ob_continue')));
    await _tapButton(tester, find.text(i18n.t('auth', 'ob_continue')));
    expect(find.text(i18n.t('auth', 'ob_s4_cat')), findsOneWidget);
    expect(find.text(i18n.t('auth', 'ob_branch_name_short')), findsOneWidget);
    expect(find.text(i18n.t('auth', 'ob_branch_code')), findsOneWidget);
    expect(find.text(i18n.t('auth', 'ob_email')), findsOneWidget);

    // إنهاء الإعداد → PUT يُرسل حقول الفرع فعليًا إلى الخادم
    await _tapButton(tester, find.text(i18n.t('auth', 'ob_finish')));
    expect(adapter.capturedPut, isNotNull);
    expect(adapter.capturedPut!['branch_name'], 'الفرع الرئيسي');
    expect(adapter.capturedPut!['branch_code'], 'MAIN');
    expect(adapter.capturedPut!['email'], 'owner@pharmacy.eg');
    expect(adapter.capturedPut!['name'], 'صيدلية الشفاء');
    expect(adapter.capturedPut!['complete'], true);
  });

  testWidgets('الفراغ في اسم الفرع يمنع المتابعة برسالة ودودة', (tester) async {
    final i18n = AppI18n.instance;
    i18n.setLocale('ar');
    _stubSecureStorage(tester);
    ApiClient.instance.dio.httpClientAdapter = _OnboardingAdapter();

    await _pumpWizard(tester);

    // امسح اسم الفرع المحفوظ مسبقًا ثم حاول المتابعة
    await tester.enterText(find.byKey(const Key('ob_branch_name')), '');
    await _tapButton(tester, find.text(i18n.t('auth', 'ob_continue')));

    expect(find.text(i18n.t('auth', 'ob_branch_required')), findsOneWidget);
    // ما زلنا في الخطوة 1 — لم ينتقل
    expect(find.text(i18n.t('auth', 'ob_s1_title')), findsOneWidget);
  });
}

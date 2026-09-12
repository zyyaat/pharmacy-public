// المرحلة 2+3 — اختبارات offline-first:
//   1) مفاتيح i18n الجديدة موجودة بالثماني لغات (offline_sale_needed + export_*)
//      وشارة offline_chip بالعربية والإنجليزية (اصطلاح Task 82) مع سقوط
//      اللغات الجزئية إلى العربية عبر دلالة deep-merge.
//   2) شارة «غير متصل» في شريط نقطة البيع تظهر وتختفي مع NetworkSignal —
//      منطق الاتصال للعمليات التي تحتاج الخادم (المرحلة 2).
//   3) حارس مصدّر التقارير: مفاتيح فارغة = فشل آمن report_capture_failed
//      بلا لمس قنوات المنصة إطلاقًا (المرحلة 3).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:provider/provider.dart';

import 'package:pharmacy_mobile/core/api_client.dart';
import 'package:pharmacy_mobile/core/offline.dart';
import 'package:pharmacy_mobile/core/strings.dart';
import 'package:pharmacy_mobile/core/theme.dart';
import 'package:pharmacy_mobile/models/models.dart';
import 'package:pharmacy_mobile/print/report_exporter.dart';
import 'package:pharmacy_mobile/screens/pos_screen.dart';
import 'package:pharmacy_mobile/screens/reports_screen.dart';
import 'package:pharmacy_mobile/state/app_state.dart';

/// بديل خادم: أي مسار → قائمة فارغة (POS/التقارير لا يجلبان شيئًا معطوبًا).
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

Future<void> _pumpPOS(WidgetTester tester) async {
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
        home: const POSScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    ApiClient.instance.dio.httpClientAdapter = _EmptyAdapter();
  });

  setUp(() {
    NetworkSignal.reset();
    AppI18n.instance.setLocale('ar');
  });

  group('مفاتيح i18n — المرحلة 2+3', () {
    test('offline_sale_needed ومفاتيح التصدير موجودة بالثماني لغات', () {
      final AppI18n i18n = AppI18n.instance;
      for (final String locale in AppI18n.locales) {
        i18n.setLocale(locale);
        expect(
          i18n.t('errors', 'offline_sale_needed').startsWith('errors.'),
          isFalse,
          reason: 'مفتاح offline_sale_needed ناقص في $locale',
        );
        for (final String key in <String>['export_pdf', 'export_preparing', 'export_failed', 'export_empty']) {
          expect(
            i18n.t('reports', key).startsWith('reports.'),
            isFalse,
            reason: 'مفتاح reports.$key ناقص في $locale',
          );
        }
      }
      i18n.setLocale('ar');
    });

    test('نص الرسالة الهادئة يحمل المعنى الصحيح عربيًا وإنجليزيًا', () {
      final AppI18n i18n = AppI18n.instance;
      i18n.setLocale('ar');
      expect(i18n.t('errors', 'offline_sale_needed'), contains('البيع'));
      expect(i18n.t('errors', 'offline_sale_needed'), contains('الإنترنت'));
      i18n.setLocale('en');
      expect(i18n.t('errors', 'offline_sale_needed'), contains('internet connection'));
      i18n.setLocale('ar');
    });

    test('شارة offline_chip: عربي وإنجليزي صريحان، واللغات الجزئية تسقط للعربية', () {
      final AppI18n i18n = AppI18n.instance;
      i18n.setLocale('ar');
      expect(i18n.t('common', 'offline_chip'), 'غير متصل');
      i18n.setLocale('en');
      expect(i18n.t('common', 'offline_chip'), 'Offline');
      i18n.setLocale('fr');
      expect(i18n.t('common', 'offline_chip'), 'غير متصل',
          reason: 'اللغات الجزئية ترجع للعربية مثل دلالة deep-merge');
      i18n.setLocale('ar');
    });
  });

  group('شارة نقطة البيع — منطق الاتصال (المرحلة 2)', () {
    testWidgets('تظهر عند الانقطاع وتختفي عند العودة فورًا مع NetworkSignal',
        (WidgetTester tester) async {
      _stubSecureStorage(tester);
      // التحميلات الأولية تنجح (بديل الخادم) فتُرجع الإشارة «متصل» — هذا
      // صحيح بالتصميم: نتائج API هي مصدر الحقيقة. ثم نحاكي انقطاعًا حقيقيًا.
      await _pumpPOS(tester);
      NetworkSignal.noteNetworkFailure(); // منقطعون فعلًا
      await tester.pump(const Duration(milliseconds: 100));

      final exception = tester.takeException();
      if (exception != null) fail('استثناء build: $exception');

      expect(find.text('غير متصل'), findsOneWidget,
          reason: 'الشارة الكهرمانية في شريط نقطة البيع');
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);

      NetworkSignal.noteSuccess(); // عاد الاتصال — إخفاء تفاؤلي
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('غير متصل'), findsNothing);
      expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
    });
  });

  group('مصدّر التقارير PDF (المرحلة 3)', () {
    test('حارس المفاتيح الفارغة: فشل آمن report_capture_failed بلا منصة', () async {
      final ReportExportResult result = await shareReportPdf(
        boundaryKeys: const <GlobalKey>[],
        jobName: 'test-empty',
      );
      expect(result.ok, isFalse);
      expect(result.error, 'report_capture_failed');
    });

    testWidgets('شاشة تقرير المبيعات تعرض زر التصدير بعد جاهزية البيانات',
        (WidgetTester tester) async {
      _stubSecureStorage(tester);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: AppState(),
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
            home: const SalesReportScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final exception = tester.takeException();
      if (exception != null) fail('استثناء build: $exception');

      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget,
          reason: 'زر تصدير PDF يظهر مباشرة بعد جاهزية التقرير (حتى فارغًا)');
      expect(
        find.byTooltip(AppI18n.instance.t('reports', 'export_pdf')),
        findsOneWidget,
      );
    });
  });
}

// Task 110 — اختبار انحدار نقل إصلاح بحث POS بالويب (Task 103،
// product-search.tsx) إلى شاشة Flutter:
//   1) الأكواد الرقمية ≥6 أرقام تُبحث أثناء الكتابة كأي نص والقائمة تبقى
//      ظاهرة بدل الإخفاء النهائي لحظة اكتمال الكود (كانت isScannerCode
//      تقفل الجلسة وتلغي أي طلب جارٍ).
//   2) صندوق «لا نتائج» يشمل الأكواد الرقمية (كان مستثنى منه).
//   3) الإضافة (pick) تُنهي جلسة البحث بالكامل: إلغاء المؤجّل ورفع التسلسل
//      وتصفير سبينر البحث فورًا — نتيجة قديمة وصلت بعد الإضافة لا تفتح
//      القائمة شبحًا ولا تُبقي الدوران فوق حقل فارغ.
import 'dart:async';
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
import 'package:pharmacy_mobile/widgets/ui.dart';

/// صف منتج مطابق لشكل GET /pharmacy/pos/search (product + match_type/score).
/// strength فارغة كي يُعرض الاسم نصًا واحدًا بلا لاحقة تركيز (يثبّت find.text).
Map<String, dynamic> _row({String id = 'pr1', String name = 'بانادول إكسترا'}) =>
    <String, dynamic>{
      'id': id,
      'name': name,
      'generic_name': 'باراسيتامول',
      'strength': '',
      'barcode': '650123456789',
      'packaging_type': 'BOX_STRIP',
      'units_per_box': 24,
      'selling_price_piastres': 3600,
      'partial_selling_price_piastres': 200,
      'stock': 10,
      'match_type': 'barcode_exact',
      'score': 1.0,
    };

/// خادم مبرمَج: /pharmacy/pos/search يجيب فورًا بصفوف q من _instant،
/// أو يعلّق الطلب بـ Completer إذا كان q ضمن _hold (يتحكم الاختبار بإفلاته).
/// بقية المسارات: data فاضية (POS لا يجلب شيئًا آخر عند الفتح).
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._instant, {Set<String> hold = const <String>{}})
      : _hold = hold;

  final Map<String, List<dynamic>> _instant;
  final Set<String> _hold;
  final Map<String, Completer<ResponseBody>> held = <String, Completer<ResponseBody>>{};
  final List<String> queries = <String>[]; // سجل ترتيب طلبات البحث

  ResponseBody _rows(List<dynamic> rows) => ResponseBody.fromString(
        jsonEncode(<String, dynamic>{'data': rows}),
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/json'],
        },
      );

  void completeHeld(String q, List<dynamic> rows) {
    final Completer<ResponseBody>? c = held.remove(q);
    if (c != null && !c.isCompleted) c.complete(_rows(rows));
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.path.endsWith('/pharmacy/pos/search')) {
      final String q = options.uri.queryParameters['q'] ?? '';
      queries.add(q);
      if (_hold.contains(q)) {
        final Completer<ResponseBody> c = Completer<ResponseBody>();
        held[q] = c;
        return c.future;
      }
      return _rows(_instant[q] ?? <dynamic>[]);
    }
    return ResponseBody.fromString(
      jsonEncode(<String, dynamic>{'data': <dynamic>[]}),
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

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  // تجاوز التأجيل 180ms ثم إنجاز الاستجابة (المعلّقة لا تُنجَز هنا).
  await tester.pump(const Duration(milliseconds: 260));
  await tester.pump();
}

void main() {
  testWidgets('رمز باركود رقمي (6+ أرقام) يُبحث أثناء الكتابة والقائمة تبقى ظاهرة',
      (WidgetTester tester) async {
    _stubSecureStorage(tester);
    AppI18n.instance.setLocale('ar');
    final _ScriptedAdapter adapter = _ScriptedAdapter(
      <String, List<dynamic>>{'650123456789': <dynamic>[_row()]},
    );
    ApiClient.instance.dio.httpClientAdapter = adapter;
    await _pumpPOS(tester);
    expect(tester.takeException(), isNull);

    await _type(tester, '650123456789');

    expect(
      adapter.queries.contains('650123456789'),
      isTrue,
      reason: 'الكود الرقمي المكتمل يجب أن يُبحث كأي نص (كان isScannerCode '
          'يمنع البحث ويقفل القائمة نهائيًا — Task 103 بالويب / Task 110 هنا)',
    );
    expect(
      find.text('بانادول إكسترا'),
      findsOneWidget,
      reason: 'القائمة يجب أن تبقى ظاهرة للمنتج المطابق بالباركود',
    );
  });

  testWidgets('رمز رقمي بلا نتائج يُظهر صندوق «لا نتائج» لا الصمت',
      (WidgetTester tester) async {
    _stubSecureStorage(tester);
    AppI18n.instance.setLocale('ar');
    final _ScriptedAdapter adapter = _ScriptedAdapter(<String, List<dynamic>>{});
    ApiClient.instance.dio.httpClientAdapter = adapter;
    await _pumpPOS(tester);
    expect(tester.takeException(), isNull);

    await _type(tester, '999999');

    expect(
      adapter.queries.contains('999999'),
      isTrue,
      reason: 'الكود الرقمي يُبحث كأي نص فلا صمت عند عدم التطابق',
    );
    expect(
      find.text(AppI18n.instance.t('pos', 'noResults')),
      findsOneWidget,
      reason: 'صندوق «لا نتائج» كان يستثني الأكواد الرقمية (Task 103/110)',
    );
  });

  testWidgets('الإضافة تُنهي جلسة البحث: لا سبينر بعد الالتقاط ولا قائمة شبح',
      (WidgetTester tester) async {
    _stubSecureStorage(tester);
    AppI18n.instance.setLocale('ar');
    final _ScriptedAdapter adapter = _ScriptedAdapter(
      <String, List<dynamic>>{'para': <dynamic>[_row()]},
      hold: <String>{'parac'},
    );
    ApiClient.instance.dio.httpClientAdapter = adapter;
    await _pumpPOS(tester);
    expect(tester.takeException(), isNull);

    // بحث أول يكتمل → القائمة ظاهرة.
    await _type(tester, 'para');
    expect(find.text('بانادول إكسترا'), findsOneWidget);

    // كتابة إضافية → طلب ثاني معلّق قيد الطيران.
    await _type(tester, 'parac');
    expect(
      adapter.held.containsKey('parac'),
      isTrue,
      reason: 'يجب أن يكون الطلب الثاني قيد الطيران قبل الالتقاط',
    );

    // الالتقاط أثناء الطلب المعلّق.
    await tester.tap(find.text('بانادول إكسترا'));
    await tester.pump();

    expect(
      find.byType(LoaderSpin),
      findsNothing,
      reason: 'سبينر الحقل يجب أن يتصفّر فور الإضافة — قبل الإصلاح كان يظل '
          'يدور فوق حقل فارغ حتى وصول نتيجة قُطعت جلستها (نفس عائلة عيب '
          'السبينر المعلّق المُصلح بالويب)',
    );
    expect(
      find.text('بانادول إكسترا'),
      findsOneWidget,
      reason: 'المنتج الملتقط أُضيف للسلة مرة واحدة',
    );

    // النتيجة القديمة تصل بعد الإضافة → لا قائمة شبح ولا عودة للدوران.
    adapter.completeHeld('parac', <dynamic>[_row(id: 'ghost', name: 'منتج شبح')]);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(
      find.text('منتج شبح'),
      findsNothing,
      reason: 'نتيجة قديمة وصلت بعد الإضافة لا تفتح القائمة شبحًا',
    );
    expect(find.byType(LoaderSpin), findsNothing);
    expect(find.text('بانادول إكسترا'), findsOneWidget);
  });
}

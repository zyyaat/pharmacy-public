// Task 82 — أساس معمارية offline-first (المرحلة 1):
//   1) OfflineCache: كاش قراءة-عبر مشفّر — استجابات GET تُكتب، وفشل الشبكة
//      يعيد آخر نسخة (stale-if-error) — فيدخل التطبيق ويوجد بلا إنترنت.
//   2) NetworkSignal: إشارة الحالة من نتائج API الحقيقية + مراقب الواجهات.
//   3) OfflineBanner: الشريط الكهرماني أعلى الصفحات عند العمل من الكاش.
//   4) انحدار Task 81: مفاتيح splash_offline فُقدت في إعادة التوليد فكانت
//      بطاقة السپلاش تعرض المفتاح الخام — العودة لمصدر الحقيقة أصلحتها،
//      وهذا الاختبار يثبّتها.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pharmacy_mobile/core/offline.dart';
import 'package:pharmacy_mobile/core/strings.dart';
import 'package:pharmacy_mobile/widgets/ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    NetworkSignal.reset();
  });

  group('OfflineCache — منطق الكاش على مخزن ذاكرة', () {
    late OfflineCache cache;
    late MemoryOfflineStore store;

    setUp(() {
      store = MemoryOfflineStore();
      cache = OfflineCache(store: store);
    });

    test('حفظ وقراءة نفس الاستجابة (roundtrip)', () async {
      final Map<String, dynamic> payload = <String, dynamic>{
        'data': <dynamic>[<String, dynamic>{'id': 'p1', 'name': 'Panadol'}],
        'total': 1,
      };
      await cache.put('GET /pharmacy/inventory', payload);
      final Map<String, dynamic>? got = await cache.get('GET /pharmacy/inventory');
      expect(got, isNotNull);
      expect(got!['total'], 1);
      expect((got['data'] as List<dynamic>).first, isA<Map>());
    });

    test('مفتاح cacheKey يفرّق بين الاستعلامات المختلفة', () {
      final String a = OfflineCache.cacheKey('GET', '/pharmacy/pos/sales', <String, dynamic>{'limit': 20, 'offset': 0});
      final String b = OfflineCache.cacheKey('GET', '/pharmacy/pos/sales', <String, dynamic>{'offset': 0, 'limit': 20});
      final String c = OfflineCache.cacheKey('GET', '/pharmacy/pos/sales', <String, dynamic>{'limit': 20, 'offset': 20});
      expect(a, equals(b), reason: 'ترتيب معاملات الاستعلام لا يغيّر المفتاح');
      expect(a, isNot(equals(c)), reason: 'offset مختلف = صفحات مختلفة = مفتاح مختلف');
      expect(OfflineCache.cacheKey('GET', '/pharmacy/branches'),
          isNot(equals(OfflineCache.cacheKey('POST', '/pharmacy/branches'))));
    });

    test('مدخلة تالفة (JSON مكسور) تعيد null بلا انفجار', () async {
      await cache.put('GET /x', <String, dynamic>{'ok': 1});
      // نجتاح التخزين بقيمة تالفة تحت نفس المفتاح المجزأ
      await store.write('oc:${cache.hashKey('GET /x')}', 'not-json{{');
      expect(await cache.get('GET /x'), isNull);
    });

    test('إصدار قديم يُتجاهل (schemaVersion)', () async {
      await cache.put('GET /y', <String, dynamic>{'ok': 1});
      await store.write(
          'oc:${cache.hashKey('GET /y')}',
          jsonEncode(<String, dynamic>{'k': 'GET /y', 'v': 0, 'at': 1, 'd': <String, dynamic>{'stale': true}}));
      expect(await cache.get('GET /y'), isNull);
    });

    test('مدخلة أضخم من السقف تُتخطى ولا تُخزن', () async {
      final String big = 'x' * (OfflineCache.maxEntries + 1500000);
      await cache.put('GET /big', <String, dynamic>{'blob': big});
      expect(await cache.get('GET /big'), isNull);
    });

    test('trim: يُبقي الأحدث فقط ضمن maxEntries', () async {
      for (int i = 0; i < OfflineCache.maxEntries + 2; i++) {
        await cache.put(
          'GET /k$i',
          <String, dynamic>{'i': i},
          at: DateTime.fromMillisecondsSinceEpoch(1000 + i),
        );
      }
      expect(await cache.count(), OfflineCache.maxEntries);
      expect(await cache.get('GET /k0'), isNull, reason: 'الأقدم يُحذف أولًا');
      expect(await cache.get('GET /k1'), isNull, reason: 'ثاني الأقدم يُحذف أيضًا');
      expect(await cache.get('GET /k${OfflineCache.maxEntries + 1}'), isNotNull, reason: 'الأحدث يبقى');
    });

    test('clear يمسح المداخلات والفهرس معًا', () async {
      await cache.put('GET /a', <String, dynamic>{'v': 1});
      await cache.put('GET /b', <String, dynamic>{'v': 2});
      expect(await cache.count(), 2);
      await cache.clear();
      expect(await cache.count(), 0);
      expect(await cache.get('GET /a'), isNull);
      expect(await cache.get('GET /b'), isNull);
    });
  });

  group('NetworkSignal — إشارة الشبكة', () {
    test('فشل شبكة يرفع العلم ونجاح بعده يُنزله', () {
      expect(NetworkSignal.offline.value, isFalse);
      NetworkSignal.noteNetworkFailure();
      expect(NetworkSignal.offline.value, isTrue);
      NetworkSignal.noteSuccess();
      expect(NetworkSignal.offline.value, isFalse);
    });

    test('تكرار الإشارة لا يُطلق إشعارات زائدة', () {
      int notifications = 0;
      void listener() => notifications++;
      NetworkSignal.offline.addListener(listener);
      NetworkSignal.noteSuccess(); // بالفعل false — بلا إشعار
      NetworkSignal.noteNetworkFailure();
      NetworkSignal.noteNetworkFailure(); // بالفعل true — بلا إشعار
      NetworkSignal.noteSuccess();
      expect(notifications, 2);
      NetworkSignal.offline.removeListener(listener);
    });
  });

  testWidgets('OfflineBanner: عنوان + تلميح + أيقونة wifi-off بلا أحمر صارخ', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: OfflineBanner(
            title: 'لا يوجد اتصال بالإنترنت',
            hint: 'تُعرض البيانات المخزّنة على جهازك من آخر مزامنة',
          ),
        ),
      ),
    ));

    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    expect(find.text('لا يوجد اتصال بالإنترنت'), findsOneWidget);
    expect(find.text('تُعرض البيانات المخزّنة على جهازك من آخر مزامنة'), findsOneWidget);

    // لغة التحذير الهادئة: لا نصّ يستخدم الأحمر الصارخ (error) كما في Task 79
    final List<Text> texts = tester.widgetList<Text>(find.byType(Text)).toList();
    final Color errorColor = ThemeData().colorScheme.error;
    for (final Text t in texts) {
      final TextStyle? style = t.style;
      if (style?.color != null) {
        expect(style!.color, isNot(errorColor), reason: 'الشريط تحذير هادئ لا خطأ: "${t.data}"');
      }
    }
  });

  test('splash_offline يعود نصًّا حقيقيًا لا مفتاحًا خامًا — عربي وإنجليزي (انحدار Task 81)', () {
    final AppI18n i18n = AppI18n.instance;

    i18n.setLocale('ar');
    expect(i18n.t('common', 'splash_offline'), contains('تعذّر الاتصال'));
    expect(i18n.t('common', 'splash_offline_hint'), contains('المحاولة'));

    i18n.setLocale('en');
    expect(i18n.t('common', 'splash_offline'), contains('Cannot reach the server'));
    expect(i18n.t('common', 'splash_offline_hint'), contains('Retrying'));

    i18n.setLocale('ar');
  });

  test('مفاتيح شريط عدم الاتصال موجودة في عربي وإنجليزي (Task 82)', () {
    final AppI18n i18n = AppI18n.instance;

    i18n.setLocale('ar');
    expect(i18n.t('common', 'offline_banner_title'), 'لا يوجد اتصال بالإنترنت');
    expect(i18n.t('common', 'offline_banner_hint'), contains('المخزّنة'));

    i18n.setLocale('en');
    expect(i18n.t('common', 'offline_banner_title'), 'No internet connection');
    expect(i18n.t('common', 'offline_banner_hint'), contains('last sync'));

    i18n.setLocale('ar');
  });
}

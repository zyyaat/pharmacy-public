// Task 84 — offline-first المرحلة 4: الجلب الاستباقي (إحماء الكاش):
//   1) المسار السليم: أساسيات → تقرير 30 يومًا → صفحات المبيعات (يتوقف
//      عند أول صفحة ناقصة) → صفحات الحركات — ثم تُكتب علامة آخر نجاح.
//   2) العلامة داخل نافذة minInterval تمنع الإعادة (لا ضرب للخادم عند
//      كل فتح) — وانقضاؤها يعيد التشغيل.
//   3) الانقطاع قبل البدء = لا طلب واحد.
//   4) أول فشل في منتصف المسار يوقف البقية ولا تُكتب العلامة (المسار
//      المقطوع يعاد كاملًا في الإقلاع القادم).
//   5) انقلاب إشارة الشبكة للانقطاع أثناء العمل يوقفه فورًا — حتي لا
//      يُكمل «نجاحًا» وهميًا من كاش stale-if-error.
//   6) بوابة enabled تنعدم افتراضيًا (الاختبارات لا تلمس الشبكة الحقيقية).
import 'package:flutter_test/flutter_test.dart';

import 'package:pharmacy_mobile/core/offline.dart';
import 'package:pharmacy_mobile/core/prefetch.dart';

/// بديل API يسجّل كل طلب ويعيد أجسادًا مجدولة بالترتيب
class _FakeApi implements PrefetchApi {
  _FakeApi(this.bodies);

  /// الأجساد بالترتيب — القائمة تنفد فتعيد آخر جسم متاح
  final List<Map<String, dynamic>> bodies;

  final List<String> calls = <String>[];

  /// فهرس الطلب الذي يفشل استثناءً (شبكة) — -1 لا فشل
  int failAt = -1;

  /// فهرس الطلب الذي ينجح ويقلب الإشارة للانقطاع بعده (محاكاة العودة
  /// من كاش stale-if-error بعد فشل شبكي في _dispatch)
  int flipOfflineAt = -1;

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    final int idx = calls.length;
    calls.add('$path?${query == null ? '' : _q(query)}');
    if (idx == failAt) {
      NetworkSignal.noteNetworkFailure();
      throw Exception('network down');
    }
    if (idx == flipOfflineAt) {
      NetworkSignal.noteNetworkFailure();
    }
    return bodies[idx.clamp(0, bodies.length - 1)];
  }

  static String _q(Map<String, dynamic> query) {
    final keys = query.keys.toList()..sort();
    return keys.map((k) => '$k=${query[k]}').join('&');
  }
}

Map<String, dynamic> _salesPage(int count) => <String, dynamic>{
      'data': <String, dynamic>{
        'sales': List<dynamic>.generate(count, (int i) => <String, dynamic>{'id': 's$i'}),
        'total': count,
      },
    };

Map<String, dynamic> _movementsPage(int count) => <String, dynamic>{
      'data': <String, dynamic>{
        'movements':
            List<dynamic>.generate(count, (int i) => <String, dynamic>{'id': 'm$i'}),
        'total': count,
      },
    };

/// أجساد المسار السليم: مخزون + نواقص + عملاء + تقرير +
/// مبيعات (صفحة ممتلئة ثم ناقصة) + حركات (صفحتان ممتلئتان = سقف)
List<Map<String, dynamic>> _happyBodies() => <Map<String, dynamic>>[
      <String, dynamic>{'data': <dynamic>[]}, // inventory
      <String, dynamic>{'data': <dynamic>[]}, // low-stock
      <String, dynamic>{'data': <dynamic>[]}, // customers
      <String, dynamic>{'data': <String, dynamic>{'totals': <String, dynamic>{}}}, // report
      _salesPage(PrefetchService.salesPageSize), // sales p0
      _salesPage(30), // sales p1 ناقصة → توقف
      _movementsPage(PrefetchService.movementsPageSize), // movements p0
      _movementsPage(PrefetchService.movementsPageSize), // movements p1 (سقف الصفحات)
    ];

void main() {
  setUp(() {
    NetworkSignal.reset();
    PrefetchService.enabled = false; // كل اختبار يبدأ من الوضع الافتراضي
  });

  test('بوابة enabled منعدمة افتراضيًا — maybeWarm لا يلمس الشبكة إطلاقًا', () async {
    final api = _FakeApi(_happyBodies());
    final service = PrefetchService(
        api: api, cache: OfflineCache(store: MemoryOfflineStore()));
    await service.maybeWarm();
    expect(api.calls, isEmpty, reason: 'البوابة مغلقة — لا طلب واحد');
  });

  test('المسار السليم: 8 طلبات بالترتيب + توقف عند صفحة المبيعات الناقصة + علامة نجاح',
      () async {
    final store = MemoryOfflineStore();
    final api = _FakeApi(_happyBodies());
    final cache = OfflineCache(store: store);
    final service = PrefetchService(api: api, cache: cache);

    await service.warm();

    expect(api.calls.length, 8, reason: '3 أساسيات + تقرير + مبيعات×2 + حركات×2');
    expect(api.calls[4], contains('offset=0'), reason: 'صفحة المبيعات الأولى');
    expect(api.calls[5], contains('offset=100'), reason: 'الصفحة الثانية بإزاحة 100');
    expect(api.calls[5], contains('limit=100'));
    expect(api.calls.length, lessThan(10),
        reason: 'توقف عند الصفحة الناقصة: لا صفحة ثالثة للمبيعات');

    // العلامة كُتبت داخل الكاش نفسه
    final marker = await cache.get('meta:prefetch:last-warm');
    expect(marker, isNotNull);
    expect(marker!['at'], isA<num>());
    expect(await cache.count(), 1,
        reason: 'العلامة فقط — تخزين استجابات GET يجري في ApiClient._dispatch لا في الخدمة');
  });

  test('العلامة داخل نافذة minInterval تمنع الإعادة — وانقضاؤها يعيدها', () async {
    final cache = OfflineCache(store: MemoryOfflineStore());
    final api = _FakeApi(_happyBodies());
    final service = PrefetchService(api: api, cache: cache);

    await service.warm();
    expect(api.calls.length, 8);

    await service.warm(); // داخل الـ 6 ساعات الافتراضية
    expect(api.calls.length, 8, reason: 'لا إعادة قبل انقضاء النافذة');

    // خدمة جديدة بنافذة صفرية تُعيد التشغيل فورًا (نفس الكاش به العلامة)
    final api2 = _FakeApi(_happyBodies());
    final eager = PrefetchService(api: api2, cache: cache, minInterval: Duration.zero);
    await eager.warm();
    expect(api2.calls.length, 8, reason: 'انقضاء النافذة يعيد الإحماء كاملًا');
  });

  test('الانقطاع قبل البدء = لا طلب واحد', () async {
    NetworkSignal.noteNetworkFailure();
    final api = _FakeApi(_happyBodies());
    final service = PrefetchService(
        api: api, cache: OfflineCache(store: MemoryOfflineStore()));
    await service.warm();
    expect(api.calls, isEmpty);
  });

  test('أول فشل يوقف البقية ولا تُكتب العلامة — إعادة المحاولة لاحقًا تُكمل', () async {
    final cache = OfflineCache(store: MemoryOfflineStore());
    final api = _FakeApi(_happyBodies())..failAt = 2; // فشل طلب العملاء
    final service = PrefetchService(api: api, cache: cache);

    await service.warm();
    expect(api.calls.length, 3, reason: 'توقف عند أول فشل: لا تقرير ولا صفحات');
    expect(await cache.get('meta:prefetch:last-warm'), isNull,
        reason: 'المسار المقطوع لا يكتب العلامة');

    // الإقلاع القادم (بلا فشل): يعيد المسار كاملًا ويكتب العلامة
    NetworkSignal.reset();
    final api2 = _FakeApi(_happyBodies());
    final service2 = PrefetchService(api: api2, cache: cache);
    await service2.warm();
    expect(api2.calls.length, 8);
    expect(await cache.get('meta:prefetch:last-warm'), isNotNull);
  });

  test('انقلاب الإشارة للانقطاع أثناء العمل يوقف البقية فورًا', () async {
    final api = _FakeApi(_happyBodies())..flipOfflineAt = 4; // نجاح مبيعات p0 ثم انقطاع
    final service = PrefetchService(
        api: api, cache: OfflineCache(store: MemoryOfflineStore()));

    await service.warm();
    expect(api.calls.length, 5,
        reason: 'بعد انقلاب الإشارة لا يُطلب صفحة مبيعات ثانية ولا الحركات');
  });

  test('نافذة التقرير = آخر 30 يومًا بنفس صيغة شاشة التقارير', () async {
    final api = _FakeApi(_happyBodies());
    final service = PrefetchService(
        api: api, cache: OfflineCache(store: MemoryOfflineStore()));
    await service.warm();

    final reportCall = api.calls[3];
    expect(reportCall, startsWith('/pharmacy/reports/sales?'));
    expect(reportCall, contains('from='));
    expect(reportCall, contains('to='));
    // صيغة التاريخ YYYY-MM-DD
    expect(RegExp(r'from=\d{4}-\d{2}-\d{2}').hasMatch(reportCall), isTrue);
    expect(RegExp(r'to=\d{4}-\d{2}-\d{2}').hasMatch(reportCall), isTrue);
  });
}

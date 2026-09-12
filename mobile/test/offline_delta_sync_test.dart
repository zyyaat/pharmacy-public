// Task 87 — المزامنة الذكية (delta sync) — اختبارات العقد الكامل:
//   1) لا مؤشر ⇒ إحماء كامل + ping يؤسس المؤشر من ساعة الخادم.
//   2) إحماء لم يكتمل (تخطّي/قطع) ⇒ لا ping ولا تقديم للمؤشر.
//   3) مؤشر موجود ⇒ طلب /sync واحد: دمج المخزون (upsert + حذف +
//      إعادة حساب days_until_expiry/status + الترتيب) وتقدم المؤشر.
//   4) دمج العملاء (upsert رصيد + حذف).
//   5) دمج صفحات المبيعات كنافذة منطقية: الجديد رأس الصفحة الأولى.
//   6) دمج الحركات (إضافات رأس الصفحة).
//   7) overflow ⇒ جلب كامل للقسم عبر مسار القراءة-عبر.
//   8) فشل الدلتا ⇒ سقوط للإحماء؛ وإن لم يكتمل الإحماء يبقى المؤشر كما هو.
//   9) الانقطاع قبل البدء ⇒ لا طلب واحد.
//  10) قواعد الحقول المشتقة (out_of_stock/low_stock/expiring_soon/normal).
import 'package:flutter_test/flutter_test.dart';

import 'package:pharmacy_mobile/core/offline.dart';
import 'package:pharmacy_mobile/core/prefetch.dart';
import 'package:pharmacy_mobile/core/sync.dart';

const String cursorKey = 'meta:sync:cursor';
const String bootTime = '2026-09-12T08:00:00Z';
const String deltaTime = '2026-09-12T09:00:00Z';

String iso(DateTime d) => d.toIso8601String();
DateTime daysFromToday(int days) {
  final DateTime n = DateTime.now();
  return DateTime(n.year, n.month, n.day + days);
}

/// خادم وهمي يخدم المسارات بالتوجيه — يسجّل كل طلب، ويكتب للكاش مثل
/// ApiClient._dispatch (عقد القراءة-عبر: كل GET ناجح يُخزّن بنفس المفتاح)
/// — فيكشف اختبار overflow أي انحراف في صيغة المفاتيح بين sync وApiClient.
class _FakeApi implements SyncApi, PrefetchApi {
  _FakeApi({OfflineCache? cache}) : _cache = cache;

  final OfflineCache? _cache;

  final List<String> calls = <String>[];

  /// جسم استجابة /sync بلا since (bootstrap)
  Map<String, dynamic> bootBody = <String, dynamic>{
    'data': <String, dynamic>{'server_time': bootTime},
  };

  /// جسم /sync?since=… — null يعني رمي خطأ شبكة (فشل الدلتا)
  Map<String, dynamic>? deltaBody;

  /// أجساد الجلب الكامل عند overflow / refetch
  Map<String, dynamic> inventoryBody = <String, dynamic>{'data': <dynamic>[]};
  Map<String, dynamic> customersBody = <String, dynamic>{
    'data': <String, dynamic>{'customers': <dynamic>[]},
  };
  Map<String, dynamic> salesPageBody = <String, dynamic>{
    'data': <String, dynamic>{'sales': <dynamic>[], 'total': 0},
  };
  Map<String, dynamic> movementsPageBody = <String, dynamic>{
    'data': <String, dynamic>{'movements': <dynamic>[], 'total': 0},
  };

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    final String q = query == null ? '' : '?' + _q(query);
    calls.add('$path$q');
    final Map<String, dynamic> body = await _route(path, query);
    final OfflineCache? cache = _cache;
    if (cache != null) {
      await cache.put(OfflineCache.cacheKey('GET', path, query), body);
    }
    return body;
  }

  Future<Map<String, dynamic>> _route(String path, Map<String, dynamic>? query) async {
    if (path == '/pharmacy/sync') {
      if (query?['since'] == null) return bootBody;
      final Map<String, dynamic>? body = deltaBody;
      if (body == null) {
        NetworkSignal.noteNetworkFailure();
        throw Exception('network down');
      }
      return body;
    }
    if (path == '/pharmacy/inventory') return inventoryBody;
    if (path == '/pharmacy/customers') return customersBody;
    if (path == '/pharmacy/pos/sales') return salesPageBody;
    if (path == '/pharmacy/inventory/movements') return movementsPageBody;
    if (path == '/pharmacy/inventory/low-stock') {
      return <String, dynamic>{'data': <String, dynamic>{'items': <dynamic>[], 'total': 0}};
    }
    if (path == '/pharmacy/reports/sales') {
      return <String, dynamic>{'data': <String, dynamic>{'totals': <String, dynamic>{}}};
    }
    throw Exception('unexpected path $path');
  }
  static String _q(Map<String, dynamic> query) {
    final List<String> keys = query.keys.toList()..sort();
    return keys.map((String k) => '$k=${query[k]}').join('&');
  }
}

class _NoApi implements SyncApi, PrefetchApi {
  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) =>
      throw Exception('no network in this fake');
}

/// إحماء وهمي يسجّل الاستدعاء ويتحكم في النتيجة
class _FakeWarmer extends PrefetchService {
  _FakeWarmer() : super(api: _NoApi(), cache: OfflineCache(store: MemoryOfflineStore()));

  bool ran = false;
  bool succeed = true;

  @override
  Future<bool> warm() async {
    ran = true;
    return succeed;
  }
}

Map<String, dynamic> inventoryRow(
    {required String batchId, required String name, required int quantity,
    int minStock = 2, DateTime? expiry, String status = 'normal', int? days}) {
  return <String, dynamic>{
    'batch_id': batchId,
    'pharmacy_product_id': 'pp-$batchId',
    'global_product_id': 'gp-$batchId',
    'product_name': name,
    'generic_name': '',
    'brand_name': '',
    'barcode': '',
    'dosage_form': 'tablet',
    'strength': '1mg',
    'batch_number': 'B-$batchId',
    'unit': 'box',
    'quantity': quantity,
    'cost_per_unit_piastres': 100,
    'total_cost_piastres': 100 * quantity,
    'expiry_date': expiry == null ? null : iso(expiry),
    'days_until_expiry': days,
    'selling_price_piastres': 500,
    'partial_selling_price_piastres': 0,
    'packaging_type': 'WHOLE_ONLY',
    'units_per_box': 1,
    'min_stock_level': minStock,
    'branch_name': '',
    'status': status,
  };
}

Map<String, dynamic> customerRow({required String id, required String name,
    required int balance, required String createdAt}) {
  return <String, dynamic>{
    'id': id, 'name': name, 'phone': '',
    'balance_piastres': balance, 'created_at': createdAt,
  };
}

Map<String, dynamic> saleRow({required String id, required String createdAt,
    required int invoice, int returned = 0, String status = 'completed'}) {
  return <String, dynamic>{
    'id': id, 'invoice_number': invoice, 'status': status,
    'total_amount_piastres': 1000, 'discount_amount_piastres': 0,
    'payment_type': 'cash', 'customer_name': '', 'created_at': createdAt,
    'products_count': 1, 'total_quantity_base': 2,
    'returned_amount_piastres': returned, 'returns': <dynamic>[],
  };
}

Map<String, dynamic> movementRow({required String id, required String createdAt}) {
  return <String, dynamic>{
    'id': id, 'created_at': createdAt, 'movement_type': 'SALE',
    'quantity': -2.0, 'unit': 'box', 'product_name': 'p',
    'generic_name': null, 'batch_number': null, 'branch_name': null,
    'actor_name': null, 'reference_type': null, 'reason': null,
    'notes': null, 'quantity_after': 8.0,
  };
}

void main() {
  setUp(() {
    NetworkSignal.reset();
    PrefetchService.enabled = true; // الاختبارات تفتح البوابة عمدًا
  });

  tearDown(() {
    PrefetchService.enabled = false;
  });

  test('لا مؤشر ⇒ إحماء كامل + ping يؤسس المؤشر من ساعة الخادم', () async {
    final api = _FakeApi();
    final cache = OfflineCache(store: MemoryOfflineStore());
    final warmer = _FakeWarmer();
    final service = SyncService(api: api, cache: cache, warmer: warmer);

    await service.maybeRun();

    expect(warmer.ran, isTrue, reason: 'أول تشغيل = إحماء كامل');
    expect(api.calls.where((String c) => c.startsWith('/pharmacy/sync')), hasLength(1),
        reason: 'ping واحد بلا since');
    expect(api.calls, isNot(contains('/pharmacy/sync?since=')));
    final cursor = await cache.get(cursorKey);
    expect(cursor, isNotNull);
    expect(cursor!['since'], bootTime, reason: 'المؤشر من server_time لا من ساعة الجهاز');
  });

  test('إحماء لم يكتمل (تخطّي) ⇒ لا ping ولا مؤشر — حماية من إسقاط تغييرات',
      () async {
    final api = _FakeApi();
    final cache = OfflineCache(store: MemoryOfflineStore());
    final warmer = _FakeWarmer()..succeed = false;
    final service = SyncService(api: api, cache: cache, warmer: warmer);

    await service.maybeRun();

    expect(warmer.ran, isTrue);
    expect(api.calls, isEmpty, reason: 'الكاش ليس محدّثًا بالكامل ⇒ لا ping ولا مؤشر');
    expect(await cache.get(cursorKey), isNull);
  });

  test('مؤشر موجود ⇒ دمج المخزون: upsert + حذف + إعادة حساب المشتقات + مؤشر يتقدم',
      () async {
    final api = _FakeApi();
    final cache = OfflineCache(store: MemoryOfflineStore());
    // مؤشر سابق + قاعدة مخزون مخزّنة (صفّان)
    await cache.put(cursorKey, <String, dynamic>{'since': bootTime, 'at': 0});
    final rowA = inventoryRow(batchId: 'A', name: 'أول', quantity: 30,
        expiry: daysFromToday(400), days: 400);
    final rowB = inventoryRow(batchId: 'B', name: 'ثانٍ', quantity: 1,
        expiry: daysFromToday(400), days: 400);
    await cache.put('GET /pharmacy/inventory', <String, dynamic>{
      'data': <dynamic>[rowA, rowB],
    });

    // صف A تغيّر (بيع أغلب الدفعة + اقترب انتهاؤه) وB حُذف من الخادم.
    // days_until_expiry في الصف الوارد عالق على 400 عمدًا — الدمج يجب أن
    // يعيد حسابه من expiry_date (10 أيام) لا أن يوثق قيمة الخادم العالقة.
    final rowA2 = inventoryRow(batchId: 'A', name: 'أول', quantity: 5,
        expiry: daysFromToday(10), days: 400);
    api.deltaBody = <String, dynamic>{
      'data': <String, dynamic>{
        'server_time': deltaTime,
        'inventory': <String, dynamic>{
          'items': <dynamic>[rowA2],
          'deleted_ids': <dynamic>['B'],
          'overflow': false,
        },
      },
    };

    final service = SyncService(api: api, cache: cache, warmer: _FakeWarmer());
    await service.maybeRun();

    expect(api.calls.where((String c) => c.startsWith('/pharmacy/sync?since=')), hasLength(1));
    final merged = await cache.get('GET /pharmacy/inventory');
    final List<dynamic> rows = merged!['data'] as List<dynamic>;
    expect(rows, hasLength(1), reason: 'B حُذف عبر deleted_ids');
    final Map<String, dynamic> a = rows.first as Map<String, dynamic>;
    expect(a['quantity'], 5, reason: 'الصف المحدّث حلّ محل القديم');
    expect(a['status'], 'expiring_soon',
        reason: 'الكمية فوق الحد لكن الانتهاء خلال 10 أيام ≤ 90 ⇒ expiring_soon');
    expect(a['days_until_expiry'], 10,
        reason: 'العدّاد أُعيد حسابه من تاريخ الانتهاء لا بقيمة آخر مزامنة (400)');
    final cursor = await cache.get(cursorKey);
    expect(cursor!['since'], deltaTime, reason: 'المؤشر تقدّم إلى server_time');
  });

  test('مؤشر موجود ⇒ دمج العملاء: رصيد محدّث + حذف', () async {
    final api = _FakeApi();
    final cache = OfflineCache(store: MemoryOfflineStore());
    await cache.put(cursorKey, <String, dynamic>{'since': bootTime, 'at': 0});
    await cache.put('GET /pharmacy/customers', <String, dynamic>{
      'data': <String, dynamic>{
        'customers': <dynamic>[
          customerRow(id: 'c1', name: 'قديم', balance: 1000, createdAt: iso(daysFromToday(-5))),
          customerRow(id: 'c2', name: 'محذوف', balance: 0, createdAt: iso(daysFromToday(-6))),
        ],
      },
    });
    api.deltaBody = <String, dynamic>{
      'data': <String, dynamic>{
        'server_time': deltaTime,
        'customers': <String, dynamic>{
          'items': <dynamic>[
            customerRow(id: 'c1', name: 'قديم', balance: 400, createdAt: iso(daysFromToday(-5))),
            customerRow(id: 'c3', name: 'جديد', balance: 0, createdAt: iso(daysFromToday(-1))),
          ],
          'deleted_ids': <dynamic>['c2'],
          'overflow': false,
        },
      },
    };

    final service = SyncService(api: api, cache: cache, warmer: _FakeWarmer());
    await service.maybeRun();

    final merged = await cache.get('GET /pharmacy/customers');
    final List<dynamic> rows =
        (merged!['data'] as Map)['customers'] as List<dynamic>;
    expect(rows, hasLength(2), reason: 'c2 حُذف وc3 أُضيف');
    final Map<String, dynamic> first = rows.first as Map<String, dynamic>;
    expect(first['id'], 'c3', reason: 'الأحدث إنشاءً أولًا (ترتيب الخادم)');
    final c1 = rows.firstWhere((dynamic r) => (r as Map)['id'] == 'c1') as Map;
    expect(c1['balance_piastres'], 400, reason: 'الرصيد المحسوب خادميًا حلّ محل القديم');
  });

  test('مؤشر موجود ⇒ صفحات المبيعات كنافذة منطقية: الجديد رأس الصفحة الأولى',
      () async {
    final api = _FakeApi();
    final cache = OfflineCache(store: MemoryOfflineStore());
    await cache.put(cursorKey, <String, dynamic>{'since': bootTime, 'at': 0});
    final s1 = saleRow(id: 's1', createdAt: iso(daysFromToday(-1)), invoice: 2);
    final s2 = saleRow(id: 's2', createdAt: iso(daysFromToday(-2)), invoice: 1);
    await cache.put(SyncService.salesPageKey(0), <String, dynamic>{
      'data': <String, dynamic>{'sales': <dynamic>[s1, s2], 'total': 2},
    });

    final sNew = saleRow(id: 'sNew', createdAt: iso(daysFromToday(0)), invoice: 3);
    final s2b = saleRow(id: 's2', createdAt: iso(daysFromToday(-2)), invoice: 1,
        returned: 300, status: 'partially_returned');
    api.deltaBody = <String, dynamic>{
      'data': <String, dynamic>{
        'server_time': deltaTime,
        'sales': <String, dynamic>{
          'items': <dynamic>[sNew, s2b],
          'deleted_ids': <dynamic>[],
          'overflow': false,
        },
      },
    };

    final service = SyncService(api: api, cache: cache, warmer: _FakeWarmer());
    await service.maybeRun();

    final p0 = await cache.get(SyncService.salesPageKey(0));
    final List<dynamic> rows0 = (p0!['data'] as Map)['sales'] as List<dynamic>;
    expect(rows0, hasLength(3), reason: 'النافذة المدمجة كاملة في الصفحة الأولى');
    expect((rows0.first as Map)['id'], 'sNew', reason: 'الأحدث رأس الصفحة');
    final s2merged = rows0.firstWhere((dynamic r) => (r as Map)['id'] == 's2') as Map;
    expect(s2merged['returned_amount_piastres'], 300,
        reason: 'الفاتورة المُسترجَعة حلّ محل نسختها المخزّنة');
    expect(s2merged['status'], 'partially_returned');
  });

  test('overflow في قسم ⇒ جلب كامل لذلك القسم عبر مسار القراءة-عبر', () async {
    final cache = OfflineCache(store: MemoryOfflineStore());
    final api = _FakeApi(cache: cache);
    await cache.put(cursorKey, <String, dynamic>{'since': bootTime, 'at': 0});
    await cache.put('GET /pharmacy/inventory', <String, dynamic>{
      'data': <dynamic>[inventoryRow(batchId: 'old', name: 'x', quantity: 1)],
    });
    final fresh = inventoryRow(batchId: 'fresh', name: 'y', quantity: 9);
    api.inventoryBody = <String, dynamic>{'data': <dynamic>[fresh]};
    api.deltaBody = <String, dynamic>{
      'data': <String, dynamic>{
        'server_time': deltaTime,
        'inventory': <String, dynamic>{
          'items': <dynamic>[], 'deleted_ids': <dynamic>[], 'overflow': true,
        },
      },
    };

    final service = SyncService(api: api, cache: cache, warmer: _FakeWarmer());
    await service.maybeRun();

    expect(api.calls, contains('/pharmacy/inventory'),
        reason: 'overflow ⇒ جلب كامل بدل دمج دلتا ناقصة');
    final merged = await cache.get('GET /pharmacy/inventory');
    final List<dynamic> rows = merged!['data'] as List<dynamic>;
    expect(rows, hasLength(1));
    expect((rows.first as Map)['batch_id'], 'fresh');
  });

  test('فشل الدلتا ⇒ سقوط للإحماء؛ وإن لم يكتمل الإحماء يبقى المؤشر كما هو',
      () async {
    final api = _FakeApi()..deltaBody = null; // رمي خطأ عند since
    final cache = OfflineCache(store: MemoryOfflineStore());
    await cache.put(cursorKey, <String, dynamic>{'since': bootTime, 'at': 0});
    final warmer = _FakeWarmer()..succeed = false;
    final service = SyncService(api: api, cache: cache, warmer: warmer);

    await service.maybeRun();

    expect(warmer.ran, isTrue, reason: 'سقط للإحماء');
    final cursor = await cache.get(cursorKey);
    expect(cursor!['since'], bootTime,
        reason: 'لا تقديم للمؤشر على كاش غير محدّث بالكامل');
  });

  test('الانقطاع قبل البدء ⇒ لا طلب واحد', () async {
    NetworkSignal.noteNetworkFailure();
    final api = _FakeApi();
    final service = SyncService(
        api: api, cache: OfflineCache(store: MemoryOfflineStore()), warmer: _FakeWarmer());
    await service.maybeRun();
    expect(api.calls, isEmpty);
  });

  test('قواعد الحقول المشتقة: out_of_stock ثم low_stock ثم expiring_soon ثم normal',
      () {
    final far = daysFromToday(400);
    final near = daysFromToday(10);

    final out = inventoryRow(batchId: 'o', name: 'x', quantity: 0, expiry: far, days: 400);
    SyncService.refreshInventoryDerived(out);
    expect(out['status'], 'out_of_stock');

    final low = inventoryRow(batchId: 'l', name: 'x', quantity: 2, minStock: 2, expiry: far, days: 400);
    SyncService.refreshInventoryDerived(low);
    expect(low['status'], 'low_stock');

    final expiring = inventoryRow(batchId: 'e', name: 'x', quantity: 9, minStock: 2, expiry: near, days: 400);
    SyncService.refreshInventoryDerived(expiring);
    expect(expiring['status'], 'expiring_soon');
    expect(expiring['days_until_expiry'], 10);

    final normal = inventoryRow(batchId: 'n', name: 'x', quantity: 9, minStock: 2, expiry: far, days: 400);
    SyncService.refreshInventoryDerived(normal);
    expect(normal['status'], 'normal');

    // الحجر الصحي يُحفظ من قيمة الخادم حين لا تنطبق أولويات أعلى
    final quarantine = inventoryRow(batchId: 'q', name: 'x', quantity: 9, minStock: 2, expiry: far, days: 400, status: 'quarantined');
    SyncService.refreshInventoryDerived(quarantine);
    expect(quarantine['status'], 'quarantined');
  });
}

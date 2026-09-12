import 'api_client.dart';
import 'format.dart';
import 'offline.dart';
import 'prefetch.dart';

/// Task 87 — المزامنة الذكية (delta sync) فوق كاش المراحل 1–4.
///
/// المشكلة: الكاش «قراءة-عبر» يخزّن *الاستجابات* كاملة بمفاتيح URL، وخدمة
/// الإحماء كانت تعيد جلب القوائم كاملة (المخزون + العملاء + 3 صفحات مبيعات +
/// صفحتا حركات + التقرير) وتكتب فوق نفس المفاتيح — أي أن فتح التطبيق مع
/// الإنترنت كان يعيد تنزيل بيانات موجودة أصلًا على الجهاز، والحذف في قواعد
/// الخادم لا يصل للجهاز أبدًا.
///
/// الحل — عقد مزامنة تدريجية مع الخادم (api_level 59):
///
/// 1) مؤشر زمني (cursor) من **ساعة الخادم حصرًا**: بعد الإحماء الكامل يُطلب
///    `/pharmacy/sync` بلا since فيعيد server_time فقط — المؤشر لا يأتي من
///    ساعة الجهاز أبدًا (حماية من انحراف الساعة).
/// 2) عند كل جاهزية مع اتصال: طلب واحد رخيص
///    `GET /pharmacy/sync?since=<cursor>` يعيد **فقط ما تغيّر**: صفوف
///    المخزون/العملاء/الفواتير/الحركات المتغيرة + deleted_ids (قبور الحذف
///    من sync_tombstones) + server_time جديد.
/// 3) الدمج داخل أجساد الكاش المخزّنة نفسها: upsert بمعرّف الصف
///    (batch_id / id)، حذف deleted_ids، إعادة ترتيب بترتيب الخادم، وقطع عند
///    نفس سقوف الخادم (500/200/3×100/2×100) — فتبقى أجساد الكاش مطابقة
///    لما كان الخادم سيردّ به.
/// 4) الصفوف المتغيرة تأتي بنفس شكل صفوف نقاط القائمة حرفيًا (sync_rows.go
///    خادميًا) — فالدمج استبدال صف كامل بلا أي إعادة تشكيل.
/// 5) overflow=true في أي قسم (فجوة أطول من السقف) ⇒ جلب كامل لذلك القسم
///    عبر مسار القراءة-عبر العادي بدل دمج دلتا ناقصة.
/// 6) الحقول المشتقة الزمنية (days_until_expiry + status) تُعاد محليًا عند
///    كل دمج بنفس دلالة الخادم (migration 16) — فعدّاد الانتهاء لا يبقى
///    عالقًا بقيمة يوم آخر مزامنة.
/// 7) النواقص (low-stock) وتقرير 30 يومًا صغيران فتُجلب مجددًا كما هي.
/// 8) أي فشل ⇒ سقوط صامت للإحماء الكامل السابق بلا تغيير المؤشر — لا يكسر
///    شيئًا أبدًا، والمحاولة التالية عند الإقلاع القادم.
///
/// القواعد الثابتة (نفس انضباط PrefetchService):
/// - fire-and-forget لا يمس الإقلاع، لا يرمي أبدًا.
/// - أول فشل يوقف الدلتا كلها بهدوء — المؤشر يبقى كما هو فيُعاد لاحقًا.
/// - انقلاب إشارة الشبكة أثناء العمل يوقفه فورًا.
/// - بوابة [PrefetchService.enabled] نفسها تفعّله (main() فقط).

/// واجهة الجلب — تُحقن للاختبارات
abstract class SyncApi {
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query});
}

/// التنفيذ الحقيقي: نفس مسار _send في ApiClient — فيعمل الكاش قراءة-عبر
/// وإشارة الشبكة والتجديد عند 401 كما هي بلا أي منطق مزدوج.
class ApiSyncApi implements SyncApi {
  const ApiSyncApi();

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) =>
      ApiClient.instance.prefetchGet(path, query: query);
}

class SyncService {
  SyncService({SyncApi? api, OfflineCache? cache, PrefetchService? warmer})
      : _api = api ?? const ApiSyncApi(),
        _cache = cache ?? OfflineCache.instance,
        _warmer = warmer;

  static final SyncService instance = SyncService();

  final SyncApi _api;
  final OfflineCache _cache;
  final PrefetchService? _warmer;

  /// مؤشر آخر مزامنة ناجحة — مخزّن في الكاش نفسه (يمسح مع الخروج)
  static const String _cursorKey = 'meta:sync:cursor';

  // مفاتيح أقسام الكاش — بنفس صيغة OfflineCache.cacheKey التي يكتب بها
  // ApiClient وPrefetchService (بلا استعلام).
  static const String _inventoryKey = 'GET /pharmacy/inventory';
  static const String _customersKey = 'GET /pharmacy/customers';

  // مفاتيح الصفحات المقسّمة — مطابقة حرفيًا لما يكتبه ApiClient عند الطلب
  // بنفس الاستعلام (المفاتيح مرتبة ترتيبًا معجميًا: limit قبل offset).
  static String salesPageKey(int offset) =>
      'GET /pharmacy/pos/sales?limit=${PrefetchService.salesPageSize}&offset=$offset';
  static String movementsPageKey(int offset) =>
      'GET /pharmacy/inventory/movements?limit=${PrefetchService.movementsPageSize}&offset=$offset';

  /// نقطة الاستدعاء من AppState — تنعدم بلا بوابة التشغيل أو مع الانقطاع
  Future<void> maybeRun() async {
    if (!PrefetchService.enabled) return;
    if (NetworkSignal.offline.value) return;

    final String? cursor = await _readCursor();
    if (cursor == null) {
      await _bootstrap();
      return;
    }
    final bool ok = await _delta(cursor);
    if (!ok) {
      // خادم قديم بلا /sync أو فشل شبكي/منطقي — الإحماء الكامل السابق هو
      // شبكة الأمان؛ المؤشر لم يتغير فالمحاولة تعاد في الإقلاع القادم.
      await _bootstrap();
    }
  }

  /// الإحماء الكامل ثم توليد المؤشر من ساعة الخادم (وليس ساعة الجهاز).
  ///
  /// صرامة Task 87: المؤشر لا يتقدم إلا بعد إحماء كامل ناجح فعليًا — لو
  /// تخطّى الإحماء (نافذة الـ6 ساعات) أو قُطع في المنتصف فالكاش ليس محدّثًا
  /// بالكامل، وتقديم المؤشر حينها قد يُسقط تغييرات لم تصل أبدًا. في هذه
  /// الحالة يبقى المؤشر الحالي صالحًا (إن وُجد) وتُعاد المحاولة لاحقًا.
  Future<void> _bootstrap() async {
    final bool warmed = await (_warmer?.warm() ?? PrefetchService.instance.warm());
    if (!warmed) return;
    final Map<String, dynamic>? boot = await _step(() => _api.get('/pharmacy/sync'));
    final Object? data = boot?['data'];
    final Object? serverTime = data is Map ? data['server_time'] : null;
    if (serverTime is String && serverTime.isNotEmpty) {
      await _writeCursor(serverTime);
    }
  }

  /// المزامنة التدريجية — لا ترمي؛ تعيد true فقط عند نجاح كامل الدمج
  /// (حينها وحدها يتقدم المؤشر).
  Future<bool> _delta(String since) async {
    final Map<String, dynamic>? body =
        await _step(() => _api.get('/pharmacy/sync', query: <String, dynamic>{'since': since}));
    if (body == null) return false;
    if (NetworkSignal.offline.value) return false;

    final Object? raw = body['data'];
    if (raw is! Map) return false;
    final Map<String, dynamic> data = Map<String, dynamic>.from(raw);
    final Object? st = data['server_time'];
    final String serverTime = st is String && st.isNotEmpty ? st : since;

    final Object? inv = data['inventory'];
    if (inv is Map && !await _applyInventory(Map<String, dynamic>.from(inv))) return false;

    final Object? cust = data['customers'];
    if (cust is Map && !await _applyCustomers(Map<String, dynamic>.from(cust))) return false;

    final Object? sales = data['sales'];
    if (sales is Map && !await _applySales(Map<String, dynamic>.from(sales))) return false;

    final Object? movs = data['movements'];
    if (movs is Map && !await _applyMovements(Map<String, dynamic>.from(movs))) return false;

    // الصغيران الرخيصان: النواقص + تقرير آخر 30 يومًا (نافذة شاشة التقارير)
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    await _step(() => _api.get('/pharmacy/inventory/low-stock'));
    await _step(() => _api.get('/pharmacy/reports/sales', query: <String, dynamic>{
          'from': Fmt.isoDay(today.subtract(const Duration(days: 29))),
          'to': Fmt.isoDay(today),
        }));
    if (NetworkSignal.offline.value) return false;

    await _writeCursor(serverTime);
    return true;
  }

  // ------------------------------------------------------------- الأقسام

  /// المخزون: صف لكل دفعة — upsert بـ batch_id + حذف + ترتيب الخادم
  /// (الاسم ثم تاريخ الانتهاء NULLs أخيرًا) + قطع عند 500.
  Future<bool> _applyInventory(Map<String, dynamic> section) async {
    final List<dynamic> changed = (section['items'] as List<dynamic>?) ?? const <dynamic>[];
    final List<dynamic> deleted = (section['deleted_ids'] as List<dynamic>?) ?? const <dynamic>[];

    if (section['overflow'] == true) {
      return await _refetchBody('/pharmacy/inventory', null) != null;
    }

    final Map<String, dynamic>? cached = await _cache.get(_inventoryKey);
    if (cached == null) {
      if (changed.isEmpty && deleted.isEmpty) return true;
      return await _refetchBody('/pharmacy/inventory', null) != null; // قاعدة باردة
    }

    final Map<String, Map<String, dynamic>> byId = <String, Map<String, dynamic>>{};
    for (final Object? row in _listOf(cached['data'])) {
      final Map<String, dynamic> m = Map<String, dynamic>.from(row as Map);
      byId[m['batch_id'].toString()] = m;
    }
    for (final Object? id in deleted) {
      byId.remove(id.toString());
    }
    for (final Object? raw in changed) {
      final Map<String, dynamic> row = Map<String, dynamic>.from(raw as Map);
      refreshInventoryDerived(row);
      byId[row['batch_id'].toString()] = row;
    }

    final List<Map<String, dynamic>> merged = byId.values.toList()
      ..sort(compareInventoryRows);
    if (merged.length > 500) merged.removeRange(500, merged.length);

    return await _writeList(_inventoryKey, cached, merged);
  }

  /// العملاء: upsert بـ id + حذف + ترتيب الأحدث إنشاءً + قطع عند 200.
  Future<bool> _applyCustomers(Map<String, dynamic> section) async {
    final List<dynamic> changed = (section['items'] as List<dynamic>?) ?? const <dynamic>[];
    final List<dynamic> deleted = (section['deleted_ids'] as List<dynamic>?) ?? const <dynamic>[];

    if (section['overflow'] == true) {
      return await _refetchBody('/pharmacy/customers', null) != null;
    }

    final Map<String, dynamic>? cached = await _cache.get(_customersKey);
    if (cached == null) {
      if (changed.isEmpty && deleted.isEmpty) return true;
      return await _refetchBody('/pharmacy/customers', null) != null;
    }

    final Map<String, Map<String, dynamic>> byId = <String, Map<String, dynamic>>{};
    final Object? dataMap = cached['data'];
    final List<dynamic> rows =
        dataMap is Map ? (dataMap['customers'] as List<dynamic>? ?? const <dynamic>[]) : const <dynamic>[];
    for (final Object? row in rows) {
      final Map<String, dynamic> m = Map<String, dynamic>.from(row as Map);
      byId[m['id'].toString()] = m;
    }
    for (final Object? id in deleted) {
      byId.remove(id.toString());
    }
    for (final Object? raw in changed) {
      final Map<String, dynamic> row = Map<String, dynamic>.from(raw as Map);
      byId[row['id'].toString()] = row;
    }

    final List<Map<String, dynamic>> merged = byId.values.toList()
      ..sort((Map<String, dynamic> a, Map<String, dynamic> b) =>
          compareTsDesc(_tsOf(a['created_at']), _tsOf(b['created_at'])));
    if (merged.length > 200) merged.removeRange(200, merged.length);

    final Map<String, dynamic> out = Map<String, dynamic>.from(cached);
    out['data'] = <String, dynamic>{'customers': merged};
    return await _writeMap(_customersKey, out);
  }

  /// الفواتير: الصفحات المخزّنة تُعامل كنافذة منطقية واحدة (الأحدث أولًا)
  /// تُدمج ثم يُعاد توزيعها على نفس المفاتيح بالتتابع — الفاتورة الجديدة
  /// تدخل رأس الصفحة الأولى وتُزح الأقدم للصفحة التالية بدل أن تضيع.
  Future<bool> _applySales(Map<String, dynamic> section) async {
    final List<dynamic> changed = (section['items'] as List<dynamic>?) ?? const <dynamic>[];
    final List<dynamic> deleted = (section['deleted_ids'] as List<dynamic>?) ?? const <dynamic>[];

    return _applyPaged(
      section: section,
      changed: changed,
      deleted: deleted,
      path: '/pharmacy/pos/sales',
      rowKey: 'sales',
      pageKeyOf: salesPageKey,
      pageSize: PrefetchService.salesPageSize,
      maxPages: PrefetchService.salesMaxPages,
      rowsOf: _salesOf,
      idOf: (Map<String, dynamic> row) => row['id'].toString(),
      compare: compareSalesRows,
      splice: (Map<String, dynamic> data, List<Map<String, dynamic>> slice) =>
          data['sales'] = slice,
    );
  }

  /// الحركات: سجل إضافي حصرًا — الإضافات الجديدة تدخل رأس الصفحات المخزّنة.
  Future<bool> _applyMovements(Map<String, dynamic> section) async {
    final List<dynamic> changed = (section['items'] as List<dynamic>?) ?? const <dynamic>[];
    final List<dynamic> deleted = (section['deleted_ids'] as List<dynamic>?) ?? const <dynamic>[];

    return _applyPaged(
      section: section,
      changed: changed,
      deleted: deleted,
      path: '/pharmacy/inventory/movements',
      rowKey: 'movements',
      pageKeyOf: movementsPageKey,
      pageSize: PrefetchService.movementsPageSize,
      maxPages: PrefetchService.movementsMaxPages,
      rowsOf: _movementsOf,
      idOf: (Map<String, dynamic> row) => row['id'].toString(),
      compare: compareMovementRows,
      splice: (Map<String, dynamic> data, List<Map<String, dynamic>> slice) =>
          data['movements'] = slice,
    );
  }

  /// جوهر دمج القوائم المقسّمة — مشترك بين المبيعات والحركات:
  /// overflow ⇒ جلب صفحات كاملة؛ لا صفحات مخزّنة ⇒ جلب صفحات كاملة عند
  /// وجود تغييرات؛ وإلا دمج النافذة المنطقية وإعادة توزيعها بالتتابع على
  /// الصفحات المخزّنة فقط.
  Future<bool> _applyPaged({
    required Map<String, dynamic> section,
    required List<dynamic> changed,
    required List<dynamic> deleted,
    required String path,
    required String rowKey,
    required String Function(int offset) pageKeyOf,
    required int pageSize,
    required int maxPages,
    required List<dynamic> Function(Map<String, dynamic>?) rowsOf,
    required String Function(Map<String, dynamic>) idOf,
    required int Function(Map<String, dynamic>, Map<String, dynamic>) compare,
    required void Function(Map<String, dynamic>, List<Map<String, dynamic>>) splice,
  }) async {
    final List<String> keys = <String>[
      for (int i = 0; i < maxPages; i++) pageKeyOf(i * pageSize),
    ];

    if (section['overflow'] == true) {
      return await _refetchPages(keys, path, rowKey, pageSize) != null;
    }

    final List<Map<String, dynamic>?> pages = <Map<String, dynamic>?>[
      for (final String k in keys) await _cache.get(k),
    ];
    final bool anyCached = pages.any((Map<String, dynamic>? p) => p != null);
    if (!anyCached) {
      if (changed.isEmpty && deleted.isEmpty) return true;
      return await _refetchPages(keys, path, rowKey, pageSize) != null;
    }

    final Map<String, Map<String, dynamic>> byId = <String, Map<String, dynamic>>{};
    for (final Map<String, dynamic>? page in pages) {
      for (final Object? row in rowsOf(page)) {
        final Map<String, dynamic> m = Map<String, dynamic>.from(row as Map);
        byId[idOf(m)] = m;
      }
    }
    for (final Object? id in deleted) {
      byId.remove(id.toString());
    }
    for (final Object? raw in changed) {
      final Map<String, dynamic> row = Map<String, dynamic>.from(raw as Map);
      byId[idOf(row)] = row;
    }

    final List<Map<String, dynamic>> merged = byId.values.toList()..sort(compare);

    // إعادة التوزيع بالتتابع: كل صفحة مخزّنة تأخذ دفعتها التالية من
    // النافذة المدمجة — الصفحات الغائبة تبقى غائبة.
    int cursor = 0;
    for (int i = 0; i < keys.length; i++) {
      final Map<String, dynamic>? cached = pages[i];
      if (cached == null) continue;
      final List<Map<String, dynamic>> slice = cursor < merged.length
          ? merged.sublist(cursor, (cursor + pageSize) <= merged.length ? cursor + pageSize : merged.length)
          : <Map<String, dynamic>>[];
      cursor += pageSize;
      final Map<String, dynamic> out = Map<String, dynamic>.from(cached);
      final Object? dataMap = out['data'];
      if (dataMap is Map) {
        final Map<String, dynamic> dm = Map<String, dynamic>.from(dataMap);
        splice(dm, slice);
        out['data'] = dm;
      }
      if (!await _writeMap(keys[i], out)) return false;
    }
    return true;
  }

  // ------------------------------------------------------------ الأدوات

  /// خطوة محمية: أول فشل (أو انقلاب للانقطاع) يُبطل العمل — يُعاد null.
  Future<Map<String, dynamic>?> _step(Future<Map<String, dynamic>> Function() call) async {
    try {
      final Map<String, dynamic> body = await call();
      if (NetworkSignal.offline.value) return null;
      return body;
    } catch (_) {
      return null;
    }
  }

  /// جلب كامل عبر مسار القراءة-عبر (الكتابة للكاش تجري في ApiClient._dispatch)
  /// — يُستخدم عند overflow أو قاعدة باردة.
  Future<Map<String, dynamic>?> _refetchBody(String path, Map<String, dynamic>? query) =>
      _step(() => _api.get(path, query: query));

  Future<Map<String, dynamic>?> _refetchPages(
      List<String> keys, String path, String listKey, int pageSize) async {
    for (int i = 0; i < keys.length; i++) {
      final Map<String, dynamic>? body = await _refetchBody(
          path, <String, dynamic>{'limit': pageSize, 'offset': i * pageSize});
      if (body == null) return null;
      if (_listLen(body, listKey) < pageSize) break; // آخر صفحة
    }
    return const <String, dynamic>{};
  }

  static int _listLen(Map<String, dynamic>? body, String key) {
    if (body == null) return 0;
    final Object? data = body['data'] is Map ? Map<String, dynamic>.from(body['data'] as Map) : body;
    final Object? list = (data as Map<String, dynamic>)[key];
    return list is List ? list.length : 0;
  }

  static List<dynamic> _listOf(Object? data) => data is List ? data : const <dynamic>[];

  static List<dynamic> _salesOf(Map<String, dynamic>? page) {
    if (page == null) return const <dynamic>[];
    final Object? data = page['data'];
    if (data is! Map) return const <dynamic>[];
    return data['sales'] as List<dynamic>? ?? const <dynamic>[];
  }

  static List<dynamic> _movementsOf(Map<String, dynamic>? page) {
    if (page == null) return const <dynamic>[];
    final Object? data = page['data'];
    if (data is! Map) return const <dynamic>[];
    return data['movements'] as List<dynamic>? ?? const <dynamic>[];
  }

  Future<bool> _writeList(String key, Map<String, dynamic> cached, List<Map<String, dynamic>> rows) async {
    final Map<String, dynamic> out = Map<String, dynamic>.from(cached);
    out['data'] = rows;
    return await _writeMap(key, out);
  }

  Future<bool> _writeMap(String key, Map<String, dynamic> body) async {
    try {
      // put يحدّث زمن LRU إلى الآن — المفتاح صار الأحدث استخدامًا
      await _cache.put(key, body);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------ الحقول المشتقة الزمنية

  /// إعادة حساب days_until_expiry وstatus محليًا — نفس دلالة الخادم
  /// (migration 16): out_of_stock ← low_stock ← expiring_soon (expiry ≤
  /// اليوم + 90 يومًا) ← quarantined (تُحفظ من قيمة الخادم لأن
  /// is_quarantined لا يُعرض) ← normal.
  static void refreshInventoryDerived(Map<String, dynamic> row) {
    final DateTime? expiry = _dayOf(row['expiry_date']);
    if (expiry != null) {
      final DateTime today = _dayStart(DateTime.now());
      row['days_until_expiry'] = expiry.difference(today).inDays;
    }
    final int quantity = _asInt(row['quantity']);
    final int minLevel = _asInt(row['min_stock_level']);
    if (quantity <= 0) {
      row['status'] = 'out_of_stock';
    } else if (quantity <= minLevel) {
      row['status'] = 'low_stock';
    } else if (expiry != null &&
        !expiry.isAfter(_dayStart(DateTime.now()).add(const Duration(days: 90)))) {
      row['status'] = 'expiring_soon';
    } else if (row['status'] == 'quarantined') {
      row['status'] = 'quarantined';
    } else {
      row['status'] = 'normal';
    }
  }

  static int _asInt(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  /// تاريخ ISO → بداية اليوم بتوقيت الجهاز (الخادم يحسب CURRENT_DATE محليًا)
  static DateTime? _dayOf(Object? v) {
    final DateTime? ts = _tsOf(v);
    return ts == null ? null : DateTime(ts.year, ts.month, ts.day);
  }

  static DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  /// timestamp من قيمة JSON المخزنة — ISO8601 نصًا بعد جولة الكاش
  static DateTime? _tsOf(Object? v) {
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  /// مقارنة تنازلية آمنة لقيم التوقيت (null = الأقدم)
  static int compareTsDesc(DateTime? a, DateTime? b) {
    if (a == b) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  /// ترتيب المخزون كما يخدمه الخادم: الاسم ثم تاريخ الانتهاء NULLs أخيرًا
  static int compareInventoryRows(Map<String, dynamic> a, Map<String, dynamic> b) {
    final String an = a['product_name']?.toString() ?? '';
    final String bn = b['product_name']?.toString() ?? '';
    final int byName = an.compareTo(bn);
    if (byName != 0) return byName;
    final DateTime? ae = _tsOf(a['expiry_date']);
    final DateTime? be = _tsOf(b['expiry_date']);
    if (ae == null && be == null) return 0;
    if (ae == null) return 1; // NULLs last
    if (be == null) return -1;
    return ae.compareTo(be);
  }

  /// ترتيب الفواتير كما يخدمه الخادم: created_at ثم invoice_number تنازليًا
  static int compareSalesRows(Map<String, dynamic> a, Map<String, dynamic> b) {
    final int byTs = compareTsDesc(_tsOf(a['created_at']), _tsOf(b['created_at']));
    if (byTs != 0) return byTs;
    final int an = _asInt(a['invoice_number']);
    final int bn = _asInt(b['invoice_number']);
    return bn.compareTo(an);
  }

  /// ترتيب الحركات كما يخدمه الخادم: created_at ثم id تنازليًا
  static int compareMovementRows(Map<String, dynamic> a, Map<String, dynamic> b) {
    final int byTs = compareTsDesc(_tsOf(a['created_at']), _tsOf(b['created_at']));
    if (byTs != 0) return byTs;
    return (b['id']?.toString() ?? '').compareTo(a['id']?.toString() ?? '');
  }

  // ------------------------------------------------------------ المؤشر

  Future<String?> _readCursor() async {
    try {
      final Map<String, dynamic>? m = await _cache.get(_cursorKey);
      final Object? since = m?['since'];
      return since is String && since.isNotEmpty ? since : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCursor(String serverTime) async {
    try {
      await _cache.put(_cursorKey, <String, dynamic>{
        'since': serverTime,
        'at': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {
      // الكاش إضافة — فشله لا يمس شيئًا
    }
  }
}

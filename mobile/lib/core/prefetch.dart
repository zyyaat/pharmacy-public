import 'api_client.dart';
import 'format.dart';
import 'offline.dart';

/// Task 84 — offline-first المرحلة 4: الجلب الاستباقي (cache warming).
///
/// كاش المرحلة 1 كان «قراءة-عبر» صرفًا: لا يُخزَّن إلا ما زاره المستخدم
/// وهو متصل — فالدخول بلا إنترنت بعد إقلاع جديد يجد كاشًا نحيفًا (صفحة
/// مبيعات واحدة ربما). الجلب الاستباقي يسخّن الكاش بعد جاهزية الجلسة
/// والاتصال، فتحقيق طلب المستخدم الحرفي: «سجلات كثيرة في الكاش مثل شهر
/// ماضٍ لا قليلين»:
///
/// 1) الأساسيات: المخزون + نواقصه + العملاء (تنقّل كامل بلا إنترنت).
/// 2) تقرير آخر 30 يومًا — ليشتغل تصدير PDF (المرحلة 3) بلا إنترنت
///    مباشرة بعد الإقلاع، لا بعد زيارة صفحة التقارير أولًا.
/// 3) صفحات المبيعات الحديثة (حتى 3×100 = 300 فاتورة ≈ شهر فأكثر).
/// 4) صفحات حركات المخزون (حتى 2×100 = 200 حركة).
///
/// القواعد الثابتة:
/// - تسلسلي لا متوازٍ (لطف بالخادم) وfire-and-forget (لا يمس الإقلاع).
/// - أول فشل يوقف كل شيء بهدوء — المحاولة القادمة عند الإقلاع التالي.
/// - انقلاب إشارة الشبكة للانقطاع أثناء العمل يوقفه فورًا (حتى لا
///   نكمل «نجاحًا» وهميًا من كاش stale-if-error).
/// - لا يُعاد قبل انقضاء [minInterval] من آخر نجاح كامل (علامة في
///   الكاش نفسه) — فلا نضرب الخادم عند كل فتح للتطبيق.
/// - الخدمة لا ترمي أبدًا: كل الأخطاء تُبتلع، فهي تحسين لا شرط.

/// واجهة الجلب — تُحقن للاختبارات (بديل وهمي يسجّل الطلبات)
abstract class PrefetchApi {
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query});
}

/// التنفيذ الحقيقي: نفس مسار _send العادي في ApiClient — فيعمل الكاش
/// قراءة-عبر وإشارة الشبكة والتجديد عند 401 كما هي بلا أي منطق مزدوج.
class ApiPrefetchApi implements PrefetchApi {
  const ApiPrefetchApi();

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) =>
      ApiClient.instance.prefetchGet(path, query: query);
}

class PrefetchService {
  PrefetchService({
    PrefetchApi? api,
    OfflineCache? cache,
    this.minInterval = const Duration(hours: 6),
  })  : _api = api ?? const ApiPrefetchApi(),
        _cache = cache ?? OfflineCache.instance;

  static final PrefetchService instance = PrefetchService();

  /// بوابة التشغيل: main() يفعّلها في التطبيق الحقيقي فقط — الاختبارات
  /// التي تبني AppState مباشرة لا تحتاج إحماءً ولا يجوز أن تلمس الشبكة.
  static bool enabled = false;

  final PrefetchApi _api;
  final OfflineCache _cache;

  /// لا يُعاد الإحماء قبل انقضاء هذه المدة من آخر نجاح كامل
  final Duration minInterval;

  /// علامة آخر إحماء ناجح — مخزّنة في الكاش نفسه (تُمسح مع الخروج)
  static const String _markerKey = 'meta:prefetch:last-warm';

  // أعمق الجلب — سقوف الخادم: المبيعات 100/صفحة (sales_history_handler)،
  // الحركات 200/صفحة (inventory_movements_handler).
  static const int salesPageSize = 100;
  static const int salesMaxPages = 3; // حتى 300 فاتورة حديثة
  static const int movementsPageSize = 100;
  static const int movementsMaxPages = 2; // حتى 200 حركة

  /// نقطة الاستدعاء من AppState — تنعدم بلا بوابة التشغيل
  Future<void> maybeWarm() async {
    if (!enabled) return;
    await warm();
  }

  /// يشغّل الإحماء بالكامل. لا يرمي أبدًا — كل خطأ يوقف العمل بهدوء.
  /// تعيد true فقط عند إكمال المسار كاملًا (تجاهلها يعني: تخطي بسبب
  /// النافذة/الانقطاع أو قطع في المنتصف — والكاش حينها ليس محدّثًا بالكامل
  /// فلا يجوز لمؤشر المزامنة التدريجية أن يتقدم على أساسه — Task 87).
  Future<bool> warm() async {
    if (NetworkSignal.offline.value) return false;

    final int? last = await _readMarker();
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    if (last != null && nowMs - last < minInterval.inMilliseconds) return false;

    bool aborted = false;

    Future<Map<String, dynamic>?> step(Future<Map<String, dynamic>> Function() call) async {
      if (aborted) return null;
      try {
        final Map<String, dynamic> body = await call();
        // stale-if-error قد يعيد كاشًا قديمًا بعد فشل شبكي دون رمي خطأ —
        // لكن الإشارة تكون قد انقلبت للانقطاع فنتوقف بدل مواصلة عمل وهمي
        if (NetworkSignal.offline.value) {
          aborted = true;
          return null;
        }
        return body;
      } catch (_) {
        aborted = true; // أول فشل يوقف — يعاد المحاولة في الإقلاع القادم
        return null;
      }
    }

    // 1) الأساسيات — تنقّل كامل بلا إنترنت
    await step(() => _api.get('/pharmacy/inventory'));
    await step(() => _api.get('/pharmacy/inventory/low-stock'));
    await step(() => _api.get('/pharmacy/customers'));

    // 2) تقرير آخر 30 يومًا — نفس نافذة شاشة التقارير الافتراضية
    //    (reports_screen: من اليوم −29 إلى اليوم) ليصدر PDF فورًا
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    await step(() => _api.get('/pharmacy/reports/sales', query: <String, dynamic>{
          'from': Fmt.isoDay(today.subtract(const Duration(days: 29))),
          'to': Fmt.isoDay(today),
        }));

    // 3+4) صفحات القوائم المقسّمة — نستمر طالما الصفحة ممتلئة
    Future<void> pages(String path, String listKey, int pageSize, int maxPages) async {
      for (int i = 0; i < maxPages; i++) {
        if (aborted) return;
        final Map<String, dynamic>? body = await step(() =>
            _api.get(path, query: <String, dynamic>{'limit': pageSize, 'offset': i * pageSize}));
        if (aborted) return;
        if (_listLen(body, listKey) < pageSize) return; // آخر صفحة
      }
    }

    await pages('/pharmacy/pos/sales', 'sales', salesPageSize, salesMaxPages);
    await pages('/pharmacy/inventory/movements', 'movements', movementsPageSize, movementsMaxPages);

    // العلامة بعد نجاح كامل فقط — المسار المقطوع يعاد كاملًا لاحقًا
    if (!aborted) {
      await _cache.put(_markerKey, <String, dynamic>{'at': nowMs});
      return true;
    }
    return false;
  }

  /// طول قائمة داخل استجابة خام (data.sales / data.movements) — 0 عند أي شك
  static int _listLen(Map<String, dynamic>? body, String key) {
    if (body == null) return 0;
    final Object? data = body['data'] is Map
        ? Map<String, dynamic>.from(body['data'] as Map)
        : body;
    final Object? list = (data as Map<String, dynamic>)[key];
    return list is List ? list.length : 0;
  }

  Future<int?> _readMarker() async {
    try {
      final Map<String, dynamic>? m = await _cache.get(_markerKey);
      final Object? at = m?['at'];
      return at is num ? at.toInt() : null;
    } catch (_) {
      return null;
    }
  }
}

import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Task 82 — أساس معمارية offline-first (المرحلة 1):
///
/// 1) OfflineCache — كاش «قراءة-عبر» (read-through / stale-if-error) لاستجابات
///    GET على تخزين مشفّر: كل استجابة ناجحة تُكتب، وعند فشل الشبكة تُعاد
///    آخر نسخة مخزّنة بدل رمي خطأ — فيتنقل المستخدم داخل التطبيق بلا إنترنت
///    (سجلات آخر شهر، المخزون، العملاء…) ويتعامل العمليات المكتوبة (بيع/
///    تعديل) مع الخادم كما هي.
///
/// 2) NetworkSignal — إشارة «هل نحن منقطعون فعلًا؟» يغذيها أدقّ مصدر متاح:
///    نتائج API نفسها (نجاح = متصل، فشل شبكة = منقطع) + مراقب واجهات الجهاز
///    (wifi/بيانات) للكشف الفوري. الشريط في الواجهة يستمع لها.
///
/// مبدأ ثابت: الكاش يجوز أن يفشل بصمت — لا يجوز أن يكسر استدعاء API أبدًا.
/// كل الدوال تبتلع أخطاء التخزين وتكمل، والقراءة الفاشلة تعيد null.

/// مخزن الكاش المجرد — قابل للحقن (اختبارات تستخدم الذاكرة، التطبيق مشفّر)
abstract class OfflineStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// المخزن الحقيقي: نفس تشفير SessionStore (Keystore عبر
/// EncryptedSharedPreferences) — بيانات أعمال مرتبطة بجلسة مستخدم.
class SecureOfflineStore implements OfflineStore {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// مخزن اختبارات — خريطة في الذاكرة فقط
class MemoryOfflineStore implements OfflineStore {
  final Map<String, String> _map = <String, String>{};

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> write(String key, String value) async {
    _map[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _map.remove(key);
  }
}

class OfflineCache {
  OfflineCache({OfflineStore? store}) : _store = store ?? SecureOfflineStore();

  static final OfflineCache instance = OfflineCache();

  final OfflineStore _store;

  /// إصدار بنية المدخلة — تغيّره يُبطل الكاش القديم كله دفعة واحدة
  static const int schemaVersion = 1;

  /// حد المداخلات (LRU بالزمن): صفحات المخزون/المبيعات/العملاء الأخيرة —
  /// عمليًا يغطي سجلات الشهور الأخيرة دون نمو غير محدود للتخزين.
  static const int maxEntries = 150;

  /// سقف حجم المدخلة الواحدة بالبايت المشفّرة — حماية من استجابة شاذة ضخمة
  static const int _maxEntryBytes = 1500000;

  static const String _indexKey = 'oc:index';
  static const String _prefix = 'oc:';

  /// مفتاح كاش موحّد لاستدعاء API: الطريقة + المسار + الاستعلام مرتبًا.
  /// عام ليُختبر ويُستخدم من ApiClient بنفس الدلالة.
  static String cacheKey(String method, String path, [Map<String, dynamic>? query]) {
    if (query == null || query.isEmpty) return '$method $path';
    final List<String> keys = query.keys.toList()..sort();
    final String q = keys.map((String k) => '$k=${query[k]}').join('&');
    return '$method $path?$q';
  }

  /// تجزئة FNV-1a (63 بت آمنة) — مفتاح تخزين قصير من مفتاح طويل.
  /// عامة: تستخدمها الاختبارات للوصول إلى مفتاح التخزين الخام.
  String hashKey(String key) {
    int h = 0xcbf29ce484222325;
    for (int i = 0; i < key.length; i++) {
      h ^= key.codeUnitAt(i);
      h = (h * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF;
    }
    return h.toRadixString(36);
  }

  Map<String, int> _decodeIndex(String? raw) {
    if (raw == null || raw.isEmpty) return <String, int>{};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return <String, int>{};
    return decoded.map<String, int>((k, v) => MapEntry(k.toString(), (v is num ? v : 0).toInt()));
  }

  /// آخر استجابة مخزّنة للمفتاح — null إن لم توجد أو كان الإصدار مختلفًا
  Future<Map<String, dynamic>?> get(String key) async {
    try {
      final raw = await _store.read('$_prefix${hashKey(key)}');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      if (decoded['k'] != key) return null; // دفاع من تصادم التجزئة
      if (decoded['v'] != schemaVersion) return null;
      final data = decoded['d'];
      if (data is Map) return Map<String, dynamic>.from(data);
    } catch (_) {
      // تالف/فشل تخزين = لا كاش — الاستدعاء يكمل مساره الطبيعي
    }
    return null;
  }

  /// تخزين استجابة ناجحة (أحدث زمن الحفظ = وقت الاستدعاء)
  Future<void> put(String key, Map<String, dynamic> data, {DateTime? at}) async {
    try {
      final int ms = (at ?? DateTime.now()).millisecondsSinceEpoch;
      final String entry = jsonEncode(<String, dynamic>{
        'k': key,
        'v': schemaVersion,
        'at': ms,
        'd': data,
      });
      if (entry.length > _maxEntryBytes) return; // استجابة شاذة ضخمة — لا نختنق بالتخزين
      await _store.write('$_prefix${hashKey(key)}', entry);
      final Map<String, int> index = _decodeIndex(await _store.read(_indexKey));
      index[key] = ms;
      await _store.write(_indexKey, jsonEncode(index));
      if (index.length > maxEntries) await _trim(index);
    } catch (_) {
      // الكاش أمر إضافي — فشله لا يمس استجابة API أبدًا
    }
  }

  /// إبقاء الأحدث فقط ضمن maxEntries (LRU بزمن الحفظ)
  Future<void> _trim(Map<String, int> index) async {
    final List<String> keys = index.keys.toList()
      ..sort((String a, String b) => index[a]!.compareTo(index[b]!));
    for (final String k in keys.take(index.length - maxEntries)) {
      await _store.delete('$_prefix${hashKey(k)}');
      index.remove(k);
    }
    await _store.write(_indexKey, jsonEncode(index));
  }

  /// مسح كل الكاش — يُستدعى عند تسجيل الخروج ورفض الجلسة:
  /// بيانات الأعمال المخزّنة مرتبطة بجلسة مستخدم ولا تجوز أن تُترك على جهاز
  /// مشترك بعد نهاية الجلسة.
  Future<void> clear() async {
    try {
      final Map<String, int> index = _decodeIndex(await _store.read(_indexKey));
      for (final String k in index.keys) {
        await _store.delete('$_prefix${hashKey(k)}');
      }
    } catch (_) {/* نمسح ما نستطيع */}
    try {
      await _store.delete(_indexKey);
    } catch (_) {}
  }

  /// عدد المداخلات الحية — للتشخيص والاختبارات
  Future<int> count() async {
    try {
      return _decodeIndex(await _store.read(_indexKey)).length;
    } catch (_) {
      return 0;
    }
  }
}

/// إشارة حالة الشبكة الحقيقية — مصدر واحد تسمعه الواجهة (شريط عدم الاتصال).
/// الأصدق: نتائج API نفسها (نجاح حقيقي ≠ واجهة wifi مفعّلة بلا إنترنت).
class NetworkSignal {
  NetworkSignal._();

  /// true = آخر ما عرفناه أن الخادم غير مصول إليه
  static final ValueNotifier<bool> offline = ValueNotifier<bool>(false);

  static void noteSuccess() {
    if (offline.value) offline.value = false;
  }

  static void noteNetworkFailure() {
    if (!offline.value) offline.value = true;
  }

  /// للاختبارات — يعيد الحالة الافتراضية «متصل»
  static void reset() {
    offline.value = false;
  }
}

/// مراقبة واجهات الجهاز (wifi/بيانات الجوال) — طبقة تعزيز للكشف الفوري
/// فوق إشارة API: قطع الواجهة يظهر الشريط فورًا بلا انتظار أول استدعاء،
/// وعودة الواجهة تُخفيه تفاؤليًا (أي فشل API حقيقي يعيده فورًا).
/// كل شيء محمي: بيئة بلا قناة المنصة (اختبارات) تكمل بصمت.
Future<void> startConnectivityWatch() async {
  try {
    try {
      final List<ConnectivityResult> current = await Connectivity().checkConnectivity();
      if (current.contains(ConnectivityResult.none)) NetworkSignal.noteNetworkFailure();
    } catch (_) {}
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> status) {
      if (status.contains(ConnectivityResult.none)) {
        NetworkSignal.noteNetworkFailure();
      } else {
        NetworkSignal.noteSuccess();
      }
    });
  } catch (_) {
    // فشل المراقب لا يهم — إشارة نتائج API وحدها تكفي
  }
}

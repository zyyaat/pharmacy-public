import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Task 59 — جلسة كوكيز يدوية تعادل سلوك المتصفح مع الباك اند.
///
/// الباك اند يوثّق عبر كوكيز معتمة (pharmacy_access / pharmacy_refresh /
/// pharmacy_csrf) ولا يقبل Authorization: Bearer إطلاقًا، لذا التطبيق:
/// 1) يمتص ترويسات Set-Cookie من كل استجابة (حتى الأخطاء 401 التي تمسح الكوكيز)
/// 2) يعيد إرسالها في كل طلب لنفس المضيف
/// 3) MaxAge<0 أو قيمة فارغة ⇒ حذف الكوكي (سلوك clearAuthCookies في الخادم)
/// 4) تخزين دائم في التخزين الآمن واستعادة تلقائية عند إقلاع التطبيق
///
/// نتجاهل خاصية Path عمدًا ونرسل الكل لكل طلب — كل نداءاتنا على نفس المضيف
/// وخادمنا يهمل الكوكيز غير المطابقة، وهذا أبسط وأكثر مرونة من محاكاة RFC.
class SessionCookies {
  static const String _storageKey = 'pharmacy_session_cookies';
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final Map<String, String> _byName = {};
  bool _loaded = false;

  String? operator [](String name) => _byName[name];

  String? get csrf => _byName['pharmacy_csrf'];
  bool get isEmpty => _byName.isEmpty;

  String? header() {
    if (_byName.isEmpty) return null;
    return _byName.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// يمتص ترويسات set-cookie الخام القادمة من dio (قائمة نصوص).
  void absorb(List<String>? rawSetCookies) {
    if (rawSetCookies == null || rawSetCookies.isEmpty) return;
    var changed = false;
    for (final raw in rawSetCookies) {
      if (raw.trim().isEmpty) continue;
      try {
        final c = Cookie.fromSetCookieValue(raw);
        final maxAge = c.maxAge; // int? — كوكي الجلسة بلا Max-Age تأتي null
        if (c.value.isEmpty || (maxAge != null && maxAge < 0)) {
          if (_byName.containsKey(c.name)) {
            _byName.remove(c.name);
            changed = true;
          }
        } else {
          if (_byName[c.name] != c.value) {
            _byName[c.name] = c.value;
            changed = true;
          }
        }
      } catch (_) {
        // ترويسة مشوهة — نتجاهلها كما يفعل المتصفح
      }
    }
    if (changed) _persist();
  }

  void clear() {
    if (_byName.isEmpty && _loaded) return;
    _byName.clear();
    _persist();
  }

  Future<void> restore() async {
    if (_loaded) return;
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            if (k is String && v is String && v.isNotEmpty) {
              _byName[k] = v;
            }
          });
        }
      }
    } catch (_) {
      _byName.clear();
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    try {
      if (_byName.isEmpty) {
        await _storage.delete(key: _storageKey);
      } else {
        await _storage.write(key: _storageKey, value: jsonEncode(_byName));
      }
    } catch (_) {
      // فشل التخزين لا يجب أن يكسر الجلسة الحية في الذاكرة
    }
  }
}

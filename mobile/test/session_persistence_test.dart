// قاعدة المستخدم: «يبقى مسجلاً دخول حتى يسجّل الخروج بنفسه».
// هذه العدّة تثبت سلوك الجلسة من كل جهاته عبر خادم وهمي وتخزين آمن وهمي:
// 1) فساد كوكيز الجلسة (401) + بيانات محفوظة ⇒ دخول صامت ويبقى جاهزًا
// 2) فساد الكوكيز بلا بيانات محفوظة ⇒ شاشة الدخول (الطبيعي)
// 3) انقطاع الشبكة أثناء الإقلاع ⇒ لا يُسقط الجلسة أبدًا (إعادة محاولة)
// 4) الدخول يخزّن البيانات مشفّرة، والخروج اليدوي الوحيد يمسحها كليًا
// 5) رفض الدخول فعليًا (كلمة المرور تغيّرت) يمسح المحفوظ ويطلب دخولًا يدويًا
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pharmacy_mobile/core/api_client.dart';
import 'package:pharmacy_mobile/state/app_state.dart';

const String _kCredentialsKey = 'pharmacy_saved_credentials';

const Map<String, dynamic> _user = <String, dynamic>{
  'id': 'u1',
  'email': 'owner@pharmacy.eg',
  'first_name': 'صاحب',
  'last_name': 'الصيدلية',
  'display_name': 'صاحب الصيدلية',
  'role': 'OWNER',
};

const Map<String, dynamic> _context = <String, dynamic>{
  'data': <String, dynamic>{
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
  },
};

const Map<String, dynamic> _permissions = <String, dynamic>{
  'data': <String, dynamic>{
    'principal_type': 'pharmacy',
    'role': 'owner',
    'permissions': <String>[],
    'full_access': true,
  },
};

final Map<String, List<String>> _jsonHeaders = <String, List<String>>{
  Headers.contentTypeHeader: <String>['application/json'],
};

/// خادم وهمي بحالات قابلة للضبط لكل اختبار.
class _SessionMock implements HttpClientAdapter {
  int meStatus = 200;
  int loginStatus = 200;
  bool networkDown = false;
  int loginCalls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    if (path.endsWith('/auth/pharmacy/me')) {
      if (networkDown) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: 'network unreachable',
        );
      }
      if (meStatus != 200) {
        return ResponseBody.fromString(
            jsonEncode(<String, dynamic>{'code': 'unauthorized'}), meStatus,
            headers: _jsonHeaders);
      }
      return ResponseBody.fromString(
          jsonEncode(<String, dynamic>{'user': _user}), 200,
          headers: _jsonHeaders);
    }
    if (path.endsWith('/auth/pharmacy/login')) {
      loginCalls++;
      if (loginStatus != 200) {
        return ResponseBody.fromString(
            jsonEncode(<String, dynamic>{'code': 'INVALID_CREDENTIALS'}),
            loginStatus,
            headers: _jsonHeaders);
      }
      return ResponseBody.fromString(
          jsonEncode(<String, dynamic>{'user': _user}), 200,
          headers: _jsonHeaders);
    }
    if (path.endsWith('/auth/pharmacy/logout')) {
      return ResponseBody.fromString(jsonEncode(<String, dynamic>{'ok': true}), 200,
          headers: _jsonHeaders);
    }
    if (path.endsWith('/pharmacy/context')) {
      return ResponseBody.fromString(jsonEncode(_context), 200, headers: _jsonHeaders);
    }
    if (path.endsWith('/pharmacy/permissions/me')) {
      return ResponseBody.fromString(
          jsonEncode(_permissions), 200, headers: _jsonHeaders);
    }
    return ResponseBody.fromString(
        jsonEncode(<String, dynamic>{'data': <dynamic>[]}), 200,
        headers: _jsonHeaders);
  }

  @override
  void close({bool force = false}) {}
}

final _SessionMock mock = _SessionMock();

/// تخزين آمن وهمي في الذاكرة (نفس قناة الإضافة).
final Map<String, String> fakeSecureStorage = <String, String>{};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    ApiClient.instance.dio.httpClientAdapter = mock;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async {
        final args = call.arguments is Map
            ? Map<String, Object?>.from(call.arguments as Map)
            : <String, Object?>{};
        switch (call.method) {
          case 'read':
            return fakeSecureStorage[args['key'] as String? ?? ''];
          case 'write':
            fakeSecureStorage[args['key'] as String? ?? ''] =
                args['value'] as String? ?? '';
            return null;
          case 'delete':
            fakeSecureStorage.remove(args['key'] as String? ?? '');
            return null;
          default:
            return null;
        }
      },
    );
  });

  setUp(() {
    fakeSecureStorage.clear();
    mock
      ..meStatus = 200
      ..loginStatus = 200
      ..networkDown = false
      ..loginCalls = 0;
  });

  test('boot: cookies dead (401) + saved credentials → silent relogin, still ready',
      () async {
    fakeSecureStorage[_kCredentialsKey] = jsonEncode(<String, String>{
      'email': 'owner@pharmacy.eg',
      'password': 'secret123',
    });
    mock.meStatus = 401;

    final state = AppState();
    await state.boot();

    expect(state.phase, AuthPhase.ready, reason: 'يجب أن يبقى مسجلاً بالدخول الصامت');
    expect(state.user?.email, 'owner@pharmacy.eg');
    expect(state.context?.pharmacyName, 'صيدلية الشفاء');
    expect(mock.loginCalls, 1, reason: 'تم الدخول الصامت مرة واحدة');
    expect(
      fakeSecureStorage.containsKey(_kCredentialsKey),
      isTrue,
      reason: 'البيانات المحفوظة تبقى للإقلاعات القادمة',
    );
  });

  test('boot: cookies dead (401) + no saved credentials → login screen (anonymous)',
      () async {
    mock.meStatus = 401;

    final state = AppState();
    await state.boot();

    expect(state.phase, AuthPhase.anonymous);
    expect(state.user, isNull);
  });

  test('boot: network down → never logs out (rethrows for splash retry)', () async {
    fakeSecureStorage[_kCredentialsKey] = jsonEncode(<String, String>{
      'email': 'owner@pharmacy.eg',
      'password': 'secret123',
    });
    mock.networkDown = true;

    final state = AppState();
    await expectLater(state.boot(), throwsA(isA<ApiException>()));
    expect(state.phase, isNot(AuthPhase.anonymous),
        reason: 'انقطاع الشبكة لا يُخرج المستخدم — شاشة البداية تعيد المحاولة');
  });

  test('login stores encrypted credentials; manual logout is the only way out',
      () async {
    final state = AppState();
    await state.login('owner@pharmacy.eg', 'secret123');

    expect(state.phase, AuthPhase.ready);
    final saved = fakeSecureStorage[_kCredentialsKey];
    expect(saved, isNotNull);
    expect(saved!, contains('owner@pharmacy.eg'));

    await state.logout();
    expect(state.phase, AuthPhase.anonymous);
    expect(fakeSecureStorage.containsKey(_kCredentialsKey), isFalse,
        reason: 'الخروج اليدوي يمسح البيانات المحفوظة بالكامل');
  });

  test('boot: cookies dead + wrong password on server → saved data cleared, manual login',
      () async {
    fakeSecureStorage[_kCredentialsKey] = jsonEncode(<String, String>{
      'email': 'owner@pharmacy.eg',
      'password': 'old-pass',
    });
    mock.meStatus = 401;
    mock.loginStatus = 401;

    final state = AppState();
    await state.boot();

    expect(state.phase, AuthPhase.anonymous,
        reason: 'الخادم رفض الدخول فعليًا — يُطلب دخول يدوي');
    expect(fakeSecureStorage.containsKey(_kCredentialsKey), isFalse,
        reason: 'البيانات الفاسدة تُمسح ولا تُعاد محاولتها');
  });
}

import 'package:dio/dio.dart';

import '../config.dart';
import '../models/models.dart';
import 'cookies.dart';

/// استثناء موحّد يحمل كود الباك اند (EMAIL_NOT_VERIFIED / csrf_failed …)
/// وحالته HTTP ليترجمة المستوى الأعلى رسالة مفهومة للمستخدم.
class ApiException implements Exception {
  final String code;
  final String message;
  final int? status;

  ApiException(this.code, this.message, {this.status});

  bool get emailNotVerified => code == 'EMAIL_NOT_VERIFIED';
  bool get isNetwork => code == 'NETWORK_UNREACHABLE';

  @override
  String toString() => message;
}

/// عميل الـ API — نسخة محمولة من lib/api.ts في تطبيق الويب:
/// جلسة كوكيز معتمة + حقن CSRF + تجديد تلقائي عند 401 مرة واحدة.
/// نقاط النهاية مطابقة حرفيًا لما يسجله backend/internal/auth/handler.go.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final SessionCookies cookies = SessionCookies();

  String _baseUrl = AppConfig.apiBaseUrl;
  String get baseUrl => _baseUrl;

  Future<bool>? _refreshing;

  late final Dio dio = _build();

  Dio _build() {
    final d = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 25),
      headers: <String, String>{'Accept': 'application/json'},
    ));
    d.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final cookieHeader = cookies.header();
        if (cookieHeader != null) options.headers['cookie'] = cookieHeader;
        final method = options.method.toUpperCase();
        if (method != 'GET' && cookies.csrf != null) {
          options.headers['X-CSRF-Token'] = cookies.csrf;
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        cookies.absorb(response.headers['set-cookie']);
        handler.next(response);
      },
      onError: (e, handler) {
        final res = e.response;
        if (res != null) cookies.absorb(res.headers['set-cookie']);
        handler.next(e);
      },
    ));
    return d;
  }

  /// يبدّل عنوان الخادم (تجاوز داخل التطبيق) ويمسح كوكيز المضيف القديم.
  Future<void> applyServerUrl(String? rawOverride) async {
    final hasOverride = rawOverride != null && rawOverride.trim().isNotEmpty;
    final url = AppConfig.normalizeBaseUrl(hasOverride ? rawOverride : AppConfig.apiBaseUrl);
    if (url == _baseUrl) return;
    _baseUrl = url;
    dio.options.baseUrl = url;
    cookies.clear();
  }

  // ---------------------------------------------------------------- الجلسة

  Future<User> login(String email, String password) async {
    final body = await _send('POST', '/auth/pharmacy/login',
        body: <String, dynamic>{'email': email, 'password': password},
        allowRefresh: false);
    return User.fromJson(_mapOf(body['user']));
  }

  Future<User> me() async {
    final body = await _send('GET', '/auth/pharmacy/me');
    return User.fromJson(_mapOf(body['user']));
  }

  Future<void> logout() async {
    try {
      await _send('POST', '/auth/pharmacy/logout');
    } finally {
      cookies.clear();
    }
  }

  Future<bool> refresh() {
    // دمج النداءات المتوازية: كل من ينتظر يحصل على نتيجة نفس المحاولة
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    try {
      await _dispatch('POST', '/auth/pharmacy/refresh');
      return true;
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 403) cookies.clear();
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setLocale(String locale) =>
      _send('PATCH', '/auth/pharmacy/locale',
          body: <String, dynamic>{'locale': locale});

  // ------------------------------------------------------- التسجيل والتحقق

  Future<void> register({
    required String companyName,
    required String companyEmail,
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) {
    return _send('POST', '/auth/register', allowRefresh: false, body: <String, dynamic>{
      'company_name': companyName,
      'company_email': companyEmail,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'password': password,
    });
  }

  Future<({bool sessionCreated, bool onboardingRequired, User? user})>
      verifyEmail(String email, String code) async {
    final body = await _send('POST', '/auth/verify-email',
        body: <String, dynamic>{'email': email, 'code': code},
        allowRefresh: false);
    User? user;
    if (body['user'] is Map) {
      user = User.fromJson(_mapOf(body['user']));
    }
    return (
      sessionCreated: body['session_created'] == true,
      onboardingRequired: body['onboarding_required'] == true,
      user: user,
    );
  }

  Future<void> resendVerification(String email) =>
      _send('POST', '/auth/resend-verification',
          body: <String, dynamic>{'email': email}, allowRefresh: false);

  // ------------------------------------------------------------ الإعداد

  Future<OnboardingState> getOnboarding() async {
    final body = await _send('GET', '/pharmacy/onboarding');
    return OnboardingState.fromJson(_mapOf(body['data']));
  }

  Future<OnboardingState> updateOnboarding(Map<String, dynamic> payload) async {
    final body = await _send('PUT', '/pharmacy/onboarding', body: payload);
    return OnboardingState.fromJson(_mapOf(body['data']));
  }

  // ------------------------------------------------------------ اللوحة

  Future<DashboardStats> dashboardStats() async {
    final body = await _send('GET', '/pharmacy/dashboard/stats');
    return DashboardStats.fromJson(body);
  }

  Future<List<Product>> products({String search = ''}) async {
    final body = await _send('GET', '/pharmacy/products',
        query: search.isEmpty ? null : <String, dynamic>{'search': search});
    final list = body['data'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((m) => Product.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }
    return <Product>[];
  }

  // ------------------------------------------------------------ النواة

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
    bool allowRefresh = true,
  }) async {
    try {
      return await _dispatch(method, path, body: body, query: query);
    } on ApiException catch (e) {
      // تجديد مرة واحدة فقط لطلبات العمل الحقيقية — لا تجديد لمحاولات
      // الدخول/التحقق نفسها (فشلها هو جواب، لا انتهاء جلسة)
      final isAuthPath = path.startsWith('/auth/');
      if (allowRefresh && !isAuthPath && e.status == 401) {
        final ok = await refresh();
        if (ok) {
          return await _dispatch(method, path, body: body, query: query);
        }
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _dispatch(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) async {
    Response<dynamic> res;
    try {
      res = await dio.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: Options(method: method),
      );
    } on DioException catch (e) {
      throw _fromDio(e);
    }
    return _mapOf(res.data);
  }

  ApiException _fromDio(DioException e) {
    final res = e.response;
    if (res == null || res.statusCode == null) {
      return ApiException('NETWORK_UNREACHABLE', 'network_unreachable', status: 0);
    }
    var code = 'API_ERROR';
    var message = 'API_ERROR';
    final data = res.data;
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      code = (m['code'] ?? m['error'] ?? 'API_ERROR').toString();
      message = (m['message'] ?? m['error'] ?? 'API_ERROR').toString();
    }
    return ApiException(code, message, status: res.statusCode);
  }

  Map<String, dynamic> _mapOf(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }
}

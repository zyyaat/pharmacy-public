import 'package:dio/dio.dart';

import '../config.dart';
import '../models/models.dart';
import 'cookies.dart';
import 'offline.dart';

/// استثناء موحّد يحمل كود الباك اند (EMAIL_NOT_VERIFIED / csrf_failed …)
/// وحالته HTTP ليترجمة المستوى الأعلى رسالة مفهومة للمستخدم.
class ApiException implements Exception {
  final String code;
  final String message;
  final int? status;
  final Map<String, dynamic> payload;

  ApiException(this.code, this.message, {this.status, Map<String, dynamic>? payload})
      : payload = payload ?? <String, dynamic>{};

  bool get emailNotVerified => code == 'EMAIL_NOT_VERIFIED';
  bool get isNetwork => code == 'NETWORK_UNREACHABLE';
  bool get isPriceChanged => code == 'PRICE_CHANGED' || code == 'pos_price_changed';

  @override
  String toString() => message;
}

/// عميل الـ API — نسخة موبايل كاملة من lib/api.ts في تطبيق الويب (Task 61):
/// جلسة كوكيز معتمة + حقن CSRF مزدوج + تجديد تلقائي عند 401 مرة واحدة،
/// وكل نقاط النهاية التي يستخدمها الويب بنفس المسارات والأشكال.
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
      receiveTimeout: const Duration(seconds: 40),
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

  // ---------------------------------------------------------------- الجلسة

  Future<User> login(String email, String password) async {
    final body = await _send('POST', '/auth/pharmacy/login',
        body: <String, dynamic>{'email': email, 'password': password},
        allowRefresh: false);
    return User.fromJson(mOf(body['user']));
  }

  Future<User> me() async {
    final body = await _send('GET', '/auth/pharmacy/me');
    return User.fromJson(mOf(body['user']));
  }

  Future<void> logout() async {
    try {
      await _send('POST', '/auth/pharmacy/logout');
    } finally {
      cookies.clear();
    }
  }

  Future<bool> refresh() =>
      _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

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
      _send('PATCH', '/auth/pharmacy/locale', body: <String, dynamic>{'locale': locale});

  // ------------------------------------------------------- التسجيل والتحقق

  /// Task 68-f — يعيد هل أُرسل رمز التحقق عند إنشاء الحساب كما يقرأ الويب
  /// (register/page.tsx:122: email_verification_sent !== false — غائب/غير منطقي
  /// ⇒ مُرسل) من استجابة /auth/register (backend auth/handler.go:129).
  /// الويب يمررها لـ /verify-email?sent=1|0؛ هنا تُقرأ من RegisterScreen عبر
  /// lastRegisterEmailVerificationSent ليمررها لشاشة التحقق (AppState نفسه
  /// يبقى Future<void> حفاظًا على عقد الاختبارات).
  Future<bool> register({
    required String companyName,
    required String companyEmail,
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    final body = await _send('POST', '/auth/register', allowRefresh: false, body: <String, dynamic>{
      'company_name': companyName,
      'company_email': companyEmail,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'password': password,
    });
    final sent = body['email_verification_sent'];
    _lastRegisterEmailVerificationSent = sent is bool ? sent : true;
    return _lastRegisterEmailVerificationSent;
  }

  /// هل قيل إن رمز التحقق أُرسل في آخر استجابة تسجيل ناجحة؟ يُستهلك فورًا
  /// بعد نجاح AppState.register — لا معنى له بعد مغادرة مسار التسجيل.
  bool get lastRegisterEmailVerificationSent => _lastRegisterEmailVerificationSent;
  bool _lastRegisterEmailVerificationSent = true;

  Future<({bool sessionCreated, bool onboardingRequired, User? user})>
      verifyEmail(String email, String code) async {
    final body = await _send('POST', '/auth/verify-email',
        body: <String, dynamic>{'email': email, 'code': code}, allowRefresh: false);
    User? user;
    if (body['user'] is Map) user = User.fromJson(mOf(body['user']));
    return (
      sessionCreated: body['session_created'] == true,
      onboardingRequired: body['onboarding_required'] == true,
      user: user,
    );
  }

  /// Task 68-f — يعيد علم الإرسال كما يقرأ الويب (verify-email/page.tsx:147:
  /// response.sent !== false) من استجابة /auth/resend-verification
  /// (backend auth/handler.go:333): sent=false ⇒ رمز سابق ما زال صالحًا
  /// فتُعرض verify_code_exists بدل verify_code_sent.
  Future<bool> resendVerification(String email) async {
    final body = await _send('POST', '/auth/resend-verification',
        body: <String, dynamic>{'email': email}, allowRefresh: false);
    final sent = body['sent'];
    return sent is bool ? sent : true;
  }

  // ------------------------------------------------------------ الإعداد

  Future<OnboardingState> getOnboarding() async {
    final body = await _send('GET', '/pharmacy/onboarding');
    return OnboardingState.fromJson(mOf(body['data']));
  }

  Future<OnboardingState> updateOnboarding(Map<String, dynamic> payload) async {
    final body = await _send('PUT', '/pharmacy/onboarding', body: payload);
    return OnboardingState.fromJson(mOf(body['data']));
  }

  // ------------------------------------------------------------ السياق واللوحة

  Future<PharmacyContext> context() async {
    final body = await _send('GET', '/pharmacy/context');
    return PharmacyContext.fromJson(unwrapMap(body));
  }

  Future<DashboardStats> dashboardStats() async {
    final body = await _send('GET', '/pharmacy/dashboard/stats');
    return DashboardStats.fromJson(unwrapMap(body));
  }

  Future<List<ActivityItem>> dashboardActivity() async {
    final body = await _send('GET', '/pharmacy/dashboard/activity');
    return unwrapList(body).map((e) => ActivityItem.fromJson(mOf(e))).toList();
  }

  Future<MyPermissions> myPermissions() async {
    final body = await _send('GET', '/pharmacy/permissions/me');
    return MyPermissions.fromJson(unwrapMap(body));
  }

  // ------------------------------------------------------------ المخزون

  Future<List<InventoryItem>> inventory() async {
    final body = await _send('GET', '/pharmacy/inventory');
    return unwrapList(body).map((e) => InventoryItem.fromJson(mOf(e))).toList();
  }

  Future<List<LowStockItem>> lowStock() async {
    final body = await _send('GET', '/pharmacy/inventory/low-stock');
    return unwrapList(body).map((e) => LowStockItem.fromJson(mOf(e))).toList();
  }

  Future<List<Product>> products({String search = ''}) async {
    final body = await _send('GET', '/pharmacy/products',
        query: search.isEmpty ? null : <String, dynamic>{'search': search});
    return unwrapList(body).map((e) => Product.fromJson(mOf(e))).toList();
  }

  Future<ProductDetail> product(String id) async {
    final body = await _send('GET', '/pharmacy/products/$id');
    return ProductDetail.fromJson(unwrapMap(body));
  }

  Future<void> createProduct(Map<String, dynamic> payload) =>
      _send('POST', '/pharmacy/products', body: payload);

  Future<void> updateProduct(String id, Map<String, dynamic> payload) =>
      _send('PUT', '/pharmacy/products/$id', body: payload);

  /// Task 68-i (B) — ضبط المخزون يدعم idempotency عبر ترويسة Idempotency-Key
  /// حصريًا (backend pharmacy_dashboard_handler.go:216 يقرأ الترويسة ولا يقرأ
  /// حقل الجسم) — تُرسل الترويسة ويبقى حقل الجسم للتوافق الخلفي.
  Future<void> adjustBatchStock(String batchId, int delta, String reason, String idempotencyKey) {
    return _send('POST', '/pharmacy/inventory/$batchId/adjust',
        headers: <String, String>{'Idempotency-Key': idempotencyKey},
        body: <String, dynamic>{
          'delta': delta,
          'reason': reason,
          'idempotency_key': idempotencyKey,
        });
  }

  Future<({List<StockMovementRow> movements, int total})> stockMovements({
    String type = '',
    String search = '',
    String from = '',
    String to = '',
    String direction = '',
    int limit = 50,
    int offset = 0,
  }) async {
    final body = await _send('GET', '/pharmacy/inventory/movements', query: <String, dynamic>{
      if (type.isNotEmpty) 'type': type,
      if (search.isNotEmpty) 'search': search,
      if (from.isNotEmpty) 'from': from,
      if (to.isNotEmpty) 'to': to,
      if (direction.isNotEmpty) 'direction': direction,
      'limit': limit,
      'offset': offset,
    });
    final data = unwrapMap(body);
    return (
      movements: lOf(data['movements']).map((e) => StockMovementRow.fromJson(mOf(e))).toList(),
      total: iOf(data['total']),
    );
  }

  // ------------------------------------------------------------ نقطة البيع

  Future<Product?> lookupPOSProduct(String barcode) async {
    try {
      final body = await _send('GET', '/pharmacy/pos/products',
          query: <String, dynamic>{'barcode': barcode});
      final data = body['data'];
      if (data is Map) return Product.fromJson(mOf(data));
      return null;
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<List<Product>> searchPOSProducts(String query, {int limit = 8}) async {
    if (query.trim().isEmpty) return <Product>[];
    final body = await _send('GET', '/pharmacy/pos/search',
        query: <String, dynamic>{'q': query, 'limit': limit});
    return unwrapList(body).map((e) => Product.fromJson(mOf(e))).toList();
  }

  /// إنشاء بيع — قد يرمي 409 price_changed مع رسالة الخادم المفهومة.
  /// الاستجابة: {sale_id, total_amount_piastres, discount_amount_piastres, replayed}
  /// Task 68-i (B) — مفتاح idempotency يُرسل ترويسة Idempotency-Key أيضًا
  /// (عقد الترويسة) مع بقاء حقل الجسم للتوافق الخلفي مع
  /// product_pos_handler.go:411.
  Future<({String saleId, int totalAmount, int discountAmount})> createPOSSale({
    required List<Map<String, dynamic>> items,
    String? idempotencyKey,
    Map<String, dynamic>? options,
  }) async {
    final body = await _send(
      'POST',
      '/pharmacy/pos/sales',
      headers: idempotencyKey == null ? null : <String, String>{'Idempotency-Key': idempotencyKey},
      body: <String, dynamic>{
        'items': items,
        if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
        if (options != null) ...options,
      },
    );
    final data = unwrapMap(body);
    return (
      saleId: sOf(data['sale_id']),
      totalAmount: iOf(data['total_amount_piastres']),
      discountAmount: iOf(data['discount_amount_piastres']),
    );
  }

  Future<({List<SaleSummary> sales, int total, int limit, int offset})> listPOSSales({
    int limit = 20,
    int offset = 0,
    String search = '',
    String from = '',
    String to = '',
  }) async {
    final body = await _send('GET', '/pharmacy/pos/sales', query: <String, dynamic>{
      'limit': limit,
      'offset': offset,
      if (search.isNotEmpty) 'search': search,
      if (from.isNotEmpty) 'from': from,
      if (to.isNotEmpty) 'to': to,
    });
    final data = unwrapMap(body);
    return (
      sales: lOf(data['sales']).map((e) => SaleSummary.fromJson(mOf(e))).toList(),
      total: iOf(data['total']),
      limit: iOf(data['limit'], limit),
      offset: iOf(data['offset'], offset),
    );
  }

  Future<SaleDetail> getSale(String saleId) async {
    final body = await _send('GET', '/pharmacy/pos/sales/$saleId');
    return SaleDetail.fromJson(unwrapMap(body));
  }

  /// Task 68-i (B) — مفتاح idempotency يُرسل ترويسة Idempotency-Key أيضًا
  /// (عقد الترويسة) مع بقاء حقل الجسم للتوافق الخلفي مع
  /// sales_history_handler.go:534.
  Future<({int returnNumber, int totalAmount, String saleStatus})> createSaleReturn(
      String saleId, List<Map<String, dynamic>> items, String reason, String idempotencyKey) async {
    final body = await _send(
      'POST',
      '/pharmacy/pos/sales/$saleId/returns',
      headers: <String, String>{'Idempotency-Key': idempotencyKey},
      body: <String, dynamic>{
        'items': items,
        'reason': reason,
        'idempotency_key': idempotencyKey,
      },
    );
    final data = unwrapMap(body);
    return (
      returnNumber: iOf(data['return_number']),
      totalAmount: iOf(data['total_amount_piastres']),
      saleStatus: sOf(data['sale_status']),
    );
  }

  // ------------------------------------------------------------ العملاء

  Future<List<Customer>> customers({String search = '', bool debtsOnly = false}) async {
    final body = await _send('GET', '/pharmacy/customers', query: <String, dynamic>{
      if (search.isNotEmpty) 'search': search,
      if (debtsOnly) 'debts': '1',
    });
    return unwrapList(body, 'customers').map((e) => Customer.fromJson(mOf(e))).toList();
  }

  Future<Customer> createCustomer(String name, String phone) async {
    final body = await _send('POST', '/pharmacy/customers',
        body: <String, dynamic>{'name': name, 'phone': phone});
    final data = unwrapMap(body);
    return Customer.fromJson(mOf(data['customer']));
  }

  Future<void> updateCustomer(String id, {String? name, String? phone}) =>
      _send('PUT', '/pharmacy/customers/$id', body: <String, dynamic>{
        if (name != null) 'name': name,
        if (phone != null) 'phone': phone,
      });

  Future<CustomerStatement> customerStatement(String id) async {
    final body = await _send('GET', '/pharmacy/customers/$id/statement');
    return CustomerStatement.fromJson(unwrapMap(body));
  }

  Future<void> createCustomerPayment(String customerId, int amountPiastres, String note) {
    return _send('POST', '/pharmacy/customers/$customerId/payments',
        body: <String, dynamic>{'amount_piastres': amountPiastres, 'note': note});
  }

  // ------------------------------------------------------------ الموظفون

  Future<List<Employee>> employees() async {
    final body = await _send('GET', '/pharmacy/employees');
    return unwrapList(body, 'employees').map((e) => Employee.fromJson(mOf(e))).toList();
  }

  Future<void> createEmployee(Map<String, dynamic> payload) =>
      _send('POST', '/pharmacy/employees', body: payload);

  Future<void> setEmployeeStatus(String employeeId, String status) =>
      _send('PATCH', '/pharmacy/employees/$employeeId/status',
          body: <String, dynamic>{'status': status});

  Future<EmployeePermissions> employeePermissions(String employeeId) async {
    final body = await _send('GET', '/pharmacy/employees/$employeeId/permissions');
    return EmployeePermissions.fromJson(unwrapMap(body));
  }

  Future<void> updateEmployeePermissions(String employeeId, List<String> permissions) =>
      _send('PUT', '/pharmacy/employees/$employeeId/permissions',
          body: <String, dynamic>{'permissions': permissions});

  Future<List<PermissionModule>> permissionCatalog() async {
    final body = await _send('GET', '/pharmacy/permissions/catalog');
    return unwrapList(body).map((e) => PermissionModule.fromJson(mOf(e))).toList();
  }

  Future<List<PermissionTemplate>> permissionTemplates() async {
    final body = await _send('GET', '/pharmacy/permissions/templates');
    return unwrapList(body).map((e) => PermissionTemplate.fromJson(mOf(e))).toList();
  }

  // ------------------------------------------------------------ الفروع والحضور

  Future<List<Branch>> branches() async {
    final body = await _send('GET', '/pharmacy/branches');
    return unwrapList(body, 'branches').map((e) => Branch.fromJson(mOf(e))).toList();
  }

  Future<void> createBranch(Map<String, dynamic> payload) =>
      _send('POST', '/pharmacy/branches', body: payload);

  Future<void> updateBranch(String id, Map<String, dynamic> payload) =>
      _send('PUT', '/pharmacy/branches/$id', body: payload);

  Future<void> deleteBranch(String id) => _send('DELETE', '/pharmacy/branches/$id');

  Future<({List<AttendanceRow> rows, int total})> attendance() async {
    final body = await _send('GET', '/pharmacy/attendance');
    final data = body['data'];
    final rows = data is List ? lOf(data) : lOf(unwrapMap(body)['data']);
    return (
      rows: rows.map((e) => AttendanceRow.fromJson(mOf(e))).toList(),
      total: iOf(body['total']),
    );
  }

  // ------------------------------------------------------------ التقارير

  Future<SalesReport> salesReport({String? from, String? to}) async {
    final body = await _send('GET', '/pharmacy/reports/sales', query: <String, dynamic>{
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
    });
    return SalesReport.fromJson(unwrapMap(body));
  }

  Future<InventoryReport> inventoryReport() async {
    final body = await _send('GET', '/pharmacy/reports/inventory');
    return InventoryReport.fromJson(unwrapMap(body));
  }

  Future<MovementsReport> movementsReport({String? from, String? to}) async {
    final body = await _send('GET', '/pharmacy/reports/movements', query: <String, dynamic>{
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
    });
    return MovementsReport.fromJson(unwrapMap(body));
  }

  // ------------------------------------------------------------ الإعدادات

  Future<ReceiptSettings> getSettings() async {
    final body = await _send('GET', '/pharmacy/settings');
    final data = unwrapMap(body);
    return ReceiptSettings.fromJson(mOf(data['receipt']));
  }

  Future<ReceiptSettings> updateSettings(Map<String, dynamic> receipt) async {
    final body = await _send('PUT', '/pharmacy/settings', body: <String, dynamic>{'receipt': receipt});
    final data = unwrapMap(body);
    return ReceiptSettings.fromJson(mOf(data['receipt']));
  }

  Future<List<MigrationItem>> systemMigrations() async {
    final body = await _send('GET', '/pharmacy/system/migrations');
    return unwrapList(body).map((e) => MigrationItem.fromJson(mOf(e))).toList();
  }

  // ------------------------------------------------------------ النواة

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
    bool allowRefresh = true,
    Map<String, String>? headers,
  }) async {
    try {
      return await _dispatch(method, path, body: body, query: query, headers: headers);
    } on ApiException catch (e) {
      final isAuthPath = path.startsWith('/auth/');
      if (allowRefresh && !isAuthPath && e.status == 401) {
        final ok = await refresh();
        if (ok) return await _dispatch(method, path, body: body, query: query, headers: headers);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _dispatch(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) async {
    Response<dynamic> res;
    try {
      res = await dio.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: Options(method: method, headers: headers),
      );
    } on DioException catch (e) {
      final ApiException err = _fromDio(e);
      // Task 82 — stale-if-error: انقطاع الشبكة + نسخة مخزّنة لطلب GET
      // = نعيد الكاش بدل رمي الخطأ (قراءات فقط — الكتابة تحتاج الخادم دائمًا)
      if (err.isNetwork) {
        NetworkSignal.noteNetworkFailure();
        if (method == 'GET') {
          final Map<String, dynamic>? cached =
              await OfflineCache.instance.get(OfflineCache.cacheKey(method, path, query));
          if (cached != null) return cached;
        }
      }
      throw err;
    }
    NetworkSignal.noteSuccess();
    final Map<String, dynamic> parsed = mOf(res.data);
    // Task 82 — قراءة-عبر: كل استجابة GET ناجحة تُكتب للكاش المحلي المشفّر
    // (السياق، الصلاحيات، المخزون، المبيعات، العملاء… حتى يعمل التنقل بلا إنترنت)
    if (method == 'GET') {
      await OfflineCache.instance.put(OfflineCache.cacheKey(method, path, query), parsed);
    }
    return parsed;
  }

  ApiException _fromDio(DioException e) {
    final res = e.response;
    if (res == null || res.statusCode == null) {
      return ApiException('NETWORK_UNREACHABLE', 'network_unreachable', status: 0);
    }
    var code = 'API_ERROR';
    var message = 'API_ERROR';
    Map<String, dynamic>? payload;
    final data = res.data;
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      code = (m['code'] ?? m['error'] ?? 'API_ERROR').toString();
      message = (m['message'] ?? m['error'] ?? 'API_ERROR').toString();
      if (m['data'] is Map) payload = Map<String, dynamic>.from(m['data'] as Map);
    }
    return ApiException(code, message, status: res.statusCode, payload: payload ?? const {});
  }
}

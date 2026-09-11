// Task 59 — اختبار دخان: يجبر المُجمِّع على ترجمة كامل التطبيق (كل الشاشات
// والحالة والنواة عبر imports في main.dart) — يكشف أي خطأ تجميع فورًا في
// CI قبل محاولة بناء الـ APK، ويتحقق من حقن dart-define من env.json.
import 'package:flutter_test/flutter_test.dart';

import 'package:pharmacy_mobile/config.dart';
import 'package:pharmacy_mobile/core/api_client.dart';
import 'package:pharmacy_mobile/core/cookies.dart';
import 'package:pharmacy_mobile/core/strings.dart';
import 'package:pharmacy_mobile/main.dart';
import 'package:pharmacy_mobile/models/models.dart';
import 'package:pharmacy_mobile/state/app_state.dart';

void main() {
  test('compile smoke — app, screens, state and core all compile', () {
    expect(PharmacyOSApp, isNotNull);
    expect(AuthPhase.values.length, 5);
    expect(ApiClient.instance, isNotNull);
    expect(SessionCookies().csrf, isNull);
    expect(AppConfig.otpLength, 6);
    expect(trFor('ar', 'login_title'), isNotEmpty);
    expect(trFor('en', 'login_title'), isNotEmpty);
    expect(trFor('zz', 'login_title'), isNotEmpty);
  });

  test('models parse defensively (missing keys → empty, never throw)', () {
    final user = User.fromJson(<String, dynamic>{});
    expect(user.friendlyName, '');
    final product = Product.fromJson(<String, dynamic>{
      'name': 'Panadol',
      'selling_price_piastres': 2500,
      'packaging_type': 'BOX_STRIP',
    });
    expect(product.priceEgp, '25.00');
    expect(product.isBoxStrip, isTrue);
    final stats = DashboardStats.fromJson(<String, dynamic>{
      'totalProducts': 12,
      'lowStockItems': [
        {'name': 'X', 'quantity': 3},
        'not-a-map',
      ],
    });
    expect(stats.totalProducts, 12);
    expect(stats.lowStockItems.length, 1);
    expect(stats.lowStockItems.first.name, 'X');
    final state = OnboardingState.fromJson(<String, dynamic>{});
    expect(state.onboardingRequired, isFalse);
  });
}

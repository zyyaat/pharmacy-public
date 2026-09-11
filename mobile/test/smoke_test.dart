// Task 61 — اختبار دخان: يجبر المُجمِّع على ترجمة كامل التطبيق (كل الشاشات
// والحالة والنواة عبر imports في main.dart) — يكشف أي خطأ تجميع فورًا في
// CI قبل محاولة بناء الـ APK، ويتحقق من حقن dart-define ومن الترجمة
// والتنسيقات المطابقة للويب.
import 'package:flutter_test/flutter_test.dart';

import 'package:pharmacy_mobile/config.dart';
import 'package:pharmacy_mobile/core/api_client.dart';
import 'package:pharmacy_mobile/core/cookies.dart';
import 'package:pharmacy_mobile/core/format.dart';
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
  });

  test('i18n mirrors the web dictionaries (namespaces + visible fallback)', () {
    final i18n = AppI18n.instance;
    i18n.setLocale('ar');
    // مفاتيح مأخوذة حرفيًا من ملفات الويب
    expect(i18n.t('nav', 'dashboard'), 'لوحة التحكم');
    expect(i18n.t('pos', 'paymentCash'), 'نقدي');
    expect(i18n.t('dashboard', 'total_products'), 'إجمالي المنتجات');
    // استيفاء المعاملات
    expect(i18n.t('sales', 'returnedAmount', {'amount': '12.00 ج.م'}), 'مرتجع: 12.00 ج.م');
    // المرجع المرئي للمفتاح الناقص (كالويب)
    expect(i18n.t('nosuch', 'missing'), 'nosuch.missing');
    i18n.setLocale('en');
    expect(i18n.t('nav', 'dashboard'), 'Dashboard');
    i18n.setLocale('ar');
  });

  test('money/number formatting matches lib/money.ts rules', () {
    expect(Fmt.money(10000, locale: 'ar'), '100.00 ج.م');
    expect(Fmt.money(10000, locale: 'en'), 'EGP 100.00');
    expect(Fmt.money(123456789, locale: 'ar'), '1,234,567.89 ج.م');
    expect(Fmt.parseEGPToPiastres('105.5'), 10550);
    expect(Fmt.parseEGPToPiastres('105.5'), isNot(1055));
    expect(Fmt.piastresToInput(10550), '105.50');
    expect(Fmt.stripPrice(sellingPricePiastres: 10550, partialSellingPricePiastres: 0, unitsPerBox: 3), 3517);
    expect(Fmt.number(12345), '12,345');
    expect(Fmt.number(-5000.5), '-5,000.50');
  });

  test('models parse defensively (missing keys → empty, never throw)', () {
    final user = User.fromJson(<String, dynamic>{});
    expect(user.displayName, '');
    final product = Product.fromJson(<String, dynamic>{
      'name': 'Panadol',
      'selling_price_piastres': 2500,
      'packaging_type': 'BOX_STRIP',
    });
    expect(product.sellingPricePiastres, 2500);
    expect(product.boxStrip, isTrue);
    final stats = DashboardStats.fromJson(<String, dynamic>{
      'totalProducts': 12,
      'lowStockItems': <dynamic>[
        <String, dynamic>{'name': 'X', 'quantity': 3},
        'not-a-map',
      ],
    });
    expect(stats.totalProducts, 12);
    expect(stats.lowStockItems.length, 1);
    expect(stats.lowStockItems.first.name, 'X');
    final state = OnboardingState.fromJson(<String, dynamic>{});
    expect(state.onboardingRequired, isFalse);
    // أغلفة data الدفاعية
    expect(unwrapList(<String, dynamic>{'data': <dynamic>[1, 2]}).length, 2);
    expect(unwrapMap(<String, dynamic>{'data': <String, dynamic>{'a': 1}})['a'], 1);
  });
}

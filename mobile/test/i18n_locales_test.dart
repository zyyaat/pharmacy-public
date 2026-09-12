// Task 81 — اختبار نظام اللغات الثماني (مثل تطبيق Next.js):
//   1) kI18nAll يحمل اللغات الثماني نفسها بترتيب i18n/config.ts وأسماء LOCALE_META.
//   2) المفاتيح الناقصة في لغة جزئية (auth بالأسبانية مثلًا) ترجع للعربية —
//      نفس دلالة deepMerge(catalogs.ar, catalogs[locale]) في messages/index.ts.
//   3) كود غير معروف يُطبَّع إلى العربية (حارس isLocale) — لا حالة غريبة من
//      تخزين قديم.
//   4) RTL للعربية والأردية فقط (كانت الأردية تنساب LTR في AppState).
//   5) رسالة الشبكة الودودة (درس Task 79) صديقة في اللغات الثماني — لا
//      مصطلحات تطوير (/diag وNEXT_PUBLIC وCORS) لأي لغة.
//   6) شاشة إعدادات اللغة تعرض اللغات الثماني بأسمائها الأصلية والإنجليزية.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_mobile/core/i18n_data.dart';
import 'package:pharmacy_mobile/core/strings.dart';
import 'package:pharmacy_mobile/screens/settings_screen.dart';
import 'package:pharmacy_mobile/state/app_state.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // state.setLocale تكتب اللغة في التخزين الآمن — نفس محاكاة session_persistence_test
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async => null,
    );
  });

  tearDown(() async {
    // إعادة الحالة الافتراضية بعد كل اختبار يغيّر اللغة
    await AppI18n.instance.setLocale('ar');
  });

  test('اللغات الثماني نفسها بترتيب الويب وأسماء LOCALE_META', () {
    expect(AppI18n.locales, <String>['ar', 'en', 'fr', 'es', 'tr', 'zh', 'hi', 'ur']);
    expect(kI18nAll.keys.toSet(), AppI18n.locales.toSet());
    for (final String code in AppI18n.locales) {
      expect(kI18nAll[code], isNotNull, reason: '$code ناقص من kI18nAll');
      expect(kI18nAll[code]!.containsKey('common'), isTrue, reason: '$code بلا نطاق common');
      expect(kI18nAll[code]!.containsKey('settings'), isTrue, reason: '$code بلا نطاق settings');
      final (String native, String english) = AppI18n.localeMeta[code]!;
      expect(native, isNotEmpty);
      expect(english, isNotEmpty);
    }
  });

  test('المفتاح الناقص في لغة جزئية يرجع للعربية (دلالة deepMerge)', () async {
    final AppI18n i18n = AppI18n.instance;

    // الأسبانية: common مترجم بالكامل، لكن ob_* في auth غير موجودة → العربية
    await i18n.setLocale('es');
    expect(i18n.locale, 'es');
    expect(i18n.t('common', 'loading'), 'Cargando...');
    expect(i18n.t('auth', 'ob_s1_title'), 'ما اسم صيدليتك؟');
    // المفتاح المترجم في اللغة الجزئية لا يُستبدل بالعربية
    expect(i18n.t('settings', 'language_title'), 'Idioma');

    // الأردية: نمط قريب مع اختلاف النطاق
    await i18n.setLocale('ur');
    expect(i18n.t('auth', 'ob_branch_name'), 'اسم الفرع الرئيسي');
  });

  test('كود غير معروف يُطبَّع إلى العربية (مثل isLocale بالويب)', () async {
    final AppI18n i18n = AppI18n.instance;
    await i18n.setLocale('zz');
    expect(i18n.locale, 'ar');
    await i18n.setLocale('UR'); // الأكواد صغيرة دائمًا
    expect(i18n.locale, 'ar');
  });

  test('RTL للعربية والأردية فقط — في AppI18n وAppState معًا', () async {
    final AppI18n i18n = AppI18n.instance;
    final AppState state = AppState();

    await i18n.setLocale('ar');
    expect(i18n.isRtl, isTrue);
    expect(state.isRtl, isTrue, reason: 'الحالة الافتراضية عربية');

    await state.setLocale('ur');
    expect(state.locale, 'ur');
    expect(state.isRtl, isTrue, reason: 'الأردية RTL كالويب (dirFor) — كان ينقصها هنا');
    expect(i18n.isRtl, isTrue);

    await state.setLocale('fr');
    expect(state.isRtl, isFalse);
    expect(i18n.isRtl, isFalse);
  });

  test('رسالة الشبكة الودودة في اللغات الثماني — صفر مصطلحات تطوير (درس 79)', () {
    final AppI18n i18n = AppI18n.instance;
    const List<String> jargon = <String>[
      '/diag', 'NEXT_PUBLIC', 'BACKEND_INTERNAL', 'CORS', 'backend',
    ];
    const Map<String, String> marker = <String, String>{
      'ar': 'تعذّر الاتصال بالخادم',
      'en': 'Cannot reach the server',
      'es': 'No se pudo conectar con el servidor',
      'fr': 'Impossible de joindre le serveur',
      'tr': 'Sunucuya ulaşılamadı',
      'zh': '无法连接服务器',
      'hi': 'सर्वर से कनेक्ट नहीं हो सका',
      'ur': 'سرور سے رابطہ ممکن نہیں',
    };
    for (final String code in AppI18n.locales) {
      i18n.setLocale(code);
      final String message = i18n.error('NETWORK_UNREACHABLE');
      expect(message, contains(marker[code]!),
          reason: '$code لا تحمل رسالة الشبكة الودودة');
      for (final String word in jargon) {
        expect(message.contains(word), isFalse,
            reason: 'رسالة $code تحمل مصطلح تطوير ($word)');
      }
    }
  });

  testWidgets('شاشة إعدادات اللغة تعرض اللغات الثماني بالأسماء الأصلية والإنجليزية',
      (WidgetTester tester) async {
    // سطح أطول — البطاقات الثماني لا تتسع على 800×600 (درس Task 80)
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final AppState state = AppState();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: LanguageSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    for (final String code in AppI18n.locales) {
      final (String native, String english) = AppI18n.localeMeta[code]!;
      // 'English' يتكرر (أصلي + إنجليزي للغة en نفسها) → findsWidgets أدق
      expect(find.textContaining(native), findsWidgets,
          reason: '$code غائبة من منتقي اللغة');
      expect(find.textContaining(english), findsWidgets,
          reason: 'الاسم الإنجليزي لـ $code غائب');
    }
  });
}

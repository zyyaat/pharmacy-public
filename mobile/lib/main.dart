import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/session_store.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/register_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/verify_email_screen.dart';
import 'state/app_state.dart';
import 'widgets/ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SessionStore();
  // استعادة كوكيز الجلسة واللغة وعنوان الخادم قبل أول إطار
  await ApiClient.instance.cookies.restore();
  String initialLocale = 'ar';
  try {
    initialLocale = await store.locale() ?? 'ar';
  } catch (_) {}
  try {
    await ApiClient.instance.applyServerUrl(await store.serverOverride());
  } catch (_) {}
  runApp(PharmacyOSApp(initialLocale: initialLocale));
}

class PharmacyOSApp extends StatelessWidget {
  const PharmacyOSApp({super.key, required this.initialLocale});

  final String initialLocale;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleProvider(initialLocale)),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, lp, _) => MaterialApp(
          title: 'Pharmacy OS',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: kBrandSeed),
            useMaterial3: true,
          ),
          locale: Locale(lp.locale),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          initialRoute: '/',
          routes: <String, WidgetBuilder>{
            '/': (_) => const SplashScreen(),
            '/login': (_) => const LoginScreen(),
            '/register': (_) => const RegisterScreen(),
            '/verify': (_) => const VerifyEmailScreen(),
            '/onboarding': (_) => const OnboardingScreen(),
            '/home': (_) => const HomeScreen(),
          },
        ),
      ),
    );
  }
}

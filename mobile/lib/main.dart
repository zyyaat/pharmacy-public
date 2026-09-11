import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/session_store.dart';
import 'core/theme.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/register_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/verify_email_screen.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SessionStore();
  // استعادة كوكيز الجلسة واللغة وعنوان الخادم قبل أول إطار
  await ApiClient.instance.cookies.restore();
  final state = AppState();
  try {
    await state.loadInitialLocale();
  } catch (_) {}
  try {
    await ApiClient.instance.applyServerUrl(await store.serverOverride());
  } catch (_) {}
  runApp(PharmacyOSApp(state: state));
}

class PharmacyOSApp extends StatelessWidget {
  const PharmacyOSApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: Consumer<AppState>(
        builder: (BuildContext context, AppState s, _) => MaterialApp(
          title: 'Pharmacy OS',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: s.themeMode,
          locale: Locale(s.locale),
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
            // صفحات اللوحة كلها داخل هيكل /home (Drawer + Header) مثل الويب —
            // بلا مسارات مستقلة حتى لا تُعرض بلا إطار.
          },
        ),
      ),
    );
  }
}

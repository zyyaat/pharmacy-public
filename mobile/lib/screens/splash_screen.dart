import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/strings.dart';
import '../state/app_state.dart';

/// شاشة الإقلاع: تفحص الجلسة عبر /me ثم توجه — نفس منطق حراس الويب:
/// onboarding مطلوب → المعالج، جلسة سليمة → اللوحة، بلا جلسة → الدخول.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final state = context.read<AppState>();
    try {
      await state.boot();
    } on ApiException catch (_) {
      // شبكة/خادم — نظل على الشاشة مع رسالة وإعادة محاولة تلقائية قصيرة
      if (mounted) {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (mounted) _boot();
      }
      return;
    }
    if (!mounted) return;
    switch (state.phase) {
      case AuthPhase.ready:
        Navigator.pushReplacementNamed(context, '/home');
        break;
      case AuthPhase.onboarding:
        Navigator.pushReplacementNamed(context, '/onboarding');
        break;
      case AuthPhase.unverified:
        Navigator.pushReplacementNamed(context, '/verify');
        break;
      case AuthPhase.anonymous:
      case AuthPhase.booting:
        Navigator.pushReplacementNamed(context, '/login');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(Icons.local_pharmacy, size: 44, color: Colors.white),
            ),
            const SizedBox(height: 18),
            const Text('Pharmacy OS', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(i18n.t('auth', 'brand_tagline'),
                style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.55))),
            const SizedBox(height: 28),
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 10),
            Text(i18n.t('common', 'splash_loading'),
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.45))),
          ],
        ),
      ),
    );
  }
}

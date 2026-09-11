import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/ui.dart';

/// شاشة الإقلاع: تستعيد الكوكيز وتفحص الجلسة (me) ثم توجه حسب الحالة —
/// نفس منطق حارس التطبيق الويب: onboarding_required → المعالج، جلسة → اللوحة.
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
    final auth = context.read<AuthProvider>();
    await auth.boot();
    if (!mounted) return;
    switch (auth.phase) {
      case AuthPhase.ready:
        Navigator.pushReplacementNamed(context, '/home');
        break;
      case AuthPhase.onboarding:
        Navigator.pushReplacementNamed(context, '/onboarding');
        break;
      case AuthPhase.unverified:
        Navigator.pushReplacementNamed(context, '/verify');
        break;
      default:
        Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFFF0FDFA), Color(0xFFECFEFF), Color(0xFFF8FAFC)],
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandLogo(size: 96),
              SizedBox(height: 28),
              SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(strokeWidth: 2.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

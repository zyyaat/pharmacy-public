import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/strings.dart';
import '../state/app_state.dart';
import '../widgets/ui.dart';

/// شاشة الإقلاع — BrandSplash مطابق للويب (brand-splash.tsx/css) بالشعار
/// الحقيقي والتوهج وحلقات السونار والنقاط، مع منطق حراس الويب نفسه:
/// onboarding مطلوب → المعالج، جلسة سليمة → اللوحة، بلا جلسة → الدخول.
/// عند فشل الاتصال: بطاقة خطأ مرئية + إعادة محاولة يدوية وتلقائية (3 ث)
/// — لم تعد حلقة صامتة بلا رسالة. الخروج بتلاشي bs-exiting (fade+scale+blur).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _failed = false;
  bool _exiting = false;
  Timer? _retry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    _retry?.cancel();
    final AppState state = context.read<AppState>();
    try {
      await state.boot();
    } on ApiException catch (_) {
      // شبكة/خادم — نبقى على الشاشة مع بطاقة خطأ مرئية وإعادة محاولة تلقائية
      if (!mounted) return;
      setState(() => _failed = true);
      _retry = Timer(const Duration(seconds: 3), () {
        if (mounted) _boot();
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _failed = false;
      _exiting = true; // تلاشي ناعم مثل bs-exiting قبل التوجيه
    });
    await Future<void>.delayed(const Duration(milliseconds: 520));
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

  void _manualRetry() {
    setState(() => _failed = false);
    _boot();
  }

  @override
  Widget build(BuildContext context) {
    final AppI18n i18n = AppI18n.instance;
    return Scaffold(
      backgroundColor: const Color(0xFF04150D),
      body: BrandSplash(
        subtitle: i18n.t('auth', 'brand_tagline'),
        exiting: _exiting,
        footer: _failed
            ? _OfflineCard(
                message: i18n.t('common', 'splash_offline'),
                retryLabel: i18n.t('common', 'retry'),
                onRetry: _manualRetry,
              )
            : null,
      ),
    );
  }
}

/// بطاقة انقطاع الاتصال داخل السپلاش — داكنة شبه شفافة بحد مضمر وزر إعادة
/// محاولة بألوان الهوية (لاصقة بأسلوب بطاقة الخطأ في onboarding بالويب).
class _OfflineCard extends StatelessWidget {
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;
  const _OfflineCard({required this.message, required this.retryLabel, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF14D4C).withOpacity(0.45)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.6, color: Color(0xFFECFDF5))),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF00D084).withOpacity(0.6)),
              ),
              child: Text(retryLabel,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF00D084))),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/strings.dart';
import '../core/theme.dart';
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
                hint: i18n.t('common', 'splash_offline_hint'),
                retryLabel: i18n.t('common', 'retry'),
                onRetry: _manualRetry,
              )
            : null,
      ),
    );
  }
}

/// رسالة انقطاع الاتصال داخل السپلاش — بسيطة وحديثة بلا إطار ولا خلفية:
/// أيقونة wifi-off خافتة + سطر الحالة + تلميح الإعادة التلقائية الناعم
/// + إعادة محاولة نصية بلون الهوية — بدل البطاقة المحدودة القديمة.
class _OfflineCard extends StatelessWidget {
  final String message;
  final String hint;
  final String retryLabel;
  final VoidCallback onRetry;
  const _OfflineCard({
    required this.message,
    required this.hint,
    required this.retryLabel,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    const Color fg = Color(0xFFECFDF5);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Icon(Icons.wifi_off_rounded, size: 15, color: fg.withOpacity(0.55)),
          const SizedBox(width: 8),
          Text(message,
              style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.5, color: fg.withOpacity(0.90))),
        ]),
        const SizedBox(height: 5),
        Text(hint, style: TextStyle(fontSize: 12, height: 1.5, color: fg.withOpacity(0.45))),
        const SizedBox(height: 14),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onRetry,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              const Icon(Icons.refresh_rounded, size: 16, color: AppColors.brandGreen),
              const SizedBox(width: 6),
              Text(retryLabel,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.brandGreen)),
            ]),
          ),
        ),
      ],
    );
  }
}

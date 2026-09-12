import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/strings.dart';
import '../core/theme.dart';

/// Task 62 — مكتبة واجهات الموبايل: نسخة Flutter حرفية من مكوّنات الويب
/// (globals.css + components/ui) بنفس القياسات: بطاقات rounded-xl(14) بظل sm،
/// أزرار h-10 rounded-lg، شارات rounded-full، حقول h-12 rounded-xl بتركيز
/// ring-4، جداول برأس bg-muted/40، ونوافذ Modal rounded-lg p-6.

// ---------------------------------------------------------------- العلامة

/// علامة Pharmacy OS — نفس SVG: مربع أخضر مائل -5° بثلاث أشرطة داكنة
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final s = size;
    return Transform.rotate(
      angle: -5 * 3.141592653589793 / 180,
      child: SizedBox(
        width: s,
        height: s,
        child: Stack(
          children: <Widget>[
            Container(
              decoration: BoxDecoration(
                color: AppColors.brandGreen,
                borderRadius: BorderRadius.circular(s * 30 / 128),
              ),
            ),
            Positioned(
              left: s * 42 / 128,
              top: s * 43 / 128,
              child: _bar(s, 45),
            ),
            Positioned(
              left: s * 61 / 128,
              top: s * 32 / 128,
              child: _bar(s, 67),
            ),
            Positioned(
              left: s * 80 / 128,
              top: s * 43 / 128,
              child: _bar(s, 45),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(double s, double h) {
    return Container(
      width: s * 14 / 128,
      height: s * h / 128,
      decoration: BoxDecoration(
        color: AppColors.brandBars,
        borderRadius: BorderRadius.circular(s * 7 / 128),
      ),
    );
  }
}

/// الشعار الكامل: العلامة + كلمة Pharmacy OS (نسختا فاتح/داكن مثل SVGs)
class BrandLogo extends StatelessWidget {
  final double height;
  final bool dark;
  const BrandLogo({super.key, this.height = 36, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final wordColor = dark ? AppColors.brandTextDark : AppColors.brandTextLight;
    final fontSize = height * 42 / 128 * 1.55; // 42px في SVG بعرض 520 مقابل أيقونة 128
    return Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
      BrandMark(size: height),
      SizedBox(width: height * 0.22),
      RichText(
        text: TextSpan(
          children: <TextSpan>[
            TextSpan(
              text: 'Pharmacy',
              style: TextStyle(
                color: wordColor,
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: -fontSize * 0.055,
                height: 1,
              ),
            ),
            TextSpan(
              text: ' OS',
              style: TextStyle(
                color: dark ? AppColors.brandGreen : AppColors.brandOsLight,
                fontSize: fontSize,
                fontWeight: FontWeight.w400,
                letterSpacing: -fontSize * 0.045,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- الدوّارات

/// دوران مشترك 1s خطي — مطابق لـ animate-spin في تويليند.
class _Spin extends StatefulWidget {
  final Widget child;
  const _Spin({required this.child});

  @override
  State<_Spin> createState() => _SpinState();
}

class _SpinState extends State<_Spin> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(turns: _c, child: widget.child);
  }
}

/// رسّام قوس حلقي — أداة مشتركة لكل الدوّارات أدناه (زوايا براديان،
/// 0 = الساعة 3، الاتجاه الموجب = مع عقارب الساعة مثل إحداثيات الويب).
class _RingArcPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double startAngle;
  final double sweepAngle;
  final StrokeCap cap;
  const _RingArcPainter({
    required this.color,
    required this.strokeWidth,
    required this.startAngle,
    required this.sweepAngle,
    this.cap = StrokeCap.butt,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = cap
      ..color = color;
    canvas.drawArc((Offset.zero & size).deflate(strokeWidth / 2), startAngle, sweepAngle, false, p);
  }

  @override
  bool shouldRepaint(covariant _RingArcPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.startAngle != startAngle ||
      old.sweepAngle != sweepAngle ||
      old.cap != cap;
}

/// LoadingSpinner في الويب (components/ui/loading.tsx) حرفيًا:
/// h-8 w-8 border-4 border-blue-600 border-t-transparent rounded-full
/// animate-spin — حلقة 32px بحد 4px أزرق #2563eb وفجوة الربع العلوي.
class WebLoadingSpinner extends StatelessWidget {
  final double size;
  const WebLoadingSpinner({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return _Spin(
      child: CustomPaint(
        size: Size.square(size),
        painter: _RingArcPainter(
          color: const Color(0xFF2563EB), // blue-600
          strokeWidth: size / 8, // 4px عند 32px
          startAngle: -math.pi / 4,
          sweepAngle: math.pi * 3 / 2,
        ),
      ),
    );
  }
}

/// Loader2 الصغير (أيقونة لوسيد الدوّارة) — قوس 270° بأطراف دائرية.
/// يُستخدم بأحجام الويب h-4/h-6/h-8 وبألوان primary أو muted-foreground.
class LoaderSpin extends StatelessWidget {
  final double size;
  final Color? color;
  const LoaderSpin({super.key, this.size = 16, this.color});

  @override
  Widget build(BuildContext context) {
    return _Spin(
      child: CustomPaint(
        size: Size.square(size),
        painter: _RingArcPainter(
          color: color ?? Theme.of(context).colorScheme.primary,
          strokeWidth: size * 2 / 24, // lucide stroke-width 2 على viewBox 24
          startAngle: 0,
          sweepAngle: math.pi * 3 / 2,
          cap: StrokeCap.round,
        ),
      ),
    );
  }
}

/// دوّار الزر ثنائي اللون (ui/button.tsx) حرفيًا: حلقة كاملة opacity-25
/// وقوس 90° opacity-75 — h-4 w-4 يلفّ animate-spin.
class ButtonSpinner extends StatelessWidget {
  final double size;
  final Color color;
  const ButtonSpinner({super.key, this.size = 16, required this.color});

  @override
  Widget build(BuildContext context) {
    return _Spin(
      child: CustomPaint(
        size: Size.square(size),
        painter: _TwoTonePainter(color: color, strokeWidth: size * 4 / 24),
      ),
    );
  }
}

class _TwoTonePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  const _TwoTonePainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final Paint base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color.withOpacity(0.25);
    canvas.drawCircle(rect.center, rect.width / 2, base);
    final Paint arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt
      ..color = color.withOpacity(0.75);
    // الونش الممتلئ في svg يغطي الربع العلوي الأيسر: من الساعة 9 إلى 12
    canvas.drawArc(rect, math.pi, math.pi / 2, false, arc);
  }

  @override
  bool shouldRepaint(covariant _TwoTonePainter old) => old.color != color;
}

// ---------------------------------------------------------------- BrandSplash

/// نسخة Flutter حرفية من brand-splash.tsx + brand-splash.css — شاشة التحميل
/// ذات الهوية كما في الويب: تدرّج خلفي ثلاثي الطبقات، ثلاث كرات ضوئية عائمة
/// (blur 70px)، منصة 132px بتوهج متنفّس وحلقتَي سونار (2.6s، الثانية بتأخير
/// 1.3s)، أيقونة 96px تهتز بمنحنى bsWiggle كاملًا، عنوان 30px w800 بتوهج
/// أخضر، وثلاث نقاط ترقص (1.3s بتأخيرات 0/0.18/0.36) — وخروج fade+scale(1.06)
/// +blur(10px) خلال 0.5s مثل bs-exiting. تحترم disableAnimations.
class BrandSplash extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Widget? footer;
  final bool exiting;
  const BrandSplash({
    super.key,
    this.title = 'Pharmacy OS',
    this.subtitle,
    this.footer,
    this.exiting = false,
  });

  @override
  State<BrandSplash> createState() => _BrandSplashState();
}

class _BrandSplashState extends State<BrandSplash> with TickerProviderStateMixin {
  static const Color _bg1 = Color(0xFF04150D);
  static const Color _bg2 = Color(0xFF083F2B);
  static const Color _bg3 = Color(0xFF0A5C3D);
  static const Color _text = Color(0xFFECFDF5);
  static const Color _accent = AppColors.brandGreen; // #00d084

  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
  late final AnimationController _fades = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..forward();
  late final AnimationController _wiggle = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
  late final AnimationController _glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
  late final AnimationController _ring = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
  late final AnimationController _dots = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();
  late final AnimationController _orbA = AnimationController(vsync: this, duration: const Duration(milliseconds: 26000))..repeat(reverse: true);
  late final AnimationController _orbB = AnimationController(vsync: this, duration: const Duration(milliseconds: 34000))..repeat(reverse: true);
  late final AnimationController _orbC = AnimationController(vsync: this, duration: const Duration(milliseconds: 22000))..repeat(reverse: true);
  late final AnimationController _exit = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));

  @override
  void initState() {
    super.initState();
    if (widget.exiting) _exit.forward();
  }

  @override
  void didUpdateWidget(covariant BrandSplash old) {
    super.didUpdateWidget(old);
    if (widget.exiting && !old.exiting) _exit.forward();
  }

  @override
  void dispose() {
    for (final AnimationController c in <AnimationController>[_enter, _fades, _wiggle, _glow, _ring, _dots, _orbA, _orbB, _orbC, _exit]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---- أدوات إقلاع المفاتيح (keyframes) ----

  double _seqLerp(double t, List<double> keys, List<double> vals) {
    for (int i = 0; i < keys.length - 1; i++) {
      if (t <= keys[i + 1]) {
        final double f = ((t - keys[i]) / (keys[i + 1] - keys[i])).clamp(0.0, 1.0);
        return vals[i] + (vals[i + 1] - vals[i]) * Curves.easeInOut.transform(f);
      }
    }
    return vals.last;
  }

  // ---- الخلفية: linear 160deg + اثنتا radial كما في bs-root ----

  Widget _background() {
    return Positioned.fill(
      child: Stack(
        children: <Widget>[
          Container(
            decoration: const BoxDecoration(
                // Task 72 — شبكة أمان Impeller نفسها: لون صلب تحت التدرّج
                // يظهر فقط إن سقط رسم التدرّج فلا تبقى الشاشة شفافة.
                color: Color(0xFF04150D),
                gradient: LinearGradient(
                  begin: Alignment(-0.17, -0.47), // 160deg
                  end: Alignment(0.17, 0.47),
                  colors: <Color>[_bg1, Color(0xFF020B06)],
                )),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.7, 1.0), // at 85% 100%
                radius: 1.1,
                colors: <Color>[_bg2, Color(0x00083F2B)],
                stops: <double>[0.0, 0.6],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.0, -1.0), // at 50% 0%
                radius: 1.35,
                colors: <Color>[_bg3, Color(0x000A5C3D)],
                stops: <double>[0.0, 0.55],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// كرة ضوئية عائمة — blur(70px) يُقارّب بتدرّج شعاعي ناعم.
  Widget _orb({
    required double size,
    required double alpha,
    required AnimationController c,
    required Offset drift,
    required double s0,
    required double s1,
    bool flip = false,
    bool reduce = false,
  }) {
    final Color tint = _accent.withOpacity(alpha);
    return AnimatedBuilder(
      animation: c,
      builder: (BuildContext context, Widget? child) {
        final double t = reduce ? (flip ? 1.0 : 0.0) : Curves.easeInOut.transform(flip ? 1 - c.value : c.value);
        return Transform.translate(
          offset: Offset(drift.dx * t, drift.dy * t),
          child: Transform.scale(scale: s0 + (s1 - s0) * t, child: child),
        );
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[tint, tint.withOpacity(alpha * 0.7), tint.withOpacity(0)],
            stops: const <double>[0.0, 0.55, 1.0],
          ),
        ),
      ),
    );
  }

  // ---- منصة الأيقونة ----

  Widget _stage(bool reduce) {
    return AnimatedBuilder(
      animation: _enter,
      builder: (BuildContext context, Widget? child) {
        final double t = reduce ? 1.0 : Curves.easeOutBack.transform(_enter.value);
        return Transform.scale(
          scale: 0.55 + 0.45 * t,
          child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
        );
      },
      child: SizedBox(
        width: 132,
        height: 132,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: <Widget>[_glowWidget(reduce), _ringWidget(0, reduce), _ringWidget(0.5, reduce), _iconWidget(reduce)],
        ),
      ),
    );
  }

  Widget _glowWidget(bool reduce) {
    // keyframes: 0/50/100 → .4/.92؛ 9/20 → .85/1.14
    return AnimatedBuilder(
      animation: _glow,
      builder: (BuildContext context, _) {
        final double t = _glow.value;
        final double op = reduce
            ? 0.45
            : _seqLerp(t, const <double>[0, 9, 20, 50, 100], const <double>[0.40, 0.85, 0.85, 0.40, 0.40]);
        final double sc = reduce
            ? 1.0
            : _seqLerp(t, const <double>[0, 9, 20, 50, 100], const <double>[0.92, 1.14, 1.14, 0.92, 0.92]);
        return Opacity(
          opacity: op,
          child: Transform.scale(
            scale: sc,
            child: Container(
              width: 200, // inset -34px حول المنصة 132
              height: 200,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[Color(0x8000D084), Color(0x2400D084), Color(0x0000D084)],
                  stops: <double>[0.0, 0.45, 0.7],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// حلقة سونار — scale .82→1.9 وopacity .6→0 خلال 65% من الدورة (2.6s)،
  /// الثانية بتأخير 1.3s (نصف دورة).
  Widget _ringWidget(double phase, bool reduce) {
    return AnimatedBuilder(
      animation: _ring,
      builder: (BuildContext context, _) {
        if (reduce) return const SizedBox.shrink();
        double t = (_ring.value - phase) % 1.0;
        if (t < 0) t += 1.0;
        const double k = 0.65;
        final double p = (t / k).clamp(0.0, 1.0);
        final double scale = 0.82 + (1.9 - 0.82) * Curves.easeOutCubic.transform(p);
        final double op = p >= 1 ? 0 : 0.6 * (1 - p);
        return Opacity(
          opacity: op,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _accent.withOpacity(0.6), width: 2),
              ),
            ),
          ),
        );
      },
    );
  }

  /// الأيقونة 96px — اهتزاز bsWiggle كامل (منحنيات الأصل بالدرجات).
  Widget _iconWidget(bool reduce) {
    return AnimatedBuilder(
      animation: _wiggle,
      builder: (BuildContext context, Widget? child) {
        final double t = _wiggle.value;
        final double deg = reduce
            ? 0
            : _seqLerp(t, const <double>[0, 7, 17, 27, 36, 44, 50, 100], const <double>[0, -10, 8, -5.5, 3.5, -1.2, 0, 0]);
        final double sc = reduce
            ? 1.0
            : _seqLerp(t, const <double>[0, 7, 17, 27, 36, 44, 50, 100], const <double>[1, 1.06, 1.06, 1.04, 1.02, 1.0, 1.0, 1.0]);
        return Transform.rotate(
          angle: deg * math.pi / 180,
          child: Transform.scale(scale: sc, child: child),
        );
      },
      child: Container(
        width: 96,
        height: 96,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          boxShadow: <BoxShadow>[
            BoxShadow(color: const Color(0xFF020B06).withOpacity(0.9), offset: const Offset(0, 22), blurRadius: 44, spreadRadius: -14),
            BoxShadow(color: _accent.withOpacity(0.55), offset: const Offset(0, 6), blurRadius: 18, spreadRadius: -6),
          ],
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.22), width: 1)), // inset 0 1px 0 rgba(255,255,255,.22)
        ),
        child: const BrandMark(size: 96),
      ),
    );
  }

  /// دخول العناوين bsFadeUp — تأخيرات 0.18/0.3/0.42 داخل دورة 1.4s.
  Widget _fadeUp(double delay, bool reduce, Widget child) {
    final double b = (delay / 1.4).clamp(0.0, 1.0);
    final double e = ((delay + 0.7) / 1.4).clamp(0.0, 1.0);
    return AnimatedBuilder(
      animation: _fades,
      builder: (BuildContext context, Widget? c) {
        final double t = reduce ? 1.0 : Curves.ease.transform(Interval(b, e).transform(_fades.value));
        return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: c));
      },
      child: child,
    );
  }

  Widget _dot(double delayFrac, bool reduce) {
    return AnimatedBuilder(
      animation: _dots,
      builder: (BuildContext context, _) {
        double t = (_dots.value - delayFrac) % 1.0;
        if (t < 0) t += 1.0;
        // 0/65/100 → y0 s.8 op.4؛ 32 → y-8 s1.12 op1
        final double f1 = Curves.easeInOut.transform((t / 0.32).clamp(0.0, 1.0));
        final double f2 = Curves.easeInOut.transform(((t - 0.32) / 0.33).clamp(0.0, 1.0));
        final double y = reduce ? 0 : (t < 0.32 ? -8 * f1 : -8 * (1 - f2));
        final double s = reduce ? 1.0 : (t < 0.32 ? 0.8 + 0.32 * f1 : 1.12 - 0.32 * f2);
        final double op = reduce ? 0.7 : (t < 0.32 ? 0.4 + 0.6 * f1 : 1.0 - 0.6 * f2);
        return Transform.translate(
          offset: Offset(0, y),
          child: Transform.scale(
            scale: s,
            child: Opacity(
              opacity: op,
              child: Container(width: 9, height: 9, decoration: const BoxDecoration(shape: BoxShape.circle, color: _accent)),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool reduce = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: _exit,
      builder: (BuildContext context, Widget? child) {
        final double t = Curves.ease.transform(_exit.value);
        if (t <= 0.002) return child!;
        return Opacity(
          opacity: 1 - t,
          child: Transform.scale(
            scale: 1 + 0.06 * t,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 10 * t, sigmaY: 10 * t),
              child: child,
            ),
          ),
        );
      },
      child: ColoredBox(
        color: _bg1,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints cons) {
            final double w = cons.maxWidth;
            final double h = cons.maxHeight;
            return Stack(
              children: <Widget>[
                _background(),
                // orb-1: 320px أعلى اليمين — bsFloat1 13s (translate -50,45 ×1.18)
                Positioned(top: -80, right: -60, child: _orb(size: 320, alpha: 0.40, c: _orbA, drift: const Offset(-50, 45), s0: 1, s1: 1.18, reduce: reduce)),
                // orb-2: 260px أسفل اليسار — bsFloat2 17s (translate 55,-40 ×0.92)
                Positioned(bottom: -70, left: -50, child: _orb(size: 260, alpha: 0.26, c: _orbB, drift: const Offset(55, -40), s0: 1.1, s1: 0.92, reduce: reduce)),
                // orb-3: 180px bottom 22% right 12% — 11s alternate-reverse
                Positioned(bottom: h * 0.22, right: w * 0.12, child: _orb(size: 180, alpha: 0.20, c: _orbC, drift: const Offset(-50, 45), s0: 1, s1: 1.18, flip: true, reduce: reduce)),
                Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        _stage(reduce),
                        const SizedBox(height: 34),
                        _fadeUp(0.18, reduce, Text(widget.title, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: _text, shadows: <Shadow>[Shadow(color: _accent.withOpacity(0.4), offset: const Offset(0, 2), blurRadius: 18)]))),
                        if (widget.subtitle != null) ...<Widget>[
                          const SizedBox(height: 8),
                          _fadeUp(0.30, reduce, Text(widget.subtitle!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _text.withOpacity(0.72)))),
                        ],
                        const SizedBox(height: 22),
                        _fadeUp(
                          0.42,
                          reduce,
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              _dot(0.0, reduce),
                              const SizedBox(width: 10),
                              _dot(0.18 / 1.3, reduce),
                              const SizedBox(width: 10),
                              _dot(0.36 / 1.3, reduce),
                            ],
                          ),
                        ),
                        if (widget.footer != null) ...<Widget>[
                          const SizedBox(height: 30),
                          _fadeUp(0.55, reduce, widget.footer!),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- خلفية الدخول

/// الدائرتان الضبابيتان في خلفية شاشات auth (blur-3xl = 64px)
class BlurBlobs extends StatelessWidget {
  const BlurBlobs({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = dark ? AppColors.darkPrimary : AppColors.lightPrimary;
    return IgnorePointer(
      child: ClipRect(
        child: Stack(
          children: <Widget>[
            Positioned(
              left: -128,
              top: -128,
              child: _blob(primary.withOpacity(0.10)),
            ),
            Positioned(
              right: -96,
              bottom: -160,
              child: _blob(AppColors.blobEmerald),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blob(Color color) {
    return Container(
      width: 384,
      height: 384,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 64, sigmaY: 64),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// غلاف شاشات المصادقة: خلفية + دوائر ضبابية + SafeArea
class AuthShell extends StatelessWidget {
  final Widget child;
  const AuthShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: <Widget>[
          const Positioned.fill(child: BlurBlobs()),
          SafeArea(child: child),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- بطاقات

/// Card في الويب: rounded-xl border bg-card shadow-sm hover:shadow-md
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final double? radius;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = BorderRadius.circular(radius ?? AppRadius.xl);
    final body = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? theme.colorScheme.surface,
        borderRadius: r,
        border: Border.all(color: theme.dividerColor),
        boxShadow: WebShadow.sm,
      ),
      child: child,
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: r, onTap: onTap, child: body),
    );
  }
}

/// مربّع داخلي محدد — rounded-xl border p-3.5/p-4 (سطور النواقص، سطور السلة،
/// خانة العميل الآجل، جدول المراجعة في المعالج)
class CardBox extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? color;
  final double radius;
  const CardBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.borderColor,
    this.color,
    this.radius = AppRadius.xl,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = BorderRadius.circular(radius);
    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Colors.transparent,
        borderRadius: shape,
        border: Border.all(color: borderColor ?? theme.dividerColor),
      ),
      child: child,
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: shape, onTap: onTap, child: body),
    );
  }
}

/// CardTitle في الويب: text-lg font-semibold (18px)
class CardTitle extends StatelessWidget {
  final String text;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;
  const CardTitle(this.text, {super.key, this.subtitle, this.trailing, this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...<Widget>[
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.25)),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(subtitle!, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// رأس البطاقة: CardHeader p-6 مع مسافة سفلية للمحتوى
class CardHeader extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const CardHeader(this.child, {super.key, this.padding = const EdgeInsets.fromLTRB(24, 24, 24, 12)});

  @override
  Widget build(BuildContext context) => Padding(padding: padding, child: child);
}

/// CardContent p-6
class CardContentBox extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const CardContentBox(this.child, {super.key, this.padding = const EdgeInsets.all(24)});

  @override
  Widget build(BuildContext context) => Padding(padding: padding, child: child);
}

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  const SectionHeader(this.title, {super.key, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// رأس الصفحة في كل صفحات اللوحة: h1 text-2xl font-bold + subtitle text-sm
/// muted + أزرار إجراءات — بنفس سلوك الويب flex-col sm:flex-row sm:items-center:
/// تحت 640px العنوان فوق والأزرار تحته في سطر يلتفّ (flex-wrap)، ومن 640px
/// يصيران في صف واحد مع توسيط رأسي — فلا يُخنَق العنوان أبدًا حتى مع زرّين.
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  const PageHeader(this.title, {super.key, this.subtitle, this.actions = const <Widget>[]});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.25)),
        if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8), // mt-2
          Text(subtitle!, style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.55))),
        ],
      ],
    );
    if (actions.isEmpty) return titleBlock;
    final Widget actionsWrap = Wrap(spacing: 8, runSpacing: 8, children: actions);
    return LayoutBuilder(builder: (BuildContext ctx, BoxConstraints c) {
      // مثل الويب: sm: (640px) هو حد التحول من عمود إلى صف
      if (c.maxWidth < 640) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            titleBlock,
            const SizedBox(height: 16), // gap-4
            actionsWrap,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center, // sm:items-center
        children: <Widget>[
          Expanded(child: titleBlock),
          const SizedBox(width: 16),
          actionsWrap,
        ],
      );
    });
  }
}

// ---------------------------------------------------------------- أزرار

enum WButtonVariant { primary, outline, ghost, secondary, destructive, gradient, link }

enum WButtonSize { sm, md, lg, xl, wizard, icon, iconSm }

/// زر الويب Button بكل متغيراته: rounded-lg shadow-sm active:scale-[0.98]
/// وgradient من primary إلى oklch(0.7 0.15 180) وظل primary للأزرار الكبيرة.
class WButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final WButtonVariant variant;
  final WButtonSize size;
  final bool expand;
  final Color? color;
  final bool glow; // shadow-lg shadow-primary/20 (أزرار الدخول والمعالجات)
  const WButton(
    this.label, {
    super.key,
    this.onPressed,
    this.loading = false,
    this.icon,
    this.variant = WButtonVariant.primary,
    this.size = WButtonSize.md,
    this.expand = false,
    this.color,
    this.glow = false,
  });

  @override
  State<WButton> createState() => _WButtonState();
}

class _WButtonState extends State<WButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme;
    final primary = scheme.primary;

    late Color fg;
    late Color bg;
    BorderSide side = BorderSide.none;
    List<BoxShadow> shadows = const <BoxShadow>[];
    Gradient? gradient;

    switch (widget.variant) {
      case WButtonVariant.primary:
        fg = scheme.onPrimary;
        bg = primary;
        shadows = WebShadow.sm;
      case WButtonVariant.outline:
        fg = scheme.onSurface;
        bg = dark ? Colors.transparent : scheme.surface; // bg-background
        side = BorderSide(color: theme.dividerColor);
        shadows = WebShadow.sm;
      case WButtonVariant.ghost:
        fg = scheme.onSurface;
        bg = Colors.transparent;
      case WButtonVariant.secondary:
        fg = dark ? AppColors.darkForeground : AppColors.lightSecondaryFg;
        bg = dark ? AppColors.darkSecondary : AppColors.lightSecondary;
        shadows = WebShadow.sm;
      case WButtonVariant.destructive:
        fg = scheme.onError;
        bg = scheme.error;
        shadows = WebShadow.sm;
      case WButtonVariant.gradient:
        fg = scheme.onPrimary;
        // Task 72 — «شكل الزر غريب»: على أندرويد يفعّل Flutter 3.24 محرك
        // Impeller افتراضيًا، وقد أبلغ مستخدم عن زر يظهر رماديًا باهتًا:
        // تحليل بكسلات اللقطة أثبت أن التدرّج لم يُرسم أصلًا (رماديّة الزر
        // = ظلّاه 10% متراكبان يظهران عبر تعبئة شفافة). لذلك bg = primary
        // كشبكة أمان: BoxDecoration يرسم color أولًا ثم التدرّج فوقه —
        // إذا رُسم التدرّج فلا فرق بصريًا، وإذا سقط (خلل Impeller مع
        // التدرّجات داخل AnimatedContainer) يظهر الزر أخضر صلبًا بلون
        // بداية التدرّج نفسه كالويب from-primary لا شفافًا.
        bg = primary;
        gradient = LinearGradient(colors: <Color>[primary, AppColors.gradientEnd]);
        shadows = WebShadow.md;
      case WButtonVariant.link:
        fg = primary;
        bg = Colors.transparent;
    }
    if (widget.color != null) fg = widget.color!;
    if (widget.glow) shadows = WebShadow.primaryGlow(primary);

    double height;
    double radius;
    EdgeInsets pad;
    double fontSize;
    double iconSize;
    switch (widget.size) {
      case WButtonSize.sm:
        height = 36;
        radius = AppRadius.md;
        pad = const EdgeInsets.symmetric(horizontal: 12);
        fontSize = 13;
        iconSize = 16;
      case WButtonSize.lg:
        height = 44;
        radius = AppRadius.v;
        pad = const EdgeInsets.symmetric(horizontal: 24);
        fontSize = 14;
        iconSize = 18;
      case WButtonSize.xl:
        height = 48;
        radius = AppRadius.xl;
        pad = const EdgeInsets.symmetric(horizontal: 32);
        fontSize = 16;
        iconSize = 18;
      case WButtonSize.wizard:
        height = 52; // h-13 في صفحات المعالج
        radius = AppRadius.xxl;
        pad = const EdgeInsets.symmetric(horizontal: 24);
        fontSize = 14;
        iconSize = 18;
      case WButtonSize.icon:
        height = 40;
        radius = AppRadius.v;
        pad = EdgeInsets.zero;
        fontSize = 0;
        iconSize = 20;
      case WButtonSize.iconSm:
        height = 36;
        radius = AppRadius.md;
        pad = EdgeInsets.zero;
        fontSize = 0;
        iconSize = 18;
      case WButtonSize.md:
        height = 40;
        radius = AppRadius.v;
        pad = const EdgeInsets.symmetric(horizontal: 16);
        fontSize = 14;
        iconSize = 18;
    }

    final disabled = widget.onPressed == null || widget.loading;
    final content = widget.size == WButtonSize.icon || widget.size == WButtonSize.iconSm
        ? (widget.loading
            ? _spinner(fg, 18)
            : Icon(widget.icon, size: iconSize, color: fg))
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (widget.loading)
                _spinner(fg, iconSize)
              else if (widget.icon != null)
                Icon(widget.icon, size: iconSize, color: fg),
              if ((widget.loading || widget.icon != null) && widget.label.isNotEmpty)
                const SizedBox(width: 8),
              if (widget.label.isNotEmpty)
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500, color: fg),
                  ),
                ),
            ],
          );

    final button = AnimatedScale(
      scale: _pressed && !disabled ? 0.98 : 1, // active:scale-[0.98]
      duration: const Duration(milliseconds: 120),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: height,
        padding: pad,
        decoration: BoxDecoration(
          color: bg,
          gradient: gradient,
          borderRadius: BorderRadius.circular(radius),
          border: Border.fromBorderSide(side),
          boxShadow: disabled ? const <BoxShadow>[] : shadows,
        ),
        child: content,
      ),
    );

    return Opacity(
      opacity: disabled && widget.loading ? 1 : (disabled ? 0.5 : 1),
      child: GestureDetector(
        onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: disabled
            ? null
            : () {
                setState(() => _pressed = false);
                widget.onPressed!();
              },
        child: button,
      ),
    );
  }

  /// دوّار الزر في الويب (ui/button.tsx) — ثنائي اللون h-4 w-4 حرفيًا.
  Widget _spinner(Color color, double size) => ButtonSpinner(size: 16, color: color);
}

/// PrimaryButton القديم = variant primary بعرض كامل (بنفس التوافق السابق)
class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  const PrimaryButton(this.text, {super.key, this.onPressed, this.loading = false, this.icon});

  @override
  Widget build(BuildContext context) {
    return WButton(text, onPressed: onPressed, loading: loading, icon: icon, expand: true);
  }
}

/// variant secondary بعرض كامل
class SecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  const SecondaryButton(this.text, {super.key, this.onPressed, this.icon});

  @override
  Widget build(BuildContext context) {
    return WButton(text, onPressed: onPressed, icon: icon, variant: WButtonVariant.secondary, expand: true);
  }
}

class GhostButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  const GhostButton(this.text, {super.key, this.onPressed, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    return WButton(text, onPressed: onPressed, icon: icon, variant: WButtonVariant.ghost, color: color);
  }
}

/// زر أيقونة شبح — ghost size icon (40×40 rounded-lg hover:bg-accent)
class IconButtonGhost extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final double size;
  const IconButtonGhost(this.icon, {super.key, this.onPressed, this.tooltip, this.color, this.size = 20});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final button = Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      child: Icon(icon, size: size, color: color ?? theme.colorScheme.onSurface.withOpacity(0.7)),
    );
    final w = Material(
      color: Colors.transparent,
      borderRadius: AppRadius.br,
      child: InkWell(
        borderRadius: AppRadius.br,
        onTap: onPressed,
        child: button,
      ),
    );
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

// ---------------------------------------------------------------- شارات

enum BadgeTone { primary, success, warning, destructive, muted, info }

class AppBadge extends StatelessWidget {
  final String text;
  final BadgeTone tone;
  const AppBadge(this.text, {super.key, this.tone = BadgeTone.muted});

  static BadgeTone saleStatus(String status) {
    switch (status) {
      case 'completed':
        return BadgeTone.success;
      case 'partially_returned':
        return BadgeTone.warning;
      case 'returned':
        return BadgeTone.destructive;
      default:
        return BadgeTone.muted;
    }
  }

  static BadgeTone stockStatus(String status) {
    switch (status) {
      case 'out_of_stock':
      case 'OUT_OF_STOCK':
        return BadgeTone.destructive;
      case 'low_stock':
      case 'LOW_STOCK':
        return BadgeTone.warning;
      case 'expiring':
      case 'EXPIRING':
        return BadgeTone.warning;
      case 'expired':
      case 'EXPIRED':
        return BadgeTone.destructive;
      default:
        // Task 68-k — الافتراضي muted (outline بالويب) لا أخضر النجاح:
        // شاشات المخزون تربط النغمات محليًا الآن فالتغيير آمن
        return BadgeTone.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final Color fg;
    final Color bg;
    switch (tone) {
      case BadgeTone.primary:
        fg = dark ? AppColors.darkPrimaryFg : AppColors.lightPrimaryFg;
        bg = dark ? AppColors.darkPrimary : AppColors.lightPrimary;
      case BadgeTone.success:
        fg = dark ? AppColors.successFgDark : AppColors.successFg;
        bg = const Color(0x2610B981); // emerald-500/15
      case BadgeTone.warning:
        fg = dark ? AppColors.warningFgDark : AppColors.warningFg;
        bg = const Color(0x26F59E0B); // amber-500/15
      case BadgeTone.destructive:
        fg = dark ? AppColors.darkPrimaryFg : AppColors.lightDestructiveFg;
        bg = dark ? AppColors.darkDestructive : AppColors.lightDestructive;
      case BadgeTone.info:
        fg = dark ? AppColors.infoFgDark : AppColors.infoFg;
        bg = const Color(0x262563EB); // blue-500/15
      case BadgeTone.muted:
        fg = dark ? AppColors.darkForeground : AppColors.lightForeground;
        bg = Colors.transparent;
    }
    final isOutline = tone == BadgeTone.muted;
    final isFilled = tone == BadgeTone.primary || tone == BadgeTone.destructive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2), // px-2.5 py-0.5
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: isOutline ? Border.all(color: theme.dividerColor) : null,
        boxShadow: isFilled ? WebShadow.sm : null,
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg, height: 1.35),
      ),
    );
  }
}

/// شارة حالة صلاحية التشغيلة بأيام متبقية (كصفحة المخزون في الويب)
class ExpiryBadge extends StatelessWidget {
  final int? days;
  const ExpiryBadge(this.days, {super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    if (days == null) return const SizedBox.shrink();
    final d = days!;
    if (d < 0) return AppBadge(i18n.t('inventory', 'expired'), tone: BadgeTone.destructive);
    if (d <= 30) return AppBadge(i18n.t('inventory', 'expires_30', {'days': '$d'}), tone: BadgeTone.destructive);
    if (d <= 60) return AppBadge(i18n.t('inventory', 'expires_60', {'days': '$d'}), tone: BadgeTone.warning);
    if (d <= 90) return AppBadge(i18n.t('inventory', 'expires_90', {'days': '$d'}), tone: BadgeTone.info);
    return const SizedBox.shrink();
  }
}

// ---------------------------------------------------------------- إحصائيات

enum StatTone { primary, warning, success, info }

/// بطاقة إحصائية اللوحة — طبق الأصل من صفحة الويب:
/// Card p-6: label text-sm muted ثم value text-2xl font-bold (mt-3)،
/// وصندوق أيقونة rounded-xl p-3 بلون النغمة في الجهة المقابلة.
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final StatTone tone;
  const StatCard({super.key, required this.label, required this.value, required this.icon, required this.tone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    late final Color fg;
    late final Color bg;
    switch (tone) {
      case StatTone.warning:
        fg = dark ? AppColors.warningFgDark : AppColors.warningFg;
        bg = AppColors.warningBg;
      case StatTone.success:
        fg = dark ? AppColors.successFgDark : AppColors.successFg;
        bg = AppColors.successBg;
      case StatTone.info:
        fg = dark ? AppColors.infoFgDark : AppColors.infoFg;
        bg = AppColors.infoBg;
      case StatTone.primary:
        fg = dark ? AppColors.darkPrimary : AppColors.lightPrimary;
        bg = fg.withOpacity(0.10);
    }
    return AppCard(
      padding: const EdgeInsets.all(24), // p-6
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                const SizedBox(height: 12), // mt-3
                FittedBox(
                  child: Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.1)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(12), // p-3
            decoration: BoxDecoration(color: bg, borderRadius: AppRadius.brXl),
            child: Icon(icon, size: 20, color: fg),
          ),
        ],
      ),
    );
  }
}

/// بطاقة إجراء سريع — grid tile: rounded-xl border، أيقونة 24 primary فوق
/// تسمية text-xs، مع إبراز الحد عند اللمس (hover:border-primary/30)
class QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const QuickActionTile({super.key, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: AppRadius.brXl,
      child: InkWell(
        borderRadius: AppRadius.brXl,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16), // px-3 py-4
          decoration: BoxDecoration(
            borderRadius: AppRadius.brXl,
            border: Border.all(color: theme.dividerColor),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 24, color: primary),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

/// سطر صنف ناقص في اللوحة — rounded-xl border p-3.5 مع صندوق أيقونة 40×40
/// amber وخاصية التوفر كشارة، ثم سطر حد الطلب الصغير
class LowStockTile extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String name;
  final String? subtitle;
  final String badge;
  final BadgeTone badgeTone;
  final String? note;
  const LowStockTile({
    super.key,
    this.icon = Icons.medication_outlined,
    required this.iconBg,
    required this.iconFg,
    required this.name,
    this.subtitle,
    required this.badge,
    this.badgeTone = BadgeTone.warning,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: iconBg, borderRadius: AppRadius.brXl),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: iconFg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AppBadge(badge, tone: badgeTone),
            ],
          ),
          if (note != null && note!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(note!, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5))),
          ],
        ],
      ),
    );
  }
}

/// شريط تقدم المعالجات (التسجيل/الإعداد): h-1.5 w-32 rounded-full bg-muted
/// بتعبئة primary متحركة
class ProgressTrack extends StatelessWidget {
  final double value; // 0..1
  final double width;
  const ProgressTrack({super.key, required this.value, this.width = 128});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        width: width,
        height: 6,
        child: Stack(
          children: <Widget>[
            Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
            AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
              widthFactor: value.clamp(0.0, 1.0),
              heightFactor: 1,
              alignment: AlignmentDirectional.centerStart,
              child: Container(color: Theme.of(context).colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}

/// هيكل عظمي نابض — عناصر القائمة أثناء تحميل الصلاحيات (animate-pulse)
class SkeletonBox extends StatefulWidget {
  final double height;
  final double? width;
  const SkeletonBox({super.key, this.height = 44, this.width});

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: AppRadius.br,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- حقول

/// تسمية الحقل: text-sm font-medium (mb-2)
class AppField extends StatelessWidget {
  final String label;
  final Widget child;
  final String? hint;
  final Widget? trailing;
  const AppField({super.key, required this.label, required this.child, this.hint, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
            if (trailing != null) trailing!,
          ],
        ),
        if (hint != null) ...<Widget>[
          const SizedBox(height: 2),
          Text(hint!, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5))),
        ],
        const SizedBox(height: 8), // mb-2
        child,
      ],
    );
  }
}

/// حقل عادي h-10 rounded-lg — نفس InputDecorationTheme
class AppInput extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboard;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final int maxLines;
  final FocusNode? focusNode;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final int? maxLength;
  final bool centered;
  final TextDirection? textDirection;
  const AppInput({super.key, required this.controller, this.hint, this.obscure = false,
      this.keyboard, this.validator, this.onChanged, this.enabled = true, this.maxLines = 1,
      this.focusNode, this.suffixIcon, this.prefixIcon, this.maxLength, this.centered = false,
      this.textDirection});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      validator: validator,
      onChanged: onChanged,
      enabled: enabled,
      maxLines: maxLines,
      maxLength: maxLength,
      focusNode: focusNode,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      textDirection: textDirection,
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        suffixIcon: suffixIcon,
        prefixIcon: prefixIcon,
      ),
      style: const TextStyle(fontSize: 14),
    );
  }
}

/// حقل شاشات الدخول: h-12 rounded-xl px-4 بتركيز ring-4 primary/10
/// (focus:border-primary focus:ring-4 focus:ring-primary/10)
class AuthInput extends StatefulWidget {
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboard;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool ltr;
  final bool alignEnd;
  final bool centered;
  final double height;
  final double fontSize;
  final FontWeight fontWeight;
  final TextDirection? textDirection;
  // Task 68-f — تمكين Enter للحقول (يلزم معالج WizardInput)؛ null = سلوك الافتراضي
  // كما كان تمامًا لكل الاستخدامات القائمة.
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  const AuthInput({
    super.key,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.keyboard,
    this.validator,
    this.onChanged,
    this.focusNode,
    this.ltr = false,
    this.alignEnd = false,
    this.centered = false,
    this.height = 48, // h-12
    this.fontSize = 14,
    this.fontWeight = FontWeight.w400,
    this.textDirection,
    this.onSubmitted,
    this.textInputAction,
  });

  @override
  State<AuthInput> createState() => _AuthInputState();
}

class _AuthInputState extends State<AuthInput> {
  final FocusNode _internal = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    (widget.focusNode ?? _internal).addListener(_handle);
  }

  void _handle() {
    final focused = (widget.focusNode ?? _internal).hasFocus;
    if (focused != _focused) setState(() => _focused = focused);
  }

  @override
  void dispose() {
    (widget.focusNode ?? _internal).removeListener(_handle);
    if (widget.focusNode == null) _internal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: widget.height,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor, // bg-background
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: _focused ? primary : theme.dividerColor, width: 1),
        boxShadow: _focused
            ? <BoxShadow>[BoxShadow(color: primary.withOpacity(0.10), blurRadius: 0, spreadRadius: 4)] // ring-4
            : const <BoxShadow>[],
      ),
      alignment: AlignmentDirectional.center,
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode ?? _internal,
        obscureText: widget.obscure,
        keyboardType: widget.keyboard,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        textInputAction: widget.textInputAction,
        textAlign: widget.centered ? TextAlign.center : (widget.alignEnd ? TextAlign.end : TextAlign.start),
        textDirection: widget.textDirection ?? (widget.ltr ? TextDirection.ltr : null),
        style: TextStyle(fontSize: widget.fontSize, fontWeight: widget.fontWeight),
        decoration: InputDecoration(
          hintText: widget.hint,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

/// حقل معالجات التسجيل/الإعداد: h-14 rounded-2xl px-5 text-base
/// Task 68-f — Enter يقدّم الخطوة التالية مثل onKeyDown في الويب
/// (register/page.tsx:92-97): onSubmitted اختياري، وtextInputAction الافتراضي
/// «next» عند توفيره، ويُمرر «done» صراحة للحقل الأخير في المعالج.
/// كلا المعاملين اختياريان — الاستخدامات القائمة (onboarding) بلا تغيير.
class WizardInput extends AuthInput {
  const WizardInput({
    super.key,
    required super.controller,
    super.hint,
    super.obscure,
    super.keyboard,
    super.validator,
    super.onChanged,
    super.focusNode,
    super.ltr,
    super.alignEnd,
    super.centered,
    super.textDirection,
    ValueChanged<String>? onSubmitted,
    TextInputAction? textInputAction,
  }) : super(
          height: 56,
          fontSize: 16, // h-14 text-base
          onSubmitted: onSubmitted,
          textInputAction:
              textInputAction ?? (onSubmitted != null ? TextInputAction.next : null),
        );
}

/// حقل البحث بأيقونة في البداية — مثل header والبطاقات في الويب
class SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  const SearchField({super.key, required this.controller, required this.hint, this.onChanged, this.onClear});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 18),
        prefixIconColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onClear),
        isDense: true,
      ),
      style: const TextStyle(fontSize: 14),
    );
  }
}

/// قائمة منسدلة — نفس هوية Input (Select في الويب)
class AppDropdown<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? hint;
  const AppDropdown({super.key, required this.value, required this.items, required this.onChanged, this.hint});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      hint: hint == null ? null : Text(hint!, style: const TextStyle(fontSize: 14)),
      isExpanded: true,
      icon: const Icon(Icons.keyboard_arrow_down, size: 20),
      decoration: const InputDecoration(),
      style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
    );
  }
}

class AppSwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const AppSwitchTile({super.key, required this.title, this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              if (subtitle != null)
                Text(subtitle!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55))),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

// ---------------------------------------------------------------- حالات

class EmptyState extends StatelessWidget {
  final IconData? icon;
  final String text;
  final String? actionText;
  final VoidCallback? onAction;
  final bool dashed;
  const EmptyState(this.text, {super.key, this.icon = Icons.inbox_outlined, this.actionText, this.onAction, this.dashed = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (dashed) {
      // مثل سلة POS الفارغة: rounded-xl border-dashed py-14 text-center
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 48),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: AppRadius.brXl,
          border: Border.all(color: theme.dividerColor, style: BorderStyle.solid),
        ),
        child: Text(text, style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.45))),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Column(
          children: [
            if (icon != null) ...<Widget>[
              Icon(icon, size: 44, color: theme.colorScheme.onSurface.withOpacity(0.25)),
              const SizedBox(height: 12),
            ],
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.55)),
            ),
            if (actionText != null && onAction != null) ...<Widget>[
              const SizedBox(height: 12),
              GhostButton(actionText!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

/// خطأ صفحة: Card بحد مضمر + رسالة + زر إعادة (p-8 text-center مثل الويب)
class ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorRetry(this.message, {super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      color: theme.colorScheme.error.withOpacity(0.06),
      child: Column(
        children: [
          Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: theme.colorScheme.error)),
          const SizedBox(height: 10),
          GhostButton(AppI18n.instance.t('common', 'retry'), onPressed: onRetry, icon: Icons.refresh),
        ],
      ),
    );
  }
}

class LoadingBox extends StatelessWidget {
  const LoadingBox({super.key});

  @override
  Widget build(BuildContext context) {
    // مثل الويب: LoadingSpinner الأزرق 32px (components/ui/loading.tsx)
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(child: WebLoadingSpinner()),
    );
  }
}

/// خطأ POS: rounded-lg border-destructive/30 bg-destructive/10 p-3
class ErrorBanner extends StatelessWidget {
  final String text;
  const ErrorBanner(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withOpacity(0.10),
        borderRadius: AppRadius.br,
        border: Border.all(color: theme.colorScheme.error.withOpacity(0.30)),
      ),
      child: Text(text, style: TextStyle(fontSize: 14, color: theme.colorScheme.error)),
    );
  }
}

/// نجاح POS: rounded-lg border-primary/30 bg-primary/10 p-3
class SuccessBanner extends StatelessWidget {
  final String text;
  final Widget? action;
  const SuccessBanner(this.text, {super.key, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.10),
        borderRadius: AppRadius.br,
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(text, style: TextStyle(fontSize: 14, color: theme.colorScheme.primary)),
          if (action != null) ...<Widget>[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}

/// إشعار مصادقة: rounded-xl border-primary/20 bg-primary/10 p-3
class NoticeBanner extends StatelessWidget {
  final String text;
  const NoticeBanner(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.10),
        borderRadius: AppRadius.brXl,
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.20)),
      ),
      child: Text(text, style: TextStyle(fontSize: 14, color: theme.colorScheme.primary)),
    );
  }
}

/// خطأ معالجات: rounded-xl bg-destructive/10 p-3 (بلا حد)
class FormErrorBanner extends StatelessWidget {
  final String text;
  const FormErrorBanner(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error.withOpacity(0.10),
        borderRadius: AppRadius.brXl,
      ),
      child: Text(text, style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.error)),
    );
  }
}

// ---------------------------------------------------------------- حوارات

/// Modal في الويب: طبقة سوداء 50% + بطاقة rounded-lg p-6 max-w-md
Future<T?> showAppModal<T>(BuildContext context, {String? title, required Widget child, bool dismissible = true}) {
  final theme = Theme.of(context);
  return showDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierColor: Colors.black.withOpacity(0.5),
    builder: (BuildContext ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 448), // max-w-md
          padding: const EdgeInsets.all(24), // p-6
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: AppRadius.br,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (title != null) ...<Widget>[
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                ],
                child,
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<bool?> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  String? confirmText,
  bool destructive = false,
}) {
  final i18n = AppI18n.instance;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body, style: const TextStyle(fontSize: 14)),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(i18n.t('common', 'cancel'))),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error)
              : null,
          child: Text(confirmText ?? i18n.t('common', 'confirm')),
        ),
      ],
    ),
  );
}

Future<void> appSnackbar(BuildContext context, String message, {bool error = false}) {
  return ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? Theme.of(context).colorScheme.error : null,
  )).closed;
}

/// ورقة سفلية بعنوان — للنماذج الطويلة على الموبايل
Future<T?> appBottomSheet<T>(BuildContext context, {required String title, required Widget child}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------- صفوف وعرض

class KVRow extends StatelessWidget {
  final String label;
  final String value;
  final bool money;
  const KVRow(this.label, this.value, {super.key, this.money = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.55)))),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// صف مبلغ بقالة فاصلة خفيفة (سطور الفاتورة والتقارير)
class AmountRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final int amountPiastres;
  final bool credit; // آجل
  final Widget? leading;
  final VoidCallback? onTap;
  const AmountRow({super.key, required this.title, this.subtitle, required this.amountPiastres,
      this.credit = false, this.leading, this.onTap});

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final amount = Fmt.money(amountPiastres, locale: i18n.locale);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onTap,
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[leading!, const SizedBox(width: 10)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                if (subtitle != null)
                  Text(subtitle!, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5))),
              ],
            ),
          ),
          Text(amount, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: credit ? AppColors.warningFg : null)),
        ],
      ),
    );
  }
}

/// جدول الويب حرفيًا: رأس bg-muted/40 h-10 text-xs font-semibold muted،
/// صفوف بحد سفلي border/70 وخلايا px-3 py-2.5 — داخل تمرير أفقي بعرض أدنى.
class WebTable extends StatelessWidget {
  final List<String> headers;
  final List<List<Widget>> rows;
  final double minWidth;
  const WebTable({super.key, required this.headers, required this.rows, this.minWidth = 720});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = theme.dividerColor;
    Widget table = Table(
      columnWidths: <int, TableColumnWidth>{
        for (int i = 0; i < headers.length; i++) i: const FlexColumnWidth(),
      },
      border: TableBorder(horizontalInside: BorderSide(color: border.withOpacity(0.7))),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: <TableRow>[
        TableRow(
          decoration: BoxDecoration(color: theme.colorScheme.onSurface.withOpacity(0.03)),
          children: <Widget>[
            for (final h in headers)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text(
                  h,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface.withOpacity(0.55)),
                ),
              ),
          ],
        ),
        for (final row in rows)
          TableRow(
            children: <Widget>[
              for (final cell in row)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: DefaultTextStyle(
                    style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
                    child: cell,
                  ),
                ),
            ],
          ),
      ],
    );
    if (minWidth > 0) {
      table = SizedBox(width: minWidth, child: table);
    }
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: table);
  }
}

/// عدّاد كمية POS: flex h-10 rounded-lg border بين زرّي − و +
class QtyStepper extends StatelessWidget {
  final int value;
  final VoidCallback onDec;
  final VoidCallback onInc;
  const QtyStepper({super.key, required this.value, required this.onDec, required this.onInc});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 40,
      decoration: BoxDecoration(
        borderRadius: AppRadius.br,
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.v),
            onTap: onDec,
            child: SizedBox(
              width: 34,
              child: Icon(Icons.remove, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.55)),
            ),
          ),
          Expanded(
            child: Text('$value', textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.v),
            onTap: onInc,
            child: SizedBox(
              width: 34,
              child: Icon(Icons.add, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.55)),
            ),
          ),
        ],
      ),
    );
  }
}

class PaginationRow extends StatelessWidget {
  final int total;
  final int limit;
  final int offset;
  final ValueChanged<int> onOffset;
  const PaginationRow({super.key, required this.total, required this.limit, required this.offset, required this.onOffset});

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final canPrev = offset > 0;
    final canNext = offset + limit < total;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        OutlinedButton(
          onPressed: canPrev ? () => onOffset(offset - limit) : null,
          child: Text(i18n.t('common', 'previous')),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(i18n.t('common', 'page_of', {'total': Fmt.number(total)}),
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.6))),
        ),
        OutlinedButton(
          onPressed: canNext ? () => onOffset(offset + limit) : null,
          child: Text(i18n.t('common', 'next')),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- الرسم البياني

/// رسم أعمدة مبسّط — نسخة Flutter من components/reports/bar-chart.tsx:
/// صف رأس (chart_max + سطر الملخص)، قيم سالبة تُقص إلى صفر، أعمدة صفرية
/// باهتة (bg-muted بحد أدنى 2px) بدل لون الهوية، تسميات كل ~8 أعمدة
/// (index % labelStep == 0 أو الأخير)، والرسم لا يُخفى أبدًا عندما تكون
/// القيم كلها ≤ 0 — تُعرض أصفارًا باهتة (سلوك الويب bar-chart.tsx:61-76).
class MiniBarChart extends StatelessWidget {
  final List<({String label, int value})> points;
  final String tooltipSuffix;
  final Color? barColor;
  final String? summary; // سطر الملخص أعلى الرسم (chart_summary_days مثلًا)
  final double height;
  const MiniBarChart({
    super.key,
    required this.points,
    this.tooltipSuffix = '',
    this.barColor,
    this.summary,
    this.height = 180,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    final i18n = AppI18n.instance;
    final theme = Theme.of(context);
    final color = barColor ??
        (theme.brightness == Brightness.dark ? AppColors.darkPrimary : AppColors.lightPrimary);
    final mutedBar = theme.colorScheme.onSurface.withOpacity(0.12); // bg-muted
    // أقصى قيمة بعد قصّ السوالب إلى صفر — الصفر لا يُخفي الرسم أبدًا
    var maxV = 0;
    for (final p in points) {
      if (p.value > maxV) maxV = p.value;
    }
    // كل كم عمود نُظهر تسمية حتى لا تزدحم المحور (الهدف ≈ 8 تسميات)
    final labelStep = (points.length / 8).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // صف الرأس: chart_max يمينًا وsummary يسارًا (bar-chart.tsx:49-52)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  i18n.t('reports', 'chart_max', {'value': Fmt.number(maxV)}),
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                ),
              ),
              if (summary != null && summary!.isNotEmpty)
                Text(
                  summary!,
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                ),
            ],
          ),
        ),
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (int i = 0; i < points.length; i++)
                Expanded(
                  child: Tooltip(
                    message: '${points[i].label}: ${Fmt.money(points[i].value, locale: i18n.locale)}$tooltipSuffix',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: _bar(points[i].value, maxV, color, mutedBar),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // صف التسميات: index % labelStep == 0 أو العمود الأخير فقط
        Row(
          children: <Widget>[
            for (int i = 0; i < points.length; i++)
              Expanded(
                child: Text(
                  (i % labelStep == 0 || i == points.length - 1) ? points[i].label : '',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.45)),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// عمود واحد: القيم السالبة تُقص إلى صفر، والصفر عمود باهت بارتفاع 2px.
  Widget _bar(int rawValue, int maxV, Color color, Color mutedBar) {
    final v = rawValue < 0 ? 0 : rawValue;
    if (v <= 0 || maxV <= 0) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 40), // max-w-[40px]
        child: Container(
          height: 2, // min-h-[2px]
          width: double.infinity,
          decoration: BoxDecoration(
            color: mutedBar,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ),
      );
    }
    final ratio = v / maxV;
    // min-h-[3px] للويب — أدنى عامل ارتفاع يعادل 3px من ارتفاع الرسم
    final factor = (ratio * height) < 3 ? 3 / height : ratio;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 40), // max-w-[40px]
      child: FractionallySizedBox(
        heightFactor: factor.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: color.withOpacity(0.85),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ),
      ),
    );
  }
}

/// اختيار بين خيارين (نقدي/آجل، إضافة/خصم) — كبوتَي الويب: المحدد مصمت
/// (primary أو destructive) والآخر outline
class PayChoice extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool destructive;
  const PayChoice({super.key, required this.label, required this.icon, required this.selected, required this.onTap, this.destructive = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onAccent = theme.colorScheme.onPrimary;
    return WButton(
      label,
      onPressed: onTap,
      icon: icon,
      variant: selected ? (destructive ? WButtonVariant.destructive : WButtonVariant.primary) : WButtonVariant.outline,
      color: selected ? onAccent : (destructive ? theme.colorScheme.error : null),
    );
  }
}


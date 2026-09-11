import 'package:flutter/material.dart';

/// Task 62 — الهوية البصرية للموبايل = نسخة طبق الأصل من globals.css
/// في تطبيق الويب (oklch حُوّلت إلى hex بدقة رياضية).
/// light: background #F8FBF9, primary #008D4D, border #DCE3DF …
/// dark:  background #040705, primary #00B56D …
class AppColors {
  AppColors._();

  // ---- Light (من :root في globals.css) ----
  static const lightBackground = Color(0xFFF8FBF9);
  static const lightForeground = Color(0xFF070B09);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightPrimary = Color(0xFF008D4D);
  static const lightPrimaryFg = Color(0xFFFAFAFA);
  static const lightSecondary = Color(0xFFECF4EF);
  static const lightSecondaryFg = Color(0xFF131916);
  static const lightMuted = Color(0xFFF0F3F1);
  static const lightMutedFg = Color(0xFF646B67);
  static const lightAccent = Color(0xFFECF4EF);
  static const lightAccentFg = Color(0xFF131916);
  static const lightDestructive = Color(0xFFDF202E);
  static const lightDestructiveFg = Color(0xFFFAFAFA);
  static const lightBorder = Color(0xFFDCE3DF);
  static const lightRing = Color(0xFF008D4D);

  // ---- Dark (من .dark في globals.css) ----
  static const darkBackground = Color(0xFF040705);
  static const darkForeground = Color(0xFFFAFAFA);
  static const darkCard = Color(0xFF0B110E);
  static const darkPrimary = Color(0xFF00B56D);
  static const darkPrimaryFg = Color(0xFF040705);
  static const darkSecondary = Color(0xFF121A16);
  static const darkMuted = Color(0xFF121A16);
  static const darkMutedFg = Color(0xFF939A96);
  static const darkAccent = Color(0xFF131D18);
  static const darkDestructive = Color(0xFFF14D4C);
  static const darkBorder = Color(0x1CFFFFFF); // oklch(1 0 0 / 11%)

  // ---- نغمات بطاقات الإحصائيات (صفحة اللوحة في الويب) ----
  // warning = amber-600 على amber-500/10 ، success = emerald-600 ، info = blue-600
  static const warningFg = Color(0xFFD97706);
  static const warningBg = Color(0x1AF59E0B);
  static const successFg = Color(0xFF059669);
  static const successBg = Color(0x1A10B981);
  static const infoFg = Color(0xFF2563EB);
  static const infoBg = Color(0x1A2563EB);

  // نظائر الوضع الداكن: amber-400 / emerald-400 / blue-400 بنفس الشفافيات
  static const warningFgDark = Color(0xFFFBBF24);
  static const successFgDark = Color(0xFF34D399);
  static const infoFgDark = Color(0xFF60A5FA);

  // ---- تدرّج زر gradient في الويب: from-primary to-[oklch(0.7_0.15_180)] ----
  static const gradientEnd = Color(0xFF00BCA2);

  // ---- دوائر الخلفية الضبابية في شاشات الدخول/التسجيل ----
  static const blobPrimary = Color(0x1A008D4D); // bg-primary/10
  static const blobEmerald = Color(0x1A34D399); // bg-emerald-400/10

  // ---- شعار العلامة (من SVGs) ----
  static const brandGreen = Color(0xFF00D084);
  static const brandBars = Color(0xFF06100D);
  static const brandTextLight = Color(0xFF10201A);
  static const brandTextDark = Color(0xFFF4FFF8);
  static const brandOsLight = Color(0xFF00A86B);
}

/// نصف قطر الحواف — مقياس Tailwind حرفيًا:
/// --radius = 10px ⇒ sm=6 md=8 lg=10 xl=14 و 2xl=16 3xl=24 قيم افتراضية
class AppRadius {
  AppRadius._();
  static const double v = 10; // rounded-lg (أزرار/حقول/عناصر القائمة)
  static const double sm = 6; // rounded-sm
  static const double md = 8; // rounded-md
  static const double xl = 14; // rounded-xl (البطاقات)
  static const double xxl = 16; // rounded-2xl
  static const double xxxl = 24; // rounded-3xl (بطاقات الدخول/المعالج)
  static final BorderRadius br = BorderRadius.circular(v);
  static final BorderRadius brSm = BorderRadius.circular(sm);
  static final BorderRadius brMd = BorderRadius.circular(md);
  static final BorderRadius brXl = BorderRadius.circular(xl);
  static final BorderRadius br2xl = BorderRadius.circular(xxl);
  static final BorderRadius br3xl = BorderRadius.circular(xxl + 8);
}

/// ظلال Tailwind المضمنة (shadow-sm/md/lg/2xl) بنفس قيم box-shadow
class WebShadow {
  WebShadow._();
  static const List<BoxShadow> sm = <BoxShadow>[
    BoxShadow(offset: Offset(0, 1), blurRadius: 2, color: Color(0x0D000000)),
  ];
  static const List<BoxShadow> md = <BoxShadow>[
    BoxShadow(offset: Offset(0, 4), blurRadius: 6, color: Color(0x1A000000)),
    BoxShadow(offset: Offset(0, 2), blurRadius: 4, color: Color(0x1A000000)),
  ];
  static const List<BoxShadow> lg = <BoxShadow>[
    BoxShadow(offset: Offset(0, 10), blurRadius: 15, color: Color(0x1A000000)),
    BoxShadow(offset: Offset(0, 4), blurRadius: 6, color: Color(0x1A000000)),
  ];
  static const List<BoxShadow> xl2 = <BoxShadow>[
    BoxShadow(offset: Offset(0, 25), blurRadius: 50, color: Color(0x40000000)),
  ];

  /// shadow-lg + لون الهوية: أزرار الدخول والمعالج (shadow-lg shadow-primary/20)
  static List<BoxShadow> primaryGlow(Color primary, {double alpha = 0.20}) => <BoxShadow>[
        BoxShadow(offset: const Offset(0, 10), blurRadius: 15, color: primary.withOpacity(alpha)),
        BoxShadow(offset: const Offset(0, 4), blurRadius: 6, color: primary.withOpacity(alpha * 0.6)),
      ];

  /// ظل دائرة النجاح في نهاية المعالج (shadow-xl shadow-primary/30)
  static List<BoxShadow> primaryGlowXl(Color primary) => <BoxShadow>[
        BoxShadow(offset: const Offset(0, 20), blurRadius: 25, color: primary.withOpacity(0.30)),
      ];
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(
        background: AppColors.lightBackground,
        foreground: AppColors.lightForeground,
        card: AppColors.lightCard,
        primary: AppColors.lightPrimary,
        onPrimary: AppColors.lightPrimaryFg,
        secondary: AppColors.lightSecondary,
        onSecondary: AppColors.lightSecondaryFg,
        muted: AppColors.lightMuted,
        mutedFg: AppColors.lightMutedFg,
        accent: AppColors.lightAccent,
        destructive: AppColors.lightDestructive,
        onDestructive: AppColors.lightDestructiveFg,
        border: AppColors.lightBorder,
      );

  static ThemeData dark() => _build(
        background: AppColors.darkBackground,
        foreground: AppColors.darkForeground,
        card: AppColors.darkCard,
        primary: AppColors.darkPrimary,
        onPrimary: AppColors.darkPrimaryFg,
        secondary: AppColors.darkSecondary,
        onSecondary: AppColors.darkForeground,
        muted: AppColors.darkMuted,
        mutedFg: AppColors.darkMutedFg,
        accent: AppColors.darkAccent,
        destructive: AppColors.darkDestructive,
        onDestructive: AppColors.darkForeground,
        border: AppColors.darkBorder,
      );

  static ThemeData _build({
    required Color background,
    required Color foreground,
    required Color card,
    required Color primary,
    required Color onPrimary,
    required Color secondary,
    required Color onSecondary,
    required Color muted,
    required Color mutedFg,
    required Color accent,
    required Color destructive,
    required Color onDestructive,
    required Color border,
  }) {
    final dark = background.computeLuminance() < 0.5;
    final base = ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme(
        brightness: dark ? Brightness.dark : Brightness.light,
        primary: primary,
        onPrimary: onPrimary,
        secondary: secondary,
        onSecondary: onSecondary,
        surface: card,
        onSurface: foreground,
        error: destructive,
        onError: onDestructive,
        outline: border,
        outlineVariant: border,
      ),
      dividerColor: border,
      splashFactory: InkSparkle.splashFactory,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: foreground, displayColor: foreground),
      appBarTheme: AppBarTheme(
        backgroundColor: background.withOpacity(0.80), // bg-background/80
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        toolbarHeight: 64, // h-16
        titleTextStyle: TextStyle(
          color: foreground,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        shape: Border(bottom: BorderSide(color: border)),
      ),
      cardTheme: CardTheme(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.brXl, side: BorderSide(color: border)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: background, // حقول الويب bg-background
        hintStyle: TextStyle(color: mutedFg, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: const BoxConstraints(minHeight: 40), // h-10
        border: OutlineInputBorder(borderRadius: AppRadius.br, borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: AppRadius.br, borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: AppRadius.br, borderSide: BorderSide(color: primary, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: AppRadius.br, borderSide: BorderSide(color: destructive)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: AppRadius.br, borderSide: BorderSide(color: destructive, width: 2)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: const Size(0, 40), // h-10
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.br),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          minimumSize: const Size(0, 40), // h-10
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.br),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: foreground,
        contentTextStyle: TextStyle(color: background),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.br),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.br, side: BorderSide(color: border)), // rounded-lg
        titleTextStyle: TextStyle(color: foreground, fontSize: 18, fontWeight: FontWeight.w700),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        showDragHandle: true,
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) =>
            states.contains(WidgetState.selected) ? onPrimary : null),
        trackColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) =>
            states.contains(WidgetState.selected) ? primary : null),
      ),
      checkboxTheme: CheckboxThemeData(
        side: BorderSide(color: border, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }
}

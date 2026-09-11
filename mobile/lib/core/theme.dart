import 'package:flutter/material.dart';

/// Task 61 — الهوية البصرية للموبايل = نسخة طبق الأصل من globals.css
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
}

/// نصف قطر الحواف الموحد: --radius: 0.625rem = 10px
class AppRadius {
  AppRadius._();
  static const double v = 10;
  static final BorderRadius br = BorderRadius.circular(v);
  static final BorderRadius brSm = BorderRadius.circular(6);
  static final BorderRadius brXl = BorderRadius.circular(14);
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
    final base = ThemeData(
      useMaterial3: true,
      brightness: background.computeLuminance() < 0.5 ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme(
        brightness: background.computeLuminance() < 0.5 ? Brightness.dark : Brightness.light,
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
        backgroundColor: card,
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
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
        shape: RoundedRectangleBorder(borderRadius: AppRadius.br, side: BorderSide(color: border)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        hintStyle: TextStyle(color: mutedFg, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: AppRadius.br, borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: AppRadius.br, borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: AppRadius.br, borderSide: BorderSide(color: primary, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: AppRadius.br, borderSide: BorderSide(color: destructive)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.br),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          minimumSize: const Size(0, 44),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.br),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: card,
        selectedItemColor: primary,
        unselectedItemColor: mutedFg,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 11),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        indicatorColor: primary.withOpacity(0.10),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11, color: foreground)),
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
        shape: RoundedRectangleBorder(borderRadius: AppRadius.brXl, side: BorderSide(color: border)),
        titleTextStyle: TextStyle(color: foreground, fontSize: 16, fontWeight: FontWeight.w700),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        showDragHandle: true,
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
    );
  }
}

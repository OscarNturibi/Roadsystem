import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  // ── Brand ────────────────────────────────────────────────
  static const lime   = Color(0xFF30D158); // richer green
  static const blue   = Color(0xFF0A84FF); // iOS blue, vivid
  static const red    = Color(0xFFFF453A);
  static const amber  = Color(0xFFFFD60A); // bright gold
  static const teal   = Color(0xFF5AC8FA);
  static const purple = Color(0xFFBF5AF2);
  static const orange = Color(0xFFFF9F0A);
  static const indigo = Color(0xFF5E5CE6);

  // ── Light surfaces ───────────────────────────────────────
  static const lightBg       = Color(0xFFF2F2F7);
  static const lightSurface  = Color(0xFFFFFFFF);
  static const lightSurface2 = Color(0xFFF2F2F7);
  static const lightSurface3 = Color(0xFFE5E5EA);
  static const lightBorder   = Color(0x1E3C3C43);
  static const lightSep      = Color(0x173C3C43);
  static const lightText     = Color(0xFF1C1C1E);
  static const lightText2    = Color(0xFF3A3A3C);
  static const lightMuted    = Color(0xFF8E8E93);

  // ── Dark surfaces — deep charcoal, not pure black ────────
  static const darkBg        = Color(0xFF0D0D0F); // warmer than #000
  static const darkBg2       = Color(0xFF131316);
  static const darkSurface   = Color(0xFF1C1C1F);
  static const darkSurface2  = Color(0xFF242428);
  static const darkSurface3  = Color(0xFF2C2C30);
  static const darkBorder    = Color(0x22FFFFFF);
  static const darkBorderHi  = Color(0x40FFFFFF);
  static const darkSep       = Color(0x0FFFFFFF);
  static const darkText      = Color(0xFFF5F5F7);
  static const darkText2     = Color(0xFFD1D1D6);
  static const darkMuted     = Color(0xFF86868B);

  // ── Glow colours (for shadows/borders on dark) ───────────
  static Color limeGlow   = lime.withValues(alpha: 0.28);
  static Color blueGlow   = blue.withValues(alpha: 0.28);
  static Color redGlow    = red.withValues(alpha: 0.28);
  static Color amberGlow  = amber.withValues(alpha: 0.22);
}

class AppTheme {
  static ThemeData light() => ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.lightBg,
    colorScheme: const ColorScheme.light(
      primary:   AppColors.blue,
      secondary: AppColors.lime,
      surface:   AppColors.lightSurface,
      error:     AppColors.red,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.lightBg,
      foregroundColor: AppColors.lightText,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.blue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        elevation: 0,
      ),
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w800,
          color: AppColors.lightText, letterSpacing: -0.5),
      titleLarge:   TextStyle(fontSize: 17, fontWeight: FontWeight.w600,
          color: AppColors.lightText),
      bodyMedium:   TextStyle(fontSize: 15, color: AppColors.lightText),
      bodySmall:    TextStyle(fontSize: 12, color: AppColors.lightMuted),
    ),
  );

  static ThemeData dark() => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.darkBg,
    colorScheme: const ColorScheme.dark(
      primary:   AppColors.blue,
      secondary: AppColors.lime,
      surface:   AppColors.darkSurface,
      error:     AppColors.red,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkBg,
      foregroundColor: AppColors.darkText,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.blue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        elevation: 0,
      ),
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w800,
          color: AppColors.darkText, letterSpacing: -0.5),
      titleLarge:   TextStyle(fontSize: 17, fontWeight: FontWeight.w600,
          color: AppColors.darkText),
      bodyMedium:   TextStyle(fontSize: 15, color: AppColors.darkText),
      bodySmall:    TextStyle(fontSize: 12, color: AppColors.darkMuted),
    ),
  );
}

extension ThemeX on BuildContext {
  bool   get isDark    => Theme.of(this).brightness == Brightness.dark;
  Color  get bg        => isDark ? AppColors.darkBg       : AppColors.lightBg;
  Color  get bg2       => isDark ? AppColors.darkBg2      : AppColors.lightBg;
  Color  get surface   => isDark ? AppColors.darkSurface  : AppColors.lightSurface;
  Color  get surface2  => isDark ? AppColors.darkSurface2 : AppColors.lightSurface2;
  Color  get surface3  => isDark ? AppColors.darkSurface3 : AppColors.lightSurface3;
  Color  get border    => isDark ? AppColors.darkBorder   : AppColors.lightBorder;
  Color  get borderHi  => isDark ? AppColors.darkBorderHi : AppColors.lightBorder;
  Color  get sep       => isDark ? AppColors.darkSep      : AppColors.lightSep;
  Color  get text      => isDark ? AppColors.darkText     : AppColors.lightText;
  Color  get text2     => isDark ? AppColors.darkText2    : AppColors.lightText2;
  Color  get muted     => isDark ? AppColors.darkMuted    : AppColors.lightMuted;
}

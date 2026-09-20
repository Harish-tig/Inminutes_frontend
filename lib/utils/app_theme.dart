import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The only place colours, radii, spacing and text styles are defined.
///
/// Visual direction: deep violet brand surfaces with a lime accent used only
/// on top of violet, light neutral page background, rounded tinted cards, and
/// bold italic uppercase headings. Out-of-stock items go grey.
class AppTheme {
  // Brand
  static const Color violet = Color(0xFF4F1BD1); // primary
  static const Color violetDeep = Color(0xFF35109A); // header/pressed
  static const Color violetSoft = Color(0xFFF0EBFF); // tinted card surface
  static const Color lime = Color(0xFFD4FF3F); // accent — only on violet
  static const Color violetTint = Color(0xFFDFD3FF); // card thumbnail area
  static const Color onVioletMuted = Color(0xFFCFC2FF); // secondary text on violet

  // Neutrals
  static const Color background = Color(0xFFF5F4F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textDark = Color(0xFF14121F);
  static const Color textMuted = Color(0xFF6E6A7C);
  static const Color border = Color(0xFFE8E5F0);

  // States
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFB4690E);
  static const Color danger = Color(0xFFD64545);
  static const Color muted = Color(0xFFDCDCE2); // out-of-stock surface
  static const Color mutedDark = Color(0xFF9A9AA4); // out-of-stock button
  static const Color mutedSurface = Color(0xFFEDEDF1); // out-of-stock card body
  static const Color mutedThumb = Color(0xFFE2E2E7); // out-of-stock thumbnail
  static const Color successSoft = Color(0xFFE6F6EF); // "ready" / "active" chips
  static const Color neutralSoft = Color(0xFFF1F1F4); // neutral chips

  // Shape and spacing
  static const double radius = 18;
  static const double radiusSmall = 12;
  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(16, 12, 16, 16);

  /// Section titles — "MENU", "SHARED CART".
  static const TextStyle sectionHeading = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w900,
    fontStyle: FontStyle.italic,
    letterSpacing: 0.4,
    color: textDark,
  );

  /// Product and item names — bold italic, as in the reference.
  static const TextStyle itemName = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w800,
    fontStyle: FontStyle.italic,
    color: textDark,
  );

  /// The small uppercase line above a name.
  static const TextStyle kicker = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    color: textMuted,
  );

  static const TextStyle buttonLabel = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w900,
    fontStyle: FontStyle.italic,
    letterSpacing: 0.6,
  );

  static ThemeData build() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: violet,
      primary: violet,
      surface: surface,
      error: danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: violet,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
          letterSpacing: 0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: violet,
          foregroundColor: Colors.white,
          disabledBackgroundColor: muted,
          disabledForegroundColor: mutedDark,
          elevation: 0,
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
          textStyle: buttonLabel,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: violet,
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: violet, width: 1.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
          textStyle: buttonLabel.copyWith(fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: violet),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: violet, width: 1.6),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: textDark,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
      ),
      dividerTheme: const DividerThemeData(color: border, space: 1, thickness: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: violet),
      textTheme: const TextTheme(
        titleLarge: sectionHeading,
        titleMedium: TextStyle(color: textDark, fontWeight: FontWeight.w700),
        bodyMedium: TextStyle(color: textDark),
        bodySmall: TextStyle(color: textMuted),
      ),
    );
  }
}

/// The app's visual identity: a warm literary dark theme.
///
/// Design language — "lamplit library": a deep espresso surface, a glowing
/// amber accent (audio + aged paper), a characterful serif (Fraunces) for
/// display text paired with a clean grotesque (Hanken Grotesk) for controls.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralized design tokens so every widget pulls from one palette.
abstract class AppTokens {
  /// Deepest background (page).
  static const Color ink = Color(0xFF17130F);

  /// Raised surface (cards).
  static const Color surface = Color(0xFF211B15);

  /// Higher surface (inputs, hover).
  static const Color surfaceHigh = Color(0xFF2C241C);

  /// Hairline borders.
  static const Color line = Color(0xFF3A3026);

  /// Primary glowing amber accent.
  static const Color amber = Color(0xFFE0A458);

  /// Brighter amber for highlights/gradient tops.
  static const Color amberBright = Color(0xFFF2C078);

  /// Primary cream text.
  static const Color cream = Color(0xFFF3E9DC);

  /// Muted secondary text.
  static const Color muted = Color(0xFF9C8E7C);

  /// Success / done.
  static const Color sage = Color(0xFF8FB996);

  /// Error.
  static const Color rust = Color(0xFFD08770);

  /// Standard corner radius.
  static const double radius = 16;

  /// Standard outer padding.
  static const double pad = 20;
}

/// Builds the [ThemeData] for the app.
ThemeData buildAppTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final scheme = const ColorScheme.dark(
    primary: AppTokens.amber,
    onPrimary: AppTokens.ink,
    secondary: AppTokens.amberBright,
    surface: AppTokens.surface,
    onSurface: AppTokens.cream,
    error: AppTokens.rust,
  );

  final display = GoogleFonts.fraunces(
    color: AppTokens.cream,
    fontWeight: FontWeight.w600,
  );
  final body = GoogleFonts.hankenGrotesk(color: AppTokens.cream);

  return base.copyWith(
    scaffoldBackgroundColor: AppTokens.ink,
    colorScheme: scheme,
    textTheme: base.textTheme
        .copyWith(
          displaySmall: display.copyWith(fontSize: 34, letterSpacing: -0.5),
          headlineSmall: display.copyWith(fontSize: 22),
          titleLarge: display.copyWith(fontSize: 18),
          titleMedium: body.copyWith(fontWeight: FontWeight.w600),
          bodyMedium: body.copyWith(color: AppTokens.cream, height: 1.45),
          bodySmall: body.copyWith(color: AppTokens.muted, height: 1.4),
          labelLarge: body.copyWith(fontWeight: FontWeight.w600),
        )
        .apply(bodyColor: AppTokens.cream, displayColor: AppTokens.cream),
    cardTheme: CardThemeData(
      color: AppTokens.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radius),
        side: const BorderSide(color: AppTokens.line),
      ),
    ),
    dividerColor: AppTokens.line,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppTokens.amber,
        foregroundColor: AppTokens.ink,
        textStyle: body.copyWith(fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppTokens.surfaceHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTokens.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTokens.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTokens.amber, width: 1.5),
      ),
    ),
  );
}

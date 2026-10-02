import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/models/app_settings.dart';
import 'constellation_colors.dart';

/// Rayons très arrondis, partagés par tous les composants.
abstract final class AppRadii {
  static const double sm = 14;
  static const double md = 22;
  static const double lg = 32;
  static const double pill = 999;
}

/// Durées et courbes des micro-animations.
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration medium = Duration(milliseconds: 320);
  static const Duration slow = Duration(milliseconds: 600);

  /// Léger rebond pour les apparitions.
  static const Curve bounce = Curves.easeOutBack;
  static const Curve standard = Curves.easeOutCubic;
}

/// Construction des [ThemeData] clair et sombre.
abstract final class AppTheme {
  /// Désactivable dans les tests (google_fonts tente sinon un accès réseau).
  static bool useGoogleFonts = true;

  static ThemeData dark(AccentChoice accent) =>
      _build(Brightness.dark, ConstellationColors.dark(accent));

  static ThemeData light(AccentChoice accent) =>
      _build(Brightness.light, ConstellationColors.light(accent));

  static ThemeData _build(Brightness brightness, ConstellationColors c) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.onAccent,
      secondary: c.accent,
      onSecondary: c.onAccent,
      error: c.danger,
      onError: c.onAccent,
      surface: c.background,
      onSurface: c.textPrimary,
      surfaceContainerHighest: c.backgroundElevated,
      onSurfaceVariant: c.textSecondary,
      outline: c.glassBorder,
    );

    final textTheme = _textTheme(brightness, c);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      textTheme: textTheme,
      extensions: [c],
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: c.textPrimary,
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          minimumSize: const Size(64, 56),
          padding: const EdgeInsets.symmetric(horizontal: 28),
          shape: const StadiumBorder(),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.textSecondary,
          shape: const StadiumBorder(),
          textStyle: textTheme.labelLarge,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        modalBackgroundColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.backgroundElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.backgroundElevated,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Space Grotesk (géométrique) pour les titres, Manrope pour le texte courant.
  static TextTheme _textTheme(Brightness brightness, ConstellationColors c) {
    final base =
        (brightness == Brightness.dark
                ? ThemeData.dark().textTheme
                : ThemeData.light().textTheme)
            .apply(bodyColor: c.textPrimary, displayColor: c.textPrimary);

    TextStyle display(TextStyle? s) => useGoogleFonts
        ? GoogleFonts.spaceGrotesk(textStyle: s)
        : (s ?? const TextStyle());
    TextStyle body(TextStyle? s) => useGoogleFonts
        ? GoogleFonts.manrope(textStyle: s)
        : (s ?? const TextStyle());

    return base.copyWith(
      displayLarge: display(
        base.displayLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -1.5,
        ),
      ),
      displayMedium: display(
        base.displayMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -1,
        ),
      ),
      displaySmall: display(
        base.displaySmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
      ),
      headlineLarge: display(
        base.headlineLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      headlineMedium: display(
        base.headlineMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
      ),
      headlineSmall: display(
        base.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      titleLarge: display(
        base.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      titleMedium: display(
        base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      titleSmall: display(base.titleSmall),
      bodyLarge: body(base.bodyLarge?.copyWith(height: 1.5)),
      bodyMedium: body(
        base.bodyMedium?.copyWith(height: 1.5, color: c.textSecondary),
      ),
      bodySmall: body(base.bodySmall?.copyWith(color: c.textSecondary)),
      labelLarge: display(
        base.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 16,
          letterSpacing: 0.2,
        ),
      ),
      labelMedium: body(
        base.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
      labelSmall: body(
        base.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
          color: c.textSecondary,
        ),
      ),
    );
  }
}

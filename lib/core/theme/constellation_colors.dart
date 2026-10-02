import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../domain/models/app_settings.dart';

/// Jetons de couleur du thème « Constellation ».
///
/// Exposés via une [ThemeExtension] pour être accessibles partout avec
/// `context.colors`, y compris dans les CustomPainter (scène 3D, étoiles).
@immutable
class ConstellationColors extends ThemeExtension<ConstellationColors> {
  const ConstellationColors({
    required this.background,
    required this.backgroundElevated,
    required this.glass,
    required this.glassBorder,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.star,
    required this.starDim,
    required this.constellationLine,
    required this.textPrimary,
    required this.textSecondary,
    required this.warning,
    required this.danger,
    required this.glassBlur,
  });

  /// Fond principal de l'app (#07080C en sombre).
  final Color background;

  /// Fond légèrement relevé (cartes, feuilles).
  final Color backgroundElevated;

  /// Remplissage des panneaux en verre dépoli.
  final Color glass;

  /// Liseré fin des panneaux en verre.
  final Color glassBorder;

  /// Couleur d'accent lumineuse (cyan électrique ou ambre).
  final Color accent;

  /// Accent atténué : halos, arrière-plans de boutons secondaires.
  final Color accentSoft;

  /// Texte / icônes posés sur l'accent.
  final Color onAccent;

  /// Étoiles cibles et étoiles décoratives.
  final Color star;
  final Color starDim;

  /// Lignes reliant les étoiles capturées.
  final Color constellationLine;

  final Color textPrimary;
  final Color textSecondary;

  /// Alertes (téléphone incliné, mouvement trop rapide).
  final Color warning;
  final Color danger;

  /// Intensité du flou des panneaux en verre (sigma).
  final double glassBlur;

  /// Palette sombre, déclinée selon l'accent choisi.
  factory ConstellationColors.dark(AccentChoice accent) {
    final a = accentColor(accent, Brightness.dark);
    return ConstellationColors(
      background: const Color(0xFF07080C),
      backgroundElevated: const Color(0xFF0F1118),
      glass: const Color(0xFFFFFFFF).withValues(alpha: 0.06),
      glassBorder: const Color(0xFFFFFFFF).withValues(alpha: 0.12),
      accent: a,
      accentSoft: a.withValues(alpha: 0.16),
      onAccent: const Color(0xFF07080C),
      star: const Color(0xFFF2F4FF),
      starDim: const Color(0xFF8A90A8),
      constellationLine: a.withValues(alpha: 0.55),
      textPrimary: const Color(0xFFF2F4FF),
      textSecondary: const Color(0xFF9AA0B8),
      warning: const Color(0xFFFFC857),
      danger: const Color(0xFFFF5C7A),
      glassBlur: 22,
    );
  }

  /// Palette claire : « ciel à l'aube », encre bleu nuit sur fond nacré.
  factory ConstellationColors.light(AccentChoice accent) {
    final a = accentColor(accent, Brightness.light);
    return ConstellationColors(
      background: const Color(0xFFF3F4F8),
      backgroundElevated: const Color(0xFFFFFFFF),
      glass: const Color(0xFFFFFFFF).withValues(alpha: 0.55),
      glassBorder: const Color(0xFF0B0E1A).withValues(alpha: 0.08),
      accent: a,
      accentSoft: a.withValues(alpha: 0.14),
      onAccent: const Color(0xFFFFFFFF),
      star: const Color(0xFF1A1F36),
      starDim: const Color(0xFF9AA0B8),
      constellationLine: a.withValues(alpha: 0.6),
      textPrimary: const Color(0xFF0B0E1A),
      textSecondary: const Color(0xFF5A6078),
      warning: const Color(0xFFC98A00),
      danger: const Color(0xFFD7264A),
      glassBlur: 18,
    );
  }

  /// Teinte d'accent : plus lumineuse en sombre, plus dense en clair pour
  /// garder un contraste suffisant sur fond pâle.
  static Color accentColor(AccentChoice accent, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch (accent) {
      AccentChoice.cyan =>
        dark ? const Color(0xFF2EE6FF) : const Color(0xFF0088A8),
      AccentChoice.amber =>
        dark ? const Color(0xFFFFB547) : const Color(0xFFB86E00),
    };
  }

  @override
  ConstellationColors copyWith({
    Color? background,
    Color? backgroundElevated,
    Color? glass,
    Color? glassBorder,
    Color? accent,
    Color? accentSoft,
    Color? onAccent,
    Color? star,
    Color? starDim,
    Color? constellationLine,
    Color? textPrimary,
    Color? textSecondary,
    Color? warning,
    Color? danger,
    double? glassBlur,
  }) {
    return ConstellationColors(
      background: background ?? this.background,
      backgroundElevated: backgroundElevated ?? this.backgroundElevated,
      glass: glass ?? this.glass,
      glassBorder: glassBorder ?? this.glassBorder,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      onAccent: onAccent ?? this.onAccent,
      star: star ?? this.star,
      starDim: starDim ?? this.starDim,
      constellationLine: constellationLine ?? this.constellationLine,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      glassBlur: glassBlur ?? this.glassBlur,
    );
  }

  /// Interpolation utilisée par Flutter lors des changements de thème :
  /// le passage cyan ↔ ambre ou sombre ↔ clair est ainsi animé.
  @override
  ConstellationColors lerp(ConstellationColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return ConstellationColors(
      background: c(background, other.background),
      backgroundElevated: c(backgroundElevated, other.backgroundElevated),
      glass: c(glass, other.glass),
      glassBorder: c(glassBorder, other.glassBorder),
      accent: c(accent, other.accent),
      accentSoft: c(accentSoft, other.accentSoft),
      onAccent: c(onAccent, other.onAccent),
      star: c(star, other.star),
      starDim: c(starDim, other.starDim),
      constellationLine: c(constellationLine, other.constellationLine),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      warning: c(warning, other.warning),
      danger: c(danger, other.danger),
      glassBlur: lerpDouble(glassBlur, other.glassBlur, t)!,
    );
  }
}

/// Raccourci d'accès aux couleurs : `context.colors.accent`.
extension ConstellationColorsX on BuildContext {
  ConstellationColors get colors =>
      Theme.of(this).extension<ConstellationColors>()!;
}

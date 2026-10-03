/// Couleur d'accent choisie par l'utilisateur pour le thème « Constellation ».
enum AccentChoice {
  /// Cyan électrique (par défaut).
  cyan,

  /// Ambre chaud.
  amber,
}

/// Préférence de luminosité de l'interface.
enum ThemePreference { system, dark, light }

/// Réglages persistants de l'application (modèle du domaine, immuable).
class AppSettings {
  /// `true` une fois l'onboarding terminé ou passé.
  final bool onboardingCompleted;

  final AccentChoice accent;

  final ThemePreference themePreference;

  const AppSettings({
    this.onboardingCompleted = false,
    this.accent = AccentChoice.cyan,
    this.themePreference = ThemePreference.dark,
  });

  AppSettings copyWith({
    bool? onboardingCompleted,
    AccentChoice? accent,
    ThemePreference? themePreference,
  }) {
    return AppSettings(
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      accent: accent ?? this.accent,
      themePreference: themePreference ?? this.themePreference,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.onboardingCompleted == onboardingCompleted &&
      other.accent == accent &&
      other.themePreference == themePreference;

  @override
  int get hashCode => Object.hash(onboardingCompleted, accent, themePreference);
}

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';

/// Implémentation de [SettingsRepository] basée sur SharedPreferences.
class PrefsSettingsRepository implements SettingsRepository {
  PrefsSettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _kOnboarding = 'settings.onboardingCompleted';
  static const _kAccent = 'settings.accent';
  static const _kTheme = 'settings.themePreference';

  @override
  AppSettings load() {
    return AppSettings(
      onboardingCompleted: _prefs.getBool(_kOnboarding) ?? false,
      accent: _enumByName(
        AccentChoice.values,
        _prefs.getString(_kAccent),
        AccentChoice.cyan,
      ),
      themePreference: _enumByName(
        ThemePreference.values,
        _prefs.getString(_kTheme),
        ThemePreference.dark,
      ),
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    await Future.wait([
      _prefs.setBool(_kOnboarding, settings.onboardingCompleted),
      _prefs.setString(_kAccent, settings.accent.name),
      _prefs.setString(_kTheme, settings.themePreference.name),
    ]);
  }

  /// Retrouve une valeur d'énumération par son nom, avec repli si la valeur
  /// stockée est absente ou obsolète (renommage entre deux versions).
  static T _enumByName<T extends Enum>(
    List<T> values,
    String? name,
    T fallback,
  ) {
    if (name == null) return fallback;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }
}

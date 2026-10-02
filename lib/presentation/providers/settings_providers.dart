import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repositories/prefs_settings_repository.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';

/// Instance de SharedPreferences, injectée dans `main()` via un override
/// (elle doit être chargée de façon asynchrone avant le premier frame).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider non injecté'),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => PrefsSettingsRepository(ref.watch(sharedPreferencesProvider)),
);

/// Contrôleur des réglages : expose l'état courant et persiste chaque
/// modification.
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(settingsRepositoryProvider).load();

  Future<void> _update(AppSettings next) async {
    if (next == state) return;
    state = next;
    await ref.read(settingsRepositoryProvider).save(next);
  }

  Future<void> completeOnboarding() =>
      _update(state.copyWith(onboardingCompleted: true));

  /// Permet de revoir l'onboarding depuis les réglages.
  Future<void> resetOnboarding() =>
      _update(state.copyWith(onboardingCompleted: false));

  Future<void> setAccent(AccentChoice accent) =>
      _update(state.copyWith(accent: accent));

  Future<void> setThemePreference(ThemePreference pref) =>
      _update(state.copyWith(themePreference: pref));
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// Conversion de la préférence du domaine vers le [ThemeMode] Flutter.
final themeModeProvider = Provider<ThemeMode>((ref) {
  final pref = ref.watch(
    settingsControllerProvider.select((s) => s.themePreference),
  );
  return switch (pref) {
    ThemePreference.system => ThemeMode.system,
    ThemePreference.dark => ThemeMode.dark,
    ThemePreference.light => ThemeMode.light,
  };
});

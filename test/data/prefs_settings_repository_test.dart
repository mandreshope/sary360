import 'package:flutter_test/flutter_test.dart';
import 'package:sary360/data/repositories/prefs_settings_repository.dart';
import 'package:sary360/domain/models/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PrefsSettingsRepository', () {
    test('renvoie les valeurs par défaut quand rien n\'est stocké', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = PrefsSettingsRepository(
        await SharedPreferences.getInstance(),
      );

      expect(repo.load(), const AppSettings());
    });

    test('persiste puis relit les réglages', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      const saved = AppSettings(
        onboardingCompleted: true,
        accent: AccentChoice.amber,
        themePreference: ThemePreference.light,
      );

      await PrefsSettingsRepository(prefs).save(saved);

      expect(PrefsSettingsRepository(prefs).load(), saved);
    });

    test('ignore une valeur d\'énumération inconnue', () async {
      SharedPreferences.setMockInitialValues({
        'settings.accent': 'violet',
        'settings.themePreference': 'sepia',
      });
      final repo = PrefsSettingsRepository(
        await SharedPreferences.getInstance(),
      );

      expect(repo.load().accent, AccentChoice.cyan);
      expect(repo.load().themePreference, ThemePreference.dark);
    });
  });
}

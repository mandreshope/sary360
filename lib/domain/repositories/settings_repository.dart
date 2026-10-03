import '../models/app_settings.dart';

/// Contrat de persistance des réglages.
///
/// Le domaine ne connaît que cette interface : l'implémentation concrète
/// (SharedPreferences) vit dans la couche `data`.
abstract interface class SettingsRepository {
  /// Lecture synchrone : les réglages sont chargés au démarrage de l'app.
  AppSettings load();

  Future<void> save(AppSettings settings);
}

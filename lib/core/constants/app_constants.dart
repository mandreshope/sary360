/// Constants pour l'application Sary360 - Capture sphérique 360°
class AppConstants {
  // ── Capture sphérique settings ──
  /// Nombre de rangées verticales (haut, milieu, bas)
  static const int numberOfRows = 3;

  /// Angles d'élévation pour chaque rangée (en degrés)
  /// -60° = vers le haut, 0° = horizontal, +60° = vers le bas
  static const List<double> rowElevations = [-50.0, 0.0, 50.0];

  /// Nombre de photos par rangée
  static const List<int> photosPerRow = [8, 12, 8];

  /// Nombre total de photos
  static int get totalPhotos =>
      photosPerRow.fold(0, (sum, count) => sum + count);

  /// Tolérance angulaire pour valider la position (en degrés)
  static const double angleTolerance = 12.0;

  /// Tolérance d'élévation pour valider la rangée (en degrés)
  static const double elevationTolerance = 15.0;

  // ── Image processing ──
  static const int maxImageWidth = 1920;
  static const int maxImageHeight = 1080;
  static const int jpegQuality = 85;

  // ── Equirectangular output ──
  /// Largeur de l'image équirectangulaire finale
  static const int equirectWidth = 4096;

  /// Hauteur = largeur / 2 pour une projection équirectangulaire
  static const int equirectHeight = 2048;

  // ── Camera settings ──
  static const double defaultExposure = 0.0;
  static const double defaultZoom = 1.0;

  // ── Storage ──
  static const String panoramasFolder = 'panoramas';
  static const String tempFolder = 'temp';

  // ── UI ──
  static const String appName = 'Sary360';
  static const String appVersion = '1.0.0';
}

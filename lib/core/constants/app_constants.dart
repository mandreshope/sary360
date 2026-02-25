/// Constants pour l'application Sary360 - Capture sphérique 360°
/// Inspiré de Google Street View : couverture complète de la sphère
class AppConstants {
  // ── Capture sphérique settings ──
  /// Nombre de rangées verticales (du zénith au nadir)
  /// 5 rangées : zénith, haute, horizon, basse, nadir
  static const int numberOfRows = 5;

  /// Angles d'élévation pour chaque rangée (en degrés)
  /// Couverture complète de -90° (nadir) à +90° (zénith)
  /// Convention: positif = vers le haut, négatif = vers le bas
  static const List<double> rowElevations = [
    75.0, // Zénith (presque tout en haut)
    35.0, // Haute
    0.0, // Horizon
    -35.0, // Basse
    -75.0, // Nadir (presque tout en bas)
  ];

  /// Nombre de photos par rangée
  /// Augmenté considérablement pour assurer un énorme chevauchement (Overlap > 40%)
  /// C'est indispensable pour que le mode PANORAMA d'OpenCV réussisse
  /// l'ajustement des paramètres (évite ERR_CAMERA_PARAMS_ADJUST_FAIL).
  static const List<int> photosPerRow = [
    5, // Zénith (75°)
    10, // Haute (35°)
    12, // Horizon (0°)
    10, // Basse (-35°)
    5, // Nadir (-75°)
  ];

  /// Nombre total de photos
  static int get totalPhotos =>
      photosPerRow.fold(0, (sum, count) => sum + count);

  /// Tolérance angulaire pour valider la position (en degrés)
  /// Réduction pour garantir un alignement presque millimétrique
  static const double angleTolerance = 12.0;

  /// Tolérance d'élévation pour valider la rangée (en degrés)
  static const double elevationTolerance = 12.0;

  // ── Image processing ──
  static const int maxImageWidth = 1920;
  static const int maxImageHeight = 1080;
  static const int jpegQuality = 90;

  // ── Equirectangular output ──
  /// Largeur de l'image équirectangulaire finale
  static const int equirectWidth = 4096;

  /// Hauteur = largeur / 2 pour une projection équirectangulaire
  static const int equirectHeight = 2048;

  // ── Camera settings ──
  /// FOV horizontal estimé de la caméra (en degrés)
  /// Standard ~28mm eq (65°) pour éviter l'étirement
  static const double cameraHFov = 65.0;

  /// FOV vertical estimé de la caméra (en degrés)
  /// Standard 4:3 (48°)
  static const double cameraVFov = 48.0;

  static const double defaultExposure = 0.0;
  static const double defaultZoom = 1.0;

  // ── Storage ──
  static const String panoramasFolder = 'panoramas';
  static const String tempFolder = 'temp';

  // ── UI ──
  static const String appName = 'Sary360';
  static const String appVersion = '1.0.0';

  /// Noms des rangées pour l'affichage
  static const List<String> rowNames = [
    'Zénith ↑',
    'Haute ↗',
    'Horizon →',
    'Basse ↘',
    'Nadir ↓',
  ];
}

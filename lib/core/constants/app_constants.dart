/// Constants pour l'application Sary360 - Capture sphérique 360°
/// Inspiré de Google Street View : couverture complète de la sphère
class AppConstants {
  // ── Capture sphérique settings ──
  /// Nombre de rangées verticales (du zénith au nadir)
  /// 5 rangées : zénith, haute, horizon, basse, nadir
  static const int numberOfRows = 5;

  /// Grille de capture adaptée à l'objectif utilisé (voir [CaptureGrid]).
  /// L'ordre des rangées est toujours : zénith, haute, horizon, basse, nadir.
  static CaptureGrid grid({required bool wideAngle}) =>
      wideAngle ? CaptureGrid.wide : CaptureGrid.standard;

  /// Champ de vision d'une photo ultra grand angle en portrait (degrés).
  /// Pixel 6a : calibration intrinsèque 1888,6 px sur 4032 px (≈ 94° × 62°
  /// en 16:9), mais la correction de distorsion de l'appareil recadre
  /// l'image d'environ 20 % : les focales mesurées par l'assemblage donnent
  /// ≈ 53° × 83° (photo 1080 × 1920). L'assemblage affine de toute façon la
  /// focale à partir des points-clés.
  static const double wideHFov = 53.0;
  static const double wideVFov = 83.0;

  /// Champ de vision de l'objectif principal en portrait 16:9 (degrés).
  /// Pixel 6a : objectif 4,38 mm, capteur 5,64 × 4,23 mm (≈ 65,6° × 51,6°
  /// en 4:3), petit côté recadré à ≈ 40° en 16:9.
  static const double mainHFov = 40.0;
  static const double mainVFov = 65.6;

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

/// Disposition des cibles sur la sphère : élévation et nombre de photos de
/// chaque rangée, calculés pour garder ≥ 30 % de chevauchement entre photos
/// voisines (minimum pour l'alignement OpenCV).
class CaptureGrid {
  const CaptureGrid({required this.rowElevations, required this.photosPerRow});

  /// Élévation de chaque rangée en degrés (positif = vers le haut).
  final List<double> rowElevations;

  /// Nombre de photos dans chaque rangée.
  final List<int> photosPerRow;

  int get totalPhotos => photosPerRow.fold(0, (sum, count) => sum + count);

  /// Objectif principal (portrait 16:9 ≈ 40° × 66°) : 42 photos.
  static const standard = CaptureGrid(
    rowElevations: [75.0, 35.0, 0.0, -35.0, -75.0],
    photosPerRow: [5, 10, 12, 10, 5],
  );

  /// Ultra grand angle (portrait 16:9 ≈ 53° × 83°) : 26 photos.
  /// - Horizon : 10 photos espacées de 36° → ≈ 32 % de chevauchement.
  /// - ±45° : 7 photos espacées de 51°, chaque photo couvrant ≈ 75°
  ///   d'azimut à cette élévation → ≈ 32 % ; leurs 83° de hauteur montent
  ///   jusqu'à ≈ 86°.
  /// - Pôles à ±85° : une photo chacun (au-delà de 80°, le guidage ignore
  ///   l'azimut).
  static const wide = CaptureGrid(
    rowElevations: [85.0, 45.0, 0.0, -45.0, -85.0],
    photosPerRow: [1, 7, 10, 7, 1],
  );
}

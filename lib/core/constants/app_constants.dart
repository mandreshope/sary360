/// Constants pour l'application
class AppConstants {
  // Capture settings
  static const int numberOfPhotos = 6; // 6 photos pour un panorama 360°
  static const double rotationAngle = 60.0; // 360° / 6 = 60° entre chaque photo
  static const double rotationTolerance = 10.0; // Tolérance de ±10°

  // Image processing
  static const int maxImageWidth = 1920; // Largeur max pour performance
  static const int maxImageHeight = 1080; // Hauteur max pour performance
  static const int jpegQuality = 85; // Qualité JPEG (0-100)
  static const int overlapPixels =
      100; // Pixels de chevauchement pour le stitching

  // Camera settings
  static const double defaultExposure = 0.0;
  static const double defaultZoom = 1.0;

  // Storage
  static const String panoramasFolder = 'panoramas';
  static const String tempFolder = 'temp';

  // UI
  static const String appName = 'Sary360';
  static const String appVersion = '1.0.0';

  // Rotation guidance
  static const double minRotationSpeed =
      0.1; // rad/s min pour détecter rotation
  static const double maxRotationSpeed = 2.0; // rad/s max pour rotation fluide
}

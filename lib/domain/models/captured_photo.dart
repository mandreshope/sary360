import '../../core/math/quaternion.dart';

/// Représente une photo capturée pour le panorama sphérique
class CapturedPhoto {
  final String path;

  /// Angle horizontal (azimut) en degrés, 0-360
  final double azimuth;

  /// Angle vertical (élévation) en degrés, -90 à +90
  final double elevation;

  final DateTime capturedAt;

  /// Index de la rangée (0 = haut, 1 = milieu, 2 = bas)
  final int rowIndex;

  /// Index dans la rangée
  final int indexInRow;

  /// Champ de vision horizontal utilisé (null = défaut)
  final double? hFov;

  /// Champ de vision vertical utilisé (null = défaut)
  final double? vFov;

  /// Orientation appareil → monde (Est, Nord, Haut) mesurée au
  /// déclenchement. Point de départ de l'assemblage.
  final Quaternion orientation;

  const CapturedPhoto({
    required this.path,
    required this.azimuth,
    required this.elevation,
    required this.capturedAt,
    required this.rowIndex,
    required this.indexInRow,
    this.hFov,
    this.vFov,
    required this.orientation,
  });

  CapturedPhoto copyWith({
    String? path,
    double? azimuth,
    double? elevation,
    DateTime? capturedAt,
    int? rowIndex,
    int? indexInRow,
    double? hFov,
    double? vFov,
    Quaternion? orientation,
  }) {
    return CapturedPhoto(
      path: path ?? this.path,
      azimuth: azimuth ?? this.azimuth,
      elevation: elevation ?? this.elevation,
      capturedAt: capturedAt ?? this.capturedAt,
      rowIndex: rowIndex ?? this.rowIndex,
      indexInRow: indexInRow ?? this.indexInRow,
      hFov: hFov ?? this.hFov,
      vFov: vFov ?? this.vFov,
      orientation: orientation ?? this.orientation,
    );
  }
}

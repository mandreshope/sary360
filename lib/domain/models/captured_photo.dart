/// Représente une photo capturée pour le panorama
class CapturedPhoto {
  final String path;
  final double rotationAngle; // Angle de rotation au moment de la capture
  final DateTime capturedAt;
  final int index; // Index dans la séquence (0 à n-1)

  const CapturedPhoto({
    required this.path,
    required this.rotationAngle,
    required this.capturedAt,
    required this.index,
  });

  CapturedPhoto copyWith({
    String? path,
    double? rotationAngle,
    DateTime? capturedAt,
    int? index,
  }) {
    return CapturedPhoto(
      path: path ?? this.path,
      rotationAngle: rotationAngle ?? this.rotationAngle,
      capturedAt: capturedAt ?? this.capturedAt,
      index: index ?? this.index,
    );
  }
}

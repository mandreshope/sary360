import '../../core/math/quaternion.dart';

/// Une mesure d'orientation du téléphone.
class OrientationSample {
  const OrientationSample(this.deviceToWorld, this.timestamp);

  /// Rotation repère appareil → monde (x Est, y Nord, z zénith). Avec une
  /// source sans magnétomètre, le « Nord » est arbitraire mais stable : seul
  /// le cap relatif compte pour la capture.
  final Quaternion deviceToWorld;

  /// Horodatage du capteur (secondes, origine arbitraire mais monotone).
  final double timestamp;
}

/// Source d'orientation du téléphone. Implémentations : vecteur de rotation
/// Android (platform channel), capteurs bruts (repli), ARCore à terme.
abstract interface class OrientationSource {
  /// Nom lisible de la source (diagnostic).
  String get name;

  /// Flux d'orientations (≈ 50 Hz). Émet une erreur si aucun capteur adapté.
  Stream<OrientationSample> get samples;
}

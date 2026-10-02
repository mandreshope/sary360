import 'dart:math' as math;

import 'quaternion.dart';

/// Conversions entre les repères utilisés par la capture et l'assemblage.
///
/// - Repère **appareil** (Android) : x à droite de l'écran, y vers le haut
///   de l'écran, z sortant de l'écran (vers l'utilisateur).
/// - Repère **monde** des capteurs (ENU) : x vers l'Est, y vers le Nord,
///   z vers le zénith.
/// - Repère **caméra OpenCV** : x à droite, y vers le bas, z dans l'axe de
///   visée (la caméra arrière regarde vers −z appareil).
/// - Repère **monde OpenCV** de la sphère : x vers l'Est, y vers le bas
///   (nadir), z vers le Nord. Le warper sphérique place z au centre du
///   panorama et y = −1 en haut de l'image.
///
/// Les matrices 3×3 sont des listes de 9 réels, ligne par ligne.
abstract final class CameraRotation {
  /// Orientation appareil → monde (ENU) à partir de la gravité mesurée par
  /// l'accéléromètre (au repos, elle pointe vers le haut) et du champ
  /// magnétique, comme `SensorManager.getRotationMatrix` d'Android.
  ///
  /// Renvoie `null` si les mesures sont dégénérées (capteur à zéro,
  /// champ magnétique parallèle à la gravité).
  static Quaternion? deviceToWorldFromSensors(
    List<double> gravity,
    List<double> magnetic,
  ) {
    final up = _normalize(gravity);
    if (up == null) return null;
    // Est = M × Haut (le champ magnétique pointe vers le Nord et le bas).
    final east = _normalize(_cross(magnetic, up));
    if (east == null) return null;
    final north = _cross(up, east);
    // Lignes de la matrice : coordonnées appareil des axes Est, Nord, Haut.
    return Quaternion.fromRotationMatrix([...east, ...north, ...up]);
  }

  /// Rotation caméra OpenCV → monde OpenCV pour une orientation
  /// appareil → monde (ENU) donnée.
  ///
  /// R = M · D · C, avec C : caméra → appareil = diag(1, −1, −1) et
  /// M : ENU → monde OpenCV (x = Est, y = −Haut, z = Nord).
  static List<double> openCvCameraToWorld(Quaternion deviceToWorld) {
    const c = [1.0, 0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, -1.0];
    const m = [1.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0];
    return multiply(m, multiply(deviceToWorld.toRotationMatrix(), c));
  }

  /// Cap (radians) de l'axe de visée dans le monde OpenCV : 0 au centre du
  /// panorama (Nord), positif vers l'Est.
  static double yawOf(List<double> cameraToWorld) {
    // Axe de visée = 3e colonne.
    return math.atan2(cameraToWorld[2], cameraToWorld[8]);
  }

  /// Fait tourner toutes les rotations autour de la verticale pour que la
  /// caméra [reference] se retrouve au centre du panorama.
  static List<List<double>> recenterYaw(
    List<List<double>> rotations, {
    int reference = 0,
  }) {
    if (rotations.isEmpty) return rotations;
    final yaw = yawOf(rotations[reference]);
    final c = math.cos(-yaw), s = math.sin(-yaw);
    // Rotation autour de y (vertical) : [[c,0,s],[0,1,0],[−s,0,c]].
    final ry = [c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c];
    return [for (final r in rotations) multiply(ry, r)];
  }

  /// Produit de deux matrices 3×3.
  static List<double> multiply(List<double> a, List<double> b) => [
    for (var i = 0; i < 3; i++)
      for (var j = 0; j < 3; j++)
        a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j],
  ];

  static List<double> _cross(List<double> a, List<double> b) => [
    a[1] * b[2] - a[2] * b[1],
    a[2] * b[0] - a[0] * b[2],
    a[0] * b[1] - a[1] * b[0],
  ];

  static List<double>? _normalize(List<double> v) {
    final n = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (n < 1e-6) return null;
    return [v[0] / n, v[1] / n, v[2] / n];
  }
}

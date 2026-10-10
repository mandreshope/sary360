import 'dart:math' as math;
import 'dart:ui';

import 'quaternion.dart';
import 'vec3.dart';

/// Applique une rotation (matrice 3×3 ligne par ligne) à un vecteur.
Vec3 rotate(List<double> m, Vec3 v) => Vec3(
  m[0] * v.x + m[1] * v.y + m[2] * v.z,
  m[3] * v.x + m[4] * v.y + m[5] * v.z,
  m[6] * v.x + m[7] * v.y + m[8] * v.z,
);

/// Applique la rotation inverse (transposée) à un vecteur.
Vec3 rotateInverse(List<double> m, Vec3 v) => Vec3(
  m[0] * v.x + m[3] * v.y + m[6] * v.z,
  m[1] * v.x + m[4] * v.y + m[7] * v.z,
  m[2] * v.x + m[5] * v.y + m[8] * v.z,
);

/// Projection perspective d'une direction du monde (ENU) sur l'écran, pour
/// la caméra arrière d'un téléphone d'orientation donnée.
///
/// Repère caméra (OpenCV) : x à droite de l'écran, y vers le bas, z dans
/// l'axe de visée (= −z appareil).
class ScreenProjection {
  ScreenProjection({
    required Quaternion deviceToWorld,
    required this.size,
    required this.focal,
  }) : _matrix = deviceToWorld.toRotationMatrix();

  /// Taille de la zone d'affichage (pixels logiques).
  final Size size;

  /// Focale en pixels logiques (voir [focalFor]).
  final double focal;

  final List<double> _matrix;

  /// Profondeur minimale pour qu'un point soit projeté (devant la caméra).
  static const double near = 0.05;

  /// Focale écran d'un aperçu affiché en `BoxFit.cover` : l'image (de
  /// rapport [previewAspect] = largeur / hauteur, en portrait) remplit la
  /// zone et déborde sur l'axe le plus court.
  static double focalFor({
    required Size size,
    required double previewAspect,
    required double hFovDeg,
    required double vFovDeg,
  }) {
    final screenAspect = size.width / size.height;
    if (screenAspect < previewAspect) {
      // Écran plus allongé que l'aperçu : la hauteur est entièrement visible.
      return size.height / 2 / math.tan(vFovDeg * math.pi / 360);
    }
    return size.width / 2 / math.tan(hFovDeg * math.pi / 360);
  }

  /// Direction du monde exprimée dans le repère caméra.
  Vec3 toCamera(Vec3 world) {
    final d = rotateInverse(_matrix, world);
    return Vec3(d.x, -d.y, -d.z);
  }

  /// Position écran, ou `null` si la direction est derrière la caméra.
  Offset? project(Vec3 world) {
    final c = toCamera(world);
    if (c.z < near) return null;
    return Offset(
      size.width / 2 + focal * c.x / c.z,
      size.height / 2 + focal * c.y / c.z,
    );
  }

  /// Direction écran (unitaire) vers un point, même hors champ ou derrière :
  /// sert à orienter une flèche de guidage au bord de l'écran.
  Offset directionTo(Vec3 world) {
    final c = toCamera(world);
    final len = math.sqrt(c.x * c.x + c.y * c.y);
    if (len < 1e-6) return const Offset(0, -1);
    return Offset(c.x / len, c.y / len);
  }
}

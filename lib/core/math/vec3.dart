import 'dart:math' as math;

/// Vecteur 3D minimal, immuable, utilisé par les rendus de sphère.
///
/// Repère : x vers la droite, y vers le haut, z vers l'observateur.
class Vec3 {
  const Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  /// Point de la sphère unité à partir d'un azimut et d'une élévation (radians).
  /// Azimut 0 = face à l'observateur (+z), élévation positive = vers le haut.
  factory Vec3.fromSpherical(double azimuth, double elevation) {
    final c = math.cos(elevation);
    return Vec3(
      c * math.sin(azimuth),
      math.sin(elevation),
      c * math.cos(azimuth),
    );
  }

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;

  double get length => math.sqrt(dot(this));

  Vec3 normalized() {
    final l = length;
    return l == 0 ? this : this * (1 / l);
  }

  /// Rotation autour de l'axe vertical (Y).
  Vec3 rotateY(double a) {
    final c = math.cos(a), s = math.sin(a);
    return Vec3(c * x + s * z, y, -s * x + c * z);
  }

  /// Rotation autour de l'axe horizontal (X).
  Vec3 rotateX(double a) {
    final c = math.cos(a), s = math.sin(a);
    return Vec3(x, c * y - s * z, s * y + c * z);
  }

  /// Angle (radians) entre deux directions.
  double angleTo(Vec3 o) {
    final d = normalized().dot(o.normalized()).clamp(-1.0, 1.0);
    return math.acos(d);
  }

  @override
  String toString() => 'Vec3($x, $y, $z)';
}

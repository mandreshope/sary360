import 'dart:math' as math;

/// Quaternion unitaire représentant une rotation 3D (convention Hamilton,
/// composantes x, y, z, w).
///
/// Sert à stocker l'orientation du téléphone au moment de chaque capture.
class Quaternion {
  const Quaternion(this.x, this.y, this.z, this.w);

  static const identity = Quaternion(0, 0, 0, 1);

  final double x;
  final double y;
  final double z;
  final double w;

  /// Rotation d'angle [angle] (radians) autour de l'axe unitaire (ax, ay, az).
  factory Quaternion.fromAxisAngle(
    double ax,
    double ay,
    double az,
    double angle,
  ) {
    final n = math.sqrt(ax * ax + ay * ay + az * az);
    final s = math.sin(angle / 2) / n;
    return Quaternion(ax * s, ay * s, az * s, math.cos(angle / 2));
  }

  /// Conversion depuis une matrice de rotation 3×3 (ligne par ligne).
  /// Méthode de Shepperd : on part de la plus grande composante pour rester
  /// numériquement stable quel que soit l'angle.
  factory Quaternion.fromRotationMatrix(List<double> m) {
    assert(m.length == 9);
    final m00 = m[0], m01 = m[1], m02 = m[2];
    final m10 = m[3], m11 = m[4], m12 = m[5];
    final m20 = m[6], m21 = m[7], m22 = m[8];
    final trace = m00 + m11 + m22;
    double x, y, z, w;
    if (trace > 0) {
      final s = math.sqrt(trace + 1) * 2;
      w = s / 4;
      x = (m21 - m12) / s;
      y = (m02 - m20) / s;
      z = (m10 - m01) / s;
    } else if (m00 > m11 && m00 > m22) {
      final s = math.sqrt(1 + m00 - m11 - m22) * 2;
      w = (m21 - m12) / s;
      x = s / 4;
      y = (m01 + m10) / s;
      z = (m02 + m20) / s;
    } else if (m11 > m22) {
      final s = math.sqrt(1 + m11 - m00 - m22) * 2;
      w = (m02 - m20) / s;
      x = (m01 + m10) / s;
      y = s / 4;
      z = (m12 + m21) / s;
    } else {
      final s = math.sqrt(1 + m22 - m00 - m11) * 2;
      w = (m10 - m01) / s;
      x = (m02 + m20) / s;
      y = (m12 + m21) / s;
      z = s / 4;
    }
    return Quaternion(x, y, z, w).normalized();
  }

  /// Désérialisation depuis [x, y, z, w].
  factory Quaternion.fromList(List<num> v) => Quaternion(
    v[0].toDouble(),
    v[1].toDouble(),
    v[2].toDouble(),
    v[3].toDouble(),
  );

  List<double> toList() => [x, y, z, w];

  double get norm => math.sqrt(x * x + y * y + z * z + w * w);

  Quaternion normalized() {
    final n = norm;
    return n == 0 ? identity : Quaternion(x / n, y / n, z / n, w / n);
  }

  Quaternion conjugate() => Quaternion(-x, -y, -z, w);

  /// Composition : (this * o) applique d'abord [o], puis this.
  Quaternion operator *(Quaternion o) => Quaternion(
    w * o.x + x * o.w + y * o.z - z * o.y,
    w * o.y - x * o.z + y * o.w + z * o.x,
    w * o.z + x * o.y - y * o.x + z * o.w,
    w * o.w - x * o.x - y * o.y - z * o.z,
  );

  /// Matrice de rotation 3×3 équivalente (ligne par ligne).
  List<double> toRotationMatrix() {
    final q = normalized();
    final xx = q.x * q.x, yy = q.y * q.y, zz = q.z * q.z;
    final xy = q.x * q.y, xz = q.x * q.z, yz = q.y * q.z;
    final wx = q.w * q.x, wy = q.w * q.y, wz = q.w * q.z;
    return [
      1 - 2 * (yy + zz), 2 * (xy - wz), 2 * (xz + wy), //
      2 * (xy + wz), 1 - 2 * (xx + zz), 2 * (yz - wx), //
      2 * (xz - wy), 2 * (yz + wx), 1 - 2 * (xx + yy),
    ];
  }

  /// Angle (radians) de la rotation qui mène de this à [o].
  double angleTo(Quaternion o) {
    final d = (x * o.x + y * o.y + z * o.z + w * o.w).abs().clamp(0.0, 1.0);
    return 2 * math.acos(d);
  }

  @override
  String toString() =>
      'Quaternion(${x.toStringAsFixed(4)}, ${y.toStringAsFixed(4)}, '
      '${z.toStringAsFixed(4)}, ${w.toStringAsFixed(4)})';
}

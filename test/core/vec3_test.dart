import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sary360/core/math/vec3.dart';

void main() {
  group('Vec3', () {
    test('fromSpherical place azimut 0 face à l\'observateur', () {
      final v = Vec3.fromSpherical(0, 0);
      expect(v.x, closeTo(0, 1e-9));
      expect(v.y, closeTo(0, 1e-9));
      expect(v.z, closeTo(1, 1e-9));
    });

    test('fromSpherical : élévation +90° = zénith', () {
      final v = Vec3.fromSpherical(1.234, math.pi / 2);
      expect(v.y, closeTo(1, 1e-9));
      expect(v.length, closeTo(1, 1e-9));
    });

    test('rotateY conserve la norme et tourne de 90°', () {
      final v = const Vec3(0, 0, 1).rotateY(math.pi / 2);
      expect(v.x, closeTo(1, 1e-9));
      expect(v.z, closeTo(0, 1e-9));
      expect(v.length, closeTo(1, 1e-9));
    });

    test('angleTo entre deux étoiles de l\'horizon espacées de 30°', () {
      final a = Vec3.fromSpherical(0, 0);
      final b = Vec3.fromSpherical(math.pi / 6, 0);
      expect(a.angleTo(b), closeTo(math.pi / 6, 1e-9));
    });
  });
}

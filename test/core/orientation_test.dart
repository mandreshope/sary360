import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sary360/core/math/camera_rotation.dart';
import 'package:sary360/core/math/quaternion.dart';

/// Colonne [c] d'une matrice 3×3 (ligne par ligne).
List<double> column(List<double> m, int c) => [m[c], m[3 + c], m[6 + c]];

Matcher closeToVector(List<double> expected, [double eps = 1e-6]) =>
    predicate<List<double>>(
      (v) => List.generate(
        3,
        (i) => (v[i] - expected[i]).abs() < eps,
      ).every((ok) => ok),
      'proche de $expected',
    );

void main() {
  group('Quaternion', () {
    test('aller-retour matrice ↔ quaternion sur des rotations variées', () {
      final rnd = math.Random(7);
      for (var k = 0; k < 200; k++) {
        final q = Quaternion.fromAxisAngle(
          rnd.nextDouble() - 0.5,
          rnd.nextDouble() - 0.5,
          rnd.nextDouble() - 0.5,
          rnd.nextDouble() * 2 * math.pi,
        );
        final back = Quaternion.fromRotationMatrix(q.toRotationMatrix());
        expect(q.angleTo(back), closeTo(0, 1e-6));
      }
    });

    test('rotation de 90° autour de z envoie x sur y', () {
      final m = Quaternion.fromAxisAngle(
        0,
        0,
        1,
        math.pi / 2,
      ).toRotationMatrix();
      expect(column(m, 0), closeToVector([0, 1, 0]));
    });

    test('la composition correspond au produit des matrices', () {
      final a = Quaternion.fromAxisAngle(1, 2, 3, 0.7);
      final b = Quaternion.fromAxisAngle(-2, 0.5, 1, 1.9);
      final viaQuat = (a * b).toRotationMatrix();
      final viaMat = CameraRotation.multiply(
        a.toRotationMatrix(),
        b.toRotationMatrix(),
      );
      for (var i = 0; i < 9; i++) {
        expect(viaQuat[i], closeTo(viaMat[i], 1e-9));
      }
    });

    test('angleTo mesure l\'écart entre deux orientations', () {
      final a = Quaternion.fromAxisAngle(0, 1, 0, 0.2);
      final b = Quaternion.fromAxisAngle(0, 1, 0, 0.5);
      expect(a.angleTo(b), closeTo(0.3, 1e-9));
    });
  });

  group('CameraRotation.deviceToWorldFromSensors', () {
    // Champ magnétique typique : composante Nord + composante vers le bas.
    test('téléphone à plat sur une table, haut de l\'écran vers le Nord', () {
      final q = CameraRotation.deviceToWorldFromSensors(
        [0, 0, 9.81], // gravité : z appareil vers le haut
        [0, 22, -40], // Nord = y appareil, vers le bas = −z
      )!;
      final m = q.toRotationMatrix();
      // Les colonnes donnent les axes appareil dans le monde (Est, Nord, Haut).
      expect(column(m, 0), closeToVector([1, 0, 0]));
      expect(column(m, 1), closeToVector([0, 1, 0]));
      expect(column(m, 2), closeToVector([0, 0, 1]));
    });

    test('mesures dégénérées : null', () {
      expect(
        CameraRotation.deviceToWorldFromSensors([0, 0, 0], [1, 0, 0]),
        isNull,
      );
      // Champ magnétique parallèle à la gravité.
      expect(
        CameraRotation.deviceToWorldFromSensors([0, 0, 9.8], [0, 0, -40]),
        isNull,
      );
    });
  });

  group('CameraRotation.openCvCameraToWorld', () {
    // Téléphone en portrait, caméra arrière vers le Nord : y appareil vers le
    // haut, écran (z appareil) vers le Sud.
    final facingNorth = CameraRotation.deviceToWorldFromSensors(
      [0, 9.81, 0],
      [0, -40, -22], // vers le bas = −y, Nord = −z (devant la caméra)
    )!;

    test('caméra vers le Nord : axe de visée au centre du panorama', () {
      final r = CameraRotation.openCvCameraToWorld(facingNorth);
      expect(column(r, 2), closeToVector([0, 0, 1])); // visée → z monde
      expect(column(r, 1), closeToVector([0, 1, 0])); // bas image → bas monde
      expect(column(r, 0), closeToVector([1, 0, 0])); // droite → Est
      expect(CameraRotation.yawOf(r), closeTo(0, 1e-9));
    });

    test('caméra vers l\'Est : cap de +90°', () {
      // Rotation de −90° autour du zénith (sens horaire vu de dessus).
      final turn = Quaternion.fromAxisAngle(0, 0, 1, -math.pi / 2);
      final r = CameraRotation.openCvCameraToWorld(turn * facingNorth);
      expect(CameraRotation.yawOf(r), closeTo(math.pi / 2, 1e-9));
      expect(column(r, 2), closeToVector([1, 0, 0]));
    });

    test('caméra vers le zénith : visée vers −y (haut du panorama)', () {
      // Bascule de 90° autour de l'axe Est : la visée passe du Nord au zénith.
      final tilt = Quaternion.fromAxisAngle(1, 0, 0, math.pi / 2);
      final r = CameraRotation.openCvCameraToWorld(tilt * facingNorth);
      expect(column(r, 2), closeToVector([0, -1, 0]));
    });

    test('la matrice obtenue est une rotation (orthonormée, det = 1)', () {
      final q = Quaternion.fromAxisAngle(0.3, -1, 0.4, 2.1) * facingNorth;
      final r = CameraRotation.openCvCameraToWorld(q);
      final rtr = CameraRotation.multiply([
        r[0], r[3], r[6], r[1], r[4], r[7], r[2], r[5], r[8], //
      ], r);
      for (var i = 0; i < 9; i++) {
        expect(rtr[i], closeTo(i % 4 == 0 ? 1 : 0, 1e-9));
      }
    });
  });

  group('CameraRotation.recenterYaw', () {
    test(
      'la photo de référence passe au centre, les écarts sont conservés',
      () {
        final base = CameraRotation.deviceToWorldFromSensors(
          [0, 9.81, 0],
          [0, -40, -22],
        )!;
        Quaternion yawed(double deg) =>
            Quaternion.fromAxisAngle(0, 0, 1, -deg * math.pi / 180) * base;
        final rotations = [
          CameraRotation.openCvCameraToWorld(yawed(130)),
          CameraRotation.openCvCameraToWorld(yawed(170)),
          CameraRotation.openCvCameraToWorld(yawed(-140)),
        ];

        final centered = CameraRotation.recenterYaw(rotations);

        expect(CameraRotation.yawOf(centered[0]), closeTo(0, 1e-9));
        expect(
          CameraRotation.yawOf(centered[1]),
          closeTo(40 * math.pi / 180, 1e-9),
        );
        // 130° → −140° : 90° plus loin vers l'Est.
        expect(
          CameraRotation.yawOf(centered[2]),
          closeTo(90 * math.pi / 180, 1e-9),
        );
      },
    );
  });
}

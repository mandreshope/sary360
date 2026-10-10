import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sary360/core/constants/app_constants.dart';
import 'package:sary360/core/math/quaternion.dart';
import 'package:sary360/core/math/screen_projection.dart';
import 'package:sary360/core/math/vec3.dart';
import 'package:sary360/domain/capture/capture_session.dart';

/// Téléphone tenu en portrait, caméra arrière visant le cap [headingDeg]
/// (sens horaire depuis le Nord) et l'élévation [elevationDeg].
Quaternion aim(double headingDeg, double elevationDeg) {
  final h = headingDeg * math.pi / 180;
  final e = elevationDeg * math.pi / 180;
  // Visée vers le Nord : écran (z appareil) vers le Sud, haut vers le zénith.
  const facingNorth = [1.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0];
  final base = Quaternion.fromRotationMatrix(facingNorth);
  final tilt = Quaternion.fromAxisAngle(1, 0, 0, e); // lever la visée
  final turn = Quaternion.fromAxisAngle(0, 0, 1, -h); // tourner vers l'Est
  return turn * tilt * base;
}

void main() {
  group('CaptureSession', () {
    test('la grille ultra grand angle compte 26 cibles, horizon d\'abord', () {
      final s = CaptureSession(CaptureGrid.wide);
      expect(s.total, 26);
      expect(s.targets.first.row, CaptureSession.horizonRow);
      expect(
        s.targets.take(10).every((t) => t.row == CaptureSession.horizonRow),
        isTrue,
      );
    });

    test('visée et élévation se lisent dans l\'orientation', () {
      final q = aim(30, 20);
      expect(
        CaptureSession.headingOf(CaptureSession.cameraForward(q)) *
            180 /
            math.pi,
        closeTo(30, 1e-6),
      );
      expect(CaptureSession.elevationDeg(q), closeTo(20, 1e-6));
      expect(CaptureSession.rollDeg(q), closeTo(0, 1e-6));
    });

    test('roulis détecté quand le téléphone penche sur le côté', () {
      final roll = Quaternion.fromAxisAngle(0, 1, 0, 20 * math.pi / 180);
      // Rotation autour de l'axe de visée (Nord) : l'écran penche.
      final q = roll * aim(0, 0);
      expect(CaptureSession.rollDeg(q).abs(), closeTo(20, 1e-6));
    });

    test('les cibles sont relatives au cap de départ', () {
      final s = CaptureSession(CaptureGrid.wide)..anchor(aim(100, 0));
      final first = s.targets.first; // horizon, azimut 0
      expect(s.angleToTarget(aim(100, 0), first), closeTo(0, 1e-6));
      // La 2e cible de l'horizon est 36° plus loin vers l'Est.
      expect(s.angleToTarget(aim(136, 0), s.targets[1]), closeTo(0, 1e-6));
    });

    test('cible dans le réticule selon la tolérance', () {
      final s = CaptureSession(CaptureGrid.wide)..anchor(aim(0, 0));
      expect(s.targetInReticle(aim(3, 0), toleranceDeg: 5)?.index, 0);
      expect(s.targetInReticle(aim(12, 0), toleranceDeg: 5), isNull);
    });

    test('une cible capturée ne revient plus dans le réticule', () {
      final s = CaptureSession(CaptureGrid.wide)..anchor(aim(0, 0));
      s.markCaptured(s.targets.first);
      expect(s.targetInReticle(aim(0, 0)), isNull);
      expect(s.nearestRemaining(aim(0, 0))?.index, isNot(0));
    });

    test('le zénith se vise quel que soit le cap (distance angulaire)', () {
      final s = CaptureSession(CaptureGrid.wide)..anchor(aim(0, 0));
      final zenith = s.targets.firstWhere((t) => t.row == 0);
      // À 85° d'élévation, viser depuis un cap opposé reste proche.
      expect(s.angleToTarget(aim(180, 85), zenith), lessThan(11));
      expect(s.angleToTarget(aim(0, 85), zenith), closeTo(0, 1e-6));
    });

    test('« Terminer » possible une fois l\'horizon couvert', () {
      final s = CaptureSession(CaptureGrid.wide)..anchor(aim(0, 0));
      for (final t in s.targets.where(
        (t) => t.row == CaptureSession.horizonRow,
      )) {
        expect(s.horizonComplete, isFalse);
        s.markCaptured(t);
      }
      expect(s.horizonComplete, isTrue);
      expect(s.isComplete, isFalse);
    });

    test('la constellation relie chaque cible à au moins une voisine', () {
      final s = CaptureSession(CaptureGrid.wide);
      final linked = {
        for (final (a, b) in s.edges) ...[a, b],
      };
      expect(linked.length, s.total);
    });
  });

  group('StabilityTracker', () {
    test('immobile : la durée de stabilité augmente', () {
      final tracker = StabilityTracker();
      final q = aim(0, 0);
      var stable = 0.0;
      for (var i = 0; i <= 20; i++) {
        stable = tracker.add(q, i * 0.02);
      }
      expect(stable, closeTo(0.38, 0.03));
      expect(tracker.averageOrientation()!.angleTo(q), closeTo(0, 1e-6));
    });

    test('en mouvement : pas de stabilité', () {
      final tracker = StabilityTracker();
      var stable = 0.0;
      for (var i = 0; i <= 20; i++) {
        // 30°/s autour de la verticale.
        stable = tracker.add(aim(i * 0.6, 0), i * 0.02);
      }
      expect(stable, 0);
      expect(tracker.speedDegPerSec, closeTo(30, 3));
    });
  });

  group('ScreenProjection', () {
    const size = Size(400, 800);
    final projection = ScreenProjection(
      deviceToWorld: aim(0, 0),
      size: size,
      focal: 500,
    );

    test('la direction visée tombe au centre de l\'écran', () {
      final p = projection.project(const Vec3(0, 1, 0))!;
      expect(p.dx, closeTo(200, 1e-6));
      expect(p.dy, closeTo(400, 1e-6));
    });

    test('à droite et au-dessus de la visée', () {
      final right = projection.project(Vec3(math.sin(0.2), math.cos(0.2), 0))!;
      expect(right.dx, closeTo(200 + 500 * math.tan(0.2), 1e-6));
      final up = projection.project(Vec3(0, math.cos(0.2), math.sin(0.2)))!;
      expect(up.dy, closeTo(400 - 500 * math.tan(0.2), 1e-6));
    });

    test('derrière la caméra : pas de projection, mais une direction', () {
      expect(projection.project(const Vec3(0, -1, 0)), isNull);
      final dir = projection.directionTo(const Vec3(1, -0.2, 0));
      expect(dir.dx, greaterThan(0));
    });

    test('focale d\'un aperçu en BoxFit.cover', () {
      // Écran plus allongé que l'aperçu 9:16 : la hauteur fait référence.
      final f = ScreenProjection.focalFor(
        size: const Size(390, 844),
        previewAspect: 9 / 16,
        hFovDeg: 53,
        vFovDeg: 83,
      );
      expect(f, closeTo(422 / math.tan(41.5 * math.pi / 180), 1e-6));
    });
  });
}

import 'dart:math' as math;

import '../../core/constants/app_constants.dart';
import '../../core/math/quaternion.dart';
import '../../core/math/screen_projection.dart';
import '../../core/math/vec3.dart';

/// Une cible de la sphère.
class CaptureTarget {
  const CaptureTarget({
    required this.index,
    required this.row,
    required this.indexInRow,
    required this.azimuthDeg,
    required this.elevationDeg,
  });

  final int index;

  /// Rangée dans la grille (0 = zénith, 2 = horizon, 4 = nadir).
  final int row;
  final int indexInRow;

  /// Azimut relatif au cap de départ (degrés, sens horaire vu du dessus).
  final double azimuthDeg;
  final double elevationDeg;
}

/// Logique d'une session de capture, indépendante de la caméra et des
/// capteurs : cibles, cible dans le réticule, couverture, constellation.
class CaptureSession {
  CaptureSession(this.grid) : targets = _buildTargets(grid) {
    _edges = _buildEdges();
  }

  final CaptureGrid grid;
  final List<CaptureTarget> targets;
  final Set<int> captured = {};

  /// Cap (radians, sens horaire depuis le « Nord » du capteur) de la
  /// première visée : l'azimut des cibles lui est relatif.
  double? referenceHeading;

  late final List<(int, int)> _edges;

  /// Rangée de l'horizon dans la grille.
  static const int horizonRow = 2;

  static List<CaptureTarget> _buildTargets(CaptureGrid grid) {
    final list = <CaptureTarget>[];
    // Ordre de suggestion : horizon, haut, zénith, bas, nadir.
    for (final row in const [2, 1, 0, 3, 4]) {
      final n = grid.photosPerRow[row];
      final step = 360.0 / n;
      final offset = row.isOdd ? step / 2 : 0.0;
      for (var i = 0; i < n; i++) {
        list.add(
          CaptureTarget(
            index: list.length,
            row: row,
            indexInRow: i,
            azimuthDeg: (i * step + offset) % 360,
            elevationDeg: grid.rowElevations[row],
          ),
        );
      }
    }
    return list;
  }

  /// Paires de cibles voisines (constellation) : distance angulaire
  /// inférieure à 1,2 × la plus grande distance au plus proche voisin.
  List<(int, int)> _buildEdges() {
    final dirs = [for (final t in targets) _relativeDirection(t)];
    var maxNearest = 0.0;
    for (var i = 0; i < dirs.length; i++) {
      var nearest = double.infinity;
      for (var j = 0; j < dirs.length; j++) {
        if (i != j) nearest = math.min(nearest, dirs[i].angleTo(dirs[j]));
      }
      maxNearest = math.max(maxNearest, nearest);
    }
    final threshold = maxNearest * 1.2;
    return [
      for (var i = 0; i < dirs.length; i++)
        for (var j = i + 1; j < dirs.length; j++)
          if (dirs[i].angleTo(dirs[j]) <= threshold) (i, j),
    ];
  }

  /// Arêtes de la constellation entre cibles voisines.
  List<(int, int)> get edges => _edges;

  int get total => targets.length;
  int get capturedCount => captured.length;
  bool get isComplete => captured.length == targets.length;

  /// Toutes les cibles de l'horizon sont capturées : « Terminer » possible.
  bool get horizonComplete => targets
      .where((t) => t.row == horizonRow)
      .every((t) => captured.contains(t.index));

  /// Direction d'une cible relative au cap de départ (ENU, cap 0 = +y).
  static Vec3 _relativeDirection(CaptureTarget t) {
    final az = t.azimuthDeg * math.pi / 180;
    final el = t.elevationDeg * math.pi / 180;
    return Vec3(
      math.sin(az) * math.cos(el),
      math.cos(az) * math.cos(el),
      math.sin(el),
    );
  }

  /// Direction de la cible dans le monde (ENU), ou `null` tant que le cap de
  /// départ n'est pas connu.
  Vec3? directionOf(CaptureTarget t) {
    final h = referenceHeading;
    if (h == null) return null;
    final d = _relativeDirection(t);
    // Rotation de −h autour du zénith : un cap relatif de 0 vise le cap h.
    final c = math.cos(h), s = math.sin(h);
    return Vec3(c * d.x + s * d.y, -s * d.x + c * d.y, d.z);
  }

  /// Axe de visée de la caméra arrière (−z appareil) dans le monde.
  static Vec3 cameraForward(Quaternion deviceToWorld) =>
      rotate(deviceToWorld.toRotationMatrix(), const Vec3(0, 0, -1));

  /// Cap (radians, sens horaire depuis +y) d'une direction du monde.
  static double headingOf(Vec3 d) => math.atan2(d.x, d.y);

  /// Élévation (degrés) de la visée.
  static double elevationDeg(Quaternion deviceToWorld) {
    final f = cameraForward(deviceToWorld);
    return math.asin(f.z.clamp(-1.0, 1.0)) * 180 / math.pi;
  }

  /// Inclinaison latérale (roulis, degrés) : angle entre le bord horizontal
  /// de l'écran et l'horizon. Sans signification près des pôles.
  static double rollDeg(Quaternion deviceToWorld) {
    final m = deviceToWorld.toRotationMatrix();
    final right = Vec3(m[0], m[3], m[6]); // axe x appareil dans le monde
    return math.asin(right.z.clamp(-1.0, 1.0)) * 180 / math.pi;
  }

  /// Fixe le cap de départ à la visée actuelle (une seule fois).
  void anchor(Quaternion deviceToWorld) {
    referenceHeading ??= headingOf(cameraForward(deviceToWorld));
  }

  /// Distance angulaire (degrés) entre la visée et une cible.
  double angleToTarget(Quaternion deviceToWorld, CaptureTarget t) {
    final d = directionOf(t);
    if (d == null) return double.infinity;
    return cameraForward(deviceToWorld).angleTo(d) * 180 / math.pi;
  }

  /// Cible non capturée la plus proche de la visée.
  CaptureTarget? nearestRemaining(Quaternion deviceToWorld) {
    CaptureTarget? best;
    var bestAngle = double.infinity;
    for (final t in targets) {
      if (captured.contains(t.index)) continue;
      final a = angleToTarget(deviceToWorld, t);
      if (a < bestAngle) {
        bestAngle = a;
        best = t;
      }
    }
    return best;
  }

  /// Cible non capturée dans le réticule (à moins de [toleranceDeg]).
  CaptureTarget? targetInReticle(
    Quaternion deviceToWorld, {
    double toleranceDeg = 5,
  }) {
    final t = nearestRemaining(deviceToWorld);
    if (t == null) return null;
    return angleToTarget(deviceToWorld, t) <= toleranceDeg ? t : null;
  }

  void markCaptured(CaptureTarget t) => captured.add(t.index);
  void unmarkCaptured(CaptureTarget t) => captured.remove(t.index);
}

/// Suivi de la stabilité du téléphone : vitesse angulaire lissée et durée
/// passée sous un seuil, plus l'orientation moyenne de cette période.
class StabilityTracker {
  StabilityTracker({this.thresholdDegPerSec = 6, this.smoothing = 0.3});

  /// Vitesse angulaire sous laquelle le téléphone est considéré immobile.
  final double thresholdDegPerSec;

  /// Coefficient du lissage exponentiel de la vitesse.
  final double smoothing;

  Quaternion? _last;
  double? _lastTime;
  double _speed = 0;
  double? _stableSince;
  final List<Quaternion> _window = [];

  /// Vitesse angulaire lissée (degrés / seconde).
  double get speedDegPerSec => _speed;

  void reset() {
    _stableSince = null;
    _window.clear();
  }

  /// Ajoute une mesure et renvoie la durée (secondes) de stabilité continue.
  double add(Quaternion q, double timestamp) {
    final last = _last, lastTime = _lastTime;
    _last = q;
    _lastTime = timestamp;
    if (last == null || lastTime == null) return 0;
    final dt = timestamp - lastTime;
    if (dt <= 0 || dt > 0.5) return stableFor(timestamp);
    final instant = last.angleTo(q) * 180 / math.pi / dt;
    _speed += smoothing * (instant - _speed);

    if (_speed < thresholdDegPerSec) {
      _stableSince ??= timestamp;
      _window.add(q);
    } else {
      reset();
    }
    return stableFor(timestamp);
  }

  double stableFor(double now) {
    final since = _stableSince;
    return since == null ? 0 : now - since;
  }

  /// Orientation moyenne sur la période stable (quaternions alignés sur le
  /// même hémisphère puis normalisés), ou `null` si aucune mesure.
  Quaternion? averageOrientation() {
    if (_window.isEmpty) return null;
    final ref = _window.first;
    var x = 0.0, y = 0.0, z = 0.0, w = 0.0;
    for (final q in _window) {
      final sign = (q.x * ref.x + q.y * ref.y + q.z * ref.z + q.w * ref.w) < 0
          ? -1
          : 1;
      x += sign * q.x;
      y += sign * q.y;
      z += sign * q.z;
      w += sign * q.w;
    }
    return Quaternion(x, y, z, w).normalized();
  }
}

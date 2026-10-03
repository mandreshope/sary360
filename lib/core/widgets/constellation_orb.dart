import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../math/vec3.dart';
import '../theme/constellation_colors.dart';

/// Sphère en fil de fer qui tourne lentement, parsemée d'étoiles qui
/// s'allument une à une et se relient en constellation.
///
/// Sert d'emblème visuel (accueil, onboarding) et sera réutilisée par l'écran
/// d'assemblage (la constellation « se replie » en sphère).
class ConstellationOrb extends StatefulWidget {
  const ConstellationOrb({
    super.key,
    this.size = 220,
    this.progress,
    this.rotationPeriod = const Duration(seconds: 24),
    this.loopDuration = const Duration(seconds: 9),
  });

  /// Tag Hero partagé entre l'accueil, la capture et l'assemblage.
  static const heroTag = 'constellation-orb';

  final double size;

  /// Part des étoiles allumées (0..1). `null` = boucle animée automatique.
  final double? progress;

  /// Durée d'un tour complet de la sphère.
  final Duration rotationPeriod;

  /// Durée d'un cycle d'allumage quand [progress] est `null`.
  final Duration loopDuration;

  @override
  State<ConstellationOrb> createState() => _ConstellationOrbState();
}

class _ConstellationOrbState extends State<ConstellationOrb>
    with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: widget.rotationPeriod,
  )..repeat();

  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: widget.loopDuration,
  );

  @override
  void initState() {
    super.initState();
    if (widget.progress == null) _fill.repeat();
  }

  @override
  void didUpdateWidget(ConstellationOrb old) {
    super.didUpdateWidget(old);
    if (widget.progress == null && !_fill.isAnimating) {
      _fill.repeat();
    } else if (widget.progress != null && _fill.isAnimating) {
      _fill.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: _OrbPainter(
            spin: _spin,
            fill: _fill,
            fixedProgress: widget.progress,
            colors: c,
          ),
        ),
      ),
    );
  }
}

/// Étoiles réparties en anneaux, à l'image des cibles de capture :
/// horizon, ±45°, zénith et nadir. L'ordre de la liste est aussi l'ordre
/// d'allumage : l'horizon d'abord, comme pendant une vraie capture.
final List<Vec3> _orbStars = () {
  final pts = <Vec3>[];
  void ring(double elevDeg, int count, double offsetDeg) {
    for (var i = 0; i < count; i++) {
      final az = (i * 360 / count + offsetDeg) * math.pi / 180;
      pts.add(Vec3.fromSpherical(az, elevDeg * math.pi / 180));
    }
  }

  ring(0, 12, 0);
  ring(45, 8, 22.5);
  ring(-45, 8, 22.5);
  pts.add(const Vec3(0, 1, 0));
  pts.add(const Vec3(0, -1, 0));
  return pts;
}();

/// Arêtes de la constellation : paires d'étoiles voisines (< 50°).
final List<(int, int)> _orbEdges = () {
  final edges = <(int, int)>[];
  const maxAngle = 50 * math.pi / 180;
  for (var i = 0; i < _orbStars.length; i++) {
    for (var j = i + 1; j < _orbStars.length; j++) {
      if (_orbStars[i].angleTo(_orbStars[j]) < maxAngle) edges.add((i, j));
    }
  }
  return edges;
}();

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.spin,
    required this.fill,
    required this.fixedProgress,
    required this.colors,
  }) : super(repaint: Listenable.merge([spin, fill]));

  final Animation<double> spin;
  final Animation<double> fill;
  final double? fixedProgress;
  final ConstellationColors colors;

  static const double _tilt = -0.42; // inclinaison pour voir les pôles

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide * 0.42;
    final yaw = spin.value * math.pi * 2;

    // Progression : en boucle, on remplit sur 75 % du cycle puis on éteint.
    final double progress;
    if (fixedProgress != null) {
      progress = fixedProgress!.clamp(0.0, 1.0);
    } else {
      final f = fill.value;
      progress = f < 0.75
          ? Curves.easeInOut.transform(f / 0.75)
          : 1 - (f - 0.75) / 0.25;
    }

    Vec3 xf(Vec3 p) => p.rotateY(yaw).rotateX(_tilt);
    Offset proj(Vec3 p) => center + Offset(p.x * r, -p.y * r);
    // Opacité selon la profondeur : la face arrière est estompée.
    double depthAlpha(double z) => 0.18 + 0.82 * ((z + 1) / 2);

    // Halo de la sphère.
    canvas.drawCircle(
      center,
      r * 1.25,
      Paint()
        ..shader = RadialGradient(
          colors: [colors.accent.withValues(alpha: 0.18), Colors.transparent],
        ).createShader(Rect.fromCircle(center: center, radius: r * 1.25)),
    );

    // Contour.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = colors.starDim.withValues(alpha: 0.35),
    );

    // Méridiens et parallèles, découpés en segments pour gérer la profondeur.
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    void polyline(List<Vec3> pts) {
      for (var i = 0; i < pts.length - 1; i++) {
        final a = xf(pts[i]), b = xf(pts[i + 1]);
        grid.color = colors.starDim.withValues(
          alpha: 0.28 * depthAlpha((a.z + b.z) / 2),
        );
        canvas.drawLine(proj(a), proj(b), grid);
      }
    }

    const seg = 36;
    for (final elev in const [-60.0, -30.0, 0.0, 30.0, 60.0]) {
      final e = elev * math.pi / 180;
      polyline([
        for (var i = 0; i <= seg; i++)
          Vec3.fromSpherical(i * 2 * math.pi / seg, e),
      ]);
    }
    for (var m = 0; m < 6; m++) {
      final az = m * math.pi / 6;
      polyline([
        for (var i = 0; i <= seg; i++)
          Vec3.fromSpherical(az, -math.pi / 2 + i * math.pi / seg),
      ]);
    }

    // Niveau d'allumage de chaque étoile (0..1), avec un fondu progressif.
    final n = _orbStars.length;
    final lit = List<double>.filled(n, 0);
    final scaled = progress * n;
    for (var k = 0; k < n; k++) {
      lit[k] = (scaled - k).clamp(0.0, 1.0);
    }

    final projected = [for (final s in _orbStars) xf(s)];

    // Lignes de la constellation entre étoiles allumées.
    final line = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (final (i, j) in _orbEdges) {
      final l = math.min(lit[i], lit[j]);
      if (l <= 0) continue;
      final a = projected[i], b = projected[j];
      line.color = colors.constellationLine.withValues(
        alpha: colors.constellationLine.a * l * depthAlpha((a.z + b.z) / 2),
      );
      canvas.drawLine(proj(a), proj(b), line);
    }

    // Étoiles : éteintes = petits points, allumées = cœur + halo d'accent.
    final dot = Paint();
    final glow = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    for (var i = 0; i < n; i++) {
      final p = projected[i];
      final o = proj(p);
      final da = depthAlpha(p.z);
      final l = lit[i];
      if (l > 0) {
        glow.color = colors.accent.withValues(alpha: 0.7 * l * da);
        canvas.drawCircle(o, 4.5 + 2 * l, glow);
      }
      dot.color = Color.lerp(
        colors.starDim,
        colors.star,
        l,
      )!.withValues(alpha: da);
      canvas.drawCircle(o, 1.6 + 1.2 * l, dot);
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.fixedProgress != fixedProgress || old.colors != colors;
}

import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Point cible sur la sphère (pour afficher les points à capturer)
class TargetPoint {
  final double azimuth;
  final double elevation;
  final bool isCaptured;

  const TargetPoint({
    required this.azimuth,
    required this.elevation,
    this.isCaptured = false,
  });
}

/// Guide visuel sphérique 3D inspiré de Google Street View
/// Affiche une sphère en perspective avec tous les points de capture
class SphericalGuide extends StatelessWidget {
  final double currentAzimuth;
  final double currentElevation;
  final double targetAzimuth;
  final double targetElevation;
  final bool isNearTarget;
  final int totalTargets;
  final int capturedCount;
  final List<TargetPoint> allTargets;

  const SphericalGuide({
    super.key,
    required this.currentAzimuth,
    required this.currentElevation,
    required this.targetAzimuth,
    required this.targetElevation,
    required this.isNearTarget,
    required this.totalTargets,
    required this.capturedCount,
    this.allTargets = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.6),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipOval(
        child: CustomPaint(
          painter: _Sphere3DPainter(
            currentAzimuth: currentAzimuth,
            currentElevation: currentElevation,
            targetAzimuth: targetAzimuth,
            targetElevation: targetElevation,
            isNearTarget: isNearTarget,
            totalTargets: totalTargets,
            capturedCount: capturedCount,
            allTargets: allTargets,
          ),
        ),
      ),
    );
  }
}

/// Painter qui dessine une sphère 3D avec projection
class _Sphere3DPainter extends CustomPainter {
  final double currentAzimuth;
  final double currentElevation;
  final double targetAzimuth;
  final double targetElevation;
  final bool isNearTarget;
  final int totalTargets;
  final int capturedCount;
  final List<TargetPoint> allTargets;

  _Sphere3DPainter({
    required this.currentAzimuth,
    required this.currentElevation,
    required this.targetAzimuth,
    required this.targetElevation,
    required this.isNearTarget,
    required this.totalTargets,
    required this.capturedCount,
    required this.allTargets,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Rotation de la sphère pour que la direction actuelle soit au centre
    // Correction : sens positif pour l'azimut (le monde tourne à l'envers de la tête)
    final rotAz = currentAzimuth * math.pi / 180;
    final rotEl = currentElevation * math.pi / 180;

    // Dessiner le fond de la sphère
    _drawSphereBackground(canvas, center, radius);

    // Dessiner les lignes de latitude et de longitude (grille sphérique)
    _drawSphereGrid(canvas, center, radius, rotAz, rotEl);

    // Dessiner tous les points cibles
    _drawTargetPoints(canvas, center, radius, rotAz, rotEl);

    // Dessiner la cible courante
    _drawCurrentTarget(canvas, center, radius, rotAz, rotEl);

    // Dessiner la position actuelle (centre, petite croix)
    _drawCurrentPosition(canvas, center, radius);

    // Dessiner le compteur de captures
    _drawCaptureCount(canvas, size);
  }

  /// Projette un point sphérique (azimut, élévation) en 2D
  /// avec rotation de la vue.
  /// Retourne null si le point est derrière la sphère.
  Offset? _project(
    double azDeg,
    double elDeg,
    Offset center,
    double radius,
    double rotAz,
    double rotEl,
  ) {
    final az = azDeg * math.pi / 180;
    final el = elDeg * math.pi / 180;

    // Convertir en coordonnées cartésiennes sur la sphère unitaire
    double x = math.cos(el) * math.sin(az);
    double y = math.sin(el);
    double z = math.cos(el) * math.cos(az);

    // Rotation autour de l'axe Y (azimut)
    double x2 = x * math.cos(rotAz) - z * math.sin(rotAz);
    double z2 = x * math.sin(rotAz) + z * math.cos(rotAz);

    // Rotation autour de l'axe X (élévation)
    double y2 = y * math.cos(rotEl) - z2 * math.sin(rotEl);
    double z3 = y * math.sin(rotEl) + z2 * math.cos(rotEl);

    // Si le point est derrière (z3 < 0), il n'est pas visible
    if (z3 < -0.05) return null;

    // Projection orthographique (simple et lisible pour un guide miniature)
    final px = center.dx + x2 * radius * 0.9;
    final py = center.dy - y2 * radius * 0.9;

    return Offset(px, py);
  }

  void _drawSphereBackground(Canvas canvas, Offset center, double radius) {
    // Dégradé sphérique
    final bgPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.blueGrey.shade900.withValues(alpha: 0.3),
          Colors.black.withValues(alpha: 0.5),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, bgPaint);

    // Bord lumineux
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius, borderPaint);
  }

  void _drawSphereGrid(
    Canvas canvas,
    Offset center,
    double radius,
    double rotAz,
    double rotEl,
  ) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // Lignes de latitude
    for (final lat in [-60.0, -30.0, 0.0, 30.0, 60.0]) {
      _drawLatitudeLine(canvas, center, radius, lat, rotAz, rotEl, gridPaint);
    }

    // Lignes de longitude
    for (double lon = 0; lon < 360; lon += 45) {
      _drawLongitudeLine(canvas, center, radius, lon, rotAz, rotEl, gridPaint);
    }

    // Équateur plus visible
    final equatorPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    _drawLatitudeLine(canvas, center, radius, 0, rotAz, rotEl, equatorPaint);
  }

  void _drawLatitudeLine(
    Canvas canvas,
    Offset center,
    double radius,
    double lat,
    double rotAz,
    double rotEl,
    Paint paint,
  ) {
    final path = Path();
    bool firstVisible = true;
    Offset? lastPoint;

    for (double lon = 0; lon <= 360; lon += 5) {
      final p = _project(lon, lat, center, radius, rotAz, rotEl);
      if (p != null) {
        if (firstVisible) {
          path.moveTo(p.dx, p.dy);
          firstVisible = false;
        } else {
          // Éviter de tracer des lignes qui traversent la sphère
          if (lastPoint != null && (p - lastPoint).distance < radius * 0.5) {
            path.lineTo(p.dx, p.dy);
          } else {
            path.moveTo(p.dx, p.dy);
          }
        }
        lastPoint = p;
      } else {
        firstVisible = true;
        lastPoint = null;
      }
    }
    canvas.drawPath(path, paint);
  }

  void _drawLongitudeLine(
    Canvas canvas,
    Offset center,
    double radius,
    double lon,
    double rotAz,
    double rotEl,
    Paint paint,
  ) {
    final path = Path();
    bool firstVisible = true;
    Offset? lastPoint;

    for (double lat = -90; lat <= 90; lat += 5) {
      final p = _project(lon, lat, center, radius, rotAz, rotEl);
      if (p != null) {
        if (firstVisible) {
          path.moveTo(p.dx, p.dy);
          firstVisible = false;
        } else {
          if (lastPoint != null && (p - lastPoint).distance < radius * 0.5) {
            path.lineTo(p.dx, p.dy);
          } else {
            path.moveTo(p.dx, p.dy);
          }
        }
        lastPoint = p;
      } else {
        firstVisible = true;
        lastPoint = null;
      }
    }
    canvas.drawPath(path, paint);
  }

  void _drawTargetPoints(
    Canvas canvas,
    Offset center,
    double radius,
    double rotAz,
    double rotEl,
  ) {
    for (final target in allTargets) {
      final p = _project(
        target.azimuth,
        target.elevation,
        center,
        radius,
        rotAz,
        rotEl,
      );
      if (p == null) continue;

      if (target.isCaptured) {
        // Point capturé : vert plein
        final capturedPaint = Paint()
          ..color = Colors.greenAccent.withValues(alpha: 0.9)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(p, 4, capturedPaint);

        // Check mark
        final checkPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;
        final checkPath = Path()
          ..moveTo(p.dx - 2, p.dy)
          ..lineTo(p.dx - 0.5, p.dy + 2)
          ..lineTo(p.dx + 2.5, p.dy - 2);
        canvas.drawPath(checkPath, checkPaint);
      } else {
        // Point non capturé : petit cercle ouvert
        final pendingPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        canvas.drawCircle(p, 3, pendingPaint);
      }
    }
  }

  void _drawCurrentTarget(
    Canvas canvas,
    Offset center,
    double radius,
    double rotAz,
    double rotEl,
  ) {
    final p = _project(
      targetAzimuth,
      targetElevation,
      center,
      radius,
      rotAz,
      rotEl,
    );
    if (p == null) return;

    final color = isNearTarget ? Colors.greenAccent : Colors.orangeAccent;

    // La tolérance est de ~25 degrés.
    // Sur une sphère de rayon R, la projection est env. R * sin(25°).
    // sin(25°) ≈ 0.42. Pour R=76, ça fait ~32px.
    // On va dessiner un cercle de ~25px pour représenter cette zone large.
    final toleranceRadius = radius * 0.35; // ~26px

    // Glow qui remplit la zone
    final glowPaint = Paint()
      ..color = color.withValues(alpha: isNearTarget ? 0.4 : 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(p, toleranceRadius, glowPaint);

    // Cercle cible (la zone à atteindre)
    final targetPaint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isNearTarget ? 3 : 2;
    canvas.drawCircle(p, toleranceRadius * 0.8, targetPaint); // ~20px

    // Réticule central fin pour la précision visuelle (optionnel mais aide à centrer)
    final centerCrossPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(p.dx - 6, p.dy),
      Offset(p.dx + 6, p.dy),
      centerCrossPaint,
    );
    canvas.drawLine(
      Offset(p.dx, p.dy - 6),
      Offset(p.dx, p.dy + 6),
      centerCrossPaint,
    );
  }

  void _drawCurrentPosition(Canvas canvas, Offset center, double radius) {
    // La position actuelle est toujours au centre de la sphère
    // (car on fait tourner la sphère pour centrer la vue)
    final color = isNearTarget ? Colors.greenAccent : Colors.cyanAccent;

    // Cercle glow
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 8, glowPaint);

    // Point central
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 3.5, dotPaint);

    // Cercle autour
    final ringPaint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, 6, ringPaint);
  }

  void _drawCaptureCount(Canvas canvas, Size size) {
    final textSpan = TextSpan(
      text: '$capturedCount/$totalTargets',
      style: TextStyle(
        color: capturedCount > 0
            ? Colors.greenAccent.withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.7),
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset((size.width - textPainter.width) / 2, size.height - 22),
    );
  }

  @override
  bool shouldRepaint(covariant _Sphere3DPainter oldDelegate) {
    return oldDelegate.currentAzimuth != currentAzimuth ||
        oldDelegate.currentElevation != currentElevation ||
        oldDelegate.targetAzimuth != targetAzimuth ||
        oldDelegate.targetElevation != targetElevation ||
        oldDelegate.isNearTarget != isNearTarget ||
        oldDelegate.capturedCount != capturedCount ||
        oldDelegate.allTargets.length != allTargets.length;
  }
}

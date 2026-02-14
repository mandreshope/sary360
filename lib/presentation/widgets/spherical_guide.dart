import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Guide visuel sphérique montrant les points de capture et la position courante
class SphericalGuide extends StatelessWidget {
  final double currentAzimuth;
  final double currentElevation;
  final double targetAzimuth;
  final double targetElevation;
  final bool isNearTarget;
  final int totalTargets;
  final int capturedCount;
  final List<_TargetPoint> allTargets;

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
    return SizedBox(
      width: 220,
      height: 160,
      child: CustomPaint(
        painter: _SphericalGuidePainter(
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
    );
  }
}

class _TargetPoint {
  final double azimuth;
  final double elevation;

  const _TargetPoint({required this.azimuth, required this.elevation});
}

class _SphericalGuidePainter extends CustomPainter {
  final double currentAzimuth;
  final double currentElevation;
  final double targetAzimuth;
  final double targetElevation;
  final bool isNearTarget;
  final int totalTargets;
  final int capturedCount;
  final List<_TargetPoint> allTargets;

  _SphericalGuidePainter({
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
    // Représentation équirectangulaire miniature
    // X = azimut (0-360), Y = élévation (-90 à +90)
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Fond semi-transparent
    final bgPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;

    final rRect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    canvas.drawRRect(rRect, bgPaint);
    canvas.drawRRect(rRect, borderPaint);

    // Grille
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // Ligne horizontale (équateur)
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      gridPaint,
    );

    // Lignes verticales (tous les 90°)
    for (int i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Dessiner la position actuelle
    final currentX = (currentAzimuth / 360.0) * size.width;
    final currentY = (0.5 - currentElevation / 180.0) * size.height;

    // Cercle pulsant pour la position courante
    final currentPaint = Paint()
      ..color = isNearTarget ? Colors.greenAccent : Colors.cyan
      ..style = PaintingStyle.fill;

    final currentGlowPaint = Paint()
      ..color = (isNearTarget ? Colors.greenAccent : Colors.cyan).withValues(
        alpha: 0.3,
      )
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(
        currentX.clamp(6, size.width - 6),
        currentY.clamp(6, size.height - 6),
      ),
      10,
      currentGlowPaint,
    );
    canvas.drawCircle(
      Offset(
        currentX.clamp(6, size.width - 6),
        currentY.clamp(6, size.height - 6),
      ),
      5,
      currentPaint,
    );

    // Dessiner la cible
    final targetX = (targetAzimuth / 360.0) * size.width;
    final targetY = (0.5 - targetElevation / 180.0) * size.height;

    final targetPaint = Paint()
      ..color = isNearTarget ? Colors.greenAccent : Colors.orangeAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Crosshair pour la cible
    final tx = targetX.clamp(6.0, size.width - 6);
    final ty = targetY.clamp(6.0, size.height - 6);
    canvas.drawCircle(Offset(tx, ty), 8, targetPaint);
    canvas.drawLine(Offset(tx - 12, ty), Offset(tx + 12, ty), targetPaint);
    canvas.drawLine(Offset(tx, ty - 12), Offset(tx, ty + 12), targetPaint);

    // Flèche de direction si pas proche
    if (!isNearTarget) {
      _drawDirectionArrow(canvas, size, currentX, currentY, targetX, targetY);
    }
  }

  void _drawDirectionArrow(
    Canvas canvas,
    Size size,
    double fromX,
    double fromY,
    double toX,
    double toY,
  ) {
    // Trouver la direction vers la cible (en tenant compte du wrap-around)
    double dx = toX - fromX;
    if (dx > size.width / 2) dx -= size.width;
    if (dx < -size.width / 2) dx += size.width;
    double dy = toY - fromY;

    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 1) return;

    // Normaliser
    dx /= dist;
    dy /= dist;

    // Dessiner une petite flèche
    final arrowLength = 20.0;
    final fx = fromX.clamp(20.0, size.width - 20);
    final fy = fromY.clamp(20.0, size.height - 20);

    final tipX = fx + dx * arrowLength;
    final tipY = fy + dy * arrowLength;

    final arrowPaint = Paint()
      ..color = Colors.orangeAccent.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(tipX, tipY);
    path.lineTo(
      fx + dx * (arrowLength - 8) - dy * 5,
      fy + dy * (arrowLength - 8) + dx * 5,
    );
    path.lineTo(
      fx + dx * (arrowLength - 8) + dy * 5,
      fy + dy * (arrowLength - 8) - dx * 5,
    );
    path.close();
    canvas.drawPath(path, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _SphericalGuidePainter oldDelegate) {
    return oldDelegate.currentAzimuth != currentAzimuth ||
        oldDelegate.currentElevation != currentElevation ||
        oldDelegate.targetAzimuth != targetAzimuth ||
        oldDelegate.targetElevation != targetElevation ||
        oldDelegate.isNearTarget != isNearTarget ||
        oldDelegate.capturedCount != capturedCount;
  }
}

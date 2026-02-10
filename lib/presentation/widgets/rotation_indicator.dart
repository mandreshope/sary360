import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Widget d'indicateur de rotation circulaire
class RotationIndicator extends StatelessWidget {
  final double currentRotation;
  final double targetRotation;
  final bool isNearTarget;

  const RotationIndicator({
    super.key,
    required this.currentRotation,
    required this.targetRotation,
    required this.isNearTarget,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: CustomPaint(
        painter: _RotationPainter(
          currentRotation: currentRotation,
          targetRotation: targetRotation,
          isNearTarget: isNearTarget,
        ),
      ),
    );
  }
}

class _RotationPainter extends CustomPainter {
  final double currentRotation;
  final double targetRotation;
  final bool isNearTarget;

  _RotationPainter({
    required this.currentRotation,
    required this.targetRotation,
    required this.isNearTarget,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 20;

    // Dessiner le cercle de fond
    final backgroundPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius, backgroundPaint);

    // Dessiner la position cible
    final targetAngleRadians = (targetRotation - 90) * math.pi / 180;
    final targetPaint = Paint()
      ..color = isNearTarget ? Colors.greenAccent : Colors.orangeAccent
      ..style = PaintingStyle.fill;

    final targetX = center.dx + radius * math.cos(targetAngleRadians);
    final targetY = center.dy + radius * math.sin(targetAngleRadians);
    canvas.drawCircle(Offset(targetX, targetY), 12, targetPaint);

    // Dessiner la position actuelle (flèche)
    final currentAngleRadians = (currentRotation - 90) * math.pi / 180;
    final arrowPaint = Paint()
      ..color = isNearTarget ? Colors.greenAccent : Colors.white
      ..style = PaintingStyle.fill;

    final arrowPath = Path();
    final arrowTipX = center.dx + (radius + 15) * math.cos(currentAngleRadians);
    final arrowTipY = center.dy + (radius + 15) * math.sin(currentAngleRadians);
    final arrowBaseX =
        center.dx + (radius - 10) * math.cos(currentAngleRadians);
    final arrowBaseY =
        center.dy + (radius - 10) * math.sin(currentAngleRadians);

    final perpAngle = currentAngleRadians + math.pi / 2;
    final arrowWidth = 8.0;

    arrowPath.moveTo(arrowTipX, arrowTipY);
    arrowPath.lineTo(
      arrowBaseX + arrowWidth * math.cos(perpAngle),
      arrowBaseY + arrowWidth * math.sin(perpAngle),
    );
    arrowPath.lineTo(
      arrowBaseX - arrowWidth * math.cos(perpAngle),
      arrowBaseY - arrowWidth * math.sin(perpAngle),
    );
    arrowPath.close();

    canvas.drawPath(arrowPath, arrowPaint);

    // Dessiner le texte de l'angle au centre
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${currentRotation.abs().toInt()}°',
        style: TextStyle(
          color: isNearTarget ? Colors.greenAccent : Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(_RotationPainter oldDelegate) {
    return oldDelegate.currentRotation != currentRotation ||
        oldDelegate.targetRotation != targetRotation ||
        oldDelegate.isNearTarget != isNearTarget;
  }
}

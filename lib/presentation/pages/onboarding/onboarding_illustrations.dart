import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/constellation_colors.dart';

/// Base commune : un widget animé en boucle qui délègue le dessin à un
/// peintre paramétré par `t` ∈ [0, 1).
class _LoopingIllustration extends StatefulWidget {
  const _LoopingIllustration({
    required this.duration,
    required this.painterBuilder,
    required this.size,
  });

  final Duration duration;
  final double size;
  final CustomPainter Function(Animation<double> t, ConstellationColors c)
  painterBuilder;

  @override
  State<_LoopingIllustration> createState() => _LoopingIllustrationState();
}

class _LoopingIllustrationState extends State<_LoopingIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: widget.painterBuilder(_ctrl, context.colors),
        ),
      ),
    );
  }
}

/// Écran 1 — vue de dessus : l'utilisateur tourne sur lui-même, le cône de
/// visée balaie l'horizon et allume les étoiles une à une.
class TurnAroundIllustration extends StatelessWidget {
  const TurnAroundIllustration({super.key, this.size = 280});

  final double size;

  @override
  Widget build(BuildContext context) => _LoopingIllustration(
    size: size,
    duration: const Duration(seconds: 7),
    painterBuilder: (t, c) => _TurnAroundPainter(t, c),
  );
}

class _TurnAroundPainter extends CustomPainter {
  _TurnAroundPainter(this.t, this.c) : super(repaint: t);

  final Animation<double> t;
  final ConstellationColors c;

  static const int _starCount = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.shortestSide * 0.44;
    final arm = size.shortestSide * 0.17;

    // Rotation : 90 % du cycle pour faire le tour, 10 % de pause « complet ».
    final raw = t.value;
    final sweep = Curves.easeInOutSine.transform((raw / 0.9).clamp(0.0, 1.0));
    final theta = -math.pi / 2 + sweep * math.pi * 2;
    final fadeOut = raw > 0.9 ? 1 - (raw - 0.9) / 0.1 : 1.0;

    Offset polar(double a, double r) =>
        center + Offset(math.cos(a), math.sin(a)) * r;

    // Orbite pointillée.
    final dash = Paint()
      ..color = c.starDim.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    const dashes = 64;
    for (var i = 0; i < dashes; i += 2) {
      final a0 = i * 2 * math.pi / dashes, a1 = (i + 1) * 2 * math.pi / dashes;
      canvas.drawLine(polar(a0, outer), polar(a1, outer), dash);
    }

    // Cône de visée (dégradé d'accent).
    const halfFov = 0.42;
    final phone = polar(theta, arm);
    final cone = Path()
      ..moveTo(phone.dx, phone.dy)
      ..lineTo(
        polar(theta - halfFov, outer * 1.05).dx,
        polar(theta - halfFov, outer * 1.05).dy,
      )
      ..arcTo(
        Rect.fromCircle(center: center, radius: outer * 1.05),
        theta - halfFov,
        halfFov * 2,
        false,
      )
      ..close();
    canvas.drawPath(
      cone,
      Paint()
        ..shader = RadialGradient(
          colors: [
            c.accent.withValues(alpha: 0.35),
            c.accent.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: phone, radius: outer)),
    );

    // Étoiles de l'horizon : allumées une fois balayées par le cône.
    final swept = sweep * math.pi * 2;
    final starPos = <Offset>[];
    final lit = <double>[];
    for (var i = 0; i < _starCount; i++) {
      final rel = i * 2 * math.pi / _starCount;
      starPos.add(polar(-math.pi / 2 + rel, outer));
      lit.add(((swept - rel) / 0.35).clamp(0.0, 1.0) * fadeOut);
    }
    final line = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < _starCount; i++) {
      final j = (i + 1) % _starCount;
      final l = math.min(lit[i], lit[j]);
      if (l <= 0) continue;
      line.color = c.constellationLine.withValues(
        alpha: c.constellationLine.a * l,
      );
      canvas.drawLine(starPos[i], starPos[j], line);
    }
    _drawStars(canvas, starPos, lit, c);

    // Silhouette vue de dessus : épaules (ellipse) + tête, orientées vers θ.
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(theta + math.pi / 2);
    final body = Paint()..color = c.textSecondary.withValues(alpha: 0.5);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: arm * 1.5, height: arm * 0.6),
      body,
    );
    canvas.drawCircle(Offset.zero, arm * 0.28, Paint()..color = c.textPrimary);
    // Bras tendu jusqu'au téléphone.
    canvas.drawLine(
      Offset.zero,
      Offset(0, -arm),
      Paint()
        ..color = c.textSecondary.withValues(alpha: 0.5)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    // Téléphone (vu de dessus : fine barre perpendiculaire au bras).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(0, -arm), width: arm * 0.7, height: 5),
        const Radius.circular(3),
      ),
      Paint()..color = c.accent,
    );
    canvas.restore();

    // Flèche de rotation autour de la silhouette.
    final arrowR = arm * 0.62;
    final arrow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = c.accent.withValues(alpha: 0.8);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: arrowR),
      theta + 0.9,
      math.pi * 1.1,
      false,
      arrow,
    );
    final tipA = theta + 0.9 + math.pi * 1.1;
    final tip = polar(tipA, arrowR);
    final tangent = Offset(-math.sin(tipA), math.cos(tipA));
    final normal = Offset(math.cos(tipA), math.sin(tipA));
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(
          (tip - tangent * 6 + normal * 4).dx,
          (tip - tangent * 6 + normal * 4).dy,
        )
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(
          (tip - tangent * 6 - normal * 4).dx,
          (tip - tangent * 6 - normal * 4).dy,
        ),
      arrow,
    );
  }

  @override
  bool shouldRepaint(_TurnAroundPainter old) => old.c != c;
}

/// Écran 2 — vue de profil : le téléphone pivote autour de son objectif
/// (point fixe) pour viser les anneaux haut et bas.
class PivotIllustration extends StatelessWidget {
  const PivotIllustration({super.key, this.size = 280});

  final double size;

  @override
  Widget build(BuildContext context) => _LoopingIllustration(
    size: size,
    duration: const Duration(seconds: 6),
    painterBuilder: (t, c) => _PivotPainter(t, c),
  );
}

class _PivotPainter extends CustomPainter {
  _PivotPainter(this.t, this.c) : super(repaint: t);

  final Animation<double> t;
  final ConstellationColors c;

  /// Élévations des anneaux de capture (degrés), du nadir au zénith.
  static const List<double> _rings = [-90, -45, 0, 45, 90];

  @override
  void paint(Canvas canvas, Size size) {
    // Le pivot est décalé à gauche : le téléphone vise vers la droite.
    final pivot = Offset(size.width * 0.34, size.height / 2);
    final outer = size.shortestSide * 0.52;

    // Inclinaison sinusoïdale entre −80° et +80°.
    final phi = math.sin(t.value * math.pi * 2) * 80 * math.pi / 180;

    Offset polar(double elevRad, double r) =>
        pivot + Offset(math.cos(elevRad), -math.sin(elevRad)) * r;

    // Arc de visée pointillé.
    final dash = Paint()
      ..color = c.starDim.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    const steps = 40;
    for (var i = 0; i < steps; i += 2) {
      final a0 = -math.pi / 2 + i * math.pi / steps;
      final a1 = -math.pi / 2 + (i + 1) * math.pi / steps;
      canvas.drawLine(polar(a0, outer), polar(a1, outer), dash);
    }

    // Cône de visée.
    const halfFov = 0.36;
    final cone = Path()
      ..moveTo(pivot.dx, pivot.dy)
      ..lineTo(
        polar(phi + halfFov, outer * 1.05).dx,
        polar(phi + halfFov, outer * 1.05).dy,
      )
      ..lineTo(
        polar(phi - halfFov, outer * 1.05).dx,
        polar(phi - halfFov, outer * 1.05).dy,
      )
      ..close();
    canvas.drawPath(
      cone,
      Paint()
        ..shader = RadialGradient(
          colors: [
            c.accent.withValues(alpha: 0.4),
            c.accent.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: pivot, radius: outer)),
    );

    // Étoiles des anneaux : brillent quand le cône les vise.
    final pos = <Offset>[];
    final lit = <double>[];
    for (final e in _rings) {
      final er = e * math.pi / 180;
      pos.add(polar(er, outer));
      lit.add((1 - (phi - er).abs() / 0.5).clamp(0.0, 1.0));
    }
    _drawStars(canvas, pos, lit, c);

    // Téléphone vu de profil, tournant autour de l'objectif.
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(-phi);
    final phoneRect = Rect.fromLTWH(-11, -62, 11, 110);
    canvas.drawRRect(
      RRect.fromRectAndRadius(phoneRect, const Radius.circular(5)),
      Paint()..color = c.textSecondary.withValues(alpha: 0.75),
    );
    // Objectif : sur la face arrière, aligné sur le pivot.
    canvas.drawCircle(const Offset(-1, 0), 3.5, Paint()..color = c.accent);
    canvas.restore();

    // Pivot : anneau pulsant indiquant le point qui ne bouge pas.
    final pulse = (t.value * 2) % 1.0;
    canvas.drawCircle(
      pivot,
      8 + pulse * 18,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = c.accent.withValues(alpha: 0.6 * (1 - pulse)),
    );
    final cross = Paint()
      ..color = c.accent
      ..strokeWidth = 1.2;
    canvas.drawLine(
      pivot - const Offset(6, 0),
      pivot + const Offset(6, 0),
      cross,
    );
    canvas.drawLine(
      pivot - const Offset(0, 6),
      pivot + const Offset(0, 6),
      cross,
    );
  }

  @override
  bool shouldRepaint(_PivotPainter old) => old.c != c;
}

/// Dessin partagé des étoiles : point + halo proportionnel à l'allumage.
void _drawStars(
  Canvas canvas,
  List<Offset> positions,
  List<double> lit,
  ConstellationColors c,
) {
  final glow = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
  final dot = Paint();
  for (var i = 0; i < positions.length; i++) {
    final l = lit[i];
    if (l > 0) {
      glow.color = c.accent.withValues(alpha: 0.75 * l);
      canvas.drawCircle(positions[i], 6 + 3 * l, glow);
    }
    dot.color = Color.lerp(c.starDim, c.star, l)!;
    canvas.drawCircle(positions[i], 2.2 + 1.6 * l, dot);
  }
}

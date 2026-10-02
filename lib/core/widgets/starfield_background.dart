import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/constellation_colors.dart';

/// Fond étoilé animé : étoiles scintillantes qui dérivent lentement.
///
/// Les étoiles sont générées une seule fois (graine fixe) puis animées par un
/// unique [AnimationController] ; le peintre est isolé dans un
/// [RepaintBoundary] pour ne pas redessiner le reste de l'écran.
class StarfieldBackground extends StatefulWidget {
  const StarfieldBackground({super.key, this.starCount = 140, this.child});

  final int starCount;
  final Widget? child;

  @override
  State<StarfieldBackground> createState() => _StarfieldBackgroundState();
}

class _StarfieldBackgroundState extends State<StarfieldBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  )..repeat();

  late final List<_Star> _stars = _generate(widget.starCount);

  static List<_Star> _generate(int count) {
    final rnd = math.Random(360);
    return List.generate(count, (_) {
      return _Star(
        x: rnd.nextDouble(),
        y: rnd.nextDouble(),
        // Majorité de petites étoiles, quelques-unes plus brillantes.
        radius: 0.4 + math.pow(rnd.nextDouble(), 3) * 1.6,
        phase: rnd.nextDouble() * math.pi * 2,
        speed: 2 + rnd.nextDouble() * 6,
        depth: 0.2 + rnd.nextDouble() * 0.8,
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        // Halo diffus de l'accent en haut de l'écran, comme une nébuleuse.
        gradient: RadialGradient(
          center: const Alignment(0.4, -0.9),
          radius: 1.3,
          colors: [c.accentSoft, c.background],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: _StarfieldPainter(
                stars: _stars,
                animation: _ctrl,
                color: c.star,
              ),
            ),
          ),
          if (widget.child != null) widget.child!,
        ],
      ),
    );
  }
}

class _Star {
  const _Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.phase,
    required this.speed,
    required this.depth,
  });

  final double x, y, radius, phase, speed, depth;
}

class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter({
    required this.stars,
    required this.animation,
    required this.color,
  }) : super(repaint: animation);

  final List<_Star> stars;
  final Animation<double> animation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final paint = Paint();
    for (final s in stars) {
      // Dérive horizontale lente, plus rapide pour les étoiles « proches ».
      final x = ((s.x + t * 0.05 * s.depth) % 1.0) * size.width;
      final y = s.y * size.height;
      final twinkle =
          0.55 + 0.45 * math.sin(t * math.pi * 2 * s.speed + s.phase);
      paint.color = color.withValues(alpha: (0.15 + 0.6 * twinkle) * s.depth);
      canvas.drawCircle(Offset(x, y), s.radius, paint);
    }
  }

  @override
  bool shouldRepaint(_StarfieldPainter old) =>
      old.color != color || old.stars != stars;
}

// Génère les images sources de l'icône de l'application (thème
// « Constellation ») dans assets/icon/.
//
// Commande : flutter test tool/icon/render_icon_test.dart
// Puis : dart run flutter_launcher_icons
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sary360/core/math/vec3.dart';

const _size = 1024.0;
const _night = Color(0xFF07080C);
const _cyan = Color(0xFF2EE6FF);
const _star = Color(0xFFF2F4FF);

/// Variante de rendu de l'icône.
enum IconVariant {
  /// Icône complète (iOS, Android ancien format) : fond + sphère.
  full,

  /// Premier plan de l'icône adaptative Android : sphère seule, réduite
  /// pour tenir dans la zone visible après masquage.
  foreground,

  /// Icône monochrome (icônes à thème d'Android 13+) : silhouette blanche.
  monochrome,
}

class IconPainter extends CustomPainter {
  IconPainter(this.variant);

  final IconVariant variant;

  // Orientation de la sphère : légère rotation et inclinaison pour voir le
  // pôle supérieur.
  static const double _yaw = 0.55;
  static const double _tilt = -0.42;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = size.center(Offset.zero);
    final mono = variant == IconVariant.monochrome;
    // Icône adaptative : flutter_launcher_icons insère le premier plan avec
    // une marge de 16 % (échelle 0,68). Un rayon de 0,34 donne ≈ 0,23 une
    // fois affiché, dans la zone visible après masquage (≈ 0,30).
    final radius = s * (variant == IconVariant.full ? 0.30 : 0.34);
    final haloFactor = variant == IconVariant.full ? 1.55 : 1.3;
    final lineColor = mono ? Colors.white : _cyan;

    if (variant == IconVariant.full) _paintBackground(canvas, size);

    Vec3 xf(Vec3 p) => p.rotateY(_yaw).rotateX(_tilt);
    Offset proj(Vec3 p) => center + Offset(p.x * radius, -p.y * radius);
    double front(double z) => ((z + 1) / 2).clamp(0.0, 1.0);

    if (!mono) {
      // Halo lumineux autour de la sphère.
      canvas.drawCircle(
        center,
        radius * haloFactor,
        Paint()
          ..shader =
              RadialGradient(
                colors: [
                  _cyan.withValues(alpha: 0.30),
                  _cyan.withValues(alpha: 0.08),
                  _cyan.withValues(alpha: 0),
                ],
                stops: const [0.45, 0.7, 1],
              ).createShader(
                Rect.fromCircle(center: center, radius: radius * haloFactor),
              ),
      );
      // Volume : la sphère est éclairée par le haut à gauche.
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.45, -0.5),
            radius: 1.1,
            colors: [
              const Color(0xFF1A3C48),
              const Color(0xFF0B1820),
              _night.withValues(alpha: 0.9),
            ],
            stops: const [0, 0.55, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    // Grille : parallèles et méridiens, la face arrière estompée.
    // Extrémités droites en couleur : des extrémités rondes se
    // chevaucheraient entre segments et donneraient un effet pointillé
    // (transparence cumulée). En monochrome (opaque), les rondes évitent les
    // dents sur les traits épais.
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = mono ? StrokeCap.round : StrokeCap.butt
      ..strokeWidth = s * (mono ? 0.012 : 0.0055);
    void polyline(List<Vec3> pts) {
      for (var i = 0; i < pts.length - 1; i++) {
        final a = xf(pts[i]), b = xf(pts[i + 1]);
        final f = front((a.z + b.z) / 2);
        if (mono && f < 0.5) continue; // monochrome : face avant seulement
        grid.color = lineColor.withValues(alpha: mono ? 1 : 0.10 + 0.50 * f);
        canvas.drawLine(proj(a), proj(b), grid);
      }
    }

    const seg = 96;
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

    // Contour de la sphère.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * (mono ? 0.016 : 0.008)
        ..color = mono ? Colors.white : _cyan.withValues(alpha: 0.85),
    );

    // Constellation : étoiles sur la face visible, reliées par des lignes.
    final stars = [
      for (final (az, el) in const [
        (-0.95, 0.55),
        (-0.45, 0.20),
        (0.05, 0.45),
        (0.35, 0.0),
        (-0.15, -0.40),
        (0.55, -0.45),
        (0.85, 0.30),
      ])
        proj(xf(Vec3.fromSpherical(az - _yaw, el))),
    ];
    const links = [
      (0, 1),
      (1, 2),
      (2, 6),
      (1, 3),
      (3, 6),
      (3, 5),
      (4, 5),
      (1, 4),
    ];
    final link = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * (mono ? 0.014 : 0.0075)
      ..color = mono ? Colors.white : _star.withValues(alpha: 0.9);
    if (!mono) {
      final glow = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = s * 0.022
        ..color = _cyan.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.012);
      for (final (a, b) in links) {
        canvas.drawLine(stars[a], stars[b], glow);
      }
    }
    for (final (a, b) in links) {
      canvas.drawLine(stars[a], stars[b], link);
    }
    for (var i = 0; i < stars.length; i++) {
      final r = s * (i == 3 ? 0.028 : 0.017);
      if (!mono) {
        canvas.drawCircle(
          stars[i],
          r * 2.6,
          Paint()
            ..color = _cyan.withValues(alpha: 0.55)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 1.6),
        );
      }
      canvas.drawCircle(
        stars[i],
        r,
        Paint()..color = mono ? Colors.white : _star,
      );
    }

    // Étoile scintillante : la cible en cours de capture.
    final sparkle = stars[3];
    _paintSparkle(
      canvas,
      sparkle,
      s * 0.075,
      mono ? Colors.white : _star,
      mono,
    );
  }

  void _paintBackground(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0.25, -0.35),
          radius: 1.1,
          colors: [Color(0xFF13222C), Color(0xFF0A0F16), _night],
          stops: [0, 0.55, 1],
        ).createShader(rect),
    );
    // Petites étoiles d'arrière-plan (graine fixe).
    final rnd = math.Random(360);
    final dot = Paint();
    for (var i = 0; i < 70; i++) {
      final p = Offset(
        rnd.nextDouble() * size.width,
        rnd.nextDouble() * size.height,
      );
      final d = (p - size.center(Offset.zero)).distance / size.width;
      if (d < 0.36) continue; // pas d'étoiles derrière la sphère
      dot.color = _star.withValues(alpha: 0.15 + rnd.nextDouble() * 0.45);
      canvas.drawCircle(
        p,
        size.width * (0.0015 + rnd.nextDouble() * 0.003),
        dot,
      );
    }
  }

  /// Étoile à quatre branches avec halo.
  void _paintSparkle(
    Canvas canvas,
    Offset c,
    double r,
    Color color,
    bool mono,
  ) {
    if (!mono) {
      canvas.drawCircle(
        c,
        r * 0.9,
        Paint()
          ..color = _cyan.withValues(alpha: 0.5)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.5),
      );
    }
    final path = Path();
    const k = 0.16; // finesse des branches
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2 - math.pi / 2;
      final tip = c + Offset(math.cos(a), math.sin(a)) * r;
      final side =
          c +
          Offset(math.cos(a + math.pi / 4), math.sin(a + math.pi / 4)) * r * k;
      if (i == 0) {
        path.moveTo(tip.dx, tip.dy);
      } else {
        path.lineTo(tip.dx, tip.dy);
      }
      path.lineTo(side.dx, side.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(IconPainter old) => old.variant != variant;
}

Future<void> _render(
  WidgetTester tester,
  IconVariant variant,
  String path,
) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Center(
      child: RepaintBoundary(
        key: key,
        child: SizedBox.square(
          dimension: _size,
          child: CustomPaint(painter: IconPainter(variant)),
        ),
      ),
    ),
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets('génère les images de l\'icône', (tester) async {
    tester.view.physicalSize = const Size(_size, _size);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _render(tester, IconVariant.full, 'assets/icon/icon.png');
    await _render(
      tester,
      IconVariant.foreground,
      'assets/icon/icon_foreground.png',
    );
    await _render(
      tester,
      IconVariant.monochrome,
      'assets/icon/icon_monochrome.png',
    );
  });
}

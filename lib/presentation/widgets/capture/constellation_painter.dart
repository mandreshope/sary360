import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/math/screen_projection.dart';
import '../../../core/math/vec3.dart';
import '../../../core/theme/constellation_colors.dart';
import '../../../domain/capture/capture_session.dart';
import '../../../domain/models/captured_photo.dart';
import '../../viewmodels/capture_viewmodel.dart';

/// Scène de capture dessinée par-dessus l'aperçu caméra : photos déjà prises
/// plaquées sur la sphère, constellation qui se dessine au fil des captures,
/// étoiles cibles, réticule et flèche de guidage.
class ConstellationPainter extends CustomPainter {
  ConstellationPainter({
    required this.frame,
    required this.pulse,
    required this.session,
    required this.photos,
    required this.thumbnails,
    required this.hFov,
    required this.vFov,
    required this.previewAspect,
    required this.colors,
  }) : super(repaint: Listenable.merge([frame, pulse]));

  final ValueNotifier<CaptureFrame> frame;

  /// Animation en boucle (0..1) pour le scintillement des étoiles.
  final Animation<double> pulse;
  final CaptureSession session;
  final Map<int, CapturedPhoto> photos;
  final Map<int, ui.Image> thumbnails;
  final double hFov;
  final double vFov;
  final double previewAspect;
  final ConstellationColors colors;

  /// Rayon du réticule (pixels logiques).
  static const double reticleRadius = 38;

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame.value;
    final q = f.orientation;
    if (q == null || session.referenceHeading == null) {
      _paintReticle(canvas, size, f);
      return;
    }
    final projection = ScreenProjection(
      deviceToWorld: q,
      size: size,
      focal: ScreenProjection.focalFor(
        size: size,
        previewAspect: previewAspect,
        hFovDeg: hFov,
        vFovDeg: vFov,
      ),
    );

    _paintPhotos(canvas, projection);
    _paintConstellation(canvas, projection, f);
    _paintGuide(canvas, size, projection, f);
    _paintReticle(canvas, size, f);
  }

  /// Vignettes des photos prises, en perspective : chaque photo est
  /// découpée en une grille de 5 × 5 sommets projetés (pour suivre la
  /// courbure), puis texturée avec sa vignette.
  void _paintPhotos(Canvas canvas, ScreenProjection projection) {
    const n = 4; // cellules par côté
    final paint = Paint()..color = const Color(0xE6000000);
    for (final entry in photos.entries) {
      final image = thumbnails[entry.key];
      if (image == null) continue;
      final photo = entry.value;
      final m = photo.orientation.toRotationMatrix();
      final th = math.tan((photo.hFov ?? hFov) * math.pi / 360);
      final tv = math.tan((photo.vFov ?? vFov) * math.pi / 360);

      final points = List<Offset?>.filled((n + 1) * (n + 1), null);
      for (var j = 0; j <= n; j++) {
        for (var i = 0; i <= n; i++) {
          final u = -1 + 2 * i / n, v = -1 + 2 * j / n;
          // Rayon caméra (x droite, y bas, z visée) → appareil → monde.
          final world = rotate(m, Vec3(u * th, -v * tv, -1));
          points[j * (n + 1) + i] = projection.project(world.normalized());
        }
      }

      final positions = <double>[];
      final texcoords = <double>[];
      void vertex(int i, int j) {
        final p = points[j * (n + 1) + i]!;
        positions.addAll([p.dx, p.dy]);
        texcoords.addAll([image.width * i / n, image.height * j / n]);
      }

      for (var j = 0; j < n; j++) {
        for (var i = 0; i < n; i++) {
          final corners = [
            points[j * (n + 1) + i],
            points[j * (n + 1) + i + 1],
            points[(j + 1) * (n + 1) + i],
            points[(j + 1) * (n + 1) + i + 1],
          ];
          if (corners.any((c) => c == null)) continue;
          vertex(i, j);
          vertex(i + 1, j);
          vertex(i, j + 1);
          vertex(i + 1, j);
          vertex(i + 1, j + 1);
          vertex(i, j + 1);
        }
      }
      if (positions.isEmpty) continue;
      final vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        Float32List.fromList(positions),
        textureCoordinates: Float32List.fromList(texcoords),
      );
      paint.shader = ImageShader(
        image,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.identity().storage,
      );
      canvas.drawVertices(vertices, BlendMode.srcOver, paint);
      vertices.dispose();
    }
  }

  void _paintConstellation(
    Canvas canvas,
    ScreenProjection projection,
    CaptureFrame f,
  ) {
    final positions = <int, Offset>{};
    for (final t in session.targets) {
      final d = session.directionOf(t);
      final p = d == null ? null : projection.project(d);
      if (p != null) positions[t.index] = p;
    }

    // Lignes : pâles entre étoiles restantes, lumineuses une fois les deux
    // extrémités capturées.
    final faint = Paint()
      ..strokeWidth = 1
      ..color = colors.star.withValues(alpha: 0.12);
    final bright = Paint()
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = colors.accent.withValues(alpha: 0.8);
    for (final (a, b) in session.edges) {
      final pa = positions[a], pb = positions[b];
      if (pa == null || pb == null) continue;
      final lit = session.captured.contains(a) && session.captured.contains(b);
      canvas.drawLine(pa, pb, lit ? bright : faint);
    }

    // Étoiles.
    final t = pulse.value * 2 * math.pi;
    final glow = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final dot = Paint();
    for (final target in session.targets) {
      final p = positions[target.index];
      if (p == null) continue;
      final captured = session.captured.contains(target.index);
      final isSuggestion = f.suggestion?.index == target.index;
      if (captured) {
        dot.color = colors.accent;
        canvas.drawCircle(p, 4, dot);
        continue;
      }
      // Pulsation décalée par étoile.
      final beat = 0.5 + 0.5 * math.sin(t + target.index * 0.9);
      final radius = (isSuggestion ? 9.0 : 5.0) + 2 * beat;
      glow.color = colors.accent.withValues(
        alpha: (isSuggestion ? 0.7 : 0.35) * (0.6 + 0.4 * beat),
      );
      canvas.drawCircle(p, radius * 1.8, glow);
      dot.color = colors.star;
      canvas.drawCircle(p, radius * 0.55, dot);
    }
  }

  /// Flèche au bord de l'écran vers la cible suggérée quand elle est hors
  /// champ.
  void _paintGuide(
    Canvas canvas,
    Size size,
    ScreenProjection projection,
    CaptureFrame f,
  ) {
    final target = f.suggestion;
    if (target == null || f.activeTarget != null) return;
    final d = session.directionOf(target);
    if (d == null) return;
    final p = projection.project(d);
    final margin = 48.0;
    final visible =
        p != null &&
        p.dx > margin &&
        p.dx < size.width - margin &&
        p.dy > margin &&
        p.dy < size.height - margin;
    if (visible) return;

    final dir = projection.directionTo(d);
    final center = size.center(Offset.zero);
    // Point sur l'ellipse inscrite dans l'écran, dans la direction voulue.
    final rx = size.width / 2 - margin, ry = size.height / 2 - margin * 2.5;
    final angle = math.atan2(dir.dy, dir.dx);
    final pos = center + Offset(math.cos(angle) * rx, math.sin(angle) * ry);

    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(angle);
    final path = Path()
      ..moveTo(14, 0)
      ..lineTo(-8, -10)
      ..lineTo(-3, 0)
      ..lineTo(-8, 10)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = colors.accent.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(path, Paint()..color = colors.accent);
    canvas.restore();
  }

  /// Réticule : anneau fin, arc qui se remplit pendant la stabilisation.
  void _paintReticle(Canvas canvas, Size size, CaptureFrame f) {
    final center = size.center(Offset.zero);
    final active = f.activeTarget != null;
    final warn = f.tooFast || f.tilted;
    final ringColor = warn
        ? colors.warning
        : active
        ? colors.accent
        : Colors.white.withValues(alpha: 0.85);
    canvas.drawCircle(
      center,
      reticleRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = ringColor,
    );
    if (f.stability > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: reticleRadius),
        -math.pi / 2,
        2 * math.pi * f.stability,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = colors.accent,
      );
    }
    // Repère central.
    canvas.drawCircle(center, 2.5, Paint()..color = ringColor);
  }

  @override
  bool shouldRepaint(ConstellationPainter old) =>
      old.session != session ||
      old.colors != colors ||
      old.hFov != hFov ||
      old.previewAspect != previewAspect;
}

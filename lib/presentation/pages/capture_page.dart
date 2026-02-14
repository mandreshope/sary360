import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';

import '../viewmodels/capture_viewmodel.dart';
import '../widgets/progress_indicator.dart';
import '../widgets/spherical_guide.dart';
import '../widgets/capture_button.dart';
import 'viewer_page.dart';

class CapturePage extends ConsumerStatefulWidget {
  const CapturePage({super.key});

  @override
  ConsumerState<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends ConsumerState<CapturePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(captureViewModelProvider.notifier).initializeCapture();
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = ref.watch(captureViewModelProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: _buildBody(context, viewModel)),
    );
  }

  Widget _buildBody(BuildContext context, CaptureViewState viewModel) {
    switch (viewModel.state) {
      case CaptureState.initializing:
        return _buildInitializingView();

      case CaptureState.completed:
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (viewModel.completedPanorama != null) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) =>
                    ViewerPage(panorama: viewModel.completedPanorama!),
              ),
            );
          }
        });
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );

      case CaptureState.error:
        return _buildErrorView(context, viewModel);

      case CaptureState.stitching:
        return _buildStitchingView(viewModel);

      case CaptureState.ready:
      case CaptureState.capturing:
        return _buildCaptureView(context, viewModel);

      default:
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
    }
  }

  Widget _buildInitializingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.cyanAccent),
          SizedBox(height: 24),
          Text(
            'Initialisation de la caméra...',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            'Calibration des capteurs',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureView(BuildContext context, CaptureViewState viewModel) {
    final cameraService = ref
        .read(captureViewModelProvider.notifier)
        .cameraService;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Aperçu caméra
        if (cameraService.isInitialized)
          ClipRect(
            child: OverflowBox(
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: cameraService.controller!.value.previewSize!.height,
                  height: cameraService.controller!.value.previewSize!.width,
                  child: CameraPreview(cameraService.controller!),
                ),
              ),
            ),
          ),

        // Overlay sombre en haut et bas
        _buildGradientOverlay(),

        // Bouton fermer
        Positioned(
          top: 16,
          left: 16,
          child: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: Colors.white, size: 28),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black45,
              shape: const CircleBorder(),
            ),
          ),
        ),

        // Instructions en haut
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: Center(child: _buildInstructionBadge(viewModel)),
        ),

        // Guide sphérique en haut à droite
        Positioned(
          top: 60,
          right: 16,
          child: SphericalGuide(
            currentAzimuth: viewModel.currentAzimuth,
            currentElevation: viewModel.currentElevation,
            targetAzimuth: viewModel.targetAzimuth,
            targetElevation: viewModel.targetElevation,
            isNearTarget: viewModel.isNearTarget,
            totalTargets: viewModel.totalTargets,
            capturedCount: viewModel.capturedPhotos.length,
          ),
        ),

        // Réticule central
        Center(child: _buildReticle(viewModel.isNearTarget)),

        // Indicateur d'élévation à gauche
        Positioned(
          left: 16,
          top: 0,
          bottom: 0,
          child: Center(child: _buildElevationIndicator(viewModel)),
        ),

        // Progression en bas
        Positioned(
          bottom: 120,
          left: 0,
          right: 0,
          child: Center(
            child: PanoramaProgressIndicator(
              current: viewModel.capturedPhotos.length,
              total: viewModel.totalTargets,
              rowLabel: viewModel.currentRowLabel,
              elevation: viewModel.targetElevation,
            ),
          ),
        ),

        // Bouton de capture (ou indicateur pendant la capture)
        Positioned(
          bottom: 30,
          left: 0,
          right: 0,
          child: Center(
            child: viewModel.state == CaptureState.capturing
                ? Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.5),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 3,
                      ),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.cyanAccent,
                        ),
                      ),
                    ),
                  )
                : CaptureButton(
                    enabled: viewModel.canCapture,
                    onPressed: () {
                      ref
                          .read(captureViewModelProvider.notifier)
                          .captureCurrentTarget();
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildGradientOverlay() {
    return Column(
      children: [
        Container(
          height: 100,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
            ),
          ),
        ),
        const Spacer(),
        Container(
          height: 200,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInstructionBadge(CaptureViewState viewModel) {
    final String instruction;
    final Color color;

    if (viewModel.isNearTarget) {
      instruction = '✅ Appuyez pour capturer !';
      color = Colors.greenAccent;
    } else {
      // Calculer la direction
      double azDiff = viewModel.targetAzimuth - viewModel.currentAzimuth;
      if (azDiff > 180) azDiff -= 360;
      if (azDiff < -180) azDiff += 360;

      final elDiff = viewModel.targetElevation - viewModel.currentElevation;

      final parts = <String>[];
      if (azDiff.abs() > 10) {
        parts.add(azDiff > 0 ? '→ Tournez à droite' : '← Tournez à gauche');
      }
      if (elDiff.abs() > 10) {
        parts.add(
          elDiff > 0 ? '↓ Inclinez vers le bas' : '↑ Inclinez vers le haut',
        );
      }

      instruction = parts.isEmpty ? 'Alignez le réticule' : parts.join('  •  ');
      color = Colors.orangeAccent;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Text(
        instruction,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildReticle(bool isNearTarget) {
    final color = isNearTarget ? Colors.greenAccent : Colors.white;
    return SizedBox(
      width: 80,
      height: 80,
      child: CustomPaint(
        painter: _ReticlePainter(color: color, isNear: isNearTarget),
      ),
    );
  }

  Widget _buildElevationIndicator(CaptureViewState viewModel) {
    return Container(
      width: 40,
      height: 200,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: CustomPaint(
        painter: _ElevationPainter(
          currentElevation: viewModel.currentElevation,
          targetElevation: viewModel.targetElevation,
          isNear: viewModel.isNearTarget,
        ),
      ),
    );
  }

  Widget _buildStitchingView(CaptureViewState viewModel) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icône animée
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(seconds: 2),
              builder: (context, value, child) {
                return Transform.rotate(angle: value * 6.28, child: child);
              },
              child: const Icon(
                Icons.panorama_photosphere,
                size: 64,
                color: Colors.cyanAccent,
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Assemblage sphérique en cours...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${viewModel.capturedPhotos.length} photos capturées',
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 250,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: viewModel.stitchingProgress,
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Colors.cyanAccent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${(viewModel.stitchingProgress * 100).toInt()}%',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(BuildContext context, CaptureViewState viewModel) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
            const SizedBox(height: 24),
            const Text(
              'Erreur',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              viewModel.errorMessage ?? 'Une erreur est survenue',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                ref.read(captureViewModelProvider.notifier).reset();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Réticule au centre de l'écran
class _ReticlePainter extends CustomPainter {
  final Color color;
  final bool isNear;

  _ReticlePainter({required this.color, required this.isNear});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = isNear ? 2.5 : 1.5;

    // Cercle
    canvas.drawCircle(center, 20, paint);

    // Croix
    final gap = 8.0;
    final len = 16.0;
    // Haut
    canvas.drawLine(
      Offset(center.dx, center.dy - gap),
      Offset(center.dx, center.dy - gap - len),
      paint,
    );
    // Bas
    canvas.drawLine(
      Offset(center.dx, center.dy + gap),
      Offset(center.dx, center.dy + gap + len),
      paint,
    );
    // Gauche
    canvas.drawLine(
      Offset(center.dx - gap, center.dy),
      Offset(center.dx - gap - len, center.dy),
      paint,
    );
    // Droite
    canvas.drawLine(
      Offset(center.dx + gap, center.dy),
      Offset(center.dx + gap + len, center.dy),
      paint,
    );

    // Point central quand aligné
    if (isNear) {
      final dotPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_ReticlePainter old) =>
      old.color != color || old.isNear != isNear;
}

/// Indicateur d'élévation vertical
class _ElevationPainter extends CustomPainter {
  final double currentElevation;
  final double targetElevation;
  final bool isNear;

  _ElevationPainter({
    required this.currentElevation,
    required this.targetElevation,
    required this.isNear,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Mapper l'élévation (-90 à +90) sur la hauteur
    final currentY = (0.5 - currentElevation / 180.0) * size.height;
    final targetY = (0.5 - targetElevation / 180.0) * size.height;

    // Ligne centrale
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(size.width / 2, 10),
      Offset(size.width / 2, size.height - 10),
      linePaint,
    );

    // Marqueurs -90, 0, +90
    final textPaint = Paint()..color = Colors.white.withValues(alpha: 0.5);
    final textStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.5),
      fontSize: 8,
    );

    for (final angle in [-60, 0, 60]) {
      final y = (0.5 - angle / 180.0) * size.height;
      canvas.drawCircle(Offset(size.width / 2, y), 2, textPaint);

      final textPainter = TextPainter(
        text: TextSpan(text: '$angle°', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(
          size.width / 2 - textPainter.width / 2,
          y.clamp(10, size.height - 20) + 4,
        ),
      );
    }

    // Cible
    final targetPaint = Paint()
      ..color = isNear ? Colors.greenAccent : Colors.orangeAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(4, targetY.clamp(10.0, size.height - 10)),
      Offset(size.width - 4, targetY.clamp(10.0, size.height - 10)),
      targetPaint,
    );

    // Position courante
    final currentPaint = Paint()
      ..color = isNear ? Colors.greenAccent : Colors.cyan
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width / 2, currentY.clamp(10.0, size.height - 10)),
      6,
      currentPaint,
    );
  }

  @override
  bool shouldRepaint(_ElevationPainter old) =>
      old.currentElevation != currentElevation ||
      old.targetElevation != targetElevation ||
      old.isNear != isNear;
}

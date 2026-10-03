import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';

import '../viewmodels/capture_viewmodel.dart';
import '../widgets/progress_indicator.dart';
import '../widgets/spherical_guide.dart';

import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';

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
            context.pushReplacement(
              AppRoutes.viewer,
              extra: viewModel.completedPanorama!,
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
            onPressed: () => context.pop(),
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

        // Guide sphérique 3D en haut à droite
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
            allTargets: viewModel.allTargetPoints,
          ),
        ),

        // Cadre rectangulaire flottant + point blanc (cible)
        _buildTargetFramePreview(context, viewModel),

        // Cercle central fixe d'alignement
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

        // Indicateur de capture automatique (pas de bouton)
        Positioned(
          bottom: 30,
          left: 0,
          right: 0,
          child: Center(child: _buildAutoCaptureIndicator(viewModel)),
        ),
      ],
    );
  }

  /// Indicateur de capture automatique
  /// Montre l'état : en cours de capture, aligné (prêt), ou en attente d'alignement
  Widget _buildAutoCaptureIndicator(CaptureViewState viewModel) {
    if (viewModel.state == CaptureState.capturing) {
      // Capture en cours — spinner
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.5),
          border: Border.all(
            color: Colors.greenAccent.withValues(alpha: 0.6),
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.greenAccent.withValues(alpha: 0.3),
              blurRadius: 20,
              spreadRadius: 4,
            ),
          ],
        ),
        child: const Center(
          child: SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Colors.greenAccent,
            ),
          ),
        ),
      );
    }

    if (viewModel.isNearTarget) {
      // Aligné et stabilisation en cours — cercle vert pulsant
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.8, end: 1.0),
        duration: const Duration(milliseconds: 400),
        builder: (context, scale, child) {
          return Transform.scale(
            scale: scale,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.greenAccent.withValues(alpha: 0.15),
                border: Border.all(color: Colors.greenAccent, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.greenAccent.withValues(alpha: 0.4),
                    blurRadius: 25,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check, color: Colors.greenAccent, size: 28),
                  Text(
                    'STABLE',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    // En attente d'alignement — indicateur auto-capture
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.4),
        border: Border.all(
          color: Colors.cyanAccent.withValues(alpha: 0.4),
          width: 2,
        ),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.adjust, color: Colors.cyanAccent, size: 28),
          Text(
            'AUTO',
            style: TextStyle(
              color: Colors.cyanAccent,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetFramePreview(
    BuildContext context,
    CaptureViewState viewModel,
  ) {
    if (viewModel.state == CaptureState.capturing) {
      return const SizedBox.shrink();
    }

    double azDiff = viewModel.targetAzimuth - viewModel.currentAzimuth;
    if (azDiff > 180) azDiff -= 360;
    if (azDiff < -180) azDiff += 360;

    final elDiff = viewModel.targetElevation - viewModel.currentElevation;

    // Facteur d'échelle (à ajuster selon la FoV de la caméra)
    const pixelPerDegree = 15.0;

    final dx = azDiff * pixelPerDegree;
    final dy = -elDiff * pixelPerDegree;

    final isNear = viewModel.isNearTarget;
    final color = isNear ? Colors.greenAccent : Colors.white;

    return Center(
      child: Transform.translate(
        offset: Offset(dx, dy),
        child: Container(
          // Représente le champ de vision approximatif de la photo cible
          width: 220,
          height: 300,
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
            borderRadius: BorderRadius.circular(16),
            color: color.withValues(alpha: 0.05),
          ),
          child: Center(
            // Le point central cible que l'utilisateur doit superposer au réticule central
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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

    if (viewModel.state == CaptureState.capturing) {
      instruction = '📸 Capture en cours...';
      color = Colors.greenAccent;
    } else if (viewModel.isNearTarget) {
      instruction = '✅ Stabilisé — capture auto !';
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
          elDiff > 0 ? '↑ Inclinez vers le haut' : '↓ Inclinez vers le bas',
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
      height: 260,
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
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(captureViewModelProvider.notifier).cancelStitching(),
              icon: const Icon(Icons.close_rounded),
              label: const Text('Annuler'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
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

/// Cercle central fixe d'alignement
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
      ..strokeWidth = isNear ? 3.0 : 2.0;

    // Un grand cercle au centre
    canvas.drawCircle(center, 30, paint);
  }

  @override
  bool shouldRepaint(_ReticlePainter old) =>
      old.color != color || old.isNear != isNear;
}

/// Indicateur d'élévation vertical - couvre -90° à +90°
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
    final padding = 12.0;
    final usableHeight = size.height - 2 * padding;

    // Mapper l'élévation (-90 à +90) sur la hauteur
    // +90° (zénith) = haut, -90° (nadir) = bas
    double elevationToY(double el) {
      return padding + (0.5 - el / 180.0) * usableHeight;
    }

    final currentY = elevationToY(currentElevation);
    final targetY = elevationToY(targetElevation);

    // Ligne centrale
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(size.width / 2, padding),
      Offset(size.width / 2, size.height - padding),
      linePaint,
    );

    // Marqueurs d'élévation
    final textStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.5),
      fontSize: 7,
    );
    final markerPaint = Paint()..color = Colors.white.withValues(alpha: 0.4);

    for (final angle in [-75, -35, 0, 35, 75]) {
      final y = elevationToY(angle.toDouble());
      canvas.drawCircle(Offset(size.width / 2, y), 1.5, markerPaint);

      final textPainter = TextPainter(
        text: TextSpan(text: '$angle°', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(
          size.width / 2 - textPainter.width / 2,
          y.clamp(padding, size.height - padding - 10) + 3,
        ),
      );
    }

    // Cible
    final targetPaint = Paint()
      ..color = isNear ? Colors.greenAccent : Colors.orangeAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final ty = targetY.clamp(padding, size.height - padding);
    canvas.drawLine(Offset(4, ty), Offset(size.width - 4, ty), targetPaint);

    // Position courante
    final currentPaint = Paint()
      ..color = isNear ? Colors.greenAccent : Colors.cyan
      ..style = PaintingStyle.fill;
    final cy = currentY.clamp(padding, size.height - padding);
    canvas.drawCircle(Offset(size.width / 2, cy), 6, currentPaint);
  }

  @override
  bool shouldRepaint(_ElevationPainter old) =>
      old.currentElevation != currentElevation ||
      old.targetElevation != targetElevation ||
      old.isNear != isNear;
}

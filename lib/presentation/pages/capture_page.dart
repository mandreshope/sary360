import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/constellation_colors.dart';
import '../../core/widgets/constellation_orb.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/starfield_background.dart';
import '../viewmodels/capture_viewmodel.dart';
import '../widgets/capture/constellation_painter.dart';

/// Écran de capture « constellation » : l'utilisateur vise les étoiles, la
/// photo est prise automatiquement quand le téléphone est immobile dans le
/// réticule, puis les photos sont assemblées en sphère.
class CapturePage extends ConsumerStatefulWidget {
  const CapturePage({super.key});

  @override
  ConsumerState<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends ConsumerState<CapturePage>
    with WidgetsBindingObserver {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Arrière-plan : libère caméra et capteurs ; l'assemblage, lui, continue
  /// dans son isolate.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final controller = ref.read(captureControllerProvider.notifier);
    // « inactive » (volet de notifications, dialogue système) ne libère pas
    // la caméra : l'aperçu clignoterait pour rien.
    if (lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.hidden) {
      controller.pause();
    } else if (lifecycle == AppLifecycleState.resumed) {
      controller.resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(captureControllerProvider);

    ref.listen(captureControllerProvider, (previous, next) {
      if (next.phase == CapturePhase.completed &&
          next.panorama != null &&
          !_navigated) {
        _navigated = true;
        context.pushReplacement(AppRoutes.viewer, extra: next.panorama);
      }
      final notice = next.notice;
      if (notice != null && notice != previous?.notice) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(notice)));
        ref.read(captureControllerProvider.notifier).clearNotice();
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedSwitcher(
        duration: AppMotion.medium,
        child: switch (state.phase) {
          CapturePhase.initializing => const _Initializing(),
          CapturePhase.ready => _CaptureView(state: state),
          CapturePhase.stitching ||
          CapturePhase.completed => _StitchingView(state: state),
          CapturePhase.error => _ErrorView(message: state.errorMessage),
        },
      ),
    );
  }
}

class _Initializing extends StatelessWidget {
  const _Initializing();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return StarfieldBackground(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ConstellationOrb(size: 140),
            const SizedBox(height: 24),
            Text('Préparation de la caméra…', style: text.titleMedium),
          ],
        ),
      ),
    );
  }
}

/// Visée : aperçu caméra + scène + commandes.
class _CaptureView extends ConsumerStatefulWidget {
  const _CaptureView({required this.state});

  final CaptureState state;

  @override
  ConsumerState<_CaptureView> createState() => _CaptureViewState();
}

class _CaptureViewState extends ConsumerState<_CaptureView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(captureControllerProvider.notifier);
    final camera = controller.camera.controller;
    final session = controller.session;
    final c = context.colors;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (camera != null && camera.value.isInitialized)
          _CoverPreview(controller: camera)
        else
          const ColoredBox(color: Colors.black),
        if (session != null)
          RepaintBoundary(
            child: CustomPaint(
              painter: ConstellationPainter(
                frame: controller.frame,
                pulse: _pulse,
                session: session,
                photos: controller.photos,
                thumbnails: controller.thumbnails,
                hFov: controller.camera.hFov,
                vFov: controller.camera.vFov,
                previewAspect: controller.camera.previewAspect,
                colors: c,
              ),
            ),
          ),
        _CaptureFlash(frame: controller.frame),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _TopBar(state: widget.state),
                const SizedBox(height: 12),
                _Hint(frame: controller.frame),
                const Spacer(),
                _BottomBar(state: widget.state),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Aperçu caméra qui remplit l'écran (BoxFit.cover), comme supposé par la
/// projection de la scène.
class _CoverPreview extends StatelessWidget {
  const _CoverPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final preview = controller.value.previewSize;
    // previewSize est en paysage : on l'inverse pour le portrait.
    final width = preview?.height ?? 1080;
    final height = preview?.width ?? 1920;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: width,
          height: height,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

/// Flash bref à chaque prise de vue.
class _CaptureFlash extends StatefulWidget {
  const _CaptureFlash({required this.frame});

  final ValueNotifier<CaptureFrame> frame;

  @override
  State<_CaptureFlash> createState() => _CaptureFlashState();
}

class _CaptureFlashState extends State<_CaptureFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _lastCount = widget.frame.value.flashCount;
    widget.frame.addListener(_onFrame);
  }

  void _onFrame() {
    final count = widget.frame.value.flashCount;
    if (count != _lastCount) {
      _lastCount = count;
      _flash.forward(from: 0);
    }
  }

  @override
  void dispose() {
    widget.frame.removeListener(_onFrame);
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _flash,
        builder: (context, _) => ColoredBox(
          color: Colors.white.withValues(
            alpha: _flash.isAnimating ? 0.35 * (1 - _flash.value) : 0,
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.state});

  final CaptureState state;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final progress = state.total == 0 ? 0.0 : state.capturedCount / state.total;
    return Row(
      children: [
        GlassIconButton(
          icon: Icons.close_rounded,
          tooltip: 'Quitter',
          onPressed: () => context.pop(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GlassPanel(
            radius: AppRadii.pill,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(
              children: [
                Text(
                  '${state.capturedCount} / ${state.total}',
                  style: text.labelLarge?.copyWith(color: c.textPrimary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: progress),
                      duration: AppMotion.medium,
                      curve: AppMotion.standard,
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: value,
                        minHeight: 6,
                        color: c.accent,
                        backgroundColor: c.glassBorder,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Consigne contextuelle : alertes en priorité, sinon guidage.
class _Hint extends StatelessWidget {
  const _Hint({required this.frame});

  final ValueNotifier<CaptureFrame> frame;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CaptureFrame>(
      valueListenable: frame,
      builder: (context, f, _) {
        final c = context.colors;
        final (IconData icon, String label, Color color) = f.tilted
            ? (
                Icons.screen_rotation_rounded,
                'Redressez le téléphone',
                c.warning,
              )
            : f.tooFast
            ? (Icons.speed_rounded, 'Plus lentement', c.warning)
            : f.activeTarget != null
            ? (Icons.pan_tool_rounded, 'Ne bougez plus…', c.accent)
            : f.orientation == null
            ? (
                Icons.sensors_rounded,
                'Calibration des capteurs…',
                c.textSecondary,
              )
            : (
                Icons.auto_awesome_rounded,
                'Visez l\'étoile qui brille',
                c.textPrimary,
              );
        return AnimatedSwitcher(
          duration: AppMotion.fast,
          child: GlassPanel(
            key: ValueKey(label),
            radius: AppRadii.pill,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: color),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BottomBar extends ConsumerWidget {
  const _BottomBar({required this.state});

  final CaptureState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(captureControllerProvider.notifier);
    final c = context.colors;
    return Row(
      children: [
        GlassIconButton(
          icon: Icons.undo_rounded,
          tooltip: 'Annuler la dernière photo',
          onPressed: state.capturedCount > 0 ? controller.undoLast : null,
        ),
        const Spacer(),
        AnimatedOpacity(
          opacity: state.canFinish ? 1 : 0.45,
          duration: AppMotion.medium,
          child: FilledButton.icon(
            onPressed: state.canFinish ? controller.finish : null,
            style: FilledButton.styleFrom(
              disabledBackgroundColor: c.glass,
              disabledForegroundColor: c.textSecondary,
            ),
            icon: const Icon(Icons.check_rounded),
            label: Text(state.canFinish ? 'Terminer' : 'Couvrez l\'horizon'),
          ),
        ),
      ],
    );
  }
}

/// Assemblage : la constellation se replie en une sphère qui tourne.
class _StitchingView extends ConsumerWidget {
  const _StitchingView({required this.state});

  final CaptureState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final percent = (state.stitchingProgress * 100).round();
    final step = state.stitchingProgress < 0.25
        ? 'Lecture des photos'
        : state.stitchingProgress < 0.5
        ? 'Alignement des étoiles'
        : state.stitchingProgress < 0.75
        ? 'Raccords et exposition'
        : 'Fusion de la sphère';
    return StarfieldBackground(
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Hero(
                  tag: ConstellationOrb.heroTag,
                  child: ConstellationOrb(
                    size: 220,
                    progress: state.stitchingProgress,
                    rotationPeriod: const Duration(seconds: 8),
                  ),
                ),
                const SizedBox(height: 32),
                Text('$percent %', style: text.displaySmall),
                const SizedBox(height: 8),
                Text(
                  step,
                  style: text.bodyLarge?.copyWith(color: c.textSecondary),
                ),
                const SizedBox(height: 4),
                Text('${state.capturedCount} photos', style: text.bodySmall),
                const SizedBox(height: 32),
                TextButton.icon(
                  onPressed: ref
                      .read(captureControllerProvider.notifier)
                      .cancelStitching,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Annuler'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends ConsumerWidget {
  const _ErrorView({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    return StarfieldBackground(
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: GlassPanel(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline_rounded, size: 48, color: c.danger),
                  const SizedBox(height: 16),
                  Text('Oups', style: text.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    message ?? 'Une erreur est survenue.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => context.pop(),
                        child: const Text('Retour'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: ref
                            .read(captureControllerProvider.notifier)
                            .start,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Recommencer'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

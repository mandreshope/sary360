import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../data/services/camera_service.dart';
import '../../data/services/stitching_service.dart';
import '../../domain/models/captured_photo.dart';
import '../../domain/models/panorama.dart';
import '../../presentation/widgets/spherical_guide.dart';

/// État de la capture
enum CaptureState {
  idle,
  initializing,
  ready,
  capturing,
  stitching,
  completed,
  error,
}

/// État du ViewModel de capture sphérique
class CaptureViewState {
  final CaptureState state;
  final List<CapturedPhoto> capturedPhotos;
  final int currentTargetIndex;
  final int totalTargets;
  final double currentAzimuth;
  final double currentElevation;
  final double targetAzimuth;
  final double targetElevation;
  final bool isNearTarget;
  final double stitchingProgress;
  final Panorama? completedPanorama;
  final String? errorMessage;
  final int currentRow;
  final List<TargetPoint> allTargetPoints;

  const CaptureViewState({
    this.state = CaptureState.idle,
    this.capturedPhotos = const [],
    this.currentTargetIndex = 0,
    this.totalTargets = 0,
    this.currentAzimuth = 0.0,
    this.currentElevation = 0.0,
    this.targetAzimuth = 0.0,
    this.targetElevation = 0.0,
    this.isNearTarget = false,
    this.stitchingProgress = 0.0,
    this.completedPanorama,
    this.errorMessage,
    this.currentRow = 0,
    this.allTargetPoints = const [],
  });

  /// Progression = photos capturées / total cibles (clampé entre 0 et 1)
  double get progress => totalTargets > 0
      ? (capturedPhotos.length / totalTargets).clamp(0.0, 1.0)
      : 0.0;

  bool get isCapturing =>
      state == CaptureState.capturing || state == CaptureState.ready;

  /// On peut capturer seulement si: état ready, proche de la cible,
  /// et le nombre de photos n'a pas encore atteint le total
  bool get canCapture =>
      state == CaptureState.ready &&
      isNearTarget &&
      capturedPhotos.length < totalTargets;

  String get currentRowLabel {
    if (currentRow >= 0 && currentRow < AppConstants.rowNames.length) {
      return AppConstants.rowNames[currentRow];
    }
    return 'Rangée $currentRow';
  }

  CaptureViewState copyWith({
    CaptureState? state,
    List<CapturedPhoto>? capturedPhotos,
    int? currentTargetIndex,
    int? totalTargets,
    double? currentAzimuth,
    double? currentElevation,
    double? targetAzimuth,
    double? targetElevation,
    bool? isNearTarget,
    double? stitchingProgress,
    Panorama? completedPanorama,
    String? errorMessage,
    int? currentRow,
    List<TargetPoint>? allTargetPoints,
  }) {
    return CaptureViewState(
      state: state ?? this.state,
      capturedPhotos: capturedPhotos ?? this.capturedPhotos,
      currentTargetIndex: currentTargetIndex ?? this.currentTargetIndex,
      totalTargets: totalTargets ?? this.totalTargets,
      currentAzimuth: currentAzimuth ?? this.currentAzimuth,
      currentElevation: currentElevation ?? this.currentElevation,
      targetAzimuth: targetAzimuth ?? this.targetAzimuth,
      targetElevation: targetElevation ?? this.targetElevation,
      isNearTarget: isNearTarget ?? this.isNearTarget,
      stitchingProgress: stitchingProgress ?? this.stitchingProgress,
      completedPanorama: completedPanorama ?? this.completedPanorama,
      errorMessage: errorMessage ?? this.errorMessage,
      currentRow: currentRow ?? this.currentRow,
      allTargetPoints: allTargetPoints ?? this.allTargetPoints,
    );
  }
}

/// ViewModel de capture sphérique 360°
class CaptureViewModel extends StateNotifier<CaptureViewState> {
  final CameraService _cameraService;
  final StitchingService _stitchingService;

  CaptureViewModel({
    required CameraService cameraService,
    required StitchingService stitchingService,
  }) : _cameraService = cameraService,
       _stitchingService = stitchingService,
       super(const CaptureViewState());

  CameraService get cameraService => _cameraService;

  /// Construit la liste de TargetPoint pour le guide sphérique
  List<TargetPoint> _buildTargetPoints() {
    final targets = _cameraService.targets;
    final capturedIndices = _cameraService.capturedTargetIndices;

    return List.generate(targets.length, (i) {
      return TargetPoint(
        azimuth: targets[i].azimuth,
        elevation: targets[i].elevation,
        isCaptured: capturedIndices.contains(i),
      );
    });
  }

  /// Initialise la capture sphérique
  Future<void> initializeCapture() async {
    state = state.copyWith(state: CaptureState.initializing);

    try {
      await _cameraService.initialize();

      // Écouter les changements d'orientation
      _cameraService.onOrientationChanged = (orientation) {
        if (!mounted) return;
        // Ne pas mettre à jour si on est en train de capturer ou si c'est fini
        if (state.state == CaptureState.capturing ||
            state.state == CaptureState.stitching ||
            state.state == CaptureState.completed) {
          return;
        }
        state = state.copyWith(
          currentAzimuth: orientation.azimuth,
          currentElevation: orientation.pitch,
        );
      };

      _cameraService.onTargetProximityChanged = (target, isNear) {
        if (!mounted) return;
        // Ne pas mettre à jour si on est en train de capturer ou si c'est fini
        if (state.state == CaptureState.capturing ||
            state.state == CaptureState.stitching ||
            state.state == CaptureState.completed) {
          return;
        }
        // Ne jamais dépasser le total
        if (state.capturedPhotos.length >= state.totalTargets &&
            state.totalTargets > 0) {
          return;
        }
        state = state.copyWith(
          isNearTarget: isNear,
          targetAzimuth: target.azimuth,
          targetElevation: target.elevation,
          currentRow: target.rowIndex,
        );
      };

      // ★ Capture automatique quand le hold-steady est confirmé
      _cameraService.onAutoCapture = () {
        if (!mounted) return;
        if (state.state != CaptureState.ready) return;
        if (state.capturedPhotos.length >= state.totalTargets) return;
        captureCurrentTarget();
      };

      final totalTargets = _cameraService.targets.length;
      final targetPoints = _buildTargetPoints();

      state = state.copyWith(
        state: CaptureState.ready,
        totalTargets: totalTargets,
        currentTargetIndex: 0,
        allTargetPoints: targetPoints,
      );

      // Mettre à jour la cible initiale
      if (_cameraService.currentTarget != null) {
        final target = _cameraService.currentTarget!;
        state = state.copyWith(
          targetAzimuth: target.azimuth,
          targetElevation: target.elevation,
          currentRow: target.rowIndex,
        );
      }
    } catch (e) {
      state = state.copyWith(
        state: CaptureState.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Capture une photo au point courant
  Future<void> captureCurrentTarget() async {
    // Double-vérification: état + compteur
    if (!state.canCapture) return;
    if (_cameraService.isComplete) return;

    state = state.copyWith(
      state: CaptureState.capturing,
      isNearTarget: false, // Désactiver immédiatement
    );

    try {
      final photo = await _cameraService.capturePhoto();
      final updatedPhotos = [...state.capturedPhotos, photo];
      final targetPoints = _buildTargetPoints();

      // Vérifier si on a fini (clamper le count)
      final capturedCount = updatedPhotos.length.clamp(0, state.totalTargets);

      if (_cameraService.isComplete || capturedCount >= state.totalTargets) {
        // Toutes les photos ont été prises → stitching
        state = state.copyWith(
          state: CaptureState.stitching,
          capturedPhotos: updatedPhotos,
          currentTargetIndex: state.totalTargets,
          isNearTarget: false,
          allTargetPoints: targetPoints,
        );

        // STABILITÉ ANDROID : Pauser ou libérer la caméra avant le traitement lourd
        // Cela empêche le bug "MessageQueue on a dead thread" où le plugin
        // caméra panique parce que l'Isolate de stitching bloque ou surcharge le CPU.
        try {
          await _cameraService.controller?.pausePreview();
        } catch (_) {}

        await _performStitching(updatedPhotos);
      } else {
        // Passer à la cible suivante
        final nextTarget = _cameraService.currentTarget;
        state = state.copyWith(
          state: CaptureState.ready,
          capturedPhotos: updatedPhotos,
          currentTargetIndex: _cameraService.currentTargetIndex,
          isNearTarget: false, // Forcer à false, sera mis à jour par le sensor
          targetAzimuth: nextTarget?.azimuth ?? 0,
          targetElevation: nextTarget?.elevation ?? 0,
          currentRow: nextTarget?.rowIndex ?? 0,
          allTargetPoints: targetPoints,
        );
      }
    } catch (e) {
      // Si l'erreur est juste un cooldown, revenir en ready sans afficher d'erreur
      final errorMsg = e.toString();
      if (errorMsg.contains('cooldown') ||
          errorMsg.contains('attendre') ||
          errorMsg.contains('déjà en cours')) {
        state = state.copyWith(state: CaptureState.ready, isNearTarget: false);
      } else {
        state = state.copyWith(
          state: CaptureState.error,
          errorMessage: 'Erreur de capture: $e',
        );
      }
    }
  }

  /// Effectue le stitching sphérique
  Future<void> _performStitching(List<CapturedPhoto> photos) async {
    try {
      final panorama = await _stitchingService.stitchPanorama(
        photos,
        onProgress: (progress) {
          if (mounted) {
            state = state.copyWith(stitchingProgress: progress);
          }
        },
      );

      state = state.copyWith(
        state: CaptureState.completed,
        completedPanorama: panorama,
        stitchingProgress: 1.0,
      );
    } on StitchingCancelledException {
      if (!mounted) return;
      state = state.copyWith(
        state: CaptureState.error,
        errorMessage: 'Assemblage annulé.',
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        state: CaptureState.error,
        errorMessage: 'Erreur d\'assemblage : $e',
      );
    }
  }

  /// Demande l'arrêt de l'assemblage en cours (pris en compte entre deux
  /// étapes du traitement natif).
  void cancelStitching() => _stitchingService.cancel();

  /// Réinitialise la capture
  void reset() {
    _cameraService.reset();
    final targetPoints = _buildTargetPoints();
    state = CaptureViewState(
      state: CaptureState.ready,
      totalTargets: _cameraService.targets.length,
      allTargetPoints: targetPoints,
    );

    if (_cameraService.currentTarget != null) {
      final target = _cameraService.currentTarget!;
      state = state.copyWith(
        targetAzimuth: target.azimuth,
        targetElevation: target.elevation,
        currentRow: target.rowIndex,
      );
    }
  }

  @override
  void dispose() {
    _cameraService.dispose();
    super.dispose();
  }
}

/// Provider du CameraService
final cameraServiceProvider = Provider.autoDispose<CameraService>((ref) {
  return CameraService();
});

/// Provider du StitchingService
final stitchingServiceProvider = Provider.autoDispose<StitchingService>((ref) {
  return StitchingService(); // Service sans état, mais on l'autodispose pour cohérence
});

/// Provider du CaptureViewModel
final captureViewModelProvider =
    StateNotifierProvider.autoDispose<CaptureViewModel, CaptureViewState>((
      ref,
    ) {
      final cameraService = ref.watch(cameraServiceProvider);
      final stitchingService = ref.watch(stitchingServiceProvider);
      return CaptureViewModel(
        cameraService: cameraService,
        stitchingService: stitchingService,
      );
    });

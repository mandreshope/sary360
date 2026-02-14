import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/camera_service.dart';
import '../../data/services/stitching_service.dart';
import '../../domain/models/captured_photo.dart';
import '../../domain/models/panorama.dart';

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
  });

  double get progress =>
      totalTargets > 0 ? capturedPhotos.length / totalTargets : 0.0;

  bool get isCapturing =>
      state == CaptureState.capturing || state == CaptureState.ready;

  bool get canCapture => state == CaptureState.ready && isNearTarget;

  String get currentRowLabel {
    switch (currentRow) {
      case 0:
        return 'Rangée haute';
      case 1:
        return 'Rangée horizontale';
      case 2:
        return 'Rangée basse';
      default:
        return 'Rangée $currentRow';
    }
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

  /// Initialise la capture sphérique
  Future<void> initializeCapture() async {
    state = state.copyWith(state: CaptureState.initializing);

    try {
      await _cameraService.initialize();

      // Écouter les changements d'orientation
      _cameraService.onOrientationChanged = (orientation) {
        if (!mounted) return;
        state = state.copyWith(
          currentAzimuth: orientation.azimuth,
          currentElevation: orientation.pitch,
        );
      };

      _cameraService.onTargetProximityChanged = (target, isNear) {
        if (!mounted) return;
        state = state.copyWith(
          isNearTarget: isNear,
          targetAzimuth: target.azimuth,
          targetElevation: target.elevation,
          currentRow: target.rowIndex,
        );
      };

      state = state.copyWith(
        state: CaptureState.ready,
        totalTargets: _cameraService.targets.length,
        currentTargetIndex: 0,
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
    if (!state.canCapture) return;

    state = state.copyWith(state: CaptureState.capturing);

    try {
      final photo = await _cameraService.capturePhoto();
      final updatedPhotos = [...state.capturedPhotos, photo];

      if (_cameraService.isComplete) {
        // Toutes les photos ont été prises → stitching
        state = state.copyWith(
          state: CaptureState.stitching,
          capturedPhotos: updatedPhotos,
          currentTargetIndex: _cameraService.currentTargetIndex,
        );

        await _performStitching(updatedPhotos);
      } else {
        // Passer à la cible suivante
        final nextTarget = _cameraService.currentTarget;
        state = state.copyWith(
          state: CaptureState.ready,
          capturedPhotos: updatedPhotos,
          currentTargetIndex: _cameraService.currentTargetIndex,
          isNearTarget: false,
          targetAzimuth: nextTarget?.azimuth ?? 0,
          targetElevation: nextTarget?.elevation ?? 0,
          currentRow: nextTarget?.rowIndex ?? 0,
        );
      }
    } catch (e) {
      state = state.copyWith(
        state: CaptureState.error,
        errorMessage: 'Erreur de capture: $e',
      );
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
    } catch (e) {
      state = state.copyWith(
        state: CaptureState.error,
        errorMessage: 'Erreur d\'assemblage: $e',
      );
    }
  }

  /// Réinitialise la capture
  void reset() {
    _cameraService.reset();
    state = CaptureViewState(
      state: CaptureState.ready,
      totalTargets: _cameraService.targets.length,
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
final cameraServiceProvider = Provider<CameraService>((ref) {
  return CameraService();
});

/// Provider du StitchingService
final stitchingServiceProvider = Provider<StitchingService>((ref) {
  return StitchingService();
});

/// Provider du CaptureViewModel
final captureViewModelProvider =
    StateNotifierProvider<CaptureViewModel, CaptureViewState>((ref) {
      final cameraService = ref.watch(cameraServiceProvider);
      final stitchingService = ref.watch(stitchingServiceProvider);
      return CaptureViewModel(
        cameraService: cameraService,
        stitchingService: stitchingService,
      );
    });

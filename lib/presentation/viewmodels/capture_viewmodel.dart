import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
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

/// État du ViewModel de capture
class CaptureViewState {
  final CaptureState state;
  final List<CapturedPhoto> capturedPhotos;
  final int currentPhotoIndex;
  final double currentRotation;
  final double targetRotation;
  final bool isNearTarget;
  final double stitchingProgress;
  final Panorama? completedPanorama;
  final String? errorMessage;

  const CaptureViewState({
    this.state = CaptureState.idle,
    this.capturedPhotos = const [],
    this.currentPhotoIndex = 0,
    this.currentRotation = 0.0,
    this.targetRotation = 0.0,
    this.isNearTarget = false,
    this.stitchingProgress = 0.0,
    this.completedPanorama,
    this.errorMessage,
  });

  double get progress => capturedPhotos.length / AppConstants.numberOfPhotos;
  bool get isCapturing =>
      state == CaptureState.capturing || state == CaptureState.ready;
  bool get canCapture => state == CaptureState.ready && isNearTarget;

  CaptureViewState copyWith({
    CaptureState? state,
    List<CapturedPhoto>? capturedPhotos,
    int? currentPhotoIndex,
    double? currentRotation,
    double? targetRotation,
    bool? isNearTarget,
    double? stitchingProgress,
    Panorama? completedPanorama,
    String? errorMessage,
  }) {
    return CaptureViewState(
      state: state ?? this.state,
      capturedPhotos: capturedPhotos ?? this.capturedPhotos,
      currentPhotoIndex: currentPhotoIndex ?? this.currentPhotoIndex,
      currentRotation: currentRotation ?? this.currentRotation,
      targetRotation: targetRotation ?? this.targetRotation,
      isNearTarget: isNearTarget ?? this.isNearTarget,
      stitchingProgress: stitchingProgress ?? this.stitchingProgress,
      completedPanorama: completedPanorama ?? this.completedPanorama,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// ViewModel de capture (Simplifié pour camera_360)
class CaptureViewModel extends StateNotifier<CaptureViewState> {
  final CameraService _cameraService;

  CaptureViewModel({required CameraService cameraService})
    : _cameraService = cameraService,
      super(const CaptureViewState());

  CameraService get cameraService => _cameraService;

  /// Gère le résultat de la capture camera_360
  void handleCaptureResult(Map<String, dynamic> result) {
    if (result['success'] == true) {
      final String? path = result['panorama'];
      if (path != null) {
        final panorama = Panorama(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: 'Panorama ${DateTime.now().toLocal()}',
          createdAt: DateTime.now(),
          stitchedImagePath: path,
          originalPhotoPaths: [], // camera_360 gère ça en interne
          photoCount: AppConstants.numberOfPhotos,
        );

        state = state.copyWith(
          state: CaptureState.completed,
          completedPanorama: panorama,
        );
      }
    } else {
      state = state.copyWith(
        state: CaptureState.error,
        errorMessage: 'Capture annulée ou échouée',
      );
    }
  }

  /// Réinitialise la capture
  void reset() {
    state = const CaptureViewState(state: CaptureState.ready);
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

      return CaptureViewModel(cameraService: cameraService);
    });

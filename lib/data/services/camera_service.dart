import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/models/captured_photo.dart';

/// Service de gestion de la caméra avec guidage gyroscopique
class CameraService {
  CameraController? _controller;
  List<CameraDescription>? _cameras;

  // Rotation tracking
  double _currentRotation = 0.0;
  double _initialRotation = 0.0;
  bool _isRotationInitialized = false;

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  double get currentRotation => _currentRotation - _initialRotation;

  /// Initialise la caméra
  Future<void> initialize() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        throw Exception('Aucune caméra disponible');
      }

      // Utiliser la caméra arrière
      final camera = _cameras!.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();

      // Verrouiller l'orientation en portrait
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);

      // Verrouiller l'exposition et le focus
      await _lockExposureAndFocus();
    } catch (e) {
      throw Exception('Erreur d\'initialisation de la caméra: $e');
    }
  }

  /// Verrouille l'exposition et le focus pour une cohérence entre les photos
  Future<void> _lockExposureAndFocus() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      // Verrouiller l'exposition
      final exposureMode = _controller!.value.exposureMode;
      if (exposureMode != ExposureMode.locked) {
        await _controller!.setExposureMode(ExposureMode.locked);
      }

      // Verrouiller le focus
      final focusMode = _controller!.value.focusMode;
      if (focusMode != FocusMode.locked) {
        await _controller!.setFocusMode(FocusMode.locked);
      }
    } catch (e) {
      // ignore: avoid_print
      print('Avertissement: Impossible de verrouiller exposition/focus: $e');
    }
  }

  /// Initialise la rotation de départ
  void initializeRotation(double rotation) {
    if (!_isRotationInitialized) {
      _initialRotation = rotation;
      _isRotationInitialized = true;
    }
  }

  /// Met à jour la rotation actuelle
  void updateRotation(double rotation) {
    _currentRotation = rotation;
  }

  /// Vérifie si l'utilisateur est proche de l'angle cible
  bool isNearTargetAngle(int photoIndex) {
    final targetAngle = photoIndex * AppConstants.rotationAngle;
    final currentAngle = currentRotation.abs() % 360;
    final diff = (currentAngle - targetAngle).abs();

    return diff < AppConstants.rotationTolerance ||
        (360 - diff) < AppConstants.rotationTolerance;
  }

  /// Capture une photo
  Future<CapturedPhoto> capturePhoto(int index) async {
    if (_controller == null || !_controller!.value.isInitialized) {
      throw Exception('Caméra non initialisée');
    }

    try {
      // Capturer l'image
      final XFile image = await _controller!.takePicture();

      // Créer un répertoire temporaire si nécessaire
      final tempDir = await getTemporaryDirectory();
      final photoDir = Directory('${tempDir.path}/${AppConstants.tempFolder}');
      if (!photoDir.existsSync()) {
        photoDir.createSync(recursive: true);
      }

      // Copier l'image dans le répertoire temporaire avec un nom unique
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final newPath = '${photoDir.path}/photo_${index}_$timestamp.jpg';
      await File(image.path).copy(newPath);

      return CapturedPhoto(
        path: newPath,
        rotationAngle: currentRotation,
        capturedAt: DateTime.now(),
        index: index,
      );
    } catch (e) {
      throw Exception('Erreur lors de la capture: $e');
    }
  }

  /// Réinitialise le tracking de rotation
  void resetRotation() {
    _currentRotation = 0.0;
    _initialRotation = 0.0;
    _isRotationInitialized = false;
  }

  /// Libère les ressources
  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
    resetRotation();

    // Réinitialiser l'orientation
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
}

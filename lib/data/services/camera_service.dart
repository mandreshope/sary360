import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/models/captured_photo.dart';

/// Position cible pour une capture
class CaptureTarget {
  final int rowIndex;
  final int indexInRow;
  final double azimuth; // 0-360°
  final double elevation; // -90 to +90°

  const CaptureTarget({
    required this.rowIndex,
    required this.indexInRow,
    required this.azimuth,
    required this.elevation,
  });
}

/// Orientation actuelle du téléphone
class DeviceOrientation3D {
  /// Azimut (yaw): 0-360°, direction horizontale de la boussole
  final double azimuth;

  /// Pitch: -90 to +90°, inclinaison verticale
  final double pitch;

  /// Roll: rotation latérale
  final double roll;

  const DeviceOrientation3D({
    required this.azimuth,
    required this.pitch,
    required this.roll,
  });
}

/// Service de gestion de la caméra pour capture sphérique 360°
class CameraService {
  CameraController? _controller;
  List<CameraDescription>? _cameras;

  // Orientation tracking
  bool _isTakingPicture = false;
  bool _isReady = false;

  DeviceOrientation3D _currentOrientation = const DeviceOrientation3D(
    azimuth: 0,
    pitch: 0,
    roll: 0,
  );

  // Sensor subscriptions
  StreamSubscription? _accelSub;
  StreamSubscription? _magnetSub;

  // Low-pass filtered sensor values
  double _filteredAzimuth = 0;
  double _filteredPitch = 0;

  // Magnetometer + accelerometer data for orientation
  final List<double> _gravity = [0, 0, 9.8];
  final List<double> _magnetic = [0, 0, 0];

  // Reference azimuth (set when capture starts)
  double? _referenceAzimuth;

  // Capture targets
  List<CaptureTarget> _targets = [];
  int _currentTargetIndex = 0;

  // Callbacks
  void Function(DeviceOrientation3D)? onOrientationChanged;
  void Function(CaptureTarget, bool isNear)? onTargetProximityChanged;

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get isReady => _isReady;
  DeviceOrientation3D get currentOrientation => _currentOrientation;
  List<CaptureTarget> get targets => _targets;
  int get currentTargetIndex => _currentTargetIndex;
  CaptureTarget? get currentTarget => _currentTargetIndex < _targets.length
      ? _targets[_currentTargetIndex]
      : null;

  /// Génère tous les points de capture sphérique
  void _generateTargets() {
    _targets = [];
    for (int row = 0; row < AppConstants.numberOfRows; row++) {
      final int photosInRow = AppConstants.photosPerRow[row];
      final double elevation = AppConstants.rowElevations[row];
      final double azimuthStep = 360.0 / photosInRow;

      for (int i = 0; i < photosInRow; i++) {
        _targets.add(
          CaptureTarget(
            rowIndex: row,
            indexInRow: i,
            azimuth: i * azimuthStep,
            elevation: elevation,
          ),
        );
      }
    }
    _currentTargetIndex = 0;
  }

  /// Initialise la caméra et les capteurs
  Future<void> initialize() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        throw Exception('Aucune caméra disponible');
      }

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

      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);

      _generateTargets();
      _startSensors();

      // Attendre que le pipeline natif de la caméra Android soit
      // complètement initialisé (ImageReader). Sans ce délai,
      // takePicture() peut lancer un NullPointerException.
      await Future.delayed(const Duration(milliseconds: 800));

      await _lockExposureAndFocus();
      _isReady = true;
    } catch (e) {
      throw Exception('Erreur d\'initialisation de la caméra: $e');
    }
  }

  /// Démarre l'écoute des capteurs
  void _startSensors() {
    // Accéléromètre pour gravity
    _accelSub =
        accelerometerEventStream(
          samplingPeriod: const Duration(milliseconds: 20),
        ).listen((event) {
          // Low-pass filter
          const alpha = 0.15;
          _gravity[0] = alpha * event.x + (1 - alpha) * _gravity[0];
          _gravity[1] = alpha * event.y + (1 - alpha) * _gravity[1];
          _gravity[2] = alpha * event.z + (1 - alpha) * _gravity[2];
          _updateOrientation();
        });

    // Magnétomètre pour la direction
    _magnetSub =
        magnetometerEventStream(
          samplingPeriod: const Duration(milliseconds: 20),
        ).listen((event) {
          const alpha = 0.15;
          _magnetic[0] = alpha * event.x + (1 - alpha) * _magnetic[0];
          _magnetic[1] = alpha * event.y + (1 - alpha) * _magnetic[1];
          _magnetic[2] = alpha * event.z + (1 - alpha) * _magnetic[2];
          _updateOrientation();
        });
  }

  /// Calcule l'orientation à partir des données capteurs
  void _updateOrientation() {
    // Calculer le pitch (élévation) à partir de l'accéléromètre
    final gx = _gravity[0];
    final gy = _gravity[1];
    final gz = _gravity[2];
    final gNorm = math.sqrt(gx * gx + gy * gy + gz * gz);

    if (gNorm < 0.1) return;

    // Pitch: angle entre l'axe Y du téléphone et l'horizontale
    // En portrait, gy pointe vers le haut, gz vers l'utilisateur
    double pitch = math.atan2(-gy, gz) * 180 / math.pi;
    // Ajuster: téléphone vertical (portrait) = 0° d'élévation horizontale
    // Quand gy=-9.8, gz=0 → pitch=90° → on veut 0° (horizontal)
    pitch = pitch - 90;
    if (pitch < -90) pitch += 360;
    if (pitch > 90) pitch = 180 - pitch;

    // Calculer l'azimut à partir du magnétomètre et de la gravité
    // Créer les axes de référence
    final hx = _magnetic[1] * gz - _magnetic[2] * gy;
    final hy = _magnetic[2] * gx - _magnetic[0] * gz;
    // Azimut
    double azimuth = math.atan2(hy, hx) * 180 / math.pi;
    if (azimuth < 0) azimuth += 360;

    // Low-pass sur l'azimut (gestion du wrap-around 0/360)
    const alpha = 0.1;
    double diff = azimuth - _filteredAzimuth;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    _filteredAzimuth = (_filteredAzimuth + alpha * diff) % 360;
    if (_filteredAzimuth < 0) _filteredAzimuth += 360;

    _filteredPitch = alpha * pitch + (1 - alpha) * _filteredPitch;

    // Définir la référence au premier calcul stable
    _referenceAzimuth ??= _filteredAzimuth;

    // Azimut relatif au point de départ
    double relativeAzimuth = _filteredAzimuth - _referenceAzimuth!;
    if (relativeAzimuth < 0) relativeAzimuth += 360;

    _currentOrientation = DeviceOrientation3D(
      azimuth: relativeAzimuth,
      pitch: _filteredPitch,
      roll: 0,
    );

    onOrientationChanged?.call(_currentOrientation);

    // Vérifier la proximité de la cible
    if (currentTarget != null) {
      final isNear = _isNearTarget(currentTarget!);
      onTargetProximityChanged?.call(currentTarget!, isNear);
    }
  }

  /// Vérifie si l'orientation actuelle est proche de la cible
  bool _isNearTarget(CaptureTarget target) {
    double azimuthDiff = (_currentOrientation.azimuth - target.azimuth).abs();
    if (azimuthDiff > 180) azimuthDiff = 360 - azimuthDiff;

    final elevationDiff = (_currentOrientation.pitch - target.elevation).abs();

    return azimuthDiff < AppConstants.angleTolerance &&
        elevationDiff < AppConstants.elevationTolerance;
  }

  /// Vérifie si le téléphone est dans la bonne position pour la cible courante
  bool get isNearCurrentTarget {
    if (currentTarget == null) return false;
    return _isNearTarget(currentTarget!);
  }

  /// Verrouille l'exposition et le focus
  Future<void> _lockExposureAndFocus() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      await _controller!.setExposureMode(ExposureMode.locked);
      await _controller!.setFocusMode(FocusMode.locked);
    } catch (e) {
      // Certains appareils ne supportent pas le verrouillage
    }
  }

  /// Capture une photo au point courant (avec retry pour les erreurs Android)
  Future<CapturedPhoto> capturePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      throw Exception('Caméra non initialisée');
    }
    if (!_isReady) {
      throw Exception('Caméra pas encore prête');
    }
    if (currentTarget == null) {
      throw Exception('Aucune cible de capture');
    }
    if (_isTakingPicture) {
      throw Exception('Capture déjà en cours');
    }

    _isTakingPicture = true;
    try {
      final XFile image = await _takePictureWithRetry();

      final tempDir = await getTemporaryDirectory();
      final photoDir = Directory('${tempDir.path}/${AppConstants.tempFolder}');
      if (!photoDir.existsSync()) {
        photoDir.createSync(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final target = currentTarget!;
      final newPath =
          '${photoDir.path}/photo_r${target.rowIndex}_i${target.indexInRow}_$timestamp.jpg';
      await File(image.path).copy(newPath);

      final photo = CapturedPhoto(
        path: newPath,
        azimuth: target.azimuth,
        elevation: target.elevation,
        capturedAt: DateTime.now(),
        rowIndex: target.rowIndex,
        indexInRow: target.indexInRow,
      );

      // Passer à la cible suivante
      _currentTargetIndex++;

      // Petit délai entre les captures pour laisser le pipeline
      // Android recycler l'ImageReader
      await Future.delayed(const Duration(milliseconds: 300));

      return photo;
    } catch (e) {
      throw Exception('Erreur lors de la capture: $e');
    } finally {
      _isTakingPicture = false;
    }
  }

  /// Tente de prendre la photo avec jusqu'à 3 retries
  /// pour contourner les erreurs transitoires d'ImageReader sur Android
  Future<XFile> _takePictureWithRetry({int maxRetries = 3}) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        return await _controller!.takePicture();
      } catch (e) {
        if (attempt < maxRetries - 1) {
          // Attendre de plus en plus longtemps entre les retries
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        } else {
          rethrow;
        }
      }
    }
    throw Exception('Échec de la capture après $maxRetries tentatives');
  }

  /// Réinitialise la capture
  void reset() {
    _currentTargetIndex = 0;
    _referenceAzimuth = null;
    _generateTargets();
  }

  /// Est-ce que toutes les photos ont été prises ?
  bool get isComplete => _currentTargetIndex >= _targets.length;

  /// Progression globale (0.0 - 1.0)
  double get progress =>
      _targets.isEmpty ? 0.0 : _currentTargetIndex / _targets.length;

  /// Libère les ressources
  Future<void> dispose() async {
    _accelSub?.cancel();
    _magnetSub?.cancel();
    await _controller?.dispose();
    _controller = null;

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
}

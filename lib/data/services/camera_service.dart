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

  @override
  String toString() =>
      'Target(row:$rowIndex, i:$indexInRow, az:${azimuth.toStringAsFixed(1)}°, el:${elevation.toStringAsFixed(1)}°)';
}

/// Orientation actuelle du téléphone
class DeviceOrientation3D {
  /// Azimut (yaw): 0-360°, direction horizontale relative au départ
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
/// Inspiré de Google Street View : couverture complète de la sphère
class CameraService {
  CameraController? _controller;
  List<CameraDescription>? _cameras;

  // ── État interne ──
  bool _isTakingPicture = false;
  bool _isReady = false;

  /// Cooldown après chaque capture pour éviter les doubles captures
  DateTime _lastCaptureTime = DateTime(2000);
  static const _captureCooldown = Duration(milliseconds: 1200);

  DeviceOrientation3D _currentOrientation = const DeviceOrientation3D(
    azimuth: 0,
    pitch: 0,
    roll: 0,
  );

  // ── Hold-steady : l'utilisateur doit rester stable ~240ms (rapide) ──
  int _nearTargetFrames = 0;
  static const _requiredNearFrames = 8; // ~240ms à 33Hz
  bool _confirmedNear = false;

  // ── Throttle des callbacks UI (~30 FPS pour fluidité max) ──
  DateTime _lastUIUpdate = DateTime(2000);
  static const _uiUpdateInterval = Duration(milliseconds: 32);

  // ── Sensor subscriptions ──
  StreamSubscription? _accelSub;
  StreamSubscription? _magnetSub;

  // ── Low-pass filtered sensor values ──
  double _filteredAzimuth = 0;
  double _filteredPitch = 0;
  bool _azimuthInitialized = false;

  // ── Magnetometer + accelerometer raw data ──
  final List<double> _gravity = [0, 0, 9.8];
  final List<double> _magnetic = [0, 0, 0];
  bool _hasGravityData = false;
  bool _hasMagnetData = false;

  // ── Reference azimuth (set when enough sensor data is stable) ──
  double? _referenceAzimuth;
  int _stableFrames = 0;
  static const _requiredStableFrames = 15; // ~300ms at 50Hz

  // ── Capture targets ──
  List<CaptureTarget> _targets = [];
  int _currentTargetIndex = 0;

  // ── Suivi des captures (indices des targets capturés) ──
  final Set<int> _capturedTargetIndices = {};

  // ── Callbacks ──
  void Function(DeviceOrientation3D)? onOrientationChanged;
  void Function(CaptureTarget, bool isNear)? onTargetProximityChanged;

  /// Appelé automatiquement quand le hold-steady est confirmé
  /// → la capture se déclenche sans appui sur le bouton
  void Function()? onAutoCapture;

  // ── Getters ──
  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get isReady => _isReady;
  DeviceOrientation3D get currentOrientation => _currentOrientation;
  List<CaptureTarget> get targets => _targets;
  int get currentTargetIndex => _currentTargetIndex.clamp(0, _targets.length);
  Set<int> get capturedTargetIndices => _capturedTargetIndices;

  CaptureTarget? get currentTarget {
    if (_currentTargetIndex < 0 || _currentTargetIndex >= _targets.length) {
      return null;
    }
    return _targets[_currentTargetIndex];
  }

  /// Est-ce que toutes les photos ont été prises ?
  bool get isComplete =>
      _targets.isNotEmpty && _currentTargetIndex >= _targets.length;

  /// Progression globale (0.0 - 1.0)
  double get progress =>
      _targets.isEmpty ? 0.0 : _currentTargetIndex / _targets.length;

  /// Vérifie si le téléphone est dans la bonne position pour la cible courante
  bool get isNearCurrentTarget {
    if (currentTarget == null) return false;
    return _confirmedNear;
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  INITIALISATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Génère tous les points de capture sphérique
  /// Ordre optimisé comme Google Street View : commence par l'horizon,
  /// puis monte progressivement, puis descend
  void _generateTargets() {
    _targets = [];
    _capturedTargetIndices.clear();

    // Ordre de capture optimisé pour l'expérience utilisateur :
    // Horizon d'abord (le plus naturel), puis haut, zénith, bas, nadir
    final rowOrder = [2, 1, 0, 3, 4]; // index dans rowElevations

    for (final row in rowOrder) {
      final int photosInRow = AppConstants.photosPerRow[row];
      final double elevation = AppConstants.rowElevations[row];
      final double azimuthStep = 360.0 / photosInRow;

      // Offset alterné entre les rangées pour un meilleur recouvrement
      final double azimuthOffset = (row % 2 == 0) ? 0.0 : azimuthStep / 2;

      for (int i = 0; i < photosInRow; i++) {
        final azimuth = (i * azimuthStep + azimuthOffset) % 360;
        _targets.add(
          CaptureTarget(
            rowIndex: row,
            indexInRow: i,
            azimuth: azimuth,
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

      // Attendre que le pipeline natif Android soit complètement prêt
      await Future.delayed(const Duration(milliseconds: 800));

      await _lockExposureAndFocus();
      _isReady = true;
    } catch (e) {
      throw Exception('Erreur d\'initialisation de la caméra: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  CAPTEURS & ORIENTATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Démarre l'écoute des capteurs
  /// Fréquence standard (33Hz) + filtre modéré pour une bonne réactivité
  void _startSensors() {
    // Accéléromètre pour gravity — 30ms = ~33Hz
    _accelSub =
        accelerometerEventStream(
          samplingPeriod: const Duration(milliseconds: 30),
        ).listen((event) {
          // Alpha 0.15 = bon compromis réactivité/stabilité
          const alpha = 0.15;
          _gravity[0] = alpha * event.x + (1 - alpha) * _gravity[0];
          _gravity[1] = alpha * event.y + (1 - alpha) * _gravity[1];
          _gravity[2] = alpha * event.z + (1 - alpha) * _gravity[2];
          _hasGravityData = true;
          _updateOrientation();
        });

    // Magnétomètre pour la direction — 30ms = ~33Hz
    _magnetSub =
        magnetometerEventStream(
          samplingPeriod: const Duration(milliseconds: 30),
        ).listen((event) {
          const alpha = 0.15;
          _magnetic[0] = alpha * event.x + (1 - alpha) * _magnetic[0];
          _magnetic[1] = alpha * event.y + (1 - alpha) * _magnetic[1];
          _magnetic[2] = alpha * event.z + (1 - alpha) * _magnetic[2];
          _hasMagnetData = true;
          _updateOrientation();
        });
  }

  /// Calcule l'orientation à partir des données capteurs
  void _updateOrientation() {
    // Attendre d'avoir les deux types de données
    if (!_hasGravityData || !_hasMagnetData) return;

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
    pitch = pitch - 90;
    if (pitch < -90) pitch += 360;
    if (pitch > 90) pitch = 180 - pitch;

    // Calculer l'azimut brut à partir du magnétomètre et de la gravité
    final hx = _magnetic[1] * gz - _magnetic[2] * gy;
    final hy = _magnetic[2] * gx - _magnetic[0] * gz;
    double rawAzimuth = math.atan2(hy, hx) * 180 / math.pi;
    if (rawAzimuth < 0) rawAzimuth += 360;

    // ── Low-pass filter sur l'azimut avec gestion du wrap-around ──
    // Alpha 0.15 = plus réactif pour suivre la main de l'utilisateur
    if (!_azimuthInitialized) {
      _filteredAzimuth = rawAzimuth;
      _azimuthInitialized = true;
    } else {
      const alpha = 0.15;
      double diff = rawAzimuth - _filteredAzimuth;
      // Normaliser la différence dans [-180, 180]
      if (diff > 180) diff -= 360;
      if (diff < -180) diff += 360;
      _filteredAzimuth = (_filteredAzimuth + alpha * diff) % 360;
      if (_filteredAzimuth < 0) _filteredAzimuth += 360;
    }

    // Pitch aussi plus réactif
    _filteredPitch = 0.15 * pitch + 0.85 * _filteredPitch;

    // ── Stabiliser la référence avant de l'utiliser ──
    if (_referenceAzimuth == null) {
      _stableFrames++;
      if (_stableFrames >= _requiredStableFrames) {
        _referenceAzimuth = _filteredAzimuth;
      } else {
        // Pas encore stable, ne pas envoyer d'orientation
        return;
      }
    }

    // ── Azimut relatif au point de départ ──
    double relativeAzimuth = _filteredAzimuth - _referenceAzimuth!;
    // Normaliser dans [0, 360)
    relativeAzimuth = relativeAzimuth % 360;
    if (relativeAzimuth < 0) relativeAzimuth += 360;

    _currentOrientation = DeviceOrientation3D(
      azimuth: relativeAzimuth,
      pitch: _filteredPitch,
      roll: 0,
    );

    // ── Throttle les mises à jour UI pour éviter le flood ──
    final now = DateTime.now();
    if (now.difference(_lastUIUpdate) >= _uiUpdateInterval) {
      _lastUIUpdate = now;
      onOrientationChanged?.call(_currentOrientation);
    }

    // ── Vérifier la proximité avec hold-steady ──
    if (currentTarget != null && !isComplete) {
      final isInCooldown = now.difference(_lastCaptureTime) < _captureCooldown;
      final isNearRaw = !isInCooldown && _isNearTarget(currentTarget!);

      if (isNearRaw) {
        // Incrémenter le compteur de frames stables
        _nearTargetFrames++;
        if (_nearTargetFrames >= _requiredNearFrames && !_confirmedNear) {
          _confirmedNear = true;
          onTargetProximityChanged?.call(currentTarget!, true);
          // ★ Capture automatique !
          onAutoCapture?.call();
        }
      } else {
        // On sort de la zone → reset
        if (_confirmedNear || _nearTargetFrames > 0) {
          _nearTargetFrames = 0;
          _confirmedNear = false;
          onTargetProximityChanged?.call(currentTarget!, false);
        }
      }
    }
  }

  /// Vérifie si l'orientation actuelle est proche de la cible
  bool _isNearTarget(CaptureTarget target) {
    // Différence d'azimut avec gestion du wrap-around
    double azimuthDiff = (_currentOrientation.azimuth - target.azimuth);
    // Normaliser dans [-180, 180]
    if (azimuthDiff > 180) azimuthDiff -= 360;
    if (azimuthDiff < -180) azimuthDiff += 360;

    final elevationDiff = (_currentOrientation.pitch - target.elevation).abs();

    // Tolérance plus large pour les rangées près des pôles
    // (car les points sont plus proches en longitude)
    double azTolerance = AppConstants.angleTolerance;
    if (target.elevation.abs() > 60) {
      azTolerance *= 2.0; // Double tolérance pour zénith/nadir (très facile)
    } else if (target.elevation.abs() > 30) {
      azTolerance *= 1.25; // +25% pour les rangées intermédiaires
    }

    return azimuthDiff.abs() < azTolerance &&
        elevationDiff < AppConstants.elevationTolerance;
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  CAPTURE
  // ═══════════════════════════════════════════════════════════════════════

  /// Verrouille l'exposition et le focus
  Future<void> _lockExposureAndFocus() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      await _controller!.setExposureMode(ExposureMode.locked);
      await _controller!.setFocusMode(FocusMode.locked);
    } catch (_) {
      // Certains appareils ne supportent pas le verrouillage
    }
  }

  /// Capture une photo au point courant (avec retry pour les erreurs Android)
  Future<CapturedPhoto> capturePhoto() async {
    // ── Guards ──
    if (_controller == null || !_controller!.value.isInitialized) {
      throw Exception('Caméra non initialisée');
    }
    if (!_isReady) {
      throw Exception('Caméra pas encore prête');
    }
    if (isComplete) {
      throw Exception('Toutes les photos ont déjà été capturées');
    }
    if (currentTarget == null) {
      throw Exception('Aucune cible de capture');
    }
    if (_isTakingPicture) {
      throw Exception('Capture déjà en cours');
    }

    // Vérifier le cooldown
    final timeSinceLastCapture = DateTime.now().difference(_lastCaptureTime);
    if (timeSinceLastCapture < _captureCooldown) {
      throw Exception('Veuillez attendre entre les captures');
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

      // Marquer cette cible comme capturée
      _capturedTargetIndices.add(_currentTargetIndex);

      // Passer à la cible suivante (clampé)
      if (_currentTargetIndex < _targets.length) {
        _currentTargetIndex++;
      }

      _lastCaptureTime = DateTime.now();

      // Reset hold-steady pour la prochaine cible
      _nearTargetFrames = 0;
      _confirmedNear = false;

      // Délai minimum pour laisser le temps au pipeline caméra
      await Future.delayed(const Duration(milliseconds: 150));

      return photo;
    } catch (e) {
      throw Exception('Erreur lors de la capture: $e');
    } finally {
      _isTakingPicture = false;
    }
  }

  /// Tente de prendre la photo avec jusqu'à 3 retries
  Future<XFile> _takePictureWithRetry({int maxRetries = 3}) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        return await _controller!.takePicture();
      } catch (e) {
        if (attempt < maxRetries - 1) {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        } else {
          rethrow;
        }
      }
    }
    throw Exception('Échec de la capture après $maxRetries tentatives');
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  RESET & CLEANUP
  // ═══════════════════════════════════════════════════════════════════════

  /// Réinitialise la capture
  void reset() {
    _currentTargetIndex = 0;
    _capturedTargetIndices.clear();
    _referenceAzimuth = null;
    _stableFrames = 0;
    _azimuthInitialized = false;
    _isTakingPicture = false;
    _nearTargetFrames = 0;
    _confirmedNear = false;
    _lastCaptureTime = DateTime(2000);
    _generateTargets();
  }

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

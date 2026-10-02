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
  bool _useWideAngle = false; // Drapeau pour savoir si on est en grand angle

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
      // Nettoyage de sécurité en cas de rechargement/re-initialisation
      // Empêche la fuite de mémoire native et l'erreur de MessageQueue (Dead thread)
      if (_controller != null) {
        await _controller?.dispose();
        _controller = null;
      }

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

      // Essayer d'activer l'ultra grand angle (zoom min < 1.0)
      try {
        final minZoom = await _controller!.getMinZoomLevel();
        if (minZoom < 1.0) {
          await _controller!.setZoomLevel(minZoom);
          _useWideAngle = true;
        }
      } catch (_) {
        // Ignorer si échec (reste en normal)
      }

      // PAS DE VERROUILLAGE D'EXPOSITION NI DE FOCUS (on supprime _lockExposureAndFocus)
      // OpenCV Panorama a BESOIN que chaque image soit nette et correctement exposée.
      // Si on verrouille l'exposition sur le ciel, la terre sera noire (et vice versa).
      _isReady = true;
    } catch (e) {
      throw Exception('Erreur d\'initialisation de la caméra: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  CAPTEURS & ORIENTATION
  // ═══════════════════════════════════════════════════════════════════════

  // Buffers pour moyenne glissante (lissage du bruit)
  final List<List<double>> _gravBuffer = [];
  final List<List<double>> _magBuffer = [];
  static const int _bufferSize = 5; // Moyenne sur 5 échantillons

  /// Calcule la moyenne d'un buffer de vecteurs
  List<double> _average(List<List<double>> buffer) {
    double x = 0, y = 0, z = 0;
    for (var v in buffer) {
      x += v[0];
      y += v[1];
      z += v[2];
    }
    final count = buffer.length;
    return [x / count, y / count, z / count];
  }

  /// Démarre l'écoute des capteurs
  /// Utilise une moyenne glissante pour stabiliser les valeurs brutes
  void _startSensors() {
    // Fréquence ~33Hz (30ms)
    const sampling = Duration(milliseconds: 30);

    _accelSub = accelerometerEventStream(samplingPeriod: sampling).listen((
      event,
    ) {
      // Ajouter au buffer
      _gravBuffer.add([event.x, event.y, event.z]);
      if (_gravBuffer.length > _bufferSize) _gravBuffer.removeAt(0);

      // Calculer la moyenne
      final avg = _average(_gravBuffer);
      _gravity[0] = avg[0];
      _gravity[1] = avg[1];
      _gravity[2] = avg[2];
      _hasGravityData = true;
      _updateOrientation();
    });

    _magnetSub = magnetometerEventStream(samplingPeriod: sampling).listen((
      event,
    ) {
      _magBuffer.add([event.x, event.y, event.z]);
      if (_magBuffer.length > _bufferSize) _magBuffer.removeAt(0);

      final avg = _average(_magBuffer);
      _magnetic[0] = avg[0];
      _magnetic[1] = avg[1];
      _magnetic[2] = avg[2];
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

    // ── Calcul vectoriel robuste (sans Gimbal Lock) ──
    // On construit un repère orthonormé (North, East, Down)
    // basé sur la gravité et le champ magnétique.

    // 1. Vecteur Gravité (Down) normalisé
    // Note: Sensors_plus l'axe Z est positif sortant de l'écran.
    // Sur table: Z = +9.8. Debout: Y = +9.8.
    // Donc le vecteur gravité capteur pointe vers le HAUT (réaction sol).
    // On veut le vecteur Down (vers le centre de la terre).
    // Donc Down = -Gravity.
    // Mais simplifions: on travaille avec le vecteur "Up" (zénith local) = Gravity normalisé.
    final double gNorm = math.sqrt(gx * gx + gy * gy + gz * gz);
    if (gNorm < 0.1) return; // Erreur capteur
    final double ux = gx / gNorm;
    final double uy = gy / gNorm;
    final double uz = gz / gNorm; // Vecteur Up local (dans le repère device)

    // 2. Vecteur Magnétique (North-ish) normalisé
    final double mNorm = math.sqrt(
      _magnetic[0] * _magnetic[0] +
          _magnetic[1] * _magnetic[1] +
          _magnetic[2] * _magnetic[2],
    );
    if (mNorm < 0.1) return;
    final double mx = _magnetic[0] / mNorm;
    final double my = _magnetic[1] / mNorm;
    final double mz = _magnetic[2] / mNorm;

    // 3. Calcul du vecteur West = Cross(Up, Mag)
    // (Up x North = West car on est en repère direct main droite)
    double wx = uy * mz - uz * my;
    double wy = uz * mx - ux * mz;
    double wz = ux * my - uy * mx;
    final double wNorm = math.sqrt(wx * wx + wy * wy + wz * wz);

    if (wNorm < 0.1) {
      // Cas rare : magnétique vertical (au pôle nord magnétique)
      // On garde l'ancienne orientation ou on ignore
      return;
    }
    wx /= wNorm;
    wy /= wNorm;
    wz /= wNorm;

    // 4. Calcul du vecteur North réel (projeté sur horizon)
    // North = Cross(West, Up)
    final double nx = wy * uz - wz * uy;
    final double ny = wz * ux - wx * uz;
    final double nz = wx * uy - wy * ux;

    // 5. Vecteur de visée Caméra (View)
    // Caméra arrière regarde vers -Z (standard Android/iOS)
    // C = (0, 0, -1)
    const double cx = 0;
    const double cy = 0;
    const double cz = -1;

    // ── CALCULE DE L'ELEVATION ──
    // Élévation = angle entre View et plan horizontal
    // = 90 - angle(View, Up)
    // Dot(View, Up) = |View|*|Up|*cos(angle)
    // Ici View et Up sont unitaires.
    // Dot = cx*ux + cy*uy + cz*uz = -uz
    // cos(angle_zenith) = -uz
    // angle_zenith = acos(-uz)
    // Elevation = 90 - acos(-uz) * 180 / pi
    // Ou directement: Elevation = asin(-uz) * 180 / pi
    // asin(x) est défini sur [-1, 1], uz est entre [-1, 1].
    // Si uz = 1 (table), elev = asin(-1) = -90 (Nadir).
    // Si uz = 0 (debout), elev = asin(0) = 0 (Horizon).
    // Si uz = -1 (face bas), elev = asin(1) = 90 (Zénith).
    // CORRECT !
    double rawElevation = math.asin(-uz.clamp(-1.0, 1.0)) * 180 / math.pi;

    // ── CALCULE DE L'AZIMUT ──
    // On projette le vecteur View sur le plan horizontal
    // V_horiz = View - Dot(View, Up) * Up
    final double dotVU = -uz;
    double vhx = cx - dotVU * ux;
    double vhy = cy - dotVU * uy;
    double vhz = cz - dotVU * uz;

    // Normaliser la projection (sauf si proche du zénith/nadir)
    final double vhNorm = math.sqrt(vhx * vhx + vhy * vhy + vhz * vhz);

    double rawAzimuth;
    if (vhNorm < 0.1) {
      // Proche du zénith/nadir ("Gimbal Lock" partiel)
      // L'azimut de la VUE n'a plus de sens.
      // On utilise l'azimut du HAUT du téléphone (Y axis) pour stabiliser
      // Top = (0, 1, 0)
      const double tx = 0;
      const double ty = 1;
      const double tz = 0;
      final double dotTU = uy; // Dot(Top, Up)
      double thx = tx - dotTU * ux;
      double thy = ty - dotTU * uy;
      double thz = tz - dotTU * uz;
      // Normalisation implicite dans atan2
      // Projection sur (North, East)
      // East = -West
      final double eastComp = thx * -wx + thy * -wy + thz * -wz;
      final double northComp = thx * nx + thy * ny + thz * nz;
      rawAzimuth = math.atan2(eastComp, northComp) * 180 / math.pi;
    } else {
      // Cas normal
      // Projection sur la base (North, East)
      // East = -West (car West = Up x North => North x Up = -West? Non)
      // West = Up x North. North = West x Up.
      // E = N x U? No base is (N, E, D)? No base is (N, -W, U)?
      // West vector points West. East vector = -West.

      final double eastComp = vhx * -wx + vhy * -wy + vhz * -wz;
      final double northComp = vhx * nx + vhy * ny + vhz * nz;

      rawAzimuth = math.atan2(eastComp, northComp) * 180 / math.pi;
    }

    if (rawAzimuth < 0) rawAzimuth += 360;

    // Pitch dans le code existant = Elevation
    double pitch = rawElevation;

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
        }

        // ★ Capture automatique UNIQUEMENT si parfaitement aligné (< 4°)
        // Cela évite de capturer dès qu'on entre dans la zone verte (18°)
        if (_confirmedNear && _isAlignedForCapture(currentTarget!)) {
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

    // Tolérance adaptative selon l'élévation
    // Plus on est proche des pôles, plus les méridiens convergent
    double azTolerance = AppConstants.angleTolerance;

    if (target.elevation.abs() > 80) {
      // Aux pôles (Zénith/Nadir), l'azimut importe peu ou pas du tout
      azTolerance = 180.0;
    } else if (target.elevation.abs() > 40) {
      // Pour les rangées intermédiaires (±45°), les cibles sont espacées de 60°
      // Base 18° * 1.5 = 27°. Fenêtre de capture = 54°.
      // Marge de sécurité = 6° avant chevauchement. OK.
      azTolerance *= 1.5;
    }

    return azimuthDiff.abs() < azTolerance &&
        elevationDiff < AppConstants.elevationTolerance;
  }

  /// Vérifie l'alignment strict (< 4°) pour déclencher la capture automatique
  bool _isAlignedForCapture(CaptureTarget target) {
    double azimuthDiff = (_currentOrientation.azimuth - target.azimuth);
    if (azimuthDiff > 180) azimuthDiff -= 360;
    while (azimuthDiff < -180) {
      azimuthDiff += 360;
    }

    final elevationDiff = (_currentOrientation.pitch - target.elevation).abs();

    // Au Zénith/Nadir (>80°), l'azimut est toujours bon
    if (target.elevation.abs() > 80) {
      azimuthDiff = 0;
    }

    return azimuthDiff.abs() < 4.0 && elevationDiff < 4.0;
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  CAPTURE
  // ═══════════════════════════════════════════════════════════════════════

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

      // ── Wide Angle Setup ──
      final isWide = _useWideAngle;

      final photo = CapturedPhoto(
        path: newPath,
        azimuth: target.azimuth,
        elevation: target.elevation,
        capturedAt: DateTime.now(),
        rowIndex: target.rowIndex,
        indexInRow: target.indexInRow,
        // FOV FORCE PORTRAIT ULTRA-WIDE
        // Vertical = Grand côté (~100°), Horizontal = Petit côté (~83°)
        hFov: isWide ? 83.0 : null,
        vFov: isWide ? 100.0 : null,
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

      // Délai prolongé pour laisser le temps à l'autofocus et l'exposition
      // de s'ajuster avec la toute nouvelle vue pour que la luminosité
      // des photos soit identique (fondamental pour la création de la sphère OpenCV)
      await Future.delayed(const Duration(milliseconds: 300));

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

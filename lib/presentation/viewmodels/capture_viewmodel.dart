import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/math/quaternion.dart';
import '../../data/sensors/raw_sensors_orientation_source.dart';
import '../../data/sensors/rotation_vector_orientation_source.dart';
import '../../data/services/camera_service.dart';
import '../../data/services/stitching_service.dart';
import '../../domain/capture/capture_session.dart';
import '../../domain/models/captured_photo.dart';
import '../../domain/models/panorama.dart';
import '../../domain/services/orientation_source.dart';

/// Phase de l'écran de capture.
enum CapturePhase { initializing, ready, stitching, completed, error }

/// État peu fréquent de l'écran (photos, phase, assemblage).
@immutable
class CaptureState {
  const CaptureState({
    this.phase = CapturePhase.initializing,
    this.capturedCount = 0,
    this.total = 0,
    this.canFinish = false,
    this.stitchingProgress = 0,
    this.panorama,
    this.errorMessage,
    this.notice,
  });

  final CapturePhase phase;
  final int capturedCount;
  final int total;

  /// L'horizon est couvert : l'assemblage peut être lancé.
  final bool canFinish;
  final double stitchingProgress;
  final Panorama? panorama;
  final String? errorMessage;

  /// Message ponctuel (échec d'une prise de vue…), affiché puis effacé.
  final String? notice;

  CaptureState copyWith({
    CapturePhase? phase,
    int? capturedCount,
    int? total,
    bool? canFinish,
    double? stitchingProgress,
    Panorama? panorama,
    String? errorMessage,
    String? notice,
    bool clearNotice = false,
  }) {
    return CaptureState(
      phase: phase ?? this.phase,
      capturedCount: capturedCount ?? this.capturedCount,
      total: total ?? this.total,
      canFinish: canFinish ?? this.canFinish,
      stitchingProgress: stitchingProgress ?? this.stitchingProgress,
      panorama: panorama ?? this.panorama,
      errorMessage: errorMessage ?? this.errorMessage,
      notice: clearNotice ? null : (notice ?? this.notice),
    );
  }
}

/// Image instantanée de la visée, mise à jour à chaque mesure (≈ 50 Hz).
@immutable
class CaptureFrame {
  const CaptureFrame({
    this.orientation,
    this.activeTarget,
    this.suggestion,
    this.stability = 0,
    this.tooFast = false,
    this.tilted = false,
    this.flashCount = 0,
  });

  /// Orientation appareil → monde courante.
  final Quaternion? orientation;

  /// Cible dans le réticule (stabilisation en cours).
  final CaptureTarget? activeTarget;

  /// Cible restante la plus proche (guidage).
  final CaptureTarget? suggestion;

  /// Progression de la stabilisation (0..1) ; à 1, la photo est prise.
  final double stability;

  /// Rotation trop rapide.
  final bool tooFast;

  /// Téléphone incliné sur le côté.
  final bool tilted;

  /// Incrémenté à chaque prise de vue (flash de l'interface).
  final int flashCount;
}

/// Contrôleur de la capture : caméra, orientation, déclenchement
/// automatique, puis assemblage.
class CaptureController extends AutoDisposeNotifier<CaptureState> {
  /// Durée d'immobilité dans le réticule avant la prise de vue.
  static const double stableSeconds = 0.3;

  /// Tolérances angulaires du réticule (entrée / maintien, degrés).
  static const double enterToleranceDeg = 5;
  static const double keepToleranceDeg = 7;

  /// Decoding width of the photos drawn on the sphere during capture.
  static const int thumbnailWidth = 480;

  /// Seuils d'alerte.
  static const double tooFastDegPerSec = 60;
  static const double maxRollDeg = 15;

  late CameraService camera;
  late StitchingService _stitching;
  CaptureSession? session;

  /// Mesures haute fréquence pour la scène (écoutée par le peintre).
  final frame = ValueNotifier(const CaptureFrame());

  /// Photos par index de cible, et ordre de capture.
  final Map<int, CapturedPhoto> photos = {};
  final List<int> _order = [];

  /// Vignettes décodées par index de cible (affichées sur la sphère).
  final Map<int, ui.Image> thumbnails = {};

  final _stability = StabilityTracker();
  StreamSubscription<OrientationSample>? _orientationSub;
  bool _usingFallbackSource = false;
  bool _capturing = false;
  bool _wasTooFast = false;
  bool _disposed = false;

  @override
  CaptureState build() {
    camera = ref.read(cameraServiceProvider);
    _stitching = ref.read(stitchingServiceProvider);
    ref.onDispose(_dispose);
    Future.microtask(start);
    return const CaptureState();
  }

  /// Démarre une nouvelle capture.
  Future<void> start() async {
    state = const CaptureState();
    photos.clear();
    _order.clear();
    _disposeThumbnails();
    try {
      await camera.initialize();
      await camera.startSession();
    } catch (e) {
      _fail('Caméra indisponible : $e');
      return;
    }
    if (_disposed) return;
    session = CaptureSession(AppConstants.grid(wideAngle: camera.isWideAngle));
    _listenOrientation();
    _publish(phase: CapturePhase.ready);
  }

  /// Application mise en arrière-plan : libère caméra et capteurs.
  Future<void> pause() async {
    await _orientationSub?.cancel();
    _orientationSub = null;
    if (state.phase == CapturePhase.ready) await camera.dispose();
  }

  /// Retour au premier plan : reprend la capture là où elle en était.
  Future<void> resume() async {
    if (state.phase != CapturePhase.ready || camera.isInitialized) return;
    try {
      await camera.initialize();
    } catch (e) {
      _fail('Caméra indisponible : $e');
      return;
    }
    _listenOrientation();
    // Forcer la reconstruction de l'aperçu avec le nouveau contrôleur.
    state = state.copyWith();
  }

  void _listenOrientation() {
    _orientationSub?.cancel();
    final OrientationSource source = !_usingFallbackSource && Platform.isAndroid
        ? RotationVectorOrientationSource()
        : RawSensorsOrientationSource();
    _orientationSub = source.samples.listen(
      _onSample,
      onError: (Object e) {
        if (!_usingFallbackSource) {
          // Pas de vecteur de rotation : capteurs bruts.
          debugPrint('[capture] ${source.name} indisponible ($e), repli');
          _usingFallbackSource = true;
          _listenOrientation();
        } else {
          _fail('Capteurs d\'orientation indisponibles sur cet appareil.');
        }
      },
    );
  }

  void _onSample(OrientationSample sample) {
    final s = session;
    if (s == null || state.phase != CapturePhase.ready) return;
    final q = sample.deviceToWorld;
    s.anchor(q);

    final stableFor = _stability.add(q, sample.timestamp);
    final previous = frame.value.activeTarget;

    // Hystérésis : une cible déjà visée reste active un peu plus loin.
    CaptureTarget? active;
    if (previous != null &&
        !s.captured.contains(previous.index) &&
        s.angleToTarget(q, previous) <= keepToleranceDeg) {
      active = previous;
    } else {
      active = s.targetInReticle(q, toleranceDeg: enterToleranceDeg);
    }
    if (active?.index != previous?.index) {
      _stability.reset();
      if (active != null) HapticFeedback.selectionClick();
    }

    final speed = _stability.speedDegPerSec;
    final tooFast = speed > tooFastDegPerSec;
    if (tooFast && !_wasTooFast) HapticFeedback.lightImpact();
    _wasTooFast = tooFast;
    final elevation = CaptureSession.elevationDeg(q);
    final tilted =
        elevation.abs() < 60 && CaptureSession.rollDeg(q).abs() > maxRollDeg;

    final stability = active == null || tilted
        ? 0.0
        : (stableFor / stableSeconds).clamp(0.0, 1.0);

    frame.value = CaptureFrame(
      orientation: q,
      activeTarget: active,
      suggestion: active ?? s.nearestRemaining(q),
      stability: stability,
      tooFast: tooFast,
      tilted: tilted,
      flashCount: frame.value.flashCount,
    );

    if (active != null && stability >= 1 && !_capturing) {
      _capture(active, _stability.averageOrientation() ?? q);
    }
  }

  Future<void> _capture(CaptureTarget target, Quaternion orientation) async {
    final s = session!;
    _capturing = true;
    HapticFeedback.mediumImpact();
    final ts = DateTime.now().millisecondsSinceEpoch;
    try {
      final file = await camera.capture(
        'photo_r${target.row}_i${target.indexInRow}_$ts.jpg',
      );
      if (_disposed) return;
      photos[target.index] = CapturedPhoto(
        path: file.path,
        azimuth: target.azimuthDeg,
        elevation: target.elevationDeg,
        capturedAt: DateTime.now(),
        rowIndex: target.row,
        indexInRow: target.indexInRow,
        hFov: camera.hFov,
        vFov: camera.vFov,
        orientation: orientation,
      );
      _order.add(target.index);
      s.markCaptured(target);
      frame.value = CaptureFrame(
        orientation: frame.value.orientation,
        suggestion: frame.value.orientation == null
            ? null
            : s.nearestRemaining(frame.value.orientation!),
        flashCount: frame.value.flashCount + 1,
      );
      _publish();
      unawaited(_loadThumbnail(target.index, file));
      if (s.isComplete) unawaited(finish());
    } catch (e) {
      debugPrint('[capture] échec de la prise de vue : $e');
      HapticFeedback.heavyImpact();
      if (!_disposed) {
        state = state.copyWith(
          notice: 'Photo ratée, visez à nouveau l\'étoile.',
        );
      }
    } finally {
      _stability.reset();
      _capturing = false;
    }
  }

  Future<void> _loadThumbnail(int index, File file) async {
    try {
      final bytes = await file.readAsBytes();
      // Projected on the sphere, a photo spans almost the whole screen
      // width: 480 px keeps it sharp for ~1.2 MB of texture per photo.
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: thumbnailWidth,
      );
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      if (_disposed || !photos.containsKey(index)) {
        image.dispose();
        return;
      }
      thumbnails.remove(index)?.dispose();
      thumbnails[index] = image;
      // Redessine la scène avec la nouvelle vignette.
      frame.value = CaptureFrame(
        orientation: frame.value.orientation,
        activeTarget: frame.value.activeTarget,
        suggestion: frame.value.suggestion,
        stability: frame.value.stability,
        tooFast: frame.value.tooFast,
        tilted: frame.value.tilted,
        flashCount: frame.value.flashCount,
      );
    } catch (e) {
      debugPrint('[capture] vignette illisible : $e');
    }
  }

  /// Annule la dernière photo.
  Future<void> undoLast() async {
    final s = session;
    if (s == null || _order.isEmpty || _capturing) return;
    HapticFeedback.selectionClick();
    final index = _order.removeLast();
    final photo = photos.remove(index);
    thumbnails.remove(index)?.dispose();
    s.unmarkCaptured(s.targets[index]);
    if (photo != null) {
      await File(photo.path).delete().then((_) {}, onError: (_) {});
    }
    _publish();
  }

  /// Lance l'assemblage des photos prises.
  Future<void> finish() async {
    if (state.phase != CapturePhase.ready || _order.isEmpty) return;
    HapticFeedback.heavyImpact();
    await _orientationSub?.cancel();
    _orientationSub = null;
    // Libère la caméra : l'assemblage a besoin de mémoire.
    await camera.dispose();
    final ordered = [for (final i in _order) photos[i]!];
    await _writeManifest(ordered);
    _publish(phase: CapturePhase.stitching);
    try {
      final panorama = await _stitching.stitchPanorama(
        ordered,
        onProgress: (p) {
          if (!_disposed) state = state.copyWith(stitchingProgress: p);
        },
      );
      if (_disposed) return;
      HapticFeedback.mediumImpact();
      state = state.copyWith(
        phase: CapturePhase.completed,
        panorama: panorama,
        stitchingProgress: 1,
      );
    } on StitchingCancelledException {
      _fail('Assemblage annulé.');
    } catch (e) {
      _fail('Erreur d\'assemblage : $e');
    }
  }

  /// Manifeste de la session (session.json, à côté des photos) : chemin,
  /// quaternion et champ de vision de chaque photo, dans l'ordre de capture.
  /// Permet de rejouer exactement un assemblage hors de l'app (outil
  /// stitch_cli, skill test-stitcher-on-device).
  Future<void> _writeManifest(List<CapturedPhoto> ordered) async {
    if (ordered.isEmpty) return;
    try {
      final dir = File(ordered.first.path).parent;
      final manifest = {
        'grid': camera.isWideAngle ? 'wide' : 'standard',
        'photos': [
          for (final p in ordered)
            {
              'file': p.path.split('/').last,
              'row': p.rowIndex,
              'index': p.indexInRow,
              'quaternion': p.orientation.toList(),
              'hFov': p.hFov,
              'vFov': p.vFov,
              'capturedAt': p.capturedAt.toIso8601String(),
            },
        ],
      };
      await File(
        '${dir.path}/session.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
    } catch (e) {
      debugPrint('[capture] manifeste non écrit : $e');
    }
  }

  void cancelStitching() => _stitching.cancel();

  void clearNotice() => state = state.copyWith(clearNotice: true);

  void _publish({CapturePhase? phase}) {
    final s = session;
    if (_disposed) return;
    state = state.copyWith(
      phase: phase,
      capturedCount: s?.capturedCount ?? 0,
      total: s?.total ?? 0,
      canFinish: s?.horizonComplete ?? false,
    );
  }

  void _fail(String message) {
    if (_disposed) return;
    state = state.copyWith(phase: CapturePhase.error, errorMessage: message);
  }

  void _disposeThumbnails() {
    for (final image in thumbnails.values) {
      image.dispose();
    }
    thumbnails.clear();
  }

  void _dispose() {
    _disposed = true;
    _orientationSub?.cancel();
    camera.dispose();
    _disposeThumbnails();
    frame.dispose();
  }
}

final cameraServiceProvider = Provider.autoDispose<CameraService>(
  (ref) => CameraService(),
);

final stitchingServiceProvider = Provider.autoDispose<StitchingService>(
  (ref) => StitchingService(),
);

final captureControllerProvider =
    NotifierProvider.autoDispose<CaptureController, CaptureState>(
      CaptureController.new,
    );

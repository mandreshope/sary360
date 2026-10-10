import 'dart:io';

import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';

/// Caméra arrière de la capture : initialisation (ultra grand angle si
/// disponible), prise de vue et verrouillages.
///
/// Les capteurs d'orientation et la logique des cibles sont ailleurs
/// (OrientationSource, CaptureSession).
class CameraService {
  CameraController? _controller;
  bool _wideAngle = false;
  bool _locked = false;
  Directory? _sessionDir;

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  /// L'ultra grand angle est actif (zoom minimal < 1).
  bool get isWideAngle => _wideAngle;

  /// Champ de vision d'une photo en portrait (degrés).
  double get hFov => _wideAngle ? AppConstants.wideHFov : AppConstants.mainHFov;
  double get vFov => _wideAngle ? AppConstants.wideVFov : AppConstants.mainVFov;

  /// Rapport largeur / hauteur de l'aperçu en portrait.
  double get previewAspect {
    final ratio = _controller?.value.aspectRatio ?? 16 / 9;
    return ratio > 1 ? 1 / ratio : ratio;
  }

  Future<void> initialize() async {
    await dispose();
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw const CameraUnavailableException();
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = controller;
    await controller.initialize();
    await controller.lockCaptureOrientation();
    await controller.setFlashMode(FlashMode.off);

    // Ultra grand angle (zoom minimal < 1) : moins de photos à prendre.
    _wideAngle = false;
    try {
      final minZoom = await controller.getMinZoomLevel();
      if (minZoom < 1.0) {
        await controller.setZoomLevel(minZoom);
        _wideAngle = true;
      }
    } catch (_) {
      // Zoom non pris en charge : objectif principal.
    }
    _locked = false;
  }

  /// Dossier des photos de la session, vidé à chaque nouvelle capture.
  Future<Directory> startSession() async {
    final temp = await getTemporaryDirectory();
    final dir = Directory('${temp.path}/${AppConstants.tempFolder}');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    return _sessionDir = dir;
  }

  /// Prend une photo et la range dans le dossier de session sous [name].
  ///
  /// Après la première photo, la mise au point est verrouillée : sinon le
  /// plugin relance un autofocus à chaque prise, qui n'aboutit jamais sur
  /// un objectif à mise au point fixe (ultra grand angle) et expire au bout
  /// de 3 s, d'où des photos bougées.
  ///
  /// L'exposition n'est pas verrouillée : avec une exposition verrouillée,
  /// la séquence de mesure du plugin attend un état qui n'arrive jamais et
  /// ajoute 3 s par photo. L'assemblage compense les écarts d'exposition.
  Future<File> capture(String name) async {
    final controller = _controller;
    final dir = _sessionDir;
    if (controller == null || dir == null) {
      throw StateError('Caméra non initialisée');
    }
    final image = await _takePictureWithRetry(controller);
    // Déplacement du fichier du plugin vers le dossier de session.
    final file = await File(image.path).copy('${dir.path}/$name');
    try {
      await File(image.path).delete();
    } on FileSystemException {
      // Fichier temporaire du plugin : sans importance s'il reste.
    }
    if (!_locked) {
      _locked = true;
      try {
        await controller.setFocusMode(FocusMode.locked);
      } catch (_) {
        // Mise au point non verrouillable : sans conséquence.
      }
    }
    return file;
  }

  Future<XFile> _takePictureWithRetry(CameraController controller) async {
    const attempts = 3;
    for (var i = 0; i < attempts; i++) {
      try {
        return await controller.takePicture();
      } on CameraException {
        if (i == attempts - 1) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 300 * (i + 1)));
      }
    }
    throw StateError('inatteignable');
  }

  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}

/// Aucune caméra utilisable sur l'appareil.
class CameraUnavailableException implements Exception {
  const CameraUnavailableException();

  @override
  String toString() => 'Aucune caméra disponible sur cet appareil';
}

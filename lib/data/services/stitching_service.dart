import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/math/camera_rotation.dart';
import '../../domain/models/captured_photo.dart';
import '../../domain/models/panorama.dart';
import '../native/sary_stitcher_bindings.g.dart';

/// Levée quand l'assemblage a été annulé par l'utilisateur.
class StitchingCancelledException implements Exception {
  const StitchingCancelledException();

  @override
  String toString() => 'Assemblage annulé';
}

/// Échec de l'assemblage natif, avec un message destiné à l'utilisateur.
class StitchingException implements Exception {
  const StitchingException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Requête envoyée à l'isolate d'assemblage (types simples uniquement).
class _NativeRequest {
  const _NativeRequest({
    required this.paths,
    required this.rotations,
    required this.hFov,
    required this.neighborAngle,
    required this.outputWidth,
    required this.outputPath,
    required this.progressAddress,
    required this.cancelAddress,
  });

  final List<String> paths;

  /// Rotations caméra → monde OpenCV, 9 réels par photo.
  final List<double> rotations;
  final double hFov;
  final double neighborAngle;
  final int outputWidth;
  final String outputPath;

  /// Adresses des cellules partagées allouées par l'isolate principal.
  final int progressAddress;
  final int cancelAddress;
}

/// Compte rendu renvoyé par l'isolate.
class _NativeResponse {
  const _NativeResponse({
    required this.status,
    required this.message,
    required this.refined,
    required this.matchedPairs,
    required this.medianCorrection,
    required this.elapsedMs,
  });

  final int status;
  final String message;
  final bool refined;
  final int matchedPairs;
  final double medianCorrection;
  final int elapsedMs;
}

/// Assemblage des photos en sphère équirectangulaire via le module C++
/// (native/stitcher), exécuté dans un isolate dédié.
///
/// La progression et l'annulation passent par deux cellules de mémoire
/// native partagées : le module écrit la progression, l'isolate principal
/// la lit périodiquement et peut lever le drapeau d'annulation.
class StitchingService {
  ffi.Pointer<ffi.Int32>? _cancelFlag;

  /// Demande l'arrêt de l'assemblage en cours (sans effet sinon).
  void cancel() {
    final flag = _cancelFlag;
    if (flag != null) flag.value = 1;
  }

  /// Assemble les photos en panorama sphérique 360°.
  Future<Panorama> stitchPanorama(
    List<CapturedPhoto> photos, {
    void Function(double progress)? onProgress,
    int outputWidth = AppConstants.equirectWidth,
  }) async {
    if (photos.isEmpty) {
      throw const StitchingException('Aucune photo à assembler');
    }
    if (_cancelFlag != null) {
      throw const StitchingException('Un assemblage est déjà en cours');
    }

    final appDir = await getApplicationDocumentsDirectory();
    final panoramaDir = Directory(
      '${appDir.path}/${AppConstants.panoramasFolder}',
    );
    if (!panoramaDir.existsSync()) {
      panoramaDir.createSync(recursive: true);
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = '${panoramaDir.path}/panorama_$timestamp.jpg';

    // Rotations des capteurs, recentrées pour que la première photo soit
    // au centre du panorama.
    final rotations = CameraRotation.recenterYaw([
      for (final p in photos) CameraRotation.openCvCameraToWorld(p.orientation),
    ]);

    // Toutes les photos d'une capture partagent le même objectif.
    final hFov = photos.first.hFov ?? AppConstants.mainHFov;
    final vFov = photos.first.vFov ?? AppConstants.mainVFov;

    final progress = calloc<ffi.Float>();
    final cancelFlag = calloc<ffi.Int32>();
    _cancelFlag = cancelFlag;

    // Lecture périodique de la progression écrite par le module natif.
    var lastProgress = -1.0;
    final poll = Timer.periodic(const Duration(milliseconds: 120), (_) {
      final v = progress.value;
      if (v != lastProgress) {
        lastProgress = v;
        onProgress?.call(v);
      }
    });

    try {
      final request = _NativeRequest(
        paths: [for (final p in photos) p.path],
        rotations: [for (final r in rotations) ...r],
        hFov: hFov,
        // Au-delà, deux photos ne se chevauchent plus : inutile de les
        // comparer.
        neighborAngle: math.max(hFov, vFov) - 5,
        outputWidth: outputWidth,
        outputPath: outputPath,
        progressAddress: progress.address,
        cancelAddress: cancelFlag.address,
      );
      final response = await _runInIsolate(request);

      debugPrint(
        '[stitch] statut ${response.status} en ${response.elapsedMs} ms, '
        '${response.matchedPairs} paires, '
        '${response.refined ? 'rotations affinées (correction médiane '
                  '${response.medianCorrection.toStringAsFixed(1)}°)' : 'rotations des capteurs'}'
        ' — ${response.message}',
      );

      switch (response.status) {
        case SARY_OK:
          break;
        case SARY_ERR_CANCELLED:
          throw const StitchingCancelledException();
        case SARY_ERR_OUT_OF_MEMORY:
          throw StitchingException(
            'Mémoire insuffisante pour assembler la sphère'
            '${outputWidth > AppConstants.equirectWidth ? ' : essayez la définition standard' : ''}.',
          );
        case SARY_ERR_IMAGE_READ:
          throw StitchingException('Photo illisible : ${response.message}');
        default:
          throw StitchingException(
            'Échec de l\'assemblage : ${response.message}',
          );
      }
      onProgress?.call(1.0);
    } finally {
      poll.cancel();
      _cancelFlag = null;
      calloc.free(progress);
      calloc.free(cancelFlag);
    }

    return Panorama(
      id: timestamp.toString(),
      name: 'Panorama ${DateTime.now().toString().split('.')[0]}',
      createdAt: DateTime.now(),
      stitchedImagePath: outputPath,
      originalPhotoPaths: photos.map((p) => p.path).toList(),
      photoCount: photos.length,
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  ISOLATE : appel bloquant au module natif
  // ═══════════════════════════════════════════════════════════════════

  /// Lance l'assemblage dans un isolate. La closure est créée ici, dans une
  /// méthode statique, pour ne capturer que [request] : créée dans
  /// stitchPanorama, elle embarquerait tout son contexte (callback de
  /// progression → ViewModel → CameraController), qu'un isolate ne peut pas
  /// recevoir.
  static Future<_NativeResponse> _runInIsolate(_NativeRequest request) =>
      Isolate.run(() => _stitchInIsolate(request));

  static ffi.DynamicLibrary _openLibrary() {
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libsary_stitcher.so');
    }
    if (Platform.isIOS) return ffi.DynamicLibrary.process();
    throw UnsupportedError(
      'Assemblage natif indisponible sur cette plateforme',
    );
  }

  static Future<_NativeResponse> _stitchInIsolate(_NativeRequest req) async {
    final bindings = SaryStitcherBindings(_openLibrary());
    final n = req.paths.length;

    final response = using((arena) {
      final paths = arena<ffi.Pointer<ffi.Char>>(n);
      for (var i = 0; i < n; i++) {
        paths[i] = req.paths[i].toNativeUtf8(allocator: arena).cast();
      }
      final rotations = arena<ffi.Float>(req.rotations.length);
      for (var i = 0; i < req.rotations.length; i++) {
        rotations[i] = req.rotations[i];
      }

      final params = SaryStitchParams.$allocate(
        arena,
        image_count: n,
        image_paths: paths,
        rotations: rotations,
        hfov_deg: req.hFov,
        output_width: req.outputWidth,
        jpeg_quality: AppConstants.jpegQuality,
        work_megapix: 0.6,
        // Raccords GraphCut : l'étape la plus coûteuse, 0,05 Mpx suffit.
        seam_megapix: 0.05,
        compose_megapix: -1,
        max_features: 3000,
        neighbor_max_angle_deg: req.neighborAngle,
        refine: 1,
        output_path: req.outputPath.toNativeUtf8(allocator: arena).cast(),
        progress: ffi.Pointer.fromAddress(req.progressAddress),
        cancel: ffi.Pointer.fromAddress(req.cancelAddress),
      );
      final result = arena<SaryStitchResult>();

      final status = bindings.sary_stitch(params, result);
      final r = result.ref;
      return _NativeResponse(
        status: status,
        message: _readMessage(r.message),
        refined: r.refined == 1,
        matchedPairs: r.matched_pairs,
        medianCorrection: r.median_correction_deg,
        elapsedMs: r.elapsed_ms,
      );
    });

    if (response.status == SARY_OK) {
      // Métadonnées Photo Sphere : l'image couvre toute la sphère.
      final file = File(req.outputPath);
      final bytes = await file.readAsBytes();
      final width = req.outputWidth;
      await file.writeAsBytes(_injectXmpMetadata(bytes, width, width ~/ 2));
    }
    return response;
  }

  /// Lit le message C (UTF-8 terminé par 0) d'un tableau de taille fixe.
  static String _readMessage(ffi.Array<ffi.Char> chars) {
    final bytes = <int>[];
    for (var i = 0; i < 256; i++) {
      final c = chars[i];
      if (c == 0) break;
      bytes.add(c & 0xFF);
    }
    return const Utf8Decoder(allowMalformed: true).convert(bytes);
  }

  Future<void> cleanTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final photoDir = Directory('${tempDir.path}/${AppConstants.tempFolder}');
      if (photoDir.existsSync()) {
        photoDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════════
  //  MÉTADONNÉES XMP (Google Photo Sphere)
  //  Injecte les tags nécessaires pour que Facebook / Google Photos
  //  reconnaissent l'image comme un panorama 360° interactif.
  // ═══════════════════════════════════════════════════════════════════

  static List<int> _injectXmpMetadata(List<int> jpeg, int width, int height) {
    const String xmpHeader = 'http://ns.adobe.com/xap/1.0/\x00';

    final String xmpContent =
        '''
<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Sary360">
  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
    <rdf:Description rdf:about="" xmlns:GPano="http://ns.google.com/photos/1.0/panorama/">
      <GPano:UsePanoramaViewer>True</GPano:UsePanoramaViewer>
      <GPano:CaptureSoftware>Sary360</GPano:CaptureSoftware>
      <GPano:ProjectionType>equirectangular</GPano:ProjectionType>
      <GPano:PoseHeadingDegrees>0.0</GPano:PoseHeadingDegrees>
      <GPano:CroppedAreaLeftPixels>0</GPano:CroppedAreaLeftPixels>
      <GPano:CroppedAreaTopPixels>0</GPano:CroppedAreaTopPixels>
      <GPano:FullPanoWidthPixels>$width</GPano:FullPanoWidthPixels>
      <GPano:FullPanoHeightPixels>$height</GPano:FullPanoHeightPixels>
      <GPano:CroppedAreaImageWidthPixels>$width</GPano:CroppedAreaImageWidthPixels>
      <GPano:CroppedAreaImageHeightPixels>$height</GPano:CroppedAreaImageHeightPixels>
    </rdf:Description>
  </rdf:RDF>
</x:xmpmeta>''';

    final hdrBytes = xmpHeader.codeUnits;
    final cntBytes = xmpContent.codeUnits;
    final int len = 2 + hdrBytes.length + cntBytes.length;

    final app1 = [
      0xFF,
      0xE1,
      (len >> 8) & 0xFF,
      len & 0xFF,
      ...hdrBytes,
      ...cntBytes,
    ];

    if (jpeg.length >= 2 && jpeg[0] == 0xFF && jpeg[1] == 0xD8) {
      return [0xFF, 0xD8, ...app1, ...jpeg.sublist(2)];
    }
    return jpeg;
  }
}

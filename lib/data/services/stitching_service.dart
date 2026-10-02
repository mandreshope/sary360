import 'dart:io';
import 'dart:isolate';
import 'package:path_provider/path_provider.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../core/constants/app_constants.dart';
import '../../domain/models/captured_photo.dart';
import '../../domain/models/panorama.dart';

/// Paramètres pour l'isolate de stitching sphérique
class StitchingParams {
  final List<PhotoData> photos;
  final String outputPath;
  final SendPort sendPort;

  const StitchingParams({
    required this.photos,
    required this.outputPath,
    required this.sendPort,
  });
}

/// Données sérialisables d'une photo (pour l'isolate)
class PhotoData {
  final String path;
  final double azimuth;
  final double elevation;
  final double? hFov;
  final double? vFov;

  const PhotoData({
    required this.path,
    required this.azimuth,
    required this.elevation,
    this.hFov,
    this.vFov,
  });
}

/// Résultat du stitching
class StitchingResult {
  final bool success;
  final String? panoramaPath;
  final String? error;
  final double progress;

  const StitchingResult({
    required this.success,
    this.panoramaPath,
    this.error,
    this.progress = 0.0,
  });
}

/// Service de stitching sphérique avec OpenCV
class StitchingService {
  /// Assemble les photos en panorama sphérique 360°
  Future<Panorama> stitchPanorama(
    List<CapturedPhoto> photos, {
    Function(double)? onProgress,
  }) async {
    if (photos.isEmpty) {
      throw Exception('Aucune photo à assembler');
    }

    final receivePort = ReceivePort();

    final appDir = await getApplicationDocumentsDirectory();
    final panoramaDir = Directory(
      '${appDir.path}/${AppConstants.panoramasFolder}',
    );
    if (!panoramaDir.existsSync()) {
      panoramaDir.createSync(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = '${panoramaDir.path}/panorama_$timestamp.jpg';

    // Convertir en données sérialisables pour l'isolate
    final photoDataList = photos
        .map(
          (p) => PhotoData(
            path: p.path,
            azimuth: p.azimuth,
            elevation: p.elevation,
            hFov: p.hFov,
            vFov: p.vFov,
          ),
        )
        .toList();

    await Isolate.spawn(
      _stitchInIsolate,
      StitchingParams(
        photos: photoDataList,
        outputPath: outputPath,
        sendPort: receivePort.sendPort,
      ),
    );

    StitchingResult? finalResult;
    await for (final result in receivePort) {
      if (result is StitchingResult) {
        onProgress?.call(result.progress);
        if (result.success || result.error != null) {
          finalResult = result;
          receivePort.close();
          break;
        }
      }
    }

    if (finalResult == null || !finalResult.success) {
      throw Exception(
        finalResult?.error ?? 'Erreur inconnue lors du stitching',
      );
    }

    return Panorama(
      id: timestamp.toString(),
      name: 'Panorama ${DateTime.now().toString().split('.')[0]}',
      createdAt: DateTime.now(),
      stitchedImagePath: finalResult.panoramaPath!,
      originalPhotoPaths: photos.map((p) => p.path).toList(),
      photoCount: photos.length,
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  ISOLATE - Tout le traitement lourd se fait ici avec OpenCV
  // ═══════════════════════════════════════════════════════════════════

  static Future<void> _stitchInIsolate(StitchingParams params) async {
    try {
      final photos = params.photos;
      final outputPath = params.outputPath;
      final sendPort = params.sendPort;

      // Désactiver OpenCL pour éviter les plantages (glob_rec error) liés à la
      // recherche des pilotes GPU cachés empêchés par les Sandbox Android
      cv.setUseOpenCL(false);

      // 1. Lire et redimensionner toutes les images pour OpenCV
      // C'est vital avec 42 photos : si on laisse la résolution totale (4000x3000),
      // la recherche des millions de points-clés prendra des heures sur mobile.
      final cvImages = cv.VecMat();
      for (int i = 0; i < photos.length; i++) {
        sendPort.send(
          StitchingResult(success: false, progress: (i / photos.length) * 0.20),
        );
        final matRaw = cv.imread(photos[i].path, flags: cv.IMREAD_COLOR);
        if (matRaw.isEmpty) {
          sendPort.send(
            StitchingResult(
              success: false,
              error: 'Impossible de décoder l\'image ${i + 1}',
            ),
          );
          return;
        }

        // REDIMENSIONNEMENT AGRESSIF POUR LA VITESSE
        final double maxDim = 800.0;
        double scale = 1.0;
        if (matRaw.cols > matRaw.rows && matRaw.cols > maxDim) {
          scale = maxDim / matRaw.cols;
        } else if (matRaw.rows > maxDim) {
          scale = maxDim / matRaw.rows;
        }

        final int newW = (matRaw.cols * scale).toInt();
        final int newH = (matRaw.rows * scale).toInt();

        final matResized = cv.resize(matRaw, (
          newW,
          newH,
        ), interpolation: cv.INTER_AREA);
        matRaw.dispose(); // Libère la RAM de l'image géante immédiatement

        cvImages.add(matResized);
      }

      sendPort.send(const StitchingResult(success: false, progress: 0.25));

      // 2. Initialiser le Stitcher OpenCV
      // Mode PANORAMA (Projection sphérique 360°)
      // Les paramètres "registrationResol" et "panoConfidenceThresh" ci-dessous
      // empêchent l'erreur ERR_CAMERA_PARAMS_ADJUST_FAIL même en mode PANORAMA.
      final stitcher = cv.Stitcher.create(mode: cv.StitcherMode.PANORAMA);

      // Ajustements essentiels pour la stabilité sur mobile (mémoire)
      stitcher.compositingResol =
          1.0; // Les images ont déjà été redimensionnées manuellement, on garde la taille !

      // Paramètres CRUCIAUX pour empêcher l'ajusteur de caméra de planter (ERR_CAMERA_PARAMS_ADJUST_FAIL)
      stitcher.panoConfidenceThresh =
          0.1; // (défaut 1.0) On force OpenCV à accepter les paires d'images même si la corrélation est très faible
      stitcher.registrationResol =
          1.0; // Les images ont déjà été réduites, 1.0 permet trouver des points clés précis sur l'image compressée
      stitcher.waveCorrection =
          false; // Désactiver la correction d'onde horizontale évite aux paramètres de caméra de paniquer

      sendPort.send(const StitchingResult(success: false, progress: 0.30));

      // 3. Effectuer le stitching
      // Attention: .stitch peut être lent, on prévient l'UI
      sendPort.send(const StitchingResult(success: false, progress: 0.40));

      final (status, pano) = stitcher.stitch(cvImages);

      sendPort.send(const StitchingResult(success: false, progress: 0.85));

      if (status != cv.StitcherStatus.OK) {
        // Nettoyage rapide avant Exception
        pano.dispose();
        for (int i = 0; i < cvImages.length; i++) {
          cvImages[i].dispose();
        }
        cvImages.dispose();
        stitcher.dispose();

        throw Exception(
          "Erreur de stitching OpenCV (Status: ${status.name}).\n"
          "Assurez-vous que les images se chevauchent suffisamment et ont des détails distincts.",
        );
      }

      // 4. Sauvegarder
      cv.imwrite(outputPath, pano);

      sendPort.send(const StitchingResult(success: false, progress: 0.95));

      // 5. Injecter les métadonnées XMP (Photo Sphere)
      final bytes = await File(outputPath).readAsBytes();
      final jpegWithXmp = _injectXmpMetadata(bytes, pano.cols, pano.rows);
      await File(outputPath).writeAsBytes(jpegWithXmp);

      // 6. Libération de la mémoire OpenCV (très important en Dart FFI)
      pano.dispose();
      for (int i = 0; i < cvImages.length; i++) {
        cvImages[i].dispose();
      }
      cvImages.dispose();
      stitcher.dispose();

      sendPort.send(
        StitchingResult(success: true, panoramaPath: outputPath, progress: 1.0),
      );
    } catch (e) {
      params.sendPort.send(
        StitchingResult(success: false, error: e.toString()),
      );
    }
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
} // fin StitchingService

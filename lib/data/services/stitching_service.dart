import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';

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

  const PhotoData({
    required this.path,
    required this.azimuth,
    required this.elevation,
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

/// Service de stitching sphérique - assemble en projection équirectangulaire
/// Inspiré de la méthode de projection inverse (reverse mapping) pour un
/// rendu propre sans trous.
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

  /// Point d'entrée de l'isolate de stitching
  static Future<void> _stitchInIsolate(StitchingParams params) async {
    // 1. Essayer avec OpenCV (Qualité "Google")
    bool success = false;
    try {
      success = await _stitchWithOpenCV(params);
    } catch (e) {
      // OpenCV a échoué (souvent manque de features ou mémoire)
      // On continue vers le fallback
    }

    if (success) return;

    // 2. Fallback : Méthode manuelle (Reverse Mapping)
    // Moins jolie mais robuste (marche toujours tant qu'il y a des photos)
    await _stitchLegacy(params);
  }

  /// Stitching avec OpenCV (Sticher class)
  /// Nécessite opencv_dart
  static Future<bool> _stitchWithOpenCV(StitchingParams params) async {
    final sendPort = params.sendPort;
    final photos = params.photos;
    final outputPath = params.outputPath;

    sendPort.send(const StitchingResult(success: false, progress: 0.1));

    // Charger les images en Mat
    final List<cv.Mat> images = [];
    try {
      for (int i = 0; i < photos.length; i++) {
        final mat = cv.imread(photos[i].path);
        if (mat.isEmpty) continue;
        images.add(mat);

        sendPort.send(
          StitchingResult(
            success: false,
            progress: 0.1 + (i / photos.length) * 0.2,
          ),
        );
      }

      if (images.length < 2) return false;

      sendPort.send(const StitchingResult(success: false, progress: 0.4));

      // Créer le Stitcher
      final stitcher = cv.Stitcher.create(mode: cv.StitcherMode.PANORAMA);

      // Convertir en VecMat pour l'interop C++
      final vecImages = cv.VecMat.fromList(images);
      final (status, pano) = stitcher.stitch(vecImages);
      vecImages.dispose();

      if (status != cv.StitcherStatus.OK) {
        // Erreur OpenCV (ex: ERR_NEED_MORE_IMGS)
        return false;
      }

      sendPort.send(const StitchingResult(success: false, progress: 0.8));

      // Sauvegarder le résultat
      // Convertir Mat -> Jpg bytes pour injecter XMP
      final success = cv.imwrite(outputPath, pano);

      if (success) {
        // Réouvrir pour injecter XMP
        final file = File(outputPath);
        final bytes = await file.readAsBytes();
        final width = pano.cols;
        final height = pano.rows;

        final injected = _injectXmpMetadata(bytes, width, height);
        await file.writeAsBytes(injected);

        sendPort.send(
          StitchingResult(
            success: true,
            panoramaPath: outputPath,
            progress: 1.0,
          ),
        );
        return true;
      }
      return false;
    } catch (e) {
      // En cas de crash OpenCV
      return false;
    } finally {
      // Nettoyage mémoire mémoire native
      for (final img in images) {
        img.dispose();
      }
      // pano est disposé automatiqument par dart ou pas ?
      // opencv_dart gère le GC via Finalizer normalement, mais dispose() est mieux.
    }
  }

  /// Stitching sphérique MANUEL (Fallback)
  /// Utilise la méthode « reverse mapping »
  static Future<void> _stitchLegacy(StitchingParams params) async {
    try {
      final photos = params.photos;
      final outputPath = params.outputPath;
      final sendPort = params.sendPort;

      // Phase 1: Charger toutes les images
      final List<_LoadedPhoto> loadedPhotos = [];
      for (int i = 0; i < photos.length; i++) {
        sendPort.send(
          StitchingResult(success: false, progress: (i / photos.length) * 0.4),
        );

        final file = File(photos[i].path);
        final bytes = await file.readAsBytes();
        final image = img.decodeImage(bytes);
        if (image == null) {
          sendPort.send(
            StitchingResult(
              success: false,
              error: 'Impossible de décoder l\'image ${i + 1}',
            ),
          );
          return;
        }

        // Redimensionner à une taille raisonnable pour le traitement
        final resized = _resizeImage(image, 1200);
        loadedPhotos.add(
          _LoadedPhoto(
            image: resized,
            azimuth: photos[i].azimuth,
            elevation: photos[i].elevation,
          ),
        );
      }

      sendPort.send(const StitchingResult(success: false, progress: 0.45));

      // Phase 2: Projeter via reverse mapping
      final equirect = _reverseMapToEquirectangular(loadedPhotos, sendPort);

      sendPort.send(const StitchingResult(success: false, progress: 0.85));

      // Phase 3: Remplir les trous restants (régions polaires non couvertes)
      _fillHolesMultiPass(equirect);

      sendPort.send(const StitchingResult(success: false, progress: 0.90));

      // Phase 4: Post-traitement
      final balanced = _balanceColors(equirect);

      sendPort.send(const StitchingResult(success: false, progress: 0.95));

      // Phase 5: Sauvegarder
      final outputFile = File(outputPath);

      // Encoder en JPEG
      final jpegBytes = img.encodeJpg(
        balanced,
        quality: AppConstants.jpegQuality,
      );

      // Injecter les métadonnées XMP pour Facebook/Google Photos
      final jpegWithXmp = _injectXmpMetadata(
        jpegBytes,
        balanced.width,
        balanced.height,
      );

      await outputFile.writeAsBytes(jpegWithXmp);

      sendPort.send(
        StitchingResult(success: true, panoramaPath: outputPath, progress: 1.0),
      );
    } catch (e) {
      params.sendPort.send(
        StitchingResult(success: false, error: e.toString()),
      );
    }
  }

  /// Projection inverse : pour chaque pixel de l'équirectangulaire,
  /// on trouve dans quelle(s) photo(s) source il se projette et on
  /// fait un blending pondéré.
  static img.Image _reverseMapToEquirectangular(
    List<_LoadedPhoto> photos,
    SendPort sendPort,
  ) {
    final int outW = AppConstants.equirectWidth;
    final int outH = AppConstants.equirectHeight;
    final equirect = img.Image(width: outW, height: outH);

    // FOV de la caméra
    final double hFovRad = AppConstants.cameraHFov * math.pi / 180;
    final double vFovRad = AppConstants.cameraVFov * math.pi / 180;

    // Pré-calculer les directions de chaque photo (vecteur central)
    final List<_PhotoProjection> projections = photos.map((p) {
      final azRad = p.azimuth * math.pi / 180;
      final elRad = p.elevation * math.pi / 180;
      return _PhotoProjection(
        photo: p,
        azRad: azRad,
        elRad: elRad,
        hFovRad: hFovRad,
        vFovRad: vFovRad,
        cosAz: math.cos(azRad),
        sinAz: math.sin(azRad),
        cosEl: math.cos(elRad),
        sinEl: math.sin(elRad),
      );
    }).toList();

    // Pour chaque pixel de sortie
    for (int eqY = 0; eqY < outH; eqY++) {
      // Envoyer la progression
      if (eqY % 100 == 0) {
        final prog = 0.45 + (eqY / outH) * 0.4;
        sendPort.send(StitchingResult(success: false, progress: prog));
      }

      for (int eqX = 0; eqX < outW; eqX++) {
        // Convertir pixel → latitude/longitude
        // longitude: 0 à 2π (gauche à droite)
        // latitude: π/2 à -π/2 (haut à bas)
        final double lon = (eqX / outW) * 2.0 * math.pi - math.pi;
        final double lat = (0.5 - eqY / outH) * math.pi;

        // Direction 3D correspondant à ce pixel
        final double dirX = math.cos(lat) * math.sin(lon);
        final double dirY = math.sin(lat);
        final double dirZ = math.cos(lat) * math.cos(lon);

        // Chercher dans chaque photo source si ce rayon y tombe
        double sumR = 0, sumG = 0, sumB = 0, sumW = 0;

        for (final proj in projections) {
          // Appliquer la rotation inverse de la caméra
          // (on transforme le rayon global → repère local de la caméra)

          // Rotation inverse autour de Y (azimut)
          final double rx = dirX * proj.cosAz - dirZ * proj.sinAz;
          final double rz = dirX * proj.sinAz + dirZ * proj.cosAz;

          // Rotation inverse autour de X (élévation)
          final double ry = dirY * proj.cosEl + rz * proj.sinEl;
          final double rz2 = -dirY * proj.sinEl + rz * proj.cosEl;

          // Si le point est derrière la caméra, ignorer
          if (rz2 <= 0.01) continue;

          // Projeter sur le plan image (perspective pinhole)
          final double localAz = math.atan2(rx, rz2);
          final double localEl = math.atan2(ry, rz2);

          // Vérifier si on est dans le FOV
          if (localAz.abs() > hFovRad * 0.52) continue;
          if (localEl.abs() > vFovRad * 0.52) continue;

          // Convertir en coordonnées pixel de l'image source
          final double nx = localAz / hFovRad + 0.5;
          final double ny = 0.5 - localEl / vFovRad;

          final int imgW = proj.photo.image.width;
          final int imgH = proj.photo.image.height;
          final int px = (nx * imgW).round().clamp(0, imgW - 1);
          final int py = (ny * imgH).round().clamp(0, imgH - 1);

          // Poids basé sur la distance au centre de l'image
          // Centre = plus fiable, bords = distorsion
          final double distFromCenter = math.sqrt(
            (nx - 0.5) * (nx - 0.5) + (ny - 0.5) * (ny - 0.5),
          );
          // Falloff doux avec cos^2
          final double maxDist = 0.5;
          final double normDist = (distFromCenter / maxDist).clamp(0.0, 1.0);
          // Blending plus "sharp" pour réduire les fantômes (saccades)
          // On privilégie fortement le centre de l'image.
          // Puissance 10 = Coupe nette, peu de mélange flou.
          final double weight = math
              .pow(math.cos(normDist * math.pi / 2), 10.0)
              .toDouble();

          if (weight > 0.001) {
            final pixel = proj.photo.image.getPixel(px, py);
            sumR += pixel.r * weight;
            sumG += pixel.g * weight;
            sumB += pixel.b * weight;
            sumW += weight;
          }
        }

        if (sumW > 0) {
          final r = (sumR / sumW).round().clamp(0, 255);
          final g = (sumG / sumW).round().clamp(0, 255);
          final b = (sumB / sumW).round().clamp(0, 255);
          equirect.setPixel(eqX, eqY, img.ColorRgba8(r, g, b, 255));
        } else {
          // Pixel non couvert — sera rempli par _fillHoles
          equirect.setPixel(eqX, eqY, img.ColorRgba8(0, 0, 0, 0));
        }
      }
    }

    return equirect;
  }

  /// Remplit les pixels non couverts par expansion itérative
  /// (plusieurs passes avec un kernel croissant)
  static void _fillHolesMultiPass(img.Image image) {
    final int w = image.width;
    final int h = image.height;

    // Marquer les pixels couverts
    final covered = List.generate(h, (_) => List.filled(w, false));
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final pixel = image.getPixel(x, y);
        covered[y][x] = pixel.a > 0;
      }
    }

    // Plusieurs passes avec kernel croissant
    for (int pass = 0; pass < 8; pass++) {
      final int kernelSize = pass < 3 ? 2 : (pass < 5 ? 4 : 8);
      bool anyFilled = false;

      final newPixels = <_PendingPixel>[];

      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          if (covered[y][x]) continue;

          double sumR = 0, sumG = 0, sumB = 0, sumW = 0;
          for (int ky = -kernelSize; ky <= kernelSize; ky++) {
            for (int kx = -kernelSize; kx <= kernelSize; kx++) {
              // Wrap horizontal pour la continuité panoramique
              final int nx = (x + kx) % w;
              final int ny = (y + ky).clamp(0, h - 1);
              if (covered[ny][nx]) {
                final dist = math.sqrt((kx * kx + ky * ky).toDouble());
                final weight = 1.0 / (1.0 + dist);
                final pixel = image.getPixel(nx, ny);
                sumR += pixel.r * weight;
                sumG += pixel.g * weight;
                sumB += pixel.b * weight;
                sumW += weight;
              }
            }
          }

          if (sumW > 0) {
            newPixels.add(
              _PendingPixel(
                x: x,
                y: y,
                r: (sumR / sumW).round().clamp(0, 255),
                g: (sumG / sumW).round().clamp(0, 255),
                b: (sumB / sumW).round().clamp(0, 255),
              ),
            );
            anyFilled = true;
          }
        }
      }

      // Appliquer les nouveaux pixels
      for (final p in newPixels) {
        image.setPixel(p.x, p.y, img.ColorRgba8(p.r, p.g, p.b, 255));
        covered[p.y][p.x] = true;
      }

      if (!anyFilled) break;
    }

    // Remplir tout pixel restant avec un gris neutre (pour les pôles non couverts)
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (!covered[y][x]) {
          // Utiliser un dégradé vers les pôles (gris plus sombre)
          final latFactor = (y / h - 0.5).abs() * 2; // 0 au centre, 1 aux pôles
          final gray = (30 + 20 * (1 - latFactor)).round().clamp(0, 255);
          image.setPixel(x, y, img.ColorRgba8(gray, gray, gray, 255));
        }
      }
    }
  }

  /// Redimensionne une image
  static img.Image _resizeImage(img.Image image, int maxWidth) {
    if (image.width > maxWidth) {
      final aspectRatio = image.height / image.width;
      final newHeight = (maxWidth * aspectRatio).round();
      return img.copyResize(
        image,
        width: maxWidth,
        height: newHeight,
        interpolation: img.Interpolation.linear,
      );
    }
    return image;
  }

  /// Balance des couleurs
  static img.Image _balanceColors(img.Image image) {
    return img.adjustColor(
      image,
      contrast: 1.02,
      saturation: 1.03,
      brightness: 1.01,
    );
  }

  /// Nettoie les fichiers temporaires
  Future<void> cleanTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final photoDir = Directory('${tempDir.path}/${AppConstants.tempFolder}');
      if (photoDir.existsSync()) {
        photoDir.deleteSync(recursive: true);
      }
    } catch (e) {
      // Silently fail
    }
  }

  /// Injecte les métadonnées XMP (Google Photo Sphere) dans le JPEG
  /// Permet à Facebook/Google Photos de reconnaître le 360°
  static List<int> _injectXmpMetadata(List<int> jpeg, int width, int height) {
    // Header standard pour XMP dans APP1
    const String xmpHeader = 'http://ns.adobe.com/xap/1.0/\x00';

    // Le XML XMP minimal pour Photo Sphere
    final String xmpContent =
        '''
<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 5.1.0-jc003">
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

    // Construire le segment APP1
    // Marker (FF E1) + Length (2 bytes) + Header + Content
    final List<int> headerBytes = xmpHeader.codeUnits;
    final List<int> contentBytes = xmpContent.codeUnits;
    final int length = 2 + headerBytes.length + contentBytes.length;

    final List<int> app1Segment = [
      0xFF,
      0xE1,
      (length >> 8) & 0xFF,
      length & 0xFF,
      ...headerBytes,
      ...contentBytes,
    ];

    // Insérer après le SOI (FF D8)
    // JPEG commence par FF D8
    if (jpeg.length >= 2 && jpeg[0] == 0xFF && jpeg[1] == 0xD8) {
      return [0xFF, 0xD8, ...app1Segment, ...jpeg.sublist(2)];
    }

    // Fallback si pas un JPEG valide (ne devrait pas arriver)
    return jpeg;
  }
} // Fin de la classe StitchingService

/// Données de projection pré-calculées pour une photo
class _PhotoProjection {
  final _LoadedPhoto photo;
  final double azRad;
  final double elRad;
  final double hFovRad;
  final double vFovRad;
  final double cosAz;
  final double sinAz;
  final double cosEl;
  final double sinEl;

  const _PhotoProjection({
    required this.photo,
    required this.azRad,
    required this.elRad,
    required this.hFovRad,
    required this.vFovRad,
    required this.cosAz,
    required this.sinAz,
    required this.cosEl,
    required this.sinEl,
  });
}

/// Photo chargée en mémoire avec ses métadonnées
class _LoadedPhoto {
  final img.Image image;
  final double azimuth;
  final double elevation;

  const _LoadedPhoto({
    required this.image,
    required this.azimuth,
    required this.elevation,
  });
}

/// Pixel en attente d'écriture (pour le fill-holes)
class _PendingPixel {
  final int x, y, r, g, b;
  const _PendingPixel({
    required this.x,
    required this.y,
    required this.r,
    required this.g,
    required this.b,
  });
}

import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
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

  /// Stitching sphérique dans un isolate
  static Future<void> _stitchInIsolate(StitchingParams params) async {
    try {
      final photos = params.photos;
      final outputPath = params.outputPath;
      final sendPort = params.sendPort;

      // Phase 1: Charger et redimensionner toutes les images
      final List<_LoadedPhoto> loadedPhotos = [];
      for (int i = 0; i < photos.length; i++) {
        sendPort.send(
          StitchingResult(success: false, progress: (i / photos.length) * 0.5),
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

        // Redimensionner
        final resized = _resizeImage(image, 800);
        loadedPhotos.add(
          _LoadedPhoto(
            image: resized,
            azimuth: photos[i].azimuth,
            elevation: photos[i].elevation,
          ),
        );
      }

      sendPort.send(const StitchingResult(success: false, progress: 0.6));

      // Phase 2: Projeter sur une image équirectangulaire
      final equirect = _projectToEquirectangular(loadedPhotos);

      sendPort.send(const StitchingResult(success: false, progress: 0.85));

      // Phase 3: Post-traitement
      final balanced = _balanceColors(equirect);

      sendPort.send(const StitchingResult(success: false, progress: 0.95));

      // Phase 4: Sauvegarder
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(
        img.encodeJpg(balanced, quality: AppConstants.jpegQuality),
      );

      sendPort.send(
        StitchingResult(success: true, panoramaPath: outputPath, progress: 1.0),
      );
    } catch (e) {
      params.sendPort.send(
        StitchingResult(success: false, error: e.toString()),
      );
    }
  }

  /// Projette toutes les photos sur une image équirectangulaire
  static img.Image _projectToEquirectangular(List<_LoadedPhoto> photos) {
    final int outW = AppConstants.equirectWidth;
    final int outH = AppConstants.equirectHeight;
    final equirect = img.Image(width: outW, height: outH);

    // Remplir de noir
    for (int y = 0; y < outH; y++) {
      for (int x = 0; x < outW; x++) {
        equirect.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));
      }
    }

    // Poids pour le blending entre photos qui se chevauchent
    final weightMap = List.generate(outH, (_) => List.filled(outW, 0.0));
    final rMap = List.generate(outH, (_) => List.filled(outW, 0.0));
    final gMap = List.generate(outH, (_) => List.filled(outW, 0.0));
    final bMap = List.generate(outH, (_) => List.filled(outW, 0.0));

    // FOV estimé de la caméra (en degrés)
    const double hFov = 65.0;
    const double vFov = 50.0;
    final double hFovRad = hFov * math.pi / 180;
    final double vFovRad = vFov * math.pi / 180;

    for (final photo in photos) {
      final int imgW = photo.image.width;
      final int imgH = photo.image.height;
      final double azRad = photo.azimuth * math.pi / 180;
      final double elRad = photo.elevation * math.pi / 180;

      // Pour chaque pixel de la photo source, calculer où il se projette
      // dans l'image équirectangulaire
      for (int py = 0; py < imgH; py++) {
        for (int px = 0; px < imgW; px++) {
          // Coordonnées normalisées dans la photo (-0.5 à 0.5)
          final double nx = (px / imgW) - 0.5;
          final double ny = (py / imgH) - 0.5;

          // Angles dans le repère de la caméra
          final double localAz = nx * hFovRad;
          final double localEl = -ny * vFovRad;

          // Transformer en coordonnées sphériques globales
          // Rotation autour de l'axe vertical (azimut) puis horizontal (élévation)
          final double cosLocalEl = math.cos(localEl);
          final double sinLocalEl = math.sin(localEl);
          final double cosLocalAz = math.cos(localAz);
          final double sinLocalAz = math.sin(localAz);

          // Vecteur direction dans le repère caméra
          double dx = cosLocalEl * sinLocalAz;
          double dy = sinLocalEl;
          double dz = cosLocalEl * cosLocalAz;

          // Rotation par l'élévation de la caméra (autour de l'axe X)
          final double cosEl = math.cos(elRad);
          final double sinEl = math.sin(elRad);
          final double dy2 = dy * cosEl - dz * sinEl;
          final double dz2 = dy * sinEl + dz * cosEl;

          // Rotation par l'azimut de la caméra (autour de l'axe Y)
          final double cosAz = math.cos(azRad);
          final double sinAz = math.sin(azRad);
          final double dx3 = dx * cosAz + dz2 * sinAz;
          final double dz3 = -dx * sinAz + dz2 * cosAz;

          // Convertir en latitude/longitude
          final double r = math.sqrt(dx3 * dx3 + dy2 * dy2 + dz3 * dz3);
          final double lat = math.asin((dy2 / r).clamp(-1.0, 1.0));
          double lon = math.atan2(dx3, dz3);

          // Convertir en coordonnées pixel sur l'équirectangulaire
          // lon: -π à +π → 0 à outW
          // lat: -π/2 à +π/2 → outH à 0
          final int eqX = ((lon / math.pi + 1) * 0.5 * outW).round() % outW;
          final int eqY = ((0.5 - lat / math.pi) * outH).round().clamp(
            0,
            outH - 1,
          );

          // Poids basé sur la distance au centre de l'image
          // (les bords sont moins fiables à cause de la distorsion)
          final double distFromCenter = math.sqrt(nx * nx + ny * ny) / 0.7071;
          final double weight = math.max(
            0.0,
            1.0 - distFromCenter * distFromCenter,
          );

          if (weight > 0.01) {
            final pixel = photo.image.getPixel(px, py);
            rMap[eqY][eqX] += pixel.r * weight;
            gMap[eqY][eqX] += pixel.g * weight;
            bMap[eqY][eqX] += pixel.b * weight;
            weightMap[eqY][eqX] += weight;
          }
        }
      }
    }

    // Normaliser par les poids
    for (int y = 0; y < outH; y++) {
      for (int x = 0; x < outW; x++) {
        if (weightMap[y][x] > 0) {
          final w = weightMap[y][x];
          final r = (rMap[y][x] / w).round().clamp(0, 255);
          final g = (gMap[y][x] / w).round().clamp(0, 255);
          final b = (bMap[y][x] / w).round().clamp(0, 255);
          equirect.setPixel(x, y, img.ColorRgba8(r, g, b, 255));
        }
      }
    }

    // Remplir les trous par interpolation simple
    _fillHoles(equirect, weightMap);

    return equirect;
  }

  /// Remplit les pixels non couverts par interpolation des voisins
  static void _fillHoles(img.Image image, List<List<double>> weightMap) {
    final int w = image.width;
    final int h = image.height;
    const int kernelSize = 5;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (weightMap[y][x] > 0) continue;

        double sumR = 0, sumG = 0, sumB = 0, sumW = 0;
        for (int ky = -kernelSize; ky <= kernelSize; ky++) {
          for (int kx = -kernelSize; kx <= kernelSize; kx++) {
            final int nx = (x + kx) % w;
            final int ny = (y + ky).clamp(0, h - 1);
            if (weightMap[ny][nx] > 0) {
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
          image.setPixel(
            x,
            y,
            img.ColorRgba8(
              (sumR / sumW).round().clamp(0, 255),
              (sumG / sumW).round().clamp(0, 255),
              (sumB / sumW).round().clamp(0, 255),
              255,
            ),
          );
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
      contrast: 1.03,
      saturation: 1.05,
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

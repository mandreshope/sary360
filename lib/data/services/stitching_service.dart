import 'dart:io';
import 'dart:isolate';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/models/captured_photo.dart';
import '../../domain/models/panorama.dart';

/// Paramètres pour l'isolate de stitching
class StitchingParams {
  final List<String> photoPaths;
  final String outputPath;
  final SendPort sendPort;

  const StitchingParams({
    required this.photoPaths,
    required this.outputPath,
    required this.sendPort,
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

/// Service de stitching offline des images
class StitchingService {
  /// Assemble les photos en panorama 360° (méthode simplifiée offline)
  /// Cette méthode utilise un isolate pour ne pas bloquer l'UI
  Future<Panorama> stitchPanorama(
    List<CapturedPhoto> photos, {
    Function(double)? onProgress,
  }) async {
    if (photos.isEmpty) {
      throw Exception('Aucune photo à assembler');
    }

    // Créer le port de communication
    final receivePort = ReceivePort();

    // Préparer le chemin de sortie
    final appDir = await getApplicationDocumentsDirectory();
    final panoramaDir = Directory(
      '${appDir.path}/${AppConstants.panoramasFolder}',
    );
    if (!panoramaDir.existsSync()) {
      panoramaDir.createSync(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = '${panoramaDir.path}/panorama_$timestamp.jpg';

    // Lancer l'isolate
    await Isolate.spawn(
      _stitchInIsolate,
      StitchingParams(
        photoPaths: photos.map((p) => p.path).toList(),
        outputPath: outputPath,
        sendPort: receivePort.sendPort,
      ),
    );

    // Écouter les résultats
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

    // Créer l'objet Panorama
    return Panorama(
      id: timestamp.toString(),
      name: 'Panorama ${DateTime.now().toString().split('.')[0]}',
      createdAt: DateTime.now(),
      stitchedImagePath: finalResult.panoramaPath!,
      originalPhotoPaths: photos.map((p) => p.path).toList(),
      photoCount: photos.length,
    );
  }

  /// Fonction exécutée dans l'isolate
  static Future<void> _stitchInIsolate(StitchingParams params) async {
    try {
      final photos = params.photoPaths;
      final outputPath = params.outputPath;
      final sendPort = params.sendPort;

      // Charger et traiter chaque image
      final processedImages = <img.Image>[];

      for (int i = 0; i < photos.length; i++) {
        // Mise à jour de la progression
        sendPort.send(
          StitchingResult(
            success: false,
            progress: (i / photos.length) * 0.7, // 70% pour le chargement
          ),
        );

        // Charger l'image
        final file = File(photos[i]);
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

        // Redimensionner pour performance
        final resized = _resizeImage(image);

        // Recadrer au centre pour minimiser la distorsion
        final cropped = _cropCenter(resized);

        processedImages.add(cropped);
      }

      // Mettre à jour la progression
      sendPort.send(
        const StitchingResult(
          success: false,
          progress: 0.8, // 80%
        ),
      );

      // Assembler horizontalement avec chevauchement
      final panorama = _concatenateHorizontal(processedImages);

      // Équilibrer les couleurs (simple correction)
      final balanced = _balanceColors(panorama);

      // Mettre à jour la progression
      sendPort.send(
        const StitchingResult(
          success: false,
          progress: 0.95, // 95%
        ),
      );

      // Sauvegarder le résultat
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(
        img.encodeJpg(balanced, quality: AppConstants.jpegQuality),
      );

      // Envoyer le résultat final
      sendPort.send(
        StitchingResult(success: true, panoramaPath: outputPath, progress: 1.0),
      );
    } catch (e) {
      params.sendPort.send(
        StitchingResult(success: false, error: e.toString()),
      );
    }
  }

  /// Redimensionne l'image tout en gardant l'aspect ratio
  static img.Image _resizeImage(img.Image image) {
    if (image.width > AppConstants.maxImageWidth) {
      final aspectRatio = image.height / image.width;
      final newHeight = (AppConstants.maxImageWidth * aspectRatio).round();
      return img.copyResize(
        image,
        width: AppConstants.maxImageWidth,
        height: newHeight,
        interpolation: img.Interpolation.linear,
      );
    }
    return image;
  }

  /// Recadre l'image au centre (élimine les bords pour minimiser distorsion)
  static img.Image _cropCenter(img.Image image) {
    final cropWidth = (image.width * 0.85).round(); // Garder 85% au centre
    final cropHeight = image.height;
    final x = ((image.width - cropWidth) / 2).round();

    return img.copyCrop(
      image,
      x: x,
      y: 0,
      width: cropWidth,
      height: cropHeight,
    );
  }

  /// Concatène les images horizontalement avec gestion du chevauchement
  static img.Image _concatenateHorizontal(List<img.Image> images) {
    if (images.isEmpty) {
      throw Exception('Aucune image à concaténer');
    }

    // Calculer la largeur finale
    final overlap = AppConstants.overlapPixels;
    final totalWidth =
        images.fold<int>(0, (sum, img) => sum + img.width) -
        (overlap * (images.length - 1));

    // Trouver la hauteur maximale
    final maxHeight = images.fold<int>(
      0,
      (max, img) => img.height > max ? img.height : max,
    );

    // Créer l'image panorama
    final panorama = img.Image(width: totalWidth, height: maxHeight);

    // Coller les images avec chevauchement et blending
    int xOffset = 0;
    for (int i = 0; i < images.length; i++) {
      final currentImage = images[i];

      if (i == 0) {
        // Première image : copie simple
        img.compositeImage(
          panorama,
          currentImage,
          dstX: 0,
          dstY: (maxHeight - currentImage.height) ~/ 2,
        );
      } else {
        // Images suivantes : blend dans la zone de chevauchement
        _blendImages(
          panorama,
          currentImage,
          xOffset - overlap,
          (maxHeight - currentImage.height) ~/ 2,
          overlap,
        );
      }

      xOffset += currentImage.width - overlap;
    }

    return panorama;
  }

  /// Blend deux images dans la zone de chevauchement
  static void _blendImages(
    img.Image dst,
    img.Image src,
    int dstX,
    int dstY,
    int overlapWidth,
  ) {
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final targetX = dstX + x;
        final targetY = dstY + y;

        if (targetX < 0 ||
            targetX >= dst.width ||
            targetY < 0 ||
            targetY >= dst.height) {
          continue;
        }

        final srcPixel = src.getPixel(x, y);

        // Si on est dans la zone de chevauchement
        if (x < overlapWidth) {
          // Calculer le ratio de blending (0 = 100% ancienne, 1 = 100% nouvelle)
          final blendRatio = x / overlapWidth;
          final dstPixel = dst.getPixel(targetX, targetY);

          // Blending linéaire
          final blended = _blendPixels(dstPixel, srcPixel, blendRatio);
          dst.setPixel(targetX, targetY, blended);
        } else {
          // Hors de la zone de chevauchement : copie simple
          dst.setPixel(targetX, targetY, srcPixel);
        }
      }
    }
  }

  /// Blend deux pixels avec un ratio donné
  static img.Color _blendPixels(img.Pixel p1, img.Pixel p2, double ratio) {
    final r = (p1.r * (1 - ratio) + p2.r * ratio).toInt().clamp(0, 255);
    final g = (p1.g * (1 - ratio) + p2.g * ratio).toInt().clamp(0, 255);
    final b = (p1.b * (1 - ratio) + p2.b * ratio).toInt().clamp(0, 255);
    final a = (p1.a * (1 - ratio) + p2.a * ratio).toInt().clamp(0, 255);

    return img.ColorRgba8(r, g, b, a);
  }

  /// Balance simple des couleurs pour uniformiser le panorama
  static img.Image _balanceColors(img.Image image) {
    // Appliquer une légère normalisation pour équilibrer les couleurs
    return img.adjustColor(
      image,
      contrast: 1.05,
      saturation: 1.1,
      brightness: 1.02,
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
      // ignore: avoid_print
      print('Erreur lors du nettoyage des fichiers temporaires: $e');
    }
  }
}

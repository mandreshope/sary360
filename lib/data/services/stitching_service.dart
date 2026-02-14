import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
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

/// Service de stitching sphérique avancé
/// Projection inverse (reverse mapping) avec :
///   - Interpolation bilinéaire (anti-aliasing)
///   - Normalisation d'exposition inter-photos
///   - Correction de distorsion lentille (k1)
///   - Feathering gaussien pour le blending
///   - Métadonnées XMP (Google Photo Sphere)
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

  // ═══════════════════════════════════════════════════════════════════
  //  ISOLATE - Tout le traitement lourd se fait ici
  // ═══════════════════════════════════════════════════════════════════

  static Future<void> _stitchInIsolate(StitchingParams params) async {
    try {
      final photos = params.photos;
      final outputPath = params.outputPath;
      final sendPort = params.sendPort;

      // ── Phase 1 : Chargement & pré-traitement ─────────────────────
      final List<_LoadedPhoto> loadedPhotos = [];
      for (int i = 0; i < photos.length; i++) {
        sendPort.send(
          StitchingResult(success: false, progress: (i / photos.length) * 0.30),
        );

        final file = File(photos[i].path);
        final bytes = await file.readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) {
          sendPort.send(
            StitchingResult(
              success: false,
              error: 'Impossible de décoder l\'image ${i + 1}',
            ),
          );
          return;
        }

        // Résolution plus haute pour plus de détails
        final resized = _resizeImage(decoded, 2048);

        loadedPhotos.add(
          _LoadedPhoto(
            image: resized,
            azimuth: photos[i].azimuth,
            elevation: photos[i].elevation,
          ),
        );
      }

      sendPort.send(const StitchingResult(success: false, progress: 0.32));

      // ── Phase 2 : Normalisation d'exposition ──────────────────────
      _normalizeExposure(loadedPhotos);

      sendPort.send(const StitchingResult(success: false, progress: 0.35));

      // ── Phase 3 : Projection inverse + blending ───────────────────
      final equirect = _projectToEquirectangular(loadedPhotos, sendPort);

      sendPort.send(const StitchingResult(success: false, progress: 0.85));

      // ── Phase 4 : Remplissage des trous ───────────────────────────
      _fillHoles(equirect);

      sendPort.send(const StitchingResult(success: false, progress: 0.90));

      // ── Phase 5 : Post-traitement léger ───────────────────────────
      final polished = _postProcess(equirect);

      sendPort.send(const StitchingResult(success: false, progress: 0.95));

      // ── Phase 6 : Sauvegarde avec XMP ─────────────────────────────
      final jpegBytes = img.encodeJpg(
        polished,
        quality: AppConstants.jpegQuality,
      );
      final jpegWithXmp = _injectXmpMetadata(
        jpegBytes,
        polished.width,
        polished.height,
      );
      await File(outputPath).writeAsBytes(jpegWithXmp);

      sendPort.send(
        StitchingResult(success: true, panoramaPath: outputPath, progress: 1.0),
      );
    } catch (e) {
      params.sendPort.send(
        StitchingResult(success: false, error: e.toString()),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  NORMALISATION D'EXPOSITION
  //  Calcule la luminance moyenne de chaque photo et les aligne
  //  sur la luminance médiane pour éviter les bandes de luminosité.
  // ═══════════════════════════════════════════════════════════════════

  static void _normalizeExposure(List<_LoadedPhoto> photos) {
    if (photos.length < 2) return;

    // Calculer la luminance moyenne de chaque image
    final List<double> luminances = [];
    for (final photo in photos) {
      double sum = 0;
      int count = 0;
      final image = photo.image;
      // Échantillonnage (1 pixel sur 4 pour la vitesse)
      for (int y = 0; y < image.height; y += 4) {
        for (int x = 0; x < image.width; x += 4) {
          final p = image.getPixel(x, y);
          // Luminance perceptive (BT.709)
          sum += 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b;
          count++;
        }
      }
      luminances.add(count > 0 ? sum / count : 128.0);
    }

    // Cible = luminance médiane
    final sorted = List<double>.from(luminances)..sort();
    final targetLum = sorted[sorted.length ~/ 2];

    // Appliquer un gain multiplicatif par image
    for (int i = 0; i < photos.length; i++) {
      if (luminances[i] < 1.0) continue; // Éviter division par 0
      final gain = targetLum / luminances[i];
      // Limiter le gain pour ne pas écraser les images
      final clampedGain = gain.clamp(0.7, 1.4);
      if ((clampedGain - 1.0).abs() < 0.02) continue; // Pas besoin de corriger

      final image = photos[i].image;
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final p = image.getPixel(x, y);
          final nr = (p.r * clampedGain).round().clamp(0, 255);
          final ng = (p.g * clampedGain).round().clamp(0, 255);
          final nb = (p.b * clampedGain).round().clamp(0, 255);
          image.setPixel(x, y, img.ColorRgba8(nr, ng, nb, 255));
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  PROJECTION INVERSE (REVERSE MAPPING)
  //  Pour chaque pixel de sortie, on calcule d'où il vient dans les
  //  photos sources, avec interpolation bilinéaire et distorsion.
  // ═══════════════════════════════════════════════════════════════════

  static img.Image _projectToEquirectangular(
    List<_LoadedPhoto> photos,
    SendPort sendPort,
  ) {
    final int outW = AppConstants.equirectWidth;
    final int outH = AppConstants.equirectHeight;
    final equirect = img.Image(width: outW, height: outH);

    final double hFov = AppConstants.cameraHFov * math.pi / 180;
    final double vFov = AppConstants.cameraVFov * math.pi / 180;

    // Coefficient de distorsion lentille (barillet → compenser)
    // Valeur empirique pour grand angle mobile (~28mm eq)
    const double k1 = -0.12;

    // Pré-calcul des matrices de rotation pour chaque photo
    final List<_PhotoProj> projections = photos.map((p) {
      final az = p.azimuth * math.pi / 180;
      final el = p.elevation * math.pi / 180;
      return _PhotoProj(
        photo: p,
        // Matrice de rotation inverse : R_el^T * R_az^T
        // On stocke les 9 éléments pour éviter de recalculer
        cosAz: math.cos(az),
        sinAz: math.sin(az),
        cosEl: math.cos(el),
        sinEl: math.sin(el),
      );
    }).toList();

    for (int eqY = 0; eqY < outH; eqY++) {
      if (eqY % 80 == 0) {
        sendPort.send(
          StitchingResult(success: false, progress: 0.35 + (eqY / outH) * 0.50),
        );
      }

      final double lat = (0.5 - eqY / outH) * math.pi;
      final double cosLat = math.cos(lat);
      final double sinLat = math.sin(lat);

      for (int eqX = 0; eqX < outW; eqX++) {
        final double lon = (eqX / outW) * 2.0 * math.pi - math.pi;

        // Direction 3D du rayon
        final double dx = cosLat * math.sin(lon);
        final double dy = sinLat;
        final double dz = cosLat * math.cos(lon);

        double totalR = 0, totalG = 0, totalB = 0, totalW = 0;

        for (final proj in projections) {
          // ── Rotation inverse ──
          // 1) Inverse azimut (autour de Y)
          final double rx = dx * proj.cosAz + dz * proj.sinAz;
          final double rz0 = -dx * proj.sinAz + dz * proj.cosAz;

          // 2) Inverse élévation (autour de X)
          final double ry = dy * proj.cosEl - rz0 * proj.sinEl;
          final double rz = dy * proj.sinEl + rz0 * proj.cosEl;

          // Derrière la caméra → ignorer
          if (rz <= 0.01) continue;

          // ── Projection pinhole ──
          final double tanU = rx / rz;
          final double tanV = ry / rz;

          // Coordonnées normalisées sur le plan image
          final double u0 = tanU / math.tan(hFov / 2);
          final double v0 = tanV / math.tan(vFov / 2);

          // Hors du FOV ? (marge de 4% pour l'overlap)
          if (u0.abs() > 1.04 || v0.abs() > 1.04) continue;

          // ── Correction distorsion lentille ──
          final double r2 = u0 * u0 + v0 * v0;
          final double distFactor = 1.0 + k1 * r2;
          final double u = u0 * distFactor;
          final double v = v0 * distFactor;

          // Pixel continu dans l'image source (0..W, 0..H)
          final double srcX = (u * 0.5 + 0.5) * proj.photo.image.width;
          final double srcY = (0.5 - v * 0.5) * proj.photo.image.height;

          final int imgW = proj.photo.image.width;
          final int imgH = proj.photo.image.height;

          if (srcX < 0 || srcX >= imgW - 1 || srcY < 0 || srcY >= imgH - 1) {
            continue;
          }

          // ── Interpolation bilinéaire ──
          final _RGBA color = _bilinearSample(proj.photo.image, srcX, srcY);

          // ── Poids (feathering) ──
          // Distance normalisée au centre [0..1]
          final double distU = u0.abs(); // 0 = centre, 1 = bord
          final double distV = v0.abs();
          final double edgeDist = math.max(distU, distV);

          // Falloff : cos^3 → transition progressive, pas trop brutal
          // (cos^10 coupait trop net et créait des bandes)
          final double weight = edgeDist >= 1.0
              ? 0.0
              : math.pow(math.cos(edgeDist * math.pi / 2), 3.0).toDouble();

          if (weight > 0.001) {
            totalR += color.r * weight;
            totalG += color.g * weight;
            totalB += color.b * weight;
            totalW += weight;
          }
        }

        if (totalW > 0) {
          equirect.setPixel(
            eqX,
            eqY,
            img.ColorRgba8(
              (totalR / totalW).round().clamp(0, 255),
              (totalG / totalW).round().clamp(0, 255),
              (totalB / totalW).round().clamp(0, 255),
              255,
            ),
          );
        } else {
          equirect.setPixel(eqX, eqY, img.ColorRgba8(0, 0, 0, 0));
        }
      }
    }

    return equirect;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  INTERPOLATION BILINÉAIRE
  //  Élimine l'effet "pixélisé" du nearest-neighbor
  // ═══════════════════════════════════════════════════════════════════

  static _RGBA _bilinearSample(img.Image image, double x, double y) {
    final int x0 = x.floor();
    final int y0 = y.floor();
    final int x1 = (x0 + 1).clamp(0, image.width - 1);
    final int y1 = (y0 + 1).clamp(0, image.height - 1);
    final int cx0 = x0.clamp(0, image.width - 1);
    final int cy0 = y0.clamp(0, image.height - 1);

    final double fx = x - x0;
    final double fy = y - y0;
    final double fx1 = 1.0 - fx;
    final double fy1 = 1.0 - fy;

    final p00 = image.getPixel(cx0, cy0);
    final p10 = image.getPixel(x1, cy0);
    final p01 = image.getPixel(cx0, y1);
    final p11 = image.getPixel(x1, y1);

    final double w00 = fx1 * fy1;
    final double w10 = fx * fy1;
    final double w01 = fx1 * fy;
    final double w11 = fx * fy;

    return _RGBA(
      (p00.r * w00 + p10.r * w10 + p01.r * w01 + p11.r * w11).toDouble(),
      (p00.g * w00 + p10.g * w10 + p01.g * w01 + p11.g * w11).toDouble(),
      (p00.b * w00 + p10.b * w10 + p01.b * w01 + p11.b * w11).toDouble(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  REMPLISSAGE DES TROUS (INPAINTING SIMPLIFIÉ)
  // ═══════════════════════════════════════════════════════════════════

  static void _fillHoles(img.Image image) {
    final int w = image.width;
    final int h = image.height;

    final covered = List.generate(h, (_) => List.filled(w, false));
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        covered[y][x] = image.getPixel(x, y).a > 0;
      }
    }

    // Passes avec kernel croissant
    for (int pass = 0; pass < 10; pass++) {
      final int ks = pass < 3 ? 2 : (pass < 6 ? 4 : 8);
      bool any = false;
      final pending = <_PendingPixel>[];

      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          if (covered[y][x]) continue;

          double sR = 0, sG = 0, sB = 0, sW = 0;
          for (int ky = -ks; ky <= ks; ky++) {
            for (int kx = -ks; kx <= ks; kx++) {
              final int nx = (x + kx) % w; // wrap horizontal
              final int ny = (y + ky).clamp(0, h - 1);
              if (!covered[ny][nx]) continue;
              final d = math.sqrt((kx * kx + ky * ky).toDouble());
              final wt = 1.0 / (1.0 + d);
              final p = image.getPixel(nx, ny);
              sR += p.r * wt;
              sG += p.g * wt;
              sB += p.b * wt;
              sW += wt;
            }
          }

          if (sW > 0) {
            pending.add(
              _PendingPixel(
                x: x,
                y: y,
                r: (sR / sW).round().clamp(0, 255),
                g: (sG / sW).round().clamp(0, 255),
                b: (sB / sW).round().clamp(0, 255),
              ),
            );
            any = true;
          }
        }
      }

      for (final p in pending) {
        image.setPixel(p.x, p.y, img.ColorRgba8(p.r, p.g, p.b, 255));
        covered[p.y][p.x] = true;
      }

      if (!any) break;
    }

    // Pôles non couverts → dégradé sombre
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (!covered[y][x]) {
          final lat = (y / h - 0.5).abs() * 2;
          final g = (30 + 20 * (1 - lat)).round().clamp(0, 255);
          image.setPixel(x, y, img.ColorRgba8(g, g, g, 255));
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  POST-TRAITEMENT
  // ═══════════════════════════════════════════════════════════════════

  static img.Image _postProcess(img.Image image) {
    // Contraste et saturation légèrement renforcés
    return img.adjustColor(
      image,
      contrast: 1.03,
      saturation: 1.05,
      brightness: 1.0,
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  UTILITAIRES
  // ═══════════════════════════════════════════════════════════════════

  static img.Image _resizeImage(img.Image image, int maxWidth) {
    if (image.width > maxWidth) {
      final ratio = image.height / image.width;
      return img.copyResize(
        image,
        width: maxWidth,
        height: (maxWidth * ratio).round(),
        interpolation: img.Interpolation.linear,
      );
    }
    return image;
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

// ═══════════════════════════════════════════════════════════════════
//  CLASSES INTERNES
// ═══════════════════════════════════════════════════════════════════

/// Couleur RGBA en double (pour l'interpolation)
class _RGBA {
  final double r, g, b;
  const _RGBA(this.r, this.g, this.b);
}

/// Données de projection pré-calculées
class _PhotoProj {
  final _LoadedPhoto photo;
  final double cosAz, sinAz, cosEl, sinEl;

  const _PhotoProj({
    required this.photo,
    required this.cosAz,
    required this.sinAz,
    required this.cosEl,
    required this.sinEl,
  });
}

/// Photo chargée + métadonnées
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

/// Pixel en attente (fill-holes)
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

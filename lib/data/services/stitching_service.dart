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
        final resized = img.copyResize(
          decoded,
          width: 2048,
          interpolation: img.Interpolation.linear,
        );

        loadedPhotos.add(
          _LoadedPhoto(
            image: resized,
            azimuth: photos[i].azimuth,
            elevation: photos[i].elevation,
            hFov: photos[i].hFov,
            vFov: photos[i].vFov,
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
    // ═══════════════════════════════════════════════════════════════════
    //  PHASE 1 : OPTIMISATION D'ALIGNEMENT (Registration)
    //  On utilise une petite résolution pour ajuster les positions
    // ═══════════════════════════════════════════════════════════════════
    sendPort.send(const StitchingResult(success: false, progress: 0.1));

    final corrections = _optimizeAlignments(photos);

    // ═══════════════════════════════════════════════════════════════════
    //  PHASE 2 : PROJECTION FINALE HAUTE RÉSOLUTION
    // ═══════════════════════════════════════════════════════════════════
    final int outW = AppConstants.equirectWidth;
    final int outH = AppConstants.equirectHeight;

    final double baseHFov = AppConstants.cameraHFov * math.pi / 180;
    final double baseVFov = AppConstants.cameraVFov * math.pi / 180;

    const double k1 = 0.0;

    // Pré-calcul des matrices avec CORRECTIONS
    final List<_PhotoProj> projections = [];
    for (int i = 0; i < photos.length; i++) {
      final p = photos[i];
      final corr = corrections[i]; // Correction calculée

      // Appliquer la correction
      final realAz = p.azimuth + corr.dAz;
      final realEl = p.elevation + corr.dEl;

      final az = realAz * math.pi / 180;
      final el = realEl * math.pi / 180;

      // Adaptation FOV (inchangé)
      final bool isPortrait = p.image.height > p.image.width;
      final double realHFov = p.hFov != null
          ? (p.hFov! * math.pi / 180)
          : (isPortrait ? baseVFov : baseHFov);
      final double realVFov = p.vFov != null
          ? (p.vFov! * math.pi / 180)
          : (isPortrait ? baseHFov : baseVFov);

      projections.add(
        _PhotoProj(
          photo: p,
          cosAz: math.cos(az),
          sinAz: math.sin(az),
          cosEl: math.cos(el),
          sinEl: math.sin(el),
          hFov: realHFov,
          vFov: realVFov,
        ),
      );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PHASE 3 : RENDU FINAL
    // ═══════════════════════════════════════════════════════════════════
    final equirect = img.Image(width: outW, height: outH);

    for (int eqY = 0; eqY < outH; eqY++) {
      if (eqY % 80 == 0) {
        sendPort.send(
          StitchingResult(success: false, progress: 0.35 + (eqY / outH) * 0.60),
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
          // ═══════════════════════════════════════════════════════════
          // ROTATION INVERSE : world-space → camera-space
          // ═══════════════════════════════════════════════════════════

          // 1) Inverse azimut R_y(-az) : tourne autour de Y
          final double rx = dx * proj.cosAz - dz * proj.sinAz;
          final double rz0 = dx * proj.sinAz + dz * proj.cosAz;

          // 2) Inverse élévation R_x(-el) : tourne autour de X
          // Inversion signe sinEl pour top/bottom correct
          final double ry = dy * proj.cosEl - rz0 * proj.sinEl;
          final double rz = dy * proj.sinEl + rz0 * proj.cosEl;

          // Derrière la caméra → ignorer
          if (rz <= 0.01) continue;

          // ── Projection pinhole ──
          final double tanU = rx / rz;
          final double tanV = ry / rz;

          // Coordonnées normalisées sur le plan image
          final double u0 = tanU / math.tan(proj.hFov / 2);
          final double v0 = tanV / math.tan(proj.vFov / 2);

          if (u0.abs() > 1.04 || v0.abs() > 1.04) continue;

          final double r2 = u0 * u0 + v0 * v0;
          final double distFactor = 1.0 + k1 * r2;
          final double u = u0 * distFactor;
          final double v = v0 * distFactor;

          final double srcX = (u * 0.5 + 0.5) * proj.photo.image.width;
          final double srcY = (0.5 - v * 0.5) * proj.photo.image.height;

          // Interpolation bilinéaire
          final _RGBA color = _bilinearSample(proj.photo.image, srcX, srcY);

          // Feathering
          final double distU = u0.abs();
          final double distV = v0.abs();
          final double edgeDist = math.max(distU, distV);
          final double weight = edgeDist >= 1.0
              ? 0.0
              : math.pow(math.cos(edgeDist * math.pi / 2), 3.0).toDouble();

          if (weight > 0) {
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
        }
      }
    }

    return equirect;
  }

  // ── ALGORITHME D'ALIGNEMENT ──

  static List<_Correction> _optimizeAlignments(List<_LoadedPhoto> photos) {
    final corrections = List.generate(
      photos.length,
      (_) => const _Correction(0, 0),
    );
    if (photos.isEmpty) return corrections;

    // Buffer basse rés (1 pixel = 1 degré)
    final int w = 360;
    final int h = 180;
    final buffer = img.Image(width: w, height: h); // Transparent

    // 1ere photo = ancrage
    _compositeFast(buffer, photos[0], 0, 0);

    for (int i = 1; i < photos.length; i++) {
      double bestScore = double.infinity;
      double bestDAz = 0;
      double bestDEl = 0;

      // Grid Search ±4° Az, ±3° El
      for (double dAz = -4; dAz <= 4; dAz += 1.0) {
        for (double dEl = -3; dEl <= 3; dEl += 1.0) {
          final score = _computeDiffScore(buffer, photos[i], dAz, dEl);
          if (score < bestScore) {
            bestScore = score;
            bestDAz = dAz;
            bestDEl = dEl;
          }
        }
      }
      corrections[i] = _Correction(bestDAz, bestDEl);
      _compositeFast(buffer, photos[i], bestDAz, bestDEl);
    }
    return corrections;
  }

  static double _computeDiffScore(
    img.Image buffer,
    _LoadedPhoto photo,
    double dAz,
    double dEl,
  ) {
    final azRad = (photo.azimuth + dAz) * math.pi / 180;
    final elRad = (photo.elevation + dEl) * math.pi / 180;
    final pW = photo.image.width;
    final pH = photo.image.height;
    final cosAz = math.cos(azRad);
    final sinAz = math.sin(azRad);
    final cosEl = math.cos(elRad);
    final sinEl = math.sin(elRad);

    final bool isPortrait = pH > pW;
    final double hFov = photo.hFov != null
        ? photo.hFov! * math.pi / 180
        : (isPortrait ? 0.83 : 1.13);
    final double vFov = photo.vFov != null
        ? photo.vFov! * math.pi / 180
        : (isPortrait ? 1.13 : 0.83);

    int cx = ((photo.azimuth + dAz) / 360.0 * 360).round();
    int cy = ((0.5 - (photo.elevation + dEl) / 180.0) * 180).round();
    if (cx < 0) cx += 360;
    int radX = (hFov * 180 / math.pi / 2).round() + 4;
    int radY = (vFov * 180 / math.pi / 2).round() + 4;

    double totalDiff = 0;
    int count = 0;

    for (int y = cy - radY; y <= cy + radY; y++) {
      if (y < 0 || y >= 180) continue;
      final lat = (0.5 - y / 180.0) * math.pi;
      final cosLat = math.cos(lat);
      final sinLat = math.sin(lat);

      for (int x = cx - radX; x <= cx + radX; x++) {
        final bx = x % 360;
        final bp = buffer.getPixel(bx, y);
        if (bp.a == 0) continue;

        final lon = (bx / 360.0) * 2 * math.pi - math.pi;
        final dx = cosLat * math.sin(lon);
        final dy = sinLat;
        final dz = cosLat * math.cos(lon);
        final rx = dx * cosAz - dz * sinAz;
        final rz0 = dx * sinAz + dz * cosAz;
        final ry = dy * cosEl - rz0 * sinEl;
        final rz = dy * sinEl + rz0 * cosEl;

        if (rz <= 0.01) continue;
        final tanU = rx / rz;
        final tanV = ry / rz;
        double u = tanU / math.tan(hFov / 2);
        double v = tanV / math.tan(vFov / 2);
        if (u.abs() > 1.0 || v.abs() > 1.0) continue;

        final sx = (u * 0.5 + 0.5) * pW;
        final sy = (0.5 - v * 0.5) * pH;
        final pp = photo.image.getPixelSafe(sx.round(), sy.round());

        totalDiff +=
            (bp.r - pp.r).abs() + (bp.g - pp.g).abs() + (bp.b - pp.b).abs();
        count++;
      }
    }
    if (count < 20) return 999999999;
    return totalDiff / count;
  }

  static void _compositeFast(
    img.Image buffer,
    _LoadedPhoto photo,
    double dAz,
    double dEl,
  ) {
    final azRad = (photo.azimuth + dAz) * math.pi / 180;
    final elRad = (photo.elevation + dEl) * math.pi / 180;
    final pW = photo.image.width;
    final pH = photo.image.height;
    final cosAz = math.cos(azRad);
    final sinAz = math.sin(azRad);
    final cosEl = math.cos(elRad);
    final sinEl = math.sin(elRad);

    final bool isPortrait = pH > pW;
    final double hFov = photo.hFov != null
        ? photo.hFov! * math.pi / 180
        : (isPortrait ? 0.83 : 1.13);
    final double vFov = photo.vFov != null
        ? photo.vFov! * math.pi / 180
        : (isPortrait ? 1.13 : 0.83);

    int cx = ((photo.azimuth + dAz) / 360.0 * 360).round();
    int cy = ((0.5 - (photo.elevation + dEl) / 180.0) * 180).round();
    if (cx < 0) cx += 360;
    int radX = (hFov * 180 / math.pi / 2).round() + 4;
    int radY = (vFov * 180 / math.pi / 2).round() + 4;

    for (int y = cy - radY; y <= cy + radY; y++) {
      if (y < 0 || y >= 180) continue;
      final lat = (0.5 - y / 180.0) * math.pi;
      final cosLat = math.cos(lat);
      final sinLat = math.sin(lat);
      for (int x = cx - radX; x <= cx + radX; x++) {
        final bx = x % 360;
        final bp = buffer.getPixel(bx, y);
        if (bp.a > 0) continue;

        final lon = (bx / 360.0) * 2 * math.pi - math.pi;
        final dx = cosLat * math.sin(lon);
        final dy = sinLat;
        final dz = cosLat * math.cos(lon);
        final rx = dx * cosAz - dz * sinAz;
        final rz0 = dx * sinAz + dz * cosAz;
        final ry = dy * cosEl - rz0 * sinEl;
        final rz = dy * sinEl + rz0 * cosEl;

        if (rz <= 0.01) continue;
        final tanU = rx / rz;
        final tanV = ry / rz;
        double u = tanU / math.tan(hFov / 2);
        double v = tanV / math.tan(vFov / 2);
        if (u.abs() > 1.0 || v.abs() > 1.0) continue;

        final sx = (u * 0.5 + 0.5) * pW;
        final sy = (0.5 - v * 0.5) * pH;
        final pp = photo.image.getPixelSafe(sx.round(), sy.round());
        buffer.setPixel(bx, y, pp);
      }
    }
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
  final double hFov, vFov;

  const _PhotoProj({
    required this.photo,
    required this.cosAz,
    required this.sinAz,
    required this.cosEl,
    required this.sinEl,
    required this.hFov,
    required this.vFov,
  });
}

/// Photo chargée + métadonnées
class _LoadedPhoto {
  final img.Image image;
  final double azimuth;
  final double elevation;
  final double? hFov;
  final double? vFov;

  const _LoadedPhoto({
    required this.image,
    required this.azimuth,
    required this.elevation,
    this.hFov,
    this.vFov,
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

/// Correction d'alignement (registration)
class _Correction {
  final double dAz;
  final double dEl;
  const _Correction(this.dAz, this.dEl);
}

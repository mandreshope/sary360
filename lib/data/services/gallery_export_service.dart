import 'dart:io';

import 'package:gal/gal.dart';

import '../../domain/models/panorama.dart';

/// Résultat d'un export vers la galerie du téléphone.
enum GalleryExportResult { saved, accessDenied, notEnoughSpace, failed }

/// Export des sphères vers la galerie du téléphone (MediaStore sur Android,
/// Photos sur iOS), dans un album dédié.
///
/// Le fichier est copié tel quel : les métadonnées XMP Photo Sphere sont
/// conservées, ce qui permet à Google Photos de l'ouvrir en 360°.
class GalleryExportService {
  static const album = 'Sary360';

  Future<GalleryExportResult> export(Panorama panorama) async {
    final file = File(panorama.stitchedImagePath);
    if (!file.existsSync()) return GalleryExportResult.failed;
    try {
      // Permission requise seulement sur Android 9 et moins, et sur iOS.
      if (!await Gal.hasAccess(toAlbum: true) &&
          !await Gal.requestAccess(toAlbum: true)) {
        return GalleryExportResult.accessDenied;
      }
      await Gal.putImage(file.path, album: album);
      return GalleryExportResult.saved;
    } on GalException catch (e) {
      return switch (e.type) {
        GalExceptionType.accessDenied => GalleryExportResult.accessDenied,
        GalExceptionType.notEnoughSpace => GalleryExportResult.notEnoughSpace,
        _ => GalleryExportResult.failed,
      };
    }
  }

  /// Ouvre l'application galerie du téléphone.
  Future<void> openGallery() => Gal.open();
}

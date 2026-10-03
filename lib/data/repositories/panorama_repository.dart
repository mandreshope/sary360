import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/models/panorama.dart';

/// Accès aux sphères enregistrées dans le dossier de l'application.
class PanoramaRepository {
  Future<Directory> _directory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}/${AppConstants.panoramasFolder}');
  }

  /// Sphères triées de la plus récente à la plus ancienne.
  Future<List<Panorama>> list() async {
    final dir = await _directory();
    if (!dir.existsSync()) return [];
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.jpg'))
        .toList();
    final panoramas = [
      for (final f in files)
        Panorama(
          id: f.uri.pathSegments.last,
          name: f.uri.pathSegments.last,
          createdAt: f.lastModifiedSync(),
          stitchedImagePath: f.path,
          originalPhotoPaths: const [],
          photoCount: 0,
        ),
    ];
    panoramas.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return panoramas;
  }

  /// Supprime le fichier et ses entrées du cache d'images.
  Future<void> delete(Panorama panorama) async {
    final file = File(panorama.stitchedImagePath);
    await FileImage(file).evict();
    if (file.existsSync()) await file.delete();
  }
}

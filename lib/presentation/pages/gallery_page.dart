import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/models/panorama.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  List<File> _panoramas = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPanoramas();
  }

  Future<void> _loadPanoramas() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final panDir = Directory(
        '${appDir.path}/${AppConstants.panoramasFolder}',
      );

      if (panDir.existsSync()) {
        final files = panDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.jpg'))
            .toList();

        // Trier par date de modification décroissante (plus récent en premier)
        files.sort(
          (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
        );

        if (mounted) {
          setState(() {
            _panoramas = files;
            _loading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _loading = false);
        }
      }
    } catch (e) {
      debugPrint('Erreur chargement galerie: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _openPanorama(File file) {
    // Création d'un objet Panorama à la volée
    // On extrait le nom et la date du fichier
    final name = file.uri.pathSegments.last;
    final stat = file.statSync();

    final panorama = Panorama(
      id: name,
      name: 'Panorama ${stat.changed}',
      createdAt: stat.changed,
      stitchedImagePath: file.path,
      originalPhotoPaths: [], // Non disponible depuis le fichier seul
      photoCount: 0, // Inconnu
    );

    context.push(AppRoutes.viewer, extra: panorama);
  }

  Future<void> _deletePanorama(File file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ?'),
        content: const Text('Voulez-vous vraiment supprimer ce panorama ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await file.delete();
        await _loadPanoramas(); // Recharger la liste
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la suppression: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes Panoramas'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _panoramas.isEmpty
          ? _buildEmptyState()
          : _buildGrid(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 80,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'Aucun panorama',
            style: TextStyle(fontSize: 20, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Vos captures apparaîtront ici',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.0,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _panoramas.length,
      itemBuilder: (context, index) {
        final file = _panoramas[index];
        return _buildItem(file);
      },
    );
  }

  Widget _buildItem(File file) {
    return GestureDetector(
      onTap: () => _openPanorama(file),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              file,
              fit: BoxFit.cover,
              cacheWidth: 300, // Optimisation mémoire
            ),
            // Gradient overlay pour le texte
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Icon(Icons.threesixty, color: Colors.white, size: 16),
                    GestureDetector(
                      onTap: () => _deletePanorama(file),
                      child: const Icon(
                        Icons.delete_outline,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

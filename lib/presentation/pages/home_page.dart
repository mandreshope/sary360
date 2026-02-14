import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../pages/capture_page.dart';
import '../pages/gallery_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.blue.shade900, Colors.purple.shade900],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo/Icon
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.panorama_photosphere,
                      size: 64,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Titre
                  const Text(
                    'Sary360',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Description
                  const Text(
                    'Créez des panoramas 360° immersifs\nentièrement hors ligne',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 64),

                  // Bouton principal
                  ElevatedButton(
                    onPressed: () => _startCapture(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.purple.shade900,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 20,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 8,
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.camera_alt, size: 28),
                        SizedBox(width: 12),
                        Text(
                          'Créer un panorama',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Bouton Galerie
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const GalleryPage()),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      side: const BorderSide(color: Colors.white70, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.photo_library),
                        SizedBox(width: 12),
                        Text(
                          'Voir mes captures',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Fonctionnalités
                  _buildFeatures(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatures() {
    return Column(
      children: [
        _FeatureItem(
          icon: Icons.trending_flat,
          text: 'Guidage rotation intelligente',
        ),
        const SizedBox(height: 16),
        _FeatureItem(icon: Icons.offline_bolt, text: '100% offline'),
        const SizedBox(height: 16),
        _FeatureItem(
          icon: Icons.panorama_horizontal,
          text: 'Viewer 360° interactif',
        ),
      ],
    );
  }

  Future<void> _startCapture(BuildContext context) async {
    // Demander les permissions nécessaires
    final cameraStatus = await Permission.camera.request();
    // Note: Standard motion sensors (gyro/accel) do not require runtime permission on Android.
    // Permission.sensors refers to BODY_SENSORS (heart rate, etc.) which we don't use.

    if (cameraStatus.isGranted) {
      if (context.mounted) {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const CapturePage()));
      }
    } else {
      if (context.mounted) {
        _showPermissionDialog(context);
      }
    }
  }

  void _showPermissionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permissions requises'),
        content: const Text(
          'L\'application a besoin d\'accéder à la caméra et aux capteurs '
          'pour créer des panoramas. Veuillez activer ces permissions dans '
          'les paramètres.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Paramètres'),
          ),
        ],
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(width: 12),
        Text(text, style: const TextStyle(color: Colors.white70, fontSize: 14)),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/constellation_colors.dart';
import '../../core/widgets/constellation_orb.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/starfield_background.dart';
import '../widgets/home/settings_sheet.dart';

/// Écran d'accueil : emblème animé, création d'une sphère, accès galerie.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  /// Pilote l'entrée échelonnée des éléments.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  /// Apparition décalée : chaque élément démarre à `start` (0..1).
  Widget _staggered(double start, Widget child) {
    final anim = CurvedAnimation(
      parent: _intro,
      curve: Interval(
        start,
        (start + 0.5).clamp(0, 1),
        curve: AppMotion.bounce,
      ),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(
        opacity: anim.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 24 * (1 - anim.value)),
          child: child,
        ),
      ),
      child: child,
    );
  }

  Future<void> _startCapture() async {
    HapticFeedback.mediumImpact();
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isGranted) {
      context.push(AppRoutes.capture);
    } else {
      _showPermissionDialog(permanentlyDenied: status.isPermanentlyDenied);
    }
  }

  void _showPermissionDialog({required bool permanentlyDenied}) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Caméra requise'),
        content: Text(
          permanentlyDenied
              ? 'L\'accès à la caméra a été refusé. Activez-le dans les '
                    'paramètres du système pour capturer une sphère.'
              : 'Sary360 a besoin de la caméra pour photographier chaque '
                    'étoile de votre constellation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              if (permanentlyDenied) {
                openAppSettings();
              } else {
                _startCapture();
              }
            },
            child: Text(permanentlyDenied ? 'Paramètres' : 'Réessayer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final orbSize = (MediaQuery.sizeOf(context).shortestSide * 0.78).clamp(
      220.0,
      340.0,
    );

    return Scaffold(
      body: StarfieldBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _staggered(
                  0,
                  Row(
                    children: [
                      Text('SARY360', style: text.labelSmall),
                      const Spacer(),
                      GlassIconButton(
                        icon: Icons.tune_rounded,
                        tooltip: 'Réglages',
                        onPressed: () => showSettingsSheet(context),
                      ),
                    ],
                  ),
                ),
                // L'emblème occupe l'espace restant, sans jamais déborder
                // sur les petits écrans.
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => Center(
                      child: _staggered(
                        0.1,
                        Hero(
                          tag: ConstellationOrb.heroTag,
                          child: ConstellationOrb(
                            size: orbSize.clamp(0.0, box.maxHeight),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _staggered(
                  0.25,
                  Text('Capturez\nvotre ciel.', style: text.displayMedium),
                ),
                const SizedBox(height: 12),
                _staggered(
                  0.32,
                  Text(
                    'Reliez les étoiles autour de vous pour créer une '
                    'sphère 360° immersive, assemblée sur votre téléphone.',
                    style: text.bodyLarge?.copyWith(color: c.textSecondary),
                  ),
                ),
                const SizedBox(height: 28),
                _staggered(
                  0.42,
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _startCapture,
                      icon: const Icon(Icons.blur_circular_rounded),
                      label: const Text('Nouvelle sphère'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _staggered(
                  0.5,
                  _GalleryCard(onTap: () => context.push(AppRoutes.gallery)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Accès à la galerie, sous forme de carte en verre.
class _GalleryCard extends StatelessWidget {
  const _GalleryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: GlassPanel(
        radius: AppRadii.pill,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(Icons.grid_view_rounded, color: c.accent, size: 22),
            const SizedBox(width: 14),
            Expanded(child: Text('Mes sphères', style: text.labelLarge)),
            Icon(Icons.arrow_forward_rounded, color: c.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}

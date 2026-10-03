import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/constellation_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/glass_panel.dart';
import '../../domain/models/panorama.dart';
import '../widgets/custom_panorama.dart' as pw;
import 'gallery_page.dart' show kThumbnailCacheWidth, panoramaHeroTag;

/// Visionneuse immersive : glisser pour tourner, pincer pour zoomer,
/// gyroscope activable, recentrage.
class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key, required this.panorama});

  final Panorama panorama;

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  bool _gyro = false;

  /// Change à chaque recentrage : recrée la vue avec son orientation initiale.
  int _viewKey = 0;

  /// Commandes masquées / affichées d'un tap.
  bool _chromeVisible = true;

  /// La sphère 3D apparaît en fondu après la transition Hero.
  bool _sphereVisible = false;

  @override
  void initState() {
    super.initState();
    // Immersion : barres système masquées tant que la visionneuse est ouverte.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    Future.delayed(AppMotion.slow, () {
      if (mounted) setState(() => _sphereVisible = true);
    });
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleGyro() {
    HapticFeedback.selectionClick();
    setState(() => _gyro = !_gyro);
  }

  void _recenter() {
    HapticFeedback.lightImpact();
    setState(() => _viewKey++);
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.panorama.stitchedImagePath);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Image plane de la transition Hero, recouverte ensuite par la
          // sphère 3D.
          Hero(
            tag: panoramaHeroTag(widget.panorama),
            child: Image.file(
              file,
              fit: BoxFit.cover,
              cacheWidth: kThumbnailCacheWidth,
              gaplessPlayback: true,
            ),
          ),
          AnimatedOpacity(
            opacity: _sphereVisible ? 1 : 0,
            duration: AppMotion.slow,
            curve: AppMotion.standard,
            child: pw.Panorama(
              key: ValueKey(_viewKey),
              sensorControl: _gyro
                  ? pw.SensorControl.orientation
                  : pw.SensorControl.none,
              onTap: (_, _, _) =>
                  setState(() => _chromeVisible = !_chromeVisible),
              child: Image.file(file),
            ),
          ),
          _Chrome(
            visible: _chromeVisible,
            panorama: widget.panorama,
            gyro: _gyro,
            onToggleGyro: _toggleGyro,
            onRecenter: _recenter,
          ),
          const _GestureHint(),
        ],
      ),
    );
  }
}

/// Barre supérieure et pilule de commandes, en verre dépoli.
class _Chrome extends StatelessWidget {
  const _Chrome({
    required this.visible,
    required this.panorama,
    required this.gyro,
    required this.onToggleGyro,
    required this.onRecenter,
  });

  final bool visible;
  final Panorama panorama;
  final bool gyro;
  final VoidCallback onToggleGyro;
  final VoidCallback onRecenter;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: AppMotion.medium,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    GlassIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Retour',
                      onPressed: () => context.pop(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GlassPanel(
                        radius: AppRadii.pill,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        child: Text(
                          Formatters.dateTime(panorama.createdAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelLarge?.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                GlassPanel(
                  radius: AppRadii.pill,
                  padding: const EdgeInsets.all(6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ToolButton(
                        icon: Icons.screen_rotation_alt_rounded,
                        label: 'Gyroscope',
                        active: gyro,
                        onTap: onToggleGyro,
                      ),
                      _ToolButton(
                        icon: Icons.center_focus_strong_rounded,
                        label: 'Recentrer',
                        onTap: onRecenter,
                      ),
                      _ToolButton(
                        icon: Icons.info_outline_rounded,
                        label: 'Infos',
                        onTap: () => _showInfo(context, panorama),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton de la pilule : icône + libellé, surligné à l'accent quand actif.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = active ? c.onAccent : Colors.white;
    return Semantics(
      button: true,
      toggled: active,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.medium,
          curve: AppMotion.standard,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: active ? c.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: fg, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: fg, letterSpacing: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Consigne de geste, affichée quelques secondes à l'ouverture.
class _GestureHint extends StatefulWidget {
  const _GestureHint();

  @override
  State<_GestureHint> createState() => _GestureHintState();
}

class _GestureHintState extends State<_GestureHint> {
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: AppMotion.slow,
        child: Center(
          child: GlassPanel(
            radius: AppRadii.md,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.swipe_rounded, color: Colors.white, size: 28),
                const SizedBox(height: 8),
                Text(
                  'Glissez pour explorer · pincez pour zoomer',
                  style: text.bodyMedium?.copyWith(color: Colors.white),
                ),
                Text(
                  'Touchez pour masquer les commandes',
                  style: text.bodySmall?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showInfo(BuildContext context, Panorama p) async {
  final file = File(p.stitchedImagePath);
  final size = file.existsSync() ? file.lengthSync() : 0;
  // Dimensions lues dans l'en-tête de l'image, sans la décoder entièrement.
  String dims = '—';
  try {
    final buffer = await ui.ImmutableBuffer.fromFilePath(file.path);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    dims = '${descriptor.width} × ${descriptor.height}';
    descriptor.dispose();
    buffer.dispose();
  } catch (_) {}
  if (!context.mounted) return;

  final text = Theme.of(context).textTheme;
  final c = context.colors;
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: GlassPanel(
        tint: c.backgroundElevated.withValues(alpha: 0.85),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Informations', style: text.headlineSmall),
            const SizedBox(height: 20),
            _InfoRow(
              icon: Icons.event_rounded,
              label: 'Créée le',
              value: Formatters.dateTime(p.createdAt),
            ),
            _InfoRow(
              icon: Icons.aspect_ratio_rounded,
              label: 'Définition',
              value: dims,
            ),
            _InfoRow(
              icon: Icons.sd_storage_rounded,
              label: 'Taille',
              value: Formatters.bytes(size),
            ),
            _InfoRow(
              icon: Icons.public_rounded,
              label: 'Projection',
              value: 'Équirectangulaire 360° · Photo Sphere',
            ),
          ],
        ),
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(icon, color: c.accent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: text.labelSmall),
                const SizedBox(height: 2),
                Text(value, style: text.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/constellation_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/constellation_orb.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/starfield_background.dart';
import '../../data/repositories/panorama_repository.dart';
import '../../domain/models/panorama.dart';

/// Largeur de décodage des vignettes (partagée avec la visionneuse pour la
/// transition Hero : même clé de cache, pas de second décodage).
const int kThumbnailCacheWidth = 640;

/// Tag Hero d'une sphère (vignette ↔ visionneuse).
String panoramaHeroTag(Panorama p) => 'panorama-${p.stitchedImagePath}';

/// Galerie des sphères créées.
class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage>
    with SingleTickerProviderStateMixin {
  final _repository = PanoramaRepository();
  List<Panorama>? _panoramas;

  /// Défilement lent et partagé des vignettes (aller-retour sur 24 s).
  late final AnimationController _pan = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pan.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _repository.list();
      if (mounted) setState(() => _panoramas = list);
    } catch (e) {
      debugPrint('Erreur chargement galerie: $e');
      if (mounted) setState(() => _panoramas = []);
    }
  }

  Future<void> _open(Panorama p) async {
    HapticFeedback.selectionClick();
    await context.push(AppRoutes.viewer, extra: p);
  }

  Future<void> _delete(Panorama p) async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la sphère ?'),
        content: const Text('Elle sera définitivement retirée de l\'appareil.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _repository.delete(p);
      if (!mounted) return;
      setState(() => _panoramas = [..._panoramas!]..remove(p));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Suppression impossible : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final panoramas = _panoramas;
    return Scaffold(
      body: StarfieldBackground(
        starCount: 90,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(count: panoramas?.length),
              Expanded(
                child: AnimatedSwitcher(
                  duration: AppMotion.medium,
                  child: panoramas == null
                      ? Center(
                          child: CircularProgressIndicator(
                            color: context.colors.accent,
                          ),
                        )
                      : panoramas.isEmpty
                      ? const _EmptyState()
                      : _Grid(
                          panoramas: panoramas,
                          pan: _pan,
                          onOpen: _open,
                          onDelete: _delete,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count});

  final int? count;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 24, 16),
      child: Row(
        children: [
          GlassIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Retour',
            onPressed: () => context.pop(),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mes sphères', style: text.headlineMedium),
                if (count != null && count! > 0)
                  Text(
                    count == 1 ? '1 sphère' : '$count sphères',
                    style: text.bodyMedium,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.panoramas,
    required this.pan,
    required this.onOpen,
    required this.onDelete,
  });

  final List<Panorama> panoramas;
  final Animation<double> pan;
  final ValueChanged<Panorama> onOpen;
  final ValueChanged<Panorama> onDelete;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + bottom),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.78,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: panoramas.length,
      itemBuilder: (context, i) => _Appear(
        index: i,
        child: _PanoramaCard(
          panorama: panoramas[i],
          pan: pan,
          // Décalage de phase : les vignettes ne défilent pas en bloc.
          phase: (i * 0.37) % 1.0,
          onOpen: () => onOpen(panoramas[i]),
          onDelete: () => onDelete(panoramas[i]),
        ),
      ),
    );
  }
}

/// Apparition échelonnée d'une carte (fondu + léger rebond).
class _Appear extends StatelessWidget {
  const _Appear({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + 60 * index.clamp(0, 8)),
      curve: AppMotion.bounce,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 24 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _PanoramaCard extends StatefulWidget {
  const _PanoramaCard({
    required this.panorama,
    required this.pan,
    required this.phase,
    required this.onOpen,
    required this.onDelete,
  });

  final Panorama panorama;
  final Animation<double> pan;
  final double phase;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  State<_PanoramaCard> createState() => _PanoramaCardState();
}

class _PanoramaCardState extends State<_PanoramaCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final p = widget.panorama;
    final file = File(p.stitchedImagePath);
    final size = file.existsSync() ? file.lengthSync() : 0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onOpen,
      onLongPress: widget.onDelete,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: c.glassBorder),
            boxShadow: [
              BoxShadow(
                color: c.accent.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Vignette : l'équirectangulaire défile lentement, comme une
                // sphère qui tourne.
                Hero(
                  tag: panoramaHeroTag(p),
                  child: AnimatedBuilder(
                    animation: widget.pan,
                    builder: (context, _) {
                      final t = (widget.pan.value + widget.phase) % 1.0;
                      final x = Curves.easeInOutSine.transform(t) * 2 - 1;
                      return Image.file(
                        file,
                        fit: BoxFit.cover,
                        alignment: Alignment(x, 0),
                        cacheWidth: kThumbnailCacheWidth,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: c.backgroundElevated,
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: c.textSecondary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Dégradé pour la lisibilité du bandeau.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.5, 1],
                      colors: [Colors.transparent, Color(0xAA000000)],
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: GlassIconButton(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Supprimer',
                    size: 36,
                    onPressed: widget.onDelete,
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: GlassPanel(
                    radius: AppRadii.sm,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    tint: Colors.black.withValues(alpha: 0.25),
                    child: Row(
                      children: [
                        Icon(
                          Icons.threesixty_rounded,
                          color: c.accent,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                Formatters.date(p.createdAt),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.labelMedium?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                '${Formatters.time(p.createdAt)} · ${Formatters.bytes(size)}',
                                maxLines: 1,
                                style: text.bodySmall?.copyWith(
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ConstellationOrb(size: 180, progress: 0.15),
            const SizedBox(height: 32),
            Text('Votre ciel est vide', style: text.headlineSmall),
            const SizedBox(height: 12),
            Text(
              'Capturez une première sphère : elle apparaîtra ici, prête à '
              'être explorée.',
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () async {
                final status = await Permission.camera.request();
                if (!context.mounted) return;
                if (status.isGranted) {
                  context.pushReplacement(AppRoutes.capture);
                } else if (status.isPermanentlyDenied) {
                  openAppSettings();
                }
              },
              icon: const Icon(Icons.blur_circular_rounded),
              label: const Text('Nouvelle sphère'),
            ),
          ],
        ),
      ),
    );
  }
}

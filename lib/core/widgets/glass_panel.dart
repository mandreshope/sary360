import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/constellation_colors.dart';

/// Panneau en verre dépoli : flou de l'arrière-plan + remplissage translucide
/// + liseré fin. Brique de base de toutes les surfaces flottantes.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = AppRadii.lg,
    this.tint,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Teinte optionnelle remplaçant le remplissage par défaut.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shape = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: c.glassBlur, sigmaY: c.glassBlur),
        // Remplissage + liseré. Le reflet est un second calque : dans un même
        // BoxDecoration, un dégradé masquerait la couleur de remplissage.
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: shape,
            color: tint ?? c.glass,
            border: Border.all(color: c.glassBorder),
          ),
          child: DecoratedBox(
            // Reflet subtil en haut à gauche, comme une plaque de verre.
            decoration: BoxDecoration(
              borderRadius: shape,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.07),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
            ),
            // Material transparent : les ListTile et InkWell enfants
            // peuvent dessiner leurs effets au-dessus du verre.
            child: Material(
              type: MaterialType.transparency,
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton circulaire en verre (icône seule), avec retour de pression animé.
class GlassIconButton extends StatefulWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 48,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  @override
  State<GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<GlassIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final button = GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1,
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        child: SizedBox.square(
          dimension: widget.size,
          child: GlassPanel(
            padding: EdgeInsets.zero,
            radius: AppRadii.pill,
            child: Icon(
              widget.icon,
              color: c.textPrimary,
              size: widget.size * 0.45,
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: widget.tooltip,
      child: widget.tooltip == null
          ? button
          : Tooltip(message: widget.tooltip!, child: button),
    );
  }
}

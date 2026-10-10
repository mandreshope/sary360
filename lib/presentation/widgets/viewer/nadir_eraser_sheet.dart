import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/constellation_colors.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../data/services/nadir_eraser_service.dart';
import '../../../domain/models/panorama.dart';

/// Opens the "erase the floor" tool. Returns true when the panorama file was
/// changed (edit applied or original restored).
Future<bool> showNadirEraserSheet(
  BuildContext context,
  Panorama panorama,
  ThemeData appTheme,
) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => Theme(
      data: appTheme,
      child: _NadirEraserSheet(panorama: panorama),
    ),
  );
  return changed ?? false;
}

class _NadirEraserSheet extends StatefulWidget {
  const _NadirEraserSheet({required this.panorama});

  final Panorama panorama;

  @override
  State<_NadirEraserSheet> createState() => _NadirEraserSheetState();
}

class _NadirEraserSheetState extends State<_NadirEraserSheet> {
  final _service = NadirEraserService();

  /// Radius (degrees) of the floor disc rebuilt around the nadir.
  double _radius = 20;
  NadirPreview? _preview;
  bool _showAfter = true;
  bool _busy = false;
  bool _hasOriginal = false;
  String? _error;

  /// Context margin kept around the disc in the preview (see native module).
  static const double _marginDeg = 15;

  bool get _previewIsCurrent => _preview?.maskDeg == _radius;

  @override
  void initState() {
    super.initState();
    _service.hasOriginal(widget.panorama).then((value) {
      if (mounted) setState(() => _hasOriginal = value);
    });
  }

  Future<void> _runPreview() async {
    HapticFeedback.selectionClick();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = await _service.preview(widget.panorama, _radius);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _showAfter = true;
      });
    } on NadirEraseException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    final preview = _preview;
    if (preview == null) return;
    setState(() => _busy = true);
    await _service.apply(widget.panorama, preview);
    HapticFeedback.mediumImpact();
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    await _service.restore(widget.panorama);
    HapticFeedback.mediumImpact();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final preview = _preview;
    final image = preview == null
        ? null
        : (_showAfter ? preview.afterPath : preview.beforePath);
    // Disc radius as a fraction of the preview half-size (gnomonic view).
    final discFraction =
        math.tan(_radius * math.pi / 180) /
        math.tan((_radius + _marginDeg) * math.pi / 180);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: GlassPanel(
        tint: c.backgroundElevated.withValues(alpha: 0.9),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Effacer le sol', style: text.headlineSmall),
            const SizedBox(height: 6),
            Text(
              'Une IA embarquée reconstruit le sol sous vos pieds (pieds, '
              'trépied, ombre). Vérifiez l\'aperçu avant d\'appliquer.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 16),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (image != null)
                          Image.file(File(image), fit: BoxFit.cover)
                        else
                          ColoredBox(
                            color: c.glass,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.auto_fix_high_rounded,
                                    color: c.accent,
                                    size: 36,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Vue du sol après l\'aperçu',
                                    style: text.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // Zone qui sera reconstruite.
                        CustomPaint(
                          painter: _DiscPainter(
                            fraction: discFraction,
                            color: c.accent,
                            dimmed: image != null && _showAfter,
                          ),
                        ),
                        if (_busy)
                          ColoredBox(
                            color: Colors.black.withValues(alpha: 0.35),
                            child: Center(
                              child: CircularProgressIndicator(color: c.accent),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (preview != null) ...[
              const SizedBox(height: 12),
              Center(
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('Avant')),
                    ButtonSegment(value: true, label: Text('Après')),
                  ],
                  selected: {_showAfter},
                  onSelectionChanged: (s) =>
                      setState(() => _showAfter = s.first),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Rayon : ${_radius.round()}°',
              style: text.labelMedium?.copyWith(color: c.textPrimary),
            ),
            Slider(
              value: _radius,
              min: 10,
              max: 40,
              divisions: 30,
              onChanged: _busy ? null : (v) => setState(() => _radius = v),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: text.bodySmall?.copyWith(color: c.danger),
                ),
              ),
            Row(
              children: [
                if (_hasOriginal)
                  TextButton(
                    onPressed: _busy ? null : _restore,
                    child: const Text('Restaurer l\'original'),
                  ),
                const Spacer(),
                OutlinedButton(
                  onPressed: _busy ? null : _runPreview,
                  child: const Text('Aperçu'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy || !_previewIsCurrent ? null : _apply,
                  child: const Text('Appliquer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dashed circle marking the floor area that will be rebuilt.
class _DiscPainter extends CustomPainter {
  const _DiscPainter({
    required this.fraction,
    required this.color,
    required this.dimmed,
  });

  final double fraction;
  final Color color;
  final bool dimmed;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 * fraction;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color.withValues(alpha: dimmed ? 0.35 : 0.9);
    const dashes = 48;
    for (var i = 0; i < dashes; i += 2) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * 2 * math.pi / dashes,
        2 * math.pi / dashes,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DiscPainter old) =>
      old.fraction != fraction || old.color != color || old.dimmed != dimmed;
}

import 'package:flutter/material.dart';

/// Indicateur de progression de capture sphérique
class PanoramaProgressIndicator extends StatelessWidget {
  final int current;
  final int total;
  final String rowLabel;
  final double elevation;

  const PanoramaProgressIndicator({
    super.key,
    required this.current,
    required this.total,
    this.rowLabel = '',
    this.elevation = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? current / total : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Nom de la rangée
          if (rowLabel.isNotEmpty) ...[
            Text(
              rowLabel,
              style: const TextStyle(
                color: Colors.cyanAccent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
          ],
          // Compteur
          Text(
            'Photo $current / $total',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          // Barre de progression
          SizedBox(
            width: 200,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(
                  progress >= 1.0 ? Colors.greenAccent : Colors.cyanAccent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${(progress * 100).toInt()}%',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

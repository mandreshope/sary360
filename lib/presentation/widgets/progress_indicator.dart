import 'package:flutter/material.dart';

/// Indicateur de progression de capture
class PanoramaProgressIndicator extends StatelessWidget {
  final int current;
  final int total;

  const PanoramaProgressIndicator({
    super.key,
    required this.current,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Photo $current / $total',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              total,
              (index) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index < current
                      ? Colors.greenAccent
                      : Colors.white.withValues(alpha: 0.3),
                  border: Border.all(color: Colors.white, width: 1),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Bouton de capture avec animation
class CaptureButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const CaptureButton({
    super.key,
    required this.enabled,
    required this.onPressed,
  });

  @override
  State<CaptureButton> createState() => _CaptureButtonState();
}

class _CaptureButtonState extends State<CaptureButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.enabled ? widget.onPressed : null,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: widget.enabled ? _scaleAnimation.value : 1.0,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.enabled ? Colors.white : Colors.white38,
                border: Border.all(
                  color: widget.enabled ? Colors.greenAccent : Colors.white24,
                  width: 4,
                ),
                boxShadow: widget.enabled
                    ? [
                        BoxShadow(
                          color: Colors.greenAccent.withValues(alpha: 0.5),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ]
                    : [],
              ),
              child: Icon(
                Icons.camera_alt,
                size: 40,
                color: widget.enabled ? Colors.black87 : Colors.white60,
              ),
            ),
          );
        },
      ),
    );
  }
}

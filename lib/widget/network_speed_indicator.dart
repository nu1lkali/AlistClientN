import 'package:flutter/material.dart';

/// A small, semi-transparent network speed indicator widget.
/// Displays download speed like "12.5 MB/s" in a corner without
/// obscuring the video content.
///
/// [bytesPerSecond] — current download speed in bytes/sec
/// [visible] — whether the indicator should be shown (controls + speed > 0)
/// [isLandscape] — adjusts position for landscape vs portrait
class NetworkSpeedWidget extends StatelessWidget {
  final double bytesPerSecond;
  final bool visible;
  final bool isLandscape;

  const NetworkSpeedWidget({
    super.key,
    required this.bytesPerSecond,
    required this.visible,
    required this.isLandscape,
  });

  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond < 1024) {
      return '${bytesPerSecond.toStringAsFixed(0)} B/s';
    } else if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';
    } else {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
  }

  @override
  Widget build(BuildContext context) {
    final show = visible && bytesPerSecond > 100;
    if (!show) return const SizedBox.shrink();

    final topPadding = MediaQuery.of(context).padding.top;
    final rightPadding = MediaQuery.of(context).padding.right;

    return Positioned(
      top: isLandscape ? topPadding + 4 : topPadding + 8,
      right: isLandscape ? rightPadding + 8 : 8,
      child: AnimatedOpacity(
        opacity: show ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _formatSpeed(bytesPerSecond),
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 11,
              fontFamily: 'monospace',
              shadows: const [
                Shadow(
                  color: Colors.black54,
                  blurRadius: 1,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

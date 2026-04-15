import 'dart:math';
import 'package:flutter/material.dart';

/// 波形进度条，从 bujuan-feature-new-ui 移植
class WaveformProgressWidget extends StatefulWidget {
  final double progress; // 0..1
  final Color playedColor;
  final Color unplayedColor;
  final Color? thumbColor;
  final ValueChanged<double> onChangeEnd;

  const WaveformProgressWidget({
    super.key,
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
    this.thumbColor,
    required this.onChangeEnd,
  });

  @override
  State<WaveformProgressWidget> createState() => _WaveformProgressWidgetState();
}

class _WaveformProgressWidgetState extends State<WaveformProgressWidget> {
  late final List<double> _audioSamples;
  bool _isDragging = false;
  double _localProgress = 0;

  @override
  void initState() {
    super.initState();
    final rnd = Random();
    _audioSamples = List.generate(150, (_) => 0.1 + rnd.nextDouble() * 0.8);
    _localProgress = widget.progress;
  }

  @override
  void didUpdateWidget(covariant WaveformProgressWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging && oldWidget.progress != widget.progress) {
      setState(() => _localProgress = widget.progress);
    }
  }

  double _dxToProgress(double dx, double width) =>
      (dx / width).clamp(0.0, 1.0);

  void _startDrag(Offset pos, double width) =>
      setState(() { _isDragging = true; _localProgress = _dxToProgress(pos.dx, width); });

  void _updateDrag(Offset pos, double width) =>
      setState(() => _localProgress = _dxToProgress(pos.dx, width));

  void _endDrag() {
    final v = _localProgress;
    setState(() => _isDragging = false);
    widget.onChangeEnd(v);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      final prog = _isDragging ? _localProgress : widget.progress;
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (d) => _startDrag(d.localPosition, w),
        onTapUp: (_) => _endDrag(),
        onPanStart: (d) => _startDrag(d.localPosition, w),
        onPanUpdate: (d) => _updateDrag(d.localPosition, w),
        onPanEnd: (_) => _endDrag(),
        child: CustomPaint(
          size: Size(w, h),
          painter: _WaveformPainter(
            progress: prog,
            playedColor: widget.playedColor,
            unplayedColor: widget.unplayedColor,
            thumbColor: widget.thumbColor,
            audioSamples: _audioSamples,
          ),
        ),
      );
    });
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final Color? thumbColor;
  final List<double> audioSamples;

  _WaveformPainter({
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
    required this.audioSamples,
    this.thumbColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const barWidth = 2.0;
    const spacing = 4.0;
    const totalBarWidth = barWidth + spacing;
    final maxBars = (size.width / totalBarWidth).floor();
    final count = audioSamples.length.clamp(0, maxBars);
    final prog = progress.clamp(0.0, 1.0);

    for (int i = 0; i < count; i++) {
      final barH = audioSamples[i] * size.height * 0.8;
      final left = i * totalBarWidth;
      final top = (size.height - barH) / 2;
      final paint = Paint()
        ..color = i <= (count * prog).floor() ? playedColor : unplayedColor
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(left, top, barWidth, barH), const Radius.circular(3)),
        paint,
      );
    }

    if (prog > 0 && prog < 1) {
      final px = (count * prog) * totalBarWidth;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(px - 1.5, 0, 3, size.height), const Radius.circular(3)),
        Paint()..color = thumbColor ?? playedColor..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.progress != progress || old.playedColor != playedColor;
}

import 'dart:math';

import 'package:flutter/material.dart';

/// 九宫格手势锁绘制和交互组件
class PatternLockWidget extends StatefulWidget {
  final void Function(List<int> pattern) onComplete;
  final double size;
  final Color? lineColor;
  final Color? dotColor;
  final Color? activeDotColor;
  final int gridSize; // 3 = 3x3

  const PatternLockWidget({
    super.key,
    required this.onComplete,
    this.size = 300,
    this.lineColor,
    this.dotColor,
    this.activeDotColor,
    this.gridSize = 3,
  });

  @override
  State<PatternLockWidget> createState() => PatternLockWidgetState();
}

class PatternLockWidgetState extends State<PatternLockWidget>
    with SingleTickerProviderStateMixin {
  List<int> _selectedDots = [];
  Offset? _currentPosition;
  bool _isDrawing = false;
  late AnimationController _animController;
  late Animation<double> _errorAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _errorAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _selectedDots = [];
      _currentPosition = null;
      _isDrawing = false;
    });
  }

  void showErrorThenReset({VoidCallback? onComplete}) {
    _animController.forward(from: 0).then((_) {
      _reset();
      onComplete?.call();
    });
  }

  Offset _getDotCenter(int index) {
    final n = widget.gridSize;
    final cellSize = widget.size / n;
    final row = index ~/ n;
    final col = index % n;
    return Offset(
      cellSize * col + cellSize / 2,
      cellSize * row + cellSize / 2,
    );
  }

  int? _hitTest(Offset position) {
    final n = widget.gridSize;
    final cellSize = widget.size / n;
    final dotRadius = cellSize * 0.3;

    for (int i = 0; i < n * n; i++) {
      final center = _getDotCenter(i);
      if ((position - center).distance <= dotRadius) {
        return i;
      }
    }
    return null;
  }

  void _onPanStart(DragStartDetails details) {
    final hit = _hitTest(details.localPosition);
    if (hit != null) {
      setState(() {
        _isDrawing = true;
        _selectedDots = [hit];
        _currentPosition = details.localPosition;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_isDrawing) return;
    final hit = _hitTest(details.localPosition);
    setState(() {
      _currentPosition = details.localPosition;
      if (hit != null && !_selectedDots.contains(hit)) {
        _selectedDots.add(hit);
      }
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (!_isDrawing) return;
    if (_selectedDots.length >= 4) {
      widget.onComplete(List.from(_selectedDots));
    } else if (_selectedDots.isNotEmpty) {
      // 太少的点，显示错误动画
      _animController.forward(from: 0).then((_) => _reset());
    }
    setState(() {
      _isDrawing = false;
      _currentPosition = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lineColor = widget.lineColor ?? scheme.primary;
    final dotColor = widget.dotColor ?? scheme.outline.withOpacity(0.3);
    final activeDotColor = widget.activeDotColor ?? scheme.primary;

    return AnimatedBuilder(
      animation: _errorAnimation,
      builder: (context, child) {
        final shakeOffset = _errorAnimation.value > 0
            ? sin(_errorAnimation.value * pi * 3) * 5
            : 0.0;
        return Transform.translate(
          offset: Offset(shakeOffset, 0),
          child: child,
        );
      },
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _PatternPainter(
            gridSize: widget.gridSize,
            selectedDots: _selectedDots,
            currentPosition: _currentPosition,
            isDrawing: _isDrawing,
            lineColor: lineColor,
            dotColor: dotColor,
            activeDotColor: activeDotColor,
            hasError: _errorAnimation.value > 0,
          ),
        ),
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  final int gridSize;
  final List<int> selectedDots;
  final Offset? currentPosition;
  final bool isDrawing;
  final Color lineColor;
  final Color dotColor;
  final Color activeDotColor;
  final bool hasError;

  _PatternPainter({
    required this.gridSize,
    required this.selectedDots,
    this.currentPosition,
    required this.isDrawing,
    required this.lineColor,
    required this.dotColor,
    required this.activeDotColor,
    required this.hasError,
  });

  Offset _getDotCenter(int index, Size size) {
    final cellSize = size.width / gridSize;
    final row = index ~/ gridSize;
    final col = index % gridSize;
    return Offset(
      cellSize * col + cellSize / 2,
      cellSize * row + cellSize / 2,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cellSize = size.width / gridSize;
    final dotRadius = cellSize * 0.15;
    final activeDotRadius = cellSize * 0.25;
    final dotOuterRadius = cellSize * 0.3;

    final color = hasError ? Colors.red : lineColor;
    final activeColor = hasError ? Colors.red : activeDotColor;

    // Draw inactive dots
    for (int i = 0; i < gridSize * gridSize; i++) {
      if (!selectedDots.contains(i)) {
        final center = _getDotCenter(i, size);
        canvas.drawCircle(
          center,
          dotRadius,
          Paint()
            ..color = dotColor
            ..style = PaintingStyle.fill,
        );
      }
    }

    // Draw lines between selected dots
    if (selectedDots.length >= 2) {
      final linePaint = Paint()
        ..color = activeColor.withOpacity(0.6)
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final path = Path();
      path.moveTo(
        _getDotCenter(selectedDots[0], size).dx,
        _getDotCenter(selectedDots[0], size).dy,
      );
      for (int i = 1; i < selectedDots.length; i++) {
        path.lineTo(
          _getDotCenter(selectedDots[i], size).dx,
          _getDotCenter(selectedDots[i], size).dy,
        );
      }

      // Draw line to current position
      if (isDrawing && currentPosition != null) {
        path.lineTo(currentPosition!.dx, currentPosition!.dy);
      }

      canvas.drawPath(path, linePaint);
    }

    // Draw active dots
    for (final index in selectedDots) {
      final center = _getDotCenter(index, size);
      // Outer circle
      canvas.drawCircle(
        center,
        dotOuterRadius,
        Paint()
          ..color = activeColor.withOpacity(0.2)
          ..style = PaintingStyle.fill,
      );
      // Inner circle
      canvas.drawCircle(
        center,
        activeDotRadius,
        Paint()
          ..color = activeColor
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter oldDelegate) {
    return oldDelegate.selectedDots != selectedDots ||
        oldDelegate.currentPosition != currentPosition ||
        oldDelegate.isDrawing != isDrawing ||
        oldDelegate.hasError != hasError;
  }
}
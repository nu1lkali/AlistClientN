import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// Chrome 断网小恐龙 loading 动画。
///
/// 像素数据**逐像素取自 Chromium 官方精灵图** `1x-trex.png`
/// （264x47，每帧 44x47 共 6 帧）中的两个跑步帧（帧 2 / 帧 3）：
/// 裁掉四周空白后为 38x44。原图中主体为 #535353（index 1），
/// 眼睛为白色挖空（index 3）、近白描边（index 2）均按背景处理，
/// 因此头部留出的眼睛孔洞在深色视频背景上会自然显形。
///
/// 绘制用 `isAntiAlias = false` 的整数像素矩形，保证像素风边缘干净。
///
/// 帧率刻意压到 5fps（见 [DinoRunner.frameDuration]）：Chrome 原版是 12fps，
/// 但那是「恐龙全速狂奔 + 地面飞速后掠」，动静合一所以看着顺；
/// 这里是**原地不动**的 loading，只有两条腿在交替，再用 12fps 就成了帕金森。
class DinoRunner extends StatefulWidget {
  /// 单个像素的边长。38x44 的原始网格在 2.0 时约为 76x88 逻辑像素。
  final double pixelSize;

  /// 恐龙主体颜色。默认浅灰白，适配播放器的深色遮罩背景。
  final Color color;

  /// 是否绘制下方滚动的虚线地面。
  final bool showGround;

  /// 换腿间隔。默认 200ms（5fps），是「原地慢跑」而不是「高频抖动」的节奏。
  final Duration frameDuration;

  const DinoRunner({
    super.key,
    this.pixelSize = 2.0,
    this.color = const Color(0xFFDADCE0),
    this.showGround = true,
    this.frameDuration = const Duration(milliseconds: 200),
  });

  @override
  State<DinoRunner> createState() => _DinoRunnerState();
}

class _DinoRunnerState extends State<DinoRunner> {
  int _frame = 0;

  @override
  void initState() {
    super.initState();
    // 5fps 慢跑节奏，见 [DinoRunner.frameDuration] 的注释。
    Future.doWhile(() async {
      await Future<void>.delayed(widget.frameDuration);
      if (!mounted) return false;
      setState(() => _frame = (_frame + 1) % 2);
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(
          kDinoCols * widget.pixelSize,
          kDinoRows * widget.pixelSize + (widget.showGround ? 10 : 0),
        ),
        painter: _DinoPainter(
          rows: _frame == 0 ? kDinoFrameA : kDinoFrameB,
          pixelSize: widget.pixelSize,
          color: widget.color,
          showGround: widget.showGround,
          groundOffset: _frame * 2.0,
        ),
      ),
    );
  }
}

class _DinoPainter extends CustomPainter {
  const _DinoPainter({
    required this.rows,
    required this.pixelSize,
    required this.color,
    required this.showGround,
    required this.groundOffset,
  });

  final List<String> rows;
  final double pixelSize;
  final Color color;
  final bool showGround;
  final double groundOffset;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = false
      ..color = color;

    // 逐行扫描，把连续的 '1' 合并成一个矩形再画，
    // 每帧绘制调用从上千次降到几十次。
    for (var r = 0; r < rows.length && r < kDinoRows; r++) {
      final row = rows[r];
      var c = 0;
      while (c < row.length && c < kDinoCols) {
        if (row[c] != '1') {
          c++;
          continue;
        }
        var end = c;
        while (end < row.length && end < kDinoCols && row[end] == '1') {
          end++;
        }
        canvas.drawRect(
          Rect.fromLTWH(
              c * pixelSize, r * pixelSize, (end - c) * pixelSize, pixelSize),
          paint,
        );
        c = end;
      }
    }

    if (!showGround) return;

    // 地面虚线随跑步节奏向左滚动，模拟向前跑。
    final groundY = kDinoRows * pixelSize + 5;
    final step = pixelSize * 5;
    final dash = pixelSize * 2.5;
    final width = kDinoCols * pixelSize;
    final offset = (groundOffset * pixelSize) % step;
    final groundPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = color.withOpacity(0.55);
    for (var x = -step; x < width + step; x += step) {
      canvas.drawLine(
        Offset(x + offset, groundY),
        Offset(math.min(x + offset + dash, width + step), groundY),
        groundPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DinoPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.pixelSize != pixelSize ||
      oldDelegate.rows != rows ||
      oldDelegate.groundOffset != groundOffset;
}

/// 精灵网格尺寸（裁掉原图空白后的 38x44）。
const int kDinoCols = 38;
const int kDinoRows = 44;

/// 跑步帧 1（左腿蹬地、右腿抬起），数据来自 Chromium 官方精灵图帧 2。
const List<String> kDinoFrameA = <String>[
  '00000000000000000000001111111111111111',
  '00000000000000000000001111111111111111',
  '00000000000000000000111111111111111111',
  '00000000000000000000111100111111111111',
  '00000000000000000000111100111111111111',
  '00000000000000000000111111111111111111',
  '00000000000000000000111111111111111111',
  '00000000000000000000111111111111111111',
  '00000000000000000000111111111111111111',
  '00000000000000000000111111111111111111',
  '00000000000000000000111111111111111111',
  '00000000000000000000111111111100000000',
  '00000000000000000000111111111100000000',
  '00000000000000000000111111111111111100',
  '00000000000000000000111111111111111100',
  '11000000000000000011111111110000000000',
  '11000000000000000011111111110000000000',
  '11000000000000011111111111110000000000',
  '11000000000000011111111111110000000000',
  '11110000000011111111111111111111000000',
  '11110000000011111111111111111111000000',
  '11111100001111111111111111110011000000',
  '11111100001111111111111111110011000000',
  '11111111111111111111111111110000000000',
  '11111111111111111111111111110000000000',
  '11111111111111111111111111110000000000',
  '11111111111111111111111111110000000000',
  '00111111111111111111111111110000000000',
  '00111111111111111111111111000000000000',
  '00001111111111111111111111000000000000',
  '00001111111111111111111111000000000000',
  '00000011111111111111111100000000000000',
  '00000011111111111111111100000000000000',
  '00000000111111111111110000000000000000',
  '00000000111111111111110000000000000000',
  '00000000001111110000111110000000000000',
  '00000000001111110000111110000000000000',
  '00000000001111000000000000000000000000',
  '00000000001111000000000000000000000000',
  '00000000001100000000000000000000000000',
  '00000000001100000000000000000000000000',
  '00000000001111000000000000000000000000',
  '00000000001111000000000000000000000000',
  '00000000000000000000000000000000000000',
];

/// 跑步帧 2（右腿蹬地、左腿抬起），与帧 1 仅腿部不同，数据来自精灵图帧 3。
const List<String> kDinoFrameB = <String>[
  '00000000000000000000001111111111111111',
  '00000000000000000000001111111111111111',
  '00000000000000000000111111111111111111',
  '00000000000000000000111100111111111111',
  '00000000000000000000111100111111111111',
  '00000000000000000000111111111111111111',
  '00000000000000000000111111111111111111',
  '00000000000000000000111111111111111111',
  '00000000000000000000111111111111111111',
  '00000000000000000000111111111111111111',
  '00000000000000000000111111111111111111',
  '00000000000000000000111111111100000000',
  '00000000000000000000111111111100000000',
  '00000000000000000000111111111111111100',
  '00000000000000000000111111111111111100',
  '11000000000000000011111111110000000000',
  '11000000000000000011111111110000000000',
  '11000000000000011111111111110000000000',
  '11000000000000011111111111110000000000',
  '11110000000011111111111111111111000000',
  '11110000000011111111111111111111000000',
  '11111100001111111111111111110011000000',
  '11111100001111111111111111110011000000',
  '11111111111111111111111111110000000000',
  '11111111111111111111111111110000000000',
  '11111111111111111111111111110000000000',
  '11111111111111111111111111110000000000',
  '00111111111111111111111111110000000000',
  '00111111111111111111111111000000000000',
  '00001111111111111111111111000000000000',
  '00001111111111111111111111000000000000',
  '00000011111111111111111100000000000000',
  '00000011111111111111111100000000000000',
  '00000000111111111111110000000000000000',
  '00000000111111111111110000000000000000',
  '00000000001111000011110000000000000000',
  '00000000001111000011110000000000000000',
  '00000000000011110000110000000000000000',
  '00000000000011110000110000000000000000',
  '00000000000000000000110000000000000000',
  '00000000000000000000110000000000000000',
  '00000000000000000000111100000000000000',
  '00000000000000000000111100000000000000',
  '00000000000000000000000000000000000000',
];

/// 恐龙 + 网速的组合 loading 指示器。
///
/// [bytesPerSecond] 为当前真实下行速率（B/s）；
/// 无流量时不显示，避免一直钉着一个 0。
class DinoLoadingIndicator extends StatelessWidget {
  final double? bytesPerSecond;
  final String text;
  final double pixelSize;
  final Color color;

  const DinoLoadingIndicator({
    super.key,
    this.bytesPerSecond,
    this.text = '加载中…',
    this.pixelSize = 2.0,
    this.color = const Color(0xFFDADCE0),
  });

  static String formatSpeed(double bps) {
    if (bps >= 1024 * 1024) {
      return '${(bps / (1024 * 1024)).toStringAsFixed(2)} MB/s';
    }
    if (bps >= 1024) return '${(bps / 1024).toStringAsFixed(0)} KB/s';
    return '${bps.toInt()} B/s';
  }

  @override
  Widget build(BuildContext context) {
    final speed = bytesPerSecond;
    // 加载阶段必然在拉流，任何非零读数都是有效信息；只在完全没有流量时隐藏，
    // 免得钉一个静止的「0 B/s」在那里。
    final showSpeed = speed != null && speed > 0;
    return IgnorePointer(
      ignoring: true,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DinoRunner(pixelSize: pixelSize, color: color),
            const SizedBox(height: 14),
            // 「加载中」与实时速率放在**同一行**。
            // 这个画面里用户唯一在乎的进度信号就是「有没有在下载」，压到同一
            // 视线高度才看得到；单独排成一行会变成另一枚孤立的徽标，且和
            // 「加载中」争夺注意力，反而让人不知道先看哪个。
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    color: color.withOpacity(0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
                if (showSpeed) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.downloading_rounded,
                      color: Color(0xFF4FC3F7), size: 12),
                  const SizedBox(width: 3),
                  Text(
                    formatSpeed(speed),
                    style: const TextStyle(
                      color: Color(0xFF4FC3F7),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      // 'tnum' 等宽数字，避免速率跳动时文本抖动。
                      fontFeatures: <FontFeature>[FontFeature('tnum')],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

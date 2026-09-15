import 'package:flutter/material.dart';

/// Emby「随机播放收藏」图标（矢量绘制）。
///
/// 图形来源：仓库根目录的 `1.svg`（`viewBox="0 0 512 512"`，`fill-rule: nonzero`）。
/// 早期实现是把它用 `.iconbuild/raster_svg.py` 光栅化成
/// `assets/images/icon_emby_favorite_random.png`（24 / 48 / 72 px 三档位图）再交给
/// [ImageIcon]，在高像素比的手机上相比旁边的 Material 图标（矢量字体）明显发糊。
///
/// 这里把 SVG 路径直接编译成 [Path]，用 [CustomPaint] 矢量绘制：任意尺寸、任意
/// 像素比都保持锐利；颜色与尺寸也像 [Icon] 一样取自 [IconTheme]（含禁用态、
/// 深色模式），因此在 [IconButton] 里与相邻图标的表现完全一致。
///
/// 路径数据从 `1.svg` 的 `<path d="...">` 直接转写而来（M/L/C/Z，用户坐标原样保留）。
///
/// 注意：SVG 图形本身并未铺满 512×512 的 viewBox（四周留白较大），若直接按
/// viewBox 绘制，图标会比相邻 Material 图标小一圈。这里在绘制时按图形的实际
/// 包围盒做等比归一化，使其铺满图标盒，从而与 [Icon] 视觉大小一致；并额外：
/// - 用 [fitScale] 微调整体大小；
/// - 用 [offsetY] 微调垂直位置；
/// - 先描边再填充，让线条视觉上更粗、与相邻图标笔画重量一致。
class EmbyFavoriteRandomIcon extends StatelessWidget {
  const EmbyFavoriteRandomIcon({Key? key, this.size, this.color})
      : super(key: key);

  /// 覆盖 [IconTheme] 里的尺寸，默认与相邻 [Icon] 相同。
  final double? size;

  /// 覆盖 [IconTheme] 里的颜色，默认与相邻 [Icon] 相同。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final IconThemeData iconTheme = IconTheme.of(context);
    final double iconSize = size ?? iconTheme.size ?? 24.0;
    final Color iconColor = color ??
        iconTheme.color ??
        Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: iconSize,
      height: iconSize,
      child: CustomPaint(
        painter: _EmbyFavoriteRandomPainter(iconColor),
        isComplex: false,
        willChange: false,
      ),
    );
  }
}

class _EmbyFavoriteRandomPainter extends CustomPainter {
  const _EmbyFavoriteRandomPainter(this.color);

  final Color color;

  /// SVG 根元素的 viewBox 边长。
  static const double _viewBoxSize = 512.0;

  /// SVG 根元素上的 `transform="translate(0,512) scale(0.1,-0.1)"`：
  /// 用户坐标 = 视图坐标 × 10，且 y 轴反向（SVG 的 y 向下）。
  static const double _userUnit = 0.1;

  /// 图形在视图坐标系（0~512）中的实际包围盒。
  ///
  /// 由路径数据用户坐标的极值换算而来（用户坐标 × [_userUnit]）：
  ///   x: 1132 ~ 3985  →  113.2 ~ 398.5
  ///   y: 1322 ~ 3794  →  132.2 ~ 379.4
  static const double _bboxMinX = 113.2;
  static const double _bboxMinY = 132.2;
  static const double _bboxMaxX = 398.5;
  static const double _bboxMaxY = 379.4;

  /// 归一化后的整体缩放微调：1.0 = 铺满，<1 缩小，>1 放大。
  static const double _fitScale = 0.92;

  /// 垂直微调（视图单位）：负值上移，正值下移。
  static const double _offsetY = -8;

  /// 描边宽度（用户坐标单位，×0.1 后为视图单位）：越大线条越粗。
  static const double _strokeWidth = 80;

  /// 图标轮廓，坐标与 `1.svg` 中 `<path d="...">` 完全一致。
  static final Path _outline = _buildPath();

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.shortestSide / _viewBoxSize;
    canvas.save();
    canvas.scale(scale);

    // ── 包围盒归一化：把图形实际占用的区域等比放大到铺满整个 viewBox ──
    final double bboxW = _bboxMaxX - _bboxMinX;
    final double bboxH = _bboxMaxY - _bboxMinY;
    // 以较长边为基准等比缩放，短边方向居中，保持图形不变形
    final double fit =
        _viewBoxSize / (bboxW > bboxH ? bboxW : bboxH) * _fitScale;
    final double dx = (_viewBoxSize - bboxW * fit) / 2;
    final double dy = (_viewBoxSize - bboxH * fit) / 2 + _offsetY;

    canvas.translate(dx, dy);
    canvas.scale(fit);
    canvas.translate(-_bboxMinX, -_bboxMinY);

    // ── 用户坐标变换（y 轴翻转），与 SVG 根元素 transform 一致 ──
    canvas.translate(0, _viewBoxSize);
    canvas.scale(_userUnit, -_userUnit);

    // 先描边加粗轮廓，再填充本体，使线条视觉重量与相邻 Material 图标一致
    final Paint strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final Paint fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.drawPath(_outline, strokePaint);
    canvas.drawPath(_outline, fillPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_EmbyFavoriteRandomPainter oldDelegate) =>
      oldDelegate.color != color;

  static Path _buildPath() {
    return Path()
      ..moveTo(3069, 3746)
      ..cubicTo(2972, 3720, 2890, 3651, 2854, 3565)
      ..cubicTo(2815, 3470, 2818, 3358, 2862, 3274)
      ..cubicTo(2895, 3212, 3373, 2730, 3402, 2730)
      ..cubicTo(3418, 2730, 3500, 2805, 3682, 2987)
      ..cubicTo(3979, 3283, 3985, 3291, 3985, 3430)
      ..cubicTo(3985, 3527, 3966, 3579, 3909, 3644)
      ..cubicTo(3790, 3780, 3592, 3794, 3446, 3678)
      ..cubicTo(3420, 3657, 3403, 3650, 3395, 3656)
      ..cubicTo(3314, 3715, 3283, 3732, 3234, 3745)
      ..cubicTo(3165, 3763, 3131, 3763, 3069, 3746)
      ..close()
      ..moveTo(3249, 3625)
      ..cubicTo(3267, 3616, 3305, 3587, 3336, 3560)
      ..cubicTo(3366, 3532, 3396, 3510, 3403, 3510)
      ..cubicTo(3419, 3510, 3461, 3539, 3477, 3561)
      ..cubicTo(3502, 3594, 3581, 3638, 3629, 3645)
      ..cubicTo(3760, 3663, 3880, 3560, 3880, 3430)
      ..cubicTo(3880, 3345, 3847, 3301, 3621, 3077)
      ..cubicTo(3506, 2963, 3408, 2870, 3403, 2870)
      ..cubicTo(3398, 2870, 3297, 2968, 3178, 3088)
      ..cubicTo(2971, 3296, 2961, 3307, 2945, 3364)
      ..cubicTo(2930, 3414, 2929, 3432, 2939, 3476)
      ..cubicTo(2954, 3542, 3013, 3612, 3073, 3634)
      ..cubicTo(3123, 3653, 3204, 3649, 3249, 3625)
      ..close()
      ..moveTo(1255, 3491)
      ..cubicTo(1205, 3469, 1154, 3412, 1140, 3363)
      ..cubicTo(1132, 3336, 1130, 3046, 1132, 2393)
      ..lineTo(1135, 1462)
      ..lineTo(1165, 1418)
      ..cubicTo(1184, 1391, 1213, 1366, 1245, 1350)
      ..lineTo(1295, 1325)
      ..lineTo(2380, 1322)
      ..cubicTo(3164, 1320, 3476, 1322, 3505, 1330)
      ..cubicTo(3570, 1349, 3621, 1390, 3647, 1445)
      ..lineTo(3670, 1495)
      ..lineTo(3670, 2038)
      ..lineTo(3670, 2580)
      ..lineTo(3615, 2580)
      ..lineTo(3560, 2580)
      ..lineTo(3560, 2040)
      ..lineTo(3560, 1500)
      ..lineTo(3531, 1468)
      ..lineTo(3502, 1435)
      ..lineTo(2405, 1432)
      ..lineTo(1308, 1430)
      ..lineTo(1274, 1464)
      ..lineTo(1240, 1498)
      ..lineTo(1240, 2409)
      ..cubicTo(1240, 3399, 1238, 3362, 1295, 3388)
      ..cubicTo(1314, 3397, 1492, 3400, 1985, 3400)
      ..lineTo(2650, 3400)
      ..lineTo(2650, 3455)
      ..lineTo(2650, 3510)
      ..lineTo(1973, 3510)
      ..cubicTo(1339, 3510, 1292, 3508, 1255, 3491)
      ..close()
      ..moveTo(2002, 2918)
      ..cubicTo(1993, 2909, 1990, 2777, 1990, 2384)
      ..cubicTo(1990, 1863, 1990, 1861, 2011, 1846)
      ..cubicTo(2042, 1825, 2061, 1835, 2234, 1958)
      ..cubicTo(2317, 2017, 2476, 2131, 2588, 2210)
      ..cubicTo(2780, 2346, 2791, 2356, 2788, 2384)
      ..cubicTo(2785, 2410, 2747, 2441, 2425, 2671)
      ..cubicTo(2068, 2927, 2032, 2948, 2002, 2918)
      ..close()
      ..moveTo(2370, 2574)
      ..cubicTo(2513, 2471, 2629, 2384, 2628, 2380)
      ..cubicTo(2626, 2373, 2449, 2245, 2133, 2022)
      ..lineTo(2100, 1999)
      ..lineTo(2100, 2379)
      ..cubicTo(2100, 2589, 2102, 2760, 2105, 2760)
      ..cubicTo(2107, 2760, 2227, 2676, 2370, 2574)
      ..close();
  }
}
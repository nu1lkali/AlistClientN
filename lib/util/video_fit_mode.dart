import 'package:alist/util/constant.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/material.dart';

/// 横屏全屏时画面的适配方式。
///
/// 由「设置 → 横屏画面适配」选择，也可在横屏 HUD 上点击图标循环切换；
/// 取值通过 [LandscapeFitModeHelper] 持久化到 SpUtil。
enum LandscapeFitMode {
  /// 自适应：只在「不需要放大视频、且裁切不超过 [autoMaxCropRatio]」时铺满，
  /// 否则等比完整显示（宁可留黑边，也不放大变糊、不裁掉字幕）。
  auto,

  /// 铺满裁剪：无视放大与裁切，填满整屏（相当于 BoxFit.cover）。
  cover,

  /// 完整显示：等比缩放到完整可见（相当于 BoxFit.contain）。
  contain,

  /// 拉伸填满：忽略宽高比填满整屏，画面会变形（相当于 BoxFit.fill）。
  fill;

  /// 自适应模式下允许的最大裁切比例（0.12 = 最多裁掉 12% 的画面）。
  ///
  /// 保护贴底的硬字幕：cover 会把画面上下（或左右）各裁掉一部分，
  /// 内外嵌字幕通常贴在底部 5~8% 处，裁太多就会被切掉。
  static const double autoMaxCropRatio = 0.12;

  String get label =>
      const ['自适应', '铺满裁剪', '完整显示', '拉伸填满'][index];

  String get description => const [
        '不放大视频、裁切不超过 12% 时铺满屏幕，否则完整显示',
        '填满整屏并裁掉多余画面，不限制放大',
        '等比缩放到完整可见，比例不匹配时保留黑边',
        '拉伸填满整屏，画面比例会变形',
      ][index];

  IconData get icon => const [
        Icons.aspect_ratio_rounded,
        Icons.crop_free_rounded,
        Icons.fit_screen_rounded,
        Icons.open_in_full_rounded,
      ][index];
}

/// [LandscapeFitMode] 的读写辅助。
class LandscapeFitModeHelper {
  static LandscapeFitMode read() {
    final v =
        SpUtil.getInt(AlistConstant.landscapeVideoFitMode, defValue: 0) ?? 0;
    if (v < 0 || v >= LandscapeFitMode.values.length) {
      return LandscapeFitMode.auto;
    }
    return LandscapeFitMode.values[v];
  }

  static void write(LandscapeFitMode mode) {
    SpUtil.putInt(AlistConstant.landscapeVideoFitMode, mode.index);
  }
}

import 'package:alist/util/subtitle/subtitle_controller.dart';
import 'package:alist/util/subtitle/subtitle_settings.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Flutter 层统一字幕渲染组件
///
/// 设计原则：
/// - 底层播放器（ExoPlayer/MPV）仅向 Flutter 传递 position
/// - 字幕样式在 Flutter 层统一渲染，确保两个内核下外观完全一致
/// - 支持文字描边（外轮廓）、半透明背景框、自定义颜色/字重/缩放
/// - Android 原生 GSY 播放器的字幕样式在 PlayerActivity.kt 中同步读取
///
/// 使用方式：放在 Stack 的最顶层，覆盖在视频播放器组件之上
class SubtitleView extends StatelessWidget {
  final SubtitleController controller;
  /// 字幕距底部的偏移量，需按各播放器底部控件高度调整，避免与进度条/控制栏重叠
  final double bottomOffset;

  const SubtitleView({
    super.key,
    required this.controller,
    this.bottomOffset = 60,
  });

  @override
  Widget build(BuildContext context) {
    final settings = SubtitleSettings.instance;

    return Obx(() {
      // 字幕功能未启用或未加载或当前无字幕文本 → 不渲染任何内容
      if (!settings.isSubtitleEnabled.value) return const SizedBox.shrink();
      if (!controller.isLoaded.value) return const SizedBox.shrink();

      final text = controller.currentText.value;
      if (text.isEmpty) return const SizedBox.shrink();

      return Positioned(
        left: 16,
        right: 16,
        bottom: bottomOffset, // 距底部留出进度条/控制栏空间
        child: IgnorePointer(
          child: Center(
            child: SubtitleTextWidget(text: text),
          ),
        ),
      );
    });
  }
}

/// 字幕文本渲染组件
///
/// 所有样式从 SubtitleSettings 响应式读取，支持：
/// - 字号 + 整体缩放
/// - 文字颜色 + 不透明度
/// - 字重（w400~w900）
/// - 描边宽度 + 颜色
/// - 背景颜色 + 不透明度
class SubtitleTextWidget extends StatelessWidget {
  final String text;

  const SubtitleTextWidget({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final settings = SubtitleSettings.instance;

    return Obx(() {
      final fontSize = settings.subtitleFontSize.value * settings.subtitleScale.value;
      final textColor = Color(settings.subtitleTextColor.value)
          .withOpacity(settings.subtitleTextOpacity.value);
      final fwIdx = settings.subtitleFontWeightIndex.value;
      final clampedFwIdx = fwIdx < 0
          ? 0
          : (fwIdx >= SubtitleSettings.fontWeightOptions.length
              ? SubtitleSettings.fontWeightOptions.length - 1
              : fwIdx);
      final fontWeight =
          SubtitleSettings.fontWeightOptions[clampedFwIdx].fontWeight;
      final strokeWidth = settings.subtitleStrokeWidth.value;
      final strokeColor = Color(settings.subtitleStrokeColor.value);
      final bgColor = Color(settings.subtitleBgColor.value)
          .withOpacity(settings.subtitleBgOpacity.value);

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // 描边层 — PaintingStyle.stroke 外轮廓
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: fontWeight,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = strokeWidth
                  ..color = strokeColor,
              ),
            ),
            // 填充层 — 带阴影加深立体感
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: textColor,
                shadows: [
                  Shadow(
                    offset: const Offset(1, 1),
                    blurRadius: 2,
                    color: strokeColor.withOpacity(0.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}
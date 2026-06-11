import 'package:alist/util/subtitle/subtitle_controller.dart';
import 'package:alist/util/subtitle/subtitle_settings.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Flutter 层统一字幕渲染组件
///
/// 设计原则：
/// - 底层播放器（ExoPlayer/MPV）仅向 Flutter 传递 position
/// - 字幕样式在 Flutter 层统一渲染，确保两个内核下外观完全一致
/// - 支持文字描边（外轮廓）、半透明暗色背景框
///
/// 使用方式：放在 Stack 的最顶层，覆盖在视频播放器组件之上
class SubtitleView extends StatelessWidget {
  final SubtitleController controller;

  const SubtitleView({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final settings = SubtitleSettings.instance;

    return Obx(() {
      // 字幕未启用或未加载或当前无字幕文本 → 不渲染任何内容
      if (!settings.isSubtitleEnabled.value) return const SizedBox.shrink();
      if (!controller.isLoaded.value) return const SizedBox.shrink();

      final text = controller.currentText.value;
      if (text.isEmpty) return const SizedBox.shrink();

      final fontSize = settings.subtitleFontSize.value;
      final bgOpacity = settings.subtitleBgOpacity.value;
      final strokeWidth = settings.subtitleStrokeWidth.value;

      return Positioned(
        left: 16,
        right: 16,
        bottom: 60, // 距底部留出进度条/控制栏空间
        child: IgnorePointer(
          child: Center(
            child: _SubtitleText(
              text: text,
              fontSize: fontSize,
              bgOpacity: bgOpacity,
              strokeWidth: strokeWidth,
            ),
          ),
        ),
      );
    });
  }
}

/// 字幕文本渲染组件
///
/// 实现方式：使用 Stack 叠加多层 Text 实现文字描边效果
/// - 底层：四方向偏移的描边文字（通过 PaintStyle.stroke 实现外轮廓）
/// - 顶层：正常填充文字
/// - 最外层包裹半透明暗色背景容器
class _SubtitleText extends StatelessWidget {
  final String text;
  final double fontSize;
  final double bgOpacity;
  final double strokeWidth;

  const _SubtitleText({
    required this.text,
    required this.fontSize,
    required this.bgOpacity,
    required this.strokeWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(bgOpacity),
        borderRadius: BorderRadius.circular(6),
      ),
      child: _buildStrokeText(),
    );
  }

  /// 构建带描边效果的字幕文本
  ///
  /// 使用 Stack + 多个 Text 组件实现描边效果：
  /// 1. 底层：4 个方向偏移的描边文字（stroke）
  /// 2. 顶层：白色填充文字
  Widget _buildStrokeText() {
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        // 描边层 - 四个方向偏移
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..color = Colors.black,
          ),
        ),
        // 填充层 - 白色文字
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            color: Colors.white,
            shadows: const [
              Shadow(
                offset: Offset(1, 1),
                blurRadius: 2,
                color: Colors.black54,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
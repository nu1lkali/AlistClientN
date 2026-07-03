import 'package:alist/util/subtitle/subtitle_settings.dart';
import 'package:alist/widget/alist_scaffold.dart';
import 'package:alist/widget/subtitle_view.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 字幕样式自定义页面
///
/// 所有修改即时通过 SubtitleSettings 持久化，
/// 顶部预览区使用与播放器完全相同的 SubtitleTextWidget 渲染。
class SubtitleStyleSettingsScreen extends StatelessWidget {
  const SubtitleStyleSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AlistScaffold(
      appbarTitle: const Text('字幕样式'),
      body: const _StyleSettingsBody(),
    );
  }
}

class _StyleSettingsBody extends StatelessWidget {
  const _StyleSettingsBody();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        // ---- 实时预览区 ----
        _PreviewCard(scheme: scheme, isDark: isDark),

        const SizedBox(height: 8),

        // ---- 文字设置 ----
        _SectionHeader(title: '文字设置', icon: Icons.text_fields_rounded, scheme: scheme),
        _SettingsCard(
          scheme: scheme,
          isDark: isDark,
          children: [
            _FontSizeSlider(),
            _ScaleSlider(),
            _FontWeightSelector(scheme: scheme),
          ],
        ),

        const SizedBox(height: 8),

        // ---- 颜色设置 ----
        _SectionHeader(title: '颜色与透明度', icon: Icons.color_lens_rounded, scheme: scheme),
        _SettingsCard(
          scheme: scheme,
          isDark: isDark,
          children: [
            _ColorPresetRow(
              label: '文字颜色',
              currentColorRx: SubtitleSettings.instance.subtitleTextColor,
              onColorPicked: (c) =>
                  SubtitleSettings.instance.setSubtitleTextColor(c.value),
              scheme: scheme,
              defaultColors: _textColorPresets,
            ),
            _OpacitySlider(
              label: '文字不透明度',
              rxValue: SubtitleSettings.instance.subtitleTextOpacity,
              onChanged: (v) =>
                  SubtitleSettings.instance.setSubtitleTextOpacity(v),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // ---- 描边设置 ----
        _SectionHeader(title: '描边设置', icon: Icons.border_color_rounded, scheme: scheme),
        _SettingsCard(
          scheme: scheme,
          isDark: isDark,
          children: [
            _StrokeWidthSlider(),
            _ColorPresetRow(
              label: '描边颜色',
              currentColorRx: SubtitleSettings.instance.subtitleStrokeColor,
              onColorPicked: (c) =>
                  SubtitleSettings.instance.setSubtitleStrokeColor(c.value),
              scheme: scheme,
              defaultColors: _strokeColorPresets,
            ),
          ],
        ),

        const SizedBox(height: 8),

        // ---- 背景设置 ----
        _SectionHeader(title: '背景设置', icon: Icons.format_paint_rounded, scheme: scheme),
        _SettingsCard(
          scheme: scheme,
          isDark: isDark,
          children: [
            _OpacitySlider(
              label: '背景不透明度',
              rxValue: SubtitleSettings.instance.subtitleBgOpacity,
              onChanged: (v) =>
                  SubtitleSettings.instance.setSubtitleBgOpacity(v),
            ),
            _ColorPresetRow(
              label: '背景颜色',
              currentColorRx: SubtitleSettings.instance.subtitleBgColor,
              onColorPicked: (c) =>
                  SubtitleSettings.instance.setSubtitleBgColor(c.value),
              scheme: scheme,
              defaultColors: _bgColorPresets,
            ),
          ],
        ),

        const SizedBox(height: 16),

        // ---- 重置按钮 ----
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            onPressed: () => SubtitleSettings.instance.resetToDefaults(),
            icon: const Icon(Icons.restore_rounded, size: 18),
            label: const Text('恢复默认样式'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
}

// ==================== 预设调色板 ====================

const _textColorPresets = [
  Colors.white,
  Color(0xFFFFFF00), // 黄
  Color(0xFF00FF00), // 绿
  Color(0xFF00FFFF), // 青
  Color(0xFFFF8800), // 橙
  Color(0xFFFF4081), // 粉
];

const _strokeColorPresets = [
  Colors.black,
  Color(0xFF333333), // 深灰
  Colors.white,
  Color(0xFF880000), // 暗红
  Color(0xFF000088), // 暗蓝
];

const _bgColorPresets = [
  Colors.black,
  Color(0xFF1A1A1A), // 近黑
  Color(0xFF333333), // 深灰
  Colors.transparent,
];

// ==================== 预览卡片 ====================

class _PreviewCard extends StatelessWidget {
  final ColorScheme scheme;
  final bool isDark;

  const _PreviewCard({required this.scheme, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isDark ? Colors.grey.shade900 : Colors.grey.shade200,
      ),
      height: 160,
      child: Stack(
        children: [
          // 模拟视频画面
          Center(
            child: Icon(Icons.movie_rounded,
                size: 48,
                color: isDark
                    ? Colors.white.withOpacity(0.08)
                    : Colors.black.withOpacity(0.08)),
          ),
          // 字幕预览
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SubtitleTextWidget(text: '示例字幕 Preview'),
            ),
          ),
          // 底部标签
          Positioned(
            bottom: 8,
            right: 12,
            child: Text('实时预览',
                style: TextStyle(fontSize: 10, color: scheme.outline)),
          ),
        ],
      ),
    );
  }
}

// ==================== 基础控件 ====================

/// 分组标题
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final ColorScheme scheme;

  const _SectionHeader(
      {required this.title, required this.icon, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(title,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

/// 统一卡片容器
class _SettingsCard extends StatelessWidget {
  final ColorScheme scheme;
  final bool isDark;
  final List<Widget> children;

  const _SettingsCard(
      {required this.scheme,
      required this.isDark,
      required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: isDark ? 0 : 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color:
          isDark ? scheme.surfaceVariant.withOpacity(0.3) : scheme.surface,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: scheme.outlineVariant.withOpacity(0.25)),
          ]
        ],
      ),
    );
  }
}

// ==================== 滑块控件 ====================

/// 带标签的滑块
class _LabeledSlider extends StatelessWidget {
  final String label;
  final String displayValue;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  const _LabeledSlider({
    required this.label,
    required this.displayValue,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
              Text(displayValue,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary)),
            ],
          ),
          const SizedBox(height: 4),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: displayValue,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// 带标签的透明度滑块
class _OpacitySlider extends StatelessWidget {
  final String label;
  final RxDouble rxValue;
  final ValueChanged<double> onChanged;

  const _OpacitySlider({
    required this.label,
    required this.rxValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final v = rxValue.value;
      return _LabeledSlider(
        label: label,
        displayValue: '${(v * 100).round()}%',
        value: v,
        min: 0.0,
        max: 1.0,
        divisions: 20,
        onChanged: onChanged,
      );
    });
  }
}

// ==================== 具体样式控件 ====================

class _FontSizeSlider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final settings = SubtitleSettings.instance;
    return Obx(() {
      final v = settings.subtitleFontSize.value;
      return _LabeledSlider(
        label: '字号',
        displayValue: '${v.round()}',
        value: v,
        min: 10,
        max: 40,
        divisions: 30,
        onChanged: (val) => settings.setSubtitleFontSize(val),
      );
    });
  }
}

class _ScaleSlider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final settings = SubtitleSettings.instance;
    return Obx(() {
      final v = settings.subtitleScale.value;
      return _LabeledSlider(
        label: '缩放',
        displayValue: '${v.toStringAsFixed(1)}x',
        value: v,
        min: 0.5,
        max: 2.0,
        divisions: 15,
        onChanged: (val) => settings.setSubtitleScale(val),
      );
    });
  }
}

class _StrokeWidthSlider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final settings = SubtitleSettings.instance;
    return Obx(() {
      final v = settings.subtitleStrokeWidth.value;
      return _LabeledSlider(
        label: '描边宽度',
        displayValue: v.toStringAsFixed(1),
        value: v,
        min: 0,
        max: 5.0,
        divisions: 20,
        onChanged: (val) => settings.setSubtitleStrokeWidth(val),
      );
    });
  }
}

// ==================== 字重选择器 ====================

class _FontWeightSelector extends StatelessWidget {
  final ColorScheme scheme;

  const _FontWeightSelector({required this.scheme});

  @override
  Widget build(BuildContext context) {
    final settings = SubtitleSettings.instance;
    return Obx(() {
      final idx = settings.subtitleFontWeightIndex.value;
      final clampedIdx = idx < 0
          ? 0
          : (idx >= SubtitleSettings.fontWeightOptions.length
              ? SubtitleSettings.fontWeightOptions.length - 1
              : idx);
      final currentInfo = SubtitleSettings.fontWeightOptions[clampedIdx];
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('字重',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
                Text(currentInfo.localizedLabel,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(
                SubtitleSettings.fontWeightOptions.length,
                (i) {
                  final info = SubtitleSettings.fontWeightOptions[i];
                  final selected = i == clampedIdx;
                  return ChoiceChip(
                    label: Text(info.localizedLabel,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: info.fontWeight)),
                    selected: selected,
                    onSelected: (_) =>
                        settings.setSubtitleFontWeightIndex(i),
                    selectedColor:
                        scheme.primaryContainer,
                    labelStyle: TextStyle(
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ==================== 颜色预设选择 ====================

class _ColorPresetRow extends StatelessWidget {
  final String label;
  final RxInt currentColorRx;
  final ValueChanged<Color> onColorPicked;
  final ColorScheme scheme;
  final List<Color> defaultColors;

  const _ColorPresetRow({
    required this.label,
    required this.currentColorRx,
    required this.onColorPicked,
    required this.scheme,
    required this.defaultColors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Obx(() {
            final current = Color(currentColorRx.value);
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...defaultColors.map((c) => _colorDot(c, current, onColorPicked)),
                const SizedBox(width: 4),
                // 自定义颜色按钮
                GestureDetector(
                  onTap: () => _showCustomColorPicker(context, onColorPicked),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: scheme.outlineVariant, width: 1.5),
                      gradient: const SweepGradient(colors: [
                        Colors.red, Colors.yellow, Colors.green,
                        Colors.cyan, Colors.blue, Colors.purple, Colors.red,
                      ]),
                    ),
                    child: const Center(
                      child: Icon(Icons.add, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _colorDot(Color color, Color current, ValueChanged<Color> onTap) {
    final selected = color.value == current.value;
    return GestureDetector(
      onTap: () => onTap(color),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? (color.computeLuminance() > 0.5
                    ? Colors.black87
                    : Colors.white70)
                : Colors.transparent,
            width: selected ? 3 : 0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: selected
            ? Icon(Icons.check_rounded,
                size: 18,
                color: color.computeLuminance() > 0.5
                    ? Colors.black87
                    : Colors.white70)
            : null,
      ),
    );
  }

  void _showCustomColorPicker(
      BuildContext context, ValueChanged<Color> onPicked) {
    // 简单的自定义颜色输入对话框
    final controller = TextEditingController(
        text: '#${currentColorRx.value.toRadixString(16).padLeft(8, '0').toUpperCase()}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义颜色'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('输入 ARGB 十六进制颜色值',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'FFRRGGBB (如 FF00FF00)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final hex = controller.text.trim().replaceAll('#', '');
              final parsed = int.tryParse(hex, radix: 16);
              if (parsed != null) {
                onPicked(Color(parsed));
                Navigator.pop(ctx);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
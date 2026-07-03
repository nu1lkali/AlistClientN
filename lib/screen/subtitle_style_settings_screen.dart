import 'package:alist/util/subtitle/subtitle_settings.dart';
import 'package:alist/widget/alist_scaffold.dart';
import 'package:alist/widget/subtitle_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
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
  Color(0xFF666666), // 中灰
  Colors.white,
  Color(0xFF880000), // 暗红
  Color(0xFF006600), // 暗绿
  Color(0xFF000088), // 暗蓝
  Color(0xFF440066), // 暗紫
];

const _bgColorPresets = [
  Colors.transparent,
  Colors.black,
  Color(0xFF1A1A1A), // 近黑
  Color(0xFF2A2A2A), // 深灰
  Color(0xFF111133), // 深蓝黑
  Color(0xFF331111), // 深红黑
  Color(0xFF1A1A2E), // 深紫黑
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
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 8.0;
                final chipWidth =
                    (constraints.maxWidth - spacing * 2) / 3;
                final options = SubtitleSettings.fontWeightOptions;
                return Column(
                  children: [
                    for (int row = 0; row < 2; row++)
                      Padding(
                        padding: EdgeInsets.only(top: row > 0 ? spacing : 0),
                        child: Row(
                          children: List.generate(3, (col) {
                            final i = row * 3 + col;
                            final info = options[i];
                            final selected = i == clampedIdx;
                            return Padding(
                              padding: EdgeInsets.only(
                                  right: col < 2 ? spacing : 0),
                              child: SizedBox(
                                width: chipWidth,
                                child: ChoiceChip(
                                  label: Text(info.localizedLabel,
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: info.fontWeight)),
                                  selected: selected,
                                  onSelected: (_) =>
                                      settings.setSubtitleFontWeightIndex(i),
                                  selectedColor: scheme.primaryContainer,
                                  labelStyle: TextStyle(
                                    color: selected
                                        ? scheme.onPrimaryContainer
                                        : scheme.onSurface,
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      );
    });
  }
}

// ==================== 颜色预设选择 ====================

/// 每个颜色圆点 + 间距的宽度
const double _kDotSize = 36;
const double _kDotSpacing = 8;

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
              Obx(() => Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Color(currentColorRx.value),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: scheme.outlineVariant, width: 1),
                ),
              )),
            ],
          ),
          const SizedBox(height: 8),
          Obx(() {
            final current = Color(currentColorRx.value);
            return LayoutBuilder(
              builder: (context, constraints) {
                // 自定义颜色按钮宽度：圆点 + 前方间距
                const customBtnWidth = _kDotSize + 4;
                // 计算能放几个预设颜色
                final maxDots = ((constraints.maxWidth - customBtnWidth) /
                        (_kDotSize + _kDotSpacing))
                    .floor()
                    .clamp(3, defaultColors.length);
                final displayColors = defaultColors.take(maxDots).toList();
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ...displayColors
                        .map((c) => _colorDot(c, current, onColorPicked)),
                    // 自定义颜色按钮
                    GestureDetector(
                      onTap: () =>
                          _showCustomColorPicker(context, onColorPicked, scheme),
                      child: Container(
                        width: _kDotSize,
                        height: _kDotSize,
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
                          child:
                              Icon(Icons.add, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              },
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
        width: _kDotSize,
        height: _kDotSize,
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
      BuildContext context, ValueChanged<Color> onPicked, ColorScheme scheme) {
    Color pickedColor = Color(currentColorRx.value);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          return Center(
            child: Container(
              width: 340,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 标题栏
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('自定义颜色',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                  // 颜色选择器主体
                  ColorPicker(
                    pickerColor: pickedColor,
                    onColorChanged: (color) {
                      setState(() {
                        pickedColor = color;
                      });
                    },
                    enableAlpha: true,
                    hexInputBar: true,
                    labelTypes: const [],
                    displayThumbColor: true,
                    pickerAreaHeightPercent: 0.55,
                  ),
                  // 按钮栏
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 12, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('取消')),
                        const SizedBox(width: 4),
                        FilledButton(
                          onPressed: () {
                            onPicked(pickedColor);
                            Navigator.pop(ctx);
                          },
                          child: const Text('确定'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
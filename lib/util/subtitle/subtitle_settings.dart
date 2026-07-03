import 'package:alist/util/constant.dart';
import 'package:alist/util/subtitle/subtitle_matcher.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 字幕全局设置管理器
/// 使用 GetX 的 Rx 系列实现响应式状态管理
/// 当 isSubtitleEnabled 为 true 时，播放器在加载视频时执行字幕匹配与解析逻辑
/// 当 isSubtitleEnabled 为 false 时，完全关闭字幕功能
class SubtitleSettings {
  SubtitleSettings._();

  static final SubtitleSettings instance = SubtitleSettings._();

  /// 持久化 key
  static const String _keySubtitleFontSize = 'subtitleFontSize';
  static const String _keySubtitleBgOpacity = 'subtitleBgOpacity';
  static const String _keySubtitleStrokeWidth = 'subtitleStrokeWidth';
  static const String _keySubtitleMatchMode = 'subtitleMatchMode';
  static const String _keySubtitleTextColor = 'subtitleTextColor';
  static const String _keySubtitleStrokeColor = 'subtitleStrokeColor';
  static const String _keySubtitleBgColor = 'subtitleBgColor';
  static const String _keySubtitleFontWeightIndex = 'subtitleFontWeightIndex';
  static const String _keySubtitleTextOpacity = 'subtitleTextOpacity';
  static const String _keySubtitleScale = 'subtitleScale';

  // ---- 开关 & 匹配模式 ----

  /// 字幕是否启用（全局响应式状态）
  final RxBool isSubtitleEnabled = true.obs;

  /// 字幕匹配模式（默认双模式：先精确后模糊）
  final Rx<SubtitleMatchMode> subtitleMatchMode = SubtitleMatchMode.dual.obs;

  // ---- 文字样式 ----

  /// 字幕字体大小（默认 16）
  final RxDouble subtitleFontSize = 16.0.obs;

  /// 字幕文字颜色（默认白色 0xFFFFFFFF）
  final RxInt subtitleTextColor = 0xFFFFFFFF.obs;

  /// 字幕文字不透明度（默认 1.0，范围 0.0 ~ 1.0）
  final RxDouble subtitleTextOpacity = 1.0.obs;

  /// 字幕字重索引（默认 2 → w500）
  /// 映射: 0=w400, 1=w500, 2=w600, 3=w700, 4=w800, 5=w900
  final RxInt subtitleFontWeightIndex = 2.obs;

  /// 字幕整体缩放（默认 1.0，范围 0.5 ~ 2.0）
  final RxDouble subtitleScale = 1.0.obs;

  // ---- 描边样式 ----

  /// 字幕描边宽度（默认 1.5）
  final RxDouble subtitleStrokeWidth = 1.5.obs;

  /// 字幕描边颜色（默认黑色 0xFF000000）
  final RxInt subtitleStrokeColor = 0xFF000000.obs;

  // ---- 背景样式 ----

  /// 字幕背景不透明度（默认 0.5，范围 0.0 ~ 1.0）
  final RxDouble subtitleBgOpacity = 0.5.obs;

  /// 字幕背景颜色（默认黑色 0xFF000000）
  final RxInt subtitleBgColor = 0xFF000000.obs;

  // ---- 色调映射 ----

  /// 字重索引 → FontWeight 映射表
  static const List<FontWeightInfo> fontWeightOptions = [
    FontWeightInfo(400, 'Regular', '常规'),
    FontWeightInfo(500, 'Medium', '中等'),
    FontWeightInfo(600, 'SemiBold', '半粗'),
    FontWeightInfo(700, 'Bold', '粗体'),
    FontWeightInfo(800, 'ExtraBold', '特粗'),
    FontWeightInfo(900, 'Black', '黑体'),
  ];

  /// 从持久化存储加载设置
  void loadFromStorage() {
    // isSubtitleEnabled 现在与 enableLocalSubtitle 同步
    isSubtitleEnabled.value =
        SpUtil.getBool(AlistConstant.enableLocalSubtitle, defValue: false) ?? false;

    // 文字样式
    subtitleFontSize.value =
        SpUtil.getDouble(_keySubtitleFontSize, defValue: 16.0) ?? 16.0;
    subtitleTextColor.value =
        SpUtil.getInt(_keySubtitleTextColor, defValue: 0xFFFFFFFF) ?? 0xFFFFFFFF;
    subtitleTextOpacity.value =
        SpUtil.getDouble(_keySubtitleTextOpacity, defValue: 1.0) ?? 1.0;
    subtitleFontWeightIndex.value =
        SpUtil.getInt(_keySubtitleFontWeightIndex, defValue: 2) ?? 2;
    subtitleScale.value =
        SpUtil.getDouble(_keySubtitleScale, defValue: 1.0) ?? 1.0;

    // 描边样式
    subtitleStrokeWidth.value =
        SpUtil.getDouble(_keySubtitleStrokeWidth, defValue: 1.5) ?? 1.5;
    subtitleStrokeColor.value =
        SpUtil.getInt(_keySubtitleStrokeColor, defValue: 0xFF000000) ?? 0xFF000000;

    // 背景样式
    subtitleBgOpacity.value =
        SpUtil.getDouble(_keySubtitleBgOpacity, defValue: 0.5) ?? 0.5;
    subtitleBgColor.value =
        SpUtil.getInt(_keySubtitleBgColor, defValue: 0xFF000000) ?? 0xFF000000;

    // 匹配模式
    final modeIndex = SpUtil.getInt(_keySubtitleMatchMode, defValue: 2) ?? 2;
    subtitleMatchMode.value = SubtitleMatchMode.values[modeIndex.clamp(0, SubtitleMatchMode.values.length - 1)];
  }

  /// 重置所有样式为默认值
  void resetToDefaults() {
    setSubtitleFontSize(16.0);
    setSubtitleTextColor(0xFFFFFFFF);
    setSubtitleTextOpacity(1.0);
    setSubtitleFontWeightIndex(2);
    setSubtitleScale(1.0);
    setSubtitleStrokeWidth(1.5);
    setSubtitleStrokeColor(0xFF000000);
    setSubtitleBgOpacity(0.5);
    setSubtitleBgColor(0xFF000000);
  }

  // ---- setter 方法 ----

  /// 持久化字幕开关（与 enableLocalSubtitle 共用同一个 key）
  void setSubtitleEnabled(bool enabled) {
    isSubtitleEnabled.value = enabled;
    SpUtil.putBool(AlistConstant.enableLocalSubtitle, enabled);
  }

  /// 持久化字幕字体大小
  void setSubtitleFontSize(double size) {
    subtitleFontSize.value = size;
    SpUtil.putDouble(_keySubtitleFontSize, size);
  }

  /// 持久化字幕文字颜色
  void setSubtitleTextColor(int color) {
    subtitleTextColor.value = color;
    SpUtil.putInt(_keySubtitleTextColor, color);
  }

  /// 持久化字幕文字不透明度
  void setSubtitleTextOpacity(double opacity) {
    subtitleTextOpacity.value = opacity;
    SpUtil.putDouble(_keySubtitleTextOpacity, opacity);
  }

  /// 持久化字幕字重索引
  void setSubtitleFontWeightIndex(int index) {
    subtitleFontWeightIndex.value = index;
    SpUtil.putInt(_keySubtitleFontWeightIndex, index);
  }

  /// 持久化字幕整体缩放
  void setSubtitleScale(double scale) {
    subtitleScale.value = scale;
    SpUtil.putDouble(_keySubtitleScale, scale);
  }

  /// 持久化字幕描边宽度
  void setSubtitleStrokeWidth(double width) {
    subtitleStrokeWidth.value = width;
    SpUtil.putDouble(_keySubtitleStrokeWidth, width);
  }

  /// 持久化字幕描边颜色
  void setSubtitleStrokeColor(int color) {
    subtitleStrokeColor.value = color;
    SpUtil.putInt(_keySubtitleStrokeColor, color);
  }

  /// 持久化字幕背景不透明度
  void setSubtitleBgOpacity(double opacity) {
    subtitleBgOpacity.value = opacity;
    SpUtil.putDouble(_keySubtitleBgOpacity, opacity);
  }

  /// 持久化字幕背景颜色
  void setSubtitleBgColor(int color) {
    subtitleBgColor.value = color;
    SpUtil.putInt(_keySubtitleBgColor, color);
  }

  /// 持久化字幕匹配模式
  void setSubtitleMatchMode(SubtitleMatchMode mode) {
    subtitleMatchMode.value = mode;
    SpUtil.putInt(_keySubtitleMatchMode, mode.index);
  }
}

/// 字重选项描述
class FontWeightInfo {
  final int weight;
  final String label; // 英文标签（默认）
  final String labelZh; // 中文标签
  const FontWeightInfo(this.weight, this.label, this.labelZh);

  FontWeight get fontWeight {
    switch (weight) {
      case 400: return FontWeight.w400;
      case 500: return FontWeight.w500;
      case 600: return FontWeight.w600;
      case 700: return FontWeight.w700;
      case 800: return FontWeight.w800;
      case 900: return FontWeight.w900;
      default: return FontWeight.w600;
    }
  }

  /// 根据系统语言获取本地化标签
  String get localizedLabel {
    final isZh = Get.locale?.toString().startsWith("zh_") == true;
    return isZh ? labelZh : label;
  }
}
import 'package:flustars/flustars.dart';
import 'package:get/get.dart';

/// 字幕全局设置管理器
/// 使用 GetX 的 RxBool 实现响应式状态管理
/// 当 isSubtitleEnabled 为 true 时，播放器在加载视频时执行字幕匹配与解析逻辑
/// 当 isSubtitleEnabled 为 false 时，完全关闭字幕功能
class SubtitleSettings {
  SubtitleSettings._();

  static final SubtitleSettings instance = SubtitleSettings._();

  /// 持久化 key
  static const String _keySubtitleEnabled = 'subtitleEnabled';
  static const String _keySubtitleFontSize = 'subtitleFontSize';
  static const String _keySubtitleBgOpacity = 'subtitleBgOpacity';
  static const String _keySubtitleStrokeWidth = 'subtitleStrokeWidth';

  /// 字幕是否启用（全局响应式状态）
  final RxBool isSubtitleEnabled = true.obs;

  /// 字幕字体大小（默认 16）
  final RxDouble subtitleFontSize = 16.0.obs;

  /// 字幕背景不透明度（默认 0.5，范围 0.0 ~ 1.0）
  final RxDouble subtitleBgOpacity = 0.5.obs;

  /// 字幕描边宽度（默认 1.5）
  final RxDouble subtitleStrokeWidth = 1.5.obs;

  /// 从持久化存储加载设置
  void loadFromStorage() {
    isSubtitleEnabled.value =
        SpUtil.getBool(_keySubtitleEnabled, defValue: true) ?? true;
    subtitleFontSize.value =
        SpUtil.getDouble(_keySubtitleFontSize, defValue: 16.0) ?? 16.0;
    subtitleBgOpacity.value =
        SpUtil.getDouble(_keySubtitleBgOpacity, defValue: 0.5) ?? 0.5;
    subtitleStrokeWidth.value =
        SpUtil.getDouble(_keySubtitleStrokeWidth, defValue: 1.5) ?? 1.5;
  }

  /// 持久化字幕开关
  void setSubtitleEnabled(bool enabled) {
    isSubtitleEnabled.value = enabled;
    SpUtil.putBool(_keySubtitleEnabled, enabled);
  }

  /// 持久化字幕字体大小
  void setSubtitleFontSize(double size) {
    subtitleFontSize.value = size;
    SpUtil.putDouble(_keySubtitleFontSize, size);
  }

  /// 持久化字幕背景不透明度
  void setSubtitleBgOpacity(double opacity) {
    subtitleBgOpacity.value = opacity;
    SpUtil.putDouble(_keySubtitleBgOpacity, opacity);
  }

  /// 持久化字幕描边宽度
  void setSubtitleStrokeWidth(double width) {
    subtitleStrokeWidth.value = width;
    SpUtil.putDouble(_keySubtitleStrokeWidth, width);
  }
}
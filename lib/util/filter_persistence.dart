import 'package:alist/screen/file_list/file_list_menu_anchor.dart';
import 'package:flustars/flustars.dart';

/// 文件列表过滤状态持久化工具
///
/// 使用 SharedPreferences 存储用户选择的过滤模式，
/// 确保切换页面或重启 App 后依然保留上次的过滤状态。
class FilterPersistence {
  FilterPersistence._();

  static const String _keyFilterMode = 'fileFilterMode';

  /// 保存当前过滤模式
  static void saveFilterMode(FilterMode mode) {
    SpUtil.putInt(_keyFilterMode, mode.index);
  }

  /// 加载上次保存的过滤模式
  ///
  /// 如果没有保存过，返回 [FilterMode.none]
  static FilterMode loadFilterMode() {
    final index = SpUtil.getInt(_keyFilterMode, defValue: FilterMode.none.index) ?? FilterMode.none.index;
    if (index >= 0 && index < FilterMode.values.length) {
      return FilterMode.values[index];
    }
    return FilterMode.none;
  }

  /// 清除保存的过滤模式（重置为默认）
  static void clearFilterMode() {
    SpUtil.remove(_keyFilterMode);
  }
}

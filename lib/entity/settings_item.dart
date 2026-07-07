import 'package:flutter/material.dart';

/// 搜索型设置项方向：nav = 导航跳转, switchTile = 开关, custom = 自定义 widget
enum SettingsItemType { nav, switchTile, custom }

/// 单个设置项的数据模型
class SettingsItemData {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final List<String> searchTerms; // 额外搜索关键词（拼音/英文/别名）
  final SettingsItemType type;
  final VoidCallback? onTap;
  final bool Function()? switchValue;
  final ValueChanged<bool>? switchOnChanged;
  final bool Function()? switchEnabled;
  final Widget Function(BuildContext, ColorScheme, bool)? customBuilder;

  const SettingsItemData({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailingText,
    this.searchTerms = const [],
    this.type = SettingsItemType.nav,
    this.onTap,
    this.switchValue,
    this.switchOnChanged,
    this.switchEnabled,
    this.customBuilder,
  });

  /// 是否匹配搜索关键词
  bool matches(String query) {
    final q = query.toLowerCase();
    if (title.toLowerCase().contains(q)) return true;
    if (subtitle != null && subtitle!.toLowerCase().contains(q)) return true;
    for (final term in searchTerms) {
      if (term.toLowerCase().contains(q)) return true;
    }
    return false;
  }
}

/// 设置分组
class SettingsSectionData {
  final String title;
  final IconData icon;
  final List<SettingsItemData> items;

  const SettingsSectionData({
    required this.title,
    required this.icon,
    required this.items,
  });

  /// 过滤后只保留匹配项
  SettingsSectionData filter(String query) {
    final matched = items.where((i) => i.matches(query)).toList();
    return SettingsSectionData(title: title, icon: icon, items: matched);
  }

  bool get hasMatches => items.isNotEmpty;
}

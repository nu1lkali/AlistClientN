import 'dart:convert';
import 'package:flustars/flustars.dart';

/// 搜索过滤规则管理器
/// 存储路径过滤规则，使用 SharedPreferences 持久化
class SearchFilterHelper {
  static const String _key = 'searchFilterRules';

  /// 获取所有过滤规则
  static List<SearchFilterRule> getAllRules() {
    final jsonStr = SpUtil.getString(_key);
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final List<dynamic> list = jsonDecode(jsonStr);
      return list.map((e) => SearchFilterRule.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// 保存所有过滤规则
  static Future<void> saveAllRules(List<SearchFilterRule> rules) async {
    final jsonStr = jsonEncode(rules.map((r) => r.toJson()).toList());
    await SpUtil.putString(_key, jsonStr);
  }

  /// 添加一条规则
  static Future<void> addRule(SearchFilterRule rule) async {
    final rules = getAllRules();
    // 检查重复
    if (rules.any((r) => r.path == rule.path)) return;
    rules.add(rule);
    await saveAllRules(rules);
  }

  /// 更新一条规则
  static Future<void> updateRule(int index, SearchFilterRule rule) async {
    final rules = getAllRules();
    if (index < 0 || index >= rules.length) return;
    rules[index] = rule;
    await saveAllRules(rules);
  }

  /// 删除一条规则
  static Future<void> deleteRule(int index) async {
    final rules = getAllRules();
    if (index < 0 || index >= rules.length) return;
    rules.removeAt(index);
    await saveAllRules(rules);
  }

  /// 过滤上下文
  static bool shouldFilter(String filePath, {bool inSearch = false, bool inFileList = false}) {
    final rules = getAllRules();
    if (rules.isEmpty) return false;

    for (final rule in rules) {
      // 根据上下文判断是否启用
      if (inSearch && !rule.filterInSearch) continue;
      if (inFileList && !rule.filterInFileList) continue;
      // 如果没有指定上下文，用旧的 enabled 字段
      if (!inSearch && !inFileList && !rule.enabled) continue;
      final filterPath = _normalizePath(rule.path);
      final normalizedFilePath = _normalizePath(filePath);

      // 完全匹配规则路径本身，也过滤
      if (normalizedFilePath == filterPath) return true;
      
      // 文件路径以规则路径 + '/' 开头，说明在规则路径下面
      if (normalizedFilePath.startsWith('$filterPath/')) return true;
    }
    return false;
  }

  /// 标准化路径：去除末尾斜杠，确保以斜杠开头
  static String _normalizePath(String path) {
    var p = path.trim();
    if (!p.startsWith('/')) p = '/$p';
    // 去除末尾的 /
    while (p.endsWith('/') && p.length > 1) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }
}

/// 搜索过滤规则
class SearchFilterRule {
  /// 过滤的目录路径，例如 /nas/xxx/abcd
  String path;

  /// 规则备注名称（可选）
  String remark;

  /// 是否启用（总开关，兼容旧数据）
  bool enabled;

  /// 是否在搜索结果中过滤
  bool filterInSearch;

  /// 是否在文件列表浏览中过滤
  bool filterInFileList;

  SearchFilterRule({
    required this.path,
    this.remark = '',
    this.enabled = true,
    this.filterInSearch = true,
    this.filterInFileList = true,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'remark': remark,
        'enabled': enabled,
        'filterInSearch': filterInSearch,
        'filterInFileList': filterInFileList,
      };

  factory SearchFilterRule.fromJson(Map<String, dynamic> json) =>
      SearchFilterRule(
        path: json['path'] as String? ?? '',
        remark: json['remark'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
        filterInSearch: json['filterInSearch'] as bool? ?? true,
        filterInFileList: json['filterInFileList'] as bool? ?? true,
      );
}

import 'dart:convert';

import 'package:alist/util/constant.dart';
import 'package:alist/util/player/tiktok_playback_core.dart';
import 'package:alist/util/player/video_format.dart';
import 'package:flustars/flustars.dart';

/// 某个格式指定用哪个内核。
enum KernelChoice {
  /// 交给自动选路（容器嗅探 + Exo 优先 + 失败回落 libmpv）。
  auto,

  /// 指定 ExoPlayer（硬解）。放不出来时仍会回落 libmpv —— 指定了也不至于播不了。
  exo,

  /// 指定 libmpv（兼容内核，自带完整 FFmpeg）。
  compat,
}

extension KernelChoiceX on KernelChoice {
  String get key => const ['auto', 'exo', 'compat'][index];

  String get label => const ['自动', 'ExoPlayer', 'libmpv'][index];

  String get shortLabel => const ['自动', 'Exo', 'MPV'][index];

  static KernelChoice fromKey(String? k) => KernelChoice.values.firstWhere(
        (e) => e.key == k,
        orElse: () => KernelChoice.auto,
      );
}

/// 「按格式指定播放内核」的用户配置。
///
/// **默认关闭**：关闭时播放器的选路逻辑与改造前完全一致（扩展名清单 + 容器嗅探
/// + Exo 优先 + 失败回落），不会有任何行为变化。开启后用预置的一份默认配置
/// （老格式 → libmpv、常见格式 → ExoPlayer），用户可以逐条改。
///
/// 关闭状态下所有 [resolve] 都返回 [KernelChoice.auto]，等于把决定权还给自动选路。
class KernelRuleSettings {
  KernelRuleSettings._();

  static KernelRuleSettings? _instance;

  static KernelRuleSettings get instance =>
      _instance ??= KernelRuleSettings._().._load();

  /// 「文件名探测不出格式」时的兜底选择所用的键。
  static const String unknownKey = '*';

  /// 预置配置里出现的所有键（用于设置页展示顺序：先 Exo 组、再 MPV 组）。
  static final List<String> defaultKeys = <String>[
    ...kExoFriendlyFormats,
    ...kCompatFormatsHandledByMediaKit,
  ];

  bool enabled = false;

  final Map<String, KernelChoice> _rules = <String, KernelChoice>{};

  /// 当前规则（键为扩展名，或 [unknownKey] 表示「探测不出格式」）。
  Map<String, KernelChoice> get rules => Map<String, KernelChoice>.unmodifiable(_rules);

  KernelChoice ruleOf(String key) => _rules[key] ?? KernelChoice.auto;

  // ═══════════════ 持久化 ═══════════════

  void _load() {
    enabled = SpUtil.getBool(AlistConstant.kernelRuleEnabled, defValue: false) ?? false;
    final raw = SpUtil.getString(AlistConstant.kernelRuleJson) ?? '';
    _rules.clear();
    if (raw.isEmpty) {
      _applyDefaults();
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((k, v) {
          if (k is! String || v is! String) return;
          final c = KernelChoiceX.fromKey(v);
          // auto 不落库：不存在的键本身就表示自动
          if (c != KernelChoice.auto) _rules[k] = c;
        });
      }
    } catch (_) {
      _applyDefaults();
    }
  }

  Future<void> save() async {
    final data = <String, String>{
      for (final e in _rules.entries) e.key: e.value.key,
    };
    await SpUtil.putString(AlistConstant.kernelRuleJson, jsonEncode(data));
  }

  void _applyDefaults() {
    _rules
      ..clear()
      ..addAll(defaultRuleMap());
  }

  /// 预置的默认配置：老格式走 libmpv，常见格式走 ExoPlayer，探测不出格式走自动。
  static Map<String, KernelChoice> defaultRuleMap() {
    final m = <String, KernelChoice>{};
    for (final e in kExoFriendlyFormats) {
      m[e] = KernelChoice.exo;
    }
    for (final e in kCompatFormatsHandledByMediaKit) {
      m[e] = KernelChoice.compat;
    }
    m[unknownKey] = KernelChoice.auto;
    return m;
  }

  // ═══════════════ 改规则 ═══════════════

  void setEnabled(bool v) {
    enabled = v;
    SpUtil.putBool(AlistConstant.kernelRuleEnabled, v);
  }

  /// 设置某个键的规则；[KernelChoice.auto] 表示删除这条规则（回到自动选路）。
  Future<void> setRule(String key, KernelChoice choice) async {
    if (choice == KernelChoice.auto) {
      _rules.remove(key);
    } else {
      _rules[key] = choice;
    }
    await save();
  }

  Future<void> removeRule(String key) => setRule(key, KernelChoice.auto);

  Future<void> resetToDefault() async {
    _applyDefaults();
    await save();
  }

  // ═══════════════ 查询 ═══════════════

  /// 这条片子该用哪个内核。
  ///
  /// 关闭状态下恒返回 [KernelChoice.auto]（保持原有自动选路行为）。
  KernelChoice resolve(String fileName, {String? url}) {
    if (!enabled) return KernelChoice.auto;
    final probe = probeVideoFormat(fileName, url: url);
    final key = probe.ok ? probe.ext! : unknownKey;
    return _rules[key] ?? KernelChoice.auto;
  }

  /// 这条片子按规则解析出的键（扩展名或 [unknownKey]），供 UI 显示「识别为什么」。
  String keyOf(String fileName, {String? url}) {
    final probe = probeVideoFormat(fileName, url: url);
    return probe.ok ? probe.ext! : unknownKey;
  }
}

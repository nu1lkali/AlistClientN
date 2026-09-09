import 'dart:convert';

import 'package:alist/entity/emby_config.dart';
import 'package:flustars/flustars.dart';
import 'package:get/get.dart';

/// Emby 随机播放配置管理器。
///
/// 使用 SharedPreferences（SpUtil 封装）做本地持久化：
/// - 服务器列表（多服务器，含备注/protocol/baseUrl/apiKey/缓存 userId）
/// - 媒体库列表（多媒体库，含备注/parentId）
/// - 当前选中的服务器 id 与媒体库 id
/// - 每次随机抽取数量 limit
///
/// 所有读写均为同步内存操作 + 异步落盘（SpUtil 内部处理），
/// 切换服务器后无需重启 App，下一次随机播放请求即生效。
class EmbyConfigManager {
  EmbyConfigManager._();

  static const String _keyServers = 'emby_server_list_v1';
  static const String _keyLibraries = 'emby_library_list_v1';
  static const String _keySelectedServerId = 'emby_selected_server_id_v1';
  static const String _keySelectedLibraryId = 'emby_selected_library_id_v1';
  static const String _keyRandomLimit = 'emby_random_limit_v1';

  /// 配置发生变更时的通知信号（值自增），供打开的列表页刷新 UI。
  static final RxInt revision = 0.obs;

  static void _notify() => revision.value++;

  // ───────────────────── 服务器 ─────────────────────

  static List<EmbyServerConfig> loadServers() {
    final raw = SpUtil.getString(_keyServers, defValue: '');
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => EmbyServerConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static void saveServers(List<EmbyServerConfig> servers) {
    SpUtil.putString(
        _keyServers, jsonEncode(servers.map((e) => e.toJson()).toList()));
    _notify();
  }

  /// 新增或覆盖服务器；新增时若当前无选中则自动选中。
  static void upsertServer(EmbyServerConfig server) {
    final servers = loadServers();
    final idx = servers.indexWhere((e) => e.id == server.id);
    if (idx >= 0) {
      servers[idx] = server;
    } else {
      servers.add(server);
    }
    saveServers(servers);
    final selectedId = selectedServerId;
    if (selectedId == null || selectedId.isEmpty) {
      _selectServerId(servers.last.id);
    }
  }

  /// 删除服务器；若删除的是当前选中项，则自动选中剩余第一个。
  static void deleteServer(String id) {
    final servers = loadServers()..removeWhere((e) => e.id == id);
    saveServers(servers);
    if (selectedServerId == id) {
      if (servers.isNotEmpty) {
        _selectServerId(servers.first.id);
      } else {
        SpUtil.remove(_keySelectedServerId);
        _notify();
      }
    }
  }

  /// 当前选中服务器的本地 id（可能指向已不存在的项，使用前请取 [selectedServer]）
  static String? get selectedServerId =>
      SpUtil.getString(_keySelectedServerId, defValue: '');

  static void selectServer(String id) {
    if (loadServers().any((e) => e.id == id)) _selectServerId(id);
  }

  static void _selectServerId(String id) {
    SpUtil.putString(_keySelectedServerId, id);
    _notify();
  }

  /// 当前生效的主服务器；无配置或选中失效时回退到第一个。
  static EmbyServerConfig? get selectedServer {
    final servers = loadServers();
    if (servers.isEmpty) return null;
    final id = selectedServerId;
    if (id != null && id.isNotEmpty) {
      final match = servers.where((e) => e.id == id);
      if (match.isNotEmpty) return match.first;
    }
    return servers.first;
  }

  /// 更新服务器上缓存的 userId（随机抽取成功后回写，避免重复请求 /Users）。
  static void updateServerUserId(String serverId, String userId) {
    final servers = loadServers();
    final idx = servers.indexWhere((e) => e.id == serverId);
    if (idx < 0 || userId.isEmpty) return;
    if (servers[idx].userId == userId) return;
    servers[idx] = servers[idx].copyWith(userId: userId);
    saveServers(servers);
  }

  /// 清除缓存的 userId（服务器编辑后调用，确保下次重新获取）。
  static void clearServerUserId(String serverId) {
    final servers = loadServers();
    final idx = servers.indexWhere((e) => e.id == serverId);
    if (idx < 0 || servers[idx].userId == null) return;
    servers[idx] = servers[idx].copyWith(clearUserId: true);
    saveServers(servers);
  }

  // ───────────────────── 媒体库 ─────────────────────

  static List<EmbyLibraryConfig> loadLibraries() {
    final raw = SpUtil.getString(_keyLibraries, defValue: '');
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => EmbyLibraryConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static void saveLibraries(List<EmbyLibraryConfig> libraries) {
    SpUtil.putString(
        _keyLibraries, jsonEncode(libraries.map((e) => e.toJson()).toList()));
    _notify();
  }

  /// 新增或覆盖媒体库；新增时若当前无选中则自动选中。
  static void upsertLibrary(EmbyLibraryConfig library) {
    final libraries = loadLibraries();
    final idx = libraries.indexWhere((e) => e.id == library.id);
    if (idx >= 0) {
      libraries[idx] = library;
    } else {
      libraries.add(library);
    }
    saveLibraries(libraries);
    final selectedId = selectedLibraryId;
    if (selectedId == null || selectedId.isEmpty) {
      _selectLibraryId(libraries.last.id);
    }
  }

  static void deleteLibrary(String id) {
    final libraries = loadLibraries()..removeWhere((e) => e.id == id);
    saveLibraries(libraries);
    if (selectedLibraryId == id) {
      if (libraries.isNotEmpty) {
        _selectLibraryId(libraries.first.id);
      } else {
        SpUtil.remove(_keySelectedLibraryId);
        _notify();
      }
    }
  }

  static String? get selectedLibraryId =>
      SpUtil.getString(_keySelectedLibraryId, defValue: '');

  static void selectLibrary(String id) {
    if (loadLibraries().any((e) => e.id == id)) _selectLibraryId(id);
  }

  static void _selectLibraryId(String id) {
    SpUtil.putString(_keySelectedLibraryId, id);
    _notify();
  }

  /// 当前参与随机播放的媒体库；无配置或选中失效时回退到第一个。
  static EmbyLibraryConfig? get selectedLibrary {
    final libraries = loadLibraries();
    if (libraries.isEmpty) return null;
    final id = selectedLibraryId;
    if (id != null && id.isNotEmpty) {
      final match = libraries.where((e) => e.id == id);
      if (match.isNotEmpty) return match.first;
    }
    return libraries.first;
  }

  // ───────────────────── 随机数量 ─────────────────────

  static int get randomLimit {
    final v = SpUtil.getInt(_keyRandomLimit, defValue: EmbyRandomSettings.defaultLimit);
    final limit = v ?? EmbyRandomSettings.defaultLimit;
    return limit.clamp(EmbyRandomSettings.minLimit, EmbyRandomSettings.maxLimit);
  }

  static void setRandomLimit(int limit) {
    final v = limit.clamp(EmbyRandomSettings.minLimit, EmbyRandomSettings.maxLimit);
    SpUtil.putInt(_keyRandomLimit, v);
    _notify();
  }

  /// 生成一个本地唯一 id（不引入额外依赖）。
  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().millisecond}';

  /// 归一化 baseUrl：去除可能的协议前缀与首尾空格/斜杠。
  static String normalizeBaseUrl(String input) {
    var s = (input ?? '').trim();
    s = s.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }
}

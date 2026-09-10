import 'dart:convert';

import 'package:alist/entity/emby_config.dart';
import 'package:flustars/flustars.dart';
import 'package:get/get.dart';

/// Emby 随机播放配置管理器。
///
/// 使用 SharedPreferences（SpUtil 封装）做本地持久化：
/// - 服务器列表（多服务器，含备注/protocol/baseUrl/apiKey/缓存 userId）
/// - 媒体库列表（**每条媒体库归属于某个服务器** serverId，含备注/parentId）
/// - 当前选中的服务器 id 与媒体库 id
/// - 每次随机抽取数量 limit
///
/// 服务器与媒体库联动：切换主服务器时，媒体库列表/选中目标随之切换；
/// 删除服务器时会一并删除归属它的媒体库。
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
      _ensureLibrarySelectionForServer(servers.last.id);
    }
  }

  /// 删除服务器：一并删除归属它的媒体库；若删的是当前选中项则切换到剩余第一个。
  static void deleteServer(String id) {
    // 1) 删除归属该服务器的媒体库
    final libs = _loadLibrariesRaw();
    final kept = libs.where((e) => e.serverId != id).toList();
    if (kept.length != libs.length) {
      SpUtil.putString(
          _keyLibraries, jsonEncode(kept.map((e) => e.toJson()).toList()));
    }

    // 2) 删除服务器本体
    final servers = loadServers()..removeWhere((e) => e.id == id);
    saveServers(servers);

    // 3) 修正选中项
    if (selectedServerId == id) {
      if (servers.isNotEmpty) {
        _selectServerId(servers.first.id);
      } else {
        SpUtil.remove(_keySelectedServerId);
        _notify();
      }
    }
    _ensureLibrarySelectionForServer(selectedServer?.id);
  }

  /// 当前选中服务器的本地 id（可能指向已不存在的项，使用前请取 [selectedServer]）
  static String? get selectedServerId =>
      SpUtil.getString(_keySelectedServerId, defValue: '');

  /// 切换主服务器：媒体库的选中目标随之切换（若原目标不属于新服务器）。
  static void selectServer(String id) {
    if (!loadServers().any((e) => e.id == id)) return;
    _selectServerId(id);
    _ensureLibrarySelectionForServer(id);
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

  /// 原始媒体库列表（不做迁移）。
  static List<EmbyLibraryConfig> _loadLibrariesRaw() {
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

  static bool _libraryMigrationDone = false;

  /// 历史数据迁移：早期版本媒体库没有 serverId，统一归属到当前主服务器
  /// （只有一个服务器时即为它），避免升级后媒体库"消失"。
  static void _ensureLibraryServerIds() {
    if (_libraryMigrationDone) return;
    _libraryMigrationDone = true;
    final libs = _loadLibrariesRaw();
    if (libs.isEmpty) return;
    if (libs.every((e) => e.serverId.isNotEmpty)) return;

    final target = selectedServer?.id ??
        (loadServers().isNotEmpty ? loadServers().first.id : '');
    if (target.isEmpty) return;

    final migrated = libs
        .map((e) => e.serverId.isEmpty ? e.copyWith(serverId: target) : e)
        .toList();
    SpUtil.putString(
        _keyLibraries, jsonEncode(migrated.map((e) => e.toJson()).toList()));
  }

  /// 全部媒体库（含各服务器）。
  static List<EmbyLibraryConfig> loadLibraries() {
    _ensureLibraryServerIds();
    return _loadLibrariesRaw();
  }

  /// 指定服务器下的媒体库（[serverId] 为空时返回全部，兼容无归属的历史数据）。
  static List<EmbyLibraryConfig> librariesOf(String? serverId) {
    final all = loadLibraries();
    if (serverId == null || serverId.isEmpty) return all;
    return all
        .where((e) => e.serverId == serverId || e.serverId.isEmpty)
        .toList();
  }

  static void saveLibraries(List<EmbyLibraryConfig> libraries) {
    SpUtil.putString(
        _keyLibraries, jsonEncode(libraries.map((e) => e.toJson()).toList()));
    _notify();
  }

  /// 新增或覆盖媒体库；新增时若当前无选中则自动选中。
  ///
  /// [library] 的 serverId 为空时会归属当前主服务器。
  static void upsertLibrary(EmbyLibraryConfig library) {
    var lib = library;
    if (lib.serverId.isEmpty) {
      final sid = selectedServer?.id;
      if (sid != null && sid.isNotEmpty) lib = lib.copyWith(serverId: sid);
    }
    final libraries = loadLibraries();
    final idx = libraries.indexWhere((e) => e.id == lib.id);
    if (idx >= 0) {
      libraries[idx] = lib;
    } else {
      libraries.add(lib);
    }
    saveLibraries(libraries);
    final selectedId = selectedLibraryId;
    if (selectedId == null || selectedId.isEmpty) {
      _selectLibraryId(lib.id);
    }
  }

  static void deleteLibrary(String id) {
    final libraries = loadLibraries()..removeWhere((e) => e.id == id);
    saveLibraries(libraries);
    if (selectedLibraryId == id) {
      final remaining = librariesOf(selectedServer?.id);
      if (remaining.isNotEmpty) {
        _selectLibraryId(remaining.first.id);
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

  /// 保证"当前服务器"下有一个选中的媒体库：若当前选中项不属于该服务器，
  /// 则自动切到该服务器的第一个媒体库；该服务器没有媒体库时清空选中。
  static void _ensureLibrarySelectionForServer(String? serverId) {
    final libs = librariesOf(serverId);
    final current = selectedLibraryId;
    if (libs.isEmpty) {
      if (current != null && current.isNotEmpty) {
        SpUtil.remove(_keySelectedLibraryId);
        _notify();
      }
      return;
    }
    if (current == null || current.isEmpty ||
        !libs.any((e) => e.id == current)) {
      _selectLibraryId(libs.first.id);
    }
  }

  /// 当前参与随机播放的媒体库（限定在当前主服务器范围内；
  /// 无配置或选中失效时回退为该服务器的第一个）。
  static EmbyLibraryConfig? get selectedLibrary {
    final libs = librariesOf(selectedServer?.id);
    if (libs.isEmpty) return null;
    final id = selectedLibraryId;
    if (id != null && id.isNotEmpty) {
      final match = libs.where((e) => e.id == id);
      if (match.isNotEmpty) return match.first;
    }
    return libs.first;
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
    var s = input.trim();
    s = s.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }
}

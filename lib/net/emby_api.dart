import 'dart:async';
import 'dart:convert';

import 'package:alist/entity/emby_config.dart';
import 'package:alist/entity/tiktok_play_list_model.dart';
import 'package:alist/util/emby_config_manager.dart';
import 'package:dio/dio.dart';

/// Emby 请求异常，message 为面向用户的中文描述。
class EmbyApiException implements Exception {
  final String message;
  EmbyApiException(this.message);

  @override
  String toString() => message;
}

/// “不喜欢列表”中标记 Emby 来源记录时使用的占位值。
///
/// 复用 disliked_video 表的既有列（不新增列、无需数据库迁移）：
/// - provider = [provider] 标记为 Emby 来源；
/// - server_url 存 Emby 服务器配置 id；
/// - user_id = [userId] 占位（与 AList 用户名区分）；
/// - remote_path 存 Emby 媒体项 Id。
class EmbyDislikeMark {
  EmbyDislikeMark._();

  static const String provider = 'Emby';
  static const String userId = 'emby';
}

/// Emby 媒体库条目（来自 GET /Users/{userId}/Views）。
class EmbyMediaLibrary {
  final String id;
  final String name;

  /// 库类型：movies / tvshows / music / mixed / homevideos / books ...
  final String? collectionType;

  const EmbyMediaLibrary({
    required this.id,
    required this.name,
    this.collectionType,
  });

  static EmbyMediaLibrary fromJson(Map<String, dynamic> json) {
    return EmbyMediaLibrary(
      id: json['Id']?.toString() ?? '',
      name: json['Name']?.toString() ?? '',
      collectionType: json['CollectionType']?.toString(),
    );
  }
}

/// Emby API 网络层
///
/// 特点：
/// - 每次请求前实时读取传入的服务器配置（protocol/baseUrl/apiKey），
///   请求头注入 X-Emby-Token，切换服务器后无需重启 App；
/// - 服务器未缓存 userId 时先 GET /Users 取返回列表第一个 Id；
/// - GET /Users/{userId}/Items 携带选中媒体库 parentId 随机抽取；
/// - GET /Users/{userId}/Views 拉取全部媒体库（供设置页选择，无需手工查 Id）；
/// - GET /Users/{userId}/Items/{itemId} 按媒体库 Id 反查名称；
/// - GET /Users/{userId}/Items?Filters=IsFavorite 一次拉取全部收藏 Id（O(1) 状态查询）；
/// - POST / DELETE /Users/{userId}/FavoriteItems/{itemId} 收藏 / 取消收藏；
/// - DELETE /Items/{itemId} 删除媒体（媒体库 + 物理文件，需管理员权限）；
/// - 为每个 Item 拼接 {protocol}://{baseUrl}/Videos/{id}/stream 播放直链。
class EmbyApi {
  EmbyApi._();

  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _receiveTimeout = Duration(seconds: 20);

  /// 收藏 Id 查询的分页大小
  static const int _favoritePageSize = 500;

  static Dio _newDio() => Dio(BaseOptions(
        connectTimeout: _connectTimeout,
        receiveTimeout: _receiveTimeout,
        responseType: ResponseType.json,
      ));

  static Options _authOptions(String apiKey) =>
      Options(headers: {'X-Emby-Token': apiKey});

  /// 服务器连通性测试：向 Emby 发起 GET /Users。
  ///
  /// 成功返回人类可读的成功信息（如 “连接成功，共 3 个用户”），失败抛出 [EmbyApiException]。
  static Future<String> testConnection(EmbyServerConfig server) async {
    final origin = server.serverOrigin;
    final url = '$origin/Users';
    try {
      final resp = await _newDio().get<dynamic>(
        url,
        options: _authOptions(server.apiKey),
      );
      final data = resp.data;
      final users = (data is List) ? data : <dynamic>[];
      if (resp.statusCode == 200) {
        if (users.isEmpty) {
          return '连接成功（$origin），但服务器未返回任何用户';
        }
        final first = users.first;
        final name = (first is Map && first['Name'] != null)
            ? first['Name'].toString()
            : '未知';
        return '连接成功（$origin），共 ${users.length} 个用户，'
            '将使用「$name」(Id: ${(first is Map && first['Id'] != null) ? first['Id'] : '?'})';
      }
      throw EmbyApiException('请求失败：HTTP ${resp.statusCode}');
    } on DioException catch (e) {
      throw EmbyApiException(_describeDioError(e, url, isUsersPath: true));
    }
  }

  /// 使用指定服务器与媒体库执行一次随机抽取
  ///
  /// 内部自动处理 userId 的动态获取与回写缓存；返回可直接喂给
  /// “视界流”播放器的 [TikTokVideoItem] 列表。失败抛出 [EmbyApiException]。
  static Future<List<TikTokVideoItem>> fetchRandomVideos({
    required EmbyServerConfig server,
    required EmbyLibraryConfig library,
    int? limit,
  }) async {
    final count = _clampLimit(limit);
    final origin = server.serverOrigin;
    final dio = _newDio();

    // 第一步：获取 userId（有缓存直接使用；无缓存则 GET /Users 取第一个 Id）
    final userId = await _ensureUserId(dio, server);

    // 第二步：随机拉取媒体库视频
    final items = await _fetchItems(
      dio,
      server: server,
      userId: userId,
      queryParameters: {
        'ParentId': library.parentId,
        'SortBy': 'Random',
        'Recursive': 'true',
        'IncludeItemTypes': 'Video,Movie',
        'Fields': 'Path,Overview,MediaSources',
        'Limit': count,
      },
    );
    if (items.isEmpty) {
      throw EmbyApiException(
          '媒体库「${library.remark.isNotEmpty ? library.remark : library.parentId}」'
          '未抽取到任何视频，请确认媒体库 Id 与服务器内容');
    }

    // 第三步：拼接播放直链并构造播放器数据
    return items
        .map((item) => _toVideoItem(item, origin, server.apiKey))
        .toList();
  }

  /// 收藏视频随机列表（首页“随机播放收藏”）。
  ///
  /// GET /Users/{userId}/Items?Filters=IsFavorite&SortBy=Random&Recursive=true
  ///   &IncludeItemTypes=Video,Movie&Limit={limit}
  /// 失败抛出 [EmbyApiException]（调用方据此提示）。
  static Future<List<TikTokVideoItem>> fetchFavoriteVideos({
    required EmbyServerConfig server,
    int? limit,
  }) async {
    final count = _clampLimit(limit);
    final origin = server.serverOrigin;
    final dio = _newDio();
    final userId = await _ensureUserId(dio, server);

    final items = await _fetchItems(
      dio,
      server: server,
      userId: userId,
      queryParameters: {
        'Filters': 'IsFavorite',
        'SortBy': 'Random',
        'Recursive': 'true',
        'IncludeItemTypes': 'Video,Movie',
        'Fields': 'Path,Overview,MediaSources',
        'Limit': count,
      },
    );
    return items
        .map((item) => _toVideoItem(item, origin, server.apiKey))
        .toList();
  }

  /// 一次性拉取当前用户的全部收藏媒体 Id（GET /Users/{userId}/Items?Filters=IsFavorite）。
  ///
  /// 供“视界流”进入时构建 HashSet 做 **O(1)** 收藏状态查询，
  /// 避免为队列中每个视频单独请求（打爆服务器）。内部自动分页。
  /// 失败抛出 [EmbyApiException]。
  static Future<Set<String>> fetchFavoriteIds(EmbyServerConfig server) async {
    final dio = _newDio();
    final userId = await _ensureUserId(dio, server);
    final url = '${server.serverOrigin}/Users/$userId/Items';
    final ids = <String>{};
    var startIndex = 0;

    while (true) {
      final Map<String, dynamic> data;
      try {
        final resp = await dio.get<dynamic>(
          url,
          queryParameters: {
            'Filters': 'IsFavorite',
            'Recursive': 'true',
            'IncludeItemTypes': 'Video,Movie',
            'Fields': 'Id',
            'StartIndex': startIndex,
            'Limit': _favoritePageSize,
            'SortBy': 'SortName',
          },
          options: _authOptions(server.apiKey),
        );
        data = (resp.data is Map)
            ? Map<String, dynamic>.from(resp.data as Map)
            : <String, dynamic>{};
      } on DioException catch (e) {
        throw EmbyApiException(_describeDioError(e, url, isUsersPath: false));
      }

      final rawItems = data['Items'];
      final items =
          (rawItems is List) ? rawItems.whereType<Map>().toList() : <Map>[];
      for (final item in items) {
        final id = item['Id']?.toString() ?? '';
        if (id.isNotEmpty) ids.add(id);
      }

      final total = (data['TotalRecordCount'] is int)
          ? data['TotalRecordCount'] as int
          : ids.length;
      startIndex += items.length;
      if (items.isEmpty ||
          items.length < _favoritePageSize ||
          startIndex >= total) {
        break;
      }
    }
    return ids;
  }

  /// 收藏 / 取消收藏（POST 或 DELETE /Users/{userId}/FavoriteItems/{itemId}）。
  ///
  /// 返回服务端确认后的 `IsFavorite`（响应体为 UserData，或包裹在 UserData 字段中）；
  /// 服务端未回显状态时按请求意图返回。失败抛出 [EmbyApiException]。
  static Future<bool> setFavorite(
    EmbyServerConfig server,
    String itemId, {
    required bool favorite,
  }) async {
    final dio = _newDio();
    final userId = await _ensureUserId(dio, server);
    final encodedId = Uri.encodeComponent(itemId);
    final url = '${server.serverOrigin}/Users/$userId/FavoriteItems/$encodedId';
    try {
      final resp = favorite
          ? await dio.post<dynamic>(url, options: _authOptions(server.apiKey))
          : await dio.delete<dynamic>(url, options: _authOptions(server.apiKey));
      final data = resp.data;
      if (data is Map) {
        if (data['IsFavorite'] is bool) {
          return data['IsFavorite'] as bool;
        }
        final userData = data['UserData'];
        if (userData is Map && userData['IsFavorite'] is bool) {
          return userData['IsFavorite'] as bool;
        }
      }
      return favorite; // 服务端未回显状态时按请求意图
    } on DioException catch (e) {
      throw EmbyApiException(_describeDioError(e, url, isUsersPath: false));
    }
  }

  /// 批量删除媒体项：`DELETE /Items?Ids={id1,id2,...}`（官方 deleteItems 接口）。
  ///
  /// 从媒体库移除并删除服务器磁盘文件；需要**管理员权限**的 API Key，
  /// 否则服务端返回 403。失败抛出 [EmbyApiException]（消息面向用户）。
  static Future<void> deleteItems(
      EmbyServerConfig server, List<String> itemIds) async {
    if (itemIds.isEmpty) return;
    final dio = _newDio();
    final url = '${server.serverOrigin}/Items';
    try {
      final resp = await dio.delete<dynamic>(
        url,
        queryParameters: {'Ids': itemIds.join(',')},
        options: _authOptions(server.apiKey),
      );
      final code = resp.statusCode ?? 200;
      if (code >= 400) {
        throw EmbyApiException('删除失败：HTTP $code');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // 兼容：部分版本不支持批量接口，单条时回退 DELETE /Items/{Id}
        if (itemIds.length == 1) {
          await _deleteItemByPath(server, itemIds.first);
          return;
        }
        throw EmbyApiException(
            '删除失败（404）：未找到删除接口或媒体项，请确认服务器版本与媒体 Id');
      }
      throw EmbyApiException(_describeDeleteError(e, url));
    }
  }

  /// 删除单个媒体项（[deleteItems] 的单条包装）。
  static Future<void> deleteItem(EmbyServerConfig server, String itemId) =>
      deleteItems(server, [itemId]);

  /// 单条删除的兼容路径：`DELETE /Items/{itemId}`。
  static Future<void> _deleteItemByPath(
      EmbyServerConfig server, String itemId) async {
    final dio = _newDio();
    final encodedId = Uri.encodeComponent(itemId);
    final url = '${server.serverOrigin}/Items/$encodedId';
    try {
      final resp =
          await dio.delete<dynamic>(url, options: _authOptions(server.apiKey));
      final code = resp.statusCode ?? 204;
      if (code >= 400) {
        throw EmbyApiException('删除失败：HTTP $code');
      }
    } on DioException catch (e) {
      throw EmbyApiException(_describeDeleteError(e, url));
    }
  }

  /// 删除接口的错误描述（403 权限 / 401 鉴权优先提示）。
  static String _describeDeleteError(DioException e, String url) {
    final code = e.response?.statusCode;
    if (code == 403) {
      return '权限不足（403）：删除媒体需要管理员权限的 API Key，请在 Emby 后台检查该密钥权限';
    }
    if (code == 401) {
      return '鉴权失败（401）：API Key 无效，请在服务器配置中检查密钥';
    }
    return _describeDioError(e, url, isUsersPath: false);
  }

  /// 公开的播放直链拼接（供“不喜欢列表”等处以 Emby 条目直接播放）。
  static String buildStreamUrl(EmbyServerConfig server, String itemId) =>
      _buildStreamUrl(server.serverOrigin, itemId, server.apiKey);

  /// 拉取当前用户可见的全部媒体库（GET /Users/{userId}/Views）。
  ///
  /// 返回所有媒体库的 Id / Name / CollectionType，供设置页渲染列表让用户直接勾选。
  /// 失败抛出 [EmbyApiException]。
  static Future<List<EmbyMediaLibrary>> fetchMediaLibraries(
      EmbyServerConfig server) async {
    final dio = _newDio();
    final origin = server.serverOrigin;
    final userId = await _ensureUserId(dio, server);
    final url = '$origin/Users/$userId/Views';
    try {
      final resp = await dio.get<dynamic>(
        url,
        options: _authOptions(server.apiKey),
      );
      final data = resp.data;
      if (data is Map && data['Items'] is List) {
        return (data['Items'] as List)
            .whereType<Map<String, dynamic>>()
            .map((e) => EmbyMediaLibrary.fromJson(e))
            .where((e) => e.id.isNotEmpty && e.name.isNotEmpty)
            .toList();
      }
      throw EmbyApiException('服务器返回的数据格式异常（缺少 Items 字段）');
    } on DioException catch (e) {
      throw EmbyApiException(_describeDioError(e, url, isUsersPath: false));
    }
  }

  /// 按媒体库 Id（parentId）反查媒体库名称（GET /Users/{userId}/Items/{itemId}）。
  ///
  /// 用于手动填写 ParentId 后自动补全备注名。失败时抛出 [EmbyApiException]。
  static Future<String> fetchMediaLibraryName(
      EmbyServerConfig server, String parentId) async {
    final dio = _newDio();
    final origin = server.serverOrigin;
    final userId = await _ensureUserId(dio, server);
    final encodedId = Uri.encodeComponent(parentId);
    final url = '$origin/Users/$userId/Items/$encodedId';
    try {
      final resp = await dio.get<dynamic>(
        url,
        options: _authOptions(server.apiKey),
      );
      final data = resp.data;
      if (data is Map && data['Name'] != null) {
        return data['Name'].toString();
      }
      throw EmbyApiException('未找到该媒体库，请检查 ParentId 是否正确');
    } on DioException catch (e) {
      throw EmbyApiException(_describeDioError(e, url, isUsersPath: false));
    }
  }

  // ───────────────────── 内部工具 ─────────────────────

  static int _clampLimit(int? limit) =>
      (limit ?? EmbyConfigManager.randomLimit)
          .clamp(EmbyRandomSettings.minLimit, EmbyRandomSettings.maxLimit);

  /// 统一的 Items 查询（返回 Items 数组）。
  static Future<List<Map>> _fetchItems(
    Dio dio, {
    required EmbyServerConfig server,
    required String userId,
    required Map<String, dynamic> queryParameters,
  }) async {
    final url = '${server.serverOrigin}/Users/$userId/Items';
    try {
      final resp = await dio.get<dynamic>(
        url,
        queryParameters: queryParameters,
        options: _authOptions(server.apiKey),
      );
      final data = resp.data;
      if (data is Map && data['Items'] is List) {
        return (data['Items'] as List).whereType<Map>().toList();
      }
      throw EmbyApiException('服务器返回的数据格式异常（缺少 Items 字段）');
    } on DioException catch (e) {
      throw EmbyApiException(_describeDioError(e, url, isUsersPath: false));
    }
  }

  /// Emby Item → 播放器数据（直链 + 封面 + Emby itemId，供收藏接口使用）。
  static TikTokVideoItem _toVideoItem(
      Map item, String origin, String apiKey) {
    final itemId = item['Id']?.toString() ?? '';
    final name = item['Name']?.toString() ?? '未命名视频';
    final streamUrl = _buildStreamUrl(origin, itemId, apiKey);
    return TikTokVideoItem(
      id: streamUrl,
      fileName: name,
      videoUrl: streamUrl,
      filePath: name,
      thumb: _buildPrimaryImageUrl(origin, itemId, apiKey),
      embyItemId: itemId.isEmpty ? null : itemId,
      provider: null,
      modifiedMilliseconds: null,
    );
  }

  /// 确保拿到 userId：有缓存直接返回；无缓存则 GET /Users 取列表第一个 Id 并回写缓存。
  static Future<String> _ensureUserId(
      Dio dio, EmbyServerConfig server) async {
    var userId = server.userId;
    if (userId == null || userId.isEmpty) {
      userId =
          await _fetchFirstUserId(dio, server.serverOrigin, server.apiKey);
      EmbyConfigManager.updateServerUserId(server.id, userId);
    }
    return userId;
  }

  /// GET /Users 取返回列表第一个 Id。
  static Future<String> _fetchFirstUserId(
      Dio dio, String origin, String apiKey) async {
    final url = '$origin/Users';
    try {
      final resp = await dio.get<dynamic>(
        url,
        options: _authOptions(apiKey),
      );
      final data = resp.data;
      final users = (data is List) ? data : <dynamic>[];
      if (users.isEmpty) {
        throw EmbyApiException('服务器（$origin）未返回任何用户，无法获取 userId');
      }
      final first = users.first;
      if (first is Map && first['Id'] != null) {
        return first['Id'].toString();
      }
      throw EmbyApiException('服务器（$origin）返回的用户数据缺少 Id 字段');
    } on DioException catch (e) {
      throw EmbyApiException(_describeDioError(e, url, isUsersPath: true));
    }
  }

  /// 拼接 {protocol}://{baseUrl}/Videos/{itemId}/stream?static=true&api_key=xxx
  static String _buildStreamUrl(String origin, String itemId, String apiKey) {
    final id = Uri.encodeComponent(itemId);
    return '$origin/Videos/$id/stream?static=true&api_key=$apiKey';
  }

  /// 拼接视频封面（Emby Primary Image，播放器缩略图，可能不存在）。
  static String? _buildPrimaryImageUrl(
      String origin, String itemId, String apiKey) {
    if (itemId.isEmpty) return null;
    final id = Uri.encodeComponent(itemId);
    return '$origin/Items/$id/Images/Primary?api_key=$apiKey';
  }

  static String _describeDioError(DioException e, String url,
      {required bool isUsersPath}) {
    final type = e.type;
    switch (type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
        return '连接服务器超时，请检查地址与网络（$url）';
      case DioExceptionType.receiveTimeout:
        return '服务器响应超时，请稍后重试（$url）';
      case DioExceptionType.connectionError:
        return '无法连接服务器（$url），请检查地址、端口与网络';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 401) {
          return '鉴权失败（401）：API Key 无效或无权限，请在服务器配置中检查密钥';
        }
        if (code == 403) {
          return '权限不足（403）：该操作需要管理员权限的 API Key';
        }
        if (code == 404) {
          return isUsersPath
              ? '地址不存在（404）：该地址可能不是有效的 Emby 服务器'
              : '请求资源不存在（404）：请检查 Id 是否正确';
        }
        String? body;
        try {
          final d = e.response?.data;
          if (d != null) {
            body = d is String
                ? d
                : jsonEncode(d is Map ? d : {'data': d});
            final msg = body;
            if (msg.length > 120) body = '${msg.substring(0, 120)}...';
          }
        } catch (_) {}
        return '服务器返回错误（HTTP $code）${body != null ? '：$body' : ''}';
      case DioExceptionType.cancel:
        return '请求已取消';
      case DioExceptionType.badCertificate:
        return '服务器证书校验失败（请检查 https 证书）';
      case DioExceptionType.unknown:
        final cause = e.error;
        if (cause != null) {
          return '请求异常：$cause';
        }
        return '请求失败，请稍后重试';
    }
  }
}

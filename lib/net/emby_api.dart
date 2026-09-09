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

/// Emby API 网络层（对标 cs.py）。
///
/// 特点：
/// - 每次请求前实时读取传入的服务器配置（protocol/baseUrl/apiKey），
///   请求头注入 X-Emby-Token，切换服务器后无需重启 App；
/// - 服务器未缓存 userId 时先 GET /Users 取返回列表第一个 Id；
/// - GET /Users/{userId}/Items 携带选中媒体库 parentId 随机抽取；
/// - GET /Users/{userId}/Views 拉取全部媒体库（供设置页选择，无需手工查 Id）；
/// - GET /Users/{userId}/Items/{itemId} 按媒体库 Id 反查名称；
/// - 为每个 Item 拼接 {protocol}://{baseUrl}/Videos/{id}/stream 播放直链。
class EmbyApi {
  EmbyApi._();

  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _receiveTimeout = Duration(seconds: 20);

  static Dio _newDio() => Dio(BaseOptions(
        connectTimeout: _connectTimeout,
        receiveTimeout: _receiveTimeout,
        responseType: ResponseType.json,
      ));

  /// 服务器连通性测试：向 Emby 发起 GET /Users。
  ///
  /// 成功返回人类可读的成功信息（如 “连接成功，共 3 个用户”），失败抛出 [EmbyApiException]。
  static Future<String> testConnection(EmbyServerConfig server) async {
    final origin = server.serverOrigin;
    final url = '$origin/Users';
    try {
      final resp = await _newDio().get<dynamic>(
        url,
        options: Options(headers: {'X-Emby-Token': server.apiKey}),
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

  /// 使用指定服务器与媒体库执行一次随机抽取（对标 cs.py 三步数据流）。
  ///
  /// 内部自动处理 userId 的动态获取与回写缓存；返回可直接喂给
  /// “视界流”播放器的 [TikTokVideoItem] 列表。失败抛出 [EmbyApiException]。
  static Future<List<TikTokVideoItem>> fetchRandomVideos({
    required EmbyServerConfig server,
    required EmbyLibraryConfig library,
    int? limit,
  }) async {
    final count =
        (limit ?? EmbyConfigManager.randomLimit).clamp(
            EmbyRandomSettings.minLimit, EmbyRandomSettings.maxLimit);
    final origin = server.serverOrigin;
    final dio = _newDio();

    // 第一步：获取 userId（有缓存直接使用；无缓存则 GET /Users 取第一个 Id）
    final userId = await _ensureUserId(dio, server);

    // 第二步：随机拉取媒体库视频
    final items = await _fetchRandomItems(
      dio,
      origin: origin,
      apiKey: server.apiKey,
      userId: userId,
      parentId: library.parentId,
      limit: count,
    );
    if (items.isEmpty) {
      throw EmbyApiException(
          '媒体库「${library.remark.isNotEmpty ? library.remark : library.parentId}」'
          '未抽取到任何视频，请确认媒体库 Id 与服务器内容');
    }

    // 第三步：拼接播放直链并构造播放器数据
    return items.map((item) {
      final itemId = item['Id']?.toString() ?? '';
      final name = item['Name']?.toString() ?? '未命名视频';
      final streamUrl = _buildStreamUrl(origin, itemId, server.apiKey);
      return TikTokVideoItem(
        id: streamUrl,
        fileName: name,
        videoUrl: streamUrl,
        filePath: name,
        thumb: _buildPrimaryImageUrl(origin, itemId, server.apiKey),
        provider: null,
        modifiedMilliseconds: null,
      );
    }).toList();
  }

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
        options: Options(headers: {'X-Emby-Token': server.apiKey}),
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
        options: Options(headers: {'X-Emby-Token': server.apiKey}),
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
        options: Options(headers: {'X-Emby-Token': apiKey}),
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

  /// GET /Users/{userId}/Items 随机抽取（带选中媒体库 ParentId）。
  static Future<List<dynamic>> _fetchRandomItems(
    Dio dio, {
    required String origin,
    required String apiKey,
    required String userId,
    required String parentId,
    required int limit,
  }) async {
    final url = '$origin/Users/$userId/Items';
    try {
      final resp = await dio.get<dynamic>(
        url,
        queryParameters: {
          'ParentId': parentId,
          'SortBy': 'Random',
          'Recursive': 'true',
          'IncludeItemTypes': 'Video,Movie',
          'Fields': 'Path,Overview,MediaSources',
          'Limit': limit,
        },
        options: Options(headers: {'X-Emby-Token': apiKey}),
      );
      final data = resp.data;
      if (data is Map && data['Items'] is List) {
        final items = data['Items'] as List;
        return items.whereType<Map>().toList();
      }
      throw EmbyApiException('服务器返回的数据格式异常（缺少 Items 字段）');
    } on DioException catch (e) {
      throw EmbyApiException(_describeDioError(e, url, isUsersPath: false));
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
        if (code == 404) {
          return isUsersPath
              ? '地址不存在（404）：该地址可能不是有效的 Emby 服务器'
              : '请求资源不存在（404）：请检查媒体库 Id 是否正确';
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

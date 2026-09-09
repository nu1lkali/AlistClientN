/// Emby 随机播放相关配置的数据模型。
///
/// 说明：
/// - [EmbyServerConfig]：一个 Emby 服务器配置项（备注、协议、地址端口、API Key）。
///   [userId] 为可选缓存字段：首次请求时通过 GET /Users 取到列表第一个 Id 后写回，
///   后续随机播放可直接使用，避免每次重复请求。
/// - [EmbyLibraryConfig]：一个媒体库配置项（备注、parentId），用于随机抽取的作用域。
library;

class EmbyServerConfig {
  /// 本地唯一标识（用于持久化定位与选中标记）
  final String id;

  /// 备注名（用户描述，如「家里 NAS」）
  final String remark;

  /// 协议：http 或 https
  final String protocol;

  /// 地址与端口，如 192.168.2.124:8097（不含协议前缀、不含末尾斜杠）
  final String baseUrl;

  /// Emby API Key（X-Emby-Token）
  final String apiKey;

  /// 缓存的 Emby 用户 Id（可为空，为空时请求前自动获取）
  final String? userId;

  const EmbyServerConfig({
    required this.id,
    required this.remark,
    this.protocol = 'http',
    required this.baseUrl,
    required this.apiKey,
    this.userId,
  });

  /// 服务器源地址，如 http://192.168.2.124:8097
  String get serverOrigin => '$protocol://$baseUrl';

  /// 是否可发起请求（地址与密钥齐全）
  bool get isValid => baseUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty;

  EmbyServerConfig copyWith({
    String? remark,
    String? protocol,
    String? baseUrl,
    String? apiKey,
    String? userId,
    bool clearUserId = false,
  }) {
    return EmbyServerConfig(
      id: id,
      remark: remark ?? this.remark,
      protocol: protocol ?? this.protocol,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      userId: clearUserId ? null : (userId ?? this.userId),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'remark': remark,
        'protocol': protocol,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        if (userId != null && userId!.isNotEmpty) 'userId': userId,
      };

  factory EmbyServerConfig.fromJson(Map<String, dynamic> json) {
    return EmbyServerConfig(
      id: json['id'] as String,
      remark: (json['remark'] as String?) ?? '',
      protocol: (json['protocol'] as String?) ?? 'http',
      baseUrl: (json['baseUrl'] as String?) ?? '',
      apiKey: (json['apiKey'] as String?) ?? '',
      userId: json['userId'] as String?,
    );
  }
}

/// Emby 媒体库（多媒体库）配置项。
class EmbyLibraryConfig {
  /// 本地唯一标识
  final String id;

  /// 备注名（如：电影库、短视频）
  final String remark;

  /// Emby 媒体库 Id（随机抽取时的 ParentId）
  final String parentId;

  const EmbyLibraryConfig({
    required this.id,
    required this.remark,
    required this.parentId,
  });

  bool get isValid => parentId.trim().isNotEmpty;

  EmbyLibraryConfig copyWith({String? remark, String? parentId}) {
    return EmbyLibraryConfig(
      id: id,
      remark: remark ?? this.remark,
      parentId: parentId ?? this.parentId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'remark': remark,
        'parentId': parentId,
      };

  factory EmbyLibraryConfig.fromJson(Map<String, dynamic> json) {
    return EmbyLibraryConfig(
      id: json['id'] as String,
      remark: (json['remark'] as String?) ?? '',
      parentId: (json['parentId'] as String?) ?? '',
    );
  }
}

/// Emby 随机播放的全局配置参数。
class EmbyRandomSettings {
  /// 默认每次随机抽取数量
  static const int defaultLimit = 10;

  /// 允许的最小值
  static const int minLimit = 1;

  /// 允许的最大值
  static const int maxLimit = 50;
}

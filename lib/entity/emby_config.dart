/// Emby 随机播放相关配置的数据模型。
///
/// 说明：
/// - [EmbyServerConfig]：一个 Emby 服务器配置项（备注、协议、地址端口、API Key）。
///   [userId] 为可选缓存字段：首次请求时通过 GET /Users 取到列表第一个 Id 后写回，
///   后续随机播放可直接使用，避免每次重复请求。
/// - [EmbyLibraryConfig]：一个媒体库配置项（备注、parentId），**归属于某个服务器**
///   （[serverId]），切换主服务器时列表与选中项随之切换。
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

/// Emby 媒体库（多媒体库）配置项，归属于某个服务器（[serverId]）。
class EmbyLibraryConfig {
  /// 本地唯一标识
  final String id;

  /// 归属的服务器配置 id（媒体库与服务器绑定）
  final String serverId;

  /// 备注名（如：电影库、短视频）
  final String remark;

  /// Emby 媒体库 Id（随机抽取时的 ParentId）
  final String parentId;

  /// 是否排除在「全部媒体库」随机抽取之外。
  ///
  /// 仅影响「全部媒体库」模式：勾选媒体库本身单独播放时不受此开关影响。
  final bool excludeFromAll;

  const EmbyLibraryConfig({
    required this.id,
    this.serverId = '',
    required this.remark,
    required this.parentId,
    this.excludeFromAll = false,
  });

  bool get isValid => parentId.trim().isNotEmpty;

  // ─────────────「全部媒体库」虚拟项 ─────────────
  //
  // 它不是一条真实存储的配置，而是「跨当前服务器全部媒体库随机抽取」的虚拟选项：
  // 选中后随机播放会对每个媒体库各抽一批，汇总去重后再均匀洗牌。
  // 详见 EmbyApi.fetchRandomVideosFromAllLibraries。

  /// 「全部媒体库」虚拟项的固定本地 id（不与任何真实媒体库 id 冲突）
  static const String allLibrariesId = '__all_libraries__';

  /// 占位 ParentId（无实际意义，仅用于通过 [isValid] 配置校验）
  static const String allLibrariesParentId = 'ALL';

  /// 列表/提示中的显示名
  static const String allLibrariesRemark = '全部媒体库';

  /// 构造归属于 [serverId] 的「全部媒体库」虚拟配置。
  factory EmbyLibraryConfig.allLibraries(String serverId) =>
      EmbyLibraryConfig(
        id: allLibrariesId,
        serverId: serverId,
        remark: allLibrariesRemark,
        parentId: allLibrariesParentId,
      );

  /// 当前配置是否为「全部媒体库」虚拟项
  bool get isAllLibraries => id == allLibrariesId;

  EmbyLibraryConfig copyWith({
    String? serverId,
    String? remark,
    String? parentId,
    bool? excludeFromAll,
  }) {
    return EmbyLibraryConfig(
      id: id,
      serverId: serverId ?? this.serverId,
      remark: remark ?? this.remark,
      parentId: parentId ?? this.parentId,
      excludeFromAll: excludeFromAll ?? this.excludeFromAll,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'serverId': serverId,
        'remark': remark,
        'parentId': parentId,
        'excludeFromAll': excludeFromAll,
      };

  factory EmbyLibraryConfig.fromJson(Map<String, dynamic> json) {
    return EmbyLibraryConfig(
      id: json['id'] as String,
      serverId: (json['serverId'] as String?) ?? '',
      remark: (json['remark'] as String?) ?? '',
      parentId: (json['parentId'] as String?) ?? '',
      // 历史数据没有该字段，默认参与
      excludeFromAll: (json['excludeFromAll'] as bool?) ?? false,
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
  static const int maxLimit = 100;
}

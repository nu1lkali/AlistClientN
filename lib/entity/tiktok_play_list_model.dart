/// TikTok 播放列表数据模型
/// 用于在文件列表页和 TikTok 播放器页之间传递数据
class TikTokPlayListModel {
  /// 播放列表（可变，支持后台动态追加）
  final List<TikTokVideoItem> videos;

  /// 初始播放位置索引
  final int initialIndex;

  /// 是否记录观看历史（单文件入口为true，收集N个视频入口为false）
  final bool recordHistory;

  /// 是否来自 Emby 随机播放（爱心=Emby 收藏接口、踩=加入本地“不喜欢列表”，
  /// 信息里展示直链 URL；不含 AList 收藏/踩逻辑）
  final bool fromEmby;

  TikTokPlayListModel({
    required this.videos,
    this.initialIndex = 0,
    this.recordHistory = false,
    this.fromEmby = false,
  });
}

/// TikTok 单个视频项
class TikTokVideoItem {
  /// 视频唯一 ID（使用远程路径作为唯一标识）
  final String id;

  /// 文件名
  final String fileName;

  /// 视频源 URL（直链，需要异步生成）
  String? videoUrl;

  /// 文件大小（字节）
  int? fileSize;

  /// 文件大小描述
  final String? sizeDesc;

  /// 文件路径（远程路径）
  final String filePath;

  /// 文件签名
  final String? sign;

  /// Provider（如 BaiduNetdisk）
  final String? provider;

  /// 缩略图
  final String? thumb;

  /// 修改时间戳（毫秒）
  final int? modifiedMilliseconds;

  /// Emby 媒体项 Id（Emby 来源时用于收藏/取消收藏接口）
  final String? embyItemId;

  /// 是否点赞（Emby 来源时表示是否已收藏）
  bool isLiked;

  /// 是否不喜欢
  bool isDisliked;

  TikTokVideoItem({
    required this.id,
    required this.fileName,
    this.videoUrl,
    this.fileSize,
    this.sizeDesc,
    required this.filePath,
    this.sign,
    this.provider,
    this.thumb,
    this.modifiedMilliseconds,
    this.embyItemId,
    this.isLiked = false,
    this.isDisliked = false,
  });

  /// 从 FileItemVO 构建
  factory TikTokVideoItem.fromFileItem({
    required String name,
    required String path,
    int? size,
    String? sizeDesc,
    String? sign,
    String? provider,
    String? thumb,
    int? modifiedMilliseconds,
  }) {
    return TikTokVideoItem(
      id: path,
      fileName: name,
      fileSize: size,
      sizeDesc: sizeDesc,
      filePath: path,
      sign: sign,
      provider: provider,
      thumb: thumb,
      modifiedMilliseconds: modifiedMilliseconds,
    );
  }

  /// 格式化文件大小
  String get formattedSize {
    if (fileSize == null || fileSize! <= 0) return '未知';
    if (fileSize! < 1024) return '${fileSize}B';
    if (fileSize! < 1024 * 1024) return '${(fileSize! / 1024).toStringAsFixed(1)}KB';
    if (fileSize! < 1024 * 1024 * 1024) {
      return '${(fileSize! / 1024 / 1024).toStringAsFixed(1)}MB';
    }
    return '${(fileSize! / 1024 / 1024 / 1024).toStringAsFixed(2)}GB';
  }

  /// 格式化修改时间
  String get formattedModified {
    if (modifiedMilliseconds == null || modifiedMilliseconds! <= 0) return '未知';
    final dt = DateTime.fromMillisecondsSinceEpoch(modifiedMilliseconds!);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

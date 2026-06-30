import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

class AlistConstant {
  /// 文件列表浮动按钮显示状态（响应式）
  static final showFabButtonRx = true.obs;
  /// 文件列表随机播放按钮显示状态（响应式）
  static final showFileListShuffleButtonRx = true.obs;
  /// App运行在Release环境时，inProduction为true；当App运行在Debug和Profile环境时，inProduction为false
  static const bool inProduction = kReleaseMode;

  static bool isDriverTest = false;
  static bool isUnitTest = false;

  static const String appName = "AList Client";
  static const String data = 'data';
  static const String message = 'message';
  static const String code = 'code';
  static const String noAuth = 'noAuth';

  static const String serverUrl = 'address';
  static const String baseUrl = 'baseUrl';
  static const String basePath = 'basePath';
  static const String username = 'username';
  static const String password = 'password';
  static const String token = 'token';
  static const String guest = 'guest';
  static const String useDemoServer = 'useDemoServer';
  static const String isAgreePrivacyPolicy = 'isAgreePrivacyPolicy';
  static const String ignoreSSLError = "ignoreSSLError";
  static const String ignoreAppVersion = "ignoreAppVersion";
  static const String isFirstTimeDownload = "isFirstTimeDownload";
  static const String isFirstTimeSaveToLocal = "isFirstTimeSaveToLocal";
  static const String maxRunningTaskCount = "maxRunningTaskCount";
  static const String fileNameMaxLines = 'fileNameMaxLines';
  static const String fileSortWayIndex = 'fileSortWayIndex';
  static const String fileSortWayUp = 'fileSortWayUp';
  static const String videoPlayerName = 'videoPlayerName';
  static const String videoPlayerRouter = 'videoPlayerRouter';
  static const String playerType = 'playerType';
  static const String lastPlaybackRate = 'lastPlaybackRate';
  static const String fileViewMode = 'fileViewMode'; // 0=list, 1=grid
  static const String themeColorValue = 'themeColorValue'; // int color value
  static const String enableAggressiveCache = 'enableAggressiveCache'; // aggressive preload cache
  static const String wifiOnlyPreload = 'wifiOnlyPreload'; // 仅WiFi预加载
  static const String slideshowIntervalSeconds = 'slideshowIntervalSeconds'; // gallery slideshow interval
  static const String audioPlayerUiStyle = 'audioPlayerUiStyle'; // 0=classic, 1=bujuan
  static const String groupedRandomSort = 'groupedRandomSort'; // 随机排序时按类型分组
  static const String enableMediaKitPlayer = 'enableMediaKitPlayer'; // 使用 libmpv 播放器
  static const String videoBrightness = 'videoBrightness'; // 视频播放亮度记忆
  static const String autoPipEnabled = 'autoPipEnabled'; // 自动进入画中画
  static const String extensionFilter = 'extensionFilter'; // 扩展名过滤
  static const String randomPlayCount = 'randomPlayCount'; // 随机播放数量
  static const String showFabButton = 'showFabButton'; // 文件列表FAB按钮显示
  static const String showTiktokPageIndicator = 'showTiktokPageIndicator'; // 视界流右侧页码指示器
  static const String showFileListShuffleButton = 'showFileListShuffleButton'; // 文件列表随机播放按钮
  static const String menuSortExpanded = 'menuSortExpanded'; // 排序方式展开
  static const String menuPlayExpanded = 'menuPlayExpanded'; // 播放选项展开
  static const String menuToolsExpanded = 'menuToolsExpanded'; // 整理工具展开
  static const String tiktokUiOpacity = 'tiktokUiOpacity'; // 视界流播放器控件透明度
  static const String strmHostOverrideEnabled = 'strmHostOverrideEnabled'; // .strm URL 主机替换开关
  static const String strmHostOverrideFrom = 'strmHostOverrideFrom'; // 原始主机地址（如 192.168.2.124:8024）
  static const String strmHostOverrideTo = 'strmHostOverrideTo'; // 替换后主机地址（如 frp.example.com:12345）
  static const String strmBrightness = 'strmBrightness'; // strm 播放器亮度记忆
  static const String strmPreloadEnabled = 'strmPreloadEnabled'; // strm 预加载下一个视频

  // 本地字幕相关
  static const String enableLocalSubtitle = 'enableLocalSubtitle'; // 本地字幕库总开关
  static const String localSubtitlePath = 'localSubtitlePath'; // 本地字幕目录绝对路径
  static const String subtitleDownloadToSubtitleDir = 'subtitleDownloadToSubtitleDir'; // 字幕下载直接存入字幕目录

  // 安全锁相关
  static const String securityLockEnabled = 'securityLockEnabled'; // 是否开启安全锁
  static const String securityLockType = 'securityLockType'; // 锁类型: 0=手势, 1=密码
  static const String securityLockPattern = 'securityLockPattern'; // 手势锁数据 (逗号分隔的数字)
  static const String securityLockPassword = 'securityLockPassword'; // 密码锁数据 (SHA256哈希)
  static const String securityLockAutoTimeout = 'securityLockAutoTimeout'; // 自动锁定超时(分钟), 0=不自动锁

  static const String locale = 'locale';
}

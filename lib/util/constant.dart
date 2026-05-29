import 'package:flutter/foundation.dart';

class AlistConstant {
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
  static const String slideshowIntervalSeconds = 'slideshowIntervalSeconds'; // gallery slideshow interval
  static const String audioPlayerUiStyle = 'audioPlayerUiStyle'; // 0=classic, 1=bujuan
  static const String groupedRandomSort = 'groupedRandomSort'; // 随机排序时按类型分组
  static const String enableMediaKitPlayer = 'enableMediaKitPlayer'; // 使用 libmpv 播放器
  static const String videoBrightness = 'videoBrightness'; // 视频播放亮度记忆
  static const String autoPipEnabled = 'autoPipEnabled'; // 自动进入画中画
  static const String extensionFilter = 'extensionFilter'; // 扩展名过滤
  static const String randomPlayCount = 'randomPlayCount'; // 随机播放数量

  static const String locale = 'locale';
}

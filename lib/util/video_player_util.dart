import 'dart:io';

import 'package:alist/entity/file_info_resp_entity.dart';
import 'package:alist/entity/player_resolve_info_entity.dart';
import 'package:alist/generated/images.dart';
import 'package:alist/l10n/intl_keys.dart';
import 'package:alist/net/dio_utils.dart';
import 'package:alist/screen/video_player_screen.dart';
import 'package:alist/util/alist_plugin.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/file_utils.dart';
import 'package:alist/util/named_router.dart';
import 'package:alist/util/proxy.dart';
import 'package:alist/util/string_utils.dart';
import 'package:alist/widget/player_selector_dialog.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

class VideoPlayerUtil {
  /// 根据视频总时长，计算"一次全屏宽横向拖动"应当跳转的时长。
  ///
  /// 让手势拖动的灵敏度随视频长度自适应，避免两类体验问题：
  /// - 短视频一拖就跳到结尾（跳跃幅度过大）；
  /// - 长视频拖一大段才前进几秒（不够灵敏）。
  ///
  /// 策略：全屏宽跳转 = clamp(总时长 × 12%, 15s, 10min)。
  /// 注意：单次手指拖动的有效位移通常只有 0.5~0.7 屏宽（起手点不在屏幕最左
  /// 边缘），故比例按"整屏宽"标定时需取偏大值，让一次实际拖动能覆盖有意义
  /// 的跨度：
  ///   - 30s 短视频：~15s/屏宽（实际一拖 ~9s，不会一拖到底）
  ///   - 35min 视频：~252s/屏宽（实际一拖 ~2.5 分钟）
  ///   - 1h 视频：~432s/屏宽（实际一拖 ~4 分钟）
  ///   - 2h+ 视频：封顶 10min/屏宽
  ///
  /// 调用方再把 `dx / screenWidth * seekRange` 换算成实际跳转毫秒数，
  /// 并对最终位置 clamp 到 [0, duration]。
  static Duration seekRangeForDuration(Duration duration) {
    const minRange = Duration(seconds: 15);
    const maxRange = Duration(minutes: 10);
    const ratio = 0.12;
    if (duration <= Duration.zero) return minRange;
    final scaled =
        Duration(milliseconds: (duration.inMilliseconds * ratio).round());
    if (scaled < minRange) return minRange;
    if (scaled > maxRange) return maxRange;
    return scaled;
  }

  static void go(List<VideoItem> videos, int index, String? password) async {
    var videoPlayerRouter =
        SpUtil.getString(AlistConstant.videoPlayerRouter) ?? "";

    if (videoPlayerRouter == "") {
      _playUrlWithInternalPlayer(videos, index);
    } else {
      var item = videos[index];
      var playResult = await _playUrlWithExternalPlayer(videoPlayerRouter,
          item.provider, item.localPath, item.remotePath, item.sign, password);
      if (!playResult) {
        SpUtil.remove(AlistConstant.videoPlayerRouter);
        SpUtil.remove(AlistConstant.videoPlayerName);
        _playUrlWithInternalPlayer(videos, index);
      }
    }
  }

  static void _playUrlWithInternalPlayer(List<VideoItem> videos, int index,
      {String? playerType}) async {
    if (Platform.isAndroid) {
      final enableMediaKit = SpUtil.getBool(AlistConstant.enableMediaKitPlayer, defValue: false) ?? false;

      if (playerType == null) {
        playerType = SpUtil.getString(AlistConstant.playerType);
      }
      final ext = videos[index].name
          .substringAfterLast(".")
          ?.toLowerCase() ?? "";

      if (enableMediaKit) {
        playerType = "media_kit";
      }
      // IJK 内核已支持 WMV/AVI/MPG/RMVB 等所有老格式，无需再按扩展名路由到 MediaKit

      var videosParams = <Map<String, String?>>[];
      Map<String, String> headers = {};

      for (var element in videos) {
        var videoParam = <String, String?>{};
        videosParams.add(videoParam);
        videoParam["name"] = element.name;
        videoParam["localPath"] = element.localPath;
        videoParam["remotePath"] = element.remotePath;
        videoParam["sign"] = element.sign;
        videoParam["provider"] = element.provider;
        videoParam["thumb"] = element.thumb;
        // 如果 remotePath 已是完整 URL（如 .strm 解析结果），直接使用；
        // 否则通过 FileUtils.makeFileLink 生成 alist 直链
        if (element.remotePath.startsWith('http://') ||
            element.remotePath.startsWith('https://')) {
          videoParam["url"] = element.remotePath;
        } else {
          videoParam["url"] =
              await FileUtils.makeFileLink(element.remotePath, element.sign);
        }
        videoParam["modifiedMilliseconds"] =
            element.modifiedMilliseconds?.toString();
        videoParam["size"] = element.size?.toString();
        if (videoParam["url"] == null || videoParam["url"] == "") {
          return;
        }

        if (element.provider == "BaiduNetdisk") {
          headers["User-Agent"] = "pan.baidu.com";
        }
      }

      if (playerType == "media_kit") {
        Get.toNamed(
          NamedRouter.mediaKitPlayer,
          arguments: {
            "videos": videosParams,
            "index": index,
            "headers": headers,
          },
        );
      } else {
        final autoPipEnabled = SpUtil.getBool(AlistConstant.autoPipEnabled, defValue: true) ?? true;
        final ffmpegSoftDecode = SpUtil.getBool(AlistConstant.enableFfmpegSoftDecode, defValue: false) ?? false;
        // 本地字幕目录：开关开启且路径非空时传给原生播放器
        final localSubEnabled = SpUtil.getBool(AlistConstant.enableLocalSubtitle, defValue: false) ?? false;
        final localSubDir = localSubEnabled ? (SpUtil.getString(AlistConstant.localSubtitlePath) ?? '') : '';
        AlistPlugin.playVideoWithInternalPlayer(
            videosParams, index, headers, playerType,
            autoPipEnabled: autoPipEnabled,
            subtitleDir: localSubDir.isNotEmpty ? localSubDir : null,
            ffmpegSoftDecode: ffmpegSoftDecode);
      }
    } else {
      Get.toNamed(
        NamedRouter.videoPlayer,
        arguments: {
          "videos": videos,
          "index": index,
        },
      );
    }
  }

  static Future<bool> _playUrlWithExternalPlayer(
      String videoPlayerRouter,
      String? provider,
      String? localPath,
      String remotePath,
      String? sign,
      String? password) async {
    if (localPath != null && localPath != "") {
      var packageName = videoPlayerRouter.substringBeforeLast("/")!;
      if (Platform.isAndroid) {
        var activity = videoPlayerRouter.substringAfterLast("/")!;
        return AlistPlugin.playVideoWithExternalPlayer(
            packageName, activity, localPath);
      } else {
        ProxyServer proxyServer = Get.find();
        await proxyServer.start();
        var videoUrl = proxyServer.makeFileUri(File(localPath)).toString();
        debugPrint("videoUrl=$videoUrl");
        var uri = Uri.parse("$packageName$videoUrl");
        return launchUrl(uri);
      }
    } else {
      var videoUrl = await FileUtils.makeFileLink(remotePath, sign);
      if (videoUrl == null) {
        return true;
      }

      LogUtil.d("provider=$provider");
      if (provider == "BaiduNetdisk") {
        ProxyServer proxyServer = Get.find();
        await proxyServer.start();
        var uri = proxyServer.makeProxyUrl(videoUrl,
            headers: {HttpHeaders.userAgentHeader: "pan.baidu.com"});
        videoUrl = uri.toString();
      }

      var packageName = videoPlayerRouter.substringBeforeLast("/")!;
      if (Platform.isIOS) {
        if (packageName.startsWith("nplayer-")) {
          var rawUrl = await requestRawUrl(remotePath, password);
          if (rawUrl != null) {
            var uri = Uri.parse("$packageName$rawUrl");
            return launchUrl(uri);
          } else {
            SmartDialog.showToast(Intl.tips_request_raw_url_failed.tr);
            return false;
          }
        }
        var uri = Uri.parse("$packageName$videoUrl");
        return launchUrl(uri);
      } else {
        var activity = videoPlayerRouter.substringAfterLast("/")!;
        return AlistPlugin.playVideoWithExternalPlayer(
            packageName, activity, videoUrl);
      }
    }
  }

  static Future<List<ExternalPlayerEntity>> loadPlayerResoleInfoList() async {
    List<ExternalPlayerEntity> playerList = [];

    if (!Platform.isAndroid) {
      var aliPlayer = ExternalPlayerEntity();
      aliPlayer.icon = Images.logo;
      aliPlayer.label = "AList Client";
      aliPlayer.activity = "";
      aliPlayer.packageName = "";

      var nPlayer = ExternalPlayerEntity();
      nPlayer.icon = Images.icNplayer;
      nPlayer.label = "nPlayer";
      nPlayer.activity = "";
      nPlayer.packageName = "nplayer-";

      var infuse = ExternalPlayerEntity();
      infuse.icon = Images.icInfuse;
      infuse.label = "Infuse";
      infuse.activity = "";
      infuse.packageName = "infuse://x-callback-url/play?url=";

      var vlc = ExternalPlayerEntity();
      vlc.icon = Images.icVlc;
      vlc.label = "VLC";
      vlc.activity = "";
      vlc.packageName = "vlc://";

      playerList.add(aliPlayer);
      playerList.add(nPlayer);
      playerList.add(infuse);
      playerList.add(vlc);
    } else {
      playerList = await AlistPlugin.loadPlayerResoleInfoList() ?? [];

      var exoplayer = ExternalPlayerEntity();
      exoplayer.icon = Images.logo;
      exoplayer.label = "ExoPlayer\n(AList Client)";
      exoplayer.activity = "";
      exoplayer.packageName = "exoplayer";

      var mediaKitPlayer = ExternalPlayerEntity();
      mediaKitPlayer.icon = Images.logo;
      mediaKitPlayer.label = "MediaKit\n(AList Client)";
      mediaKitPlayer.activity = "";
      mediaKitPlayer.packageName = "media_kit";
      playerList.insert(0, mediaKitPlayer);
      playerList.insert(0, exoplayer);
    }
    return playerList;
  }

  static void selectThePlayerToPlay(BuildContext context,
      List<VideoItem> videos, int index, String? password) async {
    List<ExternalPlayerEntity> externalPlayerList =
        await loadPlayerResoleInfoList();

    if (!context.mounted) {
      return;
    }

    showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (context) {
          return PlayerSelectorDialog(
            players: externalPlayerList,
            onPlayerClick: (info) {
              var isInternal = info.label.contains("AList Client");
              Navigator.of(context).pop();

              if (isInternal) {
                String? playerType;
                if (Platform.isAndroid) {
                  playerType = info.packageName;
                }
                _playUrlWithInternalPlayer(videos, index,
                    playerType: playerType);
              } else {
                var videoPlayerRouter = "${info.packageName}/${info.activity}";
                var item = videos[index];
                _playUrlWithExternalPlayer(videoPlayerRouter, item.provider,
                    item.localPath, item.remotePath, item.sign, password);
              }
            },
          );
        });
  }

  static Future<String?> requestRawUrl(String path, String? password) async {
    var params = {"path": path, "password": password ?? ""};
    String? rawUrl;
    SmartDialog.showLoading();
    await DioUtils.instance.requestNetwork<FileInfoRespEntity>(
        Method.post, "fs/get",
        params: params, onSuccess: (detail) {
      rawUrl = detail?.rawUrl;
    }, onError: (code, msg) {});
    SmartDialog.dismiss(status: SmartStatus.loading);
    return rawUrl;
  }
}
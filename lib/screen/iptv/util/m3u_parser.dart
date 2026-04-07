import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../model/iptv_channel.dart';

class M3uParseResult {
  final List<IptvChannel> channels;
  /// 保持原始分组顺序
  final List<String> groupOrder;
  /// 是否是 HLS 流（直接播放，不作为频道列表）
  final bool isHlsStream;

  M3uParseResult({
    required this.channels,
    required this.groupOrder,
    this.isHlsStream = false,
  });
}

class _ParseParams {
  final String content;
  _ParseParams(this.content);
}

class M3uParser {
  static const _extInf = '#EXTINF:';
  static const _extGrp = '#EXTGRP:';

  /// 从 URL 解析播放列表
  static Future<M3uParseResult> parseFromUrl(String url) async {
    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 15);
    dio.options.receiveTimeout = const Duration(seconds: 30);
    dio.options.followRedirects = true;
    dio.options.maxRedirects = 5;
    dio.options.headers = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/91.0 Mobile Safari/537.36',
    };
    // 让 Dio 走系统代理（VPN 场景）
    // Dio 5.x 在 Android 上底层用 HttpClient，通过环境变量读取系统代理
    // 无需额外配置，findProxyFromEnvironment 会自动生效

    final response = await dio.get(
      url,
      options: Options(
        responseType: ResponseType.plain,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    if (response.statusCode != null && response.statusCode! >= 400) {
      // 请求失败，当作直播流直接播放
      return M3uParseResult(channels: [], groupOrder: [], isHlsStream: true);
    }
    return _parseContent(response.data.toString());
  }

  /// 从字符串内容解析（用于 alist 文件内容）
  static Future<M3uParseResult> parseFromString(String content) async {
    if (content.length > 500 * 1024) {
      return compute(_parseInIsolate, _ParseParams(content));
    }
    return _parseContent(content);
  }

  static M3uParseResult _parseInIsolate(_ParseParams params) {
    return _parseContent(params.content);
  }

  static M3uParseResult _parseContent(String content) {
    // 检测是否是 HLS 流（主播放列表或媒体播放列表）
    if (content.contains('#EXT-X-STREAM-INF') ||
        content.contains('#EXT-X-TARGETDURATION') ||
        content.contains('#EXT-X-MEDIA-SEQUENCE')) {
      return M3uParseResult(channels: [], groupOrder: [], isHlsStream: true);
    }

    final lines = LineSplitter.split(content).toList();
    final List<IptvChannel> channels = [];
    // 用 LinkedHashSet 保持分组插入顺序
    final List<String> groupOrder = [];
    final Set<String> groupSeen = {};

    String? currentName;
    String? currentLogo;
    String? currentGroup;
    String? currentEpgId;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (line.startsWith(_extInf)) {
        final parsed = _parseExtInf(line);
        currentName = parsed['name'];
        currentLogo = parsed['logo'];
        currentGroup = parsed['group'];
        currentEpgId = parsed['epgId'];
      } else if (line.startsWith(_extGrp)) {
        currentGroup = line.substring(_extGrp.length).trim();
      } else if (!line.startsWith('#')) {
        // URL 行
        if (currentName != null && _isValidUrl(line)) {
          final group = currentGroup ?? 'Uncategorized';
          if (!groupSeen.contains(group)) {
            groupSeen.add(group);
            groupOrder.add(group);
          }
          channels.add(IptvChannel(
            name: currentName,
            url: line,
            logoUrl: currentLogo,
            groupName: group,
            epgId: currentEpgId,
          ));
        }
        currentName = null;
        currentLogo = null;
        currentGroup = null;
        currentEpgId = null;
      }
    }

    return M3uParseResult(channels: channels, groupOrder: groupOrder);
  }

  static Map<String, String?> _parseExtInf(String line) {
    String content = line.substring(_extInf.length);
    String? name;
    final lastComma = content.lastIndexOf(',');
    if (lastComma != -1) {
      name = content.substring(lastComma + 1).trim();
      content = content.substring(0, lastComma);
    }
    final attrs = _parseAttributes(content);
    return {
      'name': name,
      'logo': attrs['tvg-logo'] ?? attrs['logo'],
      'group': attrs['group-title'] ?? attrs['tvg-group'],
      'epgId': attrs['tvg-id'] ?? attrs['tvg-name'],
    };
  }

  static Map<String, String> _parseAttributes(String content) {
    final Map<String, String> attrs = {};
    final regex = RegExp(r'(\S+?)=["\u0027]([^"\u0027]*)["\u0027]');
    for (final match in regex.allMatches(content)) {
      final key = match.group(1)?.toLowerCase();
      final value = match.group(2);
      if (key != null && value != null) attrs[key] = value.trim();
    }
    return attrs;
  }

  static bool _isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme &&
          ['http', 'https', 'rtmp', 'rtsp', 'mms', 'mmsh', 'mmst']
              .contains(uri.scheme);
    } catch (_) {
      return false;
    }
  }
}

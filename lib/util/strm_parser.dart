import 'package:alist/net/dio_utils.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/file_utils.dart';
import 'package:dio/dio.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/foundation.dart';

/// .strm 文件解析工具类
///
/// .strm 文件是一个纯文本文件，内部存储了一段完整的视频流 URL。
/// 示例内容：
///   http://192.168.2.124:8024/smartstrm_fid/open115_php112/.../?sign=...
///
/// 该类负责：
/// 1. 通过 alist 直链读取 .strm 文件的文本内容
/// 2. 清洗提取出的 URL（去除首尾空白、换行符等）
/// 3. 验证 URL 格式的合法性
class StrmParser {
  /// 读取 .strm 文件并解析出其中的视频流 URL
  ///
  /// [path] - .strm 文件在 alist 上的远程路径
  /// [sign] - 文件的签名（部分 alist 驱动需要）
  ///
  /// 返回清洗后的视频流 URL，若读取或解析失败则返回 null
  static Future<String?> parseStrmUrl(String path, String? sign) async {
    try {
      // Step 1: 生成 .strm 文件的 alist 直链
      final strmFileUrl = await FileUtils.makeFileLink(path, sign);
      if (strmFileUrl == null || strmFileUrl.isEmpty) {
        debugPrint('[StrmParser] 无法生成 .strm 文件直链: $path');
        return null;
      }

      // Step 2: 通过 HTTP GET 读取 .strm 文件内容
      final content = await _fetchTextContent(strmFileUrl);
      if (content == null || content.isEmpty) {
        debugPrint('[StrmParser] .strm 文件内容为空: $path');
        return null;
      }

      // Step 3: 对内容进行清洗和验证
      return _sanitizeUrl(content);
    } catch (e) {
      debugPrint('[StrmParser] 解析 .strm 文件异常: $path, error=$e');
      return null;
    }
  }

  /// 批量解析多个 .strm 文件，返回成功解析的结果列表
  ///
  /// [strmEntries] - Map 列表，每个元素包含 'path' 和 'sign' 键
  /// 每个成功解析的条目返回 {path, url}
  static Future<List<Map<String, String>>> batchParseStrmUrls(
      List<Map<String, String?>> strmEntries) async {
    final results = <Map<String, String>>[];

    // 并发读取所有 .strm 文件（使用 Future.wait 提升效率）
    final futures = strmEntries.map((entry) async {
      final path = entry['path'] ?? '';
      final sign = entry['sign'];
      final url = await parseStrmUrl(path, sign);
      if (url != null) {
        results.add({'path': path, 'url': url});
      }
    });

    await Future.wait(futures, eagerError: false);
    return results;
  }

  /// 通过 HTTP GET 获取远程文件的文本内容
  ///
  /// 使用 Dio 直接 GET 请求获取 .strm 文件内容，
  /// 因为 .strm 文件是纯文本格式，直接读取原始响应即可。
  static Future<String?> _fetchTextContent(String url) async {
    try {
      final dio = DioUtils.instance.dio;

      // 构建请求选项：设置合理的超时，接受纯文本响应
      final response = await dio.get(
        url,
        options: Options(
          // 3秒连接超时 + 5秒接收超时，.strm 文件通常很小
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 5),
          // 接受任意响应类型，直接获取字符串
          responseType: ResponseType.plain,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        return response.data.toString();
      }
      debugPrint(
          '[StrmParser] HTTP请求失败: statusCode=${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('[StrmParser] HTTP请求异常: $e');
      return null;
    }
  }

  /// 清洗 URL 字符串
  ///
  /// 处理步骤：
  /// 1. 去除首尾空格、制表符、换行符（\r, \n）
  /// 2. 去除 URL 中可能夹带的不可见字符（如零宽空格等）
  /// 3. 验证是否为合法的 HTTP/HTTPS URL
  static String? _sanitizeUrl(String rawContent) {
    // Step 1: 去除所有首尾空白字符
    String url = rawContent.trim();

    // Step 2: 去除不可见字符（零宽空格、BOM 等）
    // eslint-disable-next-line no-control-regex
    url = url.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F\u200B-\u200F\uFEFF]'), '');

    // Step 3: 截取第一行（如果 .strm 内容包含多行，只取第一行有效 URL）
    final lines = url.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
        url = trimmed;
        break;
      }
    }

    // Step 4: 再次 trim 确保干净
    url = url.trim();

    if (url.isEmpty) {
      return null;
    }

    // Step 5: 验证 URL 格式 - 必须是 http:// 或 https:// 开头的合法 URI
    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
        debugPrint('[StrmParser] URL 缺少合法的 scheme: $url');
        return null;
      }
      if (!uri.hasAuthority || uri.host.isEmpty) {
        debugPrint('[StrmParser] URL 缺少合法的 host: $url');
        return null;
      }
    } catch (e) {
      debugPrint('[StrmParser] URL 格式非法: $url, error=$e');
      return null;
    }

    // Step 6: 应用主机地址替换（如果用户启用了 FRP/反向代理穿透）
    return _applyHostOverride(url);
  }

  /// 根据设置中的开关与地址映射，替换 .strm URL 中的原始主机为代理后的主机
  ///
  /// 场景：内网服务器 (192.168.x.x:8024) 通过 frp 穿透暴露到公网
  /// (frp.example.com:12345)，应用此替换后可在外网直接播放。
  static String? _applyHostOverride(String url) {
    try {
      final enabled = SpUtil.getBool(AlistConstant.strmHostOverrideEnabled, defValue: false) ?? false;
      if (!enabled) return url;

      final from = SpUtil.getString(AlistConstant.strmHostOverrideFrom);
      final to = SpUtil.getString(AlistConstant.strmHostOverrideTo);

      if (from == null || from.isEmpty || to == null || to.isEmpty) return url;

      final uri = Uri.parse(url);
      final originalAuthority = '${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';

      // 精确匹配原始主机（host:port 组合）
      if (originalAuthority == from.trim()) {
        // 解析目标地址（可能包含端口）
        final toUri = Uri.parse('http://${to.trim()}');
        final newUrl = url.replaceFirst(
          '$originalAuthority',
          '${toUri.host}${toUri.hasPort ? ':${toUri.port}' : ''}',
        );
        debugPrint('[StrmParser] 主机替换: $originalAuthority → ${to.trim()}');
        return newUrl;
      }
    } catch (e) {
      debugPrint('[StrmParser] 主机替换异常: $e');
    }
    return url;
  }

  /// 判断给定路径是否指向 .strm 文件
  static bool isStrmFile(String path) {
    final ext = path.split('.').last.toLowerCase();
    return ext == 'strm';
  }
}
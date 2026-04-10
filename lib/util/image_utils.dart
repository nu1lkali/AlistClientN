import 'dart:io';
import 'package:extended_image/extended_image.dart';
import 'package:flustars/flustars.dart';
import 'package:alist/util/constant.dart';

/// 创建绕过局域网代理的 ExtendedNetworkImageProvider
/// 只有局域网地址才绕过代理，公网地址仍走系统代理
ExtendedNetworkImageProvider noProxyImageProvider(
  String url, {
  Map<String, String>? headers,
  bool cache = true,
}) {
  return ExtendedNetworkImageProvider(
    url,
    headers: headers,
    cache: cache,
  );
}

/// 判断是否是局域网地址
bool _isLanHost(String host) {
  // IPv4 局域网段
  if (host == 'localhost' || host == '127.0.0.1') return true;
  final parts = host.split('.');
  if (parts.length != 4) return false;
  final a = int.tryParse(parts[0]);
  final b = int.tryParse(parts[1]);
  if (a == null || b == null) return false;
  if (a == 10) return true;                          // 10.0.0.0/8
  if (a == 192 && b == 168) return true;             // 192.168.0.0/16
  if (a == 172 && b >= 16 && b <= 31) return true;  // 172.16.0.0/12
  return false;
}

/// 全局 HttpOverrides：只对局域网地址绕过代理，公网地址走系统代理
/// 在 main() 里调用 HttpOverrides.global = AlistHttpOverrides()
class AlistHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (uri) {
      if (_isLanHost(uri.host)) {
        return 'DIRECT'; // 局域网直连，不走 VPN 代理
      }
      return HttpClient.findProxyFromEnvironment(uri); // 公网走系统代理
    };
    client.badCertificateCallback = (cert, host, port) {
      if (SpUtil.getBool(AlistConstant.ignoreSSLError) ?? false) {
        return true;
      }
      return false;
    };
    return client;
  }
}

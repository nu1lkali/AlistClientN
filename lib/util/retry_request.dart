import 'dart:async';

import 'package:alist/util/log_utils.dart';

/// 通用异步请求静默重试包装函数
///
/// 当传入的异步请求失败时，自动进行静默重试。
/// 适用于偶发网络错误（如 .strm 解析瞬时失败）。
///
/// 使用方式：
///   final result = await retryRequest(
///     request: () => StrmParser.parseStrmUrl(path, sign),
///     maxRetries: 3,
///     delay: Duration(milliseconds: 300),
///     onRetry: (attempt, error) => print('重试第 $attempt 次: $error'),
///   );
///
/// [request] - 要执行的异步请求函数
/// [maxRetries] - 最大重试次数（默认 3 次）
/// [delay] - 每次重试间隔（默认 300ms）
/// [onRetry] - 重试时的回调（可选），用于打印日志
/// [shouldRetry] - 判断是否应该重试的函数（可选），默认所有异常都重试
///
/// 返回请求结果，若所有重试均失败则抛出最后一次异常
Future<T> retryRequest<T>({
  required Future<T> Function() request,
  int maxRetries = 3,
  Duration delay = const Duration(milliseconds: 300),
  void Function(int attempt, dynamic error)? onRetry,
  bool Function(dynamic error)? shouldRetry,
}) async {
  dynamic lastError;
  for (int attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await request();
    } catch (e) {
      lastError = e;
      if (attempt < maxRetries) {
        if (shouldRetry != null && !shouldRetry(e)) {
          rethrow;
        }
        onRetry?.call(attempt + 1, e);
        Log.e('[retryRequest] 第 ${attempt + 1} 次重试: $e');
        await Future.delayed(delay);
      }
    }
  }
  throw lastError;
}

/// 带有默认日志输出的重试包装函数（简化版）
///
/// 适用于不需要自定义回调的场景
Future<T?> retryRequestSilent<T>({
  required Future<T?> Function() request,
  int maxRetries = 3,
  Duration delay = const Duration(milliseconds: 300),
  String tag = 'retryRequest',
}) async {
  T? result;
  for (int attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      result = await request();
      if (result != null) return result;
    } catch (e) {
      if (attempt < maxRetries) {
        Log.e('[$tag] 第 ${attempt + 1} 次重试失败: $e');
        await Future.delayed(delay);
      } else {
        Log.e('[$tag] 所有重试耗尽: $e');
      }
    }
  }
  return result;
}

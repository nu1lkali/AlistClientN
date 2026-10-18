import 'dart:async';

import 'package:alist/entity/file_list_resp_entity.dart';
import 'package:alist/net/dio_utils.dart';
import 'package:alist/util/log_utils.dart';
import 'package:dio/dio.dart';

/// AList `fs/list` 的统一入口：**自动翻页，把目录拉全**。
///
/// ## 为什么需要这一层（真实 bug，别再退回 `per_page: 0` 单次请求）
///
/// AList 后端对 `per_page` 有归一化规则（官方 API 文档 `fs/list` 一节）：
/// - `per_page <= 0` ⇒ 使用**默认值 200**；
/// - `per_page > 500` ⇒ 截断成 500。
///
/// 所以「`per_page: 0` 就是一次拿全」是个流传很广的误解 —— 请求里写 0，
/// 服务端只给你**前 200 条**。目录里文件超过 200 个（番剧一季、照片文件夹、
/// 电影合集）时，界面上就只显示一部分，而且没有任何提示，看起来像「文件丢了」。
///
/// 正确做法：`per_page = 500`（服务端上限）逐页拉，按 `has_more` / `total` /
/// 满页启发式判断还有没有下一页，直到收齐。
///
/// ## 为什么按 `params` 传而不是按参数传
///
/// 现有调用点全都是「构造一个 body map，再 `requestNetwork<FileListRespEntity>`」。
/// 保持同一个形状，调用点只改一行方法名，`onSuccess` / `onError` 的语义、
/// 取消令牌、拦截器（鉴权、401 跳登录）全部沿用，不引入第二套请求通路。
class AlistFs {
  AlistFs._();

  /// 每页条数。⚠️ 服务端上限就是 500，写更大只会被截断。
  static const int pageSize = 500;

  /// 翻页保护上限（500 × 50 = 25000 条），防「服务端忽略 page 一直返回同一批」死循环。
  static const int maxPages = 50;

  /// 请求一个目录的**全部**条目，聚合结果通过 [onSuccess] 回调一次。
  ///
  /// @param params 必须含 `path`；`password` / `refresh` 可选。`page` / `per_page`
  ///   由本方法接管（传了也会被覆盖）。
  /// @param onError 仅在**第一页**失败时回调 —— 后续页失败视为「能拿多少算多少」，
  ///   打日志后把已取到的部分回调给调用方（比整页失败更接近真机可用的行为）。
  static Future<void> requestAll({
    required Map<String, dynamic> params,
    CancelToken? cancelToken,
    required void Function(FileListRespEntity data) onSuccess,
    void Function(int code, String msg)? onError,
  }) async {
    final path = (params['path'] as String?) ?? '/';
    final password = (params['password'] as String?) ?? '';
    final refresh = params['refresh'] == true;

    final merged = <FileListRespContent>[];
    final seen = <String>{};
    FileListRespEntity? first;
    var pagesFetched = 0;

    for (var page = 1; page <= maxPages; page++) {
      final data = await _fetchPage(
        path: path,
        password: password,
        // 只在第一页要求强制刷新：每页都 refresh 会让服务端反复重扫目录
        refresh: refresh && page == 1,
        page: page,
        cancelToken: cancelToken,
        onError: page == 1 ? onError : null,
      );

      if (data == null) {
        if (page == 1) return; // 首页失败：onError 已经回调，别再假装成功
        Log.d('[AlistFs] 第 $page 页失败，返回已取到的 ${merged.length} 条：$path');
        break;
      }

      first ??= data;
      pagesFetched = page;

      final content = data.content ?? const <FileListRespContent>[];
      var added = 0;
      for (final file in content) {
        if (seen.add(file.name)) {
          merged.add(file);
          added++;
        }
      }

      // 停下来：本页空 / 服务端忽略 page 又给了同一批 / 已经没有下一页
      if (content.isEmpty || added == 0) break;
      if (!_hasMore(data, page, content.length, merged.length)) break;
    }

    if (cancelToken?.isCancelled == true) return;

    final head = first;
    if (head == null) {
      onError?.call(-1, 'AList 列目录没有返回数据：$path');
      return;
    }

    onSuccess(
      FileListRespEntity()
        ..content = merged
        ..total = merged.length
        ..readme = head.readme
        ..write = head.write
        ..provider = head.provider
        ..hasMore = false
        ..pagesTotal = pagesFetched,
    );
  }

  /// 单页请求。返回 `null` = 这一页失败（失败信息已通过 [onError] 上报）。
  static Future<FileListRespEntity?> _fetchPage({
    required String path,
    required String password,
    required bool refresh,
    required int page,
    CancelToken? cancelToken,
    void Function(int code, String msg)? onError,
  }) {
    final completer = Completer<FileListRespEntity?>();
    DioUtils.instance.requestNetwork<FileListRespEntity>(
      Method.post,
      'fs/list',
      cancelToken: cancelToken,
      params: {
        'path': path,
        'password': password,
        'page': page,
        'per_page': pageSize,
        'refresh': refresh,
      },
      onSuccess: (data) {
        if (!completer.isCompleted) completer.complete(data);
      },
      onError: (code, msg) {
        if (!completer.isCompleted) completer.complete(null);
        onError?.call(code, msg);
      },
    );
    return completer.future;
  }

  /// 「还有下一页吗」。三个判据按可靠性排序：
  /// 1. `has_more`（v3.58.0+，最准）；
  /// 2. `total`（老版本也有，但部分驱动给的值可能不准）；
  /// 3. 满页启发式（都没给时兜底，最坏只是多请求一次空页）。
  static bool _hasMore(
    FileListRespEntity data,
    int page,
    int pageCount,
    int fetched,
  ) {
    if (data.hasMore) return true;
    if (data.total > 0) return fetched < data.total;
    return pageCount >= pageSize;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/util/download/download_manager.dart';
import 'package:alist/util/download/download_task.dart';
import 'package:alist/util/download/download_task_status.dart';
import 'package:alist/util/user_controller.dart';
import 'package:alist/widget/alist_scaffold.dart';
import 'package:alist/widget/loading_status_widget.dart';
import 'package:alist/widget/overflow_text.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class MarkdownReaderScreen extends StatelessWidget {
  final MarkdownReaderScreenController _controller =
      Get.put(MarkdownReaderScreenController());

  MarkdownReaderScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlistScaffold(
      appbarTitle: OverflowText(text: _controller.markdownItem.name),
      body: Obx(
        () => LoadingStatusWidget(
          loading: _controller.loading.value,
          retryCallback: () => _controller.retry(),
          errorMsg: _controller.errMsg.value,
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Obx(() {
      if (_controller.isDownloading.value) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                '正在加载 Markdown...',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        );
      }

      if (_controller.htmlContent.value.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }

      return InAppWebView(
        initialData: InAppWebViewInitialData(
          data: _controller.htmlContent.value,
          baseUrl: Uri.parse('about:blank'),
        ),
        initialOptions: InAppWebViewGroupOptions(
          crossPlatform: InAppWebViewOptions(
            supportZoom: true,
            useOnLoadResource: true,
          ),
          android: AndroidInAppWebViewOptions(
            useWideViewPort: true,
            loadWithOverviewMode: true,
            builtInZoomControls: true,
            displayZoomControls: false,
          ),
        ),
      );
    });
  }
}

class MarkdownReaderScreenController extends GetxController {
  MarkdownItem markdownItem = Get.arguments['markdownItem'];
  StreamSubscription? _streamSubscription;
  DownloadTask? _downloadTask;
  var loading = false.obs;
  var isDownloading = false.obs;
  var localPath = "".obs;
  var errMsg = "".obs;
  var htmlContent = "".obs;

  @override
  void onInit() {
    super.onInit();
    _loadMarkdown();
  }

  @override
  void onClose() {
    _downloadTask?.cancel();
    _streamSubscription?.cancel();
    super.onClose();
  }

  void retry() {
    LogUtil.d("retry");
    errMsg.value = "";
    _loadMarkdown();
  }

  void _loadMarkdown() async {
    loading.value = true;
    isDownloading.value = true;

    // 如果直接传入了内容，跳过下载
    if (markdownItem.content != null) {
      await _renderMarkdown(null, content: markdownItem.content);
      return;
    }

    final requestHeaders = <String, dynamic>{};
    var limitFrequency = 0;
    if (markdownItem.provider == "BaiduNetdisk") {
      requestHeaders["User-Agent"] = "pan.baidu.com";
    } else if (markdownItem.provider == "AliyundriveOpen") {
      limitFrequency = 1;
    }
    
    _downloadTask = await DownloadManager.instance.download(
      name: markdownItem.name,
      remotePath: markdownItem.remotePath,
      sign: markdownItem.sign ?? "",
      thumb: markdownItem.thumb,
      requestHeaders: requestHeaders,
      limitFrequency: limitFrequency,
    );
    
    if (_downloadTask == null) {
      errMsg.value = "加载失败";
      loading.value = false;
      isDownloading.value = false;
      return;
    }
    
    if (_downloadTask?.status == DownloadTaskStatus.finished) {
      await _renderMarkdown(_downloadTask!.record.localPath);
    } else {
      _listenStatus();
    }
  }

  void _listenStatus() {
    _streamSubscription =
        DownloadManager.instance.listenDownloadStatusChange((task) async {
      if (task != _downloadTask) {
        return;
      }
      
      if (task.status == DownloadTaskStatus.finished) {
        await _renderMarkdown(task.record.localPath);
      } else if (task.status == DownloadTaskStatus.failed) {
        errMsg.value = task.failedReason ?? "加载失败";
        loading.value = false;
        isDownloading.value = false;
      }
    });
  }

  Future<void> _renderMarkdown(String? filePath, {String? content}) async {
    try {
      String mdContent;
      if (content != null) {
        mdContent = content;
      } else {
        final file = File(filePath!);
        if (!file.existsSync()) {
          errMsg.value = "文件不存在";
          loading.value = false;
          isDownloading.value = false;
          return;
        }
        mdContent = await file.readAsString();
      }
      final escapedContent = _escapeHtml(mdContent);
      
      htmlContent.value = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=3.0, user-scalable=yes">
  <title>Markdown Preview</title>
  <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
  <style>
    * {
      box-sizing: border-box;
    }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Microsoft YaHei', Arial, sans-serif;
      line-height: 1.6;
      color: #333;
      max-width: 900px;
      margin: 0 auto;
      padding: 20px;
      background-color: #fff;
    }
    h1, h2, h3, h4, h5, h6 {
      margin-top: 24px;
      margin-bottom: 16px;
      font-weight: 600;
      line-height: 1.25;
    }
    h1 { font-size: 2em; border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; }
    h2 { font-size: 1.5em; border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; }
    h3 { font-size: 1.25em; }
    h4 { font-size: 1em; }
    h5 { font-size: 0.875em; }
    h6 { font-size: 0.85em; color: #6a737d; }
    p { margin-top: 0; margin-bottom: 16px; }
    a { color: #0366d6; text-decoration: none; }
    a:hover { text-decoration: underline; }
    code {
      padding: 0.2em 0.4em;
      margin: 0;
      font-size: 85%;
      background-color: rgba(27,31,35,0.05);
      border-radius: 3px;
      font-family: 'Courier New', Courier, monospace;
    }
    pre {
      padding: 16px;
      overflow: auto;
      font-size: 85%;
      line-height: 1.45;
      background-color: #f6f8fa;
      border-radius: 6px;
    }
    pre code {
      display: inline;
      padding: 0;
      margin: 0;
      overflow: visible;
      line-height: inherit;
      background-color: transparent;
      border: 0;
    }
    blockquote {
      padding: 0 1em;
      color: #6a737d;
      border-left: 0.25em solid #dfe2e5;
      margin: 0 0 16px 0;
    }
    ul, ol {
      padding-left: 2em;
      margin-top: 0;
      margin-bottom: 16px;
    }
    li + li {
      margin-top: 0.25em;
    }
    table {
      border-spacing: 0;
      border-collapse: collapse;
      margin-top: 0;
      margin-bottom: 16px;
      width: 100%;
      overflow: auto;
    }
    table th {
      font-weight: 600;
      padding: 6px 13px;
      border: 1px solid #dfe2e5;
      background-color: #f6f8fa;
    }
    table td {
      padding: 6px 13px;
      border: 1px solid #dfe2e5;
    }
    table tr {
      background-color: #fff;
      border-top: 1px solid #c6cbd1;
    }
    table tr:nth-child(2n) {
      background-color: #f6f8fa;
    }
    img {
      max-width: 100%;
      height: auto;
      box-sizing: content-box;
    }
    hr {
      height: 0.25em;
      padding: 0;
      margin: 24px 0;
      background-color: #e1e4e8;
      border: 0;
    }
  </style>
</head>
<body>
  <div id="content"></div>
  <script>
    const markdown = `$escapedContent`;
    document.getElementById('content').innerHTML = marked.parse(markdown);
  </script>
</body>
</html>
''';
      
      errMsg.value = "";
      loading.value = false;
      isDownloading.value = false;
    } catch (e) {
      LogUtil.e("Render markdown error: $e");
      errMsg.value = "渲染失败: $e";
      loading.value = false;
      isDownloading.value = false;
    }
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('\\', '\\\\')
        .replaceAll('`', '\\`')
        .replaceAll('\$', '\\\$');
  }
}

class MarkdownItem {
  final String name;
  String? localPath;
  final String remotePath;
  final String? sign;
  final String? provider;
  final String? thumb;
  final String? content; // 直接传入 markdown 内容，不需要下载

  MarkdownItem({
    required this.name,
    this.localPath,
    required this.remotePath,
    this.sign,
    this.provider,
    this.thumb,
    this.content,
  });
}

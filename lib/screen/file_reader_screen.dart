import 'dart:async';
import 'dart:io';

import 'package:alist/l10n/intl_keys.dart';
import 'package:alist/util/download/download_manager.dart';
import 'package:alist/util/download/download_task.dart';
import 'package:alist/util/download/download_task_status.dart';
import 'package:alist/util/file_type.dart';
import 'package:alist/util/file_utils.dart';
import 'package:alist/util/widget_utils.dart';
import 'package:alist/widget/alist_scaffold.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';

class FileReaderScreen extends StatelessWidget {
  FileReaderScreen({Key? key}) : super(key: key);
  final FileReaderItem _fileReaderItem = Get.arguments["fileReaderItem"];

  @override
  Widget build(BuildContext context) {
    return AlistScaffold(
      appbarTitle: const SizedBox(),
      body: _FileReaderContainer(fileReaderItem: _fileReaderItem),
    );
  }
}

class _FileReaderContainer extends StatefulWidget {
  const _FileReaderContainer({Key? key, required this.fileReaderItem})
      : super(key: key);
  final FileReaderItem fileReaderItem;

  @override
  State<_FileReaderContainer> createState() => _FileReaderContainerState();
}

class _FileReaderContainerState extends State<_FileReaderContainer> {
  String? _localPath;
  int _downloadProgress = 0;
  bool _isOpenSuccessfully = false;
  String? failedMessage;
  String? fileName;
  DownloadTask? _downloadTask;
  late StreamSubscription _downloadProgressSubscription;
  late StreamSubscription _downloadStatusChangeSubscription;
  bool _downloadFinished = false;
  DateTime? _downloadFinishTime;

  @override
  void initState() {
    super.initState();
    _download(widget.fileReaderItem);
    _downloadProgressSubscription =
        DownloadManager.instance.listenDownloadProgressChange((task) {
      if (task == _downloadTask) {
        if (task.contentLength != null) {
          setState(() {
            _downloadProgress =
                (task.downloaded / task.contentLength! * 100).round();
          });
        }
      }
    });
    _downloadStatusChangeSubscription =
        DownloadManager.instance.listenDownloadStatusChange((task) {
      if (task == _downloadTask) {
        if (task.status == DownloadTaskStatus.failed) {
          SmartDialog.showToast(task.failedReason ?? "");
        } else if (task.status == DownloadTaskStatus.finished) {
          _onDownloadFinish(widget.fileReaderItem.fileType);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = WidgetUtils.isDarkMode(context);
    final item = widget.fileReaderItem;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Card(
          elevation: 0,
          color: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: scheme.outlineVariant.withOpacity(0.3),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildProgressIndicator(scheme),
                const SizedBox(height: 24),
                Text(
                  item.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                _buildStatusText(scheme, isDark),
                const SizedBox(height: 24),
                _buildActionArea(scheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(ColorScheme scheme) {
    final finished = _downloadFinished || failedMessage != null;
    final progress = _downloadProgress / 100.0;

    return SizedBox(
      width: 100,
      height: 100,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 100,
            height: 100,
            child: CircularProgressIndicator(
              value: finished ? 1.0 : progress.clamp(0.01, 1.0),
              strokeWidth: 6,
              backgroundColor: scheme.surfaceVariant.withOpacity(0.5),
              valueColor: AlwaysStoppedAnimation<Color>(
                failedMessage != null ? scheme.error : scheme.primary,
              ),
            ),
          ),
          if (failedMessage != null)
            Icon(Icons.error_outline_rounded, size: 36, color: scheme.error)
          else if (_downloadFinished)
            Icon(Icons.check_rounded, size: 36, color: scheme.primary)
          else
            Text(
              '$_downloadProgress%',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: scheme.primary,
              ),
            ),
        ],
      ),
    );
  }

  String _fileTypeLabel() {
    final fileType = widget.fileReaderItem.fileType;
    switch (fileType) {
      case FileType.apk:
        return 'APK 安装包';
      case FileType.video:
        return '视频文件';
      case FileType.audio:
        return '音频文件';
      case FileType.image:
        return '图片文件';
      case FileType.pdf:
        return 'PDF 文档';
      case FileType.txt:
        return '文本文件';
      case FileType.word:
        return 'Word 文档';
      case FileType.excel:
        return 'Excel 表格';
      case FileType.ppt:
        return 'PPT 演示';
      case FileType.compress:
        return '压缩包';
      case FileType.code:
        return '代码文件';
      case FileType.markdown:
        return 'Markdown 文件';
      default:
        return '文件';
    }
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(t.year, t.month, t.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) return '今天 $hh:$mm';
    if (diff == 1) return '昨天 $hh:$mm';
    if (diff == 2) return '前天 $hh:$mm';
    if (now.year == t.year) return '${t.month}/${t.day} $hh:$mm';
    return '${t.year}/${t.month}/${t.day} $hh:$mm';
  }

  Widget _buildStatusText(ColorScheme scheme, bool isDark) {
    if (failedMessage != null) {
      return Column(
        children: [
          Text(
            failedMessage!,
            style: TextStyle(fontSize: 13, color: scheme.error),
          ),
          const SizedBox(height: 4),
          Text(
            _fileTypeLabel(),
            style: TextStyle(fontSize: 12, color: scheme.outlineVariant),
          ),
        ],
      );
    }
    if (_downloadFinished) {
      final task = _downloadTask;
      final fileType = widget.fileReaderItem.fileType;
      final isApk = fileType == FileType.apk && Platform.isAndroid;
      final fileSize = (task?.contentLength != null && task!.contentLength! > 0)
          ? FileUtils.formatBytes(task.contentLength!)
          : null;
      final timeStr = _downloadFinishTime != null
          ? _formatTime(_downloadFinishTime!)
          : null;
      return Column(
        children: [
          Text(
            _downloadFinishedLabel(),
            style: TextStyle(fontSize: 13, color: scheme.outline),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              if (!isApk) _infoChip(scheme, _fileTypeLabel()),
              if (fileSize != null) _infoChip(scheme, fileSize),
              if (timeStr != null) _infoChip(scheme, timeStr),
            ],
          ),
        ],
      );
    }
    // 下载中
    final task = _downloadTask;
    String sizeInfo = '';
    if (task != null && task.contentLength != null && task.contentLength! > 0) {
      final downloaded = FileUtils.formatBytes(task.downloaded);
      final total = FileUtils.formatBytes(task.contentLength!);
      sizeInfo = '$downloaded / $total';
    }
    return Column(
      children: [
        Text(
          '正在下载…',
          style: TextStyle(fontSize: 13, color: scheme.outline),
        ),
        if (sizeInfo.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            sizeInfo,
            style: TextStyle(fontSize: 12, color: scheme.outlineVariant),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          _fileTypeLabel(),
          style: TextStyle(fontSize: 12, color: scheme.outlineVariant),
        ),
      ],
    );
  }

  Widget _infoChip(ColorScheme scheme, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: scheme.outline),
      ),
    );
  }

  String _downloadFinishedLabel() {
    final fileType = widget.fileReaderItem.fileType;
    if (fileType == FileType.apk && Platform.isAndroid) {
      return 'APK 安装包 · 下载完成';
    }
    return '下载完成';
  }

  Widget _buildActionArea(ColorScheme scheme) {
    if (failedMessage != null) {
      return FilledButton.tonalIcon(
        onPressed: () {
          setState(() {
            failedMessage = null;
            _downloadProgress = 0;
            _downloadFinished = false;
          });
          _download(widget.fileReaderItem);
        },
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('重试'),
      );
    }

    if (!_downloadFinished && !_isOpenSuccessfully) {
      // 下载中 - 显示取消按钮
      return TextButton.icon(
        onPressed: () {
          _downloadTask?.cancel();
          Navigator.of(context).pop();
        },
        icon: const Icon(Icons.close_rounded, size: 18),
        label: const Text('取消'),
        style: TextButton.styleFrom(foregroundColor: scheme.outline),
      );
    }

    // 下载完成
    final fileType = widget.fileReaderItem.fileType;
    final isApk = fileType == FileType.apk && Platform.isAndroid;

    if (isApk || _isOpenSuccessfully) {
      return FilledButton.icon(
        onPressed: _localPath != null ? () => _openFile(_localPath) : null,
        icon: Icon(isApk ? Icons.install_mobile_rounded : Icons.open_in_new_rounded),
        label: Text(isApk ? Intl.fileReaderScreen_install.tr : Intl.fileReaderScreen_openAgain.tr),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    _downloadTask?.cancel();
    _downloadProgressSubscription.cancel();
    _downloadStatusChangeSubscription.cancel();
    super.dispose();
  }

  void _download(FileReaderItem item) async {
    _downloadFinishTime = null;
    final fileType = widget.fileReaderItem.fileType;
    final requestHeaders = <String, dynamic>{};
    var limitFrequency = 0;
    if (item.provider == "BaiduNetdisk") {
      requestHeaders["User-Agent"] = "pan.baidu.com";
    } else if (item.provider == "AliyundriveOpen") {
      // 阿里云盘下载请求频率限制为 1s/次
      limitFrequency = 1;
    }

    _downloadTask = await DownloadManager.instance.download(
      name: item.name,
      remotePath: item.remotePath,
      sign: item.sign ?? "",
      thumb: item.thumb,
      requestHeaders: requestHeaders,
      limitFrequency: limitFrequency,
    );
    if (_downloadTask == null) {
      SmartDialog.showToast("Download failed.");
      return;
    }
    if (_downloadTask?.status == DownloadTaskStatus.finished) {
      _onDownloadFinish(fileType);
    }
  }

  void _onDownloadFinish(FileType? fileType) {
    LogUtil.d("_onDownloadFinish");
    _downloadFinishTime = DateTime.now();
    setState(() {
      _downloadFinished = true;
      fileName = widget.fileReaderItem.name;
      _downloadProgress = 100;
      _localPath = _downloadTask?.record.localPath;
    });
    if (!(fileType == FileType.apk && Platform.isAndroid)) {
      _openFile(_downloadTask?.record.localPath);
    }
  }

  _openFile(String? filePath) async {
    final fileType = widget.fileReaderItem.fileType;
    if (fileType == FileType.apk &&
        Platform.isAndroid &&
        !await Permission.requestInstallPackages.isGranted) {
      _showInstallPermissionDialog();
    } else {
      String? openFileType;
      switch (fileType) {
        case FileType.txt:
        case FileType.code:
          openFileType = "text/plain";
          break;
        case FileType.pdf:
          openFileType = "application/pdf";
          break;
        case FileType.apk:
          openFileType = "application/vnd.android.package-archive";
          break;
        default:
          openFileType = null;
          break;
      }

      OpenFile.open(filePath, type: openFileType).then((value) {
        if (value.type == ResultType.done) {
          setState(() {
            _isOpenSuccessfully = true;
          });
        } else {
          setState(() {
            _isOpenSuccessfully = false;
            failedMessage = value.message;
          });
        }
      });
      setState(() {
        _downloadProgress = 100;
        _downloadFinished = true;
        _localPath = filePath;
      });
    }
  }

  // just for android.
  void _showInstallPermissionDialog() {
    SmartDialog.show(builder: (context) {
      return AlertDialog(
        title: Text(Intl.installPermissionDialog_title.tr),
        content: Text(Intl.installPermissionDialog_content.tr),
        actions: [
          TextButton(
              onPressed: () {
                SmartDialog.dismiss();
              },
              child: Text(Intl.installPermissionDialog_btn_cancel.tr)),
          TextButton(
              onPressed: () {
                SmartDialog.dismiss();
                Permission.requestInstallPackages.request().then((value) {
                  if (value.isGranted) {
                    _openFile(_localPath);
                  } else {
                    SmartDialog.showToast(
                        Intl.installPermissionDialog_denied.tr);
                  }
                });
              },
              child: Text(Intl.installPermissionDialog_btn_ok.tr)),
        ],
      );
    });
  }
}

class FileReaderItem {
  final String name;
  String? localPath;
  final String remotePath;
  final String? sign;
  final String? provider;
  final String? thumb;
  final FileType? fileType;

  FileReaderItem({
    required this.name,
    this.localPath,
    required this.remotePath,
    this.sign,
    this.provider,
    this.thumb,
    required this.fileType,
  });
}

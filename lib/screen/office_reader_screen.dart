import 'dart:async';
import 'dart:io';

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/util/alist_plugin.dart';
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
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class OfficeReaderScreen extends StatelessWidget {
  final OfficeReaderScreenController _controller =
      Get.put(OfficeReaderScreenController());

  OfficeReaderScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlistScaffold(
      appbarTitle: OverflowText(text: _controller.officeItem.name),
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
                '正在下载文件...',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        );
      }

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.description_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 24),
            Text(
              '文件已准备就绪',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击下方按钮预览文档',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _controller.openFile,
              icon: const Icon(Icons.visibility),
              label: const Text('预览文档'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class OfficeReaderScreenController extends GetxController {
  OfficeItem officeItem = Get.arguments['officeItem'];
  StreamSubscription? _streamSubscription;
  DownloadTask? _downloadTask;
  var loading = false.obs;
  var isDownloading = false.obs;
  var localPath = "".obs;
  var errMsg = "".obs;

  @override
  void onInit() {
    super.onInit();
    if (officeItem.localPath == null || officeItem.localPath!.isEmpty) {
      AlistDatabaseController databaseController = Get.find();
      UserController userController = Get.find();
      final user = userController.user.value;
      databaseController.downloadRecordRecordDao
          .findRecordByRemotePath(
              user.serverUrl, user.username, officeItem.remotePath)
          .then((value) {
        if (value != null && File(value.localPath).existsSync()) {
          localPath.value = value.localPath;
          loading.value = false;
        } else {
          _download();
          _listenStatus();
        }
      });
    } else if (officeItem.localPath?.isNotEmpty == true) {
      localPath.value = officeItem.localPath!;
      loading.value = false;
    }
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
    _download();
  }

  void _download() async {
    loading.value = true;
    isDownloading.value = true;

    final requestHeaders = <String, dynamic>{};
    var limitFrequency = 0;
    if (officeItem.provider == "BaiduNetdisk") {
      requestHeaders["User-Agent"] = "pan.baidu.com";
    } else if (officeItem.provider == "AliyundriveOpen") {
      limitFrequency = 1;
    }
    
    _downloadTask = await DownloadManager.instance.download(
      name: officeItem.name,
      remotePath: officeItem.remotePath,
      sign: officeItem.sign ?? "",
      thumb: officeItem.thumb,
      requestHeaders: requestHeaders,
      limitFrequency: limitFrequency,
    );
    
    if (_downloadTask == null) {
      errMsg.value = "Download failed.";
      loading.value = false;
      isDownloading.value = false;
      return;
    }
    
    if (_downloadTask?.status == DownloadTaskStatus.finished) {
      errMsg.value = "";
      loading.value = false;
      isDownloading.value = false;
      localPath.value = _downloadTask!.record.localPath;
    }
  }

  void _listenStatus() {
    _streamSubscription =
        DownloadManager.instance.listenDownloadStatusChange((task) {
      if (task != _downloadTask) {
        return;
      }
      
      if (task.status == DownloadTaskStatus.finished) {
        errMsg.value = "";
        loading.value = false;
        isDownloading.value = false;
        localPath.value = task.record.localPath;
      } else if (task.status == DownloadTaskStatus.failed) {
        errMsg.value = task.failedReason ?? "";
        loading.value = false;
        isDownloading.value = false;
      }
    });
  }

  void openFile() async {
    if (localPath.value.isEmpty) {
      SmartDialog.showToast("文件路径无效");
      return;
    }

    final file = File(localPath.value);
    if (!file.existsSync()) {
      SmartDialog.showToast("文件不存在");
      return;
    }

    try {
      LogUtil.d("Opening document: ${localPath.value}");
      // 使用 Method Channel 调用原生文档预览
      await AlistPlugin.openDocument(localPath.value, officeItem.name);
    } on PlatformException catch (e) {
      LogUtil.e("Platform exception: ${e.code} - ${e.message}");
      if (e.code == "ERROR") {
        SmartDialog.showToast("打开文件失败: ${e.message}");
      } else {
        SmartDialog.showToast("打开文件失败: ${e.code}");
      }
    } catch (e) {
      LogUtil.e("Open file error: $e");
      SmartDialog.showToast("打开文件失败: $e");
    }
  }
}

class OfficeItem {
  final String name;
  String? localPath;
  final String remotePath;
  final String? sign;
  final String? provider;
  final String? thumb;

  OfficeItem({
    required this.name,
    this.localPath,
    required this.remotePath,
    this.sign,
    this.provider,
    this.thumb,
  });
}

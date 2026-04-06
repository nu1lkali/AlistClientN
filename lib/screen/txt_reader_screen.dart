import 'dart:convert';

import 'package:alist/l10n/intl_keys.dart';
import 'package:alist/net/dio_utils.dart';
import 'package:alist/util/file_utils.dart';
import 'package:alist/widget/alist_scaffold.dart';
import 'package:alist/widget/loading_status_widget.dart';
import 'package:alist/widget/overflow_text.dart';
import 'package:dio/dio.dart' as dio;
import 'package:flustars/flustars.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:charset/charset.dart';

class TxtReaderScreen extends StatelessWidget {
  final TxtReaderScreenController _controller =
      Get.put(TxtReaderScreenController());

  TxtReaderScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlistScaffold(
      appbarTitle: OverflowText(text: _controller.txtItem.name),
      appbarActions: [
        Obx(() => _controller.content.value.isNotEmpty
            ? PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  switch (value) {
                    case 'copy_link':
                      _controller.copyLink();
                      break;
                    case 'encoding':
                      _controller.showEncodingDialog();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'copy_link',
                    child: Row(
                      children: [
                        const Icon(Icons.link, size: 20),
                        const SizedBox(width: 12),
                        Text(Intl.fileList_menu_copyLink.tr),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'encoding',
                    child: Row(
                      children: [
                        const Icon(Icons.text_fields, size: 20),
                        const SizedBox(width: 12),
                        const Text('切换编码'),
                      ],
                    ),
                  ),
                ],
              )
            : const SizedBox()),
      ],
      body: Obx(
        () => LoadingStatusWidget(
          loading: _controller.loading.value,
          retryCallback: () => _controller.retry(),
          errorMsg: _controller.errMsg.value,
          child: _buildTextView(),
        ),
      ),
    );
  }

  Widget _buildTextView() {
    return Obx(
      () => _controller.content.value.isNotEmpty
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              physics: const BouncingScrollPhysics(),
              child: SelectableText(
                _controller.content.value,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
            )
          : const SizedBox(),
    );
  }
}

class TxtReaderScreenController extends GetxController {
  TxtItem txtItem = Get.arguments['txtItem'];
  var loading = false.obs;
  var content = "".obs;
  var errMsg = "".obs;
  var currentEncoding = 'UTF-8'.obs;
  List<int>? _rawBytes;

  @override
  void onInit() {
    super.onInit();
    _loadContent();
  }

  void retry() {
    LogUtil.d("retry");
    errMsg.value = "";
    _loadContent();
  }

  void _loadContent() async {
    loading.value = true;
    errMsg.value = "";

    try {
      final url = await FileUtils.makeFileLink(
        txtItem.remotePath,
        txtItem.sign ?? "",
        toastShowTips: false,
      );

      if (url == null || url.isEmpty) {
        errMsg.value = "Failed to get file URL";
        loading.value = false;
        return;
      }

      final requestHeaders = <String, dynamic>{};
      if (txtItem.provider == "BaiduNetdisk") {
        requestHeaders["User-Agent"] = "pan.baidu.com";
      }

      final response = await DioUtils.instance.dio.get<List<int>>(
        url,
        options: dio.Options(
          headers: requestHeaders,
          responseType: dio.ResponseType.bytes,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        _rawBytes = response.data;
        _decodeContent();
        loading.value = false;
      } else {
        errMsg.value = "Failed to load file";
        loading.value = false;
      }
    } catch (e) {
      LogUtil.e("Load txt file error: $e");
      errMsg.value = e.toString();
      loading.value = false;
    }
  }

  void _decodeContent() {
    if (_rawBytes == null) return;

    try {
      String decoded;
      bool autoDetected = false;
      String detectedEncoding = currentEncoding.value;
      
      switch (currentEncoding.value) {
        case 'UTF-8':
          decoded = utf8.decode(_rawBytes!, allowMalformed: true);
          break;
        case 'GBK':
          decoded = gbk.decode(_rawBytes!);
          break;
        case 'GB2312':
          decoded = gbk.decode(_rawBytes!); // GB2312 is subset of GBK
          break;
        case 'Latin1':
          decoded = latin1.decode(_rawBytes!);
          break;
        default:
          decoded = utf8.decode(_rawBytes!, allowMalformed: true);
      }
      
      // 检测是否有乱码，如果有则自动尝试其他编码
      if (_hasGarbledText(decoded) && currentEncoding.value == 'UTF-8') {
        LogUtil.d("检测到乱码，尝试 GBK 编码");
        decoded = gbk.decode(_rawBytes!);
        
        if (!_hasGarbledText(decoded)) {
          // GBK 解码成功
          currentEncoding.value = 'GBK';
          detectedEncoding = 'GBK';
          autoDetected = true;
        } else {
          // 如果 GBK 还是乱码，尝试 Latin1
          LogUtil.d("GBK 仍有乱码，尝试 Latin1 编码");
          decoded = latin1.decode(_rawBytes!);
          if (!_hasGarbledText(decoded)) {
            currentEncoding.value = 'Latin1';
            detectedEncoding = 'Latin1';
            autoDetected = true;
          } else {
            // 都不行，还是用 UTF-8
            decoded = utf8.decode(_rawBytes!, allowMalformed: true);
          }
        }
      }
      
      content.value = decoded;
      
      // 如果自动检测到了编码，显示提示
      if (autoDetected) {
        SmartDialog.showToast("已自动切换到 $detectedEncoding 编码");
      }
    } catch (e) {
      LogUtil.e("Decode error: $e");
      content.value = utf8.decode(_rawBytes!, allowMalformed: true);
    }
  }

  // 检测文本中是否有乱码字符
  bool _hasGarbledText(String text) {
    // 检查前 1000 个字符（避免检查整个大文件）
    final sample = text.length > 1000 ? text.substring(0, 1000) : text;
    
    // 统计可疑字符的数量
    int suspiciousCount = 0;
    int totalChars = 0;
    
    for (int i = 0; i < sample.length; i++) {
      final char = sample[i];
      final code = char.codeUnitAt(0);
      
      // 跳过常见的控制字符（换行、制表符等）
      if (code == 0x0A || code == 0x0D || code == 0x09 || code == 0x20) {
        continue;
      }
      
      totalChars++;
      
      // 检测常见的乱码模式
      // 1. Unicode 替换字符 (�)
      if (code == 0xFFFD) {
        suspiciousCount += 3; // 权重更高
      }
      // 2. 控制字符（除了常见的换行、制表符）
      else if (code < 0x20 || (code >= 0x7F && code < 0xA0)) {
        suspiciousCount++;
      }
      // 3. 私有使用区字符
      else if ((code >= 0xE000 && code <= 0xF8FF) ||
               (code >= 0xF0000 && code <= 0xFFFFD) ||
               (code >= 0x100000 && code <= 0x10FFFD)) {
        suspiciousCount++;
      }
    }
    
    // 如果可疑字符超过 5% 或有替换字符，认为是乱码
    if (totalChars > 0) {
      final ratio = suspiciousCount / totalChars;
      return ratio > 0.05 || sample.contains('�');
    }
    
    return false;
  }

  void showEncodingDialog() {
    final encodings = ['UTF-8', 'GBK', 'GB2312', 'Latin1'];
    
    SmartDialog.show(
      builder: (context) => AlertDialog(
        title: const Text('选择编码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: encodings.map((encoding) {
            return RadioListTile<String>(
              title: Text(encoding),
              value: encoding,
              groupValue: currentEncoding.value,
              onChanged: (value) {
                if (value != null) {
                  currentEncoding.value = value;
                  _decodeContent();
                  SmartDialog.dismiss();
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void copyLink() async {
    try {
      final url = await FileUtils.makeFileLink(
        txtItem.remotePath,
        txtItem.sign ?? "",
      );
      if (url != null && url.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: url));
        SmartDialog.showToast(Intl.tips_link_copied.tr);
      }
    } catch (e) {
      SmartDialog.showToast("复制失败");
    }
  }
}

class TxtItem {
  final String name;
  final String remotePath;
  final String? sign;
  final String? provider;
  final String? thumb;

  TxtItem({
    required this.name,
    required this.remotePath,
    this.sign,
    this.provider,
    this.thumb,
  });
}

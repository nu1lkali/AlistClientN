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
      content.value = decoded;
    } catch (e) {
      LogUtil.e("Decode error: $e");
      content.value = utf8.decode(_rawBytes!, allowMalformed: true);
    }
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

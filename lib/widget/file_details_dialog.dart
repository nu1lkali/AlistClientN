import 'dart:async';

import 'package:alist/entity/file_list_resp_entity.dart';
import 'package:alist/l10n/intl_keys.dart';
import 'package:alist/net/dio_utils.dart';
import 'package:alist/util/file_utils.dart';
import 'package:alist/util/image_utils.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class FileDetailsDialog extends StatefulWidget {
  const FileDetailsDialog({
    Key? key,
    required this.name,
    required this.size,
    required this.path,
    required this.modified,
    required this.thumb,
    required this.provider,
    this.isDir = false,
    this.password,
  }) : super(key: key);
  final String name;
  final String? size;
  final String path;
  final String modified;
  final String? thumb;
  final String? provider;
  final bool isDir;
  final String? password;

  @override
  State<FileDetailsDialog> createState() => _FileDetailsDialogState();
}

class _FileDetailsDialogState extends State<FileDetailsDialog> {
  String? _folderItemCount;
  bool _calculating = false;
  int? _calculatedSize;

  @override
  void initState() {
    super.initState();
    if (widget.isDir) _loadFolderInfo();
  }

  void _loadFolderInfo() {
    final body = {
      "path": widget.path,
      "password": widget.password ?? "",
      "page": 1,
      "per_page": 0,
      "refresh": false,
    };
    DioUtils.instance.requestNetwork<FileListRespEntity>(
      Method.post, "fs/list",
      params: body,
      onSuccess: (data) {
        if (!mounted) return;
        setState(() {
          _folderItemCount = "${data?.total ?? 0} 个项目";
        });
      },
      onError: (_, __) {},
    );
  }

  void _calculateSize() {
    if (_calculating) return;
    setState(() => _calculating = true);
    _calcFolderSize(widget.path).then((size) {
      if (!mounted) return;
      setState(() {
        _calculatedSize = size;
        _calculating = false;
      });
    });
  }

  Future<int> _calcFolderSize(String path) async {
    num total = 0;
    final body = {"path": path, "password": widget.password ?? "", "page": 1, "per_page": 0, "refresh": false};
    final completer = Completer<int>();
    DioUtils.instance.requestNetwork<FileListRespEntity>(
      Method.post, "fs/list",
      params: body,
      onSuccess: (data) async {
        for (final f in data?.content ?? []) {
          if (f.isDir) {
            final sub = await _calcFolderSize("$path/${f.name}");
            total = total + sub;
          } else {
            total = total + (f.size ?? 0);
          }
        }
        completer.complete(total.toInt());
      },
      onError: (_, __) => completer.complete(total.toInt()),
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "文件详情",
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 20),
                _buildInfoColumn(),
              ],
            ),
          ),
        ));
  }

  Column _buildInfoColumn() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildInfoRow("${Intl.fileDetailsDialog_name.tr}:", widget.name),
        if (!widget.isDir && widget.size != null && widget.size!.isNotEmpty)
          _buildInfoRow("${Intl.fileDetailsDialog_size.tr}:", widget.size!),
        if (widget.isDir) ...[
          if (_folderItemCount != null)
            _buildInfoRow("包含:", _folderItemCount!),
          _buildSizeRow(),
        ],
        _buildInfoRow("${Intl.fileDetailsDialog_where.tr}:", widget.path),
        _buildInfoRow("${Intl.fileDetailsDialog_modified.tr}:", widget.modified),
        if (widget.provider != null && widget.provider!.isNotEmpty)
          _buildInfoRow("${Intl.fileDetailsDialog_provider.tr}:", widget.provider!),
        if (widget.thumb != null && widget.thumb!.isNotEmpty)
          _buildThumb(widget.thumb!, FileUtils.getFileIcon(false, widget.name))
      ],
    );
  }

  Widget _buildSizeRow() {
    final scheme = Get.theme.colorScheme;
    if (_calculatedSize != null) {
      return _buildInfoRow("${Intl.fileDetailsDialog_size.tr}:", FileUtils.formatBytes(_calculatedSize!) ?? "");
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          alignment: Alignment.centerRight,
          width: 90,
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          child: Text(
            "${Intl.fileDetailsDialog_size.tr}:",
            style: Get.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: _calculating
              ? SizedBox(
                  width: 18, 
                  height: 18, 
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: scheme.primary,
                  ))
              : FilledButton.tonal(
                  onPressed: _calculateSize,
                  style: FilledButton.styleFrom(
                    minimumSize: Size.zero, 
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("计算大小", style: TextStyle(fontSize: 13)),
                ),
        ),
      ],
    );
  }

  Row _buildInfoRow(String text1, String text2) {
    final scheme = Get.theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          alignment: Alignment.centerRight,
          width: 90,
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          child: Text(
            text1,
            style: Get.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.only(left: 12, top: 12, bottom: 12),
            child: Text(
              text2,
              style: Get.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThumb(String thumb, String icon) {
    String thumbnail = FileUtils.getCompleteThumbnail(thumb)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: ExtendedImage(
        image: noProxyImageProvider(thumbnail),
        width: 200,
        height: 100,
        loadStateChanged: (state) {
          if (state.extendedImageLoadState == LoadState.failed) {
            return Image.asset(icon);
          }
          return null;
        },
        beforePaintImage: (canvas, rect, image, paint) {
          if (!rect.isEmpty) {
            canvas.save();
            canvas.clipRRect(
                RRect.fromRectAndRadius(rect, const Radius.circular(4)));
          }
          return false;
        },
      ),
    );
  }
}

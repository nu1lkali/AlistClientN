import 'package:alist/generated/images.dart';
import 'package:alist/util/file_type.dart';
import 'package:alist/util/file_utils.dart';
import 'package:alist/util/global.dart';
import 'package:alist/util/widget_utils.dart';
import 'package:alist/widget/overflow_text.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class FileListItemView extends StatelessWidget {
  const FileListItemView({
    Key? key,
    required this.icon,
    required this.fileName,
    required this.time,
    required this.sizeDesc,
    this.thumbnail,
    required this.onTap,
    this.onMoreIconButtonTap,
    this.fileNameMaxLines,
    this.highlightKeyword,
    this.watchProgress,
  }) : super(key: key);
  final GestureTapCallback onTap;
  final GestureTapCallback? onMoreIconButtonTap;
  final String icon;
  final String? thumbnail;
  final String fileName;
  final String? time;
  final String? sizeDesc;
  final int? fileNameMaxLines;
  final String? highlightKeyword;
  final double? watchProgress;

  @override
  Widget build(BuildContext context) {
    String? thumbnail = FileUtils.getCompleteThumbnail(this.thumbnail);
    bool isDarkMode = WidgetUtils.isDarkMode(context);
    String subtitle = time ?? "";
    if (sizeDesc != null) {
      subtitle = "$subtitle - $sizeDesc";
    }

    return Stack(
      children: [
        ListTile(
          horizontalTitleGap: 6,
          minVerticalPadding: 12,
          leading: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (thumbnail != null && thumbnail.isNotEmpty)
                _buildThumbnailView(icon, thumbnail)
              else
                Image.asset(icon)
            ],
          ),
          trailing: _moreIconButton(isDarkMode),
          title: Obx(() {
            int globalFileNameMaxLines = Global.fileNameMaxLines.value;
            int fileNameMaxLines = this.fileNameMaxLines ?? globalFileNameMaxLines;
            final keyword = highlightKeyword;
            if (keyword != null && keyword.isNotEmpty) {
              return _buildHighlightTitle(fileName, keyword, fileNameMaxLines);
            }
            return fileNameMaxLines == 1
                ? OverflowText(text: fileName)
                : Text(
                    fileName,
                    maxLines: fileNameMaxLines > 2 ? 1000 : 2,
                    overflow: TextOverflow.ellipsis,
                  );
          }),
          subtitle: subtitle.isNotEmpty
              ? Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                )
              : null,
          onTap: onTap,
          onLongPress: null,
        ),
        if (watchProgress != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LinearProgressIndicator(
              value: watchProgress,
              minHeight: 2,
              backgroundColor: Colors.transparent,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF6B35)),
            ),
          ),
      ],
    );
  }

  Widget _buildHighlightTitle(String text, String keyword, int maxLines) {
    final lowerText = text.toLowerCase();
    final lowerKeyword = keyword.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    int idx;
    while ((idx = lowerText.indexOf(lowerKeyword, start)) != -1) {
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + keyword.length),
        style: const TextStyle(
          color: Colors.orange,
          fontWeight: FontWeight.bold,
        ),
      ));
      start = idx + keyword.length;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return RichText(
      maxLines: maxLines > 2 ? 1000 : 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: DefaultTextStyle.of(Get.context!).style,
        children: spans,
      ),
    );
  }

  Widget _moreIconButton(bool isDarkMode) {
    if (onMoreIconButtonTap == null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            Images.iconArrowRight,
            color: isDarkMode ? Colors.white : null,
          )
        ],
      );
    } else {
      return IconButton(
        onPressed: onMoreIconButtonTap,
        icon: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: Get.theme.colorScheme.primaryContainer,
              ),
              width: 24,
              height: 12,
            ),
            const Icon(Icons.more_horiz_rounded),
          ],
        ),
      );
    }
  }

  ClipRRect _buildThumbnailView(String icon, String thumbnail) {
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(4)),
      child: ExtendedImage.network(
        thumbnail,
        fit: BoxFit.cover,
        width: 35,
        height: 35,
        loadStateChanged: (state) {
          if (state.extendedImageLoadState == LoadState.failed) {
            return Image.asset(icon);
          }
          return null;
        },
      ),
    );
  }
}

class FileItemVO {
  String name;
  String path;
  final int? size;
  final String? sizeDesc;
  final bool isDir;
  final String modified;
  final int modifiedMilliseconds;
  final String sign;
  final String thumb;
  String? folderThumb; // lazy-loaded folder cover
  double? watchProgress; // 0.0~1.0, null = not watched
  final int typeInt;
  final FileType type;
  final String icon;
  final String? provider;

  FileItemVO(
      {required this.name,
      required this.path,
      required this.size,
      required this.sizeDesc,
      required this.isDir,
      required this.modified,
      required this.modifiedMilliseconds,
      required this.sign,
      required this.thumb,
      required this.typeInt,
      required this.type,
      required this.icon,
      required this.provider});
}

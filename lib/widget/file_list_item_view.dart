import 'package:alist/generated/images.dart';
import 'package:alist/util/file_type.dart';
import 'package:alist/util/file_utils.dart';
import 'package:alist/util/global.dart';
import 'package:alist/util/widget_utils.dart';
import 'package:alist/widget/overflow_text.dart';
import 'package:alist/util/image_utils.dart';
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
    this.onShufflePlayTap,
    this.showShuffleButton = false,
    this.fileNameMaxLines,
    this.highlightKeyword,
    this.watchProgress,
    this.onLongPress,
  }) : super(key: key);
  final GestureTapCallback onTap;
  final GestureTapCallback? onMoreIconButtonTap;
  final GestureTapCallback? onShufflePlayTap;
  final bool showShuffleButton; // 是否显示shuffle按钮（非文件夹时显示但禁用）
  final GestureTapCallback? onLongPress;
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
    final scheme = Theme.of(context).colorScheme;
    String subtitle = time ?? "";
    if (sizeDesc != null) {
      subtitle = "$subtitle - $sizeDesc";
    }

    return Stack(
      children: [
        ListTile(
          horizontalTitleGap: 10,
          minVerticalPadding: 14,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          leading: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (thumbnail != null && thumbnail.isNotEmpty)
                _buildThumbnailView(icon, thumbnail)
              else
                Container(
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.surfaceVariant.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Image.asset(icon),
                )
            ],
          ),
          trailing: _trailingWidget(isDarkMode, scheme),
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
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.2,
                    ),
                  );
          }),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13),
                  ),
                ),
              if (watchProgress != null) ...[
                const SizedBox(height: 6),
                FractionallySizedBox(
                  widthFactor: 0.55,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: watchProgress,
                      minHeight: 4,
                      backgroundColor: scheme.surfaceVariant.withOpacity(0.5),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        scheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          onTap: onTap,
          onLongPress: onLongPress,
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

  Widget _trailingWidget(bool isDarkMode, ColorScheme scheme) {
    // 只有传了 showShuffleButton=true 才显示 shuffle 按钮
    if (!showShuffleButton) {
      return _moreIconButton(isDarkMode, scheme);
    }

    final shuffleEnabled = onShufflePlayTap != null;
    final shuffleBtn = IconButton(
      onPressed: onShufflePlayTap,
      tooltip: shuffleEnabled ? "随机播放" : null,
      icon: Opacity(
        opacity: shuffleEnabled ? 1.0 : 0.25,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withOpacity(shuffleEnabled ? 0.6 : 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.shuffle_rounded,
            size: 16,
            color: scheme.primary,
          ),
        ),
      ),
    );

    if (onMoreIconButtonTap == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          shuffleBtn,
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chevron_right_rounded,
                  color: scheme.outlineVariant, size: 20)
            ],
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        shuffleBtn,
        _moreIconButton(isDarkMode, scheme),
      ],
    );
  }

  Widget _moreIconButton(bool isDarkMode, ColorScheme scheme) {
    if (onMoreIconButtonTap == null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chevron_right_rounded,
            color: scheme.outlineVariant,
            size: 20,
          )
        ],
      );
    } else {
      return IconButton(
        onPressed: onMoreIconButtonTap,
        icon: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withOpacity(0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.more_horiz_rounded,
            size: 18,
            color: scheme.primary,
          ),
        ),
      );
    }
  }

  ClipRRect _buildThumbnailView(String icon, String thumbnail) {
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      child: ExtendedImage(
        image: noProxyImageProvider(thumbnail),
        fit: BoxFit.cover,
        width: 40,
        height: 40,
        loadStateChanged: (state) {
          if (state.extendedImageLoadState == LoadState.failed) {
            return Container(
              width: 40,
              height: 40,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Get.theme.colorScheme.surfaceVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.asset(icon),
            );
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
  String? localThumb; // 本地生成的视频缩略图路径
  int? videoCurrentPosition; // 上次播放位置（毫秒）
  int? videoDuration; // 视频总时长（毫秒）
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

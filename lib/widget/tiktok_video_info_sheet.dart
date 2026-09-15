import 'package:alist/entity/tiktok_play_list_model.dart';
import 'package:flutter/material.dart';

/// 「视界流」播放器的视频信息面板内容（`showModalBottomSheet` 弹出的底部框）。
///
/// 背景色 / 圆角 / 高度上限由弹出方（[TiktokVideoInfoSheet] 的调用处）设置，
/// 这里只负责渲染内容。
///
/// 横屏时屏幕高度通常只有 ~360dp，扣掉系统安全区后更少，单列平铺很容易超出
/// 可视区域，看起来像「内容显示不全」；因此宽屏（宽 > 高）下改成两列紧凑布局，
/// 长条目（文件路径 / 文件签名）独占一行，保证一屏内能看全所有信息。
/// 超长路径或更小的屏幕仍保留滚动兜底。
class TiktokVideoInfoSheet extends StatefulWidget {
  const TiktokVideoInfoSheet({
    Key? key,
    required this.video,
    required this.fromEmby,
    required this.position,
  }) : super(key: key);

  /// 当前正在播放的视频项。
  final TikTokVideoItem video;

  /// 是否来自 Emby 随机播放（决定文件路径的取值与是否显示「修改时间」）。
  final bool fromEmby;

  /// 播放位置文本，形如 `3 / 12`。
  final String position;

  @override
  State<TiktokVideoInfoSheet> createState() => _TiktokVideoInfoSheetState();
}

class _TiktokVideoInfoSheetState extends State<TiktokVideoInfoSheet> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.of(context).size;
    // 横屏 / 平板等宽屏：两列紧凑布局；竖屏：单列
    final bool wide = screen.width > screen.height;

    return SafeArea(
      child: Scrollbar(
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(20, wide ? 12 : 20, 20, wide ? 12 : 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white30,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(height: wide ? 10 : 16),
              const Text(
                '视频信息',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              SizedBox(height: wide ? 6 : 12),
              ..._buildRows(wide: wide),
            ],
          ),
        ),
      ),
    );
  }

  /// 信息条目，顺序与竖屏单列布局一致。
  List<_InfoEntry> _entries() {
    final v = widget.video;
    return [
      _InfoEntry('文件名', v.fileName, fullWidth: true),
      _InfoEntry('文件大小', v.formattedSize),
      // Emby 直链来源：文件路径展示播放直链 URL（切换视频自动跟随当前项）
      _InfoEntry(
        '文件路径',
        widget.fromEmby ? (v.videoUrl ?? v.filePath) : v.filePath,
        fullWidth: true,
      ),
      if (!widget.fromEmby) _InfoEntry('修改时间', v.formattedModified),
      _InfoEntry('Provider', v.provider ?? '未知'),
      _InfoEntry('文件签名', v.sign ?? '无', fullWidth: true),
      _InfoEntry('播放位置', widget.position),
    ];
  }

  List<Widget> _buildRows({required bool wide}) {
    final List<_InfoEntry> entries = _entries();
    if (!wide) {
      return entries.map((e) => _row(e.label, e.value)).toList();
    }
    // 宽屏两列：全宽条目独占一行，其余条目两两成对；落单的按整行渲染
    final List<Widget> rows = [];
    List<_InfoEntry> pair = [];
    void flushPair() {
      if (pair.isEmpty) return;
      if (pair.length == 1) {
        rows.add(_row(pair[0].label, pair[0].value, dense: true));
      } else {
        rows.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _row(pair[0].label, pair[0].value, dense: true)),
            Expanded(child: _row(pair[1].label, pair[1].value, dense: true)),
          ],
        ));
      }
      pair = [];
    }

    for (final _InfoEntry e in entries) {
      if (e.fullWidth) {
        flushPair();
        rows.add(_row(e.label, e.value, dense: true));
      } else {
        pair.add(e);
        if (pair.length == 2) flushPair();
      }
    }
    flushPair();
    return rows;
  }

  Widget _row(String label, String value, {bool dense = false}) => Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? 4 : 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: dense ? 72 : 80,
              child: Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      );
}

/// 信息面板里的一条信息。
class _InfoEntry {
  const _InfoEntry(this.label, this.value, {this.fullWidth = false});

  final String label;
  final String value;

  /// 宽屏两列布局下是否独占一行（内容可能很长的条目）。
  final bool fullWidth;
}

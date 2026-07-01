import 'package:alist/util/lyrics_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// 风格 B：时间轴数据流滚动风格（新风格）
///
/// 视觉特征：
/// - 歌词文本左对齐（非对称排版）
/// - 左侧常驻轻量时间戳列（如 01:23），强化时间轴数据感
/// - 当前播放行带有淡色圆角矩形背景遮罩（scheme.primaryContainer 低透明度）
///
/// 交互：
/// - 手动滚动时触发 HapticFeedback.lightImpact() 震动反馈
/// - 滚动锁定后，底部居中显示 ActionChip 提示条（"已暂停跟踪 - 点击恢复"）
/// - 非拖拽状态：轻触非高亮行或空白区域 → 回调 [onTapReturn] 返回封面
class TimelineLyricsView extends StatefulWidget {
  final LyricsController controller;
  final ColorScheme scheme;

  /// 点击非高亮区域返回封面的回调（仅在非拖拽状态下触发）
  final VoidCallback? onTapReturn;

  /// 每行歌词的高度
  final double itemExtent;

  const TimelineLyricsView({
    super.key,
    required this.controller,
    required this.scheme,
    this.onTapReturn,
    this.itemExtent = 52.0,
  });

  @override
  State<TimelineLyricsView> createState() => _TimelineLyricsViewState();
}

class _TimelineLyricsViewState extends State<TimelineLyricsView> {
  double _viewportHeight = 0;

  /// 上一次用户滚动触发震动的行索引（防抖）
  int _lastHapticIndex = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.itemExtent = widget.itemExtent;
    widget.controller.setLyricsVisible(true);
  }

  @override
  void dispose() {
    widget.controller.setLyricsVisible(false);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TimelineLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.controller.itemExtent = widget.itemExtent;
  }

  /// 根据滚动偏移量计算视口中央对应的歌词行索引
  int _centeredLineIndex(double scrollOffset) {
    if (widget.itemExtent <= 0) return 0;
    return (scrollOffset / widget.itemExtent)
        .round()
        .clamp(0, widget.controller.lyrics.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportHeight = constraints.maxHeight;
        return _buildBody();
      },
    );
  }

  Widget _buildBody() {
    return Stack(
      children: [
        // 歌词滚动列表
        _buildLyricsList(),

        // 拖拽锁定时的底部 ActionChip 提示条
        Obx(() {
          if (!widget.controller.isDragging.value) {
            return const SizedBox.shrink();
          }
          return Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: _buildTrackingChip(),
          );
        }),
      ],
    );
  }

  /// 构建带时间轴风格的歌词列表
  Widget _buildLyricsList() {
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          // 仅在非拖拽状态下，轻触非高亮行或空白区域才返回封面
          if (!widget.controller.isDragging.value) {
            widget.onTapReturn?.call();
          }
        },
        child: Obx(() {
          final state = widget.controller.loadState.value;
          switch (state) {
            case LyricsLoadState.loading:
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            case LyricsLoadState.noLyrics:
              return _buildPlaceholder('暂无歌词');
            case LyricsLoadState.error:
              return _buildPlaceholder(
                widget.controller.errorMessage.value.isNotEmpty
                    ? '歌词加载失败'
                    : '暂无歌词',
              );
            case LyricsLoadState.success:
              if (widget.controller.lyrics.isEmpty) {
                return _buildPlaceholder('暂无歌词');
              }
              return _buildSuccessList();
          }
        }),
      ),
    );
  }

  /// 构建成功状态下的时间轴歌词列表
  Widget _buildSuccessList() {
    return ListView.builder(
      controller: widget.controller.lyricsScrollController,
      itemCount: widget.controller.lyrics.length,
      padding: EdgeInsets.symmetric(
        vertical: _viewportHeight / 2 - widget.itemExtent / 2,
      ),
      itemExtent: widget.itemExtent,
      physics: const BouncingScrollPhysics(),
      itemBuilder: (context, index) {
        return Obx(() {
          final isActive =
              index == widget.controller.displayLineIndex;
          final line = widget.controller.lyrics[index];
          return _TimelineLyricRow(
            content: line.content,
            startTime: line.startTime,
            isActive: isActive,
            scheme: widget.scheme,
            itemExtent: widget.itemExtent,
          );
        });
      },
    );
  }

  /// 占位提示
  Widget _buildPlaceholder(String message) {
    return Center(
      child: Text(
        message,
        style: TextStyle(
          fontSize: 14,
          color: widget.scheme.onSurfaceVariant.withOpacity(0.6),
        ),
      ),
    );
  }

  /// 用户是否正在手动滚动
  bool _isUserScrolling = false;

  /// 处理滚动通知：区分用户手势与程序化滚动，触发震动反馈
  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification) {
      if (notification.direction != ScrollDirection.idle) {
        _isUserScrolling = true;
        final idx = _centeredLineIndex(notification.metrics.pixels);
        widget.controller.onUserScroll(idx);

        // 震动反馈（防抖：仅当行索引变化时触发）
        if (idx != _lastHapticIndex) {
          _lastHapticIndex = idx;
          HapticFeedback.lightImpact();
        }
      } else if (notification.direction == ScrollDirection.idle) {
        if (_isUserScrolling) {
          _isUserScrolling = false;
          _lastHapticIndex = -1;
          widget.controller.onUserScrollEnd();
        }
      }
    }
    // 持续拖动期间实时更新居中行索引
    if (_isUserScrolling && notification is ScrollUpdateNotification) {
      final idx = _centeredLineIndex(notification.metrics.pixels);
      widget.controller.onUserScroll(idx);
    }
    return false;
  }

  /// 拖拽锁定时的底部 ActionChip 提示条
  Widget _buildTrackingChip() {
    return Center(
      child: ActionChip(
        avatar: Icon(
          Icons.sync_disabled_rounded,
          size: 18,
          color: widget.scheme.onSecondaryContainer,
        ),
        label: Text(
          '已暂停跟踪 - 点击恢复',
          style: TextStyle(
            fontSize: 13,
            color: widget.scheme.onSecondaryContainer,
          ),
        ),
        backgroundColor:
            widget.scheme.secondaryContainer.withOpacity(0.9),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        onPressed: () => widget.controller.returnToCurrent(),
      ),
    );
  }
}

/// Style B 的单行歌词组件（独立 Widget，局部刷新）
class _TimelineLyricRow extends StatelessWidget {
  final String content;
  final Duration startTime;
  final bool isActive;
  final ColorScheme scheme;
  final double itemExtent;

  const _TimelineLyricRow({
    required this.content,
    required this.startTime,
    required this.isActive,
    required this.scheme,
    required this.itemExtent,
  });

  /// 将 Duration 格式化为 mm:ss
  String _formatTimestamp(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final ts = _formatTimestamp(startTime);

    // 当前行的高亮背景
    final Widget rowContent = Row(
      children: [
        // 左侧时间戳列
        SizedBox(
          width: 52,
          child: Text(
            ts,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w300,
              color: isActive
                  ? scheme.primary
                  : scheme.onSurfaceVariant.withOpacity(0.3),
            ),
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 12),
        // 歌词文本
        Expanded(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              fontSize: isActive ? 16 : 14,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              color: isActive
                  ? scheme.onSurface
                  : scheme.onSurfaceVariant.withOpacity(0.45),
              height: 1.4,
            ),
            child: Text(
              content.isEmpty ? '♫' : content,
              maxLines: isActive ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.start,
            ),
          ),
        ),
        const SizedBox(width: 16),
      ],
    );

    // 当前行带圆角矩形背景遮罩
    if (isActive) {
      return Container(
        height: itemExtent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: rowContent,
      );
    }

    return Container(
      height: itemExtent,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: rowContent,
    );
  }
}

import 'package:alist/util/lyrics_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';

/// 风格 A：现代流线型滚动风格（黑胶风格）
///
/// 视觉特征：
/// - 歌词文本完全居中对齐
/// - 当前行放大、加粗高亮（使用 scheme.primary），非当前行渐隐为次要颜色
/// - 顶部和底部使用 ShaderMask 实现渐隐边缘（Fading Edge）效果
/// - 手动滚动锁定后，右下角淡入半透明小悬浮按钮（FAB），点击解锁并复位
///
/// 交互：
/// - 非拖拽状态：轻触非高亮行或空白区域 → 回调 [onTapReturn] 返回封面
/// - 拖拽状态：轻触空白区不会误触发返回，仅 FAB 可解锁
class StreamlinedLyricsView extends StatefulWidget {
  final LyricsController controller;
  final ColorScheme scheme;

  /// 点击非高亮区域返回封面的回调（仅在非拖拽状态下触发）
  final VoidCallback? onTapReturn;

  /// 每行歌词的高度
  final double itemExtent;

  const StreamlinedLyricsView({
    super.key,
    required this.controller,
    required this.scheme,
    this.onTapReturn,
    this.itemExtent = 64.0,
  });

  @override
  State<StreamlinedLyricsView> createState() => _StreamlinedLyricsViewState();
}

class _StreamlinedLyricsViewState extends State<StreamlinedLyricsView> {
  /// 视口高度（LayoutBuilder 提供）
  double _viewportHeight = 0;

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
  void didUpdateWidget(covariant StreamlinedLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.controller.itemExtent = widget.itemExtent;
  }

  /// 根据当前滚动偏移量计算视口中央对应的歌词行索引
  int _centeredLineIndex(double scrollOffset) {
    if (_viewportHeight <= 0 || widget.itemExtent <= 0) return 0;
    final center = scrollOffset + _viewportHeight / 2;
    return (center / widget.itemExtent).floor().clamp(
          0,
          widget.controller.lyrics.length - 1,
        );
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

        // 拖拽锁定时的返回悬浮按钮
        Obx(() {
          if (!widget.controller.isDragging.value) {
            return const SizedBox.shrink();
          }
          return Positioned(
            right: 16,
            bottom: 16,
            child: _buildReturnFAB(),
          );
        }),
      ],
    );
  }

  /// 构建带渐隐边缘的歌词滚动列表
  Widget _buildLyricsList() {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: const [0.0, 0.12, 0.88, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: NotificationListener<ScrollNotification>(
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
      ),
    );
  }

  /// 构建成功状态下的歌词列表
  Widget _buildSuccessList() {
    return ListView.builder(
      controller: widget.controller.lyricsScrollController,
      itemCount: widget.controller.lyrics.length,
      // 顶部与底部留白，使首尾行也能滚动到视口中央
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
          return _LyricRowStreamlined(
            content: line.content,
            isActive: isActive,
            scheme: widget.scheme,
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

  /// 用户是否正在手动滚动（区分手势滚动与程序化 animateTo 滚动）
  bool _isUserScrolling = false;

  /// 处理滚动通知：精准区分用户手势滚动与程序化滚动
  bool _handleScrollNotification(ScrollNotification notification) {
    // UserScrollNotification 仅由用户手势触发（方向变更/停止）
    if (notification is UserScrollNotification) {
      if (notification.direction != ScrollDirection.idle) {
        _isUserScrolling = true;
        final idx = _centeredLineIndex(notification.metrics.pixels);
        widget.controller.onUserScroll(idx);
      } else if (notification.direction == ScrollDirection.idle) {
        if (_isUserScrolling) {
          _isUserScrolling = false;
          widget.controller.onUserScrollEnd();
        }
      }
    }
    // 持续拖动期间，通过 ScrollUpdateNotification 实时更新居中行索引
    if (_isUserScrolling && notification is ScrollUpdateNotification) {
      final idx = _centeredLineIndex(notification.metrics.pixels);
      widget.controller.onUserScroll(idx);
    }
    return false;
  }

  /// 拖拽锁定时的半透明悬浮返回按钮
  Widget _buildReturnFAB() {
    return AnimatedOpacity(
      opacity: widget.controller.isDragging.value ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      child: FloatingActionButton.small(
        backgroundColor: widget.scheme.primary.withOpacity(0.75),
        onPressed: () => widget.controller.returnToCurrent(),
        child: Icon(
          Icons.my_location_rounded,
          color: widget.scheme.onPrimary,
          size: 20,
        ),
      ),
    );
  }
}

/// Style A 的单行歌词组件（独立 Widget 保证局部刷新，避免无关行重绘）
class _LyricRowStreamlined extends StatelessWidget {
  final String content;
  final bool isActive;
  final ColorScheme scheme;

  const _LyricRowStreamlined({
    required this.content,
    required this.isActive,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      style: TextStyle(
        fontSize: isActive ? 20 : 15,
        fontWeight: isActive ? FontWeight.bold : FontWeight.w400,
        color: isActive
            ? scheme.primary
            : scheme.onSurfaceVariant.withOpacity(0.4),
        height: 1.4,
      ),
      child: Center(
        child: Text(
          content.isEmpty ? '♫' : content,
          maxLines: isActive ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}



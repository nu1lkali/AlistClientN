import 'package:alist/entity/lyric_line.dart';
import 'package:alist/util/lyrics_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// LRC 歌词调试页面
///
/// 从设置页进入，用于排查歌词加载问题。
/// 显示完整的加载流程日志、当前状态、支持手动触发重新加载。
class LrcDebugScreen extends StatelessWidget {
  const LrcDebugScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('LRC 歌词调试'),
        actions: [
          // 清空日志
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: '清空日志',
            onPressed: () => LyricsController.clearDebugLogs(),
          ),
          // 复制全部日志
          IconButton(
            icon: const Icon(Icons.copy_all),
            tooltip: '复制全部日志',
            onPressed: () {
              final allLogs = LyricsController.debugLogs.join('\n');
              Clipboard.setData(ClipboardData(text: allLogs));
              final count = LyricsController.debugLogs.length;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已复制 $count 条日志')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 状态摘要区 ──
          _buildStatusSection(context, scheme),
          const Divider(height: 1),

          // ── 操作区 ──
          _buildActionSection(context, scheme),
          const Divider(height: 1),

          // ── 日志区 ──
          Expanded(child: _buildLogSection(context, scheme)),
        ],
      ),
    );
  }

  /// 状态摘要
  Widget _buildStatusSection(BuildContext context, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: scheme.surfaceVariant.withOpacity(0.3),
      child: Obx(() {
        // 尝试获取当前 LyricsController（可能不存在）
        LyricsController? ctrl;
        try {
          ctrl = Get.find<LyricsController>();
        } catch (_) {}

        final stateStr = ctrl != null
            ? ctrl.loadState.value.name
            : '(no controller)';
        final lyricsCount = ctrl?.lyrics.length ?? 0;
        final lineIdx = ctrl?.currentLineIndex.value ?? -1;
        final isDragging = ctrl?.isDragging.value ?? false;
        final cacheDir = ctrl?.cacheDirPath ?? '(未初始化)';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _badge(stateStr, _stateColor(stateStr, scheme)),
                const SizedBox(width: 8),
                Text('歌词行数: $lyricsCount',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(width: 12),
                Text('当前行: $lineIdx',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(width: 12),
                Text('拖拽: $isDragging',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 6),
            Text('缓存目录: $cacheDir',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            // 最近一次 fetch 详情
            Obx(() {
              final info = LyricsController.lastFetchInfo;
              if (info.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: info.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '${e.key}: ${e.value}',
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                    maxLines: 3, overflow: TextOverflow.ellipsis,
                  ),
                )).toList(),
              );
            }),
            // 日志版本号（用于确认 Obx 工作）
            Obx(() {
              final ver = LyricsController.debugLogVersion.value;
              return Text('日志条数: ${LyricsController.debugLogs.length} (ver:$ver)',
                  style: TextStyle(fontSize: 10, color: scheme.outline));
            }),
          ],
        );
      }),
    );
  }

  Color _stateColor(String state, ColorScheme scheme) {
    switch (state) {
      case 'loading':
        return Colors.orange;
      case 'success':
        return Colors.green;
      case 'noLyrics':
        return Colors.red;
      case 'error':
        return Colors.red;
      default:
        return scheme.outline;
    }
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
    );
  }

  /// 操作按钮
  Widget _buildActionSection(BuildContext context, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重新加载歌词'),
              onPressed: () {
                try {
                  final ctrl = Get.find<LyricsController>();
                  // 尝试从 AudioPlayerScreenController 获取当前音频信息
                  // 注意：这些 controller 可能与调试页不在同一导航栈
                  LyricsController.addLog('=== 调试页手动触发重新加载 ===');
                  // 重置并重新触发
                  ctrl.loadState.value = LyricsLoadState.loading;
                  ctrl.lyrics.clear();
                  ctrl.currentLineIndex.value = -1;
                  // 无法获取音频路径时，提示用户
                  LyricsController.addLog('提示: 请返回播放器页面，切歌后再切回来触发加载');
                  LyricsController.addLog('或者在播放器中点击封面切换到歌词视图');
                } catch (e) {
                  LyricsController.addLog('错误: 无法获取 LyricsController: $e');
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.cleaning_services_outlined, size: 18),
            label: const Text('清空缓存'),
            onPressed: () {
              LyricsController.clearDebugLogs();
              LyricsController.lastFetchInfo.clear();
            },
          ),
        ],
      ),
    );
  }

  /// 日志列表
  Widget _buildLogSection(BuildContext context, ColorScheme scheme) {
    return Obx(() {
      // 读取 version 确保每次新增日志都触发刷新
      final ver = LyricsController.debugLogVersion.value;
      final logs = LyricsController.debugLogs.toList();

      if (logs.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_empty, size: 48, color: scheme.outline),
              const SizedBox(height: 8),
              Text('暂无日志', style: TextStyle(color: scheme.outline)),
              const SizedBox(height: 4),
              Text('打开播放器并切换到歌词视图以生成日志',
                  style: TextStyle(fontSize: 12, color: scheme.outline)),
            ],
          ),
        );
      }

      // 自动滚动到底部
      // 注意：不使用 ScrollController 因为日志可能很多
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: logs.length,
        itemBuilder: (context, index) {
          final log = logs[index];
          // 根据日志内容着色
          Color? color;
          if (log.contains('✅')) {
            color = Colors.green;
          } else if (log.contains('❌') || log.contains('失败') || log.contains('错误')) {
            color = Colors.red;
          } else if (log.contains('=====')) {
            color = scheme.primary;
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Text(
              log,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: color ?? scheme.onSurface,
                height: 1.5,
              ),
            ),
          );
        },
      );
    });
  }
}



import 'package:flutter/material.dart';

/// Emby 表单底部弹窗骨架（服务器 / 媒体库编辑共用）。
///
/// 设计要点（解决“键盘挤压 AlertDialog 变形”问题）：
/// - 通过 [MediaQuery.viewInsets] 让整个表单随键盘上移，而不是被压缩变形；
/// - 内容区可滚动（高度取“屏幕高 − 键盘高度”为上界），永不溢出；
/// - 顶部圆角 + 拖拽把手，底部操作区固定，输入时按钮始终可见；
/// - 使用方式：`showModalBottomSheet(isScrollControlled: true, backgroundColor: Colors.transparent)`
///   承载本组件，`Navigator.pop(...)` 的返回值即表单结果。
Widget buildEmbyFormSheet(
  BuildContext context, {
  required IconData icon,
  required String title,
  required List<Widget> children,
  required Widget footer,
}) {
  final scheme = Theme.of(context).colorScheme;
  final insets = MediaQuery.of(context).viewInsets;
  // 键盘弹出后可用高度：屏幕高 − 键盘高度 − 安全余量
  final maxHeight =
      (MediaQuery.of(context).size.height - insets.bottom - 24)
          .clamp(240.0, double.infinity);

  return Padding(
    padding: EdgeInsets.only(bottom: insets.bottom),
    child: Material(
      color: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            // 拖拽把手
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 0),
              child: Row(
                children: [
                  Icon(icon, color: scheme.primary, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // 可滚动表单区
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
              ),
            ),
            // 固定底部操作区
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: SafeArea(top: false, child: footer),
            ),
          ],
        ),
      ),
    ),
  );
}

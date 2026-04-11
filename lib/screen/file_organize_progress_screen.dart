import 'package:alist/util/file_organize_task.dart';
import 'package:alist/util/file_organize_executor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class FileOrganizeProgressScreen extends StatefulWidget {
  final FileOrganizeBatch batch;
  final String? password;
  final VoidCallback onComplete;
  
  const FileOrganizeProgressScreen({
    Key? key,
    required this.batch,
    this.password,
    required this.onComplete,
  }) : super(key: key);

  @override
  State<FileOrganizeProgressScreen> createState() => _FileOrganizeProgressScreenState();
}

class _FileOrganizeProgressScreenState extends State<FileOrganizeProgressScreen> {
  late FileOrganizeExecutor _executor;
  bool _isExecuting = false;
  bool _showFailedOnly = false;
  
  @override
  void initState() {
    super.initState();
    _executor = FileOrganizeExecutor(password: widget.password);
    _startExecution();
  }
  
  Future<void> _startExecution() async {
    if (_isExecuting) return;
    
    setState(() => _isExecuting = true);
    
    for (final task in widget.batch.tasks) {
      if (task.status == FileOrganizeTaskStatus.pending) {
        await _executor.executeTask(task);
        setState(() {}); // 更新UI
        
        // 短暂延迟，避免请求过快
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    
    widget.batch.endTime = DateTime.now();
    setState(() => _isExecuting = false);
  }
  
  Future<void> _retryFailed() async {
    final retryableTasks = widget.batch.retryableTasks;
    if (retryableTasks.isEmpty) {
      SmartDialog.showToast('没有可重试的任务');
      return;
    }
    
    for (final task in retryableTasks) {
      task.status = FileOrganizeTaskStatus.pending;
      task.retryCount++;
    }
    
    await _startExecution();
  }
  
  @override
  Widget build(BuildContext context) {
    final displayTasks = _showFailedOnly 
        ? widget.batch.failedTasks 
        : widget.batch.tasks;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('文件整理进度'),
        actions: [
          if (widget.batch.failedCount > 0)
            IconButton(
              icon: Icon(_showFailedOnly ? Icons.list : Icons.error_outline),
              tooltip: _showFailedOnly ? '显示全部' : '只看失败',
              onPressed: () {
                setState(() => _showFailedOnly = !_showFailedOnly);
              },
            ),
        ],
      ),
      body: Column(
        children: [
          _buildProgressCard(),
          Expanded(
            child: ListView.builder(
              itemCount: displayTasks.length,
              itemBuilder: (context, index) {
                return _buildTaskItem(displayTasks[index]);
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }
  
  Widget _buildProgressCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '总进度',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Text(
                  '${(widget.batch.progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: widget.batch.progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('总数', widget.batch.totalCount, Colors.blue),
                _buildStatItem('成功', widget.batch.successCount, Colors.green),
                _buildStatItem('失败', widget.batch.failedCount, Colors.red),
                if (widget.batch.skippedCount > 0)
                  _buildStatItem('跳过', widget.batch.skippedCount, Colors.orange),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
  
  Widget _buildTaskItem(FileOrganizeTask task) {
    Color statusColor;
    IconData statusIcon;
    
    switch (task.status) {
      case FileOrganizeTaskStatus.success:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case FileOrganizeTaskStatus.failed:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      case FileOrganizeTaskStatus.processing:
        statusColor = Colors.blue;
        statusIcon = Icons.sync;
        break;
      case FileOrganizeTaskStatus.skipped:
        statusColor = Colors.orange;
        statusIcon = Icons.skip_next;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.pending;
    }
    
    return ListTile(
      leading: Icon(statusIcon, color: statusColor),
      title: Text(
        task.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: task.status == FileOrganizeTaskStatus.failed
          ? Text(
              '${task.errorTypeText}: ${task.errorMessage ?? ""}',
              style: const TextStyle(color: Colors.red, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : Text(
              '${task.category} → ${task.targetPath}',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: Text(
        task.statusText,
        style: TextStyle(color: statusColor, fontSize: 12),
      ),
    );
  }
  
  Widget _buildBottomBar() {
    if (!widget.batch.isCompleted) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('正在整理文件...'),
          ],
        ),
      );
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          if (widget.batch.retryableTasks.isNotEmpty)
            Expanded(
              child: FilledButton.tonal(
                onPressed: _isExecuting ? null : _retryFailed,
                child: Text('重试失败项 (${widget.batch.retryableTasks.length})'),
              ),
            ),
          if (widget.batch.retryableTasks.isNotEmpty)
            const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: () {
                widget.onComplete();
                Get.back();
              },
              child: const Text('完成'),
            ),
          ),
        ],
      ),
    );
  }
}

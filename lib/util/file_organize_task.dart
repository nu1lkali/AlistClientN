/// 文件整理任务状态
enum FileOrganizeTaskStatus {
  pending,    // 等待执行
  processing, // 执行中
  success,    // 成功
  failed,     // 失败
  skipped,    // 跳过（如文件被占用）
}

/// 文件整理任务错误类型
enum FileOrganizeErrorType {
  fileOccupied,    // 文件被占用
  permissionDenied, // 权限不足
  networkError,     // 网络错误
  invalidFileName,  // 文件名非法
  targetExists,     // 目标已存在
  unknown,          // 未知错误
}

/// 单个文件的整理任务
class FileOrganizeTask {
  final String fileName;
  final String sourcePath;
  final String targetPath;
  final String category; // 类型分类（图片、视频等）
  
  FileOrganizeTaskStatus status;
  FileOrganizeErrorType? errorType;
  String? errorMessage;
  int retryCount;
  
  FileOrganizeTask({
    required this.fileName,
    required this.sourcePath,
    required this.targetPath,
    required this.category,
    this.status = FileOrganizeTaskStatus.pending,
    this.errorType,
    this.errorMessage,
    this.retryCount = 0,
  });
  
  bool get canRetry => status == FileOrganizeTaskStatus.failed && 
                       retryCount < 3 && 
                       errorType != FileOrganizeErrorType.fileOccupied;
  
  String get statusText {
    switch (status) {
      case FileOrganizeTaskStatus.pending:
        return '等待中';
      case FileOrganizeTaskStatus.processing:
        return '处理中';
      case FileOrganizeTaskStatus.success:
        return '成功';
      case FileOrganizeTaskStatus.failed:
        return '失败';
      case FileOrganizeTaskStatus.skipped:
        return '跳过';
    }
  }
  
  String get errorTypeText {
    if (errorType == null) return '';
    switch (errorType!) {
      case FileOrganizeErrorType.fileOccupied:
        return '文件被占用';
      case FileOrganizeErrorType.permissionDenied:
        return '权限不足';
      case FileOrganizeErrorType.networkError:
        return '网络错误';
      case FileOrganizeErrorType.invalidFileName:
        return '文件名非法';
      case FileOrganizeErrorType.targetExists:
        return '目标已存在';
      case FileOrganizeErrorType.unknown:
        return '未知错误';
    }
  }
}

/// 整理任务批次
class FileOrganizeBatch {
  final String batchId;
  final String operation; // 'organize' 或 'extract_organize'
  final List<FileOrganizeTask> tasks;
  final DateTime startTime;
  DateTime? endTime;
  
  FileOrganizeBatch({
    required this.batchId,
    required this.operation,
    required this.tasks,
    DateTime? startTime,
    this.endTime,
  }) : startTime = startTime ?? DateTime.now();
  
  int get totalCount => tasks.length;
  int get successCount => tasks.where((t) => t.status == FileOrganizeTaskStatus.success).length;
  int get failedCount => tasks.where((t) => t.status == FileOrganizeTaskStatus.failed).length;
  int get skippedCount => tasks.where((t) => t.status == FileOrganizeTaskStatus.skipped).length;
  int get pendingCount => tasks.where((t) => t.status == FileOrganizeTaskStatus.pending).length;
  
  double get progress => totalCount > 0 ? (successCount + failedCount + skippedCount) / totalCount : 0.0;
  
  bool get isCompleted => pendingCount == 0 && tasks.every((t) => t.status != FileOrganizeTaskStatus.processing);
  
  List<FileOrganizeTask> get failedTasks => tasks.where((t) => t.status == FileOrganizeTaskStatus.failed).toList();
  
  List<FileOrganizeTask> get retryableTasks => failedTasks.where((t) => t.canRetry).toList();
}
